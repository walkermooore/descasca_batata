-- BuildController: modo Construir (grade das alas, seção 3: "montar o layout das esteiras").
--   * Barra inferior com as máquinas da mochila; escolha uma e toque numa célula livre.
--   * Fantasma verde/vermelho mostra a célula e a seta de saída. Girar: R / Y / botão.
--   * Tocar numa máquina colocada abre o painel: Girar, Mover, Guardar, Melhorar.
--   * Controle: o cursor é o centro da tela; RT coloca, Y gira, B sai.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Format = require(Shared:WaitForChild("Format"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local player = Players.LocalPlayer
local G = Config.Grid
local R = Config.MachineRules

local Build = {}

local C
local T
local active = false
local selectedType: string? = nil
local selectedMachine: Model? = nil
local moving = false
local rot = 0
local ghost: Model
local ghostBox: Part
local bar: Frame
local list: Frame
local hint: TextLabel
local panel: Frame
local panelTitle: TextLabel
local panelInfo: TextLabel
local upgradeBtn: TextButton
local hoverCell: { number }? = nil
local busy = false

-- ---------------------------------------------------------------- utilidades

local function inventory(): { [string]: number }
	local inv = {}
	for id, n in string.gmatch(player:GetAttribute("Inventory") or "", "([^:,]+):(%d+)") do
		inv[id] = tonumber(n)
	end
	return inv
end

local function talent(id: string): number
	for tid, lvl in string.gmatch(player:GetAttribute("Talents") or "", "([^:,]+):(%d+)") do
		if tid == id then
			return tonumber(lvl) or 0
		end
	end
	return 0
end

function Build.Discount(): number
	return 1 - talent("MaquinasBaratas") * Config.TalentsById.MaquinasBaratas.PerLevel
end

local function upgradeCost(typeId: string, level: number): number?
	local def = Config.MachinesById[typeId]
	if not def or def.NoLevels or level >= R.MaxLevel then
		return nil
	end
	return math.floor(def.Cost * R.UpgradeCostFactor * R.CostGrowth ^ (level - 1) * Build.Discount())
end

local function kitchen(): Model?
	return C.Kitchen.GetOwned() -- só se constrói na própria cozinha
end

local function cellFromPoint(K: Model, p: Vector3): (number?, number?)
	local l = K:GetPivot():PointToObjectSpace(p)
	local col = math.floor((l.X + 14) / G.Cell)
	local row = math.floor((l.Z - 14) / G.Cell)
	local wings = K:GetAttribute("Wings") or 0
	if col < 0 or col >= G.SourceCol or row < 0 or row >= wings * G.RowsPerWing then
		return nil, nil
	end
	return col, row
end

local function cellCFrame(K: Model, col: number, row: number, r: number): CFrame
	return K:GetPivot() * CFrame.new(-12 + G.Cell * col, 0.4, 16 + G.Cell * row) * CFrame.Angles(0, -r * math.pi / 2, 0)
end

local function occupied(K: Model, col: number, row: number, ignore: Model?): boolean
	local folder = K:FindFirstChild("Machines")
	if not folder then
		return false
	end
	for _, m in folder:GetChildren() do
		if m ~= ignore and m:GetAttribute("Col") == col and m:GetAttribute("Row") == row then
			return true
		end
	end
	return false
end

local function pointerScreen(): Vector2
	if C.HUD.InputMode() == "Gamepad" then
		local vp = Workspace.CurrentCamera.ViewportSize
		return Vector2.new(vp.X / 2, vp.Y / 2) - GuiService:GetGuiInset()
	end
	return UserInputService:GetMouseLocation() - GuiService:GetGuiInset()
end

-- raio do ponteiro contra o chão das alas e as máquinas da minha cozinha
local function pick(screen: Vector2): (Vector3?, Model?)
	local K = kitchen()
	if not K then
		return nil, nil
	end
	local cam = Workspace.CurrentCamera
	local ray = cam:ScreenPointToRay(screen.X, screen.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local include = {}
	local wings = K:FindFirstChild("Wings")
	if wings then
		for _, w in wings:GetChildren() do
			local f = w:FindFirstChild("Floor")
			if f then
				table.insert(include, f)
			end
		end
	end
	local machines = K:FindFirstChild("Machines")
	if machines then
		table.insert(include, machines)
	end
	params.FilterDescendantsInstances = include
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * 300, params)
	if not hit then
		return nil, nil
	end
	local model: Instance? = hit.Instance
	while model and not (model:IsA("Model") and model:GetAttribute("MachineId")) do
		model = model.Parent
		if model == machines or model == nil then
			model = nil
			break
		end
	end
	return hit.Position, model :: Model?
end

local function request(...)
	if busy then
		return nil
	end
	busy = true
	local ok, res = pcall(function(...)
		return Remotes.BuildRequest:InvokeServer(...)
	end, ...)
	busy = false
	if ok and res and not res.Ok and res.Reason then
		C.HUD.Toast(res.Reason, T.RustBright)
	end
	return if ok then res else nil
end

-- ---------------------------------------------------------------- UI

local function refreshPanel()
	local m = selectedMachine
	panel.Visible = m ~= nil and m.Parent ~= nil
	if not panel.Visible or not m then
		return
	end
	local typeId = m:GetAttribute("Type")
	local def = Config.MachinesById[typeId]
	local level = m:GetAttribute("Level") or 1
	panelTitle.Text = def.Name .. (if def.NoLevels then "" else "  ·  " .. string.format(Strings.Level, level))
	local rate = m:GetAttribute("Rate") or 0
	local status = m:GetAttribute("Status")
	local info = def.Desc
	if typeId == "Esteira" then
		info = string.format(Strings.PerMin, Format.Dec(m:GetAttribute("Flow") or 0, 1))
	elseif status then
		info = string.format(Strings.PerMin, Format.Dec(rate, 1)) .. "  ·  " .. (Strings.Status[status] or status)
	end
	panelInfo.Text = info
	local cost = upgradeCost(typeId, level)
	upgradeBtn.Visible = not def.NoLevels
	if cost then
		upgradeBtn.Text = Strings.Upgrade .. " · " .. Format.Int(cost)
		upgradeBtn.TextColor3 = if (player:GetAttribute("Coins") or 0) >= cost then T.Gold else T.Dim
	else
		upgradeBtn.Text = Strings.MaxLevel
		upgradeBtn.TextColor3 = T.Dim
	end
end

local function refreshBar()
	for _, c in list:GetChildren() do
		if c:IsA("GuiButton") then
			c:Destroy()
		end
	end
	local inv = inventory()
	local any = false
	for i, def in Config.Machines do
		local n = inv[def.Id] or 0
		if n > 0 then
			any = true
			local b = Instance.new("TextButton")
			b.LayoutOrder = i
			b.Size = UDim2.fromOffset(120, 64)
			b.BackgroundColor3 = if selectedType == def.Id then T.Rust else T.PanelLight
			b.Text = ""
			b.Parent = list
			C.HUD.Corner(b, 6)
			C.HUD.Stroke(b, if selectedType == def.Id then T.Gold else T.Rust, if selectedType == def.Id then 3 else 1)
			C.HUD.Label(b, { Text = def.Name, TextWrapped = true, Size = UDim2.new(1, -8, 0, 36), Position = UDim2.fromOffset(4, 2) })
			C.HUD.Label(b, { Text = "x" .. n, TextColor3 = T.Gold, Size = UDim2.new(1, -8, 0, 20), Position = UDim2.fromOffset(4, 40) })
			b.Activated:Connect(function()
				selectedType = if selectedType == def.Id then nil else def.Id
				selectedMachine = nil
				moving = false
				refreshBar()
				refreshPanel()
			end)
		end
	end
	if selectedType and (inv[selectedType] or 0) <= 0 then
		selectedType = nil
	end
	local wings = player:GetAttribute("Wings") or 0
	hint.Text = if wings == 0 then "Libere a Ala 1 (cerca atrás da cozinha) para construir."
		elseif moving then "Toque na célula de destino."
		elseif any then Strings.BuildHint
		else Strings.BuildEmpty
end

local function button(parent: Instance, text: string, order: number, fn: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.LayoutOrder = order
	b.Size = UDim2.fromOffset(112, 44)
	b.BackgroundColor3 = T.Rust
	b.Font = T.Font
	b.TextScaled = true
	b.TextColor3 = T.Bone
	b.Text = text
	b.Parent = parent
	C.HUD.Corner(b, 6)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.Parent = b
	b.Activated:Connect(fn)
	return b
end

local function buildUi()
	local gui = C.HUD.Gui()
	bar = Instance.new("Frame")
	bar.Name = "BuildBar"
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -14)
	bar.Size = UDim2.fromOffset(640, 128)
	bar.BackgroundColor3 = T.Panel
	bar.BackgroundTransparency = 0.06
	bar.Visible = false
	bar.ZIndex = 20
	bar.Parent = gui
	C.HUD.Corner(bar, 10)
	C.HUD.Stroke(bar, T.Rust, 2)
	C.HUD.Label(bar, { Text = Strings.BuildTitle, Font = T.FontTitle, TextColor3 = T.Gold, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(0, 200, 0, 22), Position = UDim2.fromOffset(12, 6) })
	hint = C.HUD.Label(bar, { Text = "", TextColor3 = T.Dim, TextXAlignment = Enum.TextXAlignment.Right, Size = UDim2.new(1, -230, 0, 20), Position = UDim2.fromOffset(218, 8) })
	list = Instance.new("ScrollingFrame")
	list.Position = UDim2.fromOffset(10, 34)
	list.Size = UDim2.new(1, -140, 0, 84)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 4
	list.ScrollingDirection = Enum.ScrollingDirection.X
	list.AutomaticCanvasSize = Enum.AutomaticSize.X
	list.CanvasSize = UDim2.new()
	list.Parent = bar
	local ll = Instance.new("UIListLayout")
	ll.FillDirection = Enum.FillDirection.Horizontal
	ll.Padding = UDim.new(0, 8)
	ll.SortOrder = Enum.SortOrder.LayoutOrder
	ll.Parent = list
	local side = Instance.new("Frame")
	side.BackgroundTransparency = 1
	side.AnchorPoint = Vector2.new(1, 0)
	side.Position = UDim2.new(1, -10, 0, 34)
	side.Size = UDim2.fromOffset(116, 90)
	side.Parent = bar
	local sl = Instance.new("UIListLayout")
	sl.Padding = UDim.new(0, 6)
	sl.SortOrder = Enum.SortOrder.LayoutOrder
	sl.Parent = side
	button(side, Strings.Rotate .. " [R]", 1, function()
		Build.Rotate()
	end)
	button(side, "Sair [B]", 2, function()
		Build.Toggle(false)
	end)
	-- escala para celular
	local scale = Instance.new("UIScale")
	scale.Parent = bar
	local function fit()
		local vp = Workspace.CurrentCamera.ViewportSize
		scale.Scale = math.min(1, (vp.X - 30) / 650)
	end
	fit()
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)

	-- painel da máquina selecionada
	panel = Instance.new("Frame")
	panel.Name = "MachinePanel"
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, -152)
	panel.Size = UDim2.fromOffset(500, 120)
	panel.BackgroundColor3 = T.Panel
	panel.BackgroundTransparency = 0.06
	panel.Visible = false
	panel.ZIndex = 21
	panel.Parent = gui
	C.HUD.Corner(panel, 10)
	C.HUD.Stroke(panel, T.Gold, 2)
	Instance.new("UIScale").Parent = panel
	panelTitle = C.HUD.Label(panel, { Text = "", TextColor3 = T.Gold, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, -24, 0, 26), Position = UDim2.fromOffset(12, 6) })
	panelInfo = C.HUD.Label(panel, { Text = "", TextColor3 = T.Dim, TextScaled = false, TextSize = 16, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, -24, 0, 30), Position = UDim2.fromOffset(12, 32) })
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Position = UDim2.fromOffset(12, 68)
	row.Size = UDim2.new(1, -24, 0, 44)
	row.Parent = panel
	local rl = Instance.new("UIListLayout")
	rl.FillDirection = Enum.FillDirection.Horizontal
	rl.Padding = UDim.new(0, 8)
	rl.SortOrder = Enum.SortOrder.LayoutOrder
	rl.Parent = row
	button(row, Strings.Rotate, 1, function()
		if selectedMachine then
			request("Rotate", selectedMachine:GetAttribute("MachineId"))
		end
	end)
	button(row, "Mover", 2, function()
		moving = selectedMachine ~= nil
		refreshBar()
	end)
	button(row, Strings.PickUp, 3, function()
		if selectedMachine then
			local res = request("PickUp", selectedMachine:GetAttribute("MachineId"))
			if res and res.Ok and res.Refund then
				C.HUD.Toast("Guardada. As melhorias de nível se perdem ao guardar.", T.RustBright)
			end
			selectedMachine = nil
			refreshPanel()
		end
	end)
	upgradeBtn = button(row, Strings.Upgrade, 4, function()
		if selectedMachine then
			local res = request("Upgrade", selectedMachine:GetAttribute("MachineId"))
			if res and res.Ok then
				C.Effects.Play("ComboUp", 1.1)
			end
		end
	end)
	upgradeBtn.Size = UDim2.fromOffset(160, 44)

	-- fantasma
	ghost = Instance.new("Model")
	ghost.Name = "BuildGhost"
	ghostBox = Instance.new("Part")
	ghostBox.Anchored = true
	ghostBox.CanCollide = false
	ghostBox.CanQuery = false
	ghostBox.CanTouch = false
	ghostBox.Material = Enum.Material.ForceField
	ghostBox.Size = Vector3.new(3.8, 3, 3.8)
	ghostBox.Parent = ghost
	local arrow = Instance.new("Part")
	arrow.Name = "Arrow"
	arrow.Anchored = true
	arrow.CanCollide = false
	arrow.CanQuery = false
	arrow.Material = Enum.Material.Neon
	arrow.Color = T.Gold
	arrow.Size = Vector3.new(1.2, 0.2, 0.6)
	arrow.Parent = ghost
	ghost.PrimaryPart = ghostBox
