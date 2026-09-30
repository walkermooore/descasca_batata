-- PeelService: autoridade do descascar (seções 2.4, 2.5, 2.7 e 2.12).
-- Descascar livre: a casca é uma grade de pedaços (colunas x Segments), cada um com Layers camadas.
-- O cliente diz em quais pedaços a faca passou (cada passada tira uma camada) e quanta polpa
-- raspou; o servidor valida (pedaços válidos, ritmo, distância da mesa, relógio)
-- e calcula rendimento e valor. Com 90% da casca tirada a batata fica pronta e vai
-- para a mão (descascada), para o jogador colocar na esteira.
--
-- Mãos: s.Held (mão direita, a que é descascada) e s.Extra (mão esquerda, com Luvas).
-- Carrinho de mão: s.Stock batatas ainda não sorteadas (o tipo é sorteado ao ir para a mão).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local PeelMath = require(Shared.PeelMath)
local Strings = require(Shared.Strings)
local Format = require(Shared.Format)
local Remotes = ReplicatedStorage.Remotes

local PeelService = {}

local TUTORIAL_DONE = 100

local S
local potatoes = {}
local nextId = 0
local rng = Random.new()

-- ---------------------------------------------------------------- sorteio

function PeelService.GoldenChance(player: Player): number
	local s = S.Session.Get(player)
	local tool = PeelMath.ToolFor(s and s.ToolId)
	local chance = tool.GoldenChance or Config.Golden.BaseChance
	local data = S.Data.Get(player)
	if data then
		chance *= 1 + (data.Talents.SorteDourada or 0) * Config.TalentsById.SorteDourada.PerLevel
	end
	chance *= S.Monetization.GoldenMultiplier(player) -- passe Sorte Dourada (+50%)
	if S.Retention then
		chance *= S.Retention.GoldenHourMultiplier() -- Hora Dourada (x5)
	end
	return chance
end

local forcedType: { [Player]: string } = {} -- só para testes no Studio

function PeelService.DebugForceType(player: Player, ptype: string)
	forcedType[player] = ptype
end

local function rollType(player: Player): string
	if forcedType[player] then
		local t = forcedType[player]
		forcedType[player] = nil
		return t
	end
	local data = S.Data.Get(player)
	-- a primeira batata (e todo o tutorial) é sempre Comum
	if not data or data.Tutorial.Step < TUTORIAL_DONE or data.Stats.PotatoesPicked == 0 then
		return "Comum"
	end
	-- Bússola Dourada: garante a dourada dentro das próximas N batatas
	if data.GoldenPity > 0 then
		data.GoldenPity -= 1
		if data.GoldenPity == 0 then
			return "Dourada"
		end
	end
	if rng:NextNumber() < PeelService.GoldenChance(player) then
		return "Dourada"
	end
	local enabled = Config.Dev.EnabledPotatoTypes
	local total = 0
	for _, t in enabled do
		total += Config.Potatoes[t].Chance
	end
	local r = rng:NextNumber() * total
	for _, t in enabled do
		r -= Config.Potatoes[t].Chance
		if r <= 0 then
			return t
		end
	end
	return enabled[1]
end

-- ---------------------------------------------------------------- batatas

local SEG = Config.Peel.Free.Segments
local LAYERS = Config.Peel.Free.Layers

local function newPotato(K, ptype: string)
	nextId += 1
	local def = Config.Potatoes[ptype]
	local P = {
		Id = nextId,
		Type = ptype,
		Strips = def.Strips,
		Total = def.Strips * SEG, -- pedaços de casca
		Hits = {}, -- id -> camadas já tiradas (0..LAYERS)
		Removed = 0, -- pedaços tirados por completo
		Penalty = 0, -- rendimento perdido raspando polpa
		Peeled = false,
		Spoiled = false,
		Kitchen = K,
		Part = nil,
		Loose = false,
	}
	potatoes[P.Id] = P
	return P
end

