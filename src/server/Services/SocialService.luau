-- SocialService: convites para a cozinha, visitas, curtidas + mural do hub, pings rápidos
-- (seção 5). Também roteia os pedidos de ranking e corrida do cliente.
-- Sem troca entre jogadores no lançamento. Chat/voz seguem as regras do Roblox.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = ReplicatedStorage.Remotes

local SocialService = {}

local S
local lastPing: { [Player]: number } = {}

local function today(): number
	return math.floor(os.time() / 86400)
end

local function kitchenByIndex(i: any)
	if typeof(i) ~= "number" then
		return nil
	end
	return S.Kitchen.GetByIndex(i)
end

local function freeToTravel(player: Player): boolean
	local st = S.Session.GetState(player)
	return st == "Free" or st == "Holding"
end

-- Visita: vai até a porta da cozinha (os prompts só funcionam para quem é da cozinha).
local function visit(player: Player, index: any)
	local K = kitchenByIndex(index)
	local char = player.Character
	if not K or not char or not freeToTravel(player) then
		return { Ok = false }
	end
	S.Session.ResetHands(player)
	local door = K.Model:GetPivot() * CFrame.new(0, 3, -19)
	char:PivotTo(CFrame.lookAt(door.Position, (K.Model:GetPivot() * CFrame.new(0, 3, 0)).Position))
	return { Ok = true }
end

local function goHome(player: Player)
	local K = S.Kitchen.GetOwnedKitchen(player)
	local char = player.Character
	if not K or not char or not freeToTravel(player) then
		return { Ok = false }
	end
	-- ajudando um amigo: sair da cozinha dele (Leave já leva para casa)
	if S.Kitchen.GetKitchen(player) ~= K then
		S.Kitchen.Leave(player)
		return { Ok = true }
	end
	S.Session.ResetHands(player)
	char:PivotTo(K.Spawn.CFrame)
	return { Ok = true }
end