end

-- ---------------------------------------------------------------- lógica

function Build.Rotate()
	if not active then
		return
	end
	if selectedMachine and not moving and not selectedType then
		request("Rotate", selectedMachine:GetAttribute("MachineId"))
	else
		rot = (rot + 1) % 4
	end
end

function Build.IsActive(): boolean
	return active
end

function Build.Toggle(on: boolean?)
	if not Config.Features.Build then
		on = false -- grade de máquinas desligada (a esteira da cozinha tomou o lugar)
	end
	if on == nil then
		on = not active
	end
	active = on == true
	bar.Visible = active
	selectedMachine = nil
	moving = false
	ghost.Parent = if active then C.Effects.Folder() else nil
	refreshBar()
	refreshPanel()
	if active then
		C.Shop.Close()
	end
end

local function click(screen: Vector2)
	local K = kitchen()
	if not active or not K then
		return
	end
	local pos, machine = pick(screen)
	if not pos then
		return
	end
	local col, row = cellFromPoint(K, pos)
	if moving and selectedMachine then
		if col then
			request("Move", selectedMachine:GetAttribute("MachineId"), col, row)
		end
		moving = false
		refreshBar()
		return
	end
	if machine then
		selectedMachine = machine
		selectedType = nil
		refreshBar()
		refreshPanel()
		return
	end
	if selectedType and col then
		if occupied(K, col, row) then
			C.HUD.Toast(Strings.CantPlace, T.RustBright)
			return
		end
		local res = request("Place", selectedType, col, row, rot)
		if res and res.Ok then
			C.Effects.Play("Crunch", 0.6, 0.6)
		end
		return
	end
	selectedMachine = nil
	refreshPanel()