local function paintProgress(P)
	if P.Part then
		local def = Config.Potatoes[P.Type]
		P.Part.Color = if P.Peeled then def.FleshColor else def.SkinColor:Lerp(def.FleshColor, P.Removed / P.Total)
	end
end

-- Máscara com as camadas tiradas de cada pedaço ("0120..."): o close reconstrói a batata.
local function cutMask(P): string
	local t = table.create(P.Total, "0")
	for id, h in P.Hits do
		t[id] = tostring(h)
	end
	return table.concat(t)
end

local function decorate(P, part: Part)
	if P.Type == "Podre" then
		-- moscas em volta
		local e = Instance.new("ParticleEmitter")
		e.Name = "Flies"
		e.Texture = "rbxasset://textures/particles/SquareParticle.png"
		e.Color = ColorSequence.new(Color3.fromRGB(20, 20, 16))
		e.Size = NumberSequence.new(0.07)
		e.Rate = 6
		e.Lifetime = NumberRange.new(0.8, 1.4)
		e.Speed = NumberRange.new(0.6, 1.4)
		e.SpreadAngle = Vector2.new(180, 180)
		e.RotSpeed = NumberRange.new(-200, 200)
		e.Acceleration = Vector3.new(0, 0.5, 0)
		e.Parent = part
	elseif P.Type == "Dourada" then
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 205, 90)
		light.Range = 6
		light.Brightness = 1.5
		light.Parent = part
		local e = Instance.new("ParticleEmitter")
		e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		e.Color = ColorSequence.new(Color3.fromRGB(255, 215, 110))
		e.LightEmission = 1
		e.Size = NumberSequence.new(0.15, 0)
		e.Rate = 5
		e.Lifetime = NumberRange.new(0.5, 0.9)
		e.Speed = NumberRange.new(0.5, 1)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Parent = part
		part.Material = Enum.Material.Metal
	end
end

local function makePart(P): Part
	local def = Config.Potatoes[P.Type]
	local p = Instance.new("Part")
	p.Name = "Potato"
	-- colisão esférica: rola, quica e bate nas outras; a malha deixa o formato oval
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.one * 0.62 * def.WorldScale
	p.Material = Enum.Material.SmoothPlastic
	p.CanTouch = false
	p.CustomPhysicalProperties = PhysicalProperties.new(0.9, 0.9, 0.2, 1, 1)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, 0.9, 1.35)
	mesh.Parent = p
	p:SetAttribute("PotatoId", P.Id)
	p:SetAttribute("PotatoType", P.Type)
	P.Part = p
	paintProgress(P)
	decorate(P, p)
	return p
end

local function removeLoose(P)
	if P.Loose then
		local list = P.Kitchen.Loose
		local i = table.find(list, P)
		if i then
			table.remove(list, i)
		end
		P.Loose = false
	end
	if P.Part then
		local prompt = P.Part:FindFirstChild("PotatoPrompt")
		if prompt then
			prompt:Destroy()
		end
	end
end

function PeelService.DestroyPotato(P)
	if not P then
		return
	end
	removeLoose(P)
	if P.Part then
		P.Part:Destroy()
		P.Part = nil
	end
	potatoes[P.Id] = nil
end

local function publishHands(player: Player)
	local s = S.Session.Get(player)
	local P = s and s.Held
	player:SetAttribute("HeldId", P and P.Id or nil)
	player:SetAttribute("HeldType", P and P.Type or nil)
	player:SetAttribute("HeldStrips", P and P.Strips or nil)
	player:SetAttribute("HeldRemoved", P and P.Removed or nil)
	player:SetAttribute("HeldTotal", P and P.Total or nil)
	player:SetAttribute("HeldCut", P and cutMask(P) or nil)
	player:SetAttribute("HeldPeeled", P and P.Peeled or nil)
	player:SetAttribute("ExtraHeld", s and s.Extra and s.Extra.Type or nil)
end

