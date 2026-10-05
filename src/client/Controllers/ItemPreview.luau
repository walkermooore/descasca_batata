-- ItemPreview: miniaturas 3D dos itens da loja (ViewportFrame que gira devagar).
--   * Ferramentas: montadas aqui (faca, descascador em Y, lâmina a vapor, laser).
--   * Máquinas da cozinha: cópia da máquina de verdade da esteira (lavadora, fritas...).
--   * Itens de coleta e temas: modelinhos simples.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local player = Players.LocalPlayer

local ItemPreview = {}

local spinning: { { Model: Model, Base: CFrame } } = {}

local function part(m: Model, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, shape: Enum.PartType?)
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	if shape then
		p.Shape = shape
	end
	p.Parent = m
	return p
end

local METAL = Color3.fromRGB(176, 178, 184)
local STEEL = Color3.fromRGB(214, 218, 224)
local DARK = Color3.fromRGB(34, 32, 30)
local WOOD = Color3.fromRGB(86, 56, 36)
local BRASS = Color3.fromRGB(190, 146, 70)
local RUBBER_Y = Color3.fromRGB(232, 196, 54)

local rad = math.rad

-- Cilindro deitado ao longo do eixo Z (o Cylinder do Roblox nasce no eixo X).
local function cylZ(m: Model, len: number, dia: number, cf: CFrame, color: Color3, mat: Enum.Material)
	return part(m, Vector3.new(len, dia, dia), cf * CFrame.Angles(0, rad(90), 0), color, mat, Enum.PartType.Cylinder)
end
-- Cilindro em pé (eixo Y).
local function cylY(m: Model, len: number, dia: number, cf: CFrame, color: Color3, mat: Enum.Material)
	return part(m, Vector3.new(len, dia, dia), cf * CFrame.Angles(0, 0, rad(90)), color, mat, Enum.PartType.Cylinder)
end
local function ball(m: Model, dia: number, cf: CFrame, color: Color3, mat: Enum.Material)
	return part(m, Vector3.new(dia, dia, dia), cf, color, mat, Enum.PartType.Ball)
end
local function wedge(m: Model, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material)
	local w = Instance.new("WedgePart")
	w.Anchored = true
	w.Size = size
	w.CFrame = cf
	w.Color = color
	w.Material = mat
	w.Parent = m
	return w
end
local function potato(m: Model, cf: CFrame, s: number)
	local p = part(m, Vector3.new(0.34, 0.28, 0.42) * s, cf, Color3.fromRGB(128, 92, 56), Enum.Material.Ground)
	local sm = Instance.new("SpecialMesh")
	sm.MeshType = Enum.MeshType.Sphere
	sm.Parent = p
	return p
end

-- Faca: lâmina para -Z, cabo para +Z.
local function knife(m: Model, tier: Color3, rusty: boolean, scale: number)
	local bladeCol = if rusty then Color3.fromRGB(128, 90, 60) else METAL
	local bladeMat = if rusty then Enum.Material.CorrodedMetal else Enum.Material.Metal
	-- cabo com rebites e ponteira
	part(m, Vector3.new(0.2, 0.3, 0.95), CFrame.new(0, -0.02, 0.6), WOOD, Enum.Material.Wood)
	part(m, Vector3.new(0.22, 0.33, 0.08), CFrame.new(0, -0.02, 1.1), METAL, Enum.Material.Metal)
	for _, z in { 0.35, 0.62, 0.89 } do
		cylZ(m, 0.24, 0.07, CFrame.new(0, -0.02, z) * CFrame.Angles(0, rad(90), 0), STEEL, Enum.Material.Metal)
	end
	if rusty then
		part(m, Vector3.new(0.23, 0.33, 0.14), CFrame.new(0, -0.02, 0.48), Color3.fromRGB(120, 116, 104), Enum.Material.Fabric)
	end
	-- guarda na cor da raridade
	part(m, Vector3.new(0.26, 0.4, 0.1), CFrame.new(0, 0, 0.08), tier, Enum.Material.Metal)
	-- lâmina + ponta + fio
	local L = 0.8 * scale
	local H = 0.36 * scale
	part(m, Vector3.new(0.05, H, L), CFrame.new(0, 0.02, 0.03 - L / 2), bladeCol, bladeMat)
	wedge(m, Vector3.new(0.05, H, 0.38 * scale), CFrame.new(0, 0.02, 0.03 - L - 0.19 * scale), bladeCol, bladeMat)
	if not rusty then
		part(m, Vector3.new(0.056, 0.05, L), CFrame.new(0, 0.02 - H / 2 + 0.025, 0.03 - L / 2), STEEL, Enum.Material.SmoothPlastic).Reflectance = 0.3
	else
		for _, z in { -0.25, -0.5, -0.7 } do
			part(m, Vector3.new(0.06, 0.06, 0.07), CFrame.new(0, 0.02 - H / 2 + 0.02, z), DARK, Enum.Material.Slate)
		end
		part(m, Vector3.new(0.056, 0.1, 0.18), CFrame.new(0, 0.08, -0.4), Color3.fromRGB(150, 70, 36), Enum.Material.CorrodedMetal)
	end
end

