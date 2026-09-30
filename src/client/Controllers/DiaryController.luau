-- DiaryController: painel "Diário" (seção 9) — login diário, missões, Baú do Rei,
-- passe de temporada e códigos. Lê o resumo JSON do atributo "Retention" e pede as ações
-- pelo RetentionRequest. Também mostra no HUD o boost ativo e a Hora Dourada.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local player = Players.LocalPlayer

local Diary = {}

local C
local T
local panel: Frame
local body: ScrollingFrame
local tabButtons = {}
local currentTab = "Missoes"
local busy = false
local statusLabel: TextLabel
local badge: Frame

local TABS = {
	{ Id = "Missoes", Label = "Missões" },
	{ Id = "Bau", Label = "Baú do Rei" },
	{ Id = "Passe", Label = "Temporada" },
	{ Id = "Codigo", Label = "Códigos" },
}

local function summary()
	local raw = player:GetAttribute("Retention")
	if type(raw) ~= "string" then
		return nil
	end
	local ok, s = pcall(HttpService.JSONDecode, HttpService, raw)
	return if ok then s else nil
end

local function request(...)
	if busy then
		return nil
	end
	busy = true
	local ok, res = pcall(function(...)
		return Remotes.RetentionRequest:InvokeServer(...)
	end, ...)
	busy = false
	if ok and res then
		if res.Ok and res.Text then
			C.HUD.Toast(res.Text, T.Gold)
			C.Effects.Play("Coins")
		elseif not res.Ok and res.Reason then
			C.HUD.Toast(res.Reason, T.RustBright)
		end
	end
	return if ok then res else nil
end

local function clock(sec: number): string
	sec = math.max(0, math.floor(sec))
	local h, m, s = sec // 3600, (sec % 3600) // 60, sec % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	end
	return string.format("%d:%02d", m, s)
end

-- ---------------------------------------------------------------- linhas

local function row(order: number, height: number): Frame
	local f = Instance.new("Frame")
	f.LayoutOrder = order
	f.Size = UDim2.new(1, -8, 0, height)
	f.BackgroundColor3 = T.PanelLight
	f.BackgroundTransparency = 0.1
	f.Parent = body
	C.HUD.Corner(f, 6)
	return f
end

local function button(parent: Instance, text: string, enabled: boolean, onClick: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.AnchorPoint = Vector2.new(1, 0.5)
	b.Position = UDim2.new(1, -10, 0.5, 0)
	b.Size = UDim2.fromOffset(130, 40)
	b.Font = T.Font
	b.TextScaled = true
	b.Text = text
	b.BackgroundColor3 = if enabled then T.Rust else T.Panel
	b.TextColor3 = if enabled then T.Gold else T.Dim
	b.AutoButtonColor = enabled
	b.Parent = parent
	C.HUD.Corner(b, 6)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.Parent = b
	if enabled then
		b.Activated:Connect(onClick)
	end
	return b
end

local function bar(parent: Instance, frac: number, y: number)
	local bg = Instance.new("Frame")
	bg.Position = UDim2.fromOffset(12, y)
	bg.Size = UDim2.new(1, -170, 0, 8)
	bg.BackgroundColor3 = T.Panel
	bg.BorderSizePixel = 0
	bg.Parent = parent
	C.HUD.Corner(bg, 4)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(math.clamp(frac, 0, 1), 1)
	fill.BackgroundColor3 = T.Gold
	fill.BorderSizePixel = 0
	fill.Parent = bg
	C.HUD.Corner(fill, 4)
end

local function header(order: number, text: string)
	C.HUD.Label(body, {
		LayoutOrder = order,
		Text = text,
		Font = T.FontTitle,
		TextColor3 = T.Gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -8, 0, 26),
	})
end

-- ---------------------------------------------------------------- abas