local function attach(player: Player, P, handName: string): boolean
	local char = player.Character
	local hand = char and (char:FindFirstChild(handName .. "Hand") or char:FindFirstChild(handName .. " Arm")) :: BasePart?
	if not hand then
		return false
	end
	removeLoose(P)
	local part = P.Part or makePart(P)
	local old = part:FindFirstChild("HoldWeld")
	if old then
		old:Destroy()
	end
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.Massless = true
	local grip = hand:FindFirstChild(handName .. "GripAttachment") :: Attachment?
	local w = Instance.new("Weld")
	w.Name = "HoldWeld"
	w.Part0 = hand
	w.Part1 = part
	w.C0 = (if grip then grip.CFrame else CFrame.new(0, -1, 0)) * CFrame.new(0, -0.15, 0)
	w.Parent = part
	part.Parent = char
	return true
end

-- Coloca P na mão direita. state: "Holding" (padrão) ou "Peeling" (encadeando batatas).
local function hold(player: Player, P, state: string?): boolean
	local s = S.Session.Get(player)
	if not s or not attach(player, P, "Right") then
		return false
	end
	s.Held = P
	publishHands(player)
	S.Session.SetState(player, state or "Holding")
	return true
end

local function holdExtra(player: Player, P): boolean
	local s = S.Session.Get(player)
	if not s or not attach(player, P, "Left") then
		return false
	end
	s.Extra = P
	publishHands(player)
	return true
end

local function detach(P)
	if P and P.Part then
		local w = P.Part:FindFirstChild("HoldWeld")
		if w then
			w:Destroy()
		end
	end
end

local function makeLoose(P)
	local K = P.Kitchen
	local part = P.Part
	part.Parent = K.LooseFolder
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PotatoPrompt"
	prompt.ActionText = Strings.TakePotato
	prompt.ObjectText = (Config.Potatoes[P.Type].Name or "Batata")
		.. (if P.Peeled then " (descascada)" elseif P.Removed > 0 then string.format(" (%d%%)", math.floor(P.Removed / P.Total * 100)) else "")
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = Config.Interaction.PromptRange
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("Kind", "Potato")
	prompt:SetAttribute("KitchenIndex", K.Index)
	CollectionService:AddTag(prompt, "KitchenPrompt")
	prompt.Triggered:Connect(function(player)
		PeelService.PickLoose(player, P)
	end)
	prompt.Parent = part
	P.Loose = true
	table.insert(K.Loose, P)
	-- limite de batatas soltas por cozinha (seção 10)
	while #K.Loose > Config.Station.MaxLoosePotatoes do
		PeelService.DestroyPotato(K.Loose[1])
	end
end

-- Tira a próxima batata das luvas ou do carrinho de mão (nil se não houver).
local function popNext(player: Player, K)
	local s = S.Session.Get(player)
	if s.Extra then
		local P = s.Extra
		s.Extra = nil
		return P
	end
	local feeder = S.Belt.UpgradeValue(player, "Feeder") > 0
	if s.Stock > 0 or feeder then
		if s.Stock > 0 then
			S.Session.SetStock(player, s.Stock - 1)
		else
			S.Kitchen.TakeFromPile(K) -- alimentador automático: a calha puxa do monte
		end
		local data = S.Data.Get(player)
		if data then
			data.Stats.PotatoesPicked += 1
		end
		return newPotato(K, rollType(player))
	end
	return nil
end

-- Depois que a batata da mão sai (terminou ou foi descartada), a próxima assume.
local function continueWithNext(player: Player, K, wasPeeling: boolean)
	local s = S.Session.Get(player)
	s.Held = nil
	local nextP = popNext(player, K)
	if not nextP then
		publishHands(player)
		S.Session.SetState(player, "Free")
		return
	end
	local keepPeeling = wasPeeling and S.Kitchen.CanAcceptPotato(K)
	if not hold(player, nextP, if keepPeeling then "Peeling" else "Holding") then
		PeelService.DestroyPotato(nextP)
		publishHands(player)
		S.Session.SetState(player, "Free")
		return
	end
	if keepPeeling then
		s.StrokeTimes = {}
		s.LastStrokeAt = os.clock()
	elseif wasPeeling then
		S.Kitchen.Notify(player, Strings.EmptyBucket)
	end
