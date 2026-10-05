-- TutorialController: primeiros 3 minutos (seção 2.11) no cliente.
-- Fala do Chef Tubérculo + seta guia (linha no chão até o objetivo e marcador pulando).
-- O passo vem do servidor pelo atributo TutorialStep.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))

local player = Players.LocalPlayer

local Tutorial = {}

local DONE = 100
local C
local panel: Frame
local textLabel: TextLabel
local marker: BillboardGui
local markerAnchor: Part
local beam: Beam
local a0: Attachment
local a1: Attachment
local lastText = ""
local typeStart: number? = nil
local portrait: ViewportFrame
local portraitModel: Model? = nil
local portraitCam: Camera? = nil
local portraitBase: CFrame? = nil

-- Copia o Chef da cozinha para o retrato (uma vez) e mexe de leve, como se estivesse falando.
local function updatePortrait()
	if not portrait or not panel.Visible then
		return
	end
	if not portraitModel then
		local K = C.Kitchen.GetMine()
		local chef = K and K:FindFirstChild("Chef")
		if not chef then
			return
		end
		local clone = chef:Clone()
		for _, d in clone:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
			elseif d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ProximityPrompt") then
				d:Destroy()
			end
		end
		clone:PivotTo(CFrame.new())
		clone.Parent = portrait
		local cf, size = clone:GetBoundingBox()
		portraitModel = clone
		portraitBase = clone:GetPivot()
		local cam = Instance.new("Camera")
		cam.FieldOfView = 30
		-- rosto: mira entre os olhos e o chapéu (o Chef olha para -Z); as peças invisíveis
		-- do modelo aumentam a caixa, então os olhos são a referência
		local eyes, sum = 0, Vector3.zero
		for _, d in clone:GetDescendants() do
			if d:IsA("BasePart") and d.Name == "Eye" then
				eyes += 1
				sum += d.Position
			end
		end
		local face = if eyes > 0 then sum / eyes + Vector3.new(0, 0.3, 0) else cf.Position
		local faceOffset = chef:GetAttribute("FaceOffset")
		local dir = CFrame.Angles(0, math.rad(faceOffset or 0), 0):VectorToWorldSpace(Vector3.new(0, 0.1, -1)).Unit
		cam.CFrame = CFrame.lookAt(face + dir * (if eyes > 0 then 4.2 else size.Y * 1.35), face)
		cam.Parent = portrait
		portrait.CurrentCamera = cam
		portraitCam = cam
	end
	local t = os.clock()
	local talking = typeStart ~= nil
	local bob = if talking then math.sin(t * 16) * 0.04 else math.sin(t * 2) * 0.02
	local tilt = math.sin(t * 1.3) * math.rad(4)
	portraitModel:PivotTo(portraitBase * CFrame.new(0, bob, 0) * CFrame.Angles(0, tilt, 0))
end

function Tutorial.Step(): number
	return player:GetAttribute("TutorialStep") or DONE
end

function Tutorial.IsFirstPotato(): boolean
	return Tutorial.Step() == 2
end

local function target(): (BasePart?, string?)
	local K = C.Kitchen.GetMine()
	if not K then
		return nil
	end
	local k = K :: any
	local step = Tutorial.Step()
	local state = player:GetAttribute("State")
	local pile = k.Station.Pile.PromptAnchor
	local tableTop = k.Station.Table.TableTop
	-- batata pronta vai para o funil da esteira ou, sem esteira (começo do jogo), para o carrinho
	local hopper = if K:GetAttribute("HasBelt") then k:FindFirstChild("Belt") and k.Belt:FindFirstChild("Hopper") else k.Cart.Root
	local peeled = player:GetAttribute("HeldPeeled") == true
	if step == 1 then
		return pile
	elseif step == 2 or step == 3 or step == 4 then
		if state == "Holding" and peeled then
			return hopper
		elseif state == "Free" and step < 4 then
			return pile
		elseif state == "Holding" then
			return tableTop
		end
	elseif step == 5 then
		return k.Cart.Root
	elseif step == 7 then
		return k.OrderBoard
	end
	return nil
end

local function text(): string?
	local step = Tutorial.Step()
	local t = Strings.Tutorial[step]
	if not t then
		return nil
	end
	if step == 3 then
		return string.format(t, player:GetAttribute("TutorialPeeled") or 0, Config.Tutorial.PotatoesToPeel)
	end
	return t
end

local function update()
	local step = Tutorial.Step()
	local peeling = player:GetAttribute("State") == "Peeling"
	local t = text()
	panel.Visible = t ~= nil and step < DONE and not peeling
	if t and t ~= lastText then
		lastText = t
		textLabel.Text = t
		textLabel.MaxVisibleGraphemes = 0
		typeStart = os.clock()
	end
	if typeStart then
		local n = math.floor((os.clock() - typeStart) * 55)
		if n >= (utf8.len(textLabel.Text) or 0) then
			textLabel.MaxVisibleGraphemes = -1
			typeStart = nil
		else
			textLabel.MaxVisibleGraphemes = n
		end
	end
	updatePortrait()

	local part = if step < DONE and not peeling then target() else nil
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if part and hrp then
		markerAnchor.CFrame = CFrame.new(part.Position + Vector3.new(0, 3.2 + math.sin(os.clock() * 4) * 0.35, 0))
		marker.Enabled = true
		a0.WorldPosition = hrp.Position - Vector3.new(0, 2.6, 0)
		a1.WorldPosition = Vector3.new(part.Position.X, a0.WorldPosition.Y, part.Position.Z)
		beam.Enabled = (a1.WorldPosition - a0.WorldPosition).Magnitude > 3
	else
		marker.Enabled = false
		beam.Enabled = false
	end

	C.HUD.HighlightShop(step == 6)
