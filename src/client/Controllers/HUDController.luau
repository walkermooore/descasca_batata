-- HUDController: contador de Moedas, combo, avisos, banner e botões de ação.
-- Mobile primeiro: botões grandes no canto inferior direito; dicas de tecla só em PC/console.
-- Estilo: ferro escuro, ferrugem e tom de osso (ambientação sombria).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Format = require(Shared:WaitForChild("Format"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local player = Players.LocalPlayer

local HUD = {}

HUD.Theme = {
	Panel = Color3.fromRGB(28, 24, 21),
	PanelLight = Color3.fromRGB(48, 40, 34),
	Rust = Color3.fromRGB(128, 72, 44),
	RustBright = Color3.fromRGB(176, 96, 52),
	Bone = Color3.fromRGB(228, 214, 186),
	Dim = Color3.fromRGB(150, 138, 118),
	Gold = Color3.fromRGB(214, 172, 74),
	Blood = Color3.fromRGB(176, 52, 40),
	Font = Enum.Font.Oswald,
	FontTitle = Enum.Font.SpecialElite,
}
local T = HUD.Theme

local gui: ScreenGui
local coinsLabel: TextLabel
local coinsScale: UIScale
local comboFrame: Frame
local comboLabel: TextLabel
local comboMultLabel: TextLabel
local comboBar: Frame
local toastLabel: TextLabel
local bannerLabel: TextLabel
local actionBar: Frame
local displayedCoins = 0
local pendingFly = 0
local actionSignature = ""

local function corner(parent, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 6)
	c.Parent = parent
	return c
end
local function stroke(parent, color, thickness)
	local s = Instance.new("UIStroke")
	s.Color = color or T.Rust
	s.Thickness = thickness or 2
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end
local function label(parent, props): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = T.Font
	l.TextColor3 = T.Bone
	l.TextScaled = true
	for k, v in props do
		(l :: any)[k] = v
	end
	l.Parent = parent
	return l
end
HUD.Corner = corner
HUD.Stroke = stroke
HUD.Label = label

function HUD.InputMode(): string
	local t = UserInputService:GetLastInputType()
	if t.Name:find("Gamepad") then
		return "Gamepad"
	elseif t == Enum.UserInputType.Touch then
		return "Touch"
	end
	return "Keyboard"
end

-- ---------------------------------------------------------------- Moedas

local function setCoinsText(v: number)
	coinsLabel.Text = Format.Int(v)
end

local function animateCoins(target: number)
	local from = displayedCoins
	displayedCoins = target
	if target == from then
		setCoinsText(target)
		return
	end
	local nv = Instance.new("NumberValue")
	nv.Value = from
	nv.Changed:Connect(function(v)
		setCoinsText(v)
	end)
	local tw = TweenService:Create(nv, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = target })
	tw:Play()
	tw.Completed:Once(function()
		setCoinsText(target)
		nv:Destroy()
	end)
	if target > from then
		coinsScale.Scale = 1.18
		TweenService:Create(coinsScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
end

local function refreshCoins()
	local coins = player:GetAttribute("Coins") or 0
	animateCoins(math.max(coins - pendingFly, 0))
end

-- Número voa do Salão do Rei (ou da borda da tela) até o contador.
function HUD.FlyCoins(amount: number, worldPos: Vector3?)
	pendingFly += amount
	refreshCoins()
	local cam = Workspace.CurrentCamera
	local vp = cam.ViewportSize
	local start = Vector2.new(vp.X / 2, vp.Y * 0.75)
	if worldPos then
		local sp, onScreen = cam:WorldToScreenPoint(worldPos)
		if onScreen then
			start = Vector2.new(sp.X, sp.Y)
		end
	end
	local fly = label(gui, {
		Text = "+" .. Format.Int(amount),
		TextColor3 = T.Gold,
		Font = T.Font,
		Size = UDim2.fromOffset(180, 46),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(start.X, start.Y),
		ZIndex = 20,
	})
	stroke(fly, Color3.new(0, 0, 0), 2).ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	local target = coinsLabel.AbsolutePosition + coinsLabel.AbsoluteSize / 2
	local tw = TweenService:Create(fly, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = UDim2.fromOffset(target.X, target.Y),
		Size = UDim2.fromOffset(90, 24),
	})
	tw:Play()
	tw.Completed:Once(function()
		fly:Destroy()
		pendingFly = math.max(0, pendingFly - amount)
		refreshCoins()
	end)
end

-- ---------------------------------------------------------------- avisos

local toastToken = 0
function HUD.Toast(text: string, color: Color3?)
	toastToken += 1
	local my = toastToken
	toastLabel.Text = text
	toastLabel.TextColor3 = color or T.Bone
	toastLabel.Visible = true
	toastLabel.TextTransparency = 0
	toastLabel.BackgroundTransparency = 0.2
	task.delay(1.8, function()
		if my ~= toastToken then
			return
		end
		TweenService:Create(toastLabel, TweenInfo.new(0.4), { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
	end)
end

local bannerToken = 0
function HUD.Banner(text: string, color: Color3?)
	bannerToken += 1
	local my = bannerToken
	bannerLabel.Text = text
	bannerLabel.TextColor3 = color or T.Gold
	bannerLabel.TextTransparency = 0
	bannerLabel.Visible = true
	local scale = bannerLabel:FindFirstChildOfClass("UIScale") :: UIScale
	scale.Scale = 1.6
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(1.1, function()
		if my == bannerToken then
			TweenService:Create(bannerLabel, TweenInfo.new(0.35), { TextTransparency = 1 }):Play()
		end
	end)
end

-- ---------------------------------------------------------------- botões de ação

-- actions: lista de { Id, Label, KeyText, PadText, Primary, Disabled, Run }
function HUD.SetActions(actions)
	local mode = HUD.InputMode()
	local sig = mode
	for _, a in actions do
		sig ..= "|" .. a.Id .. (a.Disabled and "x" or "")
	end
	if sig == actionSignature then
		return
	end
	actionSignature = sig
	for _, c in actionBar:GetChildren() do
		if c:IsA("GuiButton") then
			c:Destroy()
		end
	end
	for i, a in actions do
		local size = if a.Primary then 118 else 84
		local b = Instance.new("TextButton")
		b.Name = a.Id
		b.LayoutOrder = if a.Primary then 100 else i
		b.Size = UDim2.fromOffset(size, size)
		b.BackgroundColor3 = if a.Disabled then T.PanelLight else (if a.Primary then T.Rust else T.Panel)
		b.BackgroundTransparency = 0.08
		b.AutoButtonColor = true
		b.Text = ""
		b.Parent = actionBar
		corner(b, size)
		stroke(b, if a.Primary then T.Gold else T.Rust, 3)
		label(b, {
			Text = a.Label,
			TextColor3 = if a.Disabled then T.Dim else T.Bone,
			Size = UDim2.fromScale(0.8, 0.3),
			Position = UDim2.fromScale(0.1, 0.3),
			Font = T.Font,
		})
		local hint = if mode == "Keyboard" then a.KeyText elseif mode == "Gamepad" then a.PadText else nil
		if hint then
			local h = label(b, {
				Text = hint,
				TextColor3 = T.Panel,
				BackgroundTransparency = 0,
				BackgroundColor3 = T.Bone,
				Size = UDim2.fromOffset(34, 22),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.78),
			})
			corner(h, 4)
		end
		b.Activated:Connect(function()
			a.Run()
		end)
	end
end

-- ---------------------------------------------------------------- combo

local function refreshCombo()
	local combo = player:GetAttribute("Combo") or 0
	local mult = player:GetAttribute("ComboMult") or 1
	comboFrame.Visible = combo > 0
	comboLabel.Text = Strings.Combo .. " " .. combo
	comboMultLabel.Text = Format.Mult(mult)
	comboMultLabel.TextColor3 = if mult > 1 then T.Gold else T.Dim
end

-- ---------------------------------------------------------------- construção

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "HUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")

	-- contador de Moedas (topo)
	local pill = Instance.new("Frame")
	pill.Name = "Coins"
	pill.AnchorPoint = Vector2.new(0.5, 0)
	pill.Position = UDim2.new(0.5, 0, 0, 6)
	pill.Size = UDim2.fromOffset(210, 46)
	pill.BackgroundColor3 = T.Panel
	pill.BackgroundTransparency = 0.1
	pill.Parent = gui
	corner(pill, 8)
	stroke(pill, T.Rust, 2)
	coinsScale = Instance.new("UIScale")
	coinsScale.Parent = pill
	local coin = Instance.new("Frame")
	coin.Size = UDim2.fromOffset(28, 28)
	coin.Position = UDim2.fromOffset(12, 9)
	coin.BackgroundColor3 = T.Gold
	coin.Parent = pill
	corner(coin, 14)
	stroke(coin, Color3.fromRGB(120, 88, 30), 2)
	coinsLabel = label(pill, {
		Text = "0",
		TextColor3 = T.Gold,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.new(1, -60, 0, 34),
		Position = UDim2.fromOffset(46, 6),
	})

	-- combo (abaixo das Moedas)
	comboFrame = Instance.new("Frame")
	comboFrame.Name = "Combo"
	comboFrame.AnchorPoint = Vector2.new(0.5, 0)
	comboFrame.Position = UDim2.new(0.5, 0, 0, 58)
	comboFrame.Size = UDim2.fromOffset(210, 40)
	comboFrame.BackgroundColor3 = T.Panel
	comboFrame.BackgroundTransparency = 0.2
	comboFrame.Visible = false
	comboFrame.Parent = gui
	corner(comboFrame, 6)
	stroke(comboFrame, T.Rust, 1)
	comboLabel = label(comboFrame, { Text = "COMBO 0", TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(0.62, -10, 0, 26), Position = UDim2.fromOffset(10, 3) })
	comboMultLabel = label(comboFrame, { Text = "x1", TextXAlignment = Enum.TextXAlignment.Right, Size = UDim2.new(0.38, -10, 0, 26), Position = UDim2.new(0.62, 0, 0, 3) })
	local barBg = Instance.new("Frame")
	barBg.Size = UDim2.new(1, -20, 0, 5)
	barBg.Position = UDim2.new(0, 10, 1, -9)
	barBg.BackgroundColor3 = T.PanelLight
	barBg.BorderSizePixel = 0
	barBg.Parent = comboFrame
	comboBar = Instance.new("Frame")
	comboBar.Size = UDim2.fromScale(1, 1)
	comboBar.BackgroundColor3 = T.RustBright
	comboBar.BorderSizePixel = 0
	comboBar.Parent = barBg

	-- aviso central
	toastLabel = label(gui, {
		Name = "Toast",
		Text = "",
		Visible = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.2),
		Size = UDim2.fromOffset(460, 40),
		BackgroundColor3 = T.Panel,
		BackgroundTransparency = 0.2,
		ZIndex = 10,
	})
	corner(toastLabel, 6)
	local tp = Instance.new("UIPadding")
	tp.PaddingTop = UDim.new(0, 6)
	tp.PaddingBottom = UDim.new(0, 6)
	tp.Parent = toastLabel

	-- banner de combo
	bannerLabel = label(gui, {
		Name = "Banner",
		Text = "",
		Visible = false,
		Font = T.FontTitle,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(520, 70),
		ZIndex = 11,
	})
	local bs = Instance.new("UIStroke")
	bs.Thickness = 3
	bs.Color = Color3.fromRGB(20, 14, 10)
	bs.Parent = bannerLabel
	Instance.new("UIScale").Parent = bannerLabel

	-- barra de ações (canto inferior direito)
	actionBar = Instance.new("Frame")
	actionBar.Name = "Actions"
	actionBar.AnchorPoint = Vector2.new(1, 1)
	actionBar.Position = UDim2.new(1, -24, 1, -24)
	actionBar.Size = UDim2.fromOffset(260, 260)
	actionBar.BackgroundTransparency = 1
	actionBar.Parent = gui
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Right
	list.VerticalAlignment = Enum.VerticalAlignment.Bottom
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 12)
	list.Parent = actionBar

	-- configurações: precisão assistida (acessibilidade, seção 2.5)
	local gear = Instance.new("TextButton")
	gear.Name = "Settings"
	gear.AnchorPoint = Vector2.new(1, 0)
	gear.Position = UDim2.new(1, -12, 0, 6)
	gear.Size = UDim2.fromOffset(46, 46)
	gear.BackgroundColor3 = T.Panel
	gear.BackgroundTransparency = 0.1
	gear.Text = "⚙"
	gear.TextScaled = true
	gear.TextColor3 = T.Bone
	gear.Font = Enum.Font.GothamBold
	gear.Parent = gui
	corner(gear, 8)
	stroke(gear, T.Rust, 2)

	local panel = Instance.new("Frame")
	panel.Name = "SettingsPanel"
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Position = UDim2.new(1, -12, 0, 58)
	panel.Size = UDim2.fromOffset(300, 116)
	panel.BackgroundColor3 = T.Panel
	panel.BackgroundTransparency = 0.05
	panel.Visible = false
	panel.Parent = gui
	corner(panel, 8)
	stroke(panel, T.Rust, 2)
	label(panel, { Text = Strings.Assisted, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, -24, 0, 26), Position = UDim2.fromOffset(12, 8) })
	label(panel, { Text = Strings.AssistedInfo, TextColor3 = T.Dim, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, Size = UDim2.new(1, -24, 0, 34), Position = UDim2.fromOffset(12, 34) })
	local toggle = Instance.new("TextButton")
	toggle.Size = UDim2.new(1, -24, 0, 30)
	toggle.Position = UDim2.fromOffset(12, 76)
	toggle.Font = T.Font
	toggle.TextScaled = true
	toggle.Parent = panel
	corner(toggle, 6)
	local function refreshToggle()
		local on = player:GetAttribute("Assisted") == true
		toggle.Text = if on then Strings.On else Strings.Off
		toggle.BackgroundColor3 = if on then T.RustBright else T.PanelLight
		toggle.TextColor3 = T.Bone
	end
	refreshToggle()
	player:GetAttributeChangedSignal("Assisted"):Connect(refreshToggle)
	toggle.Activated:Connect(function()
		Remotes.PeelAction:FireServer("SetAssisted", not (player:GetAttribute("Assisted") == true))
	end)
	gear.Activated:Connect(function()
		panel.Visible = not panel.Visible
	end)