end

-- ---------------------------------------------------------------- ações

-- Pilha: enche o carrinho de mão (se tiver) e põe batata na mão livre.
function PeelService.GivePotato(player: Player, K)
	local s = S.Session.Get(player)
	local data = S.Data.Get(player)
	if not s or not data then
		return
	end
	if s.State ~= "Free" and s.State ~= "Holding" then
		return
	end
	local stockMax = S.Session.StockMax(player)
	if s.Stock < stockMax then
		for _ = 1, stockMax - s.Stock do
			S.Kitchen.TakeFromPile(K)
		end
		S.Session.SetStock(player, stockMax)
	end
	local function fromPile()
		if s.Stock > 0 then
			S.Session.SetStock(player, s.Stock - 1)
		else
			S.Kitchen.TakeFromPile(K)
		end
		data.Stats.PotatoesPicked += 1
		return newPotato(K, rollType(player)) -- o tipo é sorteado no momento em que é pega
	end
	if s.State == "Free" then
		local P = fromPile()
		if hold(player, P) then
			S.Bus.Fire("PotatoPicked", player, P.Type)
		else
			PeelService.DestroyPotato(P)
		end
	elseif S.Session.Hands(player) >= 2 and not s.Extra then
		local P = fromPile()
		if not holdExtra(player, P) then
			PeelService.DestroyPotato(P)
		end
	end
end

function PeelService.PickLoose(player: Player, P)
	local s = S.Session.Get(player)
	if not s or not potatoes[P.Id] or not P.Loose or not S.Kitchen.CanUse(P.Kitchen, player) then
		return
	end
	if s.State == "Free" then
		hold(player, P)
	elseif s.State == "Holding" and S.Session.Hands(player) >= 2 and not s.Extra then
		holdExtra(player, P)
	end
end

local function drop(player: Player)
	local s = S.Session.Get(player)
	if not s or s.State ~= "Holding" or not s.Held then
		return
	end
	local P = s.Held
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	detach(P)
	s.Held = nil
	-- a batata da outra mão passa para a mão principal
	if s.Extra then
		local E = s.Extra
		s.Extra = nil
		hold(player, E)
	else
		publishHands(player)
		S.Session.SetState(player, "Free")
	end
	local part = P.Part
	if not part or not hrp then
		PeelService.DestroyPotato(P)
		return
	end
	makeLoose(P)
	part.CFrame = hrp.CFrame * CFrame.new(0, 0, -2)
	part.CanCollide = true
	part.CanQuery = true
	part.Massless = false
	part.Anchored = false
	part.AssemblyLinearVelocity = hrp.CFrame.LookVector * 6 + Vector3.new(0, 5, 0)
	part:SetNetworkOwner(nil)
end

local function nearTable(player: Player, K): boolean
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return hrp ~= nil
		and S.Kitchen.DistanceToTable(K, hrp.Position) <= Config.Interaction.PeelRange + Config.Interaction.ServerRangeTolerance
end

local function startPeel(player: Player)
	local s = S.Session.Get(player)
	if not s or s.State ~= "Holding" or not s.Held then
		return
	end
	local P = s.Held
	local K = S.Kitchen.GetKitchen(player)
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not K or P.Kitchen ~= K or not hrp then
		return
	end
	if P.Peeled then
		S.Kitchen.Notify(player, "Essa já está descascada: coloque na esteira")
		return
	end
	if not nearTable(player, K) then
		S.Kitchen.Notify(player, Strings.TooFar)
		return
	end
	if not S.Kitchen.CanAcceptPotato(K) then
		S.Kitchen.Notify(player, Strings.EmptyBucket)
		S.Bus.Fire("BucketFull", player)
		return
	end
	-- vira o personagem para a mesa
	local target = K.TableTop.Position
	hrp.CFrame = CFrame.lookAt(hrp.Position, Vector3.new(target.X, hrp.Position.Y, target.Z))
	s.StrokeTimes = {}
	s.LastStrokeAt = os.clock()
	S.Session.SetState(player, "Peeling")