end

local function onStep()
	local step = Tutorial.Step()
	if step == 6 then
		C.Shop.Highlight(Config.Tutorial.HighlightTool)
	else
		C.Shop.Highlight(nil)
	end
end

function Tutorial.Init(controllers)
	C = controllers
	local T = C.HUD.Theme

	-- balão do Chef: retrato 3D do próprio Chef da cozinha + nome + fala escrita aos poucos
	panel = Instance.new("Frame")
	panel.Name = "Chef"
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, -18)
	panel.Size = UDim2.fromOffset(600, 112)
	panel.BackgroundColor3 = T.Panel
	panel.BackgroundTransparency = 0.04
	panel.Visible = false
	panel.Parent = C.HUD.Gui()
	C.HUD.Corner(panel, 12)
	C.HUD.Stroke(panel, T.Rust, 2)
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(170, 160, 150))
	grad.Parent = panel
	local scale = Instance.new("UIScale")
	scale.Parent = panel
	local function fit()
		local vp = Workspace.CurrentCamera.ViewportSize
		scale.Scale = math.min(1, (vp.X - 40) / 610)
	end
	fit()
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)

	-- moldura do retrato (sai um pouco para fora do balão)
	local frame = Instance.new("Frame")
	frame.Name = "Portrait"
	frame.Size = UDim2.fromOffset(104, 104)
	frame.Position = UDim2.fromOffset(10, -18)
	frame.BackgroundColor3 = Color3.fromRGB(48, 40, 34)
	frame.Parent = panel
	C.HUD.Corner(frame, 14)
	C.HUD.Stroke(frame, T.Gold, 3)
	local vpf = Instance.new("ViewportFrame")
	vpf.Size = UDim2.fromScale(1, 1)
	vpf.BackgroundColor3 = Color3.fromRGB(62, 50, 40)
	vpf.Ambient = Color3.fromRGB(170, 160, 150)
	vpf.LightColor = Color3.fromRGB(255, 236, 210)
	vpf.LightDirection = Vector3.new(-0.4, -0.6, -1)
	vpf.Parent = frame
	C.HUD.Corner(vpf, 14)
	portrait = vpf
	local nameTag = C.HUD.Label(panel, {
		Text = Strings.ChefName,
		TextColor3 = T.Gold,
		Font = T.FontTitle,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -140, 0, 24),
		Position = UDim2.fromOffset(128, 8),
	})
	local st = Instance.new("UIStroke")
	st.Thickness = 1.5
	st.Color = Color3.fromRGB(20, 14, 10)
	st.Parent = nameTag
	textLabel = C.HUD.Label(panel, {
		Text = "",
		TextWrapped = true,
		TextScaled = false,
		TextSize = 19,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, -144, 0, 74),
		Position = UDim2.fromOffset(128, 34),
	})

	-- marcador pulando sobre o objetivo + linha no chão
	local fx = C.Effects.Folder()
	markerAnchor = Instance.new("Part")
	markerAnchor.Name = "TutorialMarker"
	markerAnchor.Anchored = true
	markerAnchor.CanCollide = false
	markerAnchor.CanQuery = false
	markerAnchor.Transparency = 1
	markerAnchor.Size = Vector3.new(0.2, 0.2, 0.2)
	markerAnchor.Parent = fx
	marker = Instance.new("BillboardGui")
	marker.Size = UDim2.fromOffset(60, 60)
	marker.AlwaysOnTop = true
	marker.Enabled = false
	marker.Adornee = markerAnchor
	marker.Parent = markerAnchor
	local arrow = C.HUD.Label(marker, { Text = "▼", TextColor3 = T.Gold, Size = UDim2.fromScale(1, 1), Font = Enum.Font.GothamBold })
	local s = Instance.new("UIStroke")
	s.Thickness = 3
	s.Color = Color3.fromRGB(30, 20, 12)
	s.Parent = arrow

	local beamHolder = Instance.new("Part")
	beamHolder.Name = "TutorialBeam"
	beamHolder.Anchored = true
	beamHolder.CanCollide = false
	beamHolder.CanQuery = false
	beamHolder.Transparency = 1
	beamHolder.Size = Vector3.new(0.2, 0.2, 0.2)
	beamHolder.CFrame = CFrame.new()
	beamHolder.Parent = fx
	a0 = Instance.new("Attachment")
	a0.Parent = beamHolder
	a1 = Instance.new("Attachment")
	a1.Parent = beamHolder
	beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = 0.5
	beam.Width1 = 0.5
	beam.FaceCamera = true
	beam.Color = ColorSequence.new(T.Gold)
	beam.Transparency = NumberSequence.new(0.35)
	beam.LightEmission = 0.6
	beam.Segments = 1
	beam.Enabled = false
	beam.Parent = beamHolder

	player:GetAttributeChangedSignal("TutorialStep"):Connect(onStep)
	onStep()
	RunService.RenderStepped:Connect(update)
end

return Tutorial