local function drawMissions(s)
	local order = 0
	local function list(title: string, missions)
		order += 1
		header(order, title)
		for _, m in missions or {} do
			order += 1
			local f = row(order, 58)
			C.HUD.Label(f, {
				Text = m.Text,
				TextColor3 = if m.Done then T.Dim else T.Bone,
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.new(1, -170, 0, 24),
				Position = UDim2.fromOffset(12, 6),
			})
			bar(f, m.P / math.max(1, m.T), 38)
			C.HUD.Label(f, {
				Text = if m.Done then "FEITA" else string.format("%s/%s · %s Moedas", Format.Int(m.P), Format.Int(m.T), Format.Int(m.Coins or 0)),
				TextColor3 = if m.Done then T.Gold else T.Dim,
				TextXAlignment = Enum.TextXAlignment.Right,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -10, 0.5, 0),
				Size = UDim2.fromOffset(150, 22),
			})
		end
	end
	order += 1
	header(order, string.format("Login diário · dia %d de %d", s.Login and s.Login.Streak or 0, #Config.Login.Rewards))
	list("Missões de hoje", s.Daily)
	list("Missões da semana", s.Weekly)
end

local chestLabel: TextLabel? = nil
local chestReadyAt = 0

local function drawChest(s)
	local f = row(1, 120)
	C.HUD.Label(f, {
		Text = "O Rei recompensa quem fica no posto. A cada 4 horas online o baú abre.",
		TextColor3 = T.Dim,
		TextWrapped = true,
		TextScaled = false,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -170, 0, 44),
		Position = UDim2.fromOffset(12, 8),
	})
	chestReadyAt = os.clock() + (s.ChestLeft or 0)
	chestLabel = C.HUD.Label(f, {
		Text = "",
		Font = T.FontTitle,
		TextColor3 = T.Gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -170, 0, 36),
		Position = UDim2.fromOffset(12, 66),
	})
	button(f, if (s.ChestLeft or 0) <= 0 then "Abrir" else "Trancado", (s.ChestLeft or 0) <= 0, function()
		request("ClaimChest")
	end)
end

local function drawPass(s)
	local p = s.Pass
	if not p then
		return
	end
	local claimedFree, claimedPrem = {}, {}
	for _, l in p.Free or {} do
		claimedFree[l] = true
	end
	for _, l in p.Prem or {} do
		claimedPrem[l] = true
	end
	local top = row(0, 64)
	C.HUD.Label(top, {
		Text = string.format("%s · Nível %d/%d", p.Season or "Temporada", p.Level, Config.Season.Levels),
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -170, 0, 26),
		Position = UDim2.fromOffset(12, 6),
	})
	bar(top, (p.XP % p.XPPer) / p.XPPer, 42)
	C.HUD.Label(top, {
		Text = if p.Premium then "Premium ativo" else "Trilha grátis",
		TextColor3 = if p.Premium then T.Gold else T.Dim,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(150, 22),
	})
	for lvl = 1, Config.Season.Levels do
		local reached = lvl <= p.Level
		local f = row(lvl, 46)
		f.BackgroundTransparency = if reached then 0.1 else 0.5
		C.HUD.Label(f, {
			Text = "Nível " .. lvl,
			TextColor3 = if reached then T.Bone else T.Dim,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.fromOffset(90, 24),
			Position = UDim2.fromOffset(12, 11),
		})
		local function claimBtn(track: string, x: number, claimed: boolean, locked: boolean)
			local ok = reached and not claimed and not locked
			local text = if claimed then "Resgatado" elseif track == "Free" then "Grátis" else "Premium"
			local b = button(f, text, ok, function()
				request("ClaimPass", lvl, track)
			end)
			b.Size = UDim2.fromOffset(110, 34)
			b.Position = UDim2.new(1, x, 0.5, 0)
		end
		claimBtn("Prem", -10, claimedPrem[lvl] == true, not p.Premium)
		claimBtn("Free", -130, claimedFree[lvl] == true, false)
	end
end

