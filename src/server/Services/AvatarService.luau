-- AvatarService: visual greybox do equipamento no avatar (seções 7.4 e 7.8).
--   * Avental e gorro de cozinha gastos (todo aprendiz ganha ao entrar).
--   * Ferramenta equipada no cinto, com o cabo na cor de tier.
--   * Luvas amarelas de borracha, mochila do aspirador.
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
		for _, n in { "LeftHand", "RightHand" } do
			local h = char:FindFirstChild(n) :: BasePart?
			if h then
				gearPart(folder, h, "Glove", h.Size * 1.08, CFrame.new(), Color3.fromRGB(226, 196, 60), Enum.Material.Plastic)
			end
		end
	end
	if data.Items.Aspirador then
		local back = CFrame.new(0, 0, torso.Size.Z / 2 + 0.45)
		gearPart(folder, torso, "VacuumPack", Vector3.new(1.3, 1.5, 0.8), back, Color3.fromRGB(96, 90, 80), Enum.Material.CorrodedMetal)
		gearPart(folder, torso, "VacuumHose", Vector3.new(1.8, 0.28, 0.28), back * CFrame.new(0.7, -0.4, 0) * CFrame.Angles(0, 0, math.rad(60)), Color3.fromRGB(50, 46, 42), Enum.Material.Fabric, Enum.PartType.Cylinder)
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