end

local function update()
	if not active then
		return
	end
	local K = kitchen()
	local show = false
	if K and (selectedType or moving) then
		local pos = pick(pointerScreen())
		if pos then
			local col, row = cellFromPoint(K, pos)
			if col then
				show = true
				local ok = not occupied(K, col, row, if moving then selectedMachine else nil)
				local r = if moving and selectedMachine then (selectedMachine:GetAttribute("Rot") or 0) else rot
				local cf = cellCFrame(K, col, row, r)
				ghostBox.CFrame = cf * CFrame.new(0, 1.5, 0)
				ghostBox.Color = if ok then Color3.fromRGB(90, 220, 100) else Color3.fromRGB(220, 70, 60)
				;(ghost:FindFirstChild("Arrow") :: BasePart).CFrame = cf * CFrame.new(1.5, 3.2, 0)
				hoverCell = { col, row }
			end
		end
	end
	for _, p in ghost:GetChildren() do
		(p :: BasePart).Transparency = if show then (if p == ghostBox then 0.35 else 0) else 1
	end
	if selectedMachine and not selectedMachine.Parent then
		-- o servidor recriou o modelo (girar/melhorar): reencontra pelo id
		local id = selectedMachine:GetAttribute("MachineId")
		selectedMachine = nil
		local folder = K and K:FindFirstChild("Machines")
		if folder then
			for _, m in folder:GetChildren() do
				if m:GetAttribute("MachineId") == id then
					selectedMachine = m
				end
			end
		end
	end
	if panel.Visible or selectedMachine then
		refreshPanel()
	end