local function drawCode()
	local f = row(1, 64)
	local box = Instance.new("TextBox")
	box.Position = UDim2.fromOffset(12, 12)
	box.Size = UDim2.new(1, -170, 0, 40)
	box.PlaceholderText = "Digite o código"
	box.Text = ""
	box.ClearTextOnFocus = false
	box.Font = T.Font
	box.TextScaled = true
	box.TextColor3 = T.Bone
	box.PlaceholderColor3 = T.Dim
	box.BackgroundColor3 = T.Panel
	box.Parent = f
	C.HUD.Corner(box, 6)
	button(f, "Resgatar", true, function()
		local res = request("Redeem", box.Text)
		if res and res.Ok then
			box.Text = ""
		end
	end)
	C.HUD.Label(body, {
		LayoutOrder = 2,
		Text = "Os códigos aparecem nas redes do jogo e em eventos.",
		TextColor3 = T.Dim,
		TextScaled = false,
		TextSize = 15,
		Size = UDim2.new(1, -8, 0, 24),
	})
end

-- ---------------------------------------------------------------- painel

function Diary.Refresh()
	if not panel or not panel.Visible then
		return
	end
	-- não redesenha a aba de código enquanto o jogador digita
	if currentTab == "Codigo" and body:FindFirstChildWhichIsA("Frame") then
		return
	end
	local pos = body.CanvasPosition
	for _, c in body:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	chestLabel = nil
	local s = summary()
	if s then
		if currentTab == "Missoes" then
			drawMissions(s)
		elseif currentTab == "Bau" then
			drawChest(s)
		elseif currentTab == "Passe" then
			drawPass(s)
		else
			drawCode()
		end
	end
	body.CanvasPosition = pos
	for id, b in tabButtons do
		b.BackgroundColor3 = if id == currentTab then T.Rust else T.Panel
	end
end

function Diary.SetTab(id: string)
	currentTab = id
	for _, c in body:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	body.CanvasPosition = Vector2.zero
	Diary.Refresh()
end

function Diary.Toggle()
	panel.Visible = not panel.Visible
	if panel.Visible then
		C.Shop.Close()
		Diary.SetTab(currentTab)
	end
end

-- há algo para resgatar? (pontinho vermelho no botão do Diário)
local function hasClaimable(s): boolean
	if not s then
		return false
	end
	if (s.ChestLeft or 1) <= 0 then
		return true
	end
	local p = s.Pass
	if p then
		local claimed = {}
		for _, l in p.Free or {} do
			claimed[l] = true
		end
		for lvl = 1, p.Level do
			if not claimed[lvl] then
				return true
			end
		end
	end
	return false
end

