-- SeasonController: painel "Nova Temporada" (rebirth) e talentos pagos com Sementes de Ouro.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Format = require(Shared:WaitForChild("Format"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local player = Players.LocalPlayer

local Season = {}

local C
local T
local panel: Frame
local progressLabel: TextLabel
local progressBar: Frame
local gainLabel: TextLabel
local seedsLabel: TextLabel
local multLabel: TextLabel
local rebirthBtn: TextButton
local talentList: Frame
local confirmUntil = 0
local busy = false

local function talents(): { [string]: number }
	local t = {}
	for id, lvl in string.gmatch(player:GetAttribute("Talents") or "", "([^:,]+):(%d+)") do
		t[id] = tonumber(lvl)
	end
	return t
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

function Season.Refresh()
	if not panel.Visible then
		return
	end
	local rb = Config.Rebirth
	local delivered = player:GetAttribute("SeasonDelivered") or 0
	local ready = delivered >= rb.PotatoesRequired
	progressLabel.Text = string.format(Strings.SeasonProgress, Format.Int(delivered), Format.Int(rb.PotatoesRequired))
	progressBar.Size = UDim2.fromScale(math.clamp(delivered / rb.PotatoesRequired, 0, 1), 1)
	local seeds = rb.SeedsBase + math.floor(math.max(0, delivered - rb.PotatoesRequired) / rb.SeedsPerExtra)
	gainLabel.Text = if ready then string.format(Strings.SeasonGain, seeds) else Strings.SeasonNotReady
	local rebirths = player:GetAttribute("Rebirths") or 0
	seedsLabel.Text = string.format(Strings.Seeds, player:GetAttribute("Seeds") or 0)
	multLabel.Text = string.format(Strings.RebirthMult, math.floor(rebirths * rb.MultiplierPerRebirth * 100 + 0.5)) .. "   ·   Temporada " .. (rebirths + 1)
	rebirthBtn.Text = if os.clock() < confirmUntil then Strings.SeasonConfirm else Strings.SeasonButton
	rebirthBtn.BackgroundColor3 = if ready then T.Rust else T.Panel
	rebirthBtn.TextColor3 = if ready then T.Gold else T.Dim

	for _, c in talentList:GetChildren() do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	local have = talents()
	local seedsNow = player:GetAttribute("Seeds") or 0
	for i, t in Config.Talents do
		local lvl = have[t.Id] or 0
		local f = Instance.new("Frame")
		f.LayoutOrder = i
		f.Size = UDim2.new(1, -8, 0, 58)
		f.BackgroundColor3 = T.PanelLight
		f.Parent = talentList
		C.HUD.Corner(f, 6)
		C.HUD.Label(f, { Text = t.Name .. "  ·  " .. string.format(Strings.TalentLevel, lvl, #t.Costs), TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, -170, 0, 24), Position = UDim2.fromOffset(10, 4) })
		C.HUD.Label(f, { Text = t.Desc, TextColor3 = T.Dim, TextScaled = false, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, -170, 0, 22), Position = UDim2.fromOffset(10, 30) })
		local cost = t.Costs[lvl + 1]
		local b = Instance.new("TextButton")
		b.AnchorPoint = Vector2.new(1, 0.5)
		b.Position = UDim2.new(1, -8, 0.5, 0)
		b.Size = UDim2.fromOffset(150, 42)
		b.Font = T.Font
		b.TextScaled = true
		b.Text = if cost then string.format(Strings.TalentCost, cost) else Strings.MaxLevel
		b.BackgroundColor3 = if cost and seedsNow >= cost then T.Rust else T.Panel
		b.TextColor3 = if cost and seedsNow >= cost then T.Gold else T.Dim
		b.Parent = f
		C.HUD.Corner(b, 6)
		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, 8)
		pad.PaddingBottom = UDim.new(0, 8)
		pad.Parent = b
		b.Activated:Connect(function()
			if cost then
				request("BuyTalent", t.Id)
			end
		end)
	end
end

function Season.Toggle()
	panel.Visible = not panel.Visible
	if panel.Visible then
		C.Shop.Close()
	end
	Season.Refresh()
end

function Season.Init(controllers)
	C = controllers
	T = C.HUD.Theme
	local gui = C.HUD.Gui()
	panel = Instance.new("Frame")
	panel.Name = "Season"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.52)
	panel.Size = UDim2.fromOffset(620, 500)
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
		scale.Scale = math.min(1, (vp.Y - 90) / 510, (vp.X - 40) / 630)
	end
	fit()
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)

	C.HUD.Label(panel, { Text = Strings.SeasonTitle, Font = T.FontTitle, TextColor3 = T.Gold, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, -80, 0, 34), Position = UDim2.fromOffset(16, 10) })
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
	close.Activated:Connect(Season.Toggle)
	C.HUD.Label(panel, { Text = Strings.SeasonInfo, TextColor3 = T.Dim, TextScaled = false, TextSize = 16, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, -32, 0, 40), Position = UDim2.fromOffset(16, 48) })
	progressLabel = C.HUD.Label(panel, { Text = "", TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, -32, 0, 22), Position = UDim2.fromOffset(16, 92) })
	local bg = Instance.new("Frame")
	bg.Position = UDim2.fromOffset(16, 118)
	bg.Size = UDim2.new(1, -32, 0, 12)
	bg.BackgroundColor3 = T.PanelLight
	bg.BorderSizePixel = 0
	bg.Parent = panel
	C.HUD.Corner(bg, 6)
	progressBar = Instance.new("Frame")
	progressBar.BackgroundColor3 = T.Gold
	progressBar.BorderSizePixel = 0
	progressBar.Parent = bg
	C.HUD.Corner(progressBar, 6)
	gainLabel = C.HUD.Label(panel, { Text = "", TextColor3 = T.Gold, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(0.5, -20, 0, 22), Position = UDim2.fromOffset(16, 138) })
	rebirthBtn = Instance.new("TextButton")
	rebirthBtn.AnchorPoint = Vector2.new(1, 0)
	rebirthBtn.Position = UDim2.new(1, -16, 0, 136)
	rebirthBtn.Size = UDim2.fromOffset(280, 48)
	rebirthBtn.Font = T.Font
	rebirthBtn.TextScaled = true
	rebirthBtn.Parent = panel
	C.HUD.Corner(rebirthBtn, 8)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.Parent = rebirthBtn
	rebirthBtn.Activated:Connect(function()
		if os.clock() < confirmUntil then
			confirmUntil = 0
			local res = request("Rebirth")
			if res and res.Ok then
				panel.Visible = false
			end
		else
			confirmUntil = os.clock() + 4
			task.delay(4.1, Season.Refresh)
		end
		Season.Refresh()
	end)
	multLabel = C.HUD.Label(panel, { Text = "", TextColor3 = T.Dim, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(0.5, -20, 0, 20), Position = UDim2.fromOffset(16, 164) })
	seedsLabel = C.HUD.Label(panel, { Text = "", TextColor3 = T.Gold, Font = T.FontTitle, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, -32, 0, 26), Position = UDim2.fromOffset(16, 196) })
	talentList = Instance.new("ScrollingFrame")
	talentList.Position = UDim2.fromOffset(12, 228)
	talentList.Size = UDim2.new(1, -24, 1, -240)
	talentList.BackgroundTransparency = 1
	talentList.BorderSizePixel = 0
	talentList.ScrollBarThickness = 6
	talentList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	talentList.CanvasSize = UDim2.new()
	talentList.Parent = panel
	local ll = Instance.new("UIListLayout")
	ll.Padding = UDim.new(0, 6)
	ll.SortOrder = Enum.SortOrder.LayoutOrder
	ll.Parent = talentList

	for _, a in { "SeasonDelivered", "Seeds", "Talents", "Rebirths" } do
		player:GetAttributeChangedSignal(a):Connect(Season.Refresh)
	end
end

return Season