end

function HUD.Gui(): ScreenGui
	return gui
end

-- ---------------------------------------------------------------- extras da Etapa 2

local extrasLabel: TextLabel
local heldLabel: TextLabel

local function refreshExtras()
	local keys = player:GetAttribute("Keys") or 0
	local frags = player:GetAttribute("Fragments") or 0
	local parts = {}
	if keys > 0 then
		table.insert(parts, string.format(Strings.Keys, keys))
	end
	if frags > 0 then
		table.insert(parts, string.format(Strings.Fragments, frags, Config.Golden.FragmentsPerRoom))
	end
	if player:GetAttribute("HasRoom") then
		table.insert(parts, "Horta Proibida +5%")
	end
	extrasLabel.Text = table.concat(parts, "  ·  ")
	extrasLabel.Visible = #parts > 0
end

local function refreshHeld()
	local parts = {}
	local held = player:GetAttribute("HeldType")
	if held then
		local name = (Config.Potatoes[held] and Config.Potatoes[held].Name) or held
		local extra = player:GetAttribute("ExtraHeld")
		table.insert(parts, string.format(Strings.Holding, name) .. (if extra then " (+1)" else ""))
	end
	local stockMax = player:GetAttribute("StockMax") or 0
	if stockMax > 0 then
		table.insert(parts, string.format(Strings.Stock, player:GetAttribute("Stock") or 0, stockMax))
	end
	heldLabel.Text = table.concat(parts, "   ")
	heldLabel.Visible = #parts > 0
	heldLabel.TextColor3 = if held == "Podre" then T.Blood elseif held == "Dourada" then T.Gold else T.Bone
