-- PotatoView: a batata em close do modo Descascar (seções 2.5 e 7.3).
-- Núcleo de polpa + casca feita de pedaços: N faixas (meridianos) x SEG pedaços cada.
-- Descascar livre: a faca tira qualquer pedaço por onde passar (CutPatch); o pedaço vira
-- uma lasca enrolada que cai na tábua. A faixa verde (SetTarget) é o minigame da PERFEITA.
-- Id de um pedaço = (faixa - 1) * SEG + segmento.

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
local THICK = 0.09
local OVERLAP_W = 1.14
local OVERLAP_L = 1.08
local HIGHLIGHT = Color3.fromRGB(200, 180, 150)

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
	p.Material = material or Enum.Material.SmoothPlastic
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

-- opts: Type, Strips, A, B, BaseCF, GreenFrac, Parent, Seed, Cut (máscara "0101..."), Target
function PotatoView.new(opts)
	local self = setmetatable({}, PotatoView)
	local def = Config.Potatoes[opts.Type] or Config.Potatoes.Comum
	local A, B, N = opts.A, opts.B, opts.Strips
	self.Def, self.A, self.B, self.N = def, A, B, N
	self.Total = N * SEG
	self.BaseCF = opts.BaseCF
	self.GreenFrac = opts.GreenFrac
	self.GreenOffset = 0
	self.Items = {}
	self.Strips = {}
	self.Overlay = {}
	self.Patches = {} -- id -> { Parts, Colors, Seg (geometria), Cut }
	self.Current = 0
	self.Beta = 0
	self.Model = Instance.new("Model")
	self.Model.Name = "PeelPotato"
	self.Model.Parent = opts.Parent
	local rng = Random.new(opts.Seed or 1)
	local skinMat = (Enum.Material :: any)[def.SkinMaterial or "SmoothPlastic"] or Enum.Material.SmoothPlastic

	-- núcleo de polpa (clara e lisa, contrasta com a casca fosca)
	local core = newPart(self.Model, Vector3.new(2 * B, 2 * A, 2 * B) * 0.955, def.FleshColor, Enum.Material.Plastic) -- fosca: não reflete as luzes
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
		local strip = { Index = i, Phi = phi, Segments = {} }
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
			-- manchas de terra: cada pedaço com um tom um pouco diferente
			local color = shade(def.SkinColor, rng:NextNumber(-0.06, 0.05))
			local seg = newPart(self.Model, Vector3.new(baseWidth * OVERLAP_W, len * OVERLAP_L, THICK), color, skinMat)
			table.insert(self.Items, { Part = seg, Local = CFrame.fromMatrix(center, across, up) })
			local geo = { Center = center, Normal = n, Across = across, Up = up, Width = baseWidth, Len = len }
			table.insert(strip.Segments, geo)
			local id = (i - 1) * SEG + j + 1
			local patch = { Parts = { seg }, Colors = { [seg] = color }, Seg = geo, Strip = i, Cut = false }
			-- pintas escuras e "olhos" (brotinhos afundados), como batata de verdade
			local roll = rng:NextNumber()
			if roll < 0.45 then
				local eye = roll < 0.12
				local size = if eye then Vector3.new(0.13, 0.1, 0.03) else Vector3.new(0.1, 0.07, 0.02) * rng:NextNumber(0.8, 1.6)
				local spot = newPart(self.Model, size, if eye then shade(def.SpotColor, -0.08) else def.SpotColor, skinMat)
				sphere(spot)
				local off = across * rng:NextNumber(-0.3, 0.3) * baseWidth + up * rng:NextNumber(-0.3, 0.3) * len
				table.insert(self.Items, { Part = spot, Local = CFrame.fromMatrix(center + n * (THICK * 0.5 + 0.004) + off, across, up) })
				table.insert(patch.Parts, spot)
				patch.Colors[spot] = spot.Color
			end
			self.Patches[id] = patch
		end
		self.Strips[i] = strip
	end

	-- faixa verde (sobreposta à faixa-alvo do minigame)
	for _ = 1, SEG do
		local o = newPart(self.Model, Vector3.new(0.1, 0.1, 0.02), Config.GreenZoneColor, Enum.Material.Neon)
		o.Transparency = 0.2
		table.insert(self.Overlay, { Part = o, Local = CFrame.identity })
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
		light.Range = 7
		light.Brightness = 1
		light.Parent = core
		self.PulseLight = light
		local e = Instance.new("ParticleEmitter")
		e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		e.Color = ColorSequence.new(Color3.fromRGB(255, 220, 120))
		e.LightEmission = 1
		e.Size = NumberSequence.new(0.25, 0)
		e.Rate = 8
		e.Lifetime = NumberRange.new(0.5, 0.9)
		e.Speed = NumberRange.new(1, 2)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Parent = core
	end

	self:SyncMask(opts.Cut)
	self:SetTarget(opts.Target or 1)
	self.Beta = Geo.StripAngle(self.Current, self.N) -- começa com a faixa verde virada para a câmera
	self:Apply()
	return self
