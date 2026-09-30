-- PotatoView: a batata em close do modo Descascar (seções 2.5 e 7.3).
-- Núcleo de polpa + casca feita de pedaços: N colunas (meridianos) x SEG pedaços cada, e cada
-- pedaço com LAYERS camadas. Descascar livre: a faca passa por um pedaço e tira uma camada
-- (HitPatch). A 1ª camada é a casca escura; embaixo aparece uma casca mais clara e fina; a última
-- passada chega na polpa. Cada camada que sai vira uma lasca enrolada que cai na tábua.
-- Id de um pedaço = (coluna - 1) * SEG + segmento.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Geo = require(Shared:WaitForChild("PotatoGeometry"))

local PotatoView = {}
PotatoView.__index = PotatoView

local SEG = Config.Peel.Free.Segments
local LAYERS = Config.Peel.Free.Layers
local THICK = 0.1
local OVERLAP_W = 1.12
local OVERLAP_L = 1.06

-- lasca de casca enrolada (mesh em ReplicatedStorage.Art.PeelCurl)
local art = ReplicatedStorage:FindFirstChild("Art")
local curlModel = art and art:FindFirstChild("PeelCurl")
local CURL = curlModel and curlModel:FindFirstChildWhichIsA("MeshPart", true)

local function newPart(parent: Instance, size: Vector3, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.Plastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function sphere(p: Part)
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Parent = p
end

local function shade(c: Color3, dv: number): Color3
	local h, s, v = c:ToHSV()
	return Color3.fromHSV(h, s, math.clamp(v + dv, 0, 1))
end

-- opts: Type, Strips, A, B, BaseCF, Parent, Seed, Cut (máscara de camadas "0120...")
function PotatoView.new(opts)
	local self = setmetatable({}, PotatoView)
	local def = Config.Potatoes[opts.Type] or Config.Potatoes.Comum
	local A, B, N = opts.A, opts.B, opts.Strips
	self.Def, self.A, self.B, self.N = def, A, B, N
	self.Total = N * SEG
	self.BaseCF = opts.BaseCF
	self.Items = {}
	self.Patches = {} -- id -> { Parts, Colors, Seg, Hits, Main }
	self.Beta = 0 -- giro em volta do eixo comprido (A/D)
	self.Tilt = 0 -- inclinação para frente/trás (W/S)
	self.Model = Instance.new("Model")
	self.Model.Name = "PeelPotato"
	self.Model.Parent = opts.Parent
	local rng = Random.new(opts.Seed or 1)
	local skinMat = (Enum.Material :: any)[def.SkinMaterial or "Plastic"] or Enum.Material.Plastic
	-- casca de baixo: mais clara e lisa (entre a casca e a polpa)
	self.UnderColor = def.SkinColor:Lerp(def.FleshColor, 0.45)

	-- núcleo de polpa (fosca e escura o bastante para não "acender" com as luzes)
	local core = newPart(self.Model, Vector3.new(2 * B, 2 * A, 2 * B) * 0.955, def.FleshColor, Enum.Material.Plastic)
	sphere(core)
	self.Core = core
	table.insert(self.Items, { Part = core, Local = CFrame.identity })

	-- tampinhas das pontas (além de THETA_MAX)
	self.Caps = {}
	local tmax = Geo.THETA_MAX
	for _, sgn in { 1, -1 } do
		local r = B * math.cos(tmax)
		local cap = newPart(self.Model, Vector3.new(r * 2.5, r * 1.4, r * 2.5), shade(def.SkinColor, -0.1), skinMat)
		sphere(cap)
		table.insert(self.Caps, cap)
		table.insert(self.Items, { Part = cap, Local = CFrame.new(0, sgn * A * math.sin(tmax), 0) })
	end

	-- casca em pedaços
	local halfAngle = math.pi / N
	for i = 1, N do
		local phi = Geo.StripAngle(i, N)
		local across = Geo.Across(phi)
		for j = 0, SEG - 1 do
			local th0 = -tmax + 2 * tmax * j / SEG
			local th1 = -tmax + 2 * tmax * (j + 1) / SEG
			local thm = (th0 + th1) / 2
			local p0, p1 = Geo.Surface(th0, phi, A, B), Geo.Surface(th1, phi, A, B)
			local n = Geo.Normal(thm, phi, A, B)
			local up = (p1 - p0).Unit
			local baseWidth = 2 * B * math.max(math.cos(th0), math.cos(th1)) * math.sin(halfAngle)
			local len = (p1 - p0).Magnitude
			local center = Geo.Surface(thm, phi, A, B) + n * (THICK * 0.5)
			local color = shade(def.SkinColor, rng:NextNumber(-0.06, 0.05))
			local seg = newPart(self.Model, Vector3.new(baseWidth * OVERLAP_W, len * OVERLAP_L, THICK), color, skinMat)
			table.insert(self.Items, { Part = seg, Local = CFrame.fromMatrix(center, across, up) })
			local geo = { Center = center, Normal = n, Across = across, Up = up, Width = baseWidth, Len = len }
			local id = (i - 1) * SEG + j + 1
			local patch = { Parts = { seg }, Main = seg, Colors = { [seg] = color }, Seg = geo, Hits = 0, Size = seg.Size }
			-- pintas escuras e "olhos" (só na casca de fora)
			local roll = rng:NextNumber()
			if roll < 0.18 then
				local eye = roll < 0.05
				local size = if eye then Vector3.new(0.1, 0.08, 0.03) else Vector3.new(0.07, 0.05, 0.02) * rng:NextNumber(0.8, 1.5)
				local spot = newPart(self.Model, size, if eye then shade(def.SpotColor, -0.08) else def.SpotColor, skinMat)
				sphere(spot)
				local off = across * rng:NextNumber(-0.3, 0.3) * baseWidth + up * rng:NextNumber(-0.3, 0.3) * len
				table.insert(self.Items, { Part = spot, Local = CFrame.fromMatrix(center + n * (THICK * 0.5 + 0.004) + off, across, up) })
				table.insert(patch.Parts, spot)
				patch.Colors[spot] = spot.Color
			end
			self.Patches[id] = patch
		end
	end

	-- detalhes por tipo (seção 7.3)
	if opts.Type == "Podre" then
		local e = Instance.new("ParticleEmitter")
		e.Texture = "rbxasset://textures/particles/SquareParticle.png"
		e.Color = ColorSequence.new(Color3.fromRGB(18, 18, 14))
		e.Size = NumberSequence.new(0.09)
		e.Rate = 10
		e.Lifetime = NumberRange.new(0.8, 1.4)
		e.Speed = NumberRange.new(1, 2)
		e.SpreadAngle = Vector2.new(180, 180)
		e.RotSpeed = NumberRange.new(-300, 300)
		e.Drag = 1
		e.Parent = core
	elseif opts.Type == "Dourada" then
		for _, patch in self.Patches do
			for _, p in patch.Parts do
				p.Material = Enum.Material.Metal
			end
		end
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 205, 90)
		light.Range = 5
		light.Brightness = 0.4
		light.Parent = core
		self.PulseLight = light
	end

	self:SyncMask(opts.Cut)
	self:Apply()
	return self
