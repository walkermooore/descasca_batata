-- EventController: barra do Pedido Gigante do Rei, HUD da Corrida de Descascar e o
-- painel de emotes e pings rápidos.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local player = Players.LocalPlayer

local Events = {}

local C
local T
local giantFrame: Frame
local giantText: TextLabel
local giantBar: Frame
local raceFrame: Frame
local raceTitle: TextLabel
local raceBoard: TextLabel
local emotePanel: Frame
local castleGui: ScreenGui
local castleTint: Frame
local castleText: TextLabel
local effectsLabel: TextLabel

local function clock(sec: number): string
	sec = math.max(0, math.floor(sec))
	return string.format("%d:%02d", sec // 60, sec % 60)
end

local function update()
	local now = Workspace:GetServerTimeNow()
	-- Pedido Gigante
	local active = Workspace:GetAttribute("GiantActive") == true
	giantFrame.Visible = active
	if active then
		local p, g = Workspace:GetAttribute("GiantProgress") or 0, Workspace:GetAttribute("GiantGoal") or 1
		giantText.Text = string.format("PEDIDO GIGANTE DO REI  ·  %s / %s batatas  ·  %s", Format.Int(p), Format.Int(g), clock((Workspace:GetAttribute("GiantEnds") or now) - now))
		giantBar.Size = UDim2.fromScale(math.clamp(p / g, 0, 1), 1)
	end
	-- Corrida
	local rs = player:GetAttribute("RaceState")
	raceFrame.Visible = rs ~= nil
	if rs == "Queued" then
		raceTitle.Text = "CORRIDA: esperando jogadores (" .. (Workspace:GetAttribute("RaceQueue") or 1) .. " na fila)"
		raceBoard.Text = ""
	elseif rs == "Countdown" then
		raceTitle.Text = "CORRIDA começa em " .. clock((player:GetAttribute("RaceEnds") or now) - now) .. ". Vá para uma mesa com batata!"
		raceBoard.Text = ""
	elseif rs == "Running" then
		raceTitle.Text = "CORRIDA  ·  " .. clock((player:GetAttribute("RaceEnds") or now) - now) .. "  ·  seus pontos: " .. Format.Dec(player:GetAttribute("RaceScore") or 0, 1)
		local parts = {}
		for name, score in string.gmatch(Workspace:GetAttribute("RaceBoard") or "", "([^=;]+)=([%d%.]+)") do
			table.insert(parts, name .. " " .. score:gsub("%.", ","))
		end
		raceBoard.Text = table.concat(parts, "   ·   ")
	end
	-- efeitos de compras ativos (boost, banquete, douradas e viagens expressas restantes)
	local parts = {}
	local t = os.time()
	local bEnds, bMult = player:GetAttribute("BoostEnds") or 0, player:GetAttribute("BoostMult") or 1
	if bMult > 1 and bEnds > t then
		table.insert(parts, string.format("Boost x%d · %s", bMult, clock(bEnds - t)))
	end
	local sEnds = Workspace:GetAttribute("ServerBoostEnds") or 0
	if sEnds > t then
		table.insert(parts, string.format("Banquete x%d · %s", Workspace:GetAttribute("ServerBoost") or 2, clock(sEnds - t)))
	end
	local golden = player:GetAttribute("GoldenForced") or 0
	if golden > 0 then
		table.insert(parts, string.format("Douradas garantidas: %d", golden))
	end
	local express = player:GetAttribute("ExpressTrips") or 0
	if express > 0 then
		table.insert(parts, string.format("Viagens expressas: %d", express))
	end
	effectsLabel.Visible = #parts > 0
	effectsLabel.Text = table.concat(parts, "   |   ")
	-- perto do castelo: tela vermelha pulsando e contagem até os guardas atirarem
	local shootAt = player:GetAttribute("CastleShootAt")
	castleGui.Enabled = shootAt ~= nil
	if shootAt then
		local left = math.max(0, shootAt - now)
		castleTint.BackgroundTransparency = 0.72 - 0.12 * math.abs(math.sin(os.clock() * 6))
		castleText.Text = string.format("Afaste-se do castelo! Os guardas atiram em %d s", math.ceil(left))
	end
end

local function buildCastleWarning()
	castleGui = Instance.new("ScreenGui")
	castleGui.Name = "CastleWarning"
	castleGui.IgnoreGuiInset = true
	castleGui.DisplayOrder = 50
	castleGui.ResetOnSpawn = false
	castleGui.Enabled = false
	castleGui.Parent = player:WaitForChild("PlayerGui")
	castleTint = Instance.new("Frame")
	castleTint.Size = UDim2.fromScale(1, 1)
	castleTint.BackgroundColor3 = Color3.fromRGB(150, 10, 10)
	castleTint.BorderSizePixel = 0
	castleTint.Parent = castleGui
	-- bordas mais fortes que o centro
	local grad = Instance.new("UIGradient")
	grad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, 0.6),
		NumberSequenceKeypoint.new(0.7, 0.6),
		NumberSequenceKeypoint.new(1, 0),
	})
	grad.Parent = castleTint
	local title = C.HUD.Label(castleGui, {
		Text = "ZONA PROIBIDA",
		TextColor3 = Color3.fromRGB(255, 220, 210),
		Size = UDim2.new(0.6, 0, 0, 56),
		Position = UDim2.new(0.2, 0, 0.28, 0),
	})
	title.TextStrokeTransparency = 0.2
	castleText = C.HUD.Label(castleGui, {
		Text = "",
		TextColor3 = Color3.fromRGB(255, 236, 228),
		Size = UDim2.new(0.7, 0, 0, 34),
		Position = UDim2.new(0.15, 0, 0.28, 62),
	})
	castleText.TextStrokeTransparency = 0.2
