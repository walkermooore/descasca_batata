-- RewardController: anúncios grandes (batata dourada, baú, pedido cumprido) e as falas do Rei
-- Glutão em balão (seção 6: "reclama, elogia e faz pedidos por balões de fala").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Format = require(Shared:WaitForChild("Format"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local player = Players.LocalPlayer

local Rewards = {}

local C
local T
local card: Frame
local cardTitle: TextLabel
local cardText: TextLabel
local king: Frame
local kingText: TextLabel
local cardToken, kingToken = 0, 0

function Rewards.Card(title: string, text: string, color: Color3?)
	cardToken += 1
	local my = cardToken
	cardTitle.Text = title
	cardTitle.TextColor3 = color or T.Gold
	cardText.Text = text
	card.Visible = true
	local scale = card:FindFirstChildOfClass("UIScale") :: UIScale
	scale.Scale = 0.6
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(3, function()
		if my == cardToken then
			card.Visible = false
		end
	end)
end

function Rewards.KingSays(text: string)
	kingToken += 1
	local my = kingToken
	kingText.Text = text
	king.Visible = true
	king.Position = UDim2.new(0, -330, 1, -190)
	TweenService:Create(king, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(0, 16, 1, -190) }):Play()
	task.delay(3.2, function()
		if my == kingToken then
			TweenService:Create(king, TweenInfo.new(0.3), { Position = UDim2.new(0, -330, 1, -190) }):Play()
		end
	end)
end

-- Chamado pelo PeelController quando a dourada termina de voar para o balde.
function Rewards.Golden(reward)
	if not reward then
		return
	end
	C.Effects.Play("ComboUp", 0.8)
	local text
	if reward.Kind == "Key" then
		text = Strings.GotKey
	elseif reward.RoomUnlocked then
		text = Strings.RoomUnlocked
	else
		text = string.format(Strings.GotFragment, reward.Fragments, reward.Needed)
	end
	Rewards.Card(Strings.Golden, text, T.Gold)
end

local function build()
	local gui = C.HUD.Gui()
	card = Instance.new("Frame")
	card.Name = "RewardCard"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.38)
	card.Size = UDim2.fromOffset(460, 120)
	card.BackgroundColor3 = T.Panel
	card.BackgroundTransparency = 0.05
	card.Visible = false
	card.ZIndex = 40
	card.Parent = gui
	C.HUD.Corner(card, 10)
	C.HUD.Stroke(card, T.Gold, 3)
	Instance.new("UIScale").Parent = card
	cardTitle = C.HUD.Label(card, { Text = "", Font = T.FontTitle, Size = UDim2.new(1, -24, 0, 46), Position = UDim2.fromOffset(12, 10) })
	cardText = C.HUD.Label(card, { Text = "", TextWrapped = true, Size = UDim2.new(1, -24, 0, 48), Position = UDim2.fromOffset(12, 60) })

	-- balão do Rei (canto inferior esquerdo)
	king = Instance.new("Frame")
	king.Name = "King"
	king.Size = UDim2.fromOffset(310, 96)
	king.Position = UDim2.new(0, -330, 1, -190)
	king.BackgroundColor3 = Color3.fromRGB(58, 22, 20)
	king.BackgroundTransparency = 0.05
	king.Visible = false
	king.ZIndex = 35
	king.Parent = gui
	C.HUD.Corner(king, 10)
	C.HUD.Stroke(king, T.Gold, 2)
	local crown = Instance.new("Frame")
	crown.Size = UDim2.fromOffset(70, 70)
	crown.Position = UDim2.fromOffset(12, 13)
	crown.BackgroundColor3 = Color3.fromRGB(226, 180, 140)
	crown.Parent = king
	C.HUD.Corner(crown, 35)
	C.HUD.Stroke(crown, T.Gold, 3)
	C.HUD.Label(crown, { Text = "♕", TextColor3 = T.Gold, Size = UDim2.fromScale(1, 1), Font = Enum.Font.GothamBold })
	C.HUD.Label(king, { Text = Strings.KingName, TextColor3 = T.Gold, Font = T.FontTitle, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, -104, 0, 24), Position = UDim2.fromOffset(94, 10) })
	kingText = C.HUD.Label(king, { Text = "", TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, -104, 0, 48), Position = UDim2.fromOffset(94, 38) })
