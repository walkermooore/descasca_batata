-- RetentionService (seção 9): motivos para voltar todo dia.
--   * Login diário de 7 dias (perder um dia só pausa), missões diárias (3) e semanais (5).
--   * Baú do Rei a cada 4 horas online.
--   * Passe de temporada de 40 níveis (trilha grátis e premium); XP vem de jogar.
--   * Hora Dourada nos fins de semana, códigos de resgate, Admin Abuse ao vivo.
-- O cliente recebe um resumo em JSON no atributo "Retention" do Player.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = ReplicatedStorage.Remotes

local RetentionService = {}

local S
local dirty: { [Player]: boolean } = {}
local serverBoost = { Mult = 1, Until = 0 }
local forcedGoldenUntil = 0

local function today(): number
	return math.floor(os.time() / 86400)
end

local function week(): number
	return math.floor((os.time() - 345600) / 604800)
end

-- ---------------------------------------------------------------- recompensas

local function describe(r): string
	local parts = {}
	if r.Coins then
		table.insert(parts, Format.Int(r.Coins) .. " Moedas")
	end
	if r.Keys then
		table.insert(parts, r.Keys .. " chave")
	end
	if r.Boost then
		table.insert(parts, string.format("Boost x%d (%d min)", r.Boost.Mult, r.Boost.Minutes))
	end
	if r.Cosmetic then
		table.insert(parts, "cosmético exclusivo")
	end
	return table.concat(parts, " + ")
end

local function grant(player: Player, r, source: string)
	local data = S.Data.Get(player)
	if not data then
		return
	end
	if r.Coins then
		S.Economy.Add(player, r.Coins, source)
	end
	if r.Keys then
		data.Keys += r.Keys
	end
	if r.Boost then
		S.Monetization.SetBoost(player, r.Boost.Mult, r.Boost.Minutes)
	end
	if r.Cosmetic then
		data.Cosmetics[r.Cosmetic] = true
		S.Avatar.Refresh(player)
	end
	S.Session.Publish(player)
	dirty[player] = true
end

-- Recompensa de cada nível do passe (gerada, para caber 40 níveis sem tabela gigante).
function RetentionService.PassReward(level: number, track: string)
	if track == "Free" then
		if level % 10 == 0 then
			return { Coins = level * 300, Keys = 1 }
		elseif level % 5 == 0 then
			return { Coins = level * 200, Boost = { Mult = 2, Minutes = 15 } }
		end
		return { Coins = level * 200 }
	end
	if level == Config.Season.Levels then
		return { Coins = 40000, Cosmetic = "CoroaDeCasca" }
	elseif level % 10 == 0 then
		return { Coins = level * 600, Cosmetic = "AventalTemporada" }
	elseif level % 4 == 0 then
		return { Boost = { Mult = 2, Minutes = 30 } }
	elseif level % 3 == 0 then
		return { Keys = 1 }
	end
	return { Coins = level * 500 }
end

-- ---------------------------------------------------------------- estado publicado

local function passLevel(data): number
	return math.min(Config.Season.Levels, math.floor(data.SeasonPass.XP / Config.Season.XPPerLevel))
end

function RetentionService.GoldenHourActive(): boolean
	if os.time() < forcedGoldenUntil then
		return true
	end
	local g = Config.GoldenHour
	local t = os.date("!*t")
	if not g.WeekDays[t.wday] then
		return false
	end
	local h = t.hour
	return h >= g.StartHourUTC and h < g.StartHourUTC + g.Hours
end

function RetentionService.GoldenHourMultiplier(): number
	return if RetentionService.GoldenHourActive() then Config.GoldenHour.Multiplier else 1
end

function RetentionService.ServerBoost(): number
	return if serverBoost.Until > os.time() then serverBoost.Mult else 1
end

local function publish(player: Player)
	local data = S.Data.Get(player)
	if not data then
		return
	end
	local function missions(list)
		local out = {}
		for _, m in list do
			table.insert(out, { Text = m.Text, P = math.floor(m.Progress), T = m.Target, Done = m.Done, Coins = m.Coins })
		end
		return out
	end
	local free, prem = {}, {}
	for lvl in data.SeasonPass.Free do
		table.insert(free, tonumber(lvl))
	end
	for lvl in data.SeasonPass.Prem do
		table.insert(prem, tonumber(lvl))
	end
	local summary = {
		Login = { Streak = data.Login.Streak },
		Daily = missions(data.Missions.Daily),
		Weekly = missions(data.Missions.Weekly),
		ChestLeft = math.max(0, Config.KingChest.OnlineSeconds - data.KingChestOnline),
		Pass = {
			Season = Config.Season.Name,
			Level = passLevel(data),
			XP = data.SeasonPass.XP,
			XPPer = Config.Season.XPPerLevel,
			Premium = data.SeasonPass.Premium,
			Free = free,
			Prem = prem,
		},
	}
	player:SetAttribute("Retention", HttpService:JSONEncode(summary))
	dirty[player] = nil