end

local function buildEmotes(gui: ScreenGui)
	emotePanel = Instance.new("Frame")
	emotePanel.Name = "Emotes"
	emotePanel.AnchorPoint = Vector2.new(0, 0.5)
	emotePanel.Position = UDim2.new(0, 126, 0.5, 60)
	emotePanel.Size = UDim2.fromOffset(250, 260)
	emotePanel.BackgroundColor3 = T.Panel
	emotePanel.BackgroundTransparency = 0.05
	emotePanel.Visible = false
	emotePanel.ZIndex = 25
	emotePanel.Parent = gui
	C.HUD.Corner(emotePanel, 10)
	C.HUD.Stroke(emotePanel, T.Rust, 2)
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(112, 40)
	grid.CellPadding = UDim2.fromOffset(8, 8)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = emotePanel
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingLeft = UDim.new(0, 10)
	pad.Parent = emotePanel
	local NAMES = { wave = "Acenar", point = "Apontar", cheer = "Comemorar", dance = "Dançar" }
	local order = 0
	local function add(text: string, color: Color3, fn: () -> ())
		order += 1
		local b = Instance.new("TextButton")
		b.LayoutOrder = order
		b.Text = text
		b.Font = T.Font
		b.TextScaled = true
		b.TextColor3 = T.Bone
		b.BackgroundColor3 = color
		b.Parent = emotePanel
		C.HUD.Corner(b, 6)
		local p = Instance.new("UIPadding")
		p.PaddingTop = UDim.new(0, 8)
		p.PaddingBottom = UDim.new(0, 8)
		p.Parent = b
		b.Activated:Connect(function()
			emotePanel.Visible = false
			fn()
		end)
	end
	for _, e in Config.Emotes do
		add(NAMES[e] or e, T.PanelLight, function()
			local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if hum then
				pcall(function()
					hum:PlayEmote(e)
				end)
			end
		end)
	end
	for _, p in Config.Pings do
		add(p.Text, T.Rust, function()
			pcall(function()
				Remotes.SocialRequest:InvokeServer("Ping", p.Id)
			end)
		end)
	end
