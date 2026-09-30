-- BeltService: a esteira da cozinha (como no Potato Please original).
--   pegar batata -> descascar -> colocar na esteira -> a esteira leva ao carrinho -> Rei paga.
-- Também cuida das melhorias da cozinha (Config.Upgrades): carrinho maior, esteira mais
-- rápida e o descascador automático, que põe batatas na esteira sozinho.
-- O servidor só cria a batata no início e decide quando ela chega; o movimento na esteira
-- é animado no cliente (BeltAnimator) a partir dos atributos T0/Dur.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)

local BeltService = {}

local S
local state = {} -- K -> { Items = { {Part, Item, T0, Dur} }, AutoAcc }
local rng = Random.new()

local PEELED_SIZE = Vector3.new(0.72, 0.6, 0.9) -- grande o bastante para ver rolando

-- ---------------------------------------------------------------- melhorias

local function levelOf(data, id: string): number
	local u = data and data.Upgrades
	return (u and u[id]) or 1
end

function BeltService.UpgradeValue(player: Player?, id: string): number
	local def = Config.UpgradesById[id].Levels
	local data = player and S.Data.Get(player)
	return def[math.clamp(levelOf(data, id), 1, #def)].Value
end

local function publishUpgrades(player: Player)
	local data = S.Data.Get(player)
	if not data then
		return
	end
	local parts = {}
	for _, u in Config.Upgrades do
		table.insert(parts, u.Id .. ":" .. levelOf(data, u.Id))
	end
	player:SetAttribute("Upgrades", table.concat(parts, ","))
end
BeltService.PublishUpgrades = publishUpgrades

function BeltService.BuyUpgrade(player: Player, id: any)
	local data = S.Data.Get(player)
	local def = typeof(id) == "string" and Config.UpgradesById[id]
	if not data or not def then
		return { Ok = false }
	end
	local lvl = levelOf(data, id)
	local nextDef = def.Levels[lvl + 1]
	if not nextDef then
		return { Ok = false, Reason = "Nível máximo" }
	end
	if not S.Economy.Spend(player, nextDef.Cost, "Upgrade:" .. id) then
		return { Ok = false, Reason = "Moedas insuficientes" }
	end
	data.Upgrades[id] = lvl + 1
	publishUpgrades(player)
	local K = S.Kitchen.GetOwnedKitchen(player)
	if K then
		BeltService.Refresh(K)
		S.Kitchen.Publish(K)
	end
	S.Bus.Fire("Purchased", player, "Upgrade:" .. id)
	return { Ok = true, Level = lvl + 1 }
end

-- ---------------------------------------------------------------- caminho

local function pathOf(K): ({ Vector3 }, number)
	local root = K.Belt:FindFirstChild("BeltRoot")
	local pts = {}
	local i = 1
	while root and root:FindFirstChild("P" .. i) do
		table.insert(pts, (root :: any)["P" .. i].WorldPosition)
		i += 1
	end
	local len = 0
	for j = 2, #pts do
		len += (pts[j] - pts[j - 1]).Magnitude
	end
	return pts, len
end

local function stateOf(K)
	local st = state[K]
	if not st then
		local pts, len = pathOf(K)
		st = { Items = {}, AutoAcc = 0, Path = pts, Length = len }
		state[K] = st
	end
	return st
end

-- ---------------------------------------------------------------- batatas na esteira

-- Coloca uma batata pronta no início da esteira. false se a esteira está lotada.
function BeltService.Push(K, item): boolean
	local st = stateOf(K)
	if #st.Items >= Config.Station.BeltMaxItems or #st.Path < 2 then
		return false
	end
	local def = Config.Potatoes[item.Type] or Config.Potatoes.Comum
	local p = S.Kitchen.MiniPotato(def.FleshColor, PEELED_SIZE)
	p.Name = "BeltPotato"
	p.Material = Enum.Material.Plastic -- fosca, como no close
	p.CastShadow = true
	p.Anchored = true
	p.CFrame = CFrame.new(st.Path[1]) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
	local dur = st.Length / BeltService.UpgradeValue(K.Owner, "Belt")
	local t0 = Workspace:GetServerTimeNow()
	p:SetAttribute("T0", t0)
	p:SetAttribute("Dur", dur)
	p:SetAttribute("Lane", rng:NextNumber(-0.35, 0.35))
	p.Parent = K.Belt.Items
	table.insert(st.Items, { Part = p, Item = item, T0 = t0, Dur = dur })
	K.Model:SetAttribute("BeltCount", #st.Items)
	return true
end

-- Jogador segurando uma batata descascada coloca na esteira (prompt do funil ou botão).
function BeltService.PlaceHeld(player: Player, K)
	if not K or not S.Kitchen.CanUse(K, player) then
		return
	end
	local s = S.Session.Get(player)
	if not s or s.State ~= "Holding" or not s.Held or not s.Held.Peeled then
		return
	end
	local P = s.Held
	if not BeltService.Push(K, P.Item) then
		S.Kitchen.Notify(player, "A esteira está cheia")
		return
	end
	S.Peel.ReleaseHeld(player)
	S.Bus.Fire("BeltPlaced", player)
end

function BeltService.Clear(K)
	local st = stateOf(K)
	for _, it in st.Items do
		it.Part:Destroy()
	end
	st.Items = {}
	st.AutoAcc = 0
	K.Model:SetAttribute("BeltCount", 0)
end

-- ---------------------------------------------------------------- descascador automático

function BeltService.Refresh(K)
	K.Model:SetAttribute("BeltSpeed", BeltService.UpgradeValue(K.Owner, "Belt"))
	local auto = K.Belt:FindFirstChild("AutoPeeler")
	if not auto then
		return
	end
	local rate = if K.Owner then BeltService.UpgradeValue(K.Owner, "AutoPeel") else 0
	local on = rate > 0
	auto:SetAttribute("Active", on)
	auto:SetAttribute("Rate", rate)
	for _, d in auto:GetDescendants() do
		if d:IsA("BasePart") then
			d.Transparency = if on then 0 else 1
			d.CanCollide = on and d.Name == "Body"
		elseif d:IsA("SurfaceGui") then
			d.Enabled = on
		elseif d:IsA("TextLabel") and d.Name == "Rate" then
			d.Text = string.format("AUTO  %s/min", Format.Int(rate))
		end
	end
end

-- Valor de uma batata do descascador automático (85%, sem combo, com os bônus permanentes).
local function autoValue(player: Player): number
	return Config.MachineRules.BaseValue * Config.MachineRules.MaxYield * S.Peel.GlobalMultiplier(player)
end

-- Moedas/min que chegam sozinhas ao Rei (limitado pelo que o carrinho consegue levar).
function BeltService.AutoCoinsPerMinute(player: Player): number
	local rate = BeltService.UpgradeValue(player, "AutoPeel")
	if rate <= 0 then
		return 0
	end
	local K = S.Kitchen.GetOwnedKitchen(player)
	local cap = if K then S.Kitchen.CartCapacity(K) else Config.Station.CartCapacity
	local d = Config.Delivery
	local speed = S.Monetization.SpeedMultiplier(player)
	local cartMax = cap / ((d.CartTravelTime + d.CartReturnTime) / speed) * 60
	return math.min(rate, cartMax) * autoValue(player)
end

-- ---------------------------------------------------------------- tick

local function tickKitchen(K, dt: number)
	local st = stateOf(K)
	local now = Workspace:GetServerTimeNow()
	-- descascador automático
	if K.Owner then
		local rate = BeltService.UpgradeValue(K.Owner, "AutoPeel")
		if rate > 0 then
			st.AutoAcc += rate / 60 * dt
			while st.AutoAcc >= 1 do
				if not BeltService.Push(K, { Value = autoValue(K.Owner), Type = "Comum", Machine = true }) then
					st.AutoAcc = math.min(st.AutoAcc, 1) -- esteira lotada: a máquina espera
					break
				end
				st.AutoAcc -= 1
			end
		end
	end
	-- chegadas ao fim da esteira: caem no carrinho (ou esperam na ponta, em fila)
	local waiting = 0
	local i = 1
	while i <= #st.Items do
		local it = st.Items[i]
		if now >= it.T0 + it.Dur then
			if waiting == 0 and S.Kitchen.AddToCart(K, it.Item) then
				it.Part:Destroy()
				table.remove(st.Items, i)
				continue
			end
			-- carrinho fora ou cheio: fica parada na ponta da esteira, uma atrás da outra
			waiting += 1
			if it.WaitIndex ~= waiting then
				it.WaitIndex = waiting
				it.Part:SetAttribute("Wait", waiting)
			end
		end
		i += 1
	end
	K.Model:SetAttribute("BeltCount", #st.Items)
end

function BeltService.Init(services)
	S = services
	S.Bus.Connect("Loaded", function(player)
		publishUpgrades(player)
		local K = S.Kitchen.GetOwnedKitchen(player)
		if K then
			BeltService.Refresh(K)
			S.Kitchen.Publish(K)
		end
	end)
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(0.1)
			local t = os.clock()
			local dt = math.min(t - last, 1)
			last = t
			for _, K in S.Kitchen.All() do
				local ok, err = pcall(tickKitchen, K, dt)
				if not ok then
					warn("[BeltService]", err)
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function() end)
end

return BeltService
