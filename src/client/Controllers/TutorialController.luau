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
	local hopper = k:FindFirstChild("Belt") and k.Belt:FindFirstChild("Hopper")
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
	end

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

	panel = Instance.new("Frame")
	panel.Name = "Chef"
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, -18)
	panel.Size = UDim2.fromOffset(560, 92)
	panel.BackgroundColor3 = T.Panel
	panel.BackgroundTransparency = 0.06
	panel.Visible = false
	panel.Parent = C.HUD.Gui()
	C.HUD.Corner(panel, 10)
	C.HUD.Stroke(panel, T.Rust, 2)
	local face = Instance.new("Frame")
	face.Size = UDim2.fromOffset(68, 68)
	face.Position = UDim2.fromOffset(12, 12)
	face.BackgroundColor3 = Color3.fromRGB(150, 112, 70)
	face.Parent = panel
	C.HUD.Corner(face, 34)
	C.HUD.Stroke(face, T.Bone, 2)
	C.HUD.Label(face, { Text = "• •\n—", TextColor3 = Color3.fromRGB(30, 22, 16), Size = UDim2.fromScale(1, 1), Font = Enum.Font.GothamBold })
	C.HUD.Label(panel, { Text = Strings.ChefName, TextColor3 = T.RustBright, Font = T.FontTitle, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, -110, 0, 22), Position = UDim2.fromOffset(94, 8) })
	textLabel = C.HUD.Label(panel, {
		Text = "",
		TextWrapped = true,
		TextScaled = false,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, -110, 0, 56),
		Position = UDim2.fromOffset(94, 32),
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
