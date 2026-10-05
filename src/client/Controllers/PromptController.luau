-- PromptController: liga/desliga localmente os ProximityPrompts conforme o estado do jogador,
-- para só aparecer o que faz sentido agora (o servidor valida tudo de novo).

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Strings = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Strings"))
local Config = require(ReplicatedStorage.Shared:WaitForChild("Config"))

local player = Players.LocalPlayer

local Prompts = {}

local function kitchenOf(prompt: Instance): Model?
	local m = prompt:FindFirstAncestorWhichIsA("Model")
	while m and m:GetAttribute("KitchenIndex") == nil do
		m = m:FindFirstAncestorWhichIsA("Model")
	end
	return m
end

-- O jogador está entre as paredes desta cozinha? (o alcance dos prompts passava pela parede)
local function insideKitchen(K: Model): boolean
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local floor = K:FindFirstChild("Floor") :: BasePart?
	if not hrp or not floor then
		return false
	end
	local p = floor.CFrame:PointToObjectSpace(hrp.Position)
	return math.abs(p.X) < floor.Size.X / 2 and math.abs(p.Z) < floor.Size.Z / 2 and p.Y > -3 and p.Y < 12
end

local function evaluate(prompt: ProximityPrompt)
	local K = kitchenOf(prompt)
	local mine = K ~= nil and K:GetAttribute("KitchenIndex") == player:GetAttribute("KitchenIndex")
	local state = player:GetAttribute("State")
	local kind = prompt:GetAttribute("Kind")
	local on = false
	if mine and K and insideKitchen(K) then
		local hands = player:GetAttribute("Hands") or 1
		local freeHand = state == "Holding" and hands >= 2 and player:GetAttribute("ExtraHeld") == nil
		if kind == "Pile" then
			local stock, stockMax = player:GetAttribute("Stock") or 0, player:GetAttribute("StockMax") or 0
			local canFill = stockMax > 0 and stock < stockMax
			on = state == "Free" or freeHand or (state == "Holding" and canFill)
			local wanted = if canFill then Strings.FillCart else Strings.TakePotato
			if prompt.ActionText ~= wanted then
				prompt.ActionText = wanted
			end
		elseif kind == "Potato" then
			on = state == "Free" or freeHand
		elseif kind == "Chest" then
			on = (state == "Free" or state == "Holding") and (player:GetAttribute("Keys") or 0) > 0
		elseif kind == "Wing" then
			local isOwner = K:GetAttribute("KitchenIndex") == player:GetAttribute("OwnKitchenIndex")
			on = isOwner and (state == "Free" or state == "Holding") and prompt:GetAttribute("Wing") == (K:GetAttribute("Wings") or 0) + 1
		elseif kind == "Order" then
			local isOwner = K:GetAttribute("KitchenIndex") == player:GetAttribute("OwnKitchenIndex")
			on = isOwner and state ~= "Peeling" and state ~= "Loading" and player:GetAttribute("OrderState") == "Offer"
		elseif kind == "Belt" then
			on = state == "Holding" and player:GetAttribute("HeldPeeled") == true and K:GetAttribute("HasBelt") == true
		elseif kind == "Cart" then
			on = state == "Holding" and player:GetAttribute("HeldPeeled") == true
				and K:GetAttribute("CartState") == "Home"
				and (K:GetAttribute("CartCount") or 0) < (K:GetAttribute("CartCapacity") or 0)
		elseif kind == "Send" then
			on = (state == "Free" or state == "Holding")
				and K:GetAttribute("CartState") == "Home"
				and (K:GetAttribute("CartCount") or 0) > 0
		end
	end
	if prompt.Enabled ~= on then
		prompt.Enabled = on
	end
end

function Prompts.Init()
	-- outros prompts dentro das cozinhas (Intendência, porta vermelha do lobby): só de dentro
	local others: { [ProximityPrompt]: Model } = {}
	local function track(d: Instance)
		if d:IsA("ProximityPrompt") and not CollectionService:HasTag(d, "KitchenPrompt") then
			local K = kitchenOf(d)
			if K then
				others[d] = K
			end
		end
	end
	local kitchens = Workspace:WaitForChild("Kitchens")
	for _, d in kitchens:GetDescendants() do
		track(d)
	end
	kitchens.DescendantAdded:Connect(track)
	kitchens.DescendantRemoving:Connect(function(d)
		others[d :: any] = nil
	end)
	task.spawn(function()
		while true do
			for _, p in CollectionService:GetTagged("KitchenPrompt") do
				if p:IsA("ProximityPrompt") then
					evaluate(p)
				end
			end
			for p, K in others do
				local inside = insideKitchen(K)
				if p.Enabled ~= inside then
					p.Enabled = inside
				end
			end
			-- prompts do hub (portal da corrida)
			for _, p in CollectionService:GetTagged("HubPrompt") do
				if p:IsA("ProximityPrompt") then
					local st = player:GetAttribute("State")
					local rs = player:GetAttribute("RaceState")
					-- portão da Horta Proibida: fechado ("EM BREVE") enquanto RoomOpen for false
					local closed = p:GetAttribute("Kind") == "SecretRoom" and not Config.Golden.RoomOpen
					p.Enabled = (st == "Free" or st == "Holding") and rs == nil and not closed
				end
			end
			task.wait(0.15)
		end
	end)
	CollectionService:GetInstanceAddedSignal("KitchenPrompt"):Connect(function(p)
		if p:IsA("ProximityPrompt") then
			evaluate(p)
		end
	end)
end

return Prompts