end

-- ---------------------------------------------------------------- geometria

function PotatoView:HalfStrip(): number
	return Geo.HalfStripWidth(self.B, self.N)
end

function PotatoView:HalfGreen(): number
	return self.GreenFrac * self:HalfStrip()
end

-- Ângulo (local) do centro da faixa verde, incluindo a oscilação da batata torta.
function PotatoView:TargetPhi(): number
	return Geo.StripAngle(self.Current, self.N) + self.GreenOffset
end

function PotatoView:RootCF(): CFrame
	return self.BaseCF * CFrame.Angles(0, self.Beta, 0)
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
	local i = math.floor(((phi + step / 2) % (2 * math.pi)) / step) + 1
	i = math.clamp(i, 1, self.N)
	local j = math.clamp(math.floor((theta + tmax) / (2 * tmax) * SEG) + 1, 1, SEG)
	return (i - 1) * SEG + j, i, j
end

function PotatoView:Id(i: number, j: number): number
	i = ((i - 1) % self.N) + 1
	return (i - 1) * SEG + j
end

function PotatoView:IsCut(id: number): boolean
	local p = self.Patches[id]
	return p == nil or p.Cut
end

function PotatoView:CutCount(): number
	local n = 0
	for _, p in self.Patches do
		if p.Cut then
			n += 1
		end
	end
	return n
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
	local rot = root * CFrame.Angles(0, -self.GreenOffset, 0)
	for _, o in self.Overlay do
		table.insert(parts, o.Part)
		table.insert(cfs, rot * o.Local)
	end
	Workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
end

function PotatoView:SetGreenFrac(frac: number)
	if frac ~= self.GreenFrac then
		self.GreenFrac = frac
		self:SetTarget(self.Current)
	end
end

function PotatoView:SetGreenOffset(offset: number)
	self.GreenOffset = offset
end

-- Gira livremente (teclas, botões, arrasto com o botão direito).
function PotatoView:Spin(delta: number)
	self.Rot = nil
	self.Beta += delta
end

-- Gira suavemente até a faixa i ficar de frente para a câmera.
function PotatoView:RotateTo(index: number, time: number)
	local to = Geo.StripAngle(index, self.N)
	-- caminho mais curto
	local diff = (to - self.Beta + math.pi) % (2 * math.pi) - math.pi
	self.Rot = { From = self.Beta, To = self.Beta + diff, T = 0, Dur = math.max(time, 1e-3) }
end

function PotatoView:Update(dt: number)
	local r = self.Rot
	if r then
		r.T += dt
		local a = math.clamp(r.T / r.Dur, 0, 1)
		a = 1 - (1 - a) * (1 - a)
		self.Beta = r.From + (r.To - r.From) * a
		if r.T >= r.Dur then
			self.Rot = nil
		end
	end
	if self.PulseLight then
		self.PulseLight.Brightness = 0.3 + 0.5 * (0.5 + 0.5 * math.sin(os.clock() * math.pi * 2))
	end
	self:Apply()
end

-- ---------------------------------------------------------------- faixa verde (minigame)