-- Descascador em Y: cabo emborrachado, garfo e lâmina(s) com fenda.
local function peelerY(m: Model, tier: Color3, double: boolean)
	cylZ(m, 1.0, 0.3, CFrame.new(0, 0, 0.62), tier, Enum.Material.SmoothPlastic)
	for _, z in { 0.35, 0.5, 0.65, 0.8 } do
		cylZ(m, 0.05, 0.33, CFrame.new(0, 0, z), DARK, Enum.Material.Rubber)
	end
	ball(m, 0.3, CFrame.new(0, 0, 1.12), tier, Enum.Material.SmoothPlastic)
	part(m, Vector3.new(0.34, 0.12, 0.12), CFrame.new(0, 0, 1.0) * CFrame.Angles(0, 0, rad(90)), DARK, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	cylZ(m, 0.22, 0.14, CFrame.new(0, 0, 0.04), STEEL, Enum.Material.Metal)
	local a = math.atan2(0.35, 0.52)
	for _, s in { -1, 1 } do
		part(m, Vector3.new(0.08, 0.08, 0.63), CFrame.new(0.175 * s, 0, -0.34) * CFrame.Angles(0, -a * s, 0), STEEL, Enum.Material.Metal)
		ball(m, 0.13, CFrame.new(0.36 * s, 0, -0.62), tier, Enum.Material.Metal)
	end
	local function blade(z: number, w: number)
		part(m, Vector3.new(w, 0.03, 0.16), CFrame.new(0, 0, z), STEEL, Enum.Material.Metal).Reflectance = 0.2
		part(m, Vector3.new(w * 0.7, 0.035, 0.03), CFrame.new(0, 0, z), DARK, Enum.Material.Metal)
	end
	blade(-0.62, 0.72)
	if double then
		for _, s in { -1, 1 } do
			part(m, Vector3.new(0.06, 0.06, 0.2), CFrame.new(0.25 * s, 0, -0.46), STEEL, Enum.Material.Metal)
		end
		blade(-0.44, 0.48)
		part(m, Vector3.new(0.32, 0.06, 0.06), CFrame.new(0, 0, -0.08), BRASS, Enum.Material.Metal)
	end
end

local function toolModel(id: string): Model
	local m = Instance.new("Model")
	local tool = Config.ToolsById[id]
	local tier = Config.TierColors[tool and tool.Tier or 1]
	if id == "Laser" then
		-- corpo, aletas brilhantes, lente, empunhadura, bateria e feixe
		cylZ(m, 1.1, 0.36, CFrame.new(0, 0, 0.2), Color3.fromRGB(206, 210, 220), Enum.Material.Metal)
		ball(m, 0.36, CFrame.new(0, 0, 0.75), Color3.fromRGB(206, 210, 220), Enum.Material.Metal)
		for _, z in { -0.1, 0.05, 0.2 } do
			cylZ(m, 0.04, 0.46, CFrame.new(0, 0, z), tier, Enum.Material.Neon)
		end
		cylZ(m, 0.24, 0.28, CFrame.new(0, 0, -0.45), DARK, Enum.Material.Metal)
		cylZ(m, 0.04, 0.2, CFrame.new(0, 0, -0.58), Color3.fromRGB(255, 70, 60), Enum.Material.Neon)
		local beam = cylZ(m, 0.7, 0.05, CFrame.new(0, 0, -0.95), Color3.fromRGB(255, 80, 70), Enum.Material.Neon)
		beam.Transparency = 0.25
		part(m, Vector3.new(0.18, 0.5, 0.24), CFrame.new(0, -0.36, 0.42) * CFrame.Angles(rad(-15), 0, 0), DARK, Enum.Material.Rubber)
		part(m, Vector3.new(0.06, 0.14, 0.06), CFrame.new(0, -0.24, 0.22), Color3.fromRGB(255, 70, 60), Enum.Material.SmoothPlastic)
		part(m, Vector3.new(0.22, 0.14, 0.4), CFrame.new(0, 0.22, 0.4), Color3.fromRGB(60, 62, 70), Enum.Material.Metal)
		part(m, Vector3.new(0.14, 0.03, 0.26), CFrame.new(0, 0.3, 0.4), Color3.fromRGB(90, 230, 255), Enum.Material.Neon)
		return m
	end
	if id == "DescascadorY" or id == "DescascadorDuplo" then
		peelerY(m, tier, id == "DescascadorDuplo")
		return m
	end
	if id == "LaminaVapor" then
		knife(m, tier, false, 1.25)
		-- caldeira de latão em cima do cabo, cano até a lâmina, manômetro e vapor
		cylZ(m, 0.7, 0.36, CFrame.new(0, 0.36, 0.62), BRASS, Enum.Material.Metal)
		for _, z in { 0.27, 0.97 } do
			cylZ(m, 0.05, 0.4, CFrame.new(0, 0.36, z), Color3.fromRGB(120, 86, 40), Enum.Material.Metal)
		end
		cylZ(m, 0.5, 0.08, CFrame.new(0, 0.3, 0.05), BRASS, Enum.Material.Metal)
		part(m, Vector3.new(0.06, 0.2, 0.2), CFrame.new(0.2, 0.42, 0.62), Color3.fromRGB(120, 86, 40), Enum.Material.Metal, Enum.PartType.Cylinder)
		part(m, Vector3.new(0.02, 0.15, 0.15), CFrame.new(0.235, 0.42, 0.62), Color3.fromRGB(255, 236, 190), Enum.Material.Neon, Enum.PartType.Cylinder)
		for i, z in { -0.2, -0.5, -0.8 } do
			local puff = ball(m, 0.16 + i * 0.05, CFrame.new(0, 0.34 + i * 0.07, z), Color3.fromRGB(240, 240, 240), Enum.Material.SmoothPlastic)
			puff.Transparency = 0.35 + i * 0.1
		end
		return m
	end
	knife(m, tier, id == "FacaCega", 1)
	return m
end

-- Luva de borracha (s = -1 esquerda, 1 direita), em pé ao longo de Y.
local function glove(m: Model, base: CFrame, s: number)
	local col = RUBBER_Y
	local dark = Color3.fromRGB(196, 158, 36)
	part(m, Vector3.new(0.52, 0.56, 0.2), base * CFrame.new(0, 0.05, 0), col, Enum.Material.Plastic)
	ball(m, 0.2, base * CFrame.new(-0.2, -0.2, 0), col, Enum.Material.Plastic)
	ball(m, 0.2, base * CFrame.new(0.2, -0.2, 0), col, Enum.Material.Plastic)
	local fingers = { { -0.18, 0.3 }, { -0.06, 0.36 }, { 0.06, 0.34 }, { 0.18, 0.26 } }
	for _, f in fingers do
		local x, len = f[1], f[2]
		cylY(m, len, 0.13, base * CFrame.new(x, 0.33 + len / 2, 0), col, Enum.Material.Plastic)
		ball(m, 0.13, base * CFrame.new(x, 0.33 + len, 0), col, Enum.Material.Plastic)
	end
	-- polegar para fora
	local tcf = base * CFrame.new(0.3 * s, 0.12, 0.02) * CFrame.Angles(0, 0, rad(-45 * s))
	cylY(m, 0.3, 0.14, tcf * CFrame.new(0, 0.1, 0), col, Enum.Material.Plastic)
	ball(m, 0.14, tcf * CFrame.new(0, 0.25, 0), col, Enum.Material.Plastic)
	-- punho largo com borda enrolada
	part(m, Vector3.new(0.58, 0.4, 0.24), base * CFrame.new(0, -0.42, 0), dark, Enum.Material.Plastic)
	part(m, Vector3.new(0.62, 0.12, 0.12), base * CFrame.new(0, -0.62, 0), dark, Enum.Material.Plastic, Enum.PartType.Cylinder)
	-- textura de aderência na palma
	for _, y in { -0.05, 0.08, 0.21 } do
		part(m, Vector3.new(0.4, 0.03, 0.21), base * CFrame.new(0, y, 0), dark, Enum.Material.Plastic)
	end
end

local function collectionModel(id: string): Model
	local m = Instance.new("Model")
	if id == "Luvas" then
		glove(m, CFrame.new(-0.36, 0, 0.12) * CFrame.Angles(0, 0, rad(10)), -1)
		glove(m, CFrame.new(0.36, 0.05, -0.12) * CFrame.Angles(0, 0, rad(-10)), 1)
	elseif id == "CarrinhoMao" then
		local tray = Color3.fromRGB(92, 104, 96)
		part(m, Vector3.new(0.9, 0.08, 1.0), CFrame.new(0, 0.05, 0), tray, Enum.Material.CorrodedMetal)
		for _, s in { -1, 1 } do
			part(m, Vector3.new(0.07, 0.42, 1.1), CFrame.new(0.5 * s, 0.24, 0) * CFrame.Angles(0, 0, rad(-18 * s)), tray, Enum.Material.CorrodedMetal)
			part(m, Vector3.new(0.09, 0.07, 1.14), CFrame.new(0.57 * s, 0.45, 0), METAL, Enum.Material.Metal)
		end
		wedge(m, Vector3.new(1.0, 0.42, 0.34), CFrame.new(0, 0.24, -0.66) * CFrame.Angles(0, rad(180), 0), tray, Enum.Material.CorrodedMetal)
		part(m, Vector3.new(1.08, 0.42, 0.07), CFrame.new(0, 0.24, 0.53), tray, Enum.Material.CorrodedMetal)
		-- roda da frente
		part(m, Vector3.new(0.14, 0.52, 0.52), CFrame.new(0, -0.3, -0.72), DARK, Enum.Material.Rubber, Enum.PartType.Cylinder)
		part(m, Vector3.new(0.16, 0.2, 0.2), CFrame.new(0, -0.3, -0.72), METAL, Enum.Material.Metal, Enum.PartType.Cylinder)
		for _, s in { -1, 1 } do
			part(m, Vector3.new(0.05, 0.05, 0.5), CFrame.new(0.1 * s, -0.12, -0.52) * CFrame.Angles(rad(-35), 0, 0), METAL, Enum.Material.Metal)
			-- cabos e pés
			cylZ(m, 1.1, 0.08, CFrame.new(0.36 * s, 0.0, 0.62), WOOD, Enum.Material.Wood)
			cylZ(m, 0.22, 0.11, CFrame.new(0.36 * s, 0.0, 1.1), DARK, Enum.Material.Rubber)
			part(m, Vector3.new(0.06, 0.36, 0.06), CFrame.new(0.3 * s, -0.2, 0.4), METAL, Enum.Material.Metal)
		end
		local spots = { { -0.22, 0.28, -0.2 }, { 0.2, 0.28, -0.25 }, { 0, 0.3, 0.15 }, { -0.25, 0.3, 0.3 }, { 0.24, 0.3, 0.26 }, { 0, 0.5, -0.05 } }
		for i, p in spots do
			potato(m, CFrame.new(p[1], p[2], p[3]) * CFrame.Angles(0, i, rad(i * 20)), 1.1)
		end
	elseif id == "Aspirador" then
		local body = Color3.fromRGB(86, 96, 84)
		cylY(m, 0.8, 0.78, CFrame.new(0, 0, 0), body, Enum.Material.CorrodedMetal)
		cylY(m, 0.1, 0.84, CFrame.new(0, 0.44, 0), DARK, Enum.Material.Metal)
		local dome = ball(m, 0.5, CFrame.new(0, 0.5, 0), body, Enum.Material.CorrodedMetal)
		dome.Size = Vector3.new(0.6, 0.3, 0.6)
		part(m, Vector3.new(0.5, 0.06, 0.08), CFrame.new(0, 0.74, 0), DARK, Enum.Material.Rubber)
		for _, s in { -1, 1 } do
			part(m, Vector3.new(0.06, 0.16, 0.06), CFrame.new(0.22 * s, 0.66, 0), DARK, Enum.Material.Metal)
		end
		-- faixa, painel e luzes
		cylY(m, 0.05, 0.8, CFrame.new(0, -0.15, 0), BRASS, Enum.Material.Metal)
		part(m, Vector3.new(0.26, 0.2, 0.04), CFrame.new(0, 0.12, -0.39), DARK, Enum.Material.Metal)
		ball(m, 0.08, CFrame.new(-0.06, 0.12, -0.41), Color3.fromRGB(255, 80, 60), Enum.Material.Neon)
		ball(m, 0.08, CFrame.new(0.06, 0.12, -0.41), Color3.fromRGB(120, 255, 120), Enum.Material.Neon)
		for _, a in { 45, 135, 225, 315 } do
			part(m, Vector3.new(0.08, 0.14, 0.14), CFrame.Angles(0, rad(a), 0) * CFrame.new(0, -0.44, -0.3), DARK, Enum.Material.Rubber, Enum.PartType.Cylinder)
		end
		-- mangueira sanfonada em arco até o bocal
		local prev = Vector3.new(0.4, 0.1, 0)
		for i = 1, 8 do
			local t = i / 8
			local p = Vector3.new(0.4 + t * 0.7, 0.1 + math.sin(t * math.pi) * 0.3 - t * 0.55, -t * 0.55)
			local mid = (prev + p) / 2
			cylZ(m, (p - prev).Magnitude + 0.04, 0.16, CFrame.lookAt(mid, p), if i % 2 == 0 then DARK else Color3.fromRGB(60, 58, 52), Enum.Material.Rubber)
			prev = p
		end
		part(m, Vector3.new(0.5, 0.08, 0.22), CFrame.new(prev + Vector3.new(0, -0.06, -0.05)), DARK, Enum.Material.Metal)
		potato(m, CFrame.new(prev + Vector3.new(0.05, -0.1, -0.35)), 0.9)
	else
		part(m, Vector3.new(1, 1, 1), CFrame.new(), Color3.fromRGB(120, 100, 80), Enum.Material.Wood)
	end
	return m
end

-- Modelos próprios das melhorias da cozinha (mais legíveis na miniatura que a peça do mapa).
local IRON = Color3.fromRGB(78, 74, 70)
local RUST = Color3.fromRGB(128, 74, 44)
local PLANK = Color3.fromRGB(104, 70, 44)
local PEELED = Color3.fromRGB(222, 200, 140)

local function peeledPotato(m: Model, cf: CFrame, s: number)
	local p = potato(m, cf, s)
	p.Color = PEELED
	p.Material = Enum.Material.SmoothPlastic
	return p
end

local function rivets(m: Model, cf: CFrame, xs: { number }, ys: { number })
	for _, x in xs do
		for _, y in ys do
			ball(m, 0.08, cf * CFrame.new(x, y, 0), STEEL, Enum.Material.Metal)
		end
	end
end

local function kitchenModel(id: string): Model?
	local m = Instance.new("Model")
	if id == "Cart" then
		-- carroça de madeira com cintas de ferro, rodas raiadas e monte de batatas
		part(m, Vector3.new(2.0, 0.12, 1.3), CFrame.new(0, 0, 0), PLANK, Enum.Material.WoodPlanks)
		for _, s in { -1, 1 } do
			part(m, Vector3.new(2.0, 0.7, 0.1), CFrame.new(0, 0.4, 0.62 * s), PLANK, Enum.Material.WoodPlanks)
			part(m, Vector3.new(0.1, 0.7, 1.3), CFrame.new(0.97 * s, 0.4, 0), PLANK, Enum.Material.WoodPlanks)
			part(m, Vector3.new(2.06, 0.08, 0.12), CFrame.new(0, 0.72, 0.62 * s), IRON, Enum.Material.Metal)
			for _, x in { -0.6, 0.6 } do
				part(m, Vector3.new(0.08, 0.74, 0.12), CFrame.new(x, 0.4, 0.63 * s), IRON, Enum.Material.Metal)
				-- rodas
				local w = CFrame.new(x, -0.28, 0.76 * s)
				part(m, Vector3.new(0.5, 0.6, 0.6), w * CFrame.Angles(0, rad(90), 0), PLANK, Enum.Material.Wood, Enum.PartType.Cylinder).Size = Vector3.new(0.1, 0.6, 0.6)
				part(m, Vector3.new(0.12, 0.64, 0.64), w * CFrame.Angles(0, rad(90), 0), IRON, Enum.Material.Metal, Enum.PartType.Cylinder).Transparency = 0.6
				for k = 0, 2 do
					part(m, Vector3.new(0.05, 0.56, 0.05), w * CFrame.Angles(0, 0, rad(k * 60)), IRON, Enum.Material.Metal)
				end
				ball(m, 0.14, w, IRON, Enum.Material.Metal)
			end
		end
		for i = 1, 9 do
			local x = ((i - 1) % 3 - 1) * 0.5
			local z = (math.floor((i - 1) / 3) - 1) * 0.35
			potato(m, CFrame.new(x, 0.6 + (if i == 5 then 0.2 else 0), z) * CFrame.Angles(0, i, rad(i * 25)), 1.2)
		end
		part(m, Vector3.new(0.05, 1.0, 0.05), CFrame.new(0.9, 1.1, 0.55), WOOD, Enum.Material.Wood)
		part(m, Vector3.new(0.4, 0.26, 0.02), CFrame.new(0.72, 1.45, 0.55), Color3.fromRGB(176, 52, 40), Enum.Material.Fabric)
	elseif id == "Belt" then
		-- esteira com trilhos, rolos nas pontas, lona com travessas e batatas
		for _, s in { -1, 1 } do
			part(m, Vector3.new(2.4, 0.16, 0.08), CFrame.new(0, 0, 0.46 * s), IRON, Enum.Material.Metal)
			for _, x in { -1.0, 1.0 } do
				part(m, Vector3.new(0.1, 0.7, 0.1), CFrame.new(x, -0.4, 0.44 * s), IRON, Enum.Material.Metal)
			end
		end
		part(m, Vector3.new(2.3, 0.06, 0.84), CFrame.new(0, 0.05, 0), DARK, Enum.Material.Rubber)
		for x = -1.0, 1.0, 0.25 do
			part(m, Vector3.new(0.04, 0.04, 0.84), CFrame.new(x, 0.09, 0), Color3.fromRGB(58, 54, 50), Enum.Material.Rubber)
		end
		for _, x in { -1.18, 1.18 } do
			part(m, Vector3.new(0.9, 0.2, 0.2), CFrame.new(x, 0.02, 0) * CFrame.Angles(0, rad(90), 0), STEEL, Enum.Material.Metal, Enum.PartType.Cylinder)
		end
		for _, x in { -1.0, 1.0 } do
			part(m, Vector3.new(2.1, 0.06, 0.06), CFrame.new(0, -0.5, 0.44 * (if x < 0 then -1 else 1)), IRON, Enum.Material.Metal)
		end
		part(m, Vector3.new(0.3, 0.3, 0.3), CFrame.new(1.0, -0.3, 0.6), RUST, Enum.Material.CorrodedMetal)
		cylZ(m, 0.1, 0.22, CFrame.new(1.0, -0.3, 0.78), STEEL, Enum.Material.Metal)
		for i, x in { -0.7, 0.05, 0.75 } do
			peeledPotato(m, CFrame.new(x, 0.26, (i - 2) * 0.12) * CFrame.Angles(0, i, 0), 1.2)
		end
	elseif id == "AutoSend" then
		-- sino de latão num suporte de madeira com corda (o carrinho parte sozinho quando enche)
		part(m, Vector3.new(0.16, 1.6, 0.16), CFrame.new(-0.55, 0, 0), WOOD, Enum.Material.Wood)
		part(m, Vector3.new(0.8, 0.12, 0.14), CFrame.new(-0.2, 0.74, 0), WOOD, Enum.Material.Wood)
		part(m, Vector3.new(0.6, 0.08, 0.6), CFrame.new(-0.55, -0.8, 0), IRON, Enum.Material.Metal)
		cylY(m, 0.14, 0.05, CFrame.new(0.1, 0.62, 0), IRON, Enum.Material.Metal)
		local dome = ball(m, 0.44, CFrame.new(0.1, 0.46, 0), BRASS, Enum.Material.Metal)
		dome.Size = Vector3.new(0.44, 0.36, 0.44)
		cylY(m, 0.36, 0.5, CFrame.new(0.1, 0.28, 0), BRASS, Enum.Material.Metal)
		cylY(m, 0.08, 0.66, CFrame.new(0.1, 0.08, 0), BRASS, Enum.Material.Metal)
		ball(m, 0.14, CFrame.new(0.1, 0.0, 0), IRON, Enum.Material.Metal)
		part(m, Vector3.new(0.04, 0.6, 0.04), CFrame.new(0.32, -0.2, 0) * CFrame.Angles(0, 0, rad(12)), Color3.fromRGB(150, 120, 80), Enum.Material.Fabric)
	elseif id == "Feeder" then
		-- funil alimentador sobre pés e rampa até a mesa
		local top, bot = 1.3, 0.5
		for _, s in { -1, 1 } do
			part(m, Vector3.new(top, 0.08, 0.72), CFrame.new(0, 0.75, 0.42 * s) * CFrame.Angles(rad(-35 * s), 0, 0), RUST, Enum.Material.CorrodedMetal).Size = Vector3.new(top, 0.72, 0.06)
			part(m, Vector3.new(0.06, 0.72, top), CFrame.new(0.42 * s, 0.75, 0) * CFrame.Angles(0, 0, rad(35 * s)), RUST, Enum.Material.CorrodedMetal)
			for _, t in { -1, 1 } do
				part(m, Vector3.new(0.08, 1.1, 0.08), CFrame.new(0.5 * s, -0.1, 0.5 * t), IRON, Enum.Material.Metal)
			end
		end
		part(m, Vector3.new(bot, 0.08, bot), CFrame.new(0, 0.42, 0), IRON, Enum.Material.Metal)
		for i = 1, 5 do
			potato(m, CFrame.new(((i % 3) - 1) * 0.3, 0.75 + math.floor(i / 3) * 0.15, (i % 2 - 0.5) * 0.3) * CFrame.Angles(0, i, rad(i * 30)), 1.1)
		end
		-- rampa
		local ramp = CFrame.new(0, 0.2, -0.9) * CFrame.Angles(rad(-22), 0, 0)
		part(m, Vector3.new(0.5, 0.05, 1.1), ramp, STEEL, Enum.Material.Metal)
		for _, s in { -1, 1 } do
			part(m, Vector3.new(0.05, 0.16, 1.1), ramp * CFrame.new(0.26 * s, 0.07, 0), IRON, Enum.Material.Metal)
		end
		potato(m, ramp * CFrame.new(0, 0.16, -0.25), 1.1)
		rivets(m, CFrame.new(0, 0.75, 0.62) * CFrame.Angles(rad(-35), 0, 0), { -0.45, 0, 0.45 }, { 0.2 })
	elseif id == "Washer" then
		-- tanque com água, bolhas, cano de borrifo e batatas boiando
		part(m, Vector3.new(1.8, 0.1, 1.1), CFrame.new(0, -0.3, 0), IRON, Enum.Material.Metal)
		for _, s in { -1, 1 } do
			part(m, Vector3.new(1.8, 0.7, 0.08), CFrame.new(0, 0, 0.51 * s), Color3.fromRGB(96, 110, 118), Enum.Material.Metal)
			part(m, Vector3.new(0.08, 0.7, 1.1), CFrame.new(0.86 * s, 0, 0), Color3.fromRGB(96, 110, 118), Enum.Material.Metal)
			part(m, Vector3.new(1.86, 0.06, 0.1), CFrame.new(0, 0.36, 0.52 * s), STEEL, Enum.Material.Metal)
			for _, x in { -0.7, 0.7 } do
				part(m, Vector3.new(0.1, 0.4, 0.1), CFrame.new(x, -0.55, 0.45 * s), IRON, Enum.Material.Metal)
			end
		end
		local water = part(m, Vector3.new(1.66, 0.04, 0.96), CFrame.new(0, 0.2, 0), Color3.fromRGB(70, 150, 200), Enum.Material.Glass)
		water.Transparency = 0.25
		for i = 1, 7 do
			local b = ball(m, 0.08 + (i % 3) * 0.04, CFrame.new(-0.7 + i * 0.2, 0.24, ((i * 37) % 7 - 3) * 0.12), Color3.fromRGB(235, 245, 255), Enum.Material.SmoothPlastic)
			b.Transparency = 0.3
		end
		for i, x in { -0.45, 0.1, 0.55 } do
			potato(m, CFrame.new(x, 0.24, (i - 2) * 0.2) * CFrame.Angles(0, i, rad(20)), 1.2)
		end
		-- cano com bicos
		cylZ(m, 0.08, 0.08, CFrame.new(0, 0, 0) * CFrame.new(0, 0.85, 0) * CFrame.Angles(0, rad(90), 0), STEEL, Enum.Material.Metal).Size = Vector3.new(1.7, 0.08, 0.08)
		for _, s in { -1, 1 } do
			part(m, Vector3.new(0.08, 0.55, 0.08), CFrame.new(0.82 * s, 0.6, 0), STEEL, Enum.Material.Metal)
		end
		for x = -0.6, 0.6, 0.3 do
			part(m, Vector3.new(0.08, 0.08, 0.08), CFrame.new(x, 0.79, 0), BRASS, Enum.Material.Metal)
			local d = part(m, Vector3.new(0.03, 0.3, 0.03), CFrame.new(x, 0.58, 0), Color3.fromRGB(150, 210, 255), Enum.Material.Neon)
			d.Transparency = 0.5
		end
	elseif id == "AutoPeel" then
		-- armário com janela redonda (tambor girando), engrenagens, funil, chaminé e saída
		part(m, Vector3.new(1.2, 1.2, 1.0), CFrame.new(0, 0, 0), RUST, Enum.Material.CorrodedMetal)
		part(m, Vector3.new(1.26, 0.1, 1.06), CFrame.new(0, 0.62, 0), IRON, Enum.Material.Metal)
		part(m, Vector3.new(1.26, 0.1, 1.06), CFrame.new(0, -0.62, 0), IRON, Enum.Material.Metal)
		cylZ(m, 0.06, 0.66, CFrame.new(0, 0.02, -0.5), IRON, Enum.Material.Metal)
		local glass = cylZ(m, 0.04, 0.54, CFrame.new(0, 0.02, -0.53), Color3.fromRGB(255, 190, 90), Enum.Material.Neon)
		glass.Transparency = 0.35
		peeledPotato(m, CFrame.new(-0.08, -0.05, -0.45), 0.9)
		potato(m, CFrame.new(0.1, 0.1, -0.45), 0.9)
		rivets(m, CFrame.new(0, 0, -0.51), { -0.5, 0.5 }, { -0.5, 0.5 })
		-- engrenagens na lateral
		for i, g in { { 0.2, 0.2, 0.5 }, { -0.2, -0.25, 0.36 } } do
			local c = CFrame.new(0.62, g[2], g[1])
			part(m, Vector3.new(0.08, g[3], g[3]), c, BRASS, Enum.Material.Metal, Enum.PartType.Cylinder)
			for k = 0, 5 do
				part(m, Vector3.new(0.08, 0.1, 0.1), c * CFrame.Angles(rad(k * 60 + i * 30), 0, 0) * CFrame.new(0, g[3] / 2 + 0.03, 0), BRASS, Enum.Material.Metal)
			end
		end
		-- funil em cima
		for _, s in { -1, 1 } do
			part(m, Vector3.new(0.7, 0.4, 0.05), CFrame.new(0, 0.85, 0.24 * s) * CFrame.Angles(rad(-25 * s), 0, 0), IRON, Enum.Material.Metal)
			part(m, Vector3.new(0.05, 0.4, 0.55), CFrame.new(0.33 * s, 0.85, 0) * CFrame.Angles(0, 0, rad(25 * s)), IRON, Enum.Material.Metal)
		end
		potato(m, CFrame.new(0, 0.95, 0), 1.0)
		-- chaminé e saída
		cylY(m, 0.6, 0.16, CFrame.new(-0.42, 0.95, 0.32), IRON, Enum.Material.Metal)
		local smoke = ball(m, 0.25, CFrame.new(-0.42, 1.35, 0.32), Color3.fromRGB(200, 200, 200), Enum.Material.SmoothPlastic)
		smoke.Transparency = 0.5
		part(m, Vector3.new(0.4, 0.05, 0.6), CFrame.new(-0.7, -0.35, -0.1) * CFrame.Angles(0, 0, rad(25)), STEEL, Enum.Material.Metal)
		peeledPotato(m, CFrame.new(-0.82, -0.36, -0.1), 1.0)
		part(m, Vector3.new(0.14, 0.14, 0.14), CFrame.new(0.3, 0.42, -0.52), Color3.fromRGB(90, 255, 120), Enum.Material.Neon)
	elseif id == "Cutter" then
		-- cortador de fritas: moldura, grade de lâminas, alavanca, batata em cima e fritas saindo
		part(m, Vector3.new(1.1, 0.12, 1.1), CFrame.new(0, -0.6, 0), IRON, Enum.Material.Metal)
		for _, s in { -1, 1 } do
			part(m, Vector3.new(0.1, 1.2, 0.1), CFrame.new(0.5 * s, 0, 0.5), IRON, Enum.Material.Metal)
			part(m, Vector3.new(0.1, 1.2, 0.1), CFrame.new(0.5 * s, 0, -0.5), IRON, Enum.Material.Metal)
		end
		part(m, Vector3.new(1.1, 0.1, 1.1), CFrame.new(0, 0.1, 0), STEEL, Enum.Material.Metal).Transparency = 0.7
		for k = -2, 2 do
			part(m, Vector3.new(0.02, 0.1, 1.0), CFrame.new(k * 0.18, 0.1, 0), STEEL, Enum.Material.Metal).Reflectance = 0.3
			part(m, Vector3.new(1.0, 0.1, 0.02), CFrame.new(0, 0.1, k * 0.18), STEEL, Enum.Material.Metal).Reflectance = 0.3
		end
		part(m, Vector3.new(1.1, 0.08, 0.1), CFrame.new(0, 0.62, 0.5), IRON, Enum.Material.Metal)
		part(m, Vector3.new(0.8, 0.06, 0.8), CFrame.new(0, 0.5, 0), RUST, Enum.Material.CorrodedMetal)
		part(m, Vector3.new(0.08, 0.08, 1.0), CFrame.new(0.55, 0.62, -0.35) * CFrame.Angles(rad(20), 0, 0), WOOD, Enum.Material.Wood)
		ball(m, 0.16, CFrame.new(0.55, 0.8, -0.82), Color3.fromRGB(176, 52, 40), Enum.Material.SmoothPlastic)
		peeledPotato(m, CFrame.new(0, 0.3, 0), 1.4)
		for i = 1, 10 do
			local fry = part(m, Vector3.new(0.07, 0.07, 0.42), CFrame.new(((i * 7) % 9 - 4) * 0.08, -0.46 + (i % 3) * 0.05, ((i * 5) % 7 - 3) * 0.1) * CFrame.Angles(rad((i % 3) * 20), rad(i * 37), 0), Color3.fromRGB(240, 206, 100), Enum.Material.SmoothPlastic)
			fry.Name = "Fry"
		end
	elseif id == "Drum" then
		-- tambor abrasivo deitado, com aros, suporte, motor com correia e funil
		local axis = CFrame.new(0, 0.2, 0)
		part(m, Vector3.new(1.6, 0.9, 0.9), axis, Color3.fromRGB(110, 104, 96), Enum.Material.Slate, Enum.PartType.Cylinder)
		for _, x in { -0.7, 0, 0.7 } do
			part(m, Vector3.new(0.08, 0.98, 0.98), axis * CFrame.new(x, 0, 0), RUST, Enum.Material.CorrodedMetal, Enum.PartType.Cylinder)
		end
		part(m, Vector3.new(0.06, 0.6, 0.6), axis * CFrame.new(-0.82, 0, 0), DARK, Enum.Material.Metal, Enum.PartType.Cylinder)
		potato(m, axis * CFrame.new(-0.84, 0, 0.05), 0.9)
		for _, s in { -1, 1 } do
			part(m, Vector3.new(0.12, 0.8, 0.12), CFrame.new(0.55 * s, -0.4, 0.35), IRON, Enum.Material.Metal)
			part(m, Vector3.new(0.12, 0.8, 0.12), CFrame.new(0.55 * s, -0.4, -0.35), IRON, Enum.Material.Metal)
		end
		part(m, Vector3.new(1.4, 0.1, 0.9), CFrame.new(0, -0.8, 0), IRON, Enum.Material.Metal)
		part(m, Vector3.new(0.45, 0.35, 0.4), CFrame.new(0.4, -0.55, -0.2), Color3.fromRGB(60, 80, 70), Enum.Material.Metal)
		part(m, Vector3.new(0.05, 0.9, 0.06), CFrame.new(0.72, -0.2, -0.2) * CFrame.Angles(0, 0, rad(10)), DARK, Enum.Material.Rubber)
		-- funil e casca caindo
		for _, s in { -1, 1 } do
			part(m, Vector3.new(0.5, 0.35, 0.05), CFrame.new(0.3, 0.8, 0.18 * s) * CFrame.Angles(rad(-25 * s), 0, 0), IRON, Enum.Material.Metal)
		end
		for i = 1, 4 do
			part(m, Vector3.new(0.12, 0.03, 0.08), CFrame.new(-0.2 + i * 0.12, -0.7, 0.2 - i * 0.08) * CFrame.Angles(0, i, 0), Color3.fromRGB(128, 92, 56), Enum.Material.Ground)
		end
	elseif id == "Masher" then
		-- prensa de purê: colunas, travessa, pistão brilhando, bacia com purê e volante vermelho
		part(m, Vector3.new(1.4, 0.12, 1.0), CFrame.new(0, -0.7, 0), IRON, Enum.Material.Metal)
		for _, s in { -1, 1 } do
			part(m, Vector3.new(0.14, 1.6, 0.14), CFrame.new(0.58 * s, 0.1, 0), IRON, Enum.Material.Metal)
		end
		part(m, Vector3.new(1.4, 0.2, 0.3), CFrame.new(0, 0.9, 0), RUST, Enum.Material.CorrodedMetal)
		cylY(m, 0.7, 0.14, CFrame.new(0, 0.45, 0), STEEL, Enum.Material.Metal).Reflectance = 0.3
		cylY(m, 0.08, 0.66, CFrame.new(0, 0.08, 0), STEEL, Enum.Material.Metal)
		for k = -1, 1 do
			part(m, Vector3.new(0.5, 0.02, 0.03), CFrame.new(0, 0.03, k * 0.15), DARK, Enum.Material.Metal)
		end
		cylY(m, 0.4, 0.8, CFrame.new(0, -0.44, 0), Color3.fromRGB(70, 66, 62), Enum.Material.Metal)
		local puree = ball(m, 0.7, CFrame.new(0, -0.22, 0), Color3.fromRGB(236, 214, 150), Enum.Material.SmoothPlastic)
		puree.Size = Vector3.new(0.7, 0.24, 0.7)
		ball(m, 0.08, CFrame.new(0.05, -0.1, 0.05), Color3.fromRGB(250, 226, 120), Enum.Material.SmoothPlastic)
		-- volante
		local wcf = CFrame.new(0.75, 0.9, 0)
		part(m, Vector3.new(0.05, 0.6, 0.6), wcf, Color3.fromRGB(176, 52, 40), Enum.Material.Metal, Enum.PartType.Cylinder).Transparency = 0
		part(m, Vector3.new(0.06, 0.46, 0.46), wcf, RUST, Enum.Material.CorrodedMetal, Enum.PartType.Cylinder)
		for k = 0, 2 do
			part(m, Vector3.new(0.06, 0.56, 0.05), wcf * CFrame.Angles(rad(k * 60), 0, 0), Color3.fromRGB(176, 52, 40), Enum.Material.Metal)
		end
		part(m, Vector3.new(0.12, 0.06, 0.06), wcf * CFrame.new(0.06, 0.28, 0), DARK, Enum.Material.Wood)
	else
		return nil
	end
	return m
end

-- Miniaturas dos passes e pacotes (Robux).
local function coinStack(m: Model, cf: CFrame, n: number)
	for i = 0, n - 1 do
		part(m, Vector3.new(0.12, 0.6, 0.6), cf * CFrame.new(0, 0.07 + i * 0.13, 0) * CFrame.Angles(0, 0, rad(90)), BRASS, Enum.Material.Metal, Enum.PartType.Cylinder)
	end
end
local function goldPotato(m: Model, cf: CFrame, s: number)
	local p = potato(m, cf, s)
	p.Color = Color3.fromRGB(240, 196, 60)
	p.Material = Enum.Material.Metal
	p.Reflectance = 0.25
	return p
end
local function chefHat(m: Model, cf: CFrame, color: Color3)
	part(m, Vector3.new(0.5, 1.0, 1.0), cf * CFrame.Angles(0, 0, rad(90)), color, Enum.Material.Fabric, Enum.PartType.Cylinder)
	ball(m, 1.3, cf * CFrame.new(0, 0.7, 0), Color3.fromRGB(245, 240, 230), Enum.Material.Fabric)
end
local function sack(m: Model, cf: CFrame, s: number)
	local b = ball(m, 1.3 * s, cf, Color3.fromRGB(150, 122, 84), Enum.Material.Fabric)
	b.Size = Vector3.new(1.3, 1.5, 1.2) * s
	part(m, Vector3.new(0.5, 0.3, 0.5) * s, cf * CFrame.new(0, 0.8 * s, 0), Color3.fromRGB(150, 122, 84), Enum.Material.Fabric)
	part(m, Vector3.new(0.56, 0.08, 0.56) * s, cf * CFrame.new(0, 0.68 * s, 0), Color3.fromRGB(90, 60, 40), Enum.Material.Fabric)
	part(m, Vector3.new(0.05, 0.5, 0.5) * s, cf * CFrame.new(0, 0, -0.6 * s) * CFrame.Angles(0, rad(90), 0), BRASS, Enum.Material.Metal, Enum.PartType.Cylinder)
end

local function passModel(id: string): Model?
	local m = Instance.new("Model")
	if id == "KitInicial" then
		knife(m, Config.TierColors[2], false, 0.8)
		m:PivotTo(CFrame.new(-0.3, 0, 0) * CFrame.Angles(rad(70), 0, rad(-20)))
		glove(m, CFrame.new(0.55, -0.1, 0.2) * CFrame.Angles(0, 0, rad(-15)), 1)
		coinStack(m, CFrame.new(0, -0.9, -0.4), 5)
	elseif id == "BaldeGigante" then
		cylY(m, 1.3, 1.5, CFrame.new(0, 0, 0), Color3.fromRGB(120, 124, 128), Enum.Material.Metal)
		cylY(m, 0.1, 1.6, CFrame.new(0, 0.65, 0), IRON, Enum.Material.Metal)
		cylY(m, 0.1, 1.6, CFrame.new(0, -0.3, 0), IRON, Enum.Material.Metal)
		for i = 1, 6 do potato(m, CFrame.new(((i % 3) - 1) * 0.35, 0.8 + math.floor(i / 4) * 0.2, (i % 2 - 0.5) * 0.4) * CFrame.Angles(0, i, rad(i * 30)), 1) end
	elseif id == "CarrinhoTurbo" then
		local c = kitchenModel("Cart") :: Model
		for _, d in c:GetChildren() do d.Parent = m end
		for i = 1, 3 do
			local s = part(m, Vector3.new(0.06, 0.06, 1.2), CFrame.new(-1.4 - i * 0.2, 0.2 + i * 0.25, 0), Color3.fromRGB(200, 220, 255), Enum.Material.Neon)
			s.Transparency = 0.3
			s.CFrame = CFrame.new(-1.5 - i * 0.15, 0.1 + i * 0.25, 0) * CFrame.Angles(0, rad(90), 0)
		end
	elseif id == "GanhoOffline8h" then
		part(m, Vector3.new(0.25, 1.8, 1.8), CFrame.new(0, 0, 0) * CFrame.Angles(0, rad(90), 0), Color3.fromRGB(70, 60, 50), Enum.Material.Wood, Enum.PartType.Cylinder)
		part(m, Vector3.new(0.27, 1.55, 1.55), CFrame.new(0, 0, -0.02) * CFrame.Angles(0, rad(90), 0), Color3.fromRGB(228, 214, 186), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		part(m, Vector3.new(0.08, 0.6, 0.05), CFrame.new(0, 0.25, -0.17), DARK, Enum.Material.Metal)
		part(m, Vector3.new(0.45, 0.08, 0.05), CFrame.new(0.2, 0, -0.17), DARK, Enum.Material.Metal)
		local moon = ball(m, 0.8, CFrame.new(0.9, 0.9, 0), Color3.fromRGB(240, 230, 170), Enum.Material.Neon)
		moon.Transparency = 0.1
	elseif id == "AutoDescascar" then
		peelerY(m, Config.TierColors[3], false)
		m:PivotTo(CFrame.Angles(rad(60), 0, 0))
		local c = CFrame.new(0.7, -0.4, 0.2)
		part(m, Vector3.new(0.12, 0.7, 0.7), c, BRASS, Enum.Material.Metal, Enum.PartType.Cylinder)
		for k = 0, 5 do part(m, Vector3.new(0.12, 0.14, 0.14), c * CFrame.Angles(rad(k * 60), 0, 0) * CFrame.new(0, 0.4, 0), BRASS, Enum.Material.Metal) end
	elseif id == "MaisAjudantes" then
		chefHat(m, CFrame.new(-0.6, 0, 0), Color3.fromRGB(236, 232, 222))
		chefHat(m, CFrame.new(0.6, 0.15, 0.3), Color3.fromRGB(236, 232, 222))
		part(m, Vector3.new(0.5, 0.15, 0.15), CFrame.new(0, 1.4, 0), Color3.fromRGB(90, 220, 110), Enum.Material.Neon)
		part(m, Vector3.new(0.15, 0.5, 0.15), CFrame.new(0, 1.4, 0), Color3.fromRGB(90, 220, 110), Enum.Material.Neon)
	elseif id == "VIP" or id == "Duelista" then
		part(m, Vector3.new(0.5, 1.4, 1.4), CFrame.new(0, 0, 0) * CFrame.Angles(0, 0, rad(90)), BRASS, Enum.Material.Metal, Enum.PartType.Cylinder).Reflectance = 0.2
		for i = 0, 5 do
			local a = i / 6 * math.pi * 2
			part(m, Vector3.new(0.18, 0.5, 0.18), CFrame.new(math.cos(a) * 0.6, 0.45, math.sin(a) * 0.6), BRASS, Enum.Material.Metal)
			ball(m, 0.16, CFrame.new(math.cos(a) * 0.68, 0.05, math.sin(a) * 0.68), if i % 2 == 0 then Color3.fromRGB(176, 40, 40) else Color3.fromRGB(60, 120, 200), Enum.Material.Neon)
		end
		if id == "Duelista" then
			-- duas facas cruzadas atrás da coroa
			local k1 = Instance.new("Model")
			knife(k1, Config.TierColors[5], false, 0.7)
			k1:PivotTo(CFrame.new(0, 0.2, 0.5) * CFrame.Angles(0, 0, rad(40)) * CFrame.Angles(rad(-90), 0, 0))
			for _, d in k1:GetChildren() do d.Parent = m end
			local k2 = Instance.new("Model")
			knife(k2, Config.TierColors[5], false, 0.7)
			k2:PivotTo(CFrame.new(0, 0.2, 0.5) * CFrame.Angles(0, 0, rad(-40)) * CFrame.Angles(rad(-90), 0, 0))
			for _, d in k2:GetChildren() do d.Parent = m end
		end
	elseif id == "SorteDourada" or id == "Bussola" or id == "CaixaDourada" then
		if id == "CaixaDourada" then
			part(m, Vector3.new(1.8, 0.9, 1.3), CFrame.new(0, -0.3, 0), PLANK, Enum.Material.WoodPlanks)
			for _, s in { -1, 1 } do part(m, Vector3.new(1.84, 0.12, 0.12), CFrame.new(0, 0.12, s * 0.62), IRON, Enum.Material.Metal) end
			for i = 1, 3 do goldPotato(m, CFrame.new((i - 2) * 0.5, 0.35, 0) * CFrame.Angles(0, i, rad(20)), 1.3) end
		elseif id == "Bussola" then
			part(m, Vector3.new(0.3, 1.6, 1.6), CFrame.new(0, 0, 0) * CFrame.Angles(0, 0, rad(90)), BRASS, Enum.Material.Metal, Enum.PartType.Cylinder)
			part(m, Vector3.new(0.32, 1.35, 1.35), CFrame.new(0, 0.01, 0) * CFrame.Angles(0, 0, rad(90)), Color3.fromRGB(228, 214, 186), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
			part(m, Vector3.new(0.12, 0.06, 1.0), CFrame.new(0, 0.2, 0) * CFrame.Angles(0, rad(30), 0), Color3.fromRGB(190, 40, 40), Enum.Material.Metal)
			goldPotato(m, CFrame.new(0.8, 0.5, 0.6), 0.9)
		else
			goldPotato(m, CFrame.new(0, 0, 0), 2.4)
		end
		local sp = Instance.new("Sparkles") sp.SparkleColor = BRASS sp.Parent = m:FindFirstChildWhichIsA("BasePart")
	elseif id == "MoedasX2" then
		coinStack(m, CFrame.new(-0.4, -0.5, 0), 7)
		coinStack(m, CFrame.new(0.4, -0.5, 0.1), 7)
		part(m, Vector3.new(0.2, 0.5, 0.5), CFrame.new(0, 0.6, -0.4) * CFrame.Angles(0, rad(90), rad(45)), Color3.fromRGB(90, 220, 110), Enum.Material.Neon)
	elseif id == "ChefLendario" then
		chefHat(m, CFrame.new(0, 0, 0), BRASS)
		local sp = Instance.new("Sparkles") sp.SparkleColor = BRASS sp.Parent = m:FindFirstChildWhichIsA("BasePart")
	elseif id == "BatataPet" then
		local b = potato(m, CFrame.new(0, 0, 0), 3.2)
		b.Color = Color3.fromRGB(150, 108, 64)
		for _, s in { -1, 1 } do
			ball(m, 0.26, CFrame.new(0.24 * s, 0.18, -0.68), Color3.fromRGB(245, 240, 230), Enum.Material.SmoothPlastic)
			ball(m, 0.12, CFrame.new(0.24 * s, 0.17, -0.8), DARK, Enum.Material.SmoothPlastic)
		end
		part(m, Vector3.new(0.34, 0.06, 0.06), CFrame.new(0, -0.08, -0.78), Color3.fromRGB(60, 34, 24), Enum.Material.SmoothPlastic)
		part(m, Vector3.new(0.18, 0.75, 0.75), CFrame.new(0, 0.6, 0.05) * CFrame.Angles(0, 0, rad(90)), Color3.fromRGB(236, 232, 222), Enum.Material.Fabric, Enum.PartType.Cylinder)
		ball(m, 0.7, CFrame.new(0, 0.85, 0.05), Color3.fromRGB(240, 236, 228), Enum.Material.Fabric)
	elseif id == "FacaDeOuro" then
		knife(m, BRASS, false, 1.1)
		for _, d in m:GetChildren() do
			if d:IsA("BasePart") and (d.Material == Enum.Material.Metal or d.Material == Enum.Material.SmoothPlastic) then
				d.Color = Color3.fromRGB(240, 196, 60)
				d.Material = Enum.Material.Metal
				d.Reflectance = 0.25
			end
		end
		local sp = Instance.new("Sparkles") sp.SparkleColor = BRASS sp.Parent = m:FindFirstChildWhichIsA("BasePart")
	elseif id == "CarrinhoDeOuro" then
		local c = kitchenModel("Cart") :: Model
		for _, d in c:GetChildren() do
			if d:IsA("BasePart") and d.Material ~= Enum.Material.Ground then
				d.Color = Color3.fromRGB(230, 186, 70)
				d.Material = Enum.Material.Metal
				d.Reflectance = 0.15
			end
			d.Parent = m
		end
	elseif id == "CarrocaReal" then
		-- carroça com laterais altas e um monte de batatas transbordando
		local c = kitchenModel("Cart") :: Model
		for _, d in c:GetChildren() do d.Parent = m end
		for _, s in { -1, 1 } do
			part(m, Vector3.new(2.0, 0.35, 0.08), CFrame.new(0, 0.95, 0.62 * s), PLANK, Enum.Material.WoodPlanks)
		end
		for i = 1, 10 do
			potato(m, CFrame.new(((i % 5) - 2) * 0.32, 0.95 + (i % 3) * 0.12, ((i % 2) - 0.5) * 0.5) * CFrame.Angles(0, i, rad(i * 25)), 1)
		end
	elseif id == "DespachoExpresso" then
		-- carroça com rastros de velocidade e uma ampulheta
		local c = kitchenModel("Cart") :: Model
		for _, d in c:GetChildren() do d.Parent = m end
		for i = 1, 3 do
			local s = part(m, Vector3.new(0.06, 0.06, 1.2), CFrame.new(-1.5 - i * 0.15, 0.1 + i * 0.25, 0) * CFrame.Angles(0, rad(90), 0), Color3.fromRGB(255, 220, 140), Enum.Material.Neon)
			s.Transparency = 0.3
		end
		local glass = CFrame.new(0.9, 1.3, 0)
		for _, y in { 0.42, -0.42 } do cylY(m, 0.08, 0.5, glass * CFrame.new(0, y, 0), PLANK, Enum.Material.Wood) end
		local top = ball(m, 0.4, glass * CFrame.new(0, 0.2, 0), Color3.fromRGB(220, 230, 235), Enum.Material.Glass)
		top.Transparency = 0.3
		local bot = ball(m, 0.4, glass * CFrame.new(0, -0.2, 0), Color3.fromRGB(220, 230, 235), Enum.Material.Glass)
		bot.Transparency = 0.3
		ball(m, 0.22, glass * CFrame.new(0, -0.26, 0), Color3.fromRGB(214, 172, 74), Enum.Material.Sand)
	elseif id == "MaquinasTurbo" then
		local c = kitchenModel("AutoPeel") :: Model
		for _, d in c:GetChildren() do d.Parent = m end
		local bolt = part(m, Vector3.new(0.15, 0.9, 0.4), CFrame.new(0.95, 0.6, -0.3) * CFrame.Angles(0, 0, rad(20)), Color3.fromRGB(255, 220, 60), Enum.Material.Neon)
		part(m, Vector3.new(0.15, 0.9, 0.4), CFrame.new(1.05, -0.1, -0.3) * CFrame.Angles(0, 0, rad(-20)), Color3.fromRGB(255, 220, 60), Enum.Material.Neon)
	elseif id == "SacoP" or id == "SacoM" or id == "SacoG" or id == "SacoXG" then
		local s = ({ SacoP = 0.7, SacoM = 0.85, SacoG = 1.0, SacoXG = 1.15 })[id]
		sack(m, CFrame.new(0, 0, 0), s)
		coinStack(m, CFrame.new(0.9 * s, -0.7 * s, -0.3), math.floor(3 + s * 4))
		if id == "SacoXG" or id == "SacoG" then sack(m, CFrame.new(-0.9, -0.2, 0.4), 0.7) end
	elseif id == "Boost2" or id == "Boost3" then
		-- frasco de tônico com rótulo
		cylY(m, 1.1, 1.0, CFrame.new(0, 0, 0), Color3.fromRGB(80, 200, 120), Enum.Material.Glass).Transparency = 0.25
		cylY(m, 0.5, 0.4, CFrame.new(0, 0.8, 0), Color3.fromRGB(80, 200, 120), Enum.Material.Glass).Transparency = 0.25
		cylY(m, 0.25, 0.46, CFrame.new(0, 1.15, 0), PLANK, Enum.Material.Wood)
		cylY(m, 0.95, 0.8, CFrame.new(0, -0.02, 0), if id == "Boost3" then Color3.fromRGB(255, 160, 60) else Color3.fromRGB(120, 255, 160), Enum.Material.Neon)
		part(m, Vector3.new(0.6, 0.4, 0.05), CFrame.new(0, 0, -0.52), Color3.fromRGB(228, 214, 186), Enum.Material.SmoothPlastic)
	elseif id == "PedidoRelampago" or id == "PassePremium" then
		part(m, Vector3.new(1.4, 1.8, 0.06), CFrame.new(0, 0, 0), Color3.fromRGB(228, 214, 186), Enum.Material.SmoothPlastic)
		for _, y in { 0.95, -0.95 } do cylY(m, 0.3, 1.6, CFrame.new(0, y, 0) * CFrame.Angles(0, 0, rad(90)), Color3.fromRGB(200, 186, 150), Enum.Material.SmoothPlastic) end
		if id == "PedidoRelampago" then
			part(m, Vector3.new(0.25, 0.9, 0.08), CFrame.new(0.05, 0.2, -0.05) * CFrame.Angles(0, 0, rad(20)), Color3.fromRGB(255, 220, 60), Enum.Material.Neon)
			part(m, Vector3.new(0.25, 0.9, 0.08), CFrame.new(-0.05, -0.4, -0.05) * CFrame.Angles(0, 0, rad(-20)), Color3.fromRGB(255, 220, 60), Enum.Material.Neon)
		else
			ball(m, 0.6, CFrame.new(0, -0.5, -0.06), Color3.fromRGB(176, 40, 40), Enum.Material.SmoothPlastic).Size = Vector3.new(0.6, 0.6, 0.1)
			for i = 0, 2 do part(m, Vector3.new(0.9, 0.06, 0.08), CFrame.new(0, 0.5 - i * 0.25, -0.05), Color3.fromRGB(120, 100, 80), Enum.Material.SmoothPlastic) end
		end
	elseif id == "Banquete" then
		part(m, Vector3.new(2.2, 0.15, 1.2), CFrame.new(0, -0.2, 0), PLANK, Enum.Material.WoodPlanks)
		for _, x in { -0.9, 0.9 } do for _, z in { -0.45, 0.45 } do part(m, Vector3.new(0.12, 0.6, 0.12), CFrame.new(x, -0.55, z), PLANK, Enum.Material.Wood) end end
		part(m, Vector3.new(0.15, 1.2, 1.2), CFrame.new(0, -0.08, 0) * CFrame.Angles(0, 0, rad(90)), Color3.fromRGB(200, 200, 205), Enum.Material.Metal, Enum.PartType.Cylinder)
		local roast = ball(m, 0.8, CFrame.new(0, 0.2, 0), Color3.fromRGB(150, 80, 40), Enum.Material.SmoothPlastic)
		roast.Size = Vector3.new(0.9, 0.55, 0.7)
		for i = 1, 4 do potato(m, CFrame.new(-0.85 + (i % 2) * 0.25, 0.05, (i - 2.5) * 0.25), 0.8) end
		part(m, Vector3.new(0.3, 0.5, 0.3), CFrame.new(0.8, 0.1, 0), BRASS, Enum.Material.Metal)
		ball(m, 0.38, CFrame.new(0.8, 0.45, 0), BRASS, Enum.Material.Metal)
	else
		return nil
	end
	return m
end

-- Máquina de verdade da esteira da minha cozinha (vem escondida: mostra as peças).
local MACHINE_OF = { Washer = "Washer", Cutter = "Cutter", Feeder = "Feeder", AutoPeel = "AutoPeeler", Drum = "Drum", Masher = "Masher" }

local function machineModel(upgradeId: string): Model?
	local idx = player:GetAttribute("OwnKitchenIndex")
	local K = idx and Workspace:FindFirstChild("Kitchens") and Workspace.Kitchens:FindFirstChild("Kitchen" .. idx)
	if not K then
		return nil
	end
	local src: Instance? = nil
	if upgradeId == "Cart" then
		src = K:FindFirstChild("Cart")
	elseif upgradeId == "Belt" then
		src = K:FindFirstChild("Belt")
	elseif MACHINE_OF[upgradeId] then
		src = K.Belt:FindFirstChild(MACHINE_OF[upgradeId])
	end
	if not src then
		return nil
	end
	local m = Instance.new("Model")
	for _, d in src:GetDescendants() do
		if d:IsA("BasePart") and not d:IsDescendantOf(src:FindFirstChild("Items") or m) and d.Name ~= "BeltRoot" then
			if upgradeId == "Belt" and (d:IsDescendantOf(src:FindFirstChild("AutoPeeler") or m) or d:IsDescendantOf(src:FindFirstChild("Washer") or m) or d:IsDescendantOf(src:FindFirstChild("Cutter") or m) or d:IsDescendantOf(src:FindFirstChild("Feeder") or m) or d:IsDescendantOf(src:FindFirstChild("Drum") or m) or d:IsDescendantOf(src:FindFirstChild("Masher") or m)) then
				continue
			end
			local c = d:Clone()
			c:ClearAllChildren()
			c.Anchored = true
			local base = d:GetAttribute("BaseTransparency")
			c.Transparency = if base ~= nil then base elseif d.Transparency >= 1 then 1 else d.Transparency
			if d.Transparency >= 1 and base == nil then
				c:Destroy()
			else
				c.Parent = m
			end
		end
	end
	return if #m:GetChildren() > 0 then m else nil
end

local function themeModel(themeId: string): Model
	local m = Instance.new("Model")
	local th = Config.Themes[themeId] or Config.Themes.Castelo
	local function mat(spec)
		return (Enum.Material :: any)[spec[1]], spec[2]
	end
	local fm, fc = mat(th.Floor)
	part(m, Vector3.new(2, 0.2, 2), CFrame.new(0, -0.6, 0), fc, fm)
	local wm, wc = mat(th.Wall)
	part(m, Vector3.new(2, 1.4, 0.2), CFrame.new(0, 0.2, 1), wc, wm)
	local lm, lc = mat(th.Lower or th.Wall)
	part(m, Vector3.new(2.02, 0.5, 0.22), CFrame.new(0, -0.25, 1), lc, lm)
	part(m, Vector3.new(0.3, 0.3, 0.3), CFrame.new(0, 0.7, 0.5), th.Light, Enum.Material.Neon)
	return m
end

-- Cria a miniatura para uma linha da loja. kind: "Tool" | "Item" | "Upgrade" | "Theme" | "Pass"
function ItemPreview.Make(parent: GuiObject, kind: string, id: string): ViewportFrame
	local vpf = Instance.new("ViewportFrame")
	vpf.Name = "Preview"
	vpf.BackgroundColor3 = Color3.fromRGB(36, 30, 26)
	vpf.Ambient = Color3.fromRGB(165, 155, 145)
	vpf.LightColor = Color3.fromRGB(255, 240, 220)
	vpf.LightDirection = Vector3.new(-0.5, -1, -0.6)
	vpf.Parent = parent
	local model: Model? = nil
	if kind == "Tool" then
		model = toolModel(id)
	elseif kind == "Item" then
		model = collectionModel(id)
	elseif kind == "Upgrade" then
		model = kitchenModel(id) or machineModel(id)
	elseif kind == "Theme" then
		model = themeModel(id)
	elseif kind == "Pass" then
		model = passModel(id)
	end
	if not model then
		-- sem modelo (passes etc.): um selo simples
		local l = Instance.new("TextLabel")
		l.Size = UDim2.fromScale(1, 1)
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.GothamBlack
		l.TextScaled = true
		l.TextColor3 = Color3.fromRGB(214, 172, 74)
		l.Text = if kind == "Pass" then "R$" else "?"
		l.Parent = vpf
		return vpf
	end
	-- ferramentas ficam inclinadas (lâmina para cima) para mostrar o perfil ao girar
	local base = if kind == "Tool" then CFrame.Angles(rad(55), 0, rad(-12)) else CFrame.new()
	local cf, size = model:GetBoundingBox()
	model.WorldPivot = cf
	model:PivotTo(base)
	model.Parent = vpf
	local cam = Instance.new("Camera")
	cam.FieldOfView = 35
	local r = size.Magnitude
	cam.CFrame = CFrame.lookAt(Vector3.new(r * 0.9, r * 0.6, -r * 1.3), Vector3.zero)
	cam.Parent = vpf
	vpf.CurrentCamera = cam
	table.insert(spinning, { Model = model, Base = base })
	return vpf
end

function ItemPreview.Init()
	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		local i = 1
		while i <= #spinning do
			local s = spinning[i]
			if not s.Model.Parent or not s.Model.Parent.Parent then
				table.remove(spinning, i)
			else
				s.Model:PivotTo(CFrame.Angles(0, t * 0.8, 0) * s.Base)
				i += 1
			end
		end
	end)
end

return ItemPreview