end

-- ---------------------------------------------------------------- geometria

function PotatoView:RootCF(): CFrame
	return self.BaseCF * CFrame.Angles(self.Tilt, 0, 0) * CFrame.Angles(0, self.Beta, 0)
end

-- Pedaço de casca num ponto da superfície (espaço local). nil nas pontas.
function PotatoView:PatchAt(p: Vector3): (number?, number?, number?)
	local theta = math.asin(math.clamp(p.Y / self.A, -1, 1))
	local tmax = Geo.THETA_MAX
	if math.abs(theta) > tmax then
		return nil
	end
	local phi = math.atan2(p.X, -p.Z)
	local step = 2 * math.pi / self.N
	local i = math.clamp(math.floor(((phi + step / 2) % (2 * math.pi)) / step) + 1, 1, self.N)
	local j = math.clamp(math.floor((theta + tmax) / (2 * tmax) * SEG) + 1, 1, SEG)
	return (i - 1) * SEG + j, i, j
end

function PotatoView:Id(i: number, j: number): number
	i = ((i - 1) % self.N) + 1
	return (i - 1) * SEG + j
end

-- true se o pedaço já não tem casca (só polpa)
function PotatoView:IsBare(id: number): boolean
	local p = self.Patches[id]
	return p == nil or p.Hits >= LAYERS
end

function PotatoView:RemovedCount(): number
	local n = 0
	for _, p in self.Patches do
		if p.Hits >= LAYERS then
			n += 1
		end
	end
	return n
end

-- Ângulo (local) do lado da batata virado para a câmera (usado pelo controle e pela faca parada).
function PotatoView:FrontPhi(): number
	return -self.Beta
end

-- ---------------------------------------------------------------- movimento

function PotatoView:Apply()
	local root = self:RootCF()
	self.Root = root
	local parts, cfs = {}, {}
	for _, it in self.Items do
		table.insert(parts, it.Part)
		table.insert(cfs, root * it.Local)
	end
	Workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
end

function PotatoView:Spin(delta: number)
	self.Beta += delta
	self.Dirty = true
end

function PotatoView:TiltBy(delta: number)
	local max = Config.Peel.Free.MaxTilt
	self.Tilt = math.clamp(self.Tilt + delta, -max, max)
	self.Dirty = true
end

function PotatoView:Update(_dt: number)
	if self.PulseLight then
		self.PulseLight.Brightness = 0.25 + 0.3 * (0.5 + 0.5 * math.sin(os.clock() * math.pi * 2))
	end
	-- mover ~200 peças por frame pesava: só reposiciona quando a batata gira ou inclina
	if self.Dirty then
		self.Dirty = false
		self:Apply()
	end
end

-- ---------------------------------------------------------------- camadas

-- Lascas vivas (as mais antigas somem quando passa do limite: física e peças demais davam lag).
local MAX_CURLS = 30
local curls: { BasePart } = {}

