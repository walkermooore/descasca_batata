-- KitchenService: lotes de cozinha, pilha, carrinho e entrega ao Rei (seções 2.2 e 2.6).
-- Fluxo: pilha -> descascar na mesa -> esteira (BeltService) -> carrinho -> Rei.
-- O carrinho é animado no cliente (CartAnimator); o servidor só troca estados e números.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Strings = require(Shared.Strings)
local Geo = require(Shared.PotatoGeometry)
local Format = require(Shared.Format)
local Remotes = ReplicatedStorage.Remotes

local KitchenService = {}

local S -- tabela de serviços
local kitchens = {}
local cartCapacity -- definida abaixo (depende do dono da cozinha)
local byPlayer: { [Player]: any } = {} -- cozinha onde o jogador trabalha (a própria ou a de um amigo)
local owned: { [Player]: any } = {} -- cozinha que o jogador possui
local invites: { [Player]: any } = {}
local rng = Random.new()

local PEELED_SIZE = Vector3.new(0.42, 0.34, 0.52)

-- ---------------------------------------------------------------- utilidades

function KitchenService.Notify(player: Player, text: string)
	Remotes.Notify:FireClient(player, text)
end

local function miniPotato(color: Color3, size: Vector3): Part
	local p = Instance.new("Part")
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end
KitchenService.MiniPotato = miniPotato

local function jitter(c: Color3, amount: number): Color3
	local h, s, v = c:ToHSV()
	return Color3.fromHSV(h, s, math.clamp(v + rng:NextNumber(-amount, amount), 0, 1))
end

local function tweenPivot(model: Model, toCF: CFrame, time: number)
	local v = Instance.new("CFrameValue")
	v.Value = model:GetPivot()
	local conn = v.Changed:Connect(function(cf)
		model:PivotTo(cf)
	end)
	local tw = TweenService:Create(v, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { Value = toCF })
	tw:Play()
	tw.Completed:Wait()
	conn:Disconnect()
	v:Destroy()
	model:PivotTo(toCF)
end

