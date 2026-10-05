-- ShopController: Loja com abas Ferramentas, Máquinas, Cozinha, Passes, Cosméticos (seção 6).
-- Sem pop-up de compra: a loja só abre quando o jogador pede (botão Loja / tecla L / Select).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Format = require(Shared:WaitForChild("Format"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local player = Players.LocalPlayer

local Shop = {}

local C
local T
local panel: Frame
local list: ScrollingFrame
local tabButtons = {}
local currentTab = "Ferramentas"
local highlightId: string? = nil
local busy = false

local function owned(): { [string]: boolean }
	local set = {}
	for id in string.gmatch(player:GetAttribute("Owned") or "", "[^,]+") do
		set[id] = true
	end
	return set
end

-- Catálogo montado a partir do Config
local function catalog(tab: string)
	local rows = {}
	if tab == "Ferramentas" then
		for _, t in Config.Tools do
			if t.Cost > 0 then
				table.insert(rows, { Id = t.Id, Name = t.Name, Desc = t.Desc, Cost = t.Cost, Tier = t.Tier, IsTool = true })
			end
		end
	end
	if tab == "Maquinas" then
		local inv = {}
		for id, n in string.gmatch(player:GetAttribute("Inventory") or "", "([^:,]+):(%d+)") do
			inv[id] = tonumber(n)
		end
		local discount = C.Build.Discount()
		for _, m in Config.Machines do
			local n = inv[m.Id] or 0
			table.insert(rows, {
				Id = m.Id,
				Name = m.Name .. (if n > 0 then "  (" .. string.format(Strings.InInventory, n) .. ")" else ""),
				Desc = m.Desc,
				Cost = math.floor(m.Cost * discount),
				IsMachine = true,
			})
		end
	end
	for _, c in Config.Collection do
		if c.Tab == tab then
			table.insert(rows, { Id = c.Id, Name = c.Name, Desc = c.Desc, Cost = c.Cost, Soon = c.Soon })
		end
	end
	if tab == "Cozinha" then
		-- melhorias da esteira (níveis vindos do atributo "Upgrades")
		local levels = {}
		for id, lvl in string.gmatch(player:GetAttribute("Upgrades") or "", "([^:,]+):(%d+)") do
			levels[id] = tonumber(lvl)
		end
		for i, u in Config.Upgrades do
			local lvl = levels[u.Id] or 1
			local now, nxt = u.Levels[lvl], u.Levels[lvl + 1]
			local info = if u.Toggle then u.Desc
				elseif nxt then string.format("%s  (%s → %s %s)", u.Desc, Format.Dec(now.Value, 1), Format.Dec(nxt.Value, 1), u.Unit)
				else string.format("%s  (%s %s)", u.Desc, Format.Dec(now.Value, 1), u.Unit)
			table.insert(rows, i, {
				Id = "Upgrade:" .. u.Id,
				UpgradeId = u.Id,
				Name = if u.Toggle then u.Name else string.format("%s  ·  N%d", u.Name, lvl),
				Desc = info,
				Cost = nxt and nxt.Cost,
				IsUpgrade = true,
				Done = nxt == nil,
			})
		end
		local wings = player:GetAttribute("Wings") or 0
		if not Config.Features.Build then
			-- sem a grade de máquinas, as alas não aparecem na loja
		elseif wings < Config.Grid.Wings then
			table.insert(rows, 1, { Id = "Wing", Name = string.format(Strings.WingRow, wings + 1), Desc = Strings.WingDesc, Cost = Config.Grid.WingCosts[wings + 1], IsWing = true })
		else
			table.insert(rows, 1, { Id = "Wing", Name = Strings.AllWings, Desc = Strings.WingDesc, IsWing = true, Done = true })
		end
		for _, id in Config.Rebirth.Themes do
			local th = Config.Themes[id]
			table.insert(rows, { Id = "Theme:" .. id, Name = string.format(Strings.Theme, th.Name), Desc = "Troca paredes, piso e luz. Máquinas e layout continuam iguais.", Theme = id, Rebirths = th.Rebirths })
		end
	end
	if tab == "Passes" then
		table.insert(rows, { Id = "HeaderPasses", Header = "Passes (para sempre)" })
		for _, p in Config.GamePasses do
			if not p.Hidden then
				table.insert(rows, { Id = p.Id, Name = p.Name, Desc = p.Desc, Robux = p.Price, IsPass = true, Soon = p.PassId == 0 })
			end
		end
		table.insert(rows, { Id = "HeaderProducts", Header = "Pacotes (uso único)" })
		for _, p in Config.Products do
			table.insert(rows, { Id = p.Id, Name = p.Name, Desc = p.Desc, Robux = p.Price, IsProduct = true, Soon = p.ProductId == 0 })
		end
	end
	if tab == "Cosmeticos" then
		table.insert(rows, { Id = "Cosmeticos", Name = Strings.Soon, Desc = "Aventais, chapéus e skins de ferramenta.", Soon = true })
	end
	return rows
end

local function request(action: string, id: string)
	if busy then
		return
	end
	busy = true
	local ok, res = pcall(function()
		return Remotes.ShopRequest:InvokeServer(action, id)
	end)
	busy = false
	if ok and res and res.Ok then
		if action == "Buy" then
			local name = (Config.ToolsById[id] or Config.CollectionById[id] or Config.MachinesById[id] or {}).Name or id
			C.HUD.Toast(string.format(Strings.Bought, name), T.Gold)
			C.Effects.Play("Coins")
		end
	elseif ok and res and res.Reason and res.Reason ~= "Owned" then
		C.HUD.Toast(res.Reason, T.RustBright)
	end
	Shop.Refresh()
end

local function passOwned(id: string): boolean
	return string.find("," .. (player:GetAttribute("Passes") or "") .. ",", "," .. id .. ",", 1, true) ~= nil
end

local function row(r, order: number, ownedSet, coins: number)
	if r.Header then
		-- dentro de um Frame: o Refresh apaga os Frames da lista ao trocar de aba
		local hf = Instance.new("Frame")
		hf.Name = r.Id
		hf.LayoutOrder = order
		hf.BackgroundTransparency = 1
		hf.Size = UDim2.new(1, -8, 0, 30)
		hf.Parent = list
		C.HUD.Label(hf, {
			Text = r.Header,
			Font = T.FontTitle,
			TextColor3 = T.Gold,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.fromScale(1, 1),
		})
		return hf
	end
	local f = Instance.new("Frame")
	f.Name = r.Id
	f.LayoutOrder = order
	f.Size = UDim2.new(1, -8, 0, 86)
	f.BackgroundColor3 = T.PanelLight
	f.BackgroundTransparency = 0.05
	f.Parent = list
	C.HUD.Corner(f, 8)
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(190, 180, 170))
	grad.Parent = f
	-- miniatura 3D do item
	local kind = if r.IsTool then "Tool"
		elseif r.IsUpgrade then "Upgrade"
		elseif r.Theme then "Theme"
		elseif r.Robux then "Pass"
		elseif Config.CollectionById[r.Id] then "Item"
		else "Other"
	local previewId = if r.IsUpgrade then r.UpgradeId elseif r.Theme then r.Theme else r.Id
	local ok, vpf = pcall(C.Preview.Make, f, kind, previewId)
	if ok and vpf then
		vpf.Size = UDim2.fromOffset(70, 70)
		vpf.Position = UDim2.fromOffset(16, 8)
		C.HUD.Corner(vpf, 8)
		C.HUD.Stroke(vpf, if r.Tier then Config.TierColors[r.Tier] else T.Rust, 2)
	end
	local st = C.HUD.Stroke(f, if r.Id == highlightId then T.Gold else T.Panel, if r.Id == highlightId then 3 else 1)
	if r.Tier then
		local bar = Instance.new("Frame")
		bar.Size = UDim2.new(0, 6, 1, -12)
		bar.Position = UDim2.fromOffset(6, 6)
		bar.BorderSizePixel = 0
		bar.BackgroundColor3 = Config.TierColors[r.Tier]
		bar.Parent = f
	end
	C.HUD.Label(f, {
		Text = r.Name,
		TextColor3 = T.Bone,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -276, 0, 28),
		Position = UDim2.fromOffset(98, 8),
	})
	C.HUD.Label(f, {
		Text = r.Desc or "",
		TextColor3 = T.Dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		TextScaled = false,
		TextSize = 15,
		Size = UDim2.new(1, -276, 0, 44),
		Position = UDim2.fromOffset(98, 38),
	})

	local b = Instance.new("TextButton")
	b.AnchorPoint = Vector2.new(1, 0.5)
	b.Position = UDim2.new(1, -10, 0.5, 0)
	b.Size = UDim2.fromOffset(160, 52)
	b.Font = T.Font
	b.TextScaled = true
	b.TextColor3 = T.Bone
	b.AutoButtonColor = true
	b.Parent = f
	C.HUD.Corner(b, 6)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.Parent = b

	local isOwned = ownedSet[r.Id] == true
	local coinsNow = coins
	local function build(action: string, arg: string?)
		if busy then
			return
		end
		busy = true
		local ok, res = pcall(function()
			return Remotes.BuildRequest:InvokeServer(action, arg)
		end)
		busy = false
		if ok and res and not res.Ok and res.Reason then
			C.HUD.Toast(res.Reason, T.RustBright)
		end
		Shop.Refresh()
	end
	if r.IsUpgrade then
		if r.Done then
			b.Text = if Config.UpgradesById[r.UpgradeId].Toggle then Strings.Owned else Strings.MaxLevel
			b.BackgroundColor3 = T.Panel
			b.TextColor3 = T.Dim
		else
			b.Text = string.format(Strings.CoinsCost, Format.Int(r.Cost))
			b.BackgroundColor3 = if coinsNow >= r.Cost then T.Rust else T.Panel
			b.TextColor3 = if coinsNow >= r.Cost then T.Gold else T.Dim
			b.Activated:Connect(function()
				if busy then
					return
				end
				busy = true
				local ok, res = pcall(function()
					return Remotes.ShopRequest:InvokeServer("Upgrade", r.UpgradeId)
				end)
				busy = false
				if ok and res and res.Ok then
					C.HUD.Toast(string.format(Strings.Bought, Config.UpgradesById[r.UpgradeId].Name), T.Gold)
					C.Effects.Play("ComboUp")
				elseif ok and res and res.Reason then
					C.HUD.Toast(res.Reason, T.RustBright)
				end
				Shop.Refresh()
			end)
		end
	elseif r.Theme then
		local unlocked = (player:GetAttribute("Rebirths") or 0) >= r.Rebirths
		local inUse = (player:GetAttribute("Theme") or "Castelo") == r.Theme
		b.Text = if inUse then Strings.ThemeInUse elseif unlocked then Strings.ThemeUse else string.format(Strings.ThemeLocked, r.Rebirths)
		b.BackgroundColor3 = if unlocked and not inUse then T.Rust else T.Panel
		b.TextColor3 = if unlocked and not inUse then T.Bone else T.Dim
		if unlocked and not inUse then
			b.Activated:Connect(function()
				build("SetTheme", r.Theme)
			end)
		end
	elseif r.IsWing then
		if r.Done then
			b.Text = Strings.Owned
			b.BackgroundColor3 = T.Panel
			b.TextColor3 = T.Dim
		else
			b.Text = string.format(Strings.CoinsCost, Format.Int(r.Cost))
			b.BackgroundColor3 = if coinsNow >= r.Cost then T.Rust else T.Panel
			b.TextColor3 = if coinsNow >= r.Cost then T.Gold else T.Dim
			b.Activated:Connect(function()
				build("BuyWing")
			end)
		end
	elseif r.IsMachine then
		b.Text = string.format(Strings.CoinsCost, Format.Int(r.Cost))
		b.BackgroundColor3 = if coinsNow >= r.Cost then T.Rust else T.Panel
		b.TextColor3 = if coinsNow >= r.Cost then T.Gold else T.Dim
		b.Activated:Connect(function()
			request("Buy", r.Id)
		end)
		if r.Id == "Esteira" then
			-- compra em lote (esteiras são muitas)
			b.Size = UDim2.fromOffset(110, 52)
			b.Position = UDim2.new(1, -66, 0.5, 0)
			local five = b:Clone()
			five.Text = "x5"
			five.Size = UDim2.fromOffset(50, 52)
			five.Position = UDim2.new(1, -10, 0.5, 0)
			five.BackgroundColor3 = if coinsNow >= r.Cost * 5 then T.Rust else T.Panel
			five.Parent = f
			five.Activated:Connect(function()
				if not busy then
					busy = true
					local ok, res = pcall(function()
						return Remotes.ShopRequest:InvokeServer("Buy", r.Id, 5)
					end)
					busy = false
					if ok and res and not res.Ok and res.Reason then
						C.HUD.Toast(res.Reason, T.RustBright)
					end
					Shop.Refresh()
				end
			end)
		end
	elseif r.IsPass and passOwned(r.Id) then
		b.Text = Strings.Owned
		b.BackgroundColor3 = T.Panel
		b.TextColor3 = T.Dim
	elseif (r.IsPass or r.IsProduct) and not r.Soon then
		b.Text = string.format(Strings.Robux, r.Robux)
		b.BackgroundColor3 = Color3.fromRGB(46, 120, 70)
		b.TextColor3 = T.Bone
		b.Activated:Connect(function()
			pcall(function()
				Remotes.Store:InvokeServer(if r.IsPass then "PromptPass" else "PromptProduct", r.Id)
			end)
		end)
	elseif r.Soon then
		b.Text = if r.Robux then string.format(Strings.Robux, r.Robux) .. " · " .. Strings.Soon else Strings.Soon
		b.BackgroundColor3 = T.Panel
		b.TextColor3 = T.Dim
		b.AutoButtonColor = false
	elseif r.IsTool and isOwned then
		local equipped = player:GetAttribute("ToolId") == r.Id
		b.Text = if equipped then Strings.Equipped else Strings.Equip
		b.BackgroundColor3 = if equipped then T.Panel else T.Rust
		b.Activated:Connect(function()
			if not equipped then
				request("Equip", r.Id)
			end
		end)
	elseif isOwned then
		b.Text = Strings.Owned
		b.BackgroundColor3 = T.Panel
		b.TextColor3 = T.Dim
	else
		b.Text = string.format(Strings.CoinsCost, Format.Int(r.Cost))
		local afford = coins >= r.Cost
		b.BackgroundColor3 = if afford then T.Rust else T.Panel
		b.TextColor3 = if afford then T.Gold else T.Dim
		b.Activated:Connect(function()
			request("Buy", r.Id)
		end)
	end
	if r.Id == highlightId and not isOwned then
		local TweenService = game:GetService("TweenService")
		TweenService:Create(st, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Thickness = 6 }):Play()
	end