end

-- "Parar": devolve a batata à mesa com as faixas já removidas.
local function stopPeel(player: Player)
	local s = S.Session.Get(player)
	if not s or s.State ~= "Peeling" or not s.Held then
		return
	end
	local P = s.Held
	local K = P.Kitchen
	detach(P)
	s.Held = nil
	if s.Extra then
		local E = s.Extra
		s.Extra = nil
		hold(player, E)
	else
		publishHands(player)
		S.Session.SetState(player, "Free")
	end
	local part = P.Part
	if not part then
		PeelService.DestroyPotato(P)
		return
	end
	makeLoose(P)
	local top = K.TableTop
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = true
	part.CFrame = top.CFrame
		* CFrame.new(rng:NextNumber(-1, 0.6), top.Size.Y / 2 + 0.3, rng:NextNumber(-0.7, 0.3))
		* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
end

-- Batata podre: "Descartar" joga na lixeira da mesa e paga 15 (se ainda não foi estragada).
local function discard(player: Player)
	local s = S.Session.Get(player)
	if not s or (s.State ~= "Holding" and s.State ~= "Peeling") or not s.Held then
		return
	end
	local P = s.Held
	local K = P.Kitchen
	if P.Type ~= "Podre" or not nearTable(player, K) then
		return
	end
	local wasPeeling = s.State == "Peeling"
	local amount = 0
	if not P.Spoiled then
		amount = S.Economy.Add(player, Config.Potatoes.Podre.DiscardValue, "Discard")
	end
	local trash = K.Model.Station:FindFirstChild("TrashCan")
	Remotes.Reward:FireClient(player, "Discard", { Amount = amount, Pos = trash and trash.Position })
	S.Bus.Fire("Discarded", player)
	PeelService.DestroyPotato(P)
	continueWithNext(player, K, wasPeeling)
end

-- Multiplicadores que valem para toda batata (manual e de máquina): rebirth, sala secreta,
-- e na Etapa 6 os passes.
function PeelService.GlobalMultiplier(player: Player): number
	local data = S.Data.Get(player)
	if not data then
		return 1
	end
	local m = S.Rebirth.Multiplier(data)
	if data.Rooms.HortaProibida then
		m *= 1 + Config.Golden.RoomCoinBonus
	end
	return m
end

-- M das batatas descascadas à mão = global x bônus da ferramenta.
function PeelService.PermanentMultiplier(player: Player): number
	local s = S.Session.Get(player)
	local tool = PeelMath.ToolFor(s and s.ToolId)
	return (1 + (tool.ValueBonus or 0)) * PeelService.GlobalMultiplier(player)
end

local function reply(player: Player, data)
	Remotes.PeelResult:FireClient(player, data)
end

-- Anti-bot (Etapa 8): o gesto é medido no cliente, então um script consegue mandar passadas
-- perfeitas. Humanos variam a duração; um bot costuma repetir. Só registra (analytics +
-- atributo "Suspect") para revisão — punir automaticamente daria falso positivo.
local function watchBot(player: Player, s, precision: number, duration: number)
	local cfg = Config.Peel
	s.Recent = s.Recent or {}
	local r = s.Recent
	table.insert(r, { P = precision, D = duration })
	if #r > cfg.BotWindow then
		table.remove(r, 1)
	end
	if #r < cfg.BotWindow or s.Flagged then
		return
	end
	local minD, maxD = math.huge, -math.huge
	for _, e in r do
		if e.P < 0.999 then
			return
		end
		minD, maxD = math.min(minD, e.D), math.max(maxD, e.D)
	end
	if maxD - minD <= cfg.BotDurationSpread then
		s.Flagged = true
		player:SetAttribute("Suspect", true)
		warn("[Peel] padrão de bot:", player.Name, player.UserId)
		S.Analytics.Custom(player, "SuspectBot", 1)
	end