end

local shopButton: TextButton
local shopPulse: Tween?

function HUD.ShopButton(): TextButton
	return shopButton
end

-- Tutorial: destaca o botão da loja
function HUD.HighlightShop(on: boolean)
	local s = shopButton:FindFirstChildOfClass("UIStroke") :: UIStroke
	if shopPulse then
		shopPulse:Cancel()
		shopPulse = nil
	end
	if on then
		s.Color = T.Gold
		s.Thickness = 3
		shopPulse = TweenService:Create(s, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Thickness = 7 })
		shopPulse:Play()
	else
		s.Color = T.Rust
		s.Thickness = 2
	end
end

local function buildExtras(C)
	extrasLabel = label(gui, {
		Name = "Extras",
		Text = "",
		Visible = false,
		TextColor3 = T.Gold,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 102),
		Size = UDim2.fromOffset(320, 20),
	})
	heldLabel = label(gui, {
		Name = "Held",
		Text = "",
		Visible = false,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -24, 1, -152),
		Size = UDim2.fromOffset(360, 24),
	})
	-- coluna de botões à esquerda: Loja, Construir, Temporada
	local side = Instance.new("Frame")
	side.Name = "SideBar"
	side.AnchorPoint = Vector2.new(0, 0.5)
	side.Position = UDim2.new(0, 12, 0.5, 0)
	side.Size = UDim2.fromOffset(104, 330)
	side.BackgroundTransparency = 1
	side.Parent = gui
	local sl = Instance.new("UIListLayout")
	sl.Padding = UDim.new(0, 8)
	sl.SortOrder = Enum.SortOrder.LayoutOrder
	sl.VerticalAlignment = Enum.VerticalAlignment.Center
	sl.Parent = side
	shopButton = Instance.new("TextButton")
	shopButton.Name = "ShopButton"
	shopButton.LayoutOrder = 1
	shopButton.Size = UDim2.fromOffset(104, 54)
	shopButton.BackgroundColor3 = T.Panel
	shopButton.BackgroundTransparency = 0.08
	shopButton.Font = T.Font
	shopButton.TextScaled = true
	shopButton.TextColor3 = T.Bone
	shopButton.Text = Strings.Shop
	shopButton.Parent = side
	corner(shopButton, 8)
	stroke(shopButton, T.Rust, 2)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.Parent = shopButton
	shopButton.Activated:Connect(function()
		C.Shop.Toggle()
	end)
	local buttons = {
		{ Strings.Season, function() C.Season.Toggle() end },
		{ "Social", function() C.Social.Toggle() end },
		{ "Emotes", function() C.Events.ToggleEmotes() end },
	}
	if Config.Features.Build then
		table.insert(buttons, 1, { Strings.Build .. " [B]", function() C.Build.Toggle() end })
	end
	for i, spec in buttons do
		local b = shopButton:Clone()
		b.Name = "Side" .. i
		b.LayoutOrder = i + 1
		b.Text = spec[1]
		b.Parent = side
		b.Activated:Connect(spec[2])
	end
	for _, a in { "Keys", "Fragments", "HasRoom" } do
		player:GetAttributeChangedSignal(a):Connect(refreshExtras)
	end
	for _, a in { "HeldType", "ExtraHeld", "Stock", "StockMax" } do
		player:GetAttributeChangedSignal(a):Connect(refreshHeld)
	end
	refreshExtras()
	refreshHeld()