function cartCapacity(K): number
	local level = 1
	local data = K.Owner and S.Data.Get(K.Owner)
	if data and data.Upgrades then
		level = data.Upgrades.Cart or 1
	end
	local def = Config.UpgradesById.Cart.Levels
	local base = (def[math.clamp(level, 1, #def)] or def[1]).Value
	-- passe Balde Gigante: +50% no carrinho
	return math.floor(base * S.Monetization.CapacityMultiplier(K.Owner))
end
KitchenService.CartCapacity = function(K)
	return cartCapacity(K)
end

-- passe Carrinho Turbo: +40% na velocidade do carrinho (viagem mais curta)
local function cartTimes(K): (number, number)
	local speed = if K.Owner then S.Monetization.SpeedMultiplier(K.Owner) else 1
	return Config.Delivery.CartTravelTime / speed, Config.Delivery.CartReturnTime / speed
end

local function publish(K)
	local m = K.Model
	local cap = cartCapacity(K)
	m:SetAttribute("CartCount", #K.Cart.Items)
	m:SetAttribute("CartCapacity", cap)
	m:SetAttribute("CartState", K.Cart.State)
	m:SetAttribute("CartStateStart", K.Cart.StateStart)
	m:SetAttribute("CartFull", #K.Cart.Items >= cap)
	K.Cart.Label.Text = string.format("%d/%d", #K.Cart.Items, cap)
end
KitchenService.Publish = publish

-- ---------------------------------------------------------------- pilha

-- Batata com física de verdade: colisão esférica (rola e bate nas outras) e malha oval.
local function physicalPotato(color: Color3, diameter: number): Part
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.one * diameter
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.CanQuery = false
	p.CanTouch = false
	p.CustomPhysicalProperties = PhysicalProperties.new(0.9, 0.9, 0.18, 1, 1)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, 0.82, 1.3)
	mesh.Parent = p
	return p
end
KitchenService.PhysicalPotato = physicalPotato

local function spawnPilePotato(K, height: number?)
	local tarp = K.Model.Station.Pile.Tarp :: BasePart
	local p = physicalPotato(jitter(Config.Potatoes.Comum.SkinColor, 0.06), rng:NextNumber(0.5, 0.62))
	p.Name = "PilePotato"
	p.CFrame = tarp.CFrame
		* CFrame.new(rng:NextNumber(-0.6, 0.6), (height or 2.5) + rng:NextNumber(0, 0.6), rng:NextNumber(-0.6, 0.6))
		* CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), rng:NextNumber(0, 6))
	p.Parent = K.Model.Station.Pile.Display
	p:SetNetworkOwner(nil)
	p.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-4, 4), rng:NextNumber(-4, 4), rng:NextNumber(-4, 4))
	table.insert(K.Pile.Parts, p)
	return p
end

local function buildPile(K)
	local pile = K.Model.Station.Pile
	local tarp = pile.Tarp
	pile.Display:ClearAllChildren()
	-- borda invisível em volta da lona: as batatas se amontoam em vez de rolar pela cozinha
	local walls = pile:FindFirstChild("PileWalls")
	if not walls then
		walls = Instance.new("Folder")
		walls.Name = "PileWalls"
		walls.Parent = pile
		-- caixote estreito e alto: as batatas se empilham num monte em vez de uma camada só
		local h = 2.4
		for _, spec in { { 0, 1.15, 2.6, 0.3 }, { 0, -1.15, 2.6, 0.3 }, { 1.15, 0, 0.3, 2.6 }, { -1.15, 0, 0.3, 2.6 } } do
			local w = Instance.new("Part")
			w.Name = "Wall"
			w.Anchored = true
			w.Transparency = 1
			w.CanQuery = false
			w.CanTouch = false
			w.Size = Vector3.new(spec[3], h, spec[4])
			w.CFrame = tarp.CFrame * CFrame.new(spec[1], tarp.Size.Y / 2 + h / 2, spec[2])
			w.Parent = walls
		end
	end
	K.Pile = { Parts = {} }
	-- monte inicial: solta em camadas e deixa a física acomodar
	for i = 1, Config.Station.PileMaxVisible do
		spawnPilePotato(K, 0.4 + math.floor((i - 1) / 9) * 0.55)
	end
end

-- Estoque infinito: a pilha mostra até 30; pegar tira a batata do topo, e a reposição
-- (1 a cada 0,5 s) cai do alto e quica no monte.
function KitchenService.TakeFromPile(K)
	local best, bestY = nil, -math.huge
	for i, p in K.Pile.Parts do
		if p.Parent and p.Position.Y > bestY then
			best, bestY = i, p.Position.Y
		end
	end
	if best then
		K.Pile.Parts[best]:Destroy()
		table.remove(K.Pile.Parts, best)
	end
end

-- ---------------------------------------------------------------- carrinho: entrada

-- A esteira aceita batata sempre (o limite é o da própria esteira, no BeltService).
function KitchenService.CanAcceptPotato(_K): boolean
	return true
end

-- Coloca uma batata pronta no carrinho. Retorna false se o carrinho está fora ou cheio.
function KitchenService.AddToCart(K, item): boolean
	local cart = K.Cart
	if cart.State ~= "Home" or #cart.Items >= cartCapacity(K) then
		return false
	end
	table.insert(cart.Items, item)
	cart.Value += item.Value
	KitchenService.RefreshCart(K)
	if #cart.Items >= cartCapacity(K) then
		KitchenService.SendCart(K) -- cheio: parte sozinho para o Rei
	end
	return true
end

-- compatibilidade: quem ainda chama as funções do balde antigo não quebra
function KitchenService.ReturnBucket(_K) end
function KitchenService.DropBucket(_player) end
function KitchenService.PickBucket(_player, _K) end
function KitchenService.Dump(_player, _K) end

-- ---------------------------------------------------------------- carrinho

local CART_SLOTS = {}
for layer = 0, 1 do
	for ix = -2, 2 do
		for iz = -2, 2 do
			table.insert(CART_SLOTS, Vector3.new(ix * 0.45, 0.72 + layer * 0.34, iz * 0.7))
		end
	end
end

-- Conteúdo do carrinho com física: cada batata nova cai de cima e se acomoda (e bate nas outras).
-- O servidor guarda o carrinho em casa; quando ele parte, o conteúdo congela para viajar junto
-- (o cliente anima o carrinho inteiro).
function KitchenService.RefreshCart(K)
	local cart = K.Cart
	local target = math.min(#cart.Items, #CART_SLOTS)
	local parts = cart.Contents:GetChildren()
	if target == 0 then
		cart.Contents:ClearAllChildren()
		publish(K)
		return
	end
	for i = #parts + 1, target do
		local item = cart.Items[i]
		local p = physicalPotato(Config.Potatoes[item.Type].FleshColor, 0.44)
		p.Name = "CartPotato"
		p.CFrame = cart.HomeCF * CFrame.new(rng:NextNumber(-0.8, 0.8), 2.4 + rng:NextNumber(0, 1.2), rng:NextNumber(-1.3, 1.3))
		p.Anchored = cart.State ~= "Home"
		p.Parent = cart.Contents
		if not p.Anchored then
			p:SetNetworkOwner(nil)
		end
	end
	for i = target + 1, #parts do
		parts[i]:Destroy()
	end
	publish(K)
end

local function freezeCart(K)
	for _, p in K.Cart.Contents:GetChildren() do
		if p:IsA("BasePart") then
			p.Anchored = true
		end
	end
end

function KitchenService.SendCart(K)
	local cart = K.Cart
	if cart.State ~= "Home" or #cart.Items == 0 then
		return
	end
	freezeCart(K)
	local travel, back = cartTimes(K)
	K.Model:SetAttribute("CartTravel", travel)
	K.Model:SetAttribute("CartReturn", back)
	cart.State = "ToKing"
	cart.StateStart = Workspace:GetServerTimeNow()
	publish(K)
	local owner = K.Owner
	if owner then
		S.Bus.Fire("CartSent", owner)
	end
	task.delay(travel, function()
		local value, count = cart.Value, #cart.Items
		local producers = {}
		for _, item in cart.Items do
			if item.Producer then
				producers[item.Producer] = (producers[item.Producer] or 0) + item.Value
			end
		end
		cart.Items = {}
		cart.Value = 0
		cart.State = "Returning"
		cart.StateStart = Workspace:GetServerTimeNow()
		KitchenService.RefreshCart(K)
		if owner and owner.Parent and K.Owner == owner then
			-- bônus de equipe: +10% por amigo na cozinha (máx. +30%)
			local bonus = 1 + KitchenService.TeamBonus(K)
			local amount = math.max(1, math.floor(value * bonus + 0.5))
			-- o número que voa na tela já inclui passes e boosts
			Remotes.Delivered:FireClient(owner, S.Economy.Preview(owner, amount, "Delivery"), cart.EndPos, count)
			S.Economy.Add(owner, amount, "Delivery")
			-- cada ajudante recebe 30% do que produziu, sem descontar do dono
			for userId, produced in producers do
				local helper = Players:GetPlayerByUserId(userId)
				if helper and helper ~= owner then
					local share = produced * bonus * Config.Social.HelperShare
					if share >= 0.5 then
						local paid = S.Economy.Add(helper, share, "HelperShare")
						Remotes.Delivered:FireClient(helper, paid, cart.EndPos, 0)
					end
				end
			end
			local data = S.Data.Get(owner)
			if data then
				data.Stats.PotatoesDelivered += count
				data.Stats.SeasonDelivered += count
				owner:SetAttribute("SeasonDelivered", data.Stats.SeasonDelivered)
			end
			S.Bus.Fire("Delivered", owner, amount, count)
		end
		task.delay(back, function()
			cart.State = "Home"
			cart.StateStart = Workspace:GetServerTimeNow()
			publish(K)
		end)
	end)
end

-- Visual das melhorias (descascador automático ao lado da esteira).
function KitchenService.ApplyUpgrades(K)
	if S.Belt then
		S.Belt.Refresh(K)
	end
	publish(K)
end

function KitchenService.RefreshOwner(player: Player)
	local K = owned[player]
	if K then
		KitchenService.ApplyUpgrades(K)
	end
end

-- Batatas das máquinas antigas (grade): vão para a esteira.
function KitchenService.AddMachinePotatoes(K, n: number, value: number): number
	local accepted = 0
	for _ = 1, n do
		if not (S.Belt and S.Belt.Push(K, { Value = value, Type = "Comum", Machine = true })) then
			break
		end
		accepted += 1
	end
	return accepted
end

-- Tanque -> carrinho pelo cano. Com o tanque ligado, o carrinho parte sozinho quando enche.
function KitchenService.LoadCart(K, n: number, value: number): number
	local cart = K.Cart
	if cart.State ~= "Home" or n <= 0 then
		return 0
	end
	local cap = cartCapacity(K)
	local k = math.min(n, cap - #cart.Items)
	for _ = 1, k do
		table.insert(cart.Items, { Value = value, Type = "Comum", Machine = true })
		cart.Value += value
	end
	if k > 0 then
		KitchenService.RefreshCart(K)
	end
	if #cart.Items >= cap then
		KitchenService.SendCart(K)
	end
	return k
end

local WALLS = { BackL = true, BackR = true, Left = true, Right = true, FrontL = true, FrontR = true, SideL = true, SideR = true, End = true }
local TRIMS = { Trim = true, TrimBack = true, Lintel = true, BackLintel = true }

local function styleOf(spec): (Enum.Material, Color3)
	return (Enum.Material :: any)[spec[1]], spec[2]
end

-- Alas: piso, grade, cerca e placa de preço da próxima ala.
function KitchenService.ApplyWings(K, count: number)
	K.Model:SetAttribute("Wings", count)
	local theme = Config.Themes[K.Theme or "Castelo"] or Config.Themes.Castelo
	local wings = K.Model:FindFirstChild("Wings")
	if not wings then
		return
	end
	for w = 1, Config.Grid.Wings do
		local wing = wings:FindFirstChild("Wing" .. w)
		if wing then
			local open = w <= count
			local floor = wing.Floor
			if open then
				floor.Material, floor.Color = styleOf(theme.Floor)
			else
				floor.Material, floor.Color = Enum.Material.Ground, Color3.fromRGB(40, 34, 28)
			end
			for _, g in wing.Grid:GetChildren() do
				(g :: BasePart).Transparency = if open then 0.35 else 1
			end
			for _, p in wing.Fence:GetDescendants() do
				if p:IsA("BasePart") then
					p.Transparency = if open then 1 else 0
					p.CanCollide = not open
					p.CanQuery = not open
				elseif p:IsA("SurfaceGui") then
					-- só a placa da próxima ala (as de trás apareciam pela grade); sem a grade de
					-- máquinas (Features.Build desligado) a ala fica fechada e sem placa
					p.Enabled = Config.Features.Build and w == count + 1
					local label = p:FindFirstChild("Text") :: TextLabel?
					if label then
						label.Text = if w == count + 1
							then string.format(Strings.WingLocked, w, Format.Int(Config.Grid.WingCosts[w]))
							else "ALA " .. w .. " BLOQUEADA"
					end
				elseif p:IsA("ProximityPrompt") then
					p.Enabled = Config.Features.Build and w == count + 1
					p.ObjectText = string.format("Ala %d · %s Moedas", w, Format.Int(Config.Grid.WingCosts[w]))
				end
			end
		end
	end
end

-- Cozinhas temáticas: trocam só paredes, piso, acabamento e luz (seção 7.7).
function KitchenService.ApplyTheme(K, themeId: string)
	local theme = Config.Themes[themeId] or Config.Themes.Castelo
	K.Theme = if Config.Themes[themeId] then themeId else "Castelo"
	K.Model:SetAttribute("Theme", K.Theme)
	local function paint(container: Instance?)
		if not container then
			return
		end
		for _, p in container:GetDescendants() do
			if p:IsA("BasePart") then
				if WALLS[p.Name] then
					p.Material, p.Color = styleOf(theme.Wall)
				elseif p.Name == "Wainscot" then
					p.Material, p.Color = styleOf(theme.Lower or theme.Wall)
				elseif TRIMS[p.Name] then
					p.Material, p.Color = styleOf(theme.Trim)
				end
			end
		end
	end
	paint(K.Model:FindFirstChild("Walls"))
	paint(K.Model:FindFirstChild("Wings"))
	local floor = K.Model:FindFirstChild("Floor") :: BasePart?
	if floor then
		floor.Material, floor.Color = styleOf(theme.Floor)
	end
	local dressing = K.Model:FindFirstChild("Dressing")
	local lamp = dressing and dressing:FindFirstChild("Lamp") :: BasePart?
	if lamp then
		lamp.Color = theme.Light
		local l = lamp:FindFirstChildOfClass("PointLight")
		if l then
			l.Color = theme.Light
		end
	end
	paint(dressing)
	KitchenService.ApplyWings(K, K.Model:GetAttribute("Wings") or 0)
end

function KitchenService.ChestPosition(K): Vector3
	return K.Chest:GetPivot().Position + Vector3.new(0, 1.5, 0)
end

-- ---------------------------------------------------------------- donos

function KitchenService.GetKitchen(player: Player)
	return byPlayer[player]
end

function KitchenService.GetByIndex(i: number)
	return kitchens[i]
end

function KitchenService.DistanceToTable(K, pos: Vector3): number
	return Geo.DistanceToBox(K.TableTop, pos)
end

local function setSign(K, text: string)
	local gui = K.Model.OwnerSign:FindFirstChildOfClass("SurfaceGui")
	if gui then
		gui.Text.Text = text
	end
end

-- ---------------------------------------------------------------- co-op (seção 5)

function KitchenService.GetOwnedKitchen(player: Player)
	return owned[player]
end

function KitchenService.CanUse(K, player: Player): boolean
	return K.Owner == player or table.find(K.Members, player) ~= nil
end

function KitchenService.TeamBonus(K): number
	local n = 0
	for _, m in K.Members do
		if m.Parent then
			n += 1
		end
	end
	return math.min(Config.Social.TeamBonusMax, n * Config.Social.TeamBonusPerFriend)
end

local function publishMembers(K)
	local names = {}
	for _, m in K.Members do
		table.insert(names, m.DisplayName)
	end
	K.Model:SetAttribute("Members", table.concat(names, ", "))
	K.Model:SetAttribute("MemberCount", #K.Members)
	K.Model:SetAttribute("TeamBonus", KitchenService.TeamBonus(K))
end

local function setWorkKitchen(player: Player, K)
	byPlayer[player] = K
	player:SetAttribute("KitchenIndex", K and K.Index or 0)
	player:SetAttribute("GuestOf", if K and K.Owner ~= player then K.Owner.DisplayName else nil)
end

local function teleportTo(player: Player, K)
	local char = player.Character
	if K and char and char.Parent then
		char:PivotTo(K.Spawn.CFrame)
	end
end

-- Sai da cozinha do amigo (volta para a própria, se tiver).
function KitchenService.Leave(player: Player, silent: boolean?)
	local K = byPlayer[player]
	if not K or K.Owner == player then
		return false
	end
	local i = table.find(K.Members, player)
	if i then
		table.remove(K.Members, i)
	end
	S.Session.ResetHands(player)
	publishMembers(K)
	setWorkKitchen(player, owned[player])
	if player.Parent then
		teleportTo(player, owned[player])
	end
	if not silent and K.Owner then
		KitchenService.Notify(K.Owner, player.DisplayName .. " saiu da sua cozinha")
	end
	return true
end

function KitchenService.Invite(owner: Player, target: Player)
	local K = owned[owner]
	if not K or not target or target == owner or not target.Parent then
		return { Ok = false }
	end
	if byPlayer[target] == K then
		return { Ok = false, Reason = "Já está na sua cozinha" }
	end
	if 1 + #K.Members >= Config.Server.MaxPlayersPerKitchen then
		return { Ok = false, Reason = "Cozinha cheia (4 pessoas)" }
	end
	invites[target] = { K = K, From = owner, Expires = os.clock() + Config.Social.InviteSeconds }
	Remotes.Social:FireClient(target, "Invite", { From = owner.DisplayName, Seconds = Config.Social.InviteSeconds })
	return { Ok = true }
end

function KitchenService.AcceptInvite(player: Player)
	local inv = invites[player]
	invites[player] = nil
	if not inv or os.clock() > inv.Expires or inv.K.Owner ~= inv.From then
		return { Ok = false, Reason = "Convite expirou" }
	end
	local K = inv.K
	if 1 + #K.Members >= Config.Server.MaxPlayersPerKitchen then
		return { Ok = false, Reason = "Cozinha cheia" }
	end
	local st = S.Session.GetState(player)
	if st ~= "Free" and st ~= "Holding" then
		return { Ok = false, Reason = "Termine o que está fazendo primeiro" }
	end
	KitchenService.Leave(player, true)
	S.Session.ResetHands(player)
	table.insert(K.Members, player)
	setWorkKitchen(player, K)
	publishMembers(K)
	teleportTo(player, K)
	KitchenService.Notify(K.Owner, player.DisplayName .. " entrou na sua cozinha (+10% de produção)")
	return { Ok = true }
end

function KitchenService.Kick(owner: Player, target: Player)
	local K = owned[owner]
	if K and target and table.find(K.Members, target) then
		KitchenService.Leave(target, true)
		KitchenService.Notify(target, "Você saiu da cozinha de " .. owner.DisplayName)
		return { Ok = true }
	end
	return { Ok = false }
end

function KitchenService.All()
	return kitchens
end

local function teleportHome(player: Player, char: Model)
	local K = byPlayer[player]
	if not K then
		return
	end
	char:WaitForChild("HumanoidRootPart", 5)
	task.wait()
	if char.Parent then
		char:PivotTo(K.Spawn.CFrame)
	end
end

local function assign(player: Player)
	for _, K in kitchens do
		if not K.Owner then
			K.Owner = player
			owned[player] = K
			setWorkKitchen(player, K)
			player:SetAttribute("OwnKitchenIndex", K.Index)
			K.Model:SetAttribute("OwnerUserId", player.UserId)
			K.Model:SetAttribute("OwnerName", player.DisplayName)
			setSign(K, string.format(Strings.KitchenOf, player.DisplayName))
			task.spawn(function()
				local data = S.Data.WaitForData(player)
				if data and K.Owner == player then
					KitchenService.ApplyUpgrades(K)
					K.Model:SetAttribute("Wings", data.Wings)
					KitchenService.ApplyTheme(K, data.Theme)
				end
			end)
			if player.Character then
				task.spawn(teleportHome, player, player.Character)
			end
			return
		end
	end
	player:SetAttribute("KitchenIndex", 0)
	player:SetAttribute("OwnKitchenIndex", 0)
	task.delay(3, KitchenService.Notify, player, Strings.NoKitchen)
end

local function release(player: Player)
	invites[player] = nil
	KitchenService.Leave(player)
	byPlayer[player] = nil
	local K = owned[player]
	if not K then
		return
	end
	owned[player] = nil
	-- os convidados voltam para as próprias cozinhas
	for _, m in table.clone(K.Members) do
		KitchenService.Leave(m, true)
		KitchenService.Notify(m, "O dono da cozinha saiu do jogo")
	end
	K.Owner = nil
	K.Model:SetAttribute("OwnerUserId", 0)
	K.Model:SetAttribute("OwnerName", nil)
	setSign(K, Strings.KitchenFree)
	if S.Belt then
		S.Belt.Clear(K)
	end
	KitchenService.ApplyUpgrades(K)
	K.Model:SetAttribute("Wings", 0)
	KitchenService.ApplyTheme(K, "Castelo")
	S.Machines.ClearKitchen(K)
	if K.Cart.State == "Home" then
		K.Cart.Items = {}
		K.Cart.Value = 0
	end
	for _, P in table.clone(K.Loose) do
		S.Peel.DestroyPotato(P)
	end
	KitchenService.RefreshCart(K)
end

-- ---------------------------------------------------------------- init

local function wirePrompt(prompt: ProximityPrompt, K)
	prompt.Triggered:Connect(function(player)
		local kind = prompt:GetAttribute("Kind")
		if not KitchenService.CanUse(K, player) then
			return
		end
		-- só o dono compra alas e aceita os pedidos do quadro da própria cozinha
		if (kind == "Wing" or kind == "Order") and K.Owner ~= player then
			return
		end
		if kind == "Pile" then
			S.Peel.GivePotato(player, K)
		elseif kind == "Belt" then
			S.Belt.PlaceHeld(player, K)
		elseif kind == "Send" then
			local st = S.Session.GetState(player)
			if st ~= "Peeling" and st ~= "Loading" then
				KitchenService.SendCart(K)
			end
		elseif kind == "Chest" then
			S.Rewards.OpenChest(player, K)
		elseif kind == "Order" then
			S.Orders.Accept(player)
		elseif kind == "Wing" then
			S.Machines.BuyWing(player)
		end
	end)
end

local function setupKitchen(model: Model)
	local index = model:GetAttribute("KitchenIndex") :: number
	local station = model:WaitForChild("Station")
	local cartModel = model:WaitForChild("Cart") :: Model
	local root = cartModel:WaitForChild("Root") :: BasePart

	local loose = Instance.new("Folder")
	loose.Name = "LoosePotatoes"
	loose.Parent = model

	local railEnd = model:WaitForChild("RailEnd") :: BasePart
	local K = {
		Index = index,
		Model = model,
		Owner = nil,
		Members = {},
		TableTop = station.Table.TableTop,
		Belt = model:WaitForChild("Belt"),
		LooseFolder = loose,
		Loose = {},
		Spawn = model.KitchenSpawn,
		Chest = model:WaitForChild("Chest"),
		BoardText = model.OrderBoard:FindFirstChild("OrderText", true),
		Cart = {
			Model = cartModel,
			Root = root,
			Contents = cartModel.Contents,
			Label = root.CountGui.Label,
			Items = {},
			Value = 0,
			State = "Home",
			StateStart = 0,
			HomeCF = root.CFrame,
			EndPos = Vector3.new(root.Position.X, root.Position.Y, railEnd.Position.Z),
		},
	}
	model:SetAttribute("CartHome", root.Position)
	model:SetAttribute("CartEnd", K.Cart.EndPos)
	kitchens[index] = K

	buildPile(K)
	publish(K)
	KitchenService.ApplyTheme(K, "Castelo")
	for _, d in model:GetDescendants() do
		if d:IsA("ProximityPrompt") and CollectionService:HasTag(d, "KitchenPrompt") then
			wirePrompt(d, K)
		end
	end
end

function KitchenService.Init(services)
	S = services
	local folder = Workspace:WaitForChild("Kitchens")
	for _, model in folder:GetChildren() do
		setupKitchen(model)
	end

	local function onPlayer(p: Player)
		assign(p)
		p.CharacterAdded:Connect(function(char)
			teleportHome(p, char)
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in Players:GetPlayers() do
		task.spawn(onPlayer, p)
	end
	Players.PlayerRemoving:Connect(release)

	-- repõe a pilha
	task.spawn(function()
		while true do
			task.wait(Config.Station.PileRefillInterval)
			for _, K in kitchens do
				for i = #K.Pile.Parts, 1, -1 do
					local p = K.Pile.Parts[i]
					-- batata que caiu para fora da borda: some e volta pela reposição
					if not p.Parent or p.Position.Y < K.Model.Station.Pile.Tarp.Position.Y - 1 then
						p:Destroy()
						table.remove(K.Pile.Parts, i)
					end
				end
				if #K.Pile.Parts < Config.Station.PileMaxVisible then
					spawnPilePotato(K, 3)
				end
			end
		end
	end)
end

return KitchenService