end

function Rewards.Init(controllers)
	C = controllers
	T = C.HUD.Theme
	build()
	Remotes.Reward.OnClientEvent:Connect(function(kind: string, info)
		info = info or {}
		if kind == "Chest" then
			C.HUD.FlyCoins(info.Amount, info.Pos)
			C.Effects.Play("Coins")
			Rewards.Card("BAÚ DO PORÃO", string.format(Strings.ChestOpened, Format.Int(info.Amount)))
		elseif kind == "Order" then
			C.HUD.FlyCoins(info.Amount, nil)
			C.Effects.Play("Coins")
			Rewards.Card(Strings.OrderTitle, string.format(Strings.OrderDone, Format.Int(info.Amount)))
			Rewards.KingSays("Hmm. É isso que eu queria. Por enquanto.")
		elseif kind == "OrderFailed" then
			C.HUD.Toast(Strings.OrderFailed, T.Blood)
			Rewards.KingSays("LENTO DEMAIS! Esqueça o pedido.")
		elseif kind == "Discard" then
			C.Effects.Play("Squish", 0.7)
			if info.Amount and info.Amount > 0 then
				C.HUD.FlyCoins(info.Amount, info.Pos)
				C.HUD.Toast(string.format(Strings.Discarded, Format.Int(info.Amount)), T.Gold)
			end
		elseif kind == "King" then
			Rewards.KingSays(info.Text)
		elseif kind == "GiantStart" then
			Rewards.KingSays(string.format("PEDIDO GIGANTE! Quero %s batatas em %d minutos. TODOS!", Format.Int(info.Goal), math.floor(info.Seconds / 60)))
			C.Effects.Play("ComboUp", 0.6)
		elseif kind == "GiantDone" then
			C.HUD.FlyCoins(info.Amount, nil)
			C.Effects.Play("Coins")
			Rewards.Card("BAÚ DO REI", "Pedido Gigante cumprido! +" .. Format.Int(info.Amount) .. " Moedas")
			Rewards.KingSays("...Satisfeito. Por uma hora. Talvez.")
		elseif kind == "GiantFailed" then
			Rewards.KingSays("INÚTEIS! O pedido gigante falhou.")
		elseif kind == "RaceResult" then
			local lines = {}
			for i, r in info.Board do
				table.insert(lines, i .. ". " .. r.Name .. " (" .. Format.Dec(r.Score, 1) .. ")")
			end
			if info.Prize > 0 then
				C.HUD.FlyCoins(info.Prize, nil)
			end
			Rewards.Card("CORRIDA: " .. info.Rank .. "º LUGAR", table.concat(lines, "   ") .. (if info.Prize > 0 then "\n+" .. Format.Int(info.Prize) .. " Moedas" else ""), if info.Rank == 1 then T.Gold else T.Bone)
		elseif kind == "Offline" then
			C.HUD.FlyCoins(info.Amount, nil)
			C.Effects.Play("Coins")
			Rewards.Card(Strings.OfflineTitle, string.format(Strings.OfflineText, Format.Int(info.Amount), info.Time))
		elseif kind == "Rebirth" then
			C.Effects.Play("ComboUp", 0.7)
			Rewards.Card("TEMPORADA " .. info.Season, string.format(Strings.SeasonDone, info.Season, info.Seeds) .. "\n" .. info.Theme)
			Rewards.KingSays("Nova temporada, mesma fome. AO TRABALHO!")
		end
	end)
	Remotes.Delivered.OnClientEvent:Connect(function()
		if (player:GetAttribute("TutorialStep") or 100) >= 100 then
			local lines = Strings.KingLines
			Rewards.KingSays(lines[math.random(1, #lines)])
		end
	end)
	if player:GetAttribute("DataOffline") then
		task.delay(4, C.HUD.Toast, Strings.DataOffline, T.RustBright)
	end
	player:GetAttributeChangedSignal("DataOffline"):Connect(function()
		if player:GetAttribute("DataOffline") then
			C.HUD.Toast(Strings.DataOffline, T.RustBright)
		end
	end)
end

return Rewards
