-- PeelController: o modo Descascar (seção 2.5) — descascar LIVRE, como no Potato Please.
--
-- A faca tira uma tira de casca por onde passar, em qualquer direção. A casca tem camadas:
-- cada passada num pedaço tira uma camada (a casca escura, depois a de baixo); para chegar na
-- polpa é preciso passar de novo. A batata gira com A/D (e inclina com W/S), roda do mouse,
-- botão direito arrastando ou os botões na tela (celular). Sem minigame: passar onde já não
-- tem casca raspa a polpa e só tira pontos; passadas limpas seguidas sobem o combo.
-- Com 90% da casca fora a batata fica pronta e vai para a mão (ou direto para a esteira).
--
-- Cada posição do dedo/mouse vira um raio da câmera cruzado com o elipsóide da batata; as
-- posições entre dois frames são interpoladas, então a faca não "pula" pedaços com FPS baixo.
-- O cliente prevê o resultado na hora; o servidor confirma ou corrige.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local PeelMath = require(Shared:WaitForChild("PeelMath"))
local Geo = require(Shared:WaitForChild("PotatoGeometry"))
local Strings = require(Shared:WaitForChild("Strings"))
local Format = require(Shared:WaitForChild("Format"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local PotatoView = require(script.Parent:WaitForChild("PotatoView"))

local player = Players.LocalPlayer
local cfg = Config.Peel
local A, B = cfg.CloseupA, cfg.CloseupB

local Peel = {}

local C
local controls
local camera = Workspace.CurrentCamera

local active = false
local view
local ptype = "Comum"
local strips = 8
local total = 80 -- pedaços de casca
local predictedRemoved = 0 -- pedaços já tirados (previsão local)
local pending: { [number]: { number } } = {} -- seq -> pedaços cortados, até o servidor confirmar
local spinInput = 0 -- -1/0/1 (teclas e botões)
local tiltInput = 0 -- -1/0/1 (W/S)
local spinButtons = 0
local rightDrag = false
local lastCrunch = 0
local SEG = Config.Peel.Free.Segments
local seq = 0
local stroke = nil
local finishing = nil
local exitPending = false
local localCombo = 0
local lastStrokeClock = 0
local lastMult = 1
local validStrokes = 0
local savedCF, savedFov
local closeCF
local camTween = false
local shakeTime, shakeAmp = 0, 0
local stick = Vector2.zero
local lamp: Part?
local viewId: number? = nil
local strokesThisPotato = 0
local hiddenLamp: { BasePart } = {}
local board: Part? = nil

local buildView -- definida mais abaixo

local RESULT_TEXT = { Perfect = Strings.Perfect, Good = Strings.Good, Bad = Strings.Bad }
local RESULT_COLOR = {
	Perfect = Color3.fromRGB(240, 200, 80),
	Good = Color3.fromRGB(228, 214, 186),
	Bad = Color3.fromRGB(196, 58, 44),
}

-- ---------------------------------------------------------------- UI do modo

local ui = {}

local function buildUi()
	local T = C.HUD.Theme
	local gui = Instance.new("ScreenGui")
	gui.Name = "PeelGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false -- mesmas coordenadas de ScreenPointToRay/WorldToScreenPoint
	gui.DisplayOrder = 5
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")
	ui.Gui = gui

	-- medidor de precisão sobre a batata
	local meter = Instance.new("Frame")
	meter.Name = "Meter"
	meter.AnchorPoint = Vector2.new(0.5, 1)
	meter.Size = UDim2.fromOffset(230, 14)
	meter.BackgroundColor3 = T.Panel
	meter.BackgroundTransparency = 0.1
	meter.Visible = false
	meter.Parent = gui
	C.HUD.Corner(meter, 4)
	C.HUD.Stroke(meter, T.Rust, 2)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BorderSizePixel = 0
	fill.BackgroundColor3 = T.Bone
	fill.Parent = meter
	C.HUD.Corner(fill, 4)
	for _, x in { Config.Peel.Results.Good.MinPrecision, Config.Peel.Results.Perfect.MinPrecision } do
		local mark = Instance.new("Frame")
		mark.Size = UDim2.new(0, 2, 1, 6)
		mark.AnchorPoint = Vector2.new(0.5, 0.5)
		mark.Position = UDim2.fromScale(x, 0.5)
		mark.BackgroundColor3 = T.Bone
		mark.BorderSizePixel = 0
		mark.ZIndex = 3
		mark.Parent = meter
	end
	ui.Meter = meter
	ui.Fill = fill
	ui.MeterLabel = C.HUD.Label(meter, {
		Text = "",
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.new(0, 0, 0, -26),
	})

	-- progresso das faixas
	ui.StripLabel = C.HUD.Label(gui, {
		Text = "",
		TextColor3 = T.Dim,
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(200, 22),
	})

	-- dica de gesto
	ui.Hint = C.HUD.Label(gui, {
		Text = "",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.fromOffset(560, 30),
		BackgroundColor3 = T.Panel,
		BackgroundTransparency = 0.25,
	})
	C.HUD.Corner(ui.Hint, 6)

	-- rastro do gesto
	ui.Trail = {}
	ui.TrailIndex = 0
	for i = 1, 28 do
		local d = Instance.new("Frame")
		d.AnchorPoint = Vector2.new(0.5, 0.5)
		d.Size = UDim2.fromOffset(12, 12)
		d.BackgroundColor3 = T.Bone
		d.BackgroundTransparency = 1
		d.BorderSizePixel = 0
		d.ZIndex = 4
		d.Parent = gui
		C.HUD.Corner(d, 6)
		ui.Trail[i] = d
	end

	-- cursor do controle
	local cur = Instance.new("Frame")
	cur.AnchorPoint = Vector2.new(0.5, 0.5)
	cur.Size = UDim2.fromOffset(20, 20)
	cur.BackgroundColor3 = T.Bone
	cur.BackgroundTransparency = 0.2
	cur.Visible = false
	cur.ZIndex = 5
	cur.Parent = gui
	C.HUD.Corner(cur, 10)
	C.HUD.Stroke(cur, T.Panel, 2)
	ui.Cursor = cur

	-- botões de girar a batata (celular; no PC também funcionam com o mouse)
	for _, spec in { { "RotL", -1, UDim2.new(0.5, -250, 0.5, 0), "<" }, { "RotR", 1, UDim2.new(0.5, 250, 0.5, 0), ">" } } do
		local b = Instance.new("TextButton")
		b.Name = spec[1]
		b.AnchorPoint = Vector2.new(0.5, 0.5)
		b.Position = spec[3]
		b.Size = UDim2.fromOffset(70, 70)
		b.Text = spec[4]
		b.Font = Enum.Font.GothamBlack
		b.TextScaled = true
		b.TextColor3 = T.Bone
		b.BackgroundColor3 = T.Panel
		b.BackgroundTransparency = 0.25
		b.AutoButtonColor = true
		b.ZIndex = 8
		b.Parent = gui
		C.HUD.Corner(b, 35)
		C.HUD.Stroke(b, T.Rust, 2)
		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, 14)
		pad.PaddingBottom = UDim.new(0, 14)
		pad.Parent = b
		b.MouseButton1Down:Connect(function()
			spinButtons = spec[2]
		end)
		b.MouseButton1Up:Connect(function()
			spinButtons = 0
		end)
		b.MouseLeave:Connect(function()
			spinButtons = 0
		end)
		ui[spec[1]] = b
	end

	-- mão do tutorial
	ui.Hand = C.HUD.Label(gui, {
		Text = "☝",
		TextColor3 = T.Bone,
		Font = Enum.Font.GothamBold,
		AnchorPoint = Vector2.new(0.3, 0),
		Size = UDim2.fromOffset(56, 56),
		Visible = false,
		ZIndex = 7,
	})
	local hs = Instance.new("UIStroke")
	hs.Thickness = 2
	hs.Color = Color3.fromRGB(20, 14, 10)
	hs.Parent = ui.Hand
end

local function trailAdd(pos: Vector2)
	ui.TrailIndex = ui.TrailIndex % #ui.Trail + 1
	local d = ui.Trail[ui.TrailIndex]
	d.Position = UDim2.fromOffset(pos.X, pos.Y)
	d.Size = UDim2.fromOffset(12, 12)
	d.BackgroundTransparency = 0.15
	TweenService:Create(d, TweenInfo.new(0.3), { BackgroundTransparency = 1, Size = UDim2.fromOffset(4, 4) }):Play()
end

local function toScreen(world: Vector3): Vector2
	local p = camera:WorldToScreenPoint(world)
	return Vector2.new(p.X, p.Y)
end

local function popup(text: string, color: Color3, world: Vector3, size: number, rise: number)
	local pos = toScreen(world)
	local l = C.HUD.Label(ui.Gui, {
		Text = text,
		TextColor3 = color,
		Font = C.HUD.Theme.FontTitle,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(pos.X, pos.Y),
		Size = UDim2.fromOffset(size * 6, size),
		ZIndex = 6,
	})
	local s = Instance.new("UIStroke")
	s.Thickness = 2
	s.Color = Color3.fromRGB(18, 12, 8)
	s.Parent = l
	local sc = Instance.new("UIScale")
	sc.Scale = 1.35
	sc.Parent = l
	TweenService:Create(sc, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(l, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.fromOffset(pos.X, pos.Y - rise),
	}):Play()
	task.delay(0.45, function()
		TweenService:Create(l, TweenInfo.new(0.35), { TextTransparency = 1 }):Play()
		TweenService:Create(s, TweenInfo.new(0.35), { Transparency = 1 }):Play()
	end)
	Debris:AddItem(l, 0.9)
end

local function showMeter(_precision: number, _final: string?)
	ui.Meter.Visible = false -- sem minigame: não há medidor de precisão
end

local function refreshHint()
	if validStrokes >= 3 then
		ui.Hint.Visible = false
		return
	end
	ui.Hint.Visible = true
	ui.Hint.Text = if C.HUD.InputMode() == "Gamepad" then Strings.GamepadHint
		elseif C.HUD.InputMode() == "Touch" then Strings.FreePeelHintTouch
		else Strings.FreePeelHint
end

local function progressText(): string
	return string.format(Strings.SkinLeft, math.floor(math.min(predictedRemoved / math.max(total, 1) / Config.Peel.Free.FinishFraction, 1) * 100 + 0.5))
end

-- ---------------------------------------------------------------- medição

local function greenFrac(): number
	-- tutorial: na primeira batata a faixa verde é 2x mais larga
	return PeelMath.GreenWidth(player:GetAttribute("ToolId"), player:GetAttribute("Assisted") == true, C.Tutorial.IsFirstPotato())
end

-- (a mão animada do tutorial mostrava o gesto da faixa verde; sem minigame ela não aparece)
local function handVisible(): boolean
	return false
end

-- Ponto (local) da batata sob o dedo/mouse, ou nil.
local function measurePointer(pos: Vector2): Vector3?
	local ray = camera:ScreenPointToRay(pos.X, pos.Y)
	return Geo.RayHit(view.Root, A, B, ray.Origin, ray.Direction)
end

-- Controle: o analógico direito percorre a faixa verde (theta) com desvio lateral.
local function stickPoint(v: Vector2): Vector3
	local theta = math.asin(math.clamp(v.Y, -1, 1) * 0.985)
	return Geo.FromMeasure(theta, math.clamp(v.X, -1, 1) * B * 0.8, view:FrontPhi(), A, B)
end

local function stickScreen(v: Vector2): Vector2
	return toScreen(view.Root * stickPoint(v))
end

-- A lâmina tira uma camada de cada pedaço sob ela (ferramentas melhores são mais largas).
-- Passar onde já não tem casca raspa polpa (conta para perder pontos).
local function knifeCut(hit: Vector3)
	local s = stroke
	local id, i, j = view:PatchAt(hit)
	if not id then
		return
	end
	local width = Config.Peel.Free.KnifeWidth + PeelMath.ToolFor(player:GetAttribute("ToolId")).StripsPerStroke - 1
	for n = 0, width - 1 do
		local off = n - math.floor((width - 1) / 2)
		local pid = view:Id(i + off, j)
		if s.CutSet[pid] then
			continue -- cada passada tira no máximo uma camada de cada pedaço
		end
		if view:HitPatch(pid, C.Effects.Folder(), cfg.StripDebrisLifetime) then
			s.CutSet[pid] = true
			table.insert(s.Cut, pid)
			if os.clock() - lastCrunch > 0.09 then
				lastCrunch = os.clock()
				C.Effects.Play("Crunch", 1.3 + math.random() * 0.3, 0.25)
			end
		elseif off == 0 and not s.Scraped[pid] and view:IsBare(pid) then
			s.Scraped[pid] = true
			s.Flesh += 1
		end
	end
end

local function addSample(hit: Vector3?, weight: number)
	local s = stroke
	if hit == nil then
		return
	end
	s.HasHit = true
	s.Total += weight
	knifeCut(hit)
end

-- ---------------------------------------------------------------- ferramenta na mão
-- A ferramenta equipada aparece no close e segue o dedo/mouse encostando na batata.

local knife: Model? = nil

local function buildKnife()
	if knife then
		knife:Destroy()
	end
	local toolId = player:GetAttribute("ToolId") or "FacaCega"
	local tool = PeelMath.ToolFor(toolId)
	local tier = Config.TierColors[tool.Tier] or Config.TierColors[1]
	local m = Instance.new("Model")
	m.Name = "PeelTool"
	local function piece(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = material
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Parent = m
		return p
	end
	-- convenção: a ponta da lâmina fica em z = -0.45 (a ferramenta "aponta" para -Z)
	-- cabo escuro e gasto; o anel mostra a raridade da ferramenta
	local root = piece("Handle", Vector3.new(0.13, 0.2, 0.6), CFrame.new(0, 0, 0.44), if toolId == "Laser" then tier else Color3.fromRGB(62, 42, 28), if toolId == "Laser" then Enum.Material.Metal else Enum.Material.Wood)
	for _, z in { 0.3, 0.58 } do
		piece("Rivet", Vector3.new(0.15, 0.05, 0.05), CFrame.new(0, 0.02, z), Color3.fromRGB(150, 140, 120), Enum.Material.Metal)
	end
	piece("Ring", Vector3.new(0.17, 0.23, 0.06), CFrame.new(0, 0, 0.12), tier, Enum.Material.Metal)
	if toolId == "Laser" then
		piece("Tip", Vector3.new(0.14, 0.14, 0.4), CFrame.new(0, 0, -0.2), Color3.fromRGB(255, 70, 60), Enum.Material.Neon)
	elseif toolId == "DescascadorY" or toolId == "DescascadorDuplo" then
		piece("ArmL", Vector3.new(0.05, 0.05, 0.45), CFrame.new(-0.18, 0, -0.18) * CFrame.Angles(0, math.rad(-20), 0), Color3.fromRGB(150, 150, 150), Enum.Material.Metal)
		piece("ArmR", Vector3.new(0.05, 0.05, 0.45), CFrame.new(0.18, 0, -0.18) * CFrame.Angles(0, math.rad(20), 0), Color3.fromRGB(150, 150, 150), Enum.Material.Metal)
		piece("Blade", Vector3.new(0.42, 0.05, 0.06), CFrame.new(0, 0, -0.42), Color3.fromRGB(170, 170, 170), Enum.Material.Metal)
	else
		local rusty = toolId == "FacaCega"
		piece("Blade", Vector3.new(0.05, 0.2, 0.6), CFrame.new(0, 0, -0.15), if rusty then Color3.fromRGB(120, 88, 62) else Color3.fromRGB(165, 165, 165), if rusty then Enum.Material.CorrodedMetal else Enum.Material.Metal)
	end
	m.PrimaryPart = root
	m.WorldPivot = CFrame.new()
	m:ScaleTo(1.6) -- legível no close
	m.WorldPivot = CFrame.new()
	m.Parent = C.Effects.Folder()
	knife = m
end

local function surfaceNormal(pLocal: Vector3): Vector3
	return Vector3.new(pLocal.X / (B * B), pLocal.Y / (A * A), pLocal.Z / (B * B)).Unit
end

local function updateKnife()
	if not knife or not view then
		if knife then
			knife:PivotTo(CFrame.new(0, -500, 0))
		end
		return
	end
	local mode = C.HUD.InputMode()
	local screen: Vector2? = nil
	if stroke and stroke.Source == "Pointer" then
		screen = stroke.Last
	elseif mode == "Gamepad" or (stroke and stroke.Source == "Stick") then
		screen = stickScreen(stick)
	elseif mode == "Keyboard" then
		local m = UserInputService:GetMouseLocation()
		if m.X >= 0 and m.Y >= 0 then -- mouse fora da janela: estaciona na ponta da faixa
			screen = m - GuiService:GetGuiInset()
		end
	end
	local contact, normal
	if screen then
		local ray = camera:ScreenPointToRay(screen.X, screen.Y)
		local hit = Geo.RayHit(view.Root, A, B, ray.Origin, ray.Direction)
		if hit then
			contact = view.Root * hit
			normal = view.Root:VectorToWorldSpace(surfaceNormal(hit))
		else
			local depth = (view.Root.Position - camera.CFrame.Position).Magnitude - B
			contact = ray.Origin + ray.Direction * depth
			normal = -camera.CFrame.LookVector
		end
	else
		-- toque sem dedo na tela: a ferramenta espera na ponta de cima da faixa
		local pLocal = Geo.Surface(math.rad(55), view:FrontPhi(), A, B)
		contact = view.Root * pLocal
		normal = view.Root:VectorToWorldSpace(surfaceNormal(pLocal))
	end
	-- segurada de lado (como uma mão à direita), inclinada, a ponta encostando na casca
	local pressing = stroke ~= nil
	local back = if pressing then 0.7 else 1.15
	local cam = camera.CFrame
	local from = contact + (normal * 0.55 + cam.RightVector * 0.85 + cam.UpVector * 0.35).Unit * back
	knife:PivotTo(CFrame.lookAt(from, contact, cam.UpVector))
end

local function pointerPos(): Vector2
	if stroke and stroke.Input and stroke.Input.UserInputType == Enum.UserInputType.Touch then
		local p = stroke.Input.Position
		return Vector2.new(p.X, p.Y)
	end
	return UserInputService:GetMouseLocation() - GuiService:GetGuiInset()
end

local function stepPointer(pos: Vector2)
	local last = stroke.Last
	local d = (pos - last).Magnitude
	if d < 0.5 then
		return
	end
	local n = math.clamp(math.ceil(d / 4), 1, 48)
	for i = 1, n do
		addSample(measurePointer(last:Lerp(pos, i / n)), d / n)
	end
	stroke.Last = pos
	trailAdd(pos)
end

local function stepStick(v: Vector2)
	local last = stroke.Last
	local a, b = stickScreen(last), stickScreen(v)
	local d = (b - a).Magnitude
	if d < 0.5 then
		return
	end
	local n = math.clamp(math.ceil(d / 4), 1, 48)
	for i = 1, n do
		addSample(stickPoint(last:Lerp(v, i / n)), d / n)
	end
	stroke.Last = v
	trailAdd(b)
end

local function currentPrecision(): number
	if not stroke or stroke.Total <= 0 then
		return 0
	end
	return stroke.Inside / stroke.Total
end

-- ---------------------------------------------------------------- feedback

local function shake(time: number, amp: number)
	shakeTime, shakeAmp = time, amp
end

local function fleshChunk(pos: Vector3, out: Vector3)
	local def = Config.Potatoes[ptype]
	local p = Instance.new("Part")
	p.Size = Vector3.new(0.28, 0.2, 0.24)
	p.Color = def.FleshColor
	p.Material = Enum.Material.SmoothPlastic
	p.CanQuery = false
	p.CanTouch = false
	p.CFrame = CFrame.new(pos + out * 0.1)
	p.Parent = C.Effects.Folder()
	p.AssemblyLinearVelocity = out * 4 + Vector3.new(0, 3, 0)
	p.AssemblyAngularVelocity = Vector3.new(4, 7, 2)
	Debris:AddItem(p, 3)
end

local function feedback(text: string, color: Color3?)
	if view then
		popup(text, color or C.HUD.Theme.Dim, view.Root * Vector3.new(0, -A - 0.3, 0), 30, 20)
	end
end

-- ---------------------------------------------------------------- final da batata

local Exit

local function arrive(r)
	C.Effects.Play("Splash")
	C.Effects.Burst(r.DestPos, "Splash", Vector3.yAxis)
	if ui.Gui.Enabled then
		popup("+" .. Format.Coins(r.Value), C.HUD.Theme.Gold, r.DestPos + Vector3.new(0, 0.6, 0), 34, 40)
	end
	if r.Dest == "Hand" then
		C.HUD.Toast(Strings.PutOnBelt, C.HUD.Theme.Gold)
	end
	finishing = nil
	if r.Reward then
		C.Rewards.Golden(r.Reward)
	end
	if exitPending or player:GetAttribute("State") ~= "Peeling" then
		task.delay(0.25, function()
			if active and not finishing then
				Exit()
			end
		end)
	else
		-- luvas / carrinho de mão: a próxima batata já entra no modo Descascar
		task.delay(0.15, function()
			Peel.OnHeldChanged()
		end)
	end
end

-- Brilha 0,2 s e é arremessada em arco até o balde (ou bandeja) em 0,4 s.
local function fly(r)
	finishing.Flying = true
	local from = view.Root.Position
	local to = r.DestPos or from
	view:Destroy()
	view = nil
	local def = Config.Potatoes[ptype]
	local ball = Instance.new("Part")
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.Color = def.FleshColor
	ball.Material = Enum.Material.SmoothPlastic
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = ball
	ball.Parent = C.Effects.Folder()
	local big = Vector3.new(2 * B, 2 * A, 2 * B) * 0.95
	local small = Vector3.new(0.42, 0.52, 0.42)
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local a = math.clamp((os.clock() - t0) / cfg.FinishFlyTime, 0, 1)
		ball.Size = big:Lerp(small, a)
		ball.CFrame = CFrame.new(from:Lerp(to, a) + Vector3.new(0, math.sin(a * math.pi) * 1.8, 0)) * CFrame.Angles(a * 5, a * 3, 0)
		if a >= 1 then
			conn:Disconnect()
			ball:Destroy()
			arrive(r)
		end
	end)
end

local function tryFly()
	if finishing and finishing.GlowDone and finishing.Result and not finishing.Flying and view then
		fly(finishing.Result)
	end
end

local function startFinish()
	finishing = { GlowDone = false }
	local my = finishing
	view:Glow(cfg.FinishGlowTime)
	task.delay(cfg.FinishGlowTime, function()
		if finishing == my then
			my.GlowDone = true
			tryFly()
		end
	end)
	task.delay(3, function()
		if finishing == my and not my.Flying then
			finishing = nil -- servidor não respondeu: sai do modo
			if active then
				Exit()
			end
		end
	end)
end

-- ---------------------------------------------------------------- passadas

-- Envia a passada (ou um pedaço de um arrasto longo) e prevê o resultado na tela.
local function commitStroke(s)
	local cut = s.Cut
	if #cut == 0 and s.Flesh == 0 then
		return -- só passou no ar
	end
	local duration = math.clamp(os.clock() - s.Start, Config.Peel.Free.MinDuration, Config.Peel.Free.MaxDuration)
	local assisted = player:GetAttribute("Assisted") == true
	-- mesmas regras do servidor: LIMPA sobe o combo; RUIM (quase só polpa) zera
	local result
	if #cut >= Config.Peel.Free.CleanMinHits and s.Flesh == 0 then
		result = "Perfect"
	elseif #cut == 0 or s.Flesh > #cut then
		result = "Bad"
	else
		result = "Good"
	end
	if os.clock() - lastStrokeClock > cfg.ComboExpire then
		localCombo = 0
	end
	localCombo = PeelMath.NextCombo(localCombo, result, assisted)
	local rottenNow = ptype == "Podre" and predictedRemoved == 0 and strokesThisPotato == 0
	if rottenNow then
		localCombo = 0
	end
	strokesThisPotato += 1
	lastStrokeClock = os.clock()

	local mid = view.Root.Position
	local out = -camera.CFrame.LookVector
	if result == "Bad" then
		C.Effects.Play("Squish", 0.85, 1)
		fleshChunk(mid, out)
		shake(0.1, 0.03)
	end
	if s.Flesh > 0 then
		popup(Strings.FleshScraped, RESULT_COLOR.Bad, view.Root * Vector3.new(B + 1.1, 0.4, 0), 26, 24)
	end
	if rottenNow then
		C.Effects.Play("Squish", 0.7, 1)
		popup(Strings.RottenPeeled, RESULT_COLOR.Bad, view.Root * Vector3.new(-B - 1.1, 0.4, 0), 40, 30)
	end

	seq += 1
	pending[seq] = cut
	Remotes.PeelStroke:FireServer(seq, cut, s.Flesh, duration)
	validStrokes += 1
	refreshHint()

	predictedRemoved = view:RemovedCount()
	ui.StripLabel.Text = progressText()
	if predictedRemoved >= total * Config.Peel.Free.FinishFraction and not finishing then
		startFinish()
	end
end

local function newStroke(source: string, input: InputObject?)
	return {
		Start = os.clock(),
		Source = source,
		Input = input,
		Total = 0,
		Inside = 0,
		PendingMiss = 0,
		HasHit = false,
		MinT = math.huge,
		MaxT = -math.huge,
		Cut = {},
		CutSet = {},
		Scraped = {},
		Flesh = 0,
	}
end

local function beginStroke(source: string, input: InputObject?)
	if not active or stroke or not view or finishing or camTween then
		return
	end
	stroke = newStroke(source, input)
	if source == "Pointer" then
		local pos = if input and input.UserInputType == Enum.UserInputType.Touch
			then Vector2.new(input.Position.X, input.Position.Y)
			else pointerPos()
		stroke.Last = pos
		addSample(measurePointer(pos), 0)
		trailAdd(pos)
	else
		stroke.Last = stick
		addSample(stickPoint(stick), 0)
	end
	showMeter(0)
end

local function endStroke()
	local s = stroke
	if not s then
		return
	end
	stroke = nil
	commitStroke(s)
	if not s.HasHit then
		ui.Meter.Visible = false
	end
end

-- Arrasto longo: envia o que já foi cortado e continua a passada sem soltar.
local function flushChunk()
	local s = stroke
	if not s or finishing then
		return
	end
	stroke = newStroke(s.Source, s.Input)
	stroke.Last = s.Last
	commitStroke(s)
end

-- ---------------------------------------------------------------- resposta do servidor

local function onResult(r)
	local mine = pending[r.Seq]
	pending[r.Seq] = nil
	if not r.Ok then
		if Config.Dev.DebugPeel then
			warn("[Peel] servidor rejeitou:", r.Reason)
		end
		localCombo = r.Combo or 0
		if finishing and not finishing.Flying then
			-- a batata "terminou" só na previsão: volta como estava
			finishing = nil
			local K = C.Kitchen.GetMine()
			if K and active then
				buildView(K)
			end
		end
		if view then
			if r.Cut then
				view:SyncMask(r.Cut)
			elseif mine then
				view:UndoHits(mine)
			end
			predictedRemoved = view:RemovedCount()
			ui.StripLabel.Text = progressText()
		end
		return
	end
	localCombo = r.Combo
	if r.ComboMult ~= lastMult then
		if r.ComboMult > lastMult then
			C.HUD.Banner(Strings.Combo .. " " .. Format.Mult(r.ComboMult) .. "!")
			C.Effects.Play("ComboUp")
		end
		lastMult = r.ComboMult
	end
	if r.Done then
		if finishing then
			finishing.Result = r
			tryFly()
		elseif view then
			-- o servidor fechou a batata antes da previsão local
			startFinish()
			finishing.Result = r
		end
	end
end

-- ---------------------------------------------------------------- entrar / sair

local function setCharacterHidden(hidden: boolean)
	local char = player.Character
	if not char then
		return
	end
	for _, d in char:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			d.LocalTransparencyModifier = if hidden then 1 else 0
		end
	end
end

local function update(dt: number)
	if not active then
		return
	end
	if not camTween then
		local off = CFrame.identity
		if shakeTime > 0 then
			shakeTime -= dt
			off = CFrame.new((math.random() - 0.5) * shakeAmp, (math.random() - 0.5) * shakeAmp, 0)
		end
		camera.CFrame = closeCF * off
	end
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	setCharacterHidden(true)

	if view then
		-- girar a batata (teclas A/D, setas, botões na tela, analógico esquerdo)
		local spin = spinInput + spinButtons
		if spin ~= 0 then
			view:Spin(math.clamp(spin, -1, 1) * Config.Peel.Free.RotateSpeed * dt)
		end
		if tiltInput ~= 0 then
			view:TiltBy(tiltInput * Config.Peel.Free.TiltSpeed * dt)
		end
		view:Update(dt)

		local top = toScreen(view.Root * Vector3.new(0, A + 0.25, 0))
		ui.Meter.Position = UDim2.fromOffset(top.X, top.Y - 6)
		local bottom = toScreen(view.Root * Vector3.new(0, -A - 0.15, 0))
		ui.StripLabel.Position = UDim2.fromOffset(bottom.X, bottom.Y + 4)

		if stroke then
			if os.clock() - stroke.Start > Config.Peel.Free.ChunkSeconds and not stroke.DebugHold then
				flushChunk() -- arrasto longo: vai em pedaços, sem cancelar nada
			end
			if stroke and not stroke.DebugHold then
				if stroke.Source == "Pointer" then
					stepPointer(pointerPos())
				else
					stepStick(stick)
				end
			end
		end

		-- mão do tutorial desliza de uma ponta à outra da faixa
		local showHand = handVisible()
		ui.Hand.Visible = showHand
		if showHand then
			local a = (os.clock() % 1.2) / 1.2
			local p = top:Lerp(bottom, math.clamp(a * 1.25 - 0.1, 0, 1))
			ui.Hand.Position = UDim2.fromOffset(p.X, p.Y)
			ui.Hand.TextTransparency = if a > 0.85 then (a - 0.85) / 0.15 else 0
		end

		updateKnife()

		local pad = C.HUD.InputMode() == "Gamepad"
		ui.Cursor.Visible = pad
		if pad then
			local p = stickScreen(stick)
			ui.Cursor.Position = UDim2.fromOffset(p.X, p.Y)
		end
	end
end

-- Monta a batata em close da batata que está na mão (também usada ao encadear batatas).
function buildView(K): Vector3
	ptype = player:GetAttribute("HeldType") or "Comum"
	local def = Config.Potatoes[ptype] or Config.Potatoes.Comum
	A, B = def.CloseupA or cfg.CloseupA, def.CloseupB or cfg.CloseupB
	strips = player:GetAttribute("HeldStrips") or def.Strips
	total = player:GetAttribute("HeldTotal") or strips * SEG
	predictedRemoved = player:GetAttribute("HeldRemoved") or 0
	viewId = player:GetAttribute("HeldId")
	strokesThisPotato = 0
	pending = {}

	-- close fixo sobre a mesa; distância calculada para a batata ocupar 40% da altura da tela
	local top = C.Kitchen.TableTop(K)
	local surface = top.CFrame * CFrame.new(-0.2, top.Size.Y / 2, 0)
	local potatoPos = (surface * CFrame.new(0, A + 0.55, 0)).Position
	local dist = (2 * A) / (cfg.PotatoScreenHeight * 2 * math.tan(math.rad(cfg.CameraFieldOfView / 2)))
	local dir = surface:VectorToWorldSpace(Vector3.new(0, 0.5, -1).Unit)
	local camPos = potatoPos + dir * dist
	closeCF = CFrame.lookAt(camPos, potatoPos)

	if view then
		view:Destroy()
	end
	view = PotatoView.new({
		Type = ptype,
		Strips = strips,
		Cut = player:GetAttribute("HeldCut"),
		A = A,
		B = B,
		BaseCF = CFrame.lookAt(potatoPos, camPos),
		Parent = C.Effects.Folder(),
		Seed = viewId or 1,
	})
	view:Apply()
	buildKnife()
	if ui.StripLabel then
		ui.StripLabel.Text = progressText()
	end
	return camPos
end

-- A batata da mão mudou sem sair do modo (encadeamento ou descarte): troca a batata em close.
function Peel.OnHeldChanged()
	if not active or finishing then
		return
	end
	local id = player:GetAttribute("HeldId")
	if id and id ~= viewId and player:GetAttribute("State") == "Peeling" then
		stroke = nil
		local K = C.Kitchen.GetMine()
		if K then
			buildView(K)
			refreshHint()
		end
	end
end

local function enter()
	local K = C.Kitchen.GetMine()
	if not K or active then
		return
	end
	active = true
	exitPending = false
	finishing = nil
	stroke = nil
	localCombo = player:GetAttribute("Combo") or 0
	lastMult = player:GetAttribute("ComboMult") or 1
	local camPos = buildView(K)

	-- luz local para a batata ficar legível na cozinha escura
	lamp = Instance.new("Part")
	lamp.Anchored = true
	lamp.CanCollide = false
	lamp.CanQuery = false
	lamp.Transparency = 1
	lamp.Size = Vector3.new(0.2, 0.2, 0.2)
	lamp.CFrame = CFrame.new(camPos + Vector3.new(0, 1.5, 0))
	lamp.Parent = C.Effects.Folder()
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(250, 236, 216) -- luz neutra: a casca fica marrom de verdade, não laranja
	light.Range = 8
	light.Brightness = 0.5 -- fraca: a batata não fica estourada -- cozinha bem escura: só a batata fica iluminada (sem estourar a cor da casca)
	-- o lampião da mesa fica bem na frente da câmera do close: esconde só para este jogador
	hiddenLamp = {}
	local dressing = K:FindFirstChild("Dressing")
	if dressing then
		for _, n in { "Lamp", "LampCage", "Chain" } do
			local part = dressing:FindFirstChild(n) :: BasePart?
			if part then
				part.LocalTransparencyModifier = 1
				table.insert(hiddenLamp, part)
				local pl = part:FindFirstChildOfClass("PointLight")
				if pl then
					pl.Enabled = false -- a luz de cima estourava a cor da casca
				end
			end
		end
	end
	light.Parent = lamp

	-- tábua de corte gasta sob a batata: as cascas caem sobre ela
	local top = C.Kitchen.TableTop(K)
	board = Instance.new("Part")
	board.Name = "CuttingBoard"
	board.Anchored = true
	board.CanQuery = false
	board.Size = Vector3.new(3.4, 0.14, 2.4)
	board.CFrame = top.CFrame * CFrame.new(-0.2, top.Size.Y / 2 + 0.07, 0)
	board.Color = Color3.fromRGB(122, 84, 52)
	board.Material = Enum.Material.Wood
	board.Parent = C.Effects.Folder()

	savedCF, savedFov = camera.CFrame, camera.FieldOfView
	camera.CameraType = Enum.CameraType.Scriptable
	camTween = true
	local tw = TweenService:Create(camera, TweenInfo.new(cfg.CameraTransition, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = closeCF,
		FieldOfView = cfg.CameraFieldOfView,
	})
	tw:Play()
	tw.Completed:Once(function()
		camTween = false
	end)
	-- personagem travado: o servidor zera WalkSpeed/JumpHeight; aqui escondemos o analógico/pulo
	-- da tela no celular para o dedo ficar livre para a passada
	if controls then
		controls:Disable()
	end
	GuiService.TouchControlsEnabled = false

	ui.Gui.Enabled = true
	ui.Meter.Visible = false
	ui.StripLabel.Text = progressText()
	refreshHint()
	RunService:BindToRenderStep("SpudPeel", Enum.RenderPriority.Camera.Value + 1, update)
end

Exit = function()
	if not active then
		return
	end
	active = false
	exitPending = false
	finishing = nil
	stroke = nil
	RunService:UnbindFromRenderStep("SpudPeel")
	if view then
		view:Destroy()
		view = nil
	end
	if lamp then
		lamp:Destroy()
		lamp = nil
	end
	if board then
		board:Destroy()
		board = nil
	end
	if knife then
		knife:Destroy()
		knife = nil
	end
	for _, part in hiddenLamp do
		part.LocalTransparencyModifier = 0
		local pl = part:FindFirstChildOfClass("PointLight")
		if pl then
			pl.Enabled = true
		end
	end
	hiddenLamp = {}
	ui.Gui.Enabled = false
	setCharacterHidden(false)
	if controls then
		controls:Enable()
	end
	GuiService.TouchControlsEnabled = true
	camTween = true
	local tw = TweenService:Create(camera, TweenInfo.new(cfg.CameraTransition, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {
		CFrame = savedCF,
		FieldOfView = savedFov,
	})
	tw:Play()
	tw.Completed:Once(function()
		camTween = false
		if not active then
			camera.CameraType = Enum.CameraType.Custom
		end
	end)
end

local function onStateChanged()
	local state = player:GetAttribute("State")
	if state == "Peeling" then
		if not active then
			enter()
		end
	elseif active then
		if finishing then
			exitPending = true
		else
			Exit()
		end
	end
end

function Peel.IsActive(): boolean
	return active
end

-- Só no Studio: simula uma passada pelo MESMO pipeline de medição (raio -> elipsóide),
-- porque a entrada automatizada do Studio é lenta demais para a janela de 1 s.
-- lateralPx: desvio lateral em pixels; wobblePx: zigue-zague em pixels.
-- Só no Studio: solta a passada segurada por DebugStroke(..., holdFrac).
function Peel.DebugRelease()
	if stroke and stroke.DebugHold then
		stroke.DebugHold = nil
		stroke.Start = os.clock() - 0.4
		endStroke()
		return "solta"
	end
	return "nada"
end

function Peel.DebugStroke(lateralPx: number?, wobblePx: number?, duration: number?, coverage: number?, holdFrac: number?, spin: number?, tilt: number?)
	if not RunService:IsStudio() or not active or not view or stroke or finishing then
		return "indisponível"
	end
	if spin or tilt then
		view:Spin(spin or 0) -- teste: gira/inclina a batata antes da passada (como A/D e W/S)
		view:TiltBy(tilt or 0)
		view:Update(0)
	end
	local top = toScreen(view.Root * Vector3.new(0, A + 0.15, 0))
	local bottom = toScreen(view.Root * Vector3.new(0, -A - 0.15, 0))
	local cov = coverage or 1
	local from = top:Lerp(bottom, (1 - cov) / 2)
	local to = bottom:Lerp(top, (1 - cov) / 2)
	beginStroke("Pointer", nil)
	stroke.Start = os.clock() - (duration or 0.4)
	stroke.Last = from + Vector2.new(lateralPx or 0, 0)
	stroke.HasHit, stroke.Total, stroke.Inside = false, 0, 0
	stroke.MinT, stroke.MaxT = math.huge, -math.huge
	local steps = 40
	for i = 1, math.floor(steps * (holdFrac or 1)) do
		local a = i / steps
		local zig = (wobblePx or 0) * math.sin(a * math.pi * 6)
		stepPointer(from:Lerp(to, a) + Vector2.new((lateralPx or 0) + zig, 0))
	end
	local prec = currentPrecision()
	if holdFrac then
		stroke.DebugHold = true -- fica "segurando" para a captura de tela
		return string.format("segurando em %.0f%%, precisão %.2f", holdFrac * 100, prec)
	end
	endStroke()
	return string.format("precisão %.2f", prec)
end

function Peel.Init(controllers)
	C = controllers
	buildUi()
	task.spawn(function()
		-- o PlayerModule pode estar em PlayerScripts (antigo) ou em StarterPlayer (atual)
		local pm = player:WaitForChild("PlayerScripts"):FindFirstChild("PlayerModule")
			or game:GetService("StarterPlayer"):WaitForChild("PlayerModule", 10)
		if pm then
			local ok, module = pcall(require, pm)
			if ok and type(module) == "table" and type(module.GetControls) == "function" then
				controls = module:GetControls()
			end
		end
	end)

	player:GetAttributeChangedSignal("State"):Connect(onStateChanged)
	player:GetAttributeChangedSignal("HeldId"):Connect(Peel.OnHeldChanged)
	Remotes.PeelResult.OnClientEvent:Connect(onResult)

	UserInputService.InputBegan:Connect(function(input, processed)
		if not active then
			return
		end
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			if not processed then
				beginStroke("Pointer", input)
			end
		elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
			beginStroke("Stick", input)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Thumbstick2 then
			stick = Vector2.new(input.Position.X, input.Position.Y)
		elseif not active or not view then
			return
		elseif input.KeyCode == Enum.KeyCode.Thumbstick1 then
			spinInput = if math.abs(input.Position.X) > 0.3 then math.sign(input.Position.X) else 0
			tiltInput = if math.abs(input.Position.Y) > 0.3 then -math.sign(input.Position.Y) else 0
		elseif input.UserInputType == Enum.UserInputType.MouseWheel then
			view:Spin(input.Position.Z * 0.3)
		elseif input.UserInputType == Enum.UserInputType.MouseMovement and rightDrag then
			view:Spin(input.Delta.X * 0.012) -- botão direito arrastando gira a batata
		end
	end)
	-- girar com teclado: A/D ou setas
	local SPIN_KEYS = { [Enum.KeyCode.A] = -1, [Enum.KeyCode.Left] = -1, [Enum.KeyCode.D] = 1, [Enum.KeyCode.Right] = 1 }
	local TILT_KEYS = { [Enum.KeyCode.W] = -1, [Enum.KeyCode.Up] = -1, [Enum.KeyCode.S] = 1, [Enum.KeyCode.Down] = 1 }
	local held = {}
	local function refreshSpin()
		local v, t = 0, 0
		for k in held do
			v += SPIN_KEYS[k] or 0
			t += TILT_KEYS[k] or 0
		end
		spinInput = math.clamp(v, -1, 1)
		tiltInput = math.clamp(t, -1, 1)
	end
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not active then
			return
		end
		if SPIN_KEYS[input.KeyCode] or TILT_KEYS[input.KeyCode] then
			held[input.KeyCode] = true
			refreshSpin()
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			rightDrag = true
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if SPIN_KEYS[input.KeyCode] or TILT_KEYS[input.KeyCode] then
			held[input.KeyCode] = nil
			refreshSpin()
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			rightDrag = false
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if not stroke then
			return
		end
		local t = input.UserInputType
		if stroke.Source == "Pointer" and (t == Enum.UserInputType.MouseButton1 or input == stroke.Input) then
			endStroke()
		elseif stroke.Source == "Stick" and input.KeyCode == Enum.KeyCode.ButtonR2 then
			endStroke()
		end
	end)
end

return Peel
