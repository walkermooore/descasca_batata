-- RewardService: batatas douradas, chaves, Baú do Porão e fragmentos de mapa (seção 2.9).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Strings = require(ReplicatedStorage.Shared.Strings)
local Remotes = ReplicatedStorage.Remotes

local RewardService = {}

local S
local rng = Random.new()

-- Descascada, a dourada revela uma chave (30%) ou um fragmento de mapa (70%).
-- 5 fragmentos abrem a Horta Proibida: +5% de Moedas permanente (+ cosmético, Etapa 5).
function RewardService.GoldenFound(player: Player)
	local data = S.Data.Get(player)
	if not data then
		return nil
	end
	local g = Config.Golden
	data.Stats.Golden += 1
	S.Bus.Fire("GoldenFound", player)
	local reward = { Kind = "Fragment", Fragments = 0, Needed = g.FragmentsPerRoom, RoomUnlocked = false }
	if rng:NextNumber() < g.KeyChance then
		data.Keys += 1
		reward.Kind = "Key"
	else
		data.Fragments += 1
		if data.Fragments >= g.FragmentsPerRoom and not data.Rooms.HortaProibida then
			data.Fragments -= g.FragmentsPerRoom
			data.Rooms.HortaProibida = true
			reward.RoomUnlocked = true
		end
	end
	reward.Fragments = data.Fragments
	S.Session.Publish(player)
	return reward
end

-- Produção das máquinas por minuto (Etapa 3: ProductionService).
function RewardService.MachineCoinsPerMinute(player: Player): number
	return S.Machines.AutoCoinsPerMinute(player)
end

-- A chave abre o Baú do Porão: Moedas = 30 min de produção das máquinas, mínimo 500.
function RewardService.OpenChest(player: Player, K)
	local data = S.Data.Get(player)
	local st = S.Session.GetState(player)
	if not data or st == "Peeling" or st == "Loading" then
		return
	end
	if data.Keys <= 0 then
		S.Kitchen.Notify(player, Strings.NoKey)
		return
	end
	data.Keys -= 1
	local g = Config.Golden
	local amount = math.max(g.ChestMinimum, RewardService.MachineCoinsPerMinute(player) * g.ChestProductionMinutes)
	amount = S.Economy.Add(player, amount, "Chest")
	S.Session.Publish(player)
	Remotes.Reward:FireClient(player, "Chest", { Amount = amount, Pos = S.Kitchen.ChestPosition(K) })
end

function RewardService.Init(services)
	S = services
end

return RewardService
