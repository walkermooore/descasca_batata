-- DuelController: tela do Duelo de Descasque (placar, tempo, contagem, resultado e o botão
-- "Sair da mesa" enquanto espera o adversário). O descascar em si é o PeelController de
-- sempre, que usa a mesa do duelo quando o jogador está sentado numa (atributo DuelSeat).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local player = Players.LocalPlayer

local Duel = {}

local C
local gui: ScreenGui
local panel: Frame
local myName: TextLabel
local myScore: TextLabel
local opName: TextLabel
local opScore: TextLabel
local timer: TextLabel
local leave: TextButton
local big: TextLabel
local sub: TextLabel
local resultUntil = 0
local goUntil = 0
local lastShown = ""

local function arena(): Instance?
	local world = Workspace:FindFirstChild("World")
	return world and world:FindFirstChild("Arena")
end

local function label(parent: Instance, props): TextLabel
	local T = C.HUD.Theme
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

local function build()
	local T = C.HUD.Theme
	gui = Instance.new("ScreenGui")
	gui.Name = "DuelHUD"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 20
	gui.Parent = player:WaitForChild("PlayerGui")

	panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.new(0.5, 0, 0, 118)
	panel.Size = UDim2.fromOffset(420, 92)
	panel.BackgroundColor3 = T.Panel
	panel.BackgroundTransparency = 0.1
	panel.Visible = false
	panel.Parent = gui
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = panel
	local s = Instance.new("UIStroke")
	s.Color = T.Rust
	s.Thickness = 2
	s.Parent = panel
	label(panel, { Text = "DUELO DE DESCASQUE", Font = T.FontTitle, TextColor3 = T.Gold, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 4) })
	myName = label(panel, { Text = "Você", Size = UDim2.new(0.34, 0, 0, 20), Position = UDim2.new(0.02, 0, 0, 26), TextXAlignment = Enum.TextXAlignment.Left })
	opName = label(panel, { Text = "...", Size = UDim2.new(0.34, 0, 0, 20), Position = UDim2.new(0.64, 0, 0, 26), TextXAlignment = Enum.TextXAlignment.Right })
	myScore = label(panel, { Text = "0", TextColor3 = T.Gold, Size = UDim2.new(0.18, 0, 0, 40), Position = UDim2.new(0.22, 0, 0, 46), Font = Enum.Font.GothamBold })
	opScore = label(panel, { Text = "0", TextColor3 = T.Bone, Size = UDim2.new(0.18, 0, 0, 40), Position = UDim2.new(0.6, 0, 0, 46), Font = Enum.Font.GothamBold })
	timer = label(panel, { Text = "", TextColor3 = T.Bone, Size = UDim2.new(0.2, 0, 0, 30), Position = UDim2.new(0.4, 0, 0, 50) })

	leave = Instance.new("TextButton")
	leave.Name = "Leave"
	leave.AnchorPoint = Vector2.new(0.5, 0)
	leave.Position = UDim2.new(0.5, 0, 0, 218)
	leave.Size = UDim2.fromOffset(170, 36)
	leave.BackgroundColor3 = T.Rust
	leave.Font = T.Font
	leave.TextScaled = true
	leave.TextColor3 = T.Bone
	leave.Text = "Sair da mesa"
	leave.Visible = false
	leave.Parent = gui
	local lc = Instance.new("UICorner")
	lc.CornerRadius = UDim.new(0, 6)
	lc.Parent = leave
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.Parent = leave
	leave.Activated:Connect(function()
		Remotes.Duel:FireServer("Leave")
	end)

	big = label(gui, { Name = "Big", Text = "", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.38), Size = UDim2.fromScale(0.6, 0.14), Font = T.FontTitle, TextColor3 = T.Gold, Visible = false })
	local bs = Instance.new("UIStroke")
	bs.Thickness = 3
	bs.Color = Color3.fromRGB(20, 16, 14)
	bs.Parent = big
	sub = label(gui, { Name = "Sub", Text = "", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.47), Size = UDim2.fromScale(0.5, 0.05), Visible = false })
	local ss = Instance.new("UIStroke")
	ss.Thickness = 2
	ss.Color = Color3.fromRGB(20, 16, 14)
	ss.Parent = sub
