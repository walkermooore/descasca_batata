-- AmbienceController: trilha (muda de ritmo no Pedido Gigante e na Corrida) e animações
-- procedurais do Rei Glutão (comer, reclamar, comemorar) e do Chef Tubérculo (apontar, aplaudir).
-- Etapa 5: sem rig de animação ainda, as animações são feitas com tweens de CFrame no cliente.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local player = Players.LocalPlayer

local Ambience = {}

local C
local tracks = {}
local current: string? = nil

-- ---------------------------------------------------------------- música

local function track(name: string): Sound
	if not tracks[name] then
		local def = Config.Music[name]
		local s = Instance.new("Sound")
		s.Name = "Music" .. name
		s.SoundId = def.Id
		s.Looped = true
		s.Volume = 0
		s:SetAttribute("Target", def.Volume)
		s.Parent = SoundService
		tracks[name] = s
	end
	return tracks[name]
end

local function play(name: string)
	if current == name then
		return
	end
	current = name
	for n, s in tracks do
		if n ~= name then
			TweenService:Create(s, TweenInfo.new(Config.Music.Fade), { Volume = 0 }):Play()
		end
	end
	local s = track(name)
	if not s.IsPlaying then
		s:Play()
	end
	TweenService:Create(s, TweenInfo.new(Config.Music.Fade), { Volume = s:GetAttribute("Target") }):Play()
end

local function chooseMusic()
	local event = Workspace:GetAttribute("GiantActive") == true or player:GetAttribute("RaceState") == "Running"
	play(if event then "Event" else "Main")
end

-- ---------------------------------------------------------------- Rei

local function kingModel(): Model?
	local hall = Workspace:FindFirstChild("World") and Workspace.World:FindFirstChild("KingsHall")
	return hall and (hall:FindFirstChild("King") or hall:FindFirstChild("KingGreybox")) :: Model?
end

local kingBusy = false
-- comer: o Rei se inclina para a frente e volta, 3 vezes
function Ambience.KingEat()
	local k = kingModel()
	if not k or kingBusy then
		return
	end
	kingBusy = true
	task.spawn(function()
		local base = k:GetPivot()
		for _ = 1, 3 do
			for a = 0, 1, 0.1 do
				k:PivotTo(base * CFrame.Angles(math.rad(-8) * math.sin(a * math.pi), 0, 0))
				task.wait(0.02)
			end
		end
		k:PivotTo(base)
		kingBusy = false
	end)
end

-- reclamar: sacode de um lado para o outro
function Ambience.KingShake()
	local k = kingModel()
	if not k or kingBusy then
		return
	end
	kingBusy = true
	task.spawn(function()
		local base = k:GetPivot()
		for i = 1, 12 do
			k:PivotTo(base * CFrame.Angles(0, 0, math.rad(4) * math.sin(i * 1.3)))
			task.wait(0.04)
		end
		k:PivotTo(base)
		kingBusy = false
	end)
end

-- ---------------------------------------------------------------- Chef

local function chefModel(): Model?
	local K = C.Kitchen.GetMine()
	return K and K:FindFirstChild("Chef") :: Model?
end

local chefBase: CFrame? = nil
local chefModelRef: Model? = nil

-- aplaudir: pulinhos
function Ambience.ChefCheer()
	local m = chefModel()
	if not m then
		return
	end
	task.spawn(function()
		local base = m:GetPivot()
		for i = 1, 3 do
			for a = 0, 1, 0.12 do
				m:PivotTo(base * CFrame.new(0, 0.5 * math.sin(a * math.pi), 0))
				task.wait(0.02)
			end
		end
		m:PivotTo(base)
	end)
end

-- o Chef vira na direção do objetivo do tutorial (apontar) ou do jogador
local function chefLook()
	local m = chefModel()
	if m ~= chefModelRef then
		chefModelRef = m
		chefBase = m and m:GetPivot()
	end
	if not m or not chefBase then
		return
	end
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp or (hrp.Position - chefBase.Position).Magnitude > 30 then
		return
	end
	local target = hrp.Position
	local flat = Vector3.new(target.X, chefBase.Position.Y, target.Z)
	local want = CFrame.lookAt(chefBase.Position, flat) * (m:GetAttribute("FaceOffset") and CFrame.Angles(0, math.rad(m:GetAttribute("FaceOffset")), 0) or CFrame.identity) -- frente do modelo = -Z
	local idle = CFrame.new(0, 0.06 * math.sin(os.clock() * 2), 0)
	m:PivotTo(m:GetPivot():Lerp(want * idle, 0.08))
end

-- ---------------------------------------------------------------- holofotes das torres
-- Cada torre varre o pátio devagar (só no cliente: nada disso precisa replicar).

local searchlights = {}

local function collectSearchlights()
	local camp = Workspace:WaitForChild("World"):WaitForChild("Camp", 10)
	local towers = camp and camp:WaitForChild("Towers", 10)
	if not towers then
		return
	end
	for _, t in towers:GetChildren() do
		local pivot = t:WaitForChild("SearchPivot", 5) :: BasePart?
		if pivot then
			local parts = {}
			for _, n in { "SearchLight", "Lens", "BeamEnd" } do
				local p = t:WaitForChild(n, 5) :: BasePart?
				if p then
					table.insert(parts, { Part = p, Offset = CFrame.new(pivot.Position):ToObjectSpace(p.CFrame) })
				end
			end
			table.insert(searchlights, {
				Origin = pivot.Position,
				Yaw = t:GetAttribute("BaseYaw") or 0,
				Phase = t:GetAttribute("Phase") or 0,
				Parts = parts,
			})
		end
	end
end

local function sweep()
	local t = os.clock()
	for _, s in searchlights do
		local yaw = s.Yaw + math.rad(40) * math.sin(t * 0.25 + s.Phase)
		local pitch = math.rad(-18) + math.rad(6) * math.sin(t * 0.4 + s.Phase)
		local rot = CFrame.new(s.Origin) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
		for _, it in s.Parts do
			it.Part.CFrame = rot * it.Offset
		end
	end
end

function Ambience.Init(controllers)
	C = controllers
	track("Main")
	track("Event")
	chooseMusic()
	Workspace:GetAttributeChangedSignal("GiantActive"):Connect(chooseMusic)
	player:GetAttributeChangedSignal("RaceState"):Connect(chooseMusic)
	Remotes.Delivered.OnClientEvent:Connect(function()
		Ambience.KingEat()
	end)
	Remotes.Reward.OnClientEvent:Connect(function(kind)
		if kind == "GiantFailed" or kind == "OrderFailed" then
			Ambience.KingShake()
		elseif kind == "GiantDone" or kind == "Order" then
			Ambience.KingEat()
		end
	end)
	Remotes.PeelResult.OnClientEvent:Connect(function(r)
		if r.Done and (player:GetAttribute("TutorialStep") or 100) < 100 then
			Ambience.ChefCheer()
		end
	end)
	RunService.Heartbeat:Connect(chefLook)
	task.spawn(function()
		collectSearchlights()
		RunService.Heartbeat:Connect(sweep)
	end)
end

return Ambience
