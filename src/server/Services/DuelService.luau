-- DuelService: Duelos de Descasque nas arenas (World.Arena, World.Arena2, World.Arena3...).
-- Cada arena tem duas mesas frente a frente (Seats.SeatA / SeatB). Cada jogador senta numa mesa
-- (ProximityPrompt no tapete); com as duas ocupadas começa a contagem e depois o descasque:
-- o descascar livre normal, mas cada batata pronta vale 1 ponto e a próxima entra na hora.
-- No fim do tempo quem fez mais vence e leva Moedas; o guarda do Rei atira em quem perdeu.
-- Empate: os dois ganham um pouco e ninguém leva tiro. Sair da mesa / morrer / sair do jogo
-- durante a partida = desistência (o outro vence). Só jogador contra jogador.
-- Também cuida das portas: cozinha -> lobby (porta vermelha) e lobby -> cozinha.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = ReplicatedStorage.Remotes

local DuelService = {}

local S
local cfg = Config.Duel
local arenas = {} -- lista de arenas (cada uma com seu estado)
local streaks: { [Player]: number } = {}

local function notify(player: Player, text: string)
	S.Kitchen.Notify(player, text)
end

local function other(id: string): string
	return if id == "A" then "B" else "A"
end

local function alive(player: Player?): boolean
	if not player or not player.Parent then
		return false
	end
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0
end

-- Em qual arena/mesa o jogador está sentado (no máximo uma).
local function seatOf(player: Player)
	for _, A in arenas do
		for id, st in A.Seats do
			if st.Player == player then
				return A, id
			end
		end
	end
	return nil, nil
end

local function reward(player: Player, coins: number)
	if coins > 0 then
		S.Economy.Add(player, coins, "Duel")
	end
end

-- ---------------------------------------------------------------- uma arena

