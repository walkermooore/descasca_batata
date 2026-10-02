-- RankingService: rankings semanais (batatas descascadas, batatas perfeitas, corrida) e de rebirths,
-- globais (OrderedDataStore) e entre amigos (seção 5). Os quadros do hub mostram o top 10 global.
-- Sem DataStore (Studio sem publicar): usa só os jogadores do servidor.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)

local RankingService = {}

local S
local online = false
local stores = {}
local pushed: { [Player]: { [string]: number } } = {}
local cache = {} -- chave -> { Time, Rows }
local names = {} -- userId -> nome
local friendsCache = {} -- userId -> { Time, Ids }

function RankingService.Week(): number
	-- semanas desde 05/01/1970 (segunda-feira) 00:00 UTC
	return math.floor((os.time() - 345600) / 604800)
end

local function boardDef(id: string)
	for _, b in Config.Rankings.Boards do
		if b.Id == id then
			return b
		end
	end
	return nil
end

local function storeFor(id: string): OrderedDataStore?
	online = not S.Data.IsOffline() -- o DataService inicia depois deste serviço
	if not online then
		return nil
	end
	local b = boardDef(id)
	if not b then
		return nil
	end
	local name = "Rank_" .. id .. (if b.Weekly then "_W" .. RankingService.Week() else "") .. (if RunService:IsStudio() then "_Studio" else "")
	if not stores[name] then
		stores[name] = DataStoreService:GetOrderedDataStore(name)
	end
	return stores[name]
end

-- Zera os contadores semanais quando a semana vira.
local function ensureWeek(data)
	local w = RankingService.Week()
	if data.Weekly.Week ~= w then
		data.Weekly = { Week = w, Peeled = 0, Clean = 0, Race = 0, Duels = 0 }
	end
end

local function valueOf(data, id: string): number
	ensureWeek(data)
	if id == "Peeled" then
		return data.Weekly.Peeled
	elseif id == "Clean" then
		return data.Weekly.Clean or 0
	elseif id == "Duels" then
		return data.Weekly.Duels or 0
	elseif id == "Race" then
		return data.Weekly.Race
	elseif id == "Rebirths" then
		return data.Rebirths
	end
	return 0
end

function RankingService.SubmitRace(player: Player, score: number)
	local data = S.Data.Get(player)
	if data then
		ensureWeek(data)
		data.Weekly.Race = math.max(data.Weekly.Race, math.floor(score * 10 + 0.5) / 10)
	end
end

local function nameOf(userId: number): string
	if names[userId] then
		return names[userId]
	end
	local p = Players:GetPlayerByUserId(userId)
	if p then
		names[userId] = p.DisplayName
		return p.DisplayName
	end
	local ok, n = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	names[userId] = if ok and n then n else ("#" .. userId)
	return names[userId]
end

local function serverRows(id: string, filter: { [number]: boolean }?)
	local rows = {}
	for _, p in Players:GetPlayers() do
		local data = S.Data.Get(p)
		if data and (not filter or filter[p.UserId]) then
			table.insert(rows, { Name = p.DisplayName, Value = valueOf(data, id), UserId = p.UserId })
		end
	end
	return rows
end

local function sortRows(rows)
	table.sort(rows, function(a, b)
		return a.Value > b.Value
	end)
	while #rows > Config.Rankings.Top do
		table.remove(rows)
	end
	return rows
end

local function globalRows(id: string)
	local key = "G:" .. id
	local c = cache[key]
	if c and os.clock() - c.Time < Config.Rankings.RefreshSeconds then
		return c.Rows
	end
	local store = storeFor(id)
	local rows
	if store then
		local ok, pages = pcall(function()
			return store:GetSortedAsync(false, Config.Rankings.Top)
		end)
		if ok and pages then
			rows = {}
			for _, entry in pages:GetCurrentPage() do
				local userId = tonumber(entry.key) or 0
				table.insert(rows, { Name = nameOf(userId), Value = entry.value / 10, UserId = userId })
			end
		end
	end
	rows = rows or sortRows(serverRows(id))
	cache[key] = { Time = os.clock(), Rows = rows }
	return rows