end

-- Solta a batata da mão principal (foi para a esteira); a da outra mão assume.
function PeelService.ReleaseHeld(player: Player)
	local s = S.Session.Get(player)
	if not s or not s.Held then
		return
	end
	PeelService.DestroyPotato(s.Held)
	s.Held = nil
	if s.Extra then
		local E = s.Extra
		s.Extra = nil
		hold(player, E)
	else
		publishHands(player)
		S.Session.SetState(player, "Free")
	end
end

-- A batata terminou: vira batata descascada. Com luvas / carrinho de mão (ou a outra mão
-- ocupada) ela vai sozinha para a esteira e a próxima já entra no modo Descascar; sem eles,
-- fica na mão para o jogador levar até a esteira.
local function finishPotato(player: Player, s, P, K, combo: number, comboMult: number)
	local pdata = S.Data.Get(player)
	local cfg = Config.Peel.Free
	local def = Config.Potatoes[P.Type]
	local yield = math.clamp(1 - P.Penalty, cfg.MinYield, 1)
	if s.Assisted then
		yield = math.min(yield, Config.Peel.Assisted.MaxYield)
	end
	local baseValue = if P.Spoiled then 0 else def.BaseValue
	local value = PeelMath.PotatoValue(baseValue, yield, comboMult, PeelService.PermanentMultiplier(player))
	P.Peeled = true
	P.Item = {
		Value = value,
		Type = P.Type,
		Yield = yield,
		Producer = if K.Owner ~= player then player.UserId else nil, -- convidado: 30% na entrega
	}
	-- a casca que sobrou (menos de 10%) sai junto
	for id = 1, P.Total do
		P.Hits[id] = LAYERS
	end
	P.Removed = P.Total
	paintProgress(P)
	if pdata then
		pdata.Stats.PotatoesPeeled += 1
	end
	local reward = nil
	if P.Type == "Dourada" then
		reward = S.Rewards.GoldenFound(player)
	end
	S.Bus.Fire("PotatoFinished", player, { Type = P.Type, AvgYield = yield, Value = value, Combo = combo, Spoiled = P.Spoiled })

	local autoBelt = s.Extra ~= nil or s.Stock > 0 or S.Session.HasItem(player, "Luvas") or S.Belt.UpgradeValue(player, "Feeder") > 0
	if autoBelt and S.Belt.Push(K, P.Item) then
		local belt = K.Belt:FindFirstChild("BeltRoot")
		local dest = if belt and belt:FindFirstChild("P1") then (belt :: any).P1.WorldPosition else K.TableTop.Position
		PeelService.DestroyPotato(P)
		continueWithNext(player, K, true)
		S.Bus.Fire("BeltPlaced", player)
		return value, yield, "Belt", dest, reward
	end
	-- fica na mão, descascada
	publishHands(player)
	S.Session.SetState(player, "Holding")
	local hand = player.Character and player.Character:FindFirstChild("RightHand") :: BasePart?
	return value, yield, "Hand", (hand and hand.Position) or K.TableTop.Position, reward
end