local function newArena(model: Model)
	local A = { Model = model, Seats = {}, State = "Idle", DebugSolo = false, DebugForce = nil }
	local seats = A.Seats

	local function setBoard()
		local a, b = seats.A, seats.B
		model:SetAttribute("DuelState", A.State)
		model:SetAttribute("NameA", a.Player and a.Player.DisplayName or "")
		model:SetAttribute("NameB", b.Player and b.Player.DisplayName or "")
		model:SetAttribute("ScoreA", a.Score)
		model:SetAttribute("ScoreB", b.Score)
		local board = model:FindFirstChild("Scoreboard")
		local gui = board and board:FindFirstChildOfClass("SurfaceGui")
		if gui then
			local function t(name: string, text: string)
				local l = gui:FindFirstChild(name, true) :: TextLabel?
				if l and l.Text ~= text then
					l.Text = text
				end
			end
			t("NameA", if a.Player then a.Player.DisplayName else "Mesa livre")
			t("NameB", if b.Player then b.Player.DisplayName else "Mesa livre")
			t("ScoreA", tostring(a.Score))
			t("ScoreB", tostring(b.Score))
			local ends = model:GetAttribute("EndsAt") or 0
			local left = math.max(0, math.ceil(ends - Workspace:GetServerTimeNow()))
			t("Status", if A.State == "Idle" then (if a.Player or b.Player then "Esperando adversário..." else "Sente numa mesa para duelar")
				elseif A.State == "Countdown" then "Prepare a faca!"
				elseif A.State == "Playing" then string.format("%d:%02d", left // 60, left % 60)
				else "Fim do duelo")
		end
	end
	A.SetBoard = setBoard

	local function standUp(id: string, keepState: boolean?)
		local st = seats[id]
		local p = st.Player
		st.Player = nil
		st.Score = 0
		st.Kd.Active = false
		st.Kd.Owner = nil
		if p then
			p:SetAttribute("InDuel", nil)
			p:SetAttribute("DuelSeat", nil)
			p:SetAttribute("DuelArena", nil)
			if not keepState and p.Parent then
				S.Peel.ReleaseHeld(p)
				S.Session.SetState(p, "Free")
			end
		end
		local prompt = st.Pad:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Enabled = true
		end
		setBoard()
	end
	A.StandUp = standUp

	local function sitDown(player: Player, id: string)
		local st = seats[id]
		local s = S.Session.Get(player)
		local data = S.Data.Get(player)
		if not s or not data then
			return
		end
		if data.Tutorial.Step < 100 then
			notify(player, "Termine o tutorial antes de duelar")
			return
		end
		if s.State ~= "Free" then
			notify(player, "Solte a batata antes de sentar na mesa")
			return
		end
		if not alive(player) then
			return
		end
		st.Player = player
		st.Score = 0
		st.Kd.Owner = player
		player:SetAttribute("InDuel", true)
		player:SetAttribute("DuelSeat", id)
		player:SetAttribute("DuelArena", model.Name)
		S.Session.SetState(player, "Duel") -- parado na mesa
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hrp then
			local top = st.Top.Position
			local pos = st.Pad.Position + Vector3.new(0, 3, 0)
			hrp.CFrame = CFrame.lookAt(pos, Vector3.new(top.X, pos.Y, top.Z))
		end
		local prompt = st.Pad:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Enabled = false
		end
		Remotes.Duel:FireClient(player, "Seated", { Seat = id, Arena = model.Name })
		setBoard()
	end
	A.SitDown = sitDown

	local function inRange(player: Player, st): boolean
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		return hrp ~= nil and (hrp.Position - st.Pad.Position).Magnitude <= cfg.SeatRange
	end

	local function shoot(victim: Player)
		local guard = model:FindFirstChild("Guard")
		local muzzle = guard and guard:FindFirstChild("Muzzle", true) :: BasePart?
		local char = victim.Character
		local torso = char and (char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")) :: BasePart?
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not torso or not hum or hum.Health <= 0 then
			return
		end
		if guard and muzzle then
			-- o guarda mira na vítima
			if guard:IsA("Model") then
				local gp = guard:GetPivot()
				guard:PivotTo(CFrame.lookAt(gp.Position, Vector3.new(torso.Position.X, gp.Position.Y, torso.Position.Z)))
			end
			-- clarão, fumaça e o rastro do tiro (só efeito; quem mata é o servidor logo abaixo)
			local flash = Instance.new("PointLight")
			flash.Color = Color3.fromRGB(255, 190, 110)
			flash.Range = 18
			flash.Brightness = 6
			flash.Parent = muzzle
			Debris:AddItem(flash, 0.12)
			local smoke = Instance.new("Smoke")
			smoke.Color = Color3.fromRGB(200, 200, 200)
			smoke.Opacity = 0.25
			smoke.RiseVelocity = 3
			smoke.Size = 1.5
			smoke.Parent = muzzle
			Debris:AddItem(smoke, 1.2)
			local from, to = muzzle.Position, torso.Position
			local tracer = Instance.new("Part")
			tracer.Anchored = true
			tracer.CanCollide = false
			tracer.CanQuery = false
			tracer.CanTouch = false
			tracer.Material = Enum.Material.Neon
			tracer.Color = Color3.fromRGB(255, 220, 150)
			tracer.Size = Vector3.new(0.12, 0.12, (to - from).Magnitude)
			tracer.CFrame = CFrame.lookAt((from + to) / 2, to)
			tracer.Parent = Workspace
			Debris:AddItem(tracer, 0.08)
			local snd = guard:FindFirstChild("Shot", true) :: Sound?
			if snd then
				snd:Play()
			end
		end
		-- empurrão para trás e cai
		local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hrp and muzzle then
			hrp.AssemblyLinearVelocity = (hrp.Position - muzzle.Position).Unit * 30 + Vector3.new(0, 12, 0)
		end
		hum.Health = 0
	end

	local function finish(winnerId: string?, reason: string)
		if A.State == "Ending" or A.State == "Idle" then
			return
		end
		A.State = "Ending"
		for _, st in seats do
			st.Kd.Active = false
		end
		local SA, SB = seats.A, seats.B
		local pA, pB = SA.Player, SB.Player
		-- quem ainda está na mesa larga a batata
		for _, p in { pA, pB } do
			if p and p.Parent then
				S.Peel.ReleaseHeld(p)
				if alive(p) then
					S.Session.SetState(p, "Duel")
				end
			end
		end
		if winnerId == nil and reason == "Time" then
			if SA.Score > SB.Score then
				winnerId = "A"
			elseif SB.Score > SA.Score then
				winnerId = "B"
			end
		end
		if A.DebugForce then
			local real = if pA then "A" else "B"
			winnerId = if A.DebugForce == "Win" then real else other(real)
		end
		local scoreText = string.format("%d x %d", SA.Score, SB.Score)
		if winnerId == nil then
			-- empate
			for _, p in { pA, pB } do
				if p and p.Parent then
					streaks[p] = 0
					reward(p, cfg.TieCoins)
					Remotes.Duel:FireClient(p, "Result", { Outcome = "Tie", Score = scoreText, Coins = cfg.TieCoins })
				end
			end
		else
			local W, L = seats[winnerId], seats[other(winnerId)]
			local winner, loser = W.Player, L.Player
			if winner and winner.Parent then
				streaks[winner] = (streaks[winner] or 0) + 1
				local bonus = math.min((streaks[winner] - 1) * cfg.StreakBonus, cfg.MaxStreakBonus)
				local coins = cfg.WinCoins + bonus
				if S.Monetization.HasPass(winner, "Duelista") then
					coins = math.floor(coins * (1 + Config.GamePassesById.Duelista.DuelCoinBonus))
				end
				reward(winner, coins)
				local data = S.Data.Get(winner)
				if data then
					data.Stats.DuelWins = (data.Stats.DuelWins or 0) + 1
				end
				if S.Ranking and S.Ranking.AddDuelWin then
					S.Ranking.AddDuelWin(winner)
				end
				if S.Retention and S.Retention.AddXP then
					S.Retention.AddXP(winner, 40)
				end
				S.Bus.Fire("DuelWon", winner)
				Remotes.Duel:FireClient(winner, "Result", {
					Outcome = "Win", Score = scoreText, Coins = coins, Streak = streaks[winner],
					Reason = reason, Opponent = loser and loser.DisplayName or "",
				})
			end
			if loser and loser.Parent then
				streaks[loser] = 0
				Remotes.Duel:FireClient(loser, "Result", {
					Outcome = "Lose", Score = scoreText, Reason = reason, Opponent = winner and winner.DisplayName or "",
				})
			end
			-- avisa quem está assistindo por perto
			if winner then
				for _, p in Players:GetPlayers() do
					if p ~= winner and p ~= loser then
						local hrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
						if hrp and (hrp.Position - model:GetPivot().Position).Magnitude < 60 then
							notify(p, winner.DisplayName .. " venceu o duelo (" .. scoreText .. ")")
						end
					end
				end
			end
			if loser and alive(loser) and reason ~= "Left" then
				task.delay(cfg.ShotDelay, function()
					local LA = seatOf(loser)
					if alive(loser) and LA == A then
						shoot(loser)
					end
				end)
			end
		end
		setBoard()
		task.delay(cfg.ShotDelay + 1.6, function()
			for _, id in { "A", "B" } do
				local p = seats[id].Player
				standUp(id, not alive(p))
			end
			model:SetAttribute("EndsAt", 0)
			A.DebugSolo, A.DebugForce = false, nil
			A.State = "Idle"
			setBoard()
		end)
	end
	A.Finish = finish

	local function startMatch()
		A.State = "Countdown"
		local now = Workspace:GetServerTimeNow()
		model:SetAttribute("CountdownEnd", now + cfg.Countdown)
		model:SetAttribute("EndsAt", now + cfg.Countdown + cfg.Duration)
		for _, st in seats do
			st.Score = 0
			if st.Player then
				Remotes.Duel:FireClient(st.Player, "Countdown", { At = now + cfg.Countdown, Ends = now + cfg.Countdown + cfg.Duration })
			end
		end
		setBoard()
		task.wait(cfg.Countdown)
		if A.State ~= "Countdown" then
			return
		end
		-- alguém saiu durante a contagem?
		for id, st in seats do
			if not alive(st.Player) and not (A.DebugSolo and st.Player == nil) then
				A.State = "Playing"
				finish(other(id), "Left")
				return
			end
		end
		A.State = "Playing"
		for _, st in seats do
			if st.Player then
				st.Kd.Active = true
				S.Peel.DuelGive(st.Player, st.Kd)
				Remotes.Duel:FireClient(st.Player, "Start", { Ends = model:GetAttribute("EndsAt") })
			end
		end
		setBoard()
	end

	function A.Tick()
		if A.State == "Idle" then
			-- quem sentou e foi embora / morreu libera a mesa
			for id, st in seats do
				if st.Player and (not alive(st.Player) or not inRange(st.Player, st)) then
					standUp(id, not alive(st.Player))
				end
			end
			if (seats.A.Player and seats.B.Player) or (A.DebugSolo and (seats.A.Player or seats.B.Player)) then
				A.State = "Countdown"
				task.spawn(startMatch)
				return
			end
		elseif A.State == "Countdown" or A.State == "Playing" then
			for id, st in seats do
				local p = st.Player
				if A.DebugSolo and p == nil then
					continue
				end
				if not alive(p) or not inRange(p :: Player, st) then
					finish(other(id), "Left")
					return
				end
				if A.State == "Playing" then
					local s = S.Session.Get(p :: Player)
					if s and s.State ~= "Peeling" then
						S.Peel.DuelGive(p :: Player, st.Kd) -- algo tirou a batata da mão: devolve
					end
				end
			end
			if A.State == "Playing" and Workspace:GetServerTimeNow() >= (model:GetAttribute("EndsAt") or 0) then
				finish(nil, "Time")
				return
			end
		end
		setBoard()
	end

	-- mesas
	for _, id in { "A", "B" } do
		local m = (model :: any).Seats:FindFirstChild("Seat" .. id) :: Model
		local top = (m :: any).Station.Table.TableTop :: BasePart
		local pad = (m :: any).Pad :: BasePart
		local Kd = { IsDuel = true, TableTop = top, Model = m, Loose = {}, Active = false, Owner = nil }
		local st = { Model = m, Pad = pad, Top = top, Player = nil, Kd = Kd, Score = 0 }
		Kd.OnFinish = function(player: Player)
			if A.State == "Playing" and st.Player == player then
				st.Score += 1
				setBoard()
				for _, o in seats do
					if o.Player then
						Remotes.Duel:FireClient(o.Player, "Score", { A = seats.A.Score, B = seats.B.Score })
					end
				end
			end
		end
		seats[id] = st
		local prompt = pad:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Triggered:Connect(function(player: Player)
				if seatOf(player) then
					return
				end
				if A.State ~= "Idle" then
					notify(player, "Duelo em andamento: espere terminar")
					return
				end
				if seats[id].Player then
					return
				end
				sitDown(player, id)
			end)
		end
	end
	setBoard()
	return A
end

-- ---------------------------------------------------------------- portas cozinha <-> lobby

-- Leva o jogador (com a tela escurecendo no cliente). Só andando livre ou segurando batata.
local function travel(player: Player, cf: CFrame)
	local s = S.Session.Get(player)
	local char = player.Character
	if not s or not char or not alive(player) or seatOf(player) then
		return
	end
	if s.State ~= "Free" and s.State ~= "Holding" then
		notify(player, "Termine o que está fazendo primeiro")
		return
	end
	Remotes.Duel:FireClient(player, "Travel")
	task.wait(0.3)
	if char.Parent and alive(player) then
		char:PivotTo(cf + Vector3.new(0, 3, 0))
	end
end

local function hookDoors()
	local world = Workspace:FindFirstChild("World")
	local hub = world and world:FindFirstChild("Hub")
	local lobby = hub and hub:FindFirstChild("LobbyArrival") :: BasePart?
	if lobby then
		for _, d in Workspace:WaitForChild("Kitchens"):GetDescendants() do
			if d:IsA("ProximityPrompt") and d.Name == "LobbyPrompt" then
				local kitchen = d:FindFirstAncestor("Kitchens") and d:FindFirstAncestorWhichIsA("Model")
				while kitchen and kitchen:GetAttribute("KitchenIndex") == nil do
					kitchen = kitchen:FindFirstAncestorWhichIsA("Model")
				end
				d.Triggered:Connect(function(player: Player)
					-- só de dentro da cozinha (a porta fica na parede)
					if kitchen and not S.Kitchen.IsInside(kitchen, player) then
						return
					end
					travel(player, lobby.CFrame)
				end)
			end
		end
	end
	local back = hub and hub:FindFirstChild("KitchenDoor")
	local pr = back and back:FindFirstChild("KitchenPrompt", true) :: ProximityPrompt?
	if pr then
		pr.Triggered:Connect(function(player: Player)
			local K = S.Kitchen.GetKitchen(player) or S.Kitchen.GetOwnedKitchen(player)
			local spawn = K and K.Model and K.Model:FindFirstChild("KitchenSpawn", true) :: BasePart?
			if spawn then
				travel(player, CFrame.new(spawn.Position))
			else
				notify(player, "Você ainda não tem cozinha")
			end
		end)
	end
end

function DuelService.Init(services)
	S = services
	local world = Workspace:WaitForChild("World", 10)
	if world then
		for _, m in world:GetChildren() do
			if m:IsA("Model") and m:FindFirstChild("Seats") and m.Name:match("^Arena") then
				table.insert(arenas, newArena(m))
			end
		end
		table.sort(arenas, function(a, b)
			return a.Model.Name < b.Model.Name
		end)
	end
	if #arenas == 0 then
		warn("[Duel] nenhuma arena em World: duelo desligado")
	end
	hookDoors()
	Remotes.Duel.OnServerEvent:Connect(function(player: Player, action: any)
		if action == "Leave" then
			local A, id = seatOf(player)
			if A and id and A.State == "Idle" then
				A.StandUp(id)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		streaks[player] = nil
		local A, id = seatOf(player)
		if A and id then
			if A.State == "Countdown" or A.State == "Playing" then
				A.Finish(other(id), "Left")
			end
			if A.State == "Idle" then
				A.StandUp(id, true)
			end
		end
	end)
	if RunService:IsStudio() and arenas[1] then
		-- teste no Studio: Workspace.SpudDebugDuel = "Win" / "Lose" / "Time" senta o primeiro jogador
		-- na mesa A da primeira arena e começa com a mesa B vazia (sem adversário e sem NPC)
		Workspace:GetAttributeChangedSignal("SpudDebugDuel"):Connect(function()
			local v = Workspace:GetAttribute("SpudDebugDuel")
			local p = Players:GetPlayers()[1]
			local A = arenas[1]
			if typeof(v) ~= "string" or v == "" or not p or A.State ~= "Idle" then
				return
			end
			A.DebugSolo = true
			A.DebugForce = if v == "Time" then nil else v
			if not seatOf(p) then
				A.SitDown(p, "A")
			end
		end)
	end
	task.spawn(function()
		while true do
			task.wait(0.25)
			for _, A in arenas do
				local ok, err = pcall(A.Tick)
				if not ok then
					warn("[Duel]", A.Model.Name, err)
				end
			end
		end
	end)
end

return DuelService
