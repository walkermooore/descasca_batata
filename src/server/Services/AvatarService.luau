-- AvatarService: visual greybox do equipamento no avatar (seções 7.4 e 7.8).
--   * Avental e gorro de cozinha gastos (todo aprendiz ganha ao entrar).
--   * Ferramenta equipada no cinto, com o cabo na cor de tier.
--   * Luvas de borracha mostarda gastas, mochila do aspirador (tanque, alças e mangueira).
-- Etapa 5 troca tudo por MeshParts do atlas de ferramentas.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local AvatarService = {}

local S

local function gearPart(folder: Instance, anchor: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CFrame = anchor.CFrame * offset
	local w = Instance.new("WeldConstraint")
	w.Part0 = anchor
	w.Part1 = p
	w.Parent = p
	p.Parent = folder
	return p
end

local function buildTool(folder: Instance, belt: BasePart, toolId: string)
	local tool = Config.ToolsById[toolId] or Config.Tools[1]
	local tierColor = Config.TierColors[tool.Tier] or Config.TierColors[1]
	local side = CFrame.new(-belt.Size.X / 2 - 0.12, -0.1, 0)
	local metal = Color3.fromRGB(150, 150, 150)
	local rust = Color3.fromRGB(120, 86, 60)
	if toolId == "Laser" then
		gearPart(folder, belt, "Handle", Vector3.new(0.22, 0.8, 0.22), side * CFrame.new(0, 0.1, 0), Color3.fromRGB(200, 205, 215), Enum.Material.Metal)
		gearPart(folder, belt, "Tip", Vector3.new(0.18, 0.3, 0.18), side * CFrame.new(0, -0.45, 0), Color3.fromRGB(255, 80, 70), Enum.Material.Glass)
		gearPart(folder, belt, "TierRing", Vector3.new(0.26, 0.1, 0.26), side * CFrame.new(0, 0.4, 0), tierColor, Enum.Material.Neon)
		return
	end
	gearPart(folder, belt, "Handle", Vector3.new(0.2, 0.55, 0.2), side * CFrame.new(0, 0.25, 0), tierColor, Enum.Material.Wood)
	local bladeColor = if tool.Tier == 1 then rust else metal
	if toolId == "DescascadorY" or toolId == "DescascadorDuplo" then
		gearPart(folder, belt, "ArmL", Vector3.new(0.06, 0.4, 0.06), side * CFrame.new(0, -0.2, -0.12) * CFrame.Angles(math.rad(-20), 0, 0), metal, Enum.Material.Metal)
		gearPart(folder, belt, "ArmR", Vector3.new(0.06, 0.4, 0.06), side * CFrame.new(0, -0.2, 0.12) * CFrame.Angles(math.rad(20), 0, 0), metal, Enum.Material.Metal)
		gearPart(folder, belt, "Blade", Vector3.new(0.05, 0.05, 0.4), side * CFrame.new(0, -0.42, 0), bladeColor, Enum.Material.Metal)
		if toolId == "DescascadorDuplo" then
			gearPart(folder, belt, "Blade2", Vector3.new(0.05, 0.05, 0.4), side * CFrame.new(0, -0.34, 0), bladeColor, Enum.Material.Metal)
		end
	else
		local len = if toolId == "LaminaVapor" then 0.6 else 0.5
		gearPart(folder, belt, "Blade", Vector3.new(0.05, len, 0.16), side * CFrame.new(0, -len / 2, 0), bladeColor, Enum.Material.Metal)
		if toolId == "LaminaVapor" then
			gearPart(folder, belt, "Tank", Vector3.new(0.3, 0.2, 0.2), side * CFrame.new(0, 0.55, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(181, 140, 70), Enum.Material.Metal, Enum.PartType.Cylinder)
		end
	end
end

-- Luva de trabalho de borracha mostarda, gasta: casca sobre a mão, pontas sujas de terra e
-- punho largo e mais escuro no antebraço, com a borda enrolada.
local RUBBER = Color3.fromRGB(176, 140, 50)
local RUBBER_DARK = Color3.fromRGB(122, 94, 38)
local GRIME = Color3.fromRGB(92, 72, 40)

local function buildGlove(folder: Instance, hand: BasePart?, lowerArm: BasePart?)
	if not hand then
		return
	end
	local s = hand.Size
	gearPart(folder, hand, "Glove", Vector3.new(s.X * 1.08, s.Y * 1.2, s.Z * 1.08), CFrame.new(0, 0.02, 0), RUBBER, Enum.Material.Rubber)
	gearPart(folder, hand, "GloveTips", Vector3.new(s.X * 1.1, s.Y * 0.4, s.Z * 1.1), CFrame.new(0, -s.Y * 0.42, 0), GRIME, Enum.Material.Rubber)
	-- frisos de aderência no dorso
	for i = -1, 1 do
		gearPart(folder, hand, "GloveRib", Vector3.new(s.X * 1.1, 0.03, s.Z * 1.1), CFrame.new(0, s.Y * 0.12 + i * 0.07, 0), RUBBER_DARK, Enum.Material.Rubber)
	end
	if lowerArm then
		local a = lowerArm.Size
		local wrist = -a.Y / 2
		gearPart(folder, lowerArm, "GloveCuff", Vector3.new(a.X * 1.14, 0.42, a.Z * 1.14), CFrame.new(0, wrist + 0.22, 0), RUBBER_DARK, Enum.Material.Rubber)
		gearPart(folder, lowerArm, "GloveRim", Vector3.new(a.X * 1.2, 0.09, a.Z * 1.2), CFrame.new(0, wrist + 0.45, 0), RUBBER, Enum.Material.Rubber)
	end
end

-- Mochila do aspirador: tanque de ferro corroído com cintas de latão, motor em cima, manômetro,
-- alças de couro e mangueira de borracha descendo até o quadril com o bocal.
local IRON = Color3.fromRGB(46, 44, 42)
local TANK = Color3.fromRGB(84, 90, 80)
local BRASS = Color3.fromRGB(128, 98, 52)
local LEATHER = Color3.fromRGB(64, 44, 30)
local HOSE = Color3.fromRGB(40, 37, 34)

local function cylinderAlong(folder: Instance, anchor: BasePart, name: string, a: Vector3, b: Vector3, dia: number, color: Color3, material: Enum.Material)
	-- cilindro do ponto a ao ponto b (no espaço da peça âncora); o eixo do Cylinder é X
	local cf = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0)
	return gearPart(folder, anchor, name, Vector3.new((b - a).Magnitude, dia, dia), cf, color, material, Enum.PartType.Cylinder)
end

local function buildVacuumPack(folder: Instance, torso: BasePart)
	local t = torso.Size
	local h = t.Y * 0.82
	local d = math.min(t.X * 0.52, 1.05)
	local z = t.Z / 2 + d / 2 + 0.02
	local up = CFrame.Angles(0, 0, math.rad(90)) -- Cylinder em pé
	local base = CFrame.new(0, -0.05, z)
	gearPart(folder, torso, "VacuumTank", Vector3.new(h, d, d), base * up, TANK, Enum.Material.CorrodedMetal, Enum.PartType.Cylinder)
	for _, y in { -h * 0.32, h * 0.32 } do
		gearPart(folder, torso, "VacuumBand", Vector3.new(0.1, d + 0.05, d + 0.05), base * CFrame.new(0, y, 0) * up, BRASS, Enum.Material.Metal, Enum.PartType.Cylinder)
	end
	-- motor: tampa, cúpula e respiro
	gearPart(folder, torso, "VacuumCap", Vector3.new(0.18, d * 0.86, d * 0.86), base * CFrame.new(0, h / 2 + 0.08, 0) * up, IRON, Enum.Material.Metal, Enum.PartType.Cylinder)
	gearPart(folder, torso, "VacuumMotor", Vector3.one * d * 0.6, base * CFrame.new(0, h / 2 + 0.2, 0), IRON, Enum.Material.Metal, Enum.PartType.Ball)
	gearPart(folder, torso, "VacuumVent", Vector3.new(0.3, 0.14, 0.14), base * CFrame.new(d * 0.32, h / 2 + 0.3, 0) * up, BRASS, Enum.Material.Metal, Enum.PartType.Cylinder)
	-- manômetro na lateral
	local gauge = base * CFrame.new(d / 2 + 0.03, h * 0.12, 0)
	gearPart(folder, torso, "VacuumGaugeRim", Vector3.new(0.06, 0.34, 0.34), gauge, BRASS, Enum.Material.Metal, Enum.PartType.Cylinder)
	gearPart(folder, torso, "VacuumGauge", Vector3.new(0.07, 0.27, 0.27), gauge * CFrame.new(0.01, 0, 0), Color3.fromRGB(200, 190, 164), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	gearPart(folder, torso, "VacuumNeedle", Vector3.new(0.02, 0.11, 0.025), gauge * CFrame.new(0.05, 0.03, 0) * CFrame.Angles(math.rad(35), 0, 0), Color3.fromRGB(150, 30, 24), Enum.Material.SmoothPlastic)
	-- alças: por cima dos ombros e descendo pela frente, com fivela
	for _, s in { -1, 1 } do
		local x = s * t.X * 0.24
		gearPart(folder, torso, "VacuumStrap", Vector3.new(0.26, 0.06, t.Z + 0.12), CFrame.new(x, t.Y / 2 + 0.03, 0), LEATHER, Enum.Material.Leather)
		gearPart(folder, torso, "VacuumStrap", Vector3.new(0.26, t.Y * 0.85, 0.06), CFrame.new(x, t.Y * 0.07, -t.Z / 2 - 0.03), LEATHER, Enum.Material.Leather)
		gearPart(folder, torso, "VacuumBuckle", Vector3.new(0.3, 0.16, 0.04), CFrame.new(x, -t.Y * 0.1, -t.Z / 2 - 0.07), BRASS, Enum.Material.Metal)
	end
	-- mangueira: sai do fundo do tanque, contorna o lado direito e desce até o quadril
	local pts = {
		Vector3.new(d * 0.2, -0.05 - h / 2 + 0.05, z),
		Vector3.new(d * 0.45, -h / 2 - 0.25, z - 0.1),
		Vector3.new(t.X / 2 + 0.2, -h / 2 - 0.3, t.Z * 0.2),
		Vector3.new(t.X / 2 + 0.25, -h / 2 - 0.45, -t.Z * 0.3),
	}
	for i = 2, #pts do
		cylinderAlong(folder, torso, "VacuumHose", pts[i - 1], pts[i], 0.22, HOSE, Enum.Material.Rubber)
		gearPart(folder, torso, "VacuumHoseJoint", Vector3.one * 0.25, CFrame.new(pts[i]), HOSE, Enum.Material.Rubber, Enum.PartType.Ball)
	end
	-- bocal de metal apontando para baixo
	local tip = pts[#pts]
	cylinderAlong(folder, torso, "VacuumNozzle", tip, tip + Vector3.new(0, -0.55, -0.1), 0.17, Color3.fromRGB(110, 106, 98), Enum.Material.Metal)
	cylinderAlong(folder, torso, "VacuumMouth", tip + Vector3.new(0, -0.5, -0.09), tip + Vector3.new(0, -0.62, -0.11), 0.3, IRON, Enum.Material.Metal)
end

function AvatarService.Refresh(player: Player)
	local char = player.Character
	local data = S.Data.Get(player)
	if not char or not data then
		return
	end
	local torso = (char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")) :: BasePart?
	local belt = (char:FindFirstChild("LowerTorso") or char:FindFirstChild("Torso")) :: BasePart?
	local head = char:FindFirstChild("Head") :: BasePart?
	if not torso or not belt or not head then
		return
	end
	local old = char:FindFirstChild("SpudGear")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "SpudGear"
	folder.Parent = char

	-- sem avental nem gorro: sobre avatares variados ficavam estranhos (pedido do dono do jogo)

	buildTool(folder, belt, data.Tool)

	-- cosmético exclusivo da Horta Proibida: broto dourado no gorro
	if data.Rooms.HortaProibida then
		local top = CFrame.new(0, head.Size.Y / 2 + 0.6, 0)
		gearPart(folder, head, "GoldSprout", Vector3.new(0.12, 0.5, 0.12), top, Color3.fromRGB(90, 120, 50), Enum.Material.Grass)
		gearPart(folder, head, "GoldLeaf", Vector3.new(0.5, 0.06, 0.25), top * CFrame.new(0.18, 0.2, 0) * CFrame.Angles(0, 0, math.rad(25)), Color3.fromRGB(255, 196, 60), Enum.Material.Neon)
		gearPart(folder, head, "GoldLeaf2", Vector3.new(0.5, 0.06, 0.25), top * CFrame.new(-0.18, 0.15, 0) * CFrame.Angles(0, 0, math.rad(-25)), Color3.fromRGB(255, 196, 60), Enum.Material.Neon)
	end

	if data.Items.Luvas then
		for _, side in { "Left", "Right" } do
			buildGlove(folder, char:FindFirstChild(side .. "Hand") :: BasePart?, char:FindFirstChild(side .. "LowerArm") :: BasePart?)
		end
	end
	if data.Items.Aspirador then
		buildVacuumPack(folder, torso)
	end
end

function AvatarService.Init(services)
	S = services
	local function watch(player: Player)
		player.CharacterAdded:Connect(function(char)
			-- grupo "Players": atravessa o carrinho, a esteira e a decoração pequena (grupo "NoPlayer"),
			-- para a porta e o caminho dentro da cozinha ficarem livres
			local function group(d: Instance)
				if d:IsA("BasePart") then
					d.CollisionGroup = "Players"
				end
			end
			for _, d in char:GetDescendants() do
				group(d)
			end
			char.DescendantAdded:Connect(group)
			char:WaitForChild("Humanoid", 10)
			char:WaitForChild("UpperTorso", 5)
			task.wait(0.5) -- espera a aparência do avatar carregar
			AvatarService.Refresh(player)
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, p in Players:GetPlayers() do
		watch(p)
	end
	S.Bus.Connect("Loaded", function(player)
		AvatarService.Refresh(player)
	end)
end

return AvatarService
