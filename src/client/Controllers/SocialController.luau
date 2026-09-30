-- SocialController: painel Social (cozinhas, jogadores, corrida, rankings), convite para cozinha
-- e faixa "você está na cozinha de X".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local player = Players.LocalPlayer

local Social = {}

local C
local T
local panel: Frame
local list: ScrollingFrame
local tabButtons = {}
local tab = "Cozinhas"
local rankBoard = "Peeled"
local rankScope = "Global"
local invitePopup: Frame
local inviteText: TextLabel
local guestBar: Frame
local guestText: TextLabel
local busy = false

local TABS = { "Cozinhas", "Jogadores", "Corrida", "Ranking" }

local function request(...)
	if busy then
		return nil
	end
	busy = true
	local ok, res = pcall(function(...)
		return Remotes.SocialRequest:InvokeServer(...)
	end, ...)
	busy = false
	if ok and res and not res.Ok and res.Reason then
		C.HUD.Toast(res.Reason, T.RustBright)
	end
	return if ok then res else nil
end

local function clear()
	for _, c in list:GetChildren() do
		if c:IsA("Frame") or c:IsA("TextLabel") then
			c:Destroy()
		end
	end
end

local function btn(parent: Instance, text: string, width: number, enabled: boolean, fn: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(width, 40)
	b.Font = T.Font
	b.TextScaled = true
	b.Text = text
	b.BackgroundColor3 = if enabled then T.Rust else T.Panel
	b.TextColor3 = if enabled then T.Bone else T.Dim
	b.AutoButtonColor = enabled
	b.Parent = parent
	C.HUD.Corner(b, 6)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.Parent = b
	if enabled then
		b.Activated:Connect(fn)
	end
	return b
end

local function row(order: number, title: string, sub: string?): Frame
	local f = Instance.new("Frame")
	f.LayoutOrder = order
	f.Size = UDim2.new(1, -8, 0, 58)
	f.BackgroundColor3 = T.PanelLight
	f.Parent = list
	C.HUD.Corner(f, 6)
	C.HUD.Label(f, { Text = title, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(0.55, -10, 0, 26), Position = UDim2.fromOffset(10, 4) })
	if sub then
		C.HUD.Label(f, { Text = sub, TextColor3 = T.Dim, TextScaled = false, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(0.55, -10, 0, 20), Position = UDim2.fromOffset(10, 32) })
	end
	local actions = Instance.new("Frame")
	actions.Name = "Actions"
	actions.BackgroundTransparency = 1
	actions.AnchorPoint = Vector2.new(1, 0.5)
	actions.Position = UDim2.new(1, -8, 0.5, 0)
	actions.Size = UDim2.new(0.45, 0, 0, 40)
	actions.Parent = f
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Horizontal
	l.HorizontalAlignment = Enum.HorizontalAlignment.Right
	l.Padding = UDim.new(0, 6)
	l.Parent = actions
	return actions
end

local function note(order: number, text: string)
	C.HUD.Label(list, { LayoutOrder = order, Text = text, TextColor3 = T.Dim, TextScaled = false, TextSize = 16, TextWrapped = true, Size = UDim2.new(1, -8, 0, 40) })
end

local function fillKitchens()
	local res = request("Kitchens")
	if not res or not res.Rows then
		return
	end
	note(0, "Visite cozinhas e curta as melhores. As mais curtidas aparecem no mural da praça.")
	local own = player:GetAttribute("OwnKitchenIndex")
	for _, k in res.Rows do
		local title = if k.Owner then string.format("Lote %d · %s", k.Index, k.Owner) else string.format("Lote %d · livre", k.Index)
		local sub = string.format("%s curtidas  ·  %d ajudante(s)", Format.Int(k.Likes or 0), k.Members or 0)
		local a = row(k.Index, title, sub)
		if k.Owner then
			btn(a, "Visitar", 90, true, function()
				if request("Visit", k.Index) then
					panel.Visible = false
				end
			end)
			btn(a, "♥ Curtir", 100, k.Index ~= own, function()
				local r = request("Like", k.Index)
				if r and r.Ok then
					C.HUD.Toast("Você curtiu a cozinha de " .. k.Owner, T.Gold)
					Social.Refresh()
				end
			end)
		end
	end
end

local function fillPlayers()
	local own = player:GetAttribute("OwnKitchenIndex") or 0
	local K = C.Kitchen.GetOwned()
	local members = K and (K:GetAttribute("Members") or "") or ""
	note(0, "Convide até 3 amigos para sua cozinha: +10% de produção por amigo e cada um recebe 30% do que produzir.")
	local i = 1
	for _, p in Players:GetPlayers() do
		if p ~= player then
			i += 1
			local inMine = own ~= 0 and p:GetAttribute("KitchenIndex") == own
			local where = if p:GetAttribute("GuestOf") then "ajudando " .. p:GetAttribute("GuestOf")
				elseif (p:GetAttribute("OwnKitchenIndex") or 0) > 0 then "lote " .. p:GetAttribute("OwnKitchenIndex")
				else "sem cozinha"
			local a = row(i, p.DisplayName, where)
			if inMine then
				btn(a, "Remover", 100, true, function()
					request("Kick", p.UserId)
					task.wait(0.3)
					Social.Refresh()
				end)
			else
				btn(a, "Convidar", 110, own ~= 0, function()
					local r = request("Invite", p.UserId)
					if r and r.Ok then
						C.HUD.Toast("Convite enviado para " .. p.DisplayName, T.Gold)
					end
				end)
			end
		end
	end
	if i == 1 then
		note(1, "Ninguém mais no servidor agora.")
	end
	if members ~= "" then
		note(99, "Na sua cozinha: " .. members)
	end
end

local function fillRace()
	local st = player:GetAttribute("RaceState")
	local queue = Workspace:GetAttribute("RaceQueue") or 0
	note(0, string.format("Corrida de Descascar: %d s, de 2 a %d jogadores. Vence quem descascar mais com precisão. Prêmios: %s Moedas para o 1º.", Config.Race.Duration, Config.Race.MaxPlayers, Format.Int(Config.Race.Rewards[1])))
	local a = row(1, "Fila da corrida", string.format("%d na fila  ·  estado: %s", queue, Workspace:GetAttribute("RaceState") or "Idle"))
	if st == "Queued" or st == "Countdown" then
		btn(a, "Sair da fila", 130, true, function()
			request("RaceLeave")
			task.wait(0.2)
			Social.Refresh()
		end)
	else
		btn(a, "Entrar na fila", 140, st == nil, function()
			request("RaceJoin")
			task.wait(0.2)
			Social.Refresh()
		end)
	end
end

local function fillRanking()
	local boards = Instance.new("Frame")
	boards.LayoutOrder = 0
	boards.BackgroundTransparency = 1
	boards.Size = UDim2.new(1, -8, 0, 40)
	boards.Parent = list
	local bl = Instance.new("UIListLayout")
	bl.FillDirection = Enum.FillDirection.Horizontal
	bl.Padding = UDim.new(0, 6)
	bl.Parent = boards
	for _, b in Config.Rankings.Boards do
		local x = btn(boards, b.Label, 132, true, function()
			rankBoard = b.Id
			Social.Refresh()
		end)
		if b.Id ~= rankBoard then
			x.BackgroundColor3 = T.Panel
		end
	end
	local scopes = Instance.new("Frame")
	scopes.LayoutOrder = 1
	scopes.BackgroundTransparency = 1
	scopes.Size = UDim2.new(1, -8, 0, 40)
	scopes.Parent = list
	local sl = Instance.new("UIListLayout")
	sl.FillDirection = Enum.FillDirection.Horizontal
	sl.Padding = UDim.new(0, 6)
	sl.Parent = scopes
	for _, sc in { { "Global", "Global" }, { "Friends", "Amigos" }, { "Server", "Servidor" } } do
		local x = btn(scopes, sc[2], 110, true, function()
			rankScope = sc[1]
			Social.Refresh()
		end)
		if sc[1] ~= rankScope then
			x.BackgroundColor3 = T.Panel
		end
	end
	local res = request("Rankings", rankBoard, rankScope)
	if not res or not res.Rows or #res.Rows == 0 then
		note(2, "Ninguém no ranking ainda.")
		return
	end
	for i, r in res.Rows do
		local v = if r.Value == math.floor(r.Value) then Format.Int(r.Value) else Format.Dec(r.Value, 1)
		local f = row(i + 2, string.format("%d.  %s", i, r.Name), nil)
		C.HUD.Label(f, { Text = v, TextColor3 = T.Gold, Size = UDim2.new(1, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Right })
	end
end

function Social.Refresh()
	if not panel.Visible then
		return
	end
	for id, b in tabButtons do
		b.BackgroundColor3 = if id == tab then T.Rust else T.Panel
	end
	clear()
	if tab == "Cozinhas" then
		fillKitchens()
	elseif tab == "Jogadores" then
		fillPlayers()
	elseif tab == "Corrida" then
		fillRace()
	else
		fillRanking()
	end
end

function Social.Toggle()
	panel.Visible = not panel.Visible
	if panel.Visible then
		C.Shop.Close()
		task.spawn(Social.Refresh)
	end
end

local function refreshGuest()
	local host = player:GetAttribute("GuestOf")
	guestBar.Visible = host ~= nil
	if host then
		guestText.Text = "Ajudando na cozinha de " .. host .. "  (30% do que você produzir)"
	end
end

function Social.Init(controllers)
	C = controllers
	T = C.HUD.Theme
	local gui = C.HUD.Gui()

	panel = Instance.new("Frame")
	panel.Name = "Social"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.52)
	panel.Size = UDim2.fromOffset(640, 470)
	panel.BackgroundColor3 = T.Panel
	panel.BackgroundTransparency = 0.04
	panel.Visible = false
	panel.ZIndex = 30
	panel.Parent = gui
	C.HUD.Corner(panel, 10)
	C.HUD.Stroke(panel, T.Rust, 3)
	local scale = Instance.new("UIScale")
	scale.Parent = panel
	local function fit()
		local vp = Workspace.CurrentCamera.ViewportSize
		scale.Scale = math.min(1, (vp.Y - 90) / 480, (vp.X - 40) / 650)
	end
	fit()
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	C.HUD.Label(panel, { Text = "SOCIAL", Font = T.FontTitle, TextColor3 = T.Gold, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, -80, 0, 34), Position = UDim2.fromOffset(16, 10) })
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
	close.Activated:Connect(Social.Toggle)
	local tabs = Instance.new("Frame")
	tabs.BackgroundTransparency = 1
	tabs.Position = UDim2.fromOffset(12, 54)
	tabs.Size = UDim2.new(1, -24, 0, 42)
	tabs.Parent = panel
	local tl = Instance.new("UIListLayout")
	tl.FillDirection = Enum.FillDirection.Horizontal
	tl.Padding = UDim.new(0, 6)
	tl.Parent = tabs
	for _, id in TABS do
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(1 / #TABS, -6, 1, 0)
		b.Text = id
		b.Font = T.Font
		b.TextScaled = true
		b.TextColor3 = T.Bone
		b.BackgroundColor3 = T.Panel
		b.Parent = tabs
		C.HUD.Corner(b, 6)
		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, 8)
		pad.PaddingBottom = UDim.new(0, 8)
		pad.Parent = b
		tabButtons[id] = b
		b.Activated:Connect(function()
			tab = id
			Social.Refresh()
		end)
	end
	list = Instance.new("ScrollingFrame")
	list.Position = UDim2.fromOffset(12, 104)
	list.Size = UDim2.new(1, -24, 1, -116)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.Parent = panel
	local ll = Instance.new("UIListLayout")
	ll.Padding = UDim.new(0, 6)
	ll.SortOrder = Enum.SortOrder.LayoutOrder
	ll.Parent = list

	-- convite recebido
	invitePopup = Instance.new("Frame")
	invitePopup.Name = "Invite"
	invitePopup.AnchorPoint = Vector2.new(0.5, 0)
	invitePopup.Position = UDim2.new(0.5, 0, 0, 150)
	invitePopup.Size = UDim2.fromOffset(420, 110)
	invitePopup.BackgroundColor3 = T.Panel
	invitePopup.Visible = false
	invitePopup.ZIndex = 45
	invitePopup.Parent = gui
	C.HUD.Corner(invitePopup, 10)
	C.HUD.Stroke(invitePopup, T.Gold, 2)
	inviteText = C.HUD.Label(invitePopup, { Text = "", TextWrapped = true, Size = UDim2.new(1, -24, 0, 46), Position = UDim2.fromOffset(12, 8) })
	local ib = Instance.new("Frame")
	ib.BackgroundTransparency = 1
	ib.Position = UDim2.fromOffset(12, 60)
	ib.Size = UDim2.new(1, -24, 0, 42)
	ib.Parent = invitePopup
	local il = Instance.new("UIListLayout")
	il.FillDirection = Enum.FillDirection.Horizontal
	il.HorizontalAlignment = Enum.HorizontalAlignment.Center
	il.Padding = UDim.new(0, 12)
	il.Parent = ib
	btn(ib, "Aceitar", 150, true, function()
		invitePopup.Visible = false
		local r = request("Accept")
		if r and r.Ok then
			C.HUD.Toast("Você entrou na cozinha!", T.Gold)
		end
	end)
	btn(ib, "Recusar", 150, true, function()
		invitePopup.Visible = false
	end).BackgroundColor3 = T.PanelLight

	-- faixa de convidado
	guestBar = Instance.new("Frame")
	guestBar.Name = "Guest"
	guestBar.AnchorPoint = Vector2.new(0.5, 0)
	guestBar.Position = UDim2.new(0.5, 0, 0, 124)
	guestBar.Size = UDim2.fromOffset(460, 36)
	guestBar.BackgroundColor3 = T.Panel
	guestBar.BackgroundTransparency = 0.15
	guestBar.Visible = false
	guestBar.Parent = gui
	C.HUD.Corner(guestBar, 8)
	guestText = C.HUD.Label(guestBar, { Text = "", Size = UDim2.new(1, -110, 1, -8), Position = UDim2.fromOffset(10, 4), TextXAlignment = Enum.TextXAlignment.Left })
	local leave = btn(guestBar, "Sair", 80, true, function()
		request("Leave")
	end)
	leave.AnchorPoint = Vector2.new(1, 0.5)
	leave.Position = UDim2.new(1, -6, 0.5, 0)
	leave.Size = UDim2.fromOffset(84, 28)

	player:GetAttributeChangedSignal("GuestOf"):Connect(refreshGuest)
	refreshGuest()
	Remotes.Social.OnClientEvent:Connect(function(kind, info)
		if kind == "Invite" then
			inviteText.Text = info.From .. " convidou você para ajudar na cozinha."
			invitePopup.Visible = true
			C.Effects.Play("ComboUp", 1.2, 0.6)
			task.delay(info.Seconds or 30, function()
				invitePopup.Visible = false
			end)
		end
	end)
end

return Social