function PotatoView:SetTarget(index: number)
	local prev = self.Strips[self.Current]
	if prev then
		for j = 1, SEG do
			local patch = self.Patches[self:Id(prev.Index, j)]
			for _, p in patch.Parts do
				p.Color = patch.Colors[p]
			end
		end
	end
	self.Current = index
	local strip = self.Strips[index]
	if not strip then
		for _, o in self.Overlay do
			o.Part.Transparency = 1
		end
		return
	end
	local greenW = self.GreenFrac * 2 * self:HalfStrip()
	for j, seg in strip.Segments do
		local patch = self.Patches[self:Id(index, j)]
		for _, p in patch.Parts do
			if p.Size.Z > 0.03 then
				p.Color = patch.Colors[p]:Lerp(HIGHLIGHT, 0.08)
			end
		end
		local o = self.Overlay[j]
		o.Part.Size = Vector3.new(math.min(greenW, seg.Width * 0.98), seg.Len * OVERLAP_L, 0.02)
		o.Local = CFrame.fromMatrix(seg.Center + seg.Normal * (THICK * 0.5 + 0.012), seg.Across, seg.Up)
		-- onde a casca já saiu, a faixa verde some (mostra o progresso)
		o.Part.Transparency = if patch.Cut then 0.75 else 0.2
	end
end

-- ---------------------------------------------------------------- cortar

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

local function hidePatch(self, patch, hidden: boolean)
	patch.Cut = hidden
	for _, p in patch.Parts do
		p.Transparency = if hidden then 1 else 0
	end
	if patch.Strip == self.Current then
		for jj = 1, SEG do
			if self.Patches[self:Id(self.Current, jj)] == patch then
				self.Overlay[jj].Part.Transparency = if hidden then 0.75 else 0.2
			end
		end
	end
end

-- A faca passou por este pedaço: a casca se solta como lasca enrolada. true se cortou agora.
function PotatoView:CutPatch(id: number, debrisParent: Instance, lifetime: number): boolean
	local patch = self.Patches[id]
	if not patch or patch.Cut then
		return false
	end
	hidePatch(self, patch, true)
	local seg = patch.Seg
	local root = self.Root or self:RootCF()
	local out = root:VectorToWorldSpace(seg.Normal)
	local cf = root * CFrame.fromMatrix(seg.Center, seg.Across, seg.Up)
	local piece
	if CURL then
		piece = CURL:Clone()
		local s = math.max(seg.Width, seg.Len) * 1.6 / CURL.Size.Y
		piece.Size = CURL.Size * s
		piece.TextureID = ""
		piece.Material = patch.Parts[1].Material
		piece.CFrame = cf * CFrame.Angles(0, 0, math.rad(90))
	else
		piece = patch.Parts[1]:Clone()
		piece.Transparency = 0
		piece.CFrame = cf
	end
	piece.Color = patch.Colors[patch.Parts[1]]
	piece.Anchored = false
	piece.CanCollide = true
	piece.CanQuery = false
	piece.CanTouch = false
	piece.CastShadow = true
	piece.Parent = debrisParent
	piece.AssemblyLinearVelocity = out * 3 + Vector3.new(0, 2.5, 0) + root.RightVector * (math.random() - 0.5) * 2
	piece.AssemblyAngularVelocity = root:VectorToWorldSpace(seg.Across) * (8 + math.random() * 6)
	fadeAway({ piece }, lifetime)
	return true
end

-- Servidor recusou a passada: esses pedaços voltam.
function PotatoView:RestorePatches(ids: { number })
	for _, id in ids do
		local patch = self.Patches[id]
		if patch and patch.Cut then
			hidePatch(self, patch, false)
		end
	end
end

-- Estado exato vindo do servidor ("0101...", 1 = sem casca).
function PotatoView:SyncMask(mask: string?)
	for id, patch in self.Patches do
		local cut = mask ~= nil and string.sub(mask, id, id) == "1"
		if patch.Cut ~= cut then
			hidePatch(self, patch, cut)
		end
	end
end

-- Batata termina: a casca que sobrou some e ela brilha por um instante.
function PotatoView:Glow(time: number)
	for _, patch in self.Patches do
		for _, p in patch.Parts do
			p.Transparency = 1
		end
	end
	for _, cap in self.Caps do
		cap.Transparency = 1
	end
	for _, o in self.Overlay do
		o.Part.Transparency = 1
	end
	-- brilho discreto (sem neon: antes a batata estourava de claro)
	TweenService:Create(self.Core, TweenInfo.new(time), { Color = self.Def.FleshColor:Lerp(Color3.fromRGB(255, 244, 205), 0.25) }):Play()
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 230, 170)
	light.Range = 5
	light.Brightness = 0
	light.Parent = self.Core
	TweenService:Create(light, TweenInfo.new(time), { Brightness = 0.6 }):Play()
end

function PotatoView:Destroy()
	self.Model:Destroy()
end

return PotatoView
