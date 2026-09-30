-- EconomyService: única porta para somar ou gastar Moedas (seção 10).
-- O saldo vive no save (DataService); aqui só se altera e publica.

local Players = game:GetService("Players")
local AnalyticsService = game:GetService("AnalyticsService")

local EconomyService = {}

local S

local function publish(player: Player)
	local data = S.Data.Get(player)
	if not data then
		return
	end
	player:SetAttribute("Coins", data.Coins)
	local ls = player:FindFirstChild("leaderstats")
	local iv = ls and ls:FindFirstChild("Moedas")
	if iv then
		(iv :: IntValue).Value = data.Coins
	end
end

local function log(player: Player, flow, amount: number, balance: number, source: string)
	pcall(function()
		AnalyticsService:LogEconomyEvent(player, flow, "Moedas", amount, balance, source)
	end)
end

function EconomyService.Refresh(player: Player)
	publish(player)
end

function EconomyService.Get(player: Player): number
	local data = S.Data.Get(player)
	return data and data.Coins or 0
end

-- Quanto o jogador receberia (passes Moedas x2 / VIP, boosts e assinatura valem só para produção).
function EconomyService.Preview(player: Player, amount: number, source: string): number
	local mult = if S.Monetization then S.Monetization.EarnMultiplier(player, source) else 1
	return math.floor(amount * mult + 0.5)
end

function EconomyService.Add(player: Player, amount: number, source: string): number
	local data = S.Data.Get(player)
	if not data or amount ~= amount or amount <= 0 then
		return 0
	end
	local n = EconomyService.Preview(player, amount, source)
	if S.Monetization then
		S.Monetization.NoteEarned(player, n)
	end
	if n <= 0 then
		return 0
	end
	data.Coins += n
	data.Stats.CoinsEarned += n
	publish(player)
	log(player, Enum.AnalyticsEconomyFlowType.Source, n, data.Coins, source)
	return n
end

function EconomyService.Spend(player: Player, amount: number, sink: string): boolean
	local data = S.Data.Get(player)
	if not data or amount ~= amount or amount < 0 or data.Coins < amount then
		return false
	end
	data.Coins -= amount
	publish(player)
	log(player, Enum.AnalyticsEconomyFlowType.Sink, amount, data.Coins, sink)
	return true
end

local function onPlayerAdded(player: Player)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local iv = Instance.new("IntValue")
	iv.Name = "Moedas"
	iv.Parent = ls
	ls.Parent = player
	if S.Data.WaitForData(player) then
		publish(player)
	end
end

function EconomyService.Init(services)
	S = services
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, p in Players:GetPlayers() do
		task.spawn(onPlayerAdded, p)
	end
end

return EconomyService