local function build()
	local gui = C.HUD.Gui()
	panel = Instance.new("Frame")
	panel.Name = "Diary"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.52)
	panel.Size = UDim2.fromOffset(640, 480)
	panel.BackgroundColor3 = T.Panel
	panel.BackgroundTransparency = 0.04
	panel.Visible = false
	panel.ZIndex = 30
	panel.Parent = gui
	C.HUD.Corner(panel, 10)
	C.HUD.Stroke(panel, T.Gold, 3)
	local scale = Instance.new("UIScale")
	scale.Parent = panel
	local function fit()
		local vp = Workspace.CurrentCamera.ViewportSize
		scale.Scale = math.min(1, (vp.Y - 90) / 490, (vp.X - 40) / 650)
	end
	fit()
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)

	C.HUD.Label(panel, {
		Text = "DIÁRIO DO SERVO",
		Font = T.FontTitle,
		TextColor3 = T.Gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -120, 0, 34),
		Position = UDim2.fromOffset(16, 10),
	})
	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -10, 0, 8)
	close.Size = UDim2.fromOffset(44, 40)
	close.Text = "X"
	close.Font = T.Font
	close.TextScaled = true
	close.TextColor3 = T.Bone
	close.BackgroundColor3 = T.PanelLight
	close.Parent = panel
	C.HUD.Corner(close, 6)
	close.Activated:Connect(Diary.Toggle)

	local tabs = Instance.new("Frame")
	tabs.BackgroundTransparency = 1
	tabs.Position = UDim2.fromOffset(12, 54)
	tabs.Size = UDim2.new(1, -24, 0, 42)
	tabs.Parent = panel
	local tl = Instance.new("UIListLayout")
	tl.FillDirection = Enum.FillDirection.Horizontal
	tl.Padding = UDim.new(0, 6)
	tl.SortOrder = Enum.SortOrder.LayoutOrder
	tl.Parent = tabs
	for i, t in TABS do
		local b = Instance.new("TextButton")
		b.Name = "Tab" .. t.Id
		b.LayoutOrder = i
		b.Size = UDim2.new(1 / #TABS, -6, 1, 0)
		b.Text = t.Label
		b.Font = T.Font
		b.TextScaled = true
		b.TextColor3 = T.Bone
		b.BackgroundColor3 = T.Panel
		b.Parent = tabs
		C.HUD.Corner(b, 6)
		C.HUD.Stroke(b, T.Rust, 1)
		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, 8)
		pad.PaddingBottom = UDim.new(0, 8)
		pad.Parent = b
		tabButtons[t.Id] = b
		b.Activated:Connect(function()
			Diary.SetTab(t.Id)
		end)
	end

	body = Instance.new("ScrollingFrame")
	body.Position = UDim2.fromOffset(12, 104)
	body.Size = UDim2.new(1, -24, 1, -116)
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.ScrollBarThickness = 6
	body.ScrollBarImageColor3 = T.Rust
	body.AutomaticCanvasSize = Enum.AutomaticSize.Y
	body.CanvasSize = UDim2.new()
	body.Parent = panel
	local ll = Instance.new("UIListLayout")
	ll.Padding = UDim.new(0, 6)
	ll.SortOrder = Enum.SortOrder.LayoutOrder
	ll.Parent = body

	-- linha de status no HUD: boost ativo e Hora Dourada
	statusLabel = C.HUD.Label(gui, {
		Name = "Status",
		Text = "",
		Visible = false,
		TextColor3 = T.Gold,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 124),
		Size = UDim2.fromOffset(360, 20),
	})
end

function Diary.Init(controllers)
	C = controllers
	T = C.HUD.Theme
	build()

	-- botão na coluna lateral, com pontinho quando há algo para resgatar
	local side = C.HUD.Gui():FindFirstChild("SideBar")
	local template = side and side:FindFirstChild("ShopButton") :: TextButton?
	if side and template then
		local b = template:Clone()
		b.Name = "DiaryButton"
		b.LayoutOrder = 0
		b.Text = "Diário"
		b.Parent = side
		b.Activated:Connect(Diary.Toggle)
		badge = Instance.new("Frame")
		badge.AnchorPoint = Vector2.new(0.5, 0.5)
		badge.Position = UDim2.new(1, -4, 0, 4)
		badge.Size = UDim2.fromOffset(14, 14)
		badge.BackgroundColor3 = T.Blood
		badge.Visible = false
		badge.ZIndex = 3
		badge.Parent = b
		C.HUD.Corner(badge, 7)
		side.Size = UDim2.fromOffset(104, 400)
	end

	player:GetAttributeChangedSignal("Retention"):Connect(function()
		if badge then
			badge.Visible = hasClaimable(summary())
		end
		Diary.Refresh()
	end)
	if badge then
		badge.Visible = hasClaimable(summary())
	end

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.5 then
			return
		end
		acc = 0
		if chestLabel then
			local left = chestReadyAt - os.clock()
			chestLabel.Text = if left <= 0 then "Pronto para abrir!" else "Abre em " .. clock(left)
		end
		local parts = {}
		local ends = player:GetAttribute("BoostEnds") or 0
		local mult = player:GetAttribute("BoostMult") or 1
		if mult > 1 and ends > os.time() then
			table.insert(parts, string.format("Boost x%d · %s", mult, clock(ends - os.time())))
		end
		if Workspace:GetAttribute("GoldenHour") then
			table.insert(parts, "HORA DOURADA")
		end
		if (Workspace:GetAttribute("ServerBoostEnds") or 0) > os.time() then
			table.insert(parts, string.format("Servidor x%d", Workspace:GetAttribute("ServerBoost") or 1))
		end
		statusLabel.Text = table.concat(parts, "   ·   ")
		statusLabel.Visible = #parts > 0
	end)
end

return Diary