end

function HUD.Init(C)
	build()
	buildExtras(C)
	displayedCoins = player:GetAttribute("Coins") or 0
	setCoinsText(displayedCoins)
	player:GetAttributeChangedSignal("Coins"):Connect(refreshCoins)
	for _, attr in { "Combo", "ComboMult" } do
		player:GetAttributeChangedSignal(attr):Connect(refreshCombo)
	end
	refreshCombo()
	RunService.RenderStepped:Connect(function()
		if comboFrame.Visible then
			local deadline = player:GetAttribute("ComboDeadline") or 0
			local left = math.clamp((deadline - Workspace:GetServerTimeNow()) / Config.Peel.ComboExpire, 0, 1)
			comboBar.Size = UDim2.fromScale(left, 1)
		end
	end)
	Remotes.Notify.OnClientEvent:Connect(function(text)
		HUD.Toast(text)
	end)
	Remotes.Delivered.OnClientEvent:Connect(function(amount, pos)
		-- efeito final de entrega: moedas explodindo no Salão do Rei
		if pos then
			for _ = 1, 3 do
				C.Effects.Burst(pos + Vector3.new(math.random(-2, 2), 2, math.random(-2, 2)), "Perfect", Vector3.yAxis)
			end
		end
		HUD.FlyCoins(amount, pos)
		HUD.Toast(string.format(Strings.KingThanks, Format.Int(amount)), T.Gold)
		C.Effects.Play("Coins")
	end)
	UserInputService.LastInputTypeChanged:Connect(function()
		actionSignature = "" -- redesenha dicas de tecla
	end)
end

return HUD
