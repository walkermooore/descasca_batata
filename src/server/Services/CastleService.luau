-- CastleService: zona proibida em frente ao castelo do Rei (World.KingsHall).
-- Quem entra na zona vê a tela vermelha com a contagem (atributo CastleShootAt); se continuar lá por
-- Config.Castle.Grace segundos, o guarda mais próximo do castelo (World.Guards com o
-- atributo CastleGuard) atira — mesmo efeito do duelo: clarão, rastro e som — e o jogador morre.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage.Shared.Config)

local CastleService = {}

local S
local cfg = Config.Castle
local enteredAt: { [Player]: number } = {}

local function inZone(pos: Vector3): boolean
	return pos.Z < cfg.ZoneMaxZ and pos.X > cfg.ZoneMinX and pos.X < cfg.ZoneMaxX
end

local function castleGuards(): { Model }
	local list = {}
	local folder = Workspace:FindFirstChild("World") and Workspace.World:FindFirstChild("Guards")
	if folder then
		for _, g in folder:GetChildren() do
			if g:IsA("Model") and g:GetAttribute("CastleGuard") and g:FindFirstChild("Muzzle") then
				table.insert(list, g)
			end
		end
	end
	return list
end

local function shoot(victim: Player)
	local char = victim.Character
	local torso = char and (char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")) :: BasePart?
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not torso or not hum or hum.Health <= 0 then
		return
	end
	local guard, best = nil, math.huge
	for _, g in castleGuards() do
		local d = (g:GetPivot().Position - torso.Position).Magnitude
		if d < best then
			guard, best = g, d
		end
	end
	local muzzle = guard and guard:FindFirstChild("Muzzle") :: BasePart?
	if guard and muzzle then
		-- o guarda mira na vítima
		local gp = guard:GetPivot()
		guard:PivotTo(CFrame.lookAt(gp.Position, Vector3.new(torso.Position.X, gp.Position.Y, torso.Position.Z)))
		task.delay(2, function()
			if guard.Parent then
				guard:PivotTo(gp) -- volta para a posição de guarda
			end
		end)
		-- clarão, fumaça e o rastro do tiro
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
		local snd = muzzle:FindFirstChild("Shot") :: Sound?
		if snd then
			snd:Play()
		end
		-- empurrão para trás
		local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hrp then
			hrp.AssemblyLinearVelocity = (hrp.Position - muzzle.Position).Unit * 30 + Vector3.new(0, 12, 0)
		end
	end
	hum.Health = 0
	S.Kitchen.Notify(victim, "O guarda do Rei avisou...")
end

local function scan()
	local now = os.clock()
	for _, p in Players:GetPlayers() do
		local char = p.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hrp or not hum or hum.Health <= 0 or not inZone(hrp.Position) then
			if enteredAt[p] then
				enteredAt[p] = nil
				p:SetAttribute("CastleShootAt", nil)
			end
			continue
		end
		local t = enteredAt[p]
		if not t then
			enteredAt[p] = now
			-- o cliente mostra a tela vermelha com a contagem até o tiro
			p:SetAttribute("CastleShootAt", Workspace:GetServerTimeNow() + cfg.Grace)
		elseif now - t >= cfg.Grace then
			enteredAt[p] = nil
			p:SetAttribute("CastleShootAt", nil)
			shoot(p)
		end
	end
end

function CastleService.Init(services)
	S = services
	Players.PlayerRemoving:Connect(function(p)
		enteredAt[p] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(0.1)
			scan()
		end
	end)
end

return CastleService