end

function Shop.Refresh()
	if not panel or not panel.Visible then
		return
	end
	for _, c in list:GetChildren() do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	local ownedSet = owned()
	local coins = player:GetAttribute("Coins") or 0
	for i, r in catalog(currentTab) do
		row(r, i, ownedSet, coins)
	end
	for id, b in tabButtons do
		b.BackgroundColor3 = if id == currentTab then T.Rust else T.Panel
	end
end

function Shop.SetTab(id: string)
	currentTab = id
	Shop.Refresh()
end

function Shop.Open()
	panel.Visible = true
	Shop.Refresh()
end

function Shop.Close()
	panel.Visible = false
end

function Shop.Toggle()
	if panel.Visible then
		Shop.Close()
	else
		Shop.Open()
	end
end

-- Tutorial: destaca um item (e abre a aba dele)
function Shop.Highlight(id: string?)
	highlightId = id
	if id and Config.ToolsById[id] then
		currentTab = "Ferramentas"
	end
	Shop.Refresh()
end

local function build()
	local gui = C.HUD.Gui()
	panel = Instance.new("Frame")
	panel.Name = "Shop"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.52)
	panel.Size = UDim2.fromOffset(680, 470)
	panel.BackgroundColor3 = T.Panel
	panel.BackgroundTransparency = 0.04
	panel.Visible = false
	panel.ZIndex = 30
	panel.Parent = gui
	C.HUD.Corner(panel, 10)
	C.HUD.Stroke(panel, T.Rust, 3)
	-- escala para caber em telas pequenas (celular)
	local scale = Instance.new("UIScale")
	scale.Parent = panel
	local function fit()
		local vp = Workspace.CurrentCamera.ViewportSize
		scale.Scale = math.min(1, (vp.Y - 90) / 480, (vp.X - 40) / 690)
	end
	fit()
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)

	C.HUD.Label(panel, {
		Text = "LOJA DO ACAMPAMENTO",
		Font = T.FontTitle,
		TextColor3 = T.Gold,
		Size = UDim2.new(1, -120, 0, 34),
		Position = UDim2.fromOffset(16, 10),
		TextXAlignment = Enum.TextXAlignment.Left,
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
	close.Activated:Connect(Shop.Close)

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
	for i, t in Config.ShopTabs do
		local b = Instance.new("TextButton")
		b.LayoutOrder = i
		b.Size = UDim2.new(1 / #Config.ShopTabs, -6, 1, 0)
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
			Shop.SetTab(t.Id)
		end)
	end

	list = Instance.new("ScrollingFrame")
	list.Position = UDim2.fromOffset(12, 104)
	list.Size = UDim2.new(1, -24, 1, -116)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = T.Rust
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.Parent = panel
	local ll = Instance.new("UIListLayout")
	ll.Padding = UDim.new(0, 8)
	ll.SortOrder = Enum.SortOrder.LayoutOrder
	ll.Parent = list
end

function Shop.Init(controllers)
	C = controllers
	T = C.HUD.Theme
	build()
	for _, a in { "Coins", "Owned", "ToolId", "Inventory", "Wings", "Theme", "Rebirths", "Upgrades" } do
		player:GetAttributeChangedSignal(a):Connect(Shop.Refresh)
	end
	-- janela de distribuição do pátio (prompt local, Kind = "Shop")
	game:GetService("ProximityPromptService").PromptTriggered:Connect(function(prompt)
		if prompt:GetAttribute("Kind") == "Shop" then
			Shop.Open()
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.L or input.KeyCode == Enum.KeyCode.ButtonSelect then
			Shop.Toggle()
		elseif input.KeyCode == Enum.KeyCode.Escape and panel.Visible then
			Shop.Close()
		end
	end)
end

return Shop
