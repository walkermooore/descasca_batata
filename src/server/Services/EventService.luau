-- EventService: Pedido Gigante do Rei (seção 5) e Corrida de Descascar.
--
-- Pedido Gigante: a cada 20 min, meta comum de batatas entregues por todas as cozinhas do
-- servidor; o Rei "cresce" em 5 etapas conforme a entrega; ao bater a meta, todos ganham um baú.
-- Estado em atributos do Workspace: GiantActive, GiantProgress, GiantGoal, GiantEnds, GiantNext.
-- (Evento por servidor. A seção 10 cita MemoryStore: fica pronto para somar entre servidores
-- se o design quiser um evento global; hoje não é necessário.)
--
-- Corrida: fila (portal do hub ou painel Social), 2 a 4 jogadores, 60 s. Pontos = soma do
-- rendimento das faixas descascadas à mão. Prêmios por posição e ranking semanal.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = ReplicatedStorage.Remotes

local EventService = {}

local S

-- ---------------------------------------------------------------- Pedido Gigante

local giant = { Active = false, Progress = 0, Goal = 0, Ends = 0, Step = 0 }
local kingBaseScale = nil

local function king(): Model?
	local hall = Workspace:FindFirstChild("World") and Workspace.World:FindFirstChild("KingsHall")
	return hall and hall:FindFirstChild("King") or (hall and hall:FindFirstChild("KingGreybox"))
end

local function setKingStep(step: number)
	local k = king()
	if not k then
		return
	end
	kingBaseScale = kingBaseScale or k:GetScale()
	local cfg = Config.GiantOrder
	k:ScaleTo(kingBaseScale * (1 + (cfg.KingMaxScale - 1) * step / cfg.KingSteps))
	k:SetAttribute("GrowStep", step)
end

local function publishGiant()
	Workspace:SetAttribute("GiantActive", giant.Active)
	Workspace:SetAttribute("GiantProgress", giant.Progress)
	Workspace:SetAttribute("GiantGoal", giant.Goal)
	Workspace:SetAttribute("GiantEnds", giant.Ends)
end

