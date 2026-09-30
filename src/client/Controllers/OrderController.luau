-- OrderController: painel do Pedido do Rei (progresso e tempo restante).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Strings = require(Shared:WaitForChild("Strings"))

local player = Players.LocalPlayer

local Orders = {}

local C
local frame: Frame
local textLabel: TextLabel
local progLabel: TextLabel
local bar: Frame

local function refresh()
	local state = player:GetAttribute("OrderState")
	frame.Visible = state == "Active" or state == "Offer"
	if not frame.Visible then
		return
	end
	local T = C.HUD.Theme
	textLabel.Text = player:GetAttribute("OrderText") or ""
	if state == "Offer" then
		progLabel.Text = "No quadro: aceite perto da porta"
		progLabel.TextColor3 = T.Dim
		bar.Parent.Visible = false
	else
		local p, t = player:GetAttribute("OrderProgress") or 0, player:GetAttribute("OrderTarget") or 1
		progLabel.TextColor3 = T.Bone
		bar.Parent.Visible = true
		bar.Size = UDim2.fromScale(math.clamp(p / math.max(t, 1), 0, 1), 1)
	end
end

function Orders.Init(controllers)
	C = controllers
	local T = C.HUD.Theme
	frame = Instance.new("Frame")
	frame.Name = "Order"
	frame.Position = UDim2.fromOffset(12, 64)
	frame.Size = UDim2.fromOffset(270, 86)
	frame.BackgroundColor3 = T.Panel
	frame.BackgroundTransparency = 0.12
	frame.Visible = false
	frame.Parent = C.HUD.Gui()
	C.HUD.Corner(frame, 8)
	C.HUD.Stroke(frame, T.Gold, 2)
	C.HUD.Label(frame, { Text = Strings.OrderTitle, TextColor3 = T.Gold, Font = T.FontTitle, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, -20, 0, 20), Position = UDim2.fromOffset(10, 6) })
	textLabel = C.HUD.Label(frame, { Text = "", TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, -20, 0, 22), Position = UDim2.fromOffset(10, 28) })
	progLabel = C.HUD.Label(frame, { Text = "", TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, -20, 0, 18), Position = UDim2.fromOffset(10, 52) })
	local bg = Instance.new("Frame")
	bg.Size = UDim2.new(1, -20, 0, 5)
	bg.Position = UDim2.new(0, 10, 1, -10)
	bg.BackgroundColor3 = T.PanelLight
	bg.BorderSizePixel = 0
	bg.Parent = frame
	bar = Instance.new("Frame")
	bar.BackgroundColor3 = T.Gold
	bar.BorderSizePixel = 0
	bar.Size = UDim2.fromScale(0, 1)
	bar.Parent = bg

	for _, a in { "OrderState", "OrderText", "OrderProgress", "OrderTarget" } do
		player:GetAttributeChangedSignal(a):Connect(refresh)
	end
	refresh()
	RunService.Heartbeat:Connect(function()
		if frame.Visible and player:GetAttribute("OrderState") == "Active" then
			local left = math.max(0, (player:GetAttribute("OrderDeadline") or 0) - Workspace:GetServerTimeNow())
			local p, t = player:GetAttribute("OrderProgress") or 0, player:GetAttribute("OrderTarget") or 0
			progLabel.Text = string.format("%d/%d   ·   %d:%02d", p, t, left // 60, math.floor(left % 60))
			progLabel.TextColor3 = if left < 20 then T.Blood else T.Bone
		end
	end)
end

return Orders