-- Passada do descascar livre.
--   cut: ids dos pedaços em que a faca passou nesta passada (cada um perde uma camada)
--   flesh: quantos pedaços de polpa a faca raspou (onde já não tinha casca) -> perde rendimento
local function onStroke(player: Player, seq: any, cut: any, flesh: any, duration: any, auto: any)
	if typeof(seq) ~= "number" or typeof(cut) ~= "table" or typeof(flesh) ~= "number" or typeof(duration) ~= "number" then
		return
	end
	if duration ~= duration or flesh ~= flesh then
		return -- NaN
	end
	local s = S.Session.Get(player)
	local pdata = S.Data.Get(player)
	if not s or not pdata or s.State ~= "Peeling" or not s.Held or s.Held.Peeled then
		return
	end
	local P = s.Held
	local K = P.Kitchen
	local cfg = Config.Peel
	local free = cfg.Free
	local tool = PeelMath.ToolFor(s.ToolId)
	local function reject(reason: string)
		if Config.Dev.DebugPeel then
			print("[Peel] rejeitada", player.Name, reason)
		end
		reply(player, { Seq = seq, Ok = false, Reason = reason, Removed = P.Removed, Total = P.Total, Cut = cutMask(P), Combo = s.Combo })
	end

	-- ritmo: passadas por segundo
	local now = os.clock()
	local times = s.StrokeTimes
	local i = 1
	while i <= #times do
		if now - times[i] > 1 then
			table.remove(times, i)
		else
			i += 1
		end
	end
	if #times >= cfg.MaxStrokesPerSecond then
		return reject("Rate")
	end
	table.insert(times, now)
	if duration < free.MinDuration or duration > free.MaxDuration then
		return reject("Duration")
	end
	if duration > (now - s.LastStrokeAt) + 0.25 then
		return reject("Clock")
	end
	s.LastStrokeAt = now
	if not nearTable(player, K) then
		return reject("Range")
	end
	local isAuto = auto == true and S.Monetization.HasPass(player, "AutoDescascar")
	if auto == true and not isAuto then
		return reject("NoPass")
	end

	-- pedaços válidos (cada um no máximo uma vez por passada); limites anti-script
	local width = free.KnifeWidth + tool.StripsPerStroke - 1
	if #cut > width * SEG * 3 + 8 then
		return reject("TooMany")
	end
	local seen = {}
	local hits = {}
	for _, id in cut do
		if typeof(id) == "number" and id == math.floor(id) and id >= 1 and id <= P.Total and not seen[id] then
			seen[id] = true
			if (P.Hits[id] or 0) < LAYERS then
				table.insert(hits, id)
			end
		end
	end
	s.PatchWindow = s.PatchWindow or {}
	local pw = s.PatchWindow
	local j = 1
	while j <= #pw do
		if now - pw[j].T > 1 then
			table.remove(pw, j)
		else
			j += 1
		end
	end
	local recent = 0
	for _, e in pw do
		recent += e.N
	end
	if recent + #hits > free.MaxPatchesPerSecond then
		return reject("Rate")
	end
	table.insert(pw, { T = now, N = #hits })
	local removedNow = 0
	for _, id in hits do
		local h = (P.Hits[id] or 0) + 1
		P.Hits[id] = h
		if h >= LAYERS then
			removedNow += 1
		end
	end
	P.Removed += removedNow

	-- resultado: LIMPA = tirou casca sem raspar polpa; RUIM = quase só polpa
	flesh = math.clamp(math.floor(flesh), 0, 400)
	watchBot(player, s, if flesh == 0 then 1 else 0, duration)
	local result
	if isAuto then
		result = "Good"
	elseif #hits >= free.CleanMinHits and flesh == 0 then
		result = "Perfect"
	elseif #hits == 0 or flesh > #hits then
		result = "Bad"
	else
		result = "Good"
	end
	-- errar não impede de descascar: só tira rendimento
	local steady = 1 - math.min(0.8, (pdata.Talents.MaoLeve or 0) * Config.TalentsById.MaoLeve.PerLevel) -- talento Mão leve
	P.Penalty = math.min(1, P.Penalty + (flesh * free.FleshPenalty + (if result == "Bad" then free.BadPenalty else 0)) * steady)

	-- sem combo: o valor depende só do rendimento (quanto de polpa sobrou)
	local combo, comboMult, comboTier = 0, 1, 1
	local rotten = false
	if P.Type == "Podre" and not P.Spoiled then
		P.Spoiled = true
		rotten = true
	end
	S.Bus.Fire("StrokeResult", player, result)
	local yieldNow = math.clamp(1 - P.Penalty, free.MinYield, 1)
	S.Bus.Fire("StripsPeeled", player, removedNow / SEG, yieldNow) -- corrida e rankings

	local compost = 0
	if tool.CompostPerStrip and removedNow > 0 then
		compost = S.Economy.Add(player, tool.CompostPerStrip * removedNow / SEG, "Compost")
	end

	local data = {
		Seq = seq,
		Ok = true,
		Id = P.Id,
		Result = result,
		Rotten = rotten,
		Yield = yieldNow,
		Combo = combo,
		ComboMult = comboMult,
		ComboTier = comboTier,
		Hits = #hits,
		Removed = P.Removed,
		Total = P.Total,
		Compost = compost,
		Done = false,
	}
	if P.Removed >= P.Total * free.FinishFraction then
		local value, avg, dest, destPos, reward = finishPotato(player, s, P, K, combo, comboMult)
		data.Done = true
		data.Value = value
		data.AvgYield = avg
		data.Dest = dest
		data.DestPos = destPos
		data.Reward = reward
	else
		player:SetAttribute("HeldRemoved", P.Removed)
		paintProgress(P)
	end
	if Config.Dev.DebugPeel then
		print(string.format("[Peel] %s %s %s hits=%d flesh=%d combo=%d %d/%d", player.Name, P.Type, result, #hits, flesh, combo, P.Removed, P.Total))
	end
	reply(player, data)
end

-- Aspirador: puxa batatas soltas num raio de 6 studs para as mãos livres.
local function vacuumStep()
	local radius = Config.CollectionById.Aspirador.Radius
	for _, player in Players:GetPlayers() do
		if S.Session.HasItem(player, "Aspirador") then
			local s = S.Session.Get(player)
			local K = S.Kitchen.GetKitchen(player)
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if s and K and hrp and (s.State == "Free" or s.State == "Holding") then
				for _, P in table.clone(K.Loose) do
					if P.Part and (P.Part.Position - hrp.Position).Magnitude <= radius then
						PeelService.PickLoose(player, P)
						if s.State == "Holding" and (s.Extra or S.Session.Hands(player) < 2) then
							break
						end
					end
				end
			end
		end
	end
end

function PeelService.Init(services)
	S = services

	Remotes.PeelStroke.OnServerEvent:Connect(onStroke)
	Remotes.PeelAction.OnServerEvent:Connect(function(player: Player, action: any, arg: any)
		if action == "Start" then
			startPeel(player)
		elseif action == "Stop" then
			stopPeel(player)
		elseif action == "Drop" then
			drop(player)
		elseif action == "Discard" then
			discard(player)
		elseif action == "PlaceBelt" then
			-- botão "Colocar na esteira": precisa estar perto do funil
			local K = S.Kitchen.GetKitchen(player)
			local hopper = K and K.Belt:FindFirstChild("Hopper") :: BasePart?
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if hopper and hrp and (hopper.Position - hrp.Position).Magnitude <= 11 then
				S.Belt.PlaceHeld(player, K)
			end
		elseif action == "SetAssisted" and typeof(arg) == "boolean" then
			S.Session.SetAssisted(player, arg)
		end
	end)

	-- personagem nasceu/morreu ou saiu: as batatas nas mãos somem
	S.Session.Reset:Connect(function(player)
		local s = S.Session.Get(player)
		if s then
			PeelService.DestroyPotato(s.Held)
			PeelService.DestroyPotato(s.Extra)
			s.Held, s.Extra = nil, nil
			publishHands(player)
		end
	end)

	-- expiração do combo visível no HUD + aspirador
	task.spawn(function()
		while true do
			task.wait(0.25)
			local now = Workspace:GetServerTimeNow()
			for _, player in Players:GetPlayers() do
				local s = S.Session.Get(player)
				if s and s.Combo > 0 and now > s.ComboDeadline then
					S.Session.SetCombo(player, 0, 1, 0)
				end
			end
			vacuumStep()
		end
	end)
end

return PeelService