local function startGiant()
	local cfg = Config.GiantOrder
	giant.Active = true
	giant.Progress = 0
	giant.Goal = math.max(cfg.MinGoal, cfg.GoalPerPlayer * #Players:GetPlayers())
	giant.Ends = Workspace:GetServerTimeNow() + cfg.Duration
	giant.Step = 0
	setKingStep(0)
	publishGiant()
	Remotes.Reward:FireAllClients("GiantStart", { Goal = giant.Goal, Seconds = cfg.Duration })
end

local function endGiant(success: boolean)
	giant.Active = false
	publishGiant()
	if success then
		local cfg = Config.GiantOrder
		for _, p in Players:GetPlayers() do
			if S.Data.Get(p) then
				local amount = math.max(cfg.RewardMin, S.Machines.AutoCoinsPerMinute(p) * cfg.RewardMinutes)
				local paid = S.Economy.Add(p, amount, "GiantOrder")
				Remotes.Reward:FireClient(p, "GiantDone", { Amount = paid })
			end
		end
	else
		Remotes.Reward:FireAllClients("GiantFailed", {})
	end
	task.delay(8, function()
		if not giant.Active then
			setKingStep(0)
		end
	end)
end

local function onDelivered(_player: Player, _amount: number, count: number)
	if not giant.Active then
		return
	end
	giant.Progress += count
	local step = math.min(Config.GiantOrder.KingSteps, math.floor(giant.Progress / giant.Goal * Config.GiantOrder.KingSteps))
	if step ~= giant.Step then
		giant.Step = step
		setKingStep(step)
	end
	publishGiant()
	if giant.Progress >= giant.Goal then
		endGiant(true)
	end
end

-- Studio: começa o evento já (teste)
function EventService.DebugStartGiant()
	startGiant()
end

-- ---------------------------------------------------------------- Corrida de Descascar

local queue: { Player } = {}
local race = { State = "Idle", Players = {}, Scores = {}, Ends = 0, StartsAt = 0 }

local function setRaceAttrs(p: Player, state: string?)
	p:SetAttribute("RaceState", state)
	p:SetAttribute("RaceScore", race.Scores[p] or 0)
	p:SetAttribute("RaceEnds", if state == "Running" then race.Ends elseif state == "Countdown" then race.StartsAt else nil)
end

local function publishRace()
	Workspace:SetAttribute("RaceState", race.State)
	Workspace:SetAttribute("RaceQueue", #queue)
	local parts = {}
	for _, p in race.Players do
		table.insert(parts, p.DisplayName .. "=" .. string.format("%.1f", race.Scores[p] or 0))
	end
	Workspace:SetAttribute("RaceBoard", table.concat(parts, ";"))
end

-- quem entrou pelo portal precisa ficar perto dele enquanto espera na fila
local joinedAtPortal: { [Player]: boolean } = {}

function EventService.Join(player: Player, atPortal: boolean?)
	if table.find(queue, player) or table.find(race.Players, player) then
		return { Ok = false, Reason = "Você já está na corrida" }
	end
	table.insert(queue, player)
	joinedAtPortal[player] = atPortal == true or nil
	setRaceAttrs(player, if race.State == "Countdown" then "Countdown" else "Queued")
	publishRace()
	S.Kitchen.Notify(player, "Na fila da Corrida de Descascar (" .. #queue .. " na fila)")
	return { Ok = true }
end

-- Sair da corrida = sair da fila: tira o jogador da fila e, se a corrida já começou, da corrida.
function EventService.Leave(player: Player)
	joinedAtPortal[player] = nil
	local left = false
	local i = table.find(queue, player)
	if i then
		table.remove(queue, i)
		left = true
	end
	local j = table.find(race.Players, player)
	if j then
		table.remove(race.Players, j)
		race.Scores[player] = nil
		left = true
	end
	if left then
		if player.Parent then
			setRaceAttrs(player, nil)
		end
		if race.State == "Running" and #race.Players == 0 then
			race.State = "Idle"
			race.Scores = {}
		end
		publishRace()
	end
	return { Ok = left }
end

local function portalPad(): BasePart?
	local hub = Workspace:FindFirstChild("World") and Workspace.World:FindFirstChild("Hub")
	local portal = hub and hub:FindFirstChild("RacePortal")
	return portal and portal:FindFirstChild("Pad") :: BasePart?
end

-- quem entrou pelo portal e se afastou dele antes da corrida começar sai da fila
local function dropWanderers()
	if race.State ~= "Idle" then
		return
	end
	local pad = portalPad()
	if not pad then
		return
	end
	for i = #queue, 1, -1 do
		local p = queue[i]
		local hrp = joinedAtPortal[p] and p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hrp and (hrp.Position - pad.Position).Magnitude > Config.Race.LeaveDistance then
			EventService.Leave(p)
			S.Kitchen.Notify(p, "Você se afastou do portal e saiu da fila da corrida.")
		end
	end
end

local function finishRace()
	local results = {}
	for _, p in race.Players do
		table.insert(results, { Player = p, Score = race.Scores[p] or 0 })
	end
	table.sort(results, function(a, b)
		return a.Score > b.Score
	end)
	local board = {}
	for i, r in results do
		table.insert(board, { Name = r.Player.DisplayName, Score = r.Score })
	end
	for i, r in results do
		if r.Player.Parent then
			local prize = if r.Score > 0 then (Config.Race.Rewards[i] or 0) else 0
			local paid = if prize > 0 then S.Economy.Add(r.Player, prize, "Race") else 0
			S.Ranking.SubmitRace(r.Player, r.Score)
			S.Bus.Fire("RaceFinished", r.Player)
			setRaceAttrs(r.Player, nil)
			Remotes.Reward:FireClient(r.Player, "RaceResult", { Rank = i, Score = r.Score, Prize = paid, Board = board })
		end
	end
	race.State = "Idle"
	race.Players = {}
	race.Scores = {}
	publishRace()
end

local function raceLoop()
	while true do
		task.wait(1)
		-- limpa quem saiu
		for i = #queue, 1, -1 do
			if not queue[i].Parent then
				table.remove(queue, i)
			end
		end
		dropWanderers()
		local now = Workspace:GetServerTimeNow()
		if race.State == "Idle" and #queue >= Config.Race.MinPlayers then
			race.State = "Countdown"
			race.StartsAt = now + Config.Race.LobbySeconds
			for _, p in queue do
				setRaceAttrs(p, "Countdown")
			end
			publishRace()
		elseif race.State == "Countdown" then
			if #queue < Config.Race.MinPlayers then
				race.State = "Idle"
				for _, p in queue do
					setRaceAttrs(p, "Queued")
				end
				publishRace()
			elseif now >= race.StartsAt then
				race.State = "Running"
				race.Ends = now + Config.Race.Duration
				race.Players = {}
				while #queue > 0 and #race.Players < Config.Race.MaxPlayers do
					table.insert(race.Players, table.remove(queue, 1))
				end
				for _, p in race.Players do
					race.Scores[p] = 0
					joinedAtPortal[p] = nil
					setRaceAttrs(p, "Running")
					S.Kitchen.Notify(p, "VALENDO! Descasque o máximo com precisão em 60 s")
				end
				-- quem não coube nesta corrida volta a esperar a próxima
				for _, p in queue do
					setRaceAttrs(p, "Queued")
				end
				publishRace()
			end
		elseif race.State == "Running" and now >= race.Ends then
			finishRace()
		end
	end
end

local function onStrips(player: Player, k: number, yield: number)
	if race.State == "Running" and race.Scores[player] then
		race.Scores[player] += k * yield
		player:SetAttribute("RaceScore", race.Scores[player])
		publishRace()
	end
end

function EventService.Init(services)
	S = services
	S.Bus.Connect("Delivered", onDelivered)
	S.Bus.Connect("StripsPeeled", onStrips)
	Players.PlayerRemoving:Connect(function(p)
		EventService.Leave(p)
	end)
	publishGiant()
	publishRace()
	task.spawn(raceLoop)
	task.spawn(function()
		local cfg = Config.GiantOrder
		local nextAt = Workspace:GetServerTimeNow() + cfg.FirstDelay
		while true do
			Workspace:SetAttribute("GiantNext", nextAt)
			task.wait(1)
			local now = Workspace:GetServerTimeNow()
			if giant.Active and now >= giant.Ends then
				endGiant(false)
				nextAt = now + cfg.Interval
			elseif not giant.Active and now >= nextAt and #Players:GetPlayers() > 0 then
				startGiant()
				nextAt = now + cfg.Interval
			end
		end
	end)
end

return EventService