end

local function friendIds(player: Player): { [number]: boolean }
	local c = friendsCache[player.UserId]
	if c and os.clock() - c.Time < 300 then
		return c.Ids
	end
	local ids = { [player.UserId] = true }
	local ok, pages = pcall(function()
		return Players:GetFriendsAsync(player.UserId)
	end)
	local n = 0
	while ok and pages and n < Config.Rankings.MaxFriends do
		for _, f in pages:GetCurrentPage() do
			ids[f.Id] = true
			names[f.Id] = f.DisplayName or f.Username
			n += 1
		end
		if pages.IsFinished or n >= Config.Rankings.MaxFriends then
			break
		end
		ok = pcall(function()
			pages:AdvanceToNextPageAsync()
		end)
	end
	friendsCache[player.UserId] = { Time = os.clock(), Ids = ids }
	return ids
end

local function friendRows(player: Player, id: string)
	local ids = friendIds(player)
	local rows = serverRows(id, ids)
	local inServer = {}
	for _, r in rows do
		inServer[r.UserId] = true
	end
	local store = storeFor(id)
	if store then
		for userId in ids do
			if not inServer[userId] then
				local ok, v = pcall(function()
					return store:GetAsync(tostring(userId))
				end)
				if ok and v then
					table.insert(rows, { Name = nameOf(userId), Value = v / 10, UserId = userId })
				end
			end
		end
	end
	return sortRows(rows)
end

-- scope: "Global", "Friends" ou "Server"
function RankingService.Get(player: Player, id: string, scope: string)
	if not boardDef(id) then
		return {}
	end
	if scope == "Friends" then
		return friendRows(player, id)
	elseif scope == "Server" then
		return sortRows(serverRows(id))
	end
	return globalRows(id)
end

local function push()
	for _, p in Players:GetPlayers() do
		local data = S.Data.Get(p)
		if data then
			pushed[p] = pushed[p] or {}
			for _, b in Config.Rankings.Boards do
				local v = valueOf(data, b.Id)
				local store = storeFor(b.Id)
				if store and v > 0 and pushed[p][b.Id] ~= v then
					local ok = pcall(function()
						store:SetAsync(tostring(p.UserId), math.floor(v * 10 + 0.5))
					end)
					if ok then
						pushed[p][b.Id] = v
					end
				end
			end
		end
	end
end

-- Duelo vencido: conta no ranking semanal.
function RankingService.AddDuelWin(player: Player)
	local data = S.Data.Get(player)
	if data then
		ensureWeek(data)
		data.Weekly.Duels = (data.Weekly.Duels or 0) + 1
	end
end

local function refreshBoards()
	local world = Workspace:FindFirstChild("World")
	if not world then
		return
	end
	for _, b in world:GetDescendants() do
		local id = b:GetAttribute("Board")
		local list = b:FindFirstChild("List", true) :: TextLabel?
		if id and list then
			local rows = globalRows(id)
			local lines = {}
			for i, r in rows do
				local v = if r.Value == math.floor(r.Value) then Format.Int(r.Value) else Format.Dec(r.Value, 1)
				table.insert(lines, string.format("%2d.  %s  —  %s", i, r.Name, v))
			end
			list.Text = if #lines > 0 then table.concat(lines, "\n") else "Ninguém ainda. Seja o primeiro."
		end
	end
end

function RankingService.Init(services)
	S = services
	S.Bus.Connect("Loaded", function(_, data)
		ensureWeek(data)
	end)
	S.Bus.Connect("PotatoFinished", function(player, info)
		local data = S.Data.Get(player)
		if data then
			ensureWeek(data)
			data.Weekly.Peeled += 1
			if info and not info.Spoiled and (info.AvgYield or 0) >= 0.95 - 1e-6 then
				data.Weekly.Clean = (data.Weekly.Clean or 0) + 1
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		pushed[p] = nil
	end)
	task.spawn(function()
		task.wait(10)
		while true do
			pcall(push)
			cache = {}
			pcall(refreshBoards)
			task.wait(Config.Rankings.RefreshSeconds)
		end
	end)
end

return RankingService
