-- DataService: save do jogador com trava de sessão (seção 10).
--   * UpdateAsync grava {JobId, Time} na trava ao carregar; outro servidor que encontre uma
--     trava recente espera e tenta de novo. Trava sem autosave há 3 min é abandonada.
--   * Autosave a cada 60 s (renova a trava), ao sair (libera a trava) e no BindToClose.
--   * Nunca sobrescreve um save cuja trava pertence a outro servidor.
--   * Sem acesso a DataStore (place não publicado / APIs desligadas): modo offline em memória.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local DataService = {}

local SCHEMA_VERSION = 1

local DEFAULT = {
	Version = SCHEMA_VERSION,
	Coins = 0,
	Tool = "FacaCega",
	OwnedTools = { FacaCega = true },
	Items = {},
	Keys = 0,
	Fragments = 0,
	Rooms = {},
	Settings = { Assisted = false },
	Tutorial = { Step = 1, Peeled = 0 },
	-- Etapa 3: automação e rebirth
	Machines = {}, -- lista de { Id, Type, Col, Row, Rot, Level }
	Inventory = {}, -- tipo -> quantidade comprada e não colocada
	NextMachineId = 1,
	Wings = 0,
	Tank = { Count = 0, Value = 0 },
	Rebirths = 0,
	Seeds = 0,
	Talents = {},
	Theme = "Castelo",
	-- esteira da cozinha: nível de cada melhoria (Config.Upgrades; 1 = inicial)
	Upgrades = { Cart = 1, Belt = 1, AutoPeel = 1 },
	-- Etapa 4: social
	Likes = 0, -- curtidas recebidas na cozinha
	LikesGiven = {}, -- userId do dono -> dia da última curtida
	Weekly = { Week = 0, Peeled = 0, Clean = 0, Race = 0, Duels = 0 },
	-- Etapa 6: monetização
	PassGrants = {}, -- passes com entrega única já entregues (Kit Inicial)
	Boost = { Mult = 1, Until = 0 },
	GoldenPity = 0, -- Bússola Dourada: batatas restantes até a dourada garantida
	ExpressTrips = 0, -- Despacho Expresso: viagens do carrinho que ainda vão e voltam na hora
	Sessions = 0,
	OfferFlags = {}, -- ofertas já mostradas (uma vez cada)
	SubDaily = 0, -- dia do último boost diário da assinatura
	AdsToday = { Day = 0, Count = 0 },
	-- Etapa 7: retenção
	Login = { Streak = 0, LastDay = 0 },
	Missions = { Day = 0, Week = 0, Daily = {}, Weekly = {} },
	KingChestOnline = 0,
	RedeemedCodes = {},
	SeasonPass = { Season = 0, XP = 0, Premium = false, Free = {}, Prem = {} },
	Cosmetics = {},
	Stats = {
		PotatoesPicked = 0,
		PotatoesPeeled = 0,
		PotatoesDelivered = 0,
		SeasonDelivered = 0,
		BestCombo = 0,
		Golden = 0,
		OrdersCompleted = 0,
		CoinsEarned = 0,
	},
	FirstJoin = 0,
	LastSeen = 0,
}

local store: DataStore? = nil
local offlineReason: string? = nil
local profiles: { [Player]: { Data: any, Key: string } } = {}
local waiting: { [Player]: { thread } } = {}

local function deepCopy(t)
	local c = {}
	for k, v in t do
		c[k] = if type(v) == "table" then deepCopy(v) else v
	end
	return c
end

-- Completa campos novos sem apagar os existentes (migração simples entre versões).
local function reconcile(data, template)
	for k, v in template do
		if data[k] == nil then
			data[k] = if type(v) == "table" then deepCopy(v) else v
		elseif type(v) == "table" and type(data[k]) == "table" and next(v) ~= nil then
			reconcile(data[k], v)
		end
	end
	return data
end

local function update(key: string, fn): (boolean, any)
	for attempt = 1, 3 do
		local ok, result = pcall(function()
			return (store :: DataStore):UpdateAsync(key, fn)
		end)
		if ok then
			return true, result
		end
		warn("[DataService] UpdateAsync falhou (" .. attempt .. "/3): " .. tostring(result))
		task.wait(attempt * 2)
	end
	return false, nil
end

local function finishLoad(player: Player, data, offline: boolean)
	reconcile(data, DEFAULT)
	if data.FirstJoin == 0 then
		data.FirstJoin = os.time()
	end
	data.Lock = nil
	profiles[player] = { Data = data, Key = "u_" .. player.UserId }
	player:SetAttribute("DataLoaded", true)
	player:SetAttribute("DataOffline", offline)
	for _, th in waiting[player] or {} do
		task.spawn(th, data)
	end
	waiting[player] = nil