end

function Build.Init(controllers)
	C = controllers
	T = C.HUD.Theme
	buildUi()
	for _, a in { "Inventory", "Wings" } do
		player:GetAttributeChangedSignal(a):Connect(function()
			if active then
				refreshBar()
			end
		end)
	end
	RunService.RenderStepped:Connect(update)

	local downPos: Vector2? = nil
	local downTime = 0
	UserInputService.InputBegan:Connect(function(input, processed)
		if input.KeyCode == Enum.KeyCode.B and not processed then
			if player:GetAttribute("State") ~= "Peeling" then
				Build.Toggle()
			end
			return
		end
		if not active then
			return
		end
		if input.KeyCode == Enum.KeyCode.R or input.KeyCode == Enum.KeyCode.ButtonY then
			if not processed then
				Build.Rotate()
			end
		elseif input.KeyCode == Enum.KeyCode.ButtonB then
			Build.Toggle(false)
		elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
			click(pointerScreen())
		elseif (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) and not processed then
			downPos = Vector2.new(input.Position.X, input.Position.Y)
			downTime = os.clock()
		end
	end)
	UserInputService.InputEnded:Connect(function(input, processed)
		if not active or not downPos then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			local p = Vector2.new(input.Position.X, input.Position.Y)
			-- só conta como toque se não arrastou (arrastar gira a câmera)
			if (p - downPos).Magnitude < 12 and os.clock() - downTime < 0.5 and not processed then
				click(p)
			end
			downPos = nil
		end
	end)
	-- sair do modo ao começar a descascar
	player:GetAttributeChangedSignal("State"):Connect(function()
		if active and player:GetAttribute("State") == "Peeling" then
			Build.Toggle(false)
		end
	end)
end

return Build