local function refreshMural()
	local hub = Workspace:FindFirstChild("World") and Workspace.World:FindFirstChild("Hub")
	local mural = hub and hub:FindFirstChild("Mural")
	local list = mural and mural:FindFirstChild("List", true) :: TextLabel?
	if not list then
		return
	end
	local rows = {}
	for _, K in S.Kitchen.All() do
		if K.Owner then
			table.insert(rows, { Name = K.Owner.DisplayName, Likes = K.Model:GetAttribute("Likes") or 0, Index = K.Index })
		end
	end
	table.sort(rows, function(a, b)
		return a.Likes > b.Likes
	end)
	local lines = {}
	for i = 1, math.min(5, #rows) do
		table.insert(lines, string.format("%d.  %s  —  %s curtidas  (lote %d)", i, rows[i].Name, Format.Int(rows[i].Likes), rows[i].Index))
	end
	list.Text = if #lines > 0 then table.concat(lines, "\n") else "Nenhuma cozinha ainda."
end

local function like(player: Player, index: any)
	local K = kitchenByIndex(index)
	local data = S.Data.Get(player)
	if not K or not K.Owner or K.Owner == player or not data then
		return { Ok = false }
	end
	local owner = K.Owner
	local odata = S.Data.Get(owner)
	if not odata then
		return { Ok = false }
	end
	local key = tostring(owner.UserId)
	if data.LikesGiven[key] == today() then
		return { Ok = false, Reason = "Você já curtiu essa cozinha hoje" }
	end
	data.LikesGiven[key] = today()
	odata.Likes += 1
	K.Model:SetAttribute("Likes", odata.Likes)
	S.Kitchen.Notify(owner, player.DisplayName .. " curtiu sua cozinha")
	refreshMural()
	return { Ok = true }
end

-- Ping rápido: balão sobre a cabeça por 3 s, visível para todos (para quem não tem chat).
local function ping(player: Player, id: any)
	local now = os.clock()
	if (lastPing[player] or 0) + Config.Social.PingCooldown > now then
		return { Ok = false }
	end
	local text
	for _, p in Config.Pings do
		if p.Id == id then
			text = p.Text
		end
	end
	local head = player.Character and player.Character:FindFirstChild("Head") :: BasePart?
	if not text or not head then
		return { Ok = false }
	end
	lastPing[player] = now
	local old = head:FindFirstChild("Ping")
	if old then
		old:Destroy()
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "Ping"
	gui.Size = UDim2.fromOffset(200, 44)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
	gui.MaxDistance = 80
	gui.Adornee = head
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundColor3 = Color3.fromRGB(28, 24, 21)
	l.BackgroundTransparency = 0.1
	l.TextColor3 = Color3.fromRGB(228, 214, 186)
	l.Font = Enum.Font.Oswald
	l.TextScaled = true
	l.Text = text
	l.Parent = gui
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = l
	local s = Instance.new("UIStroke")
	s.Color = Color3.fromRGB(128, 72, 44)
	s.Thickness = 2
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = l
	gui.Parent = head
	Debris:AddItem(gui, 3)
	return { Ok = true }
end

local function kitchenList()
	local rows = {}
	for _, K in S.Kitchen.All() do
		table.insert(rows, {
			Index = K.Index,
			Owner = K.Owner and K.Owner.DisplayName or nil,
			OwnerId = K.Owner and K.Owner.UserId or nil,
			Likes = K.Model:GetAttribute("Likes") or 0,
			Members = #K.Members,
			Theme = K.Theme,
		})
	end
	return rows
end

function SocialService.Init(services)
	S = services
	Remotes.SocialRequest.OnServerInvoke = function(player: Player, action: any, arg: any, arg2: any)
		if S.Session.GetState(player) == "Loading" then
			return { Ok = false }
		end
		if action == "Invite" and typeof(arg) == "number" then
			return S.Kitchen.Invite(player, Players:GetPlayerByUserId(arg))
		elseif action == "Accept" then
			return S.Kitchen.AcceptInvite(player)
		elseif action == "Leave" then
			return { Ok = S.Kitchen.Leave(player) }
		elseif action == "Kick" and typeof(arg) == "number" then
			return S.Kitchen.Kick(player, Players:GetPlayerByUserId(arg))
		elseif action == "Visit" then
			return visit(player, arg)
		elseif action == "Home" then
			return goHome(player)
		elseif action == "Like" then
			return like(player, arg)
		elseif action == "Ping" then
			return ping(player, arg)
		elseif action == "Kitchens" then
			return { Ok = true, Rows = kitchenList() }
		elseif action == "Rankings" and typeof(arg) == "string" and typeof(arg2) == "string" then
			return { Ok = true, Rows = S.Ranking.Get(player, arg, arg2) }
		elseif action == "RaceJoin" then
			return S.Race.Join(player)
		elseif action == "RaceLeave" then
			return S.Race.Leave(player)
		end
		return { Ok = false }
	end

	-- prompts do hub (portal da corrida)
	local function wire(prompt: Instance)
		if prompt:IsA("ProximityPrompt") then
			prompt.Triggered:Connect(function(player)
				local kind = prompt:GetAttribute("Kind")
				if kind == "Race" then
					S.Race.Join(player, true)
				elseif kind == "SecretRoom" then
					-- Horta Proibida: só com 5 fragmentos de mapa (seção 2.9); fechada até RoomOpen
					if not Config.Golden.RoomOpen then
						S.Kitchen.Notify(player, "A Horta Proibida abre em breve.")
						return
					end
					local data = S.Data.Get(player)
					local cave = Workspace.World:FindFirstChild("HortaProibida")
					if data and data.Rooms.HortaProibida and cave and freeToTravel(player) then
						S.Session.ResetHands(player)
						player.Character:PivotTo(cave.Arrival.CFrame * CFrame.new(0, 3, 0))
					elseif data then
						S.Kitchen.Notify(player, string.format("Trancado. Junte %d fragmentos de mapa (você tem %d).", Config.Golden.FragmentsPerRoom, data.Fragments))
					end
				elseif kind == "SecretExit" then
					local gate = Workspace.World.Hub:FindFirstChild("SecretGate")
					if gate and player.Character then
						player.Character:PivotTo(gate.Door.CFrame * CFrame.new(0, 0, -5))
					end
				end
			end)
		end
	end
	for _, p in CollectionService:GetTagged("HubPrompt") do
		wire(p)
	end

	S.Bus.Connect("Loaded", function(player, data)
		local K = S.Kitchen.GetOwnedKitchen(player)
		if K then
			K.Model:SetAttribute("Likes", data.Likes)
		end
		refreshMural()
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastPing[player] = nil
		task.defer(refreshMural)
	end)
end

return SocialService
