-- SessionService: estado de sessão de cada jogador e a máquina de estados da seção 2.3.
-- Estados: Loading, Free, Holding, Peeling, CarryingBucket, Duel (sentado na mesa do duelo).
-- Também publica em atributos do Player o que o cliente precisa saber do save
-- (ferramenta, itens, chaves, fragmentos, passo do tutorial).

local Players = game:GetService("Players")
local StarterPlayer = game:GetService("StarterPlayer")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local SessionService = {}

local S
local sessions = {}

-- Disparado quando o personagem nasce/morre ou o jogador sai: limpa batata e balde.
local resetEvent = Instance.new("BindableEvent")
SessionService.Reset = resetEvent.Event

local function applyMovement(player: Player)
	local s = sessions[player]
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not s or not hum then
		return
	end
	-- passe Carrinho Turbo: +40% de velocidade ao andar
	local speed = StarterPlayer.CharacterWalkSpeed * (if S and S.Monetization then S.Monetization.SpeedMultiplier(player) else 1)
	if s.State == "Peeling" or s.State == "Loading" or s.State == "Duel" then
		hum.WalkSpeed = if s.State == "Loading" then speed else 0
		hum.JumpHeight = if s.State == "Loading" then StarterPlayer.CharacterJumpHeight else 0
	elseif s.State == "CarryingBucket" then
		hum.WalkSpeed = speed * Config.Interaction.CarryBucketSpeedFactor
		hum.JumpHeight = 0
	else
		hum.WalkSpeed = speed
		hum.JumpHeight = StarterPlayer.CharacterJumpHeight
	end
end

function SessionService.RefreshMovement(player: Player)
	applyMovement(player)
end

function SessionService.Get(player: Player)
	return sessions[player]
end

function SessionService.GetState(player: Player): string?
	local s = sessions[player]
	return s and s.State
end

function SessionService.SetState(player: Player, state: string)
	local s = sessions[player]
	if not s then
		return
	end
	s.State = state
	player:SetAttribute("State", state)
	applyMovement(player)
end

-- Esvazia as mãos (batatas somem, balde volta) e volta ao estado Livre.
function SessionService.ResetHands(player: Player)
	local s = sessions[player]
	resetEvent:Fire(player)
	if s and s.State ~= "Loading" then
		SessionService.SetState(player, "Free")
	end
end

function SessionService.SetCombo(player: Player, combo: number, mult: number, deadline: number)
	local s = sessions[player]
	if not s then
		return
	end
	s.Combo = combo
	s.ComboDeadline = deadline
	player:SetAttribute("Combo", combo)
	player:SetAttribute("ComboMult", mult)
	player:SetAttribute("ComboDeadline", deadline)
end

function SessionService.SetAssisted(player: Player, on: boolean)
	local s = sessions[player]
	local data = S.Data.Get(player)
	if not s or not data then
		return
	end
	s.Assisted = on
	data.Settings.Assisted = on
	player:SetAttribute("Assisted", on)
	if on then
		SessionService.SetCombo(player, 0, 1, 0)
	end
end

function SessionService.HasItem(player: Player, id: string): boolean
	local data = S.Data.Get(player)
	return data ~= nil and data.Items[id] == true
end

function SessionService.Hands(player: Player): number
	return if SessionService.HasItem(player, "Luvas") then Config.Interaction.HandsWithGloves else Config.Interaction.HandsWithoutGloves
end

function SessionService.StockMax(player: Player): number
	return if SessionService.HasItem(player, "CarrinhoMao") then Config.CollectionById.CarrinhoMao.Stock else 0
end

function SessionService.SetStock(player: Player, n: number)
	local s = sessions[player]
	if s then
		s.Stock = n
		player:SetAttribute("Stock", n)
	end
end

-- Atributos derivados do save, lidos pelo cliente (HUD, loja, prompts, tutorial).
function SessionService.Publish(player: Player)
	local s = sessions[player]
	local data = S.Data.Get(player)
	if not s or not data then
		return
	end
	s.ToolId = data.Tool
	s.Assisted = data.Settings.Assisted == true
	player:SetAttribute("ToolId", data.Tool)
	player:SetAttribute("Assisted", s.Assisted)
	local owned = {}
	for id, v in data.OwnedTools do
		if v then
			table.insert(owned, id)
		end
	end
	for id, v in data.Items do
		if v then
			table.insert(owned, id)
		end
	end
	player:SetAttribute("Owned", table.concat(owned, ","))
	player:SetAttribute("Hands", SessionService.Hands(player))
	player:SetAttribute("StockMax", SessionService.StockMax(player))
	player:SetAttribute("Stock", s.Stock)
	player:SetAttribute("Keys", data.Keys)
	player:SetAttribute("Fragments", data.Fragments)
	player:SetAttribute("HasRoom", data.Rooms.HortaProibida == true)
	player:SetAttribute("TutorialStep", data.Tutorial.Step)
	player:SetAttribute("TutorialPeeled", data.Tutorial.Peeled)
end

local function onPlayerAdded(player: Player)
	sessions[player] = {
		State = "Loading",
		ToolId = Config.Dev.StartingTool,
		Assisted = false,
		Combo = 0,
		ComboDeadline = 0,
		StrokeTimes = {},
		Held = nil,
		Extra = nil,
		Stock = 0,
	}
	player:SetAttribute("State", "Loading")
	SessionService.SetCombo(player, 0, 1, 0)

	local function onCharacter(char: Model)
		resetEvent:Fire(player)
		if sessions[player] and sessions[player].State ~= "Loading" then
			SessionService.SetState(player, "Free")
		end
		local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
		if hum then
			hum.UseJumpPower = false
			applyMovement(player)
			hum.Died:Connect(function()
				resetEvent:Fire(player)
			end)
		end
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end

	local data = S.Data.WaitForData(player)
	if not data or not sessions[player] then
		return
	end
	SessionService.Publish(player)
	SessionService.SetState(player, "Free")
	S.Bus.Fire("Loaded", player, data)
end

function SessionService.Init(services)
	S = services
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, p in Players:GetPlayers() do
		task.spawn(onPlayerAdded, p)
	end
	Players.PlayerRemoving:Connect(function(player)
		resetEvent:Fire(player)
		task.defer(function()
			sessions[player] = nil
		end)
	end)
end

return SessionService
