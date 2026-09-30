-- MachineModels: modelos greybox das máquinas (seção 7.6). Cada máquina ocupa 1 célula (4x4 studs).
-- Espaço local: pivô no chão, centro da célula; a SAÍDA fica em +X, a entrada em -X.
-- Visual por nível: 1-4 madeira e lata, 5-7 cobre, 8-10 aço com luzes; faixa na cor de tier.
-- Peças com nome fixo são animadas no cliente (MachineAnimator): Drum, Piston, Mixer, Belt,
-- Bubbles, Smoke, Level.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local MachineModels = {}

local Mat = Enum.Material
local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local function levelStyle(level: number)
	if level >= 8 then
		return Mat.DiamondPlate, rgb(128, 132, 138), true
	elseif level >= 5 then
		return Mat.Metal, rgb(170, 104, 58), false
	end
	return Mat.CorrodedMetal, rgb(112, 96, 80), false
end

local function tierColor(level: number): Color3
	return Config.TierColors[math.clamp(math.ceil(level * 0.6), 1, #Config.TierColors)]
end

local function part(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, props: { [string]: any }?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Mat.SmoothPlastic
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props then
		for k, v in props do
			(p :: any)[k] = v
		end
	end
	p.Parent = model
	return p
end

local function emitter(parent: Instance, name: string, texture: string, color: Color3, size: number, rate: number, speed: number, lifetime: number, accel: Vector3)
	local att = Instance.new("Attachment")
	att.Name = name
	att.Parent = parent
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Texture = texture
	e.Color = ColorSequence.new(color)
	e.Size = NumberSequence.new(size, size * 1.6)
	e.Transparency = NumberSequence.new(0.3, 1)
	e.Rate = rate
	e.Speed = NumberRange.new(speed * 0.6, speed)
	e.Lifetime = NumberRange.new(lifetime * 0.7, lifetime)
	e.SpreadAngle = Vector2.new(25, 25)
	e.EmissionDirection = Enum.NormalId.Top
	e.Acceleration = accel
	e.Enabled = false
	e.Parent = att
	return att
end

local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"

-- ---------------------------------------------------------------- tipos

local BUILD = {}

function BUILD.Esteira(m: Model)
	part(m, "Frame", Vector3.new(4, 0.35, 3.4), CFrame.new(0, 0.18, 0), rgb(70, 60, 52), Mat.CorrodedMetal)
	part(m, "Belt", Vector3.new(4, 0.08, 2.8), CFrame.new(0, 0.39, 0), rgb(36, 32, 30), Mat.Rubber)
	for _, z in { -1.55, 1.55 } do
		part(m, "Rail", Vector3.new(4, 0.5, 0.2), CFrame.new(0, 0.55, z), rgb(96, 84, 72), Mat.CorrodedMetal)
	end
	-- seta ">" apontando para a saída (+X)
	part(m, "ArrowA", Vector3.new(1.1, 0.04, 0.18), CFrame.new(0.15, 0.45, -0.32) * CFrame.Angles(0, math.rad(-35), 0), rgb(214, 172, 74), Mat.SmoothPlastic, { CanCollide = false })
	part(m, "ArrowB", Vector3.new(1.1, 0.04, 0.18), CFrame.new(0.15, 0.45, 0.32) * CFrame.Angles(0, math.rad(35), 0), rgb(214, 172, 74), Mat.SmoothPlastic, { CanCollide = false })
end

function BUILD.Tambor(m: Model, level: number)
	local mat, col = levelStyle(level)
	for _, x in { -1.3, 1.3 } do
		part(m, "Leg", Vector3.new(0.4, 2, 2.8), CFrame.new(x, 1, 0), rgb(66, 54, 44), Mat.Wood)
	end
	part(m, "Drum", Vector3.new(2.4, 2.4, 2.4), CFrame.new(0, 2.4, 0) * CFrame.Angles(0, math.rad(90), 0), col, mat, { Shape = Enum.PartType.Cylinder })
	part(m, "Funnel", Vector3.new(1.6, 1, 1.6), CFrame.new(-0.6, 3.9, 0), rgb(90, 72, 56), Mat.Wood)
	part(m, "Chute", Vector3.new(1.2, 0.2, 1.2), CFrame.new(1.6, 1.2, 0) * CFrame.Angles(0, 0, math.rad(-25)), rgb(80, 70, 60), Mat.CorrodedMetal)
	part(m, "Stripe", Vector3.new(0.3, 2.45, 2.45), CFrame.new(0, 2.4, 0) * CFrame.Angles(0, math.rad(90), 0), tierColor(level), Mat.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
end

function BUILD.Lavadora(m: Model, level: number)
	local mat, col = levelStyle(level)
	local body = part(m, "Body", Vector3.new(3.2, 3, 3.2), CFrame.new(0, 1.5, 0), col, mat)
	part(m, "Window", Vector3.new(0.2, 1.8, 1.8), CFrame.new(0, 1.7, -1.62) * CFrame.Angles(0, math.rad(90), 0), rgb(120, 150, 150), Mat.Glass, { Shape = Enum.PartType.Cylinder, Transparency = 0.3 })
	part(m, "Stripe", Vector3.new(3.25, 0.3, 3.25), CFrame.new(0, 2.8, 0), tierColor(level))
	emitter(body, "Bubbles", SPARK, rgb(200, 220, 220), 0.25, 8, 2, 1.2, Vector3.new(0, 1, 0)).Position = Vector3.new(0, 1.6, 0)
end

function BUILD.Tanque(m: Model)
	part(m, "Body", Vector3.new(4.6, 3.2, 3.2), CFrame.new(0, 2.3, 0) * CFrame.Angles(0, 0, math.rad(90)), rgb(100, 88, 76), Mat.CorrodedMetal, { Shape = Enum.PartType.Cylinder })
	part(m, "Window", Vector3.new(0.2, 3.6, 0.9), CFrame.new(0, 2.3, -1.55), rgb(130, 150, 140), Mat.Glass, { Transparency = 0.35, CanCollide = false })
	part(m, "Level", Vector3.new(0.12, 0.05, 0.7), CFrame.new(0, 0.6, -1.52), rgb(230, 210, 150), Mat.SmoothPlastic, { CanCollide = false })
	local cap = part(m, "Cap", Vector3.new(0.3, 3.3, 3.3), CFrame.new(0, 4.6, 0) * CFrame.Angles(0, 0, math.rad(90)), rgb(70, 60, 52), Mat.CorrodedMetal, { Shape = Enum.PartType.Cylinder })
	local pipe = Instance.new("Attachment")
	pipe.Name = "PipeOut"
	pipe.Position = Vector3.new(0, 0.2, 0)
	pipe.Parent = cap
end

function BUILD.LinhaCorte(m: Model, level: number)
	local mat, col = levelStyle(level)
	part(m, "Bench", Vector3.new(3.4, 1.6, 2.6), CFrame.new(0, 0.8, 0), rgb(84, 66, 50), Mat.Wood)
	part(m, "Grid", Vector3.new(1.4, 0.2, 1.4), CFrame.new(0, 1.7, 0), col, mat)
	for _, x in { -0.9, 0.9 } do
		part(m, "Post", Vector3.new(0.25, 2.2, 0.25), CFrame.new(x, 2.7, 0), col, mat)
	end
	part(m, "Top", Vector3.new(2.1, 0.3, 0.5), CFrame.new(0, 3.9, 0), col, mat)
	part(m, "Piston", Vector3.new(1.2, 0.8, 1.2), CFrame.new(0, 3.1, 0), rgb(70, 64, 60), Mat.CorrodedMetal)
	part(m, "Basket", Vector3.new(1, 0.7, 1.4), CFrame.new(1.5, 1.95, 0), rgb(120, 96, 60), Mat.Fabric)
	part(m, "Stripe", Vector3.new(3.45, 0.25, 2.65), CFrame.new(0, 1.2, 0), tierColor(level))
end

function BUILD.FabricaPure(m: Model, level: number)
	local mat, col = levelStyle(level)
	part(m, "Pot", Vector3.new(2.6, 3.4, 3.4), CFrame.new(0, 1.3, 0) * CFrame.Angles(0, 0, math.rad(90)), col, mat, { Shape = Enum.PartType.Cylinder })
	part(m, "Mixer", Vector3.new(0.3, 2.2, 1.8), CFrame.new(0, 3, 0), rgb(80, 74, 68), Mat.Metal)
	local chimney = part(m, "Chimney", Vector3.new(0.7, 3, 0.7), CFrame.new(-1.3, 3.5, 1.2), rgb(60, 52, 46), Mat.CorrodedMetal)
	part(m, "Stripe", Vector3.new(0.3, 3.45, 3.45), CFrame.new(0, 2.2, 0) * CFrame.Angles(0, 0, math.rad(90)), tierColor(level), Mat.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
	emitter(chimney, "Smoke", SMOKE, rgb(170, 160, 150), 0.8, 4, 3, 2.5, Vector3.new(0.3, 1, 0)).Position = Vector3.new(0, 1.6, 0)
end

local function buildNpc(m: Model)
	local ok, npc = pcall(function()
		local desc = Instance.new("HumanoidDescription")
		desc.HeadColor = rgb(196, 160, 130)
		desc.TorsoColor = rgb(92, 84, 72)
		desc.LeftArmColor = rgb(196, 160, 130)
		desc.RightArmColor = rgb(196, 160, 130)
		desc.LeftLegColor = rgb(60, 52, 46)
		desc.RightLegColor = rgb(60, 52, 46)
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not npc then
		part(m, "Worker", Vector3.new(1.2, 3.6, 0.8), CFrame.new(-1.2, 1.8, 0), rgb(92, 84, 72))
		return
	end
	npc.Name = "Worker"
	local hum = npc:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	for _, d in npc:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
		end
	end
	local hrp = npc:FindFirstChild("HumanoidRootPart") :: BasePart?
	local height = if hrp and hum then hum.HipHeight + hrp.Size.Y / 2 else 3
	npc:PivotTo(CFrame.new(-1.3, height, 0) * CFrame.Angles(0, math.rad(-90), 0))
	-- avental curto e chapéu de papel (7.6)
	local torso = npc:FindFirstChild("UpperTorso") :: BasePart?
	local head = npc:FindFirstChild("Head") :: BasePart?
	if torso then
		local apron = part(npc, "Apron", Vector3.new(torso.Size.X * 0.8, torso.Size.Y * 0.9, 0.06), torso.CFrame * CFrame.new(0, -0.1, -torso.Size.Z / 2 - 0.04), rgb(150, 140, 120), Mat.Fabric, { CanCollide = false })
		apron.Anchored = true
	end
	if head then
		part(npc, "PaperHat", Vector3.new(head.Size.X * 1.05, 0.5, head.Size.Z * 0.7), head.CFrame * CFrame.new(0, head.Size.Y / 2 + 0.2, 0), rgb(200, 192, 176), Mat.Fabric, { CanCollide = false })
	end
	npc.Parent = m
end

function BUILD.Ajudante(m: Model, level: number)
	local mat, col = levelStyle(level)
	part(m, "Table", Vector3.new(1.6, 0.25, 2.8), CFrame.new(0.3, 2.6, 0), rgb(110, 86, 62), Mat.Wood)
	for _, z in { -1.2, 1.2 } do
		part(m, "Leg", Vector3.new(0.25, 2.5, 0.25), CFrame.new(0.3, 1.25, z), rgb(66, 52, 40), Mat.Wood)
	end
	part(m, "Bucket", Vector3.new(1, 1, 1), CFrame.new(1.5, 0.5, 1), col, mat, { Shape = Enum.PartType.Cylinder })
	part(m, "Potato", Vector3.new(0.45, 0.4, 0.6), CFrame.new(0.2, 2.95, 0), rgb(190, 140, 86), Mat.SmoothPlastic, { CanCollide = false })
	part(m, "Stripe", Vector3.new(1.62, 0.1, 2.82), CFrame.new(0.3, 2.45, 0), tierColor(level))
	buildNpc(m)
end

-- ---------------------------------------------------------------- arte final (Etapa 5)
-- ServerStorage.Models.MachineArt.<Tipo>: MeshParts normalizadas (pivô no chão, cabe na célula).
-- Aqui só se acrescenta o que a jogabilidade precisa em cima da malha.

local ARTFIX = {}

function ARTFIX.Lavadora(m: Model)
	local body = m:FindFirstChild("Body") :: BasePart?
	if body then
		emitter(body, "Bubbles", SPARK, rgb(200, 220, 220), 0.25, 8, 2, 1.2, Vector3.new(0, 1, 0))
	end
end

function ARTFIX.FabricaPure(m: Model)
	local chimney = (m:FindFirstChild("Chimney") or m:FindFirstChild("Body")) :: BasePart?
	if chimney then
		emitter(chimney, "Smoke", SMOKE, rgb(170, 160, 150), 0.8, 4, 3, 2.5, Vector3.new(0.3, 1, 0)).Position = Vector3.new(0, chimney.Size.Y / 2, 0)
	end
end

function ARTFIX.Tanque(m: Model)
	local body = m:FindFirstChild("Body") :: BasePart?
	local top = if body then body.Size.Y else 5
	-- visor de nível (a arte tem janela, mas o nível precisa ser uma peça que o servidor redimensiona)
	part(m, "Window", Vector3.new(0.5, top * 0.6, 0.12), CFrame.new(0, top * 0.5, -1.72), rgb(130, 150, 140), Mat.Glass, { Transparency = 0.45, CanCollide = false })
	part(m, "Level", Vector3.new(0.36, 0.05, 0.1), CFrame.new(0, top * 0.2, -1.7), rgb(230, 210, 150), Mat.Neon, { CanCollide = false })
	if body then
		local pipe = Instance.new("Attachment")
		pipe.Name = "PipeOut"
		pipe.Position = Vector3.new(0, body.Size.Y / 2, 0)
		pipe.Parent = body
	end
end

-- esteira: a seta de direção precisa continuar visível sobre a arte
function ARTFIX.Esteira(m: Model, _level: number, art: Instance)
	local top = (art:GetAttribute("TopY") or 0.6) + 0.03
	m:SetAttribute("BeltY", top + 0.2)
	part(m, "ArrowA", Vector3.new(1.1, 0.04, 0.18), CFrame.new(0.15, top, -0.32) * CFrame.Angles(0, math.rad(-35), 0), rgb(214, 172, 74), Mat.Neon, { CanCollide = false })
	part(m, "ArrowB", Vector3.new(1.1, 0.04, 0.18), CFrame.new(0.15, top, 0.32) * CFrame.Angles(0, math.rad(35), 0), rgb(214, 172, 74), Mat.Neon, { CanCollide = false })
end

local function applyArt(m: Model, typeId: string, level: number): boolean
	local folder = ServerStorage:FindFirstChild("Models") and ServerStorage.Models:FindFirstChild("MachineArt")
	local art = folder and folder:FindFirstChild(typeId)
	if not art then
		return false
	end
	for _, p in art:GetChildren() do
		p:Clone().Parent = m
	end
	if ARTFIX[typeId] then
		ARTFIX[typeId](m, level, art)
	end
	-- faixa na cor de tier (seção 7.1) no lado da saída
	if typeId ~= "Esteira" then
		part(m, "Stripe", Vector3.new(0.15, 0.3, 1.6), CFrame.new(1.9, 0.35, 0), tierColor(level), Mat.Neon, { CanCollide = false })
	end
	return true
end

-- ---------------------------------------------------------------- API

function MachineModels.Build(typeId: string, level: number): Model
	local m = Instance.new("Model")
	m.Name = typeId
	local base = part(m, "Base", Vector3.new(3.8, 0.1, 3.8), CFrame.new(0, 0.05, 0), rgb(50, 44, 38), Mat.SmoothPlastic, { Transparency = 1, CanCollide = false })
	m.PrimaryPart = base
	local fn = BUILD[typeId]
	if not applyArt(m, typeId, level) and fn then
		fn(m, level)
	end
	local _, _, lights = levelStyle(level)
	if lights and typeId ~= "Esteira" and typeId ~= "Tanque" then
		local lamp = part(m, "Lamp", Vector3.new(0.3, 0.3, 0.3), CFrame.new(1.6, 3.2, 1.6), rgb(120, 220, 255), Mat.Neon, { CanCollide = false })
		local l = Instance.new("PointLight")
		l.Color = rgb(120, 220, 255)
		l.Range = 6
		l.Brightness = 1
		l.Parent = lamp
	end
	-- placa de informação (nível, ritmo, estado)
	if typeId ~= "Esteira" then
		local gui = Instance.new("BillboardGui")
		gui.Name = "Info"
		gui.Size = UDim2.fromOffset(170, 44)
		gui.StudsOffsetWorldSpace = Vector3.new(0, 5.2, 0)
		gui.MaxDistance = 45
		gui.Parent = base
		local l = Instance.new("TextLabel")
		l.Name = "Label"
		l.Size = UDim2.fromScale(1, 1)
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.Oswald
		l.TextScaled = true
		l.TextColor3 = rgb(228, 214, 186)
		l.Text = ""
		l.Parent = gui
		local s = Instance.new("UIStroke")
		s.Thickness = 2
		s.Parent = l
	end
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	return m
end

return MachineModels