local function trackCurl(p: BasePart)
	table.insert(curls, p)
	while #curls > MAX_CURLS do
		local old = table.remove(curls, 1)
		if old and old.Parent then
			old:Destroy()
		end
	end
end

local function fadeAway(parts: { BasePart }, lifetime: number)
	task.delay(math.max(lifetime - 0.6, 0), function()
		for _, c in parts do
			if c.Parent then
				TweenService:Create(c, TweenInfo.new(0.6), { Transparency = 1 }):Play()
			end
		end
	end)
	for _, c in parts do
		Debris:AddItem(c, lifetime)
	end
end

-- Mostra o pedaço conforme as camadas tiradas: casca escura / casca de baixo / polpa.
local function paint(self, patch)
	local h = patch.Hits
	for _, p in patch.Parts do
		if p == patch.Main then
			if h <= 0 then
				p.Transparency = 0
				p.Color = patch.Colors[p]
				p.Size = patch.Size
			elseif h < LAYERS then
				p.Transparency = 0
				p.Color = self.UnderColor
				p.Size = Vector3.new(patch.Size.X, patch.Size.Y, patch.Size.Z * 0.45) -- mais fina
			else
				p.Transparency = 1
			end
		else
			p.Transparency = if h <= 0 then 0 else 1 -- pintas só na casca de fora
		end
	end
end

-- A faca passou pelo pedaço: tira uma camada e solta uma lasca. Retorna true se tirou algo.
function PotatoView:HitPatch(id: number, debrisParent: Instance, lifetime: number): boolean
	local patch = self.Patches[id]
	if not patch or patch.Hits >= LAYERS then
		return false
	end
	local wasColor = if patch.Hits == 0 then patch.Colors[patch.Main] else self.UnderColor
	patch.Hits += 1
	paint(self, patch)
	local seg = patch.Seg
	local root = self.Root or self:RootCF()
	local out = root:VectorToWorldSpace(seg.Normal)
	local cf = root * CFrame.fromMatrix(seg.Center, seg.Across, seg.Up)
	local piece
	if CURL then
		piece = CURL:Clone()
		local s = math.max(seg.Width, seg.Len) * 1.5 / CURL.Size.Y
		piece.Size = CURL.Size * s
		piece.TextureID = ""
		piece.CFrame = cf * CFrame.Angles(0, 0, math.rad(90))
	else
		piece = newPart(debrisParent, Vector3.new(seg.Width, seg.Len, 0.05), wasColor)
		piece.CFrame = cf
	end
	piece.Material = patch.Main.Material
	piece.Color = wasColor
	piece.Transparency = 0
	-- cai girando até a tábua por uma curva animada (sem física: bem mais leve)
	piece.Anchored = true
	piece.CanCollide = false
	piece.CanQuery = false
	piece.CanTouch = false
	piece.CastShadow = false
	piece.Parent = debrisParent
	local start = piece.CFrame
	local landing = start.Position + out * 0.9 + root.RightVector * (math.random() - 0.5) * 1.2
	landing = Vector3.new(landing.X, self.BaseCF.Position.Y - self.A + 0.1, landing.Z)
	local spinAxis = root:VectorToWorldSpace(seg.Across)
	local t0 = os.clock()
	local fall = 0.45
	task.spawn(function()
		while piece.Parent do
			local a = math.min((os.clock() - t0) / fall, 1)
			local pos = start.Position:Lerp(landing, a) + Vector3.new(0, math.sin(a * math.pi) * 0.5, 0)
			piece.CFrame = CFrame.new(pos) * CFrame.fromAxisAngle(spinAxis, a * 6) * (start - start.Position)
			if a >= 1 then
				break
			end
			task.wait()
		end
	end)
	trackCurl(piece)
	fadeAway({ piece }, lifetime)
	return true
end

-- Servidor recusou a passada: essas camadas voltam.
function PotatoView:UndoHits(ids: { number })
	for _, id in ids do
		local patch = self.Patches[id]
		if patch and patch.Hits > 0 then
			patch.Hits -= 1
			paint(self, patch)
		end
	end
end

-- Estado exato vindo do servidor ("0120...": camadas tiradas de cada pedaço).
function PotatoView:SyncMask(mask: string?)
	for id, patch in self.Patches do
		local h = if mask then tonumber(string.sub(mask, id, id)) or 0 else 0
		if patch.Hits ~= h then
			patch.Hits = h
			paint(self, patch)
		end
	end
end

-- Batata termina: a casca que sobrou some e ela clareia um pouco (sem neon).
function PotatoView:Glow(time: number)
	for _, patch in self.Patches do
		for _, p in patch.Parts do
			p.Transparency = 1
		end
	end
	for _, cap in self.Caps do
		cap.Transparency = 1
	end
	TweenService:Create(self.Core, TweenInfo.new(time), { Color = self.Def.FleshColor:Lerp(Color3.fromRGB(240, 226, 186), 0.2) }):Play()
end

function PotatoView:Destroy()
	self.Model:Destroy()
end

return PotatoView