end

local function pop(l: TextLabel)
	local sc = l:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	sc.Parent = l
	sc.Scale = 1.35
	TweenService:Create(sc, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

local function showBig(text: string, color: Color3, subText: string?)
	big.Text = text
	big.TextColor3 = color
	big.Visible = true
	sub.Text = subText or ""
	sub.Visible = subText ~= nil
	if text ~= lastShown then
		lastShown = text
		pop(big)
	end
end

local function update()
	local T = C.HUD.Theme
	local A = arena()
	local seat = player:GetAttribute("DuelSeat")
	local now = Workspace:GetServerTimeNow()
	local state = A and A:GetAttribute("DuelState") or "Idle"
	local showingResult = os.clock() < resultUntil
	panel.Visible = (seat ~= nil) or showingResult
	leave.Visible = seat ~= nil and state == "Idle"
	if A and seat then
		local opp = if seat == "A" then "B" else "A"
		myName.Text = "Você"
		local on = A:GetAttribute("Name" .. opp)
		opName.Text = if on and on ~= "" then on else "esperando..."
		local ms, os_ = tostring(A:GetAttribute("Score" .. seat) or 0), tostring(A:GetAttribute("Score" .. opp) or 0)
		if myScore.Text ~= ms then
			myScore.Text = ms
			pop(myScore)
		end
		if opScore.Text ~= os_ then
			opScore.Text = os_
			pop(opScore)
		end
		if state == "Playing" then
			local left = math.max(0, math.ceil((A:GetAttribute("EndsAt") or now) - now))
			timer.Text = string.format("%d:%02d", left // 60, left % 60)
			timer.TextColor3 = if left <= 10 then T.Blood else T.Bone
		elseif state == "Countdown" then
			timer.Text = "x"
		else
			timer.Text = "x"
		end
	end
	if showingResult then
		return
	end
	if A and seat and state == "Countdown" then
		local n = math.ceil((A:GetAttribute("CountdownEnd") or now) - now)
		if n >= 1 then
			showBig(tostring(n), T.Gold, "Quem descascar mais batatas vence. Quem perder... leva bala.")
			return
		end
	end
	if os.clock() < goUntil then
		showBig("JÁ!", T.Gold, nil)
		return
	end
	big.Visible = false
	sub.Visible = false
	lastShown = ""
end

local function onEvent(kind: string, d)
	local T = C.HUD.Theme
	if kind == "Seated" then
		C.HUD.Toast("Esperando um adversário sentar na outra mesa...", T.Gold)
	elseif kind == "Start" then
		goUntil = os.clock() + 0.9
		C.Effects.Play("ComboUp")
	elseif kind == "Result" then
		resultUntil = os.clock() + 4.5
		if d.Outcome == "Win" then
			local extra = if d.Streak and d.Streak > 1 then ("  ·  " .. d.Streak .. " vitórias seguidas") else ""
			local head = if d.Reason == "Left" then "O ADVERSÁRIO FUGIU!" else "VOCÊ VENCEU!"
			showBig(head, T.Gold, d.Score .. "  ·  +" .. tostring(d.Coins) .. " Moedas" .. extra)
			C.Effects.Play("ComboUp", 1.2)
		elseif d.Outcome == "Lose" then
			showBig("VOCÊ PERDEU...", T.Blood, d.Score .. "  ·  O guarda do Rei não perdoa.")
		else
			showBig("EMPATE", T.Bone, d.Score .. "  ·  +" .. tostring(d.Coins) .. " Moedas")
		end
	end
end

function Duel.Init(controllers)
	C = controllers
	build()
	Remotes:WaitForChild("Duel").OnClientEvent:Connect(onEvent)
	RunService.Heartbeat:Connect(update)
end

return Duel