end

local save

local function load(player: Player)
	if not store then
		finishLoad(player, deepCopy(DEFAULT), true)
		return
	end
	local key = "u_" .. player.UserId
	local cfg = Config.Data
	for attempt = 1, cfg.LoadRetries do
		if not player.Parent then
			return
		end
		local steal = attempt == cfg.LoadRetries
		local blocked = false
		local ok, result = update(key, function(old)
			old = old or deepCopy(DEFAULT)
			local lock = old.Lock
			if not steal and lock and lock.JobId ~= game.JobId and os.time() - (lock.Time or 0) < cfg.LockStaleSeconds then
				blocked = true
				return nil -- cancela: outro servidor ainda está com o save
			end
			old.Lock = { JobId = game.JobId, Time = os.time() }
			return old
		end)
		if not ok then
			warn("[DataService] não foi possível carregar " .. player.Name .. "; sessão sem save")
			finishLoad(player, deepCopy(DEFAULT), true)
			return
		end
		if not blocked and result then
			finishLoad(player, result, false)
			if not player.Parent then
				-- saiu durante o carregamento: libera a trava que acabamos de pegar
				save(player, true)
				profiles[player] = nil
			end
			return
		end
		task.wait(cfg.RetryWait)
	end
end

function save(player: Player, release: boolean)
	local profile = profiles[player]
	if not profile or not store or player:GetAttribute("DataOffline") then
		return
	end
	profile.Data.LastSeen = os.time()
	update(profile.Key, function(old)
		if old and old.Lock and old.Lock.JobId ~= game.JobId then
			return nil -- outro servidor tomou a trava: não sobrescrever
		end
		local copy = deepCopy(profile.Data)
		copy.Lock = if release then nil else { JobId = game.JobId, Time = os.time() }
		return copy
	end)
end

-- Retorna os dados (espera o carregamento). nil se o jogador saiu antes.
function DataService.WaitForData(player: Player)
	local p = profiles[player]
	if p then
		return p.Data
	end
	if not player.Parent then
		return nil
	end
	waiting[player] = waiting[player] or {}
	table.insert(waiting[player], coroutine.running())
	return coroutine.yield()
end

function DataService.Get(player: Player)
	local p = profiles[player]
	return p and p.Data
end

function DataService.IsOffline(): boolean
	return store == nil
end

-- Salva já (usado antes de confirmar uma compra de Robux). Retorna true se gravou.
function DataService.SaveNow(player: Player): boolean
	if not store or player:GetAttribute("DataOffline") then
		return true -- modo offline: não há onde gravar; a concessão fica só na sessão
	end
	local profile = profiles[player]
	if not profile then
		return false
	end
	local ok = update(profile.Key, function(old)
		if old and old.Lock and old.Lock.JobId ~= game.JobId then
			return nil
		end
		local copy = deepCopy(profile.Data)
		copy.Lock = { JobId = game.JobId, Time = os.time() }
		return copy
	end)
	return ok
end

function DataService.Init()
	local name = Config.Data.StoreName .. (if RunService:IsStudio() then "_Studio" else "")
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(name)
	end)
	if ok then
		store = result
		-- no Studio sem "Enable Studio Access to API Services" a primeira chamada falha
		if RunService:IsStudio() then
			local ok2, err = pcall(function()
				return (store :: DataStore):GetAsync("__probe")
			end)
			if not ok2 then
				store = nil
				offlineReason = tostring(err)
			end
		end
	else
		offlineReason = tostring(result)
	end
	if not store then
		warn("[DataService] DataStore indisponível, modo offline: " .. tostring(offlineReason))
	end

	Players.PlayerAdded:Connect(load)
	for _, p in Players:GetPlayers() do
		task.spawn(load, p)
	end
	Players.PlayerRemoving:Connect(function(player)
		save(player, true)
		profiles[player] = nil
		for _, th in waiting[player] or {} do
			task.spawn(th, nil)
		end
		waiting[player] = nil
	end)

	-- autosave
	task.spawn(function()
		while true do
			task.wait(Config.Economy.AutosaveInterval)
			for player in profiles do
				task.spawn(save, player, false)
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				save(player, true)
				pending -= 1
			end)
		end
		local t0 = os.clock()
		while pending > 0 and os.clock() - t0 < 25 do
			task.wait(0.1)
		end
	end)
end

return DataService