end

function Events.ToggleEmotes()
	emotePanel.Visible = not emotePanel.Visible
end

function Events.Init(controllers)
	C = controllers
	T = C.HUD.Theme
	local gui = C.HUD.Gui()

	giantFrame = Instance.new("Frame")
	giantFrame.Name = "Giant"
	giantFrame.AnchorPoint = Vector2.new(0.5, 0)
	giantFrame.Position = UDim2.new(0.5, 0, 0, 166)
	giantFrame.Size = UDim2.fromOffset(520, 44)
	giantFrame.BackgroundColor3 = Color3.fromRGB(58, 22, 20)
	giantFrame.BackgroundTransparency = 0.08
	giantFrame.Visible = false
	giantFrame.Parent = gui
	C.HUD.Corner(giantFrame, 8)
	C.HUD.Stroke(giantFrame, T.Gold, 2)
	giantText = C.HUD.Label(giantFrame, { Text = "", TextColor3 = T.Gold, Size = UDim2.new(1, -20, 0, 24), Position = UDim2.fromOffset(10, 3) })
	local bg = Instance.new("Frame")
	bg.Position = UDim2.new(0, 10, 1, -12)
	bg.Size = UDim2.new(1, -20, 0, 7)
	bg.BackgroundColor3 = T.Panel
	bg.BorderSizePixel = 0
	bg.Parent = giantFrame
	giantBar = Instance.new("Frame")
	giantBar.BackgroundColor3 = T.Gold
	giantBar.BorderSizePixel = 0
	giantBar.Parent = bg

	raceFrame = Instance.new("Frame")
	raceFrame.Name = "Race"
	raceFrame.AnchorPoint = Vector2.new(0.5, 0)
	raceFrame.Position = UDim2.new(0.5, 0, 0, 216)
	raceFrame.Size = UDim2.fromOffset(560, 56)
	raceFrame.BackgroundColor3 = T.Panel
	raceFrame.BackgroundTransparency = 0.1
	raceFrame.Visible = false
	raceFrame.Parent = gui
	C.HUD.Corner(raceFrame, 8)
	C.HUD.Stroke(raceFrame, T.RustBright, 2)
	raceTitle = C.HUD.Label(raceFrame, { Text = "", Size = UDim2.new(1, -20, 0, 26), Position = UDim2.fromOffset(10, 3) })
	raceBoard = C.HUD.Label(raceFrame, { Text = "", TextColor3 = T.Gold, Size = UDim2.new(1, -20, 0, 20), Position = UDim2.fromOffset(10, 31) })
	-- sair da corrida (ou da fila) a qualquer momento
	local leave = Instance.new("TextButton")
	leave.Name = "Leave"
	leave.AnchorPoint = Vector2.new(0, 0.5)
	leave.Position = UDim2.new(1, 8, 0.5, 0)
	leave.Size = UDim2.fromOffset(70, 32)
	leave.Text = "Sair"
	leave.Font = T.Font
	leave.TextScaled = true
	leave.TextColor3 = T.Bone
	leave.BackgroundColor3 = T.Rust
	leave.Parent = raceFrame
	C.HUD.Corner(leave, 6)
	local lp = Instance.new("UIPadding")
	lp.PaddingTop = UDim.new(0, 6)
	lp.PaddingBottom = UDim.new(0, 6)
	lp.Parent = leave
	leave.Activated:Connect(function()
		pcall(function()
			Remotes.SocialRequest:InvokeServer("RaceLeave")
		end)
	end)

	effectsLabel = C.HUD.Label(gui, {
		Name = "ActiveEffects",
		Text = "",
		TextColor3 = T.Gold,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 120),
		Size = UDim2.fromOffset(560, 24),
		Visible = false,
	})
	effectsLabel.TextStrokeTransparency = 0.3

	buildEmotes(gui)
	buildCastleWarning()
	RunService.Heartbeat:Connect(update)
end

return Events