end

-- ---------------------------------------------------------------- missões

local function pick(pool, count: number, seed: number)
	local rng = Random.new(seed)
	local ids = {}
	for i = 1, #pool do
		ids[i] = i
	end
	local out = {}
	for _ = 1, math.min(count, #pool) do
		local k = rng:NextInteger(1, #ids)
		local def = pool[table.remove(ids, k)]
		table.insert(out, { Id = def.Id, Kind = def.Kind, Target = def.Target, Text = def.Text, Coins = def.Coins, XP = def.XP, Progress = 0, Done = false })
	end
	return out
end

local function refreshMissions(player: Player, data)
	local m = data.Missions
	if m.Day ~= today() then
		m.Day = today()
		m.Daily = pick(Config.Missions.Daily, Config.Missions.DailyCount, today() * 7919 + player.UserId % 10007)
	end
	if m.Week ~= week() then
		m.Week = week()
		m.Weekly = pick(Config.Missions.Weekly, Config.Missions.WeeklyCount, week() * 104729 + player.UserId % 10007)
	end
end

local function addXP(player: Player, amount: number)
	local data = S.Data.Get(player)
	if not data then
		return
	end
	local before = passLevel(data)
	data.SeasonPass.XP += amount
	local after = passLevel(data)
	if after > before then
		Remotes.Reward:FireClient(player, "PassLevel", { Level = after })
	end
	dirty[player] = true
end
RetentionService.AddXP = addXP

-- kind: tipo da missão; value: quanto somar (ou o valor atual, se max=true)
local function progress(player: Player, kind: string, value: number, max: boolean?)
	local data = S.Data.Get(player)
	if not data then
		return
	end
	refreshMissions(player, data)
	for _, list in { data.Missions.Daily, data.Missions.Weekly } do
		for _, m in list do
			if m.Kind == kind and not m.Done then
				m.Progress = if max then math.max(m.Progress, value) else m.Progress + value
				if m.Progress >= m.Target then
					m.Progress = m.Target
					m.Done = true
					grant(player, { Coins = m.Coins }, "Mission")
					addXP(player, m.XP)
					Remotes.Reward:FireClient(player, "Mission", { Text = m.Text, Coins = m.Coins })
				end
				dirty[player] = true
			end
		end
	end
end

-- ---------------------------------------------------------------- ações

function RetentionService.GrantPremium(player: Player)
	local data = S.Data.Get(player)
	if data then
		data.SeasonPass.Premium = true
		dirty[player] = true
	end
end

local function claimPass(player: Player, level: any, track: any)
	local data = S.Data.Get(player)
	if not data or typeof(level) ~= "number" or (track ~= "Free" and track ~= "Prem") then
		return { Ok = false }
	end
	level = math.floor(level)
	if level < 1 or level > passLevel(data) then
		return { Ok = false, Reason = "Nível ainda não alcançado" }
	end
	if track == "Prem" and not data.SeasonPass.Premium then
		return { Ok = false, Reason = "Trilha premium" }
	end
	local claimed = if track == "Free" then data.SeasonPass.Free else data.SeasonPass.Prem
	if claimed[tostring(level)] then
		return { Ok = false, Reason = "Já resgatado" }
	end
	claimed[tostring(level)] = true
	local r = RetentionService.PassReward(level, track)
	grant(player, r, "SeasonPass")
	return { Ok = true, Text = describe(r) }
end

local function claimChest(player: Player)
	local data = S.Data.Get(player)
	if not data or data.KingChestOnline < Config.KingChest.OnlineSeconds then
		return { Ok = false, Reason = "O Baú do Rei ainda não abriu" }
	end
	data.KingChestOnline = 0
	local amount = math.max(Config.KingChest.Minimum, S.Monetization.ProductionPerMinute(player) * Config.KingChest.ProductionMinutes)
	grant(player, { Coins = math.floor(amount) }, "KingChest")
	return { Ok = true, Text = "+" .. Format.Int(amount) .. " Moedas" }
end

local function redeem(player: Player, code: any)
	local data = S.Data.Get(player)
	if not data or typeof(code) ~= "string" then
		return { Ok = false }
	end
	code = string.upper((code:gsub("%s", "")))
	local r = Config.Codes[code]
	if not r then
		return { Ok = false, Reason = "Código inválido" }
	end
	if data.RedeemedCodes[code] then
		return { Ok = false, Reason = "Código já usado" }
	end
	data.RedeemedCodes[code] = true
	grant(player, r, "Code")
	return { Ok = true, Text = describe(r) }
end

local function admin(player: Player, cmd: any, a: any, b: any)
	if not table.find(Config.Admins, player.UserId) then
		return { Ok = false }
	end
	if cmd == "abuse" and typeof(a) == "number" and typeof(b) == "number" then
		serverBoost = { Mult = math.clamp(a, 1, 5), Until = os.time() + math.clamp(b, 1, 60) * 60 }
		Workspace:SetAttribute("ServerBoost", serverBoost.Mult)
		Workspace:SetAttribute("ServerBoostEnds", serverBoost.Until)
		Remotes.Reward:FireAllClients("King", { Text = string.format("ADMIN ABUSE! Produção x%d por %d min!", serverBoost.Mult, b) })
	elseif cmd == "golden" and typeof(a) == "number" then
		forcedGoldenUntil = os.time() + math.clamp(a, 1, 120) * 60
	elseif cmd == "giant" then
		S.Events.DebugStartGiant()
	else
		return { Ok = false }
	end
	return { Ok = true }
end

-- ---------------------------------------------------------------- entrada e loops

local function onLoaded(player: Player, data)
	-- temporada nova: passe zera
	if data.SeasonPass.Season ~= Config.Season.Id then
		data.SeasonPass = { Season = Config.Season.Id, XP = 0, Premium = false, Free = {}, Prem = {} }
	end
	refreshMissions(player, data)
	-- login diário (perder um dia não zera: só avança quando o jogador volta)
	if data.Login.LastDay ~= today() then
		data.Login.LastDay = today()
		data.Login.Streak = data.Login.Streak % #Config.Login.Rewards + 1
		local r = Config.Login.Rewards[data.Login.Streak]
		task.delay(5, function()
			if player.Parent then
				grant(player, r, "Login")
				Remotes.Reward:FireClient(player, "Login", { Day = data.Login.Streak, Text = describe(r) })
			end
		end)
	end
	publish(player)
end

function RetentionService.Init(services)
	S = services
	S.Bus.Connect("Loaded", onLoaded)
	S.Bus.Connect("StrokeResult", function(player, result)
		if result == "Perfect" then
			progress(player, "Perfect", 1)
		end
	end)
	S.Bus.Connect("PotatoFinished", function(player)
		progress(player, "Peel", 1)
		addXP(player, Config.Season.XP.PotatoPeeled)
	end)
	S.Bus.Connect("Delivered", function(player, _, count)
		progress(player, "Deliver", count)
		addXP(player, Config.Season.XP.PotatoDelivered * count)
	end)
	S.Bus.Connect("ComboChanged", function(player, combo)
		progress(player, "Combo", combo, true)
	end)
	S.Bus.Connect("OrderDone", function(player)
		progress(player, "Order", 1)
		addXP(player, Config.Season.XP.OrderDone)
	end)
	S.Bus.Connect("GoldenFound", function(player)
		progress(player, "Golden", 1)
	end)
	S.Bus.Connect("RaceFinished", function(player)
		progress(player, "Race", 1)
		addXP(player, Config.Season.XP.RaceDone)
	end)
	S.Bus.Connect("Discarded", function(player)
		progress(player, "Discard", 1)
	end)

	Remotes.RetentionRequest.OnServerInvoke = function(player: Player, action: any, a: any, b: any, c: any)
		if action == "ClaimPass" then
			return claimPass(player, a, b)
		elseif action == "ClaimChest" then
			return claimChest(player)
		elseif action == "Redeem" then
			return redeem(player, a)
		elseif action == "Admin" then
			return admin(player, a, b, c)
		end
		return { Ok = false }
	end

	Players.PlayerRemoving:Connect(function(p)
		dirty[p] = nil
	end)

	-- relógio: Baú do Rei (tempo online), ajuda a amigos, Hora Dourada, publicação
	task.spawn(function()
		local tick = 0
		while true do
			task.wait(2)
			tick += 2
			Workspace:SetAttribute("GoldenHour", RetentionService.GoldenHourActive())
			for _, p in Players:GetPlayers() do
				local data = S.Data.Get(p)
				if data then
					if data.KingChestOnline < Config.KingChest.OnlineSeconds then
						data.KingChestOnline += 2
						if tick % 30 == 0 or data.KingChestOnline >= Config.KingChest.OnlineSeconds then
							dirty[p] = true
						end
					end
					if p:GetAttribute("GuestOf") then
						progress(p, "HelpMinutes", 2 / 60)
					end
					if dirty[p] then
						publish(p)
					end
				end
			end
		end
	end)
end

return RetentionService
