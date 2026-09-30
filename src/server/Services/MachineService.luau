-- MachineService: automação (seções 2.10 e 3) = "ProductionService" da seção 10.
--
-- Grade: cada ala tem 7 colunas x 3 fileiras de células de 4 studs. A coluna 6 de cada fileira
-- é a Calha da pilha (fonte infinita de batata crua, saída para -X). O jogador coloca
-- máquinas e esteiras nas colunas 0..5. Rotação r: saída em DIRS[r]; entrada pelo lado oposto.
--
-- Fluxo (recalculado só quando o layout muda):
--   Calha (cru) -> Tambor (descascada) -> [Linha de corte x3 / Fábrica de purê x5]
--   -> Lavadora (lavada) -> Tanque -> cano -> carrinho (parte sozinho quando enche).
--   Saída de máquina que não chega a lugar nenhum despeja no balde da mesa.
--   Ajudante: independente, 4/min direto no balde.
-- Tick de 1 s: só troca números; as animações rodam no cliente (MachineAnimator).
-- Batata de máquina: rendimento fixo de 85%, sem combo.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Strings = require(Shared.Strings)
local Format = require(Shared.Format)
local Remotes = ReplicatedStorage.Remotes
local MachineModels = require(script.Parent.MachineModels)

local MachineService = {}

local S
local G = Config.Grid
local R = Config.MachineRules
local FLOOR = 0.4

-- rotação -> direção na grade (coluna = +X local, fileira = +Z local)
local DIRS = { [0] = { 1, 0 }, [1] = { 0, 1 }, [2] = { -1, 0 }, [3] = { 0, -1 } }

local kitchenState = {} -- K -> { Models = {id -> Model}, Prod = {...}, Acc = {...} }

-- ---------------------------------------------------------------- regras

function MachineService.TalentLevel(data, id: string): number
	return data.Talents[id] or 0
end

function MachineService.Discount(data): number
	return 1 - MachineService.TalentLevel(data, "MaquinasBaratas") * Config.TalentsById.MaquinasBaratas.PerLevel
end

function MachineService.BuyCost(data, typeId: string): number
	local def = Config.MachinesById[typeId]
	return math.floor(def.Cost * MachineService.Discount(data))
end

function MachineService.UpgradeCost(data, typeId: string, level: number): number?
	local def = Config.MachinesById[typeId]
	if def.NoLevels or level >= R.MaxLevel then
		return nil
	end
	return math.floor(def.Cost * R.UpgradeCostFactor * R.CostGrowth ^ (level - 1) * MachineService.Discount(data))
end

local function capacity(m): number
	local def = Config.MachinesById[m.Type]
	return (def.PerMinute or math.huge) * R.ProductionGrowth ^ ((m.Level or 1) - 1)
end

function MachineService.HelperLimit(player: Player): number
	return R.MaxHelpers + S.Monetization.ExtraHelpers(player) -- +2 com o passe Mais Ajudantes
end

local function countOf(data, typeId: string): number
	local n = data.Inventory[typeId] or 0
	for _, m in data.Machines do
		if m.Type == typeId then
			n += 1
		end
	end
	return n
end
MachineService.CountOf = countOf

local function kindOf(typeId: string): string
	return if typeId == "Source" then "Source" else Config.MachinesById[typeId].Kind
end

-- O que cada tipo aceita na entrada.
local function accepts(node, item): boolean
	if not item then
		return false
	end
	local kind = kindOf(node.Type)
	if kind == "Peeler" then
		return item.Raw
	elseif kind == "Washer" or kind == "Processor" then
		return not item.Raw
	elseif kind == "Tank" then
		return item.Washed
	end
	return false
end

-- ---------------------------------------------------------------- grafo

-- Calcula a produção a partir do layout salvo (função pura: também serve para o ganho offline).
function MachineService.Compute(data)
	local rows = data.Wings * G.RowsPerWing
	local cells = {}
	local nodes = {}
	local function key(c, r)
		return c * 1000 + r
	end
	for _, m in data.Machines do
		if m.Row < rows then
			cells[key(m.Col, m.Row)] = m
			if m.Type ~= "Esteira" then
				nodes[m.Id] = { M = m, Type = m.Type, Col = m.Col, Row = m.Row, Rot = m.Rot, Ups = {} }
			end
		end
	end
	for r = 0, rows - 1 do
		local id = "src" .. r
		nodes[id] = { Type = "Source", Col = G.SourceCol, Row = r, Rot = 2, Ups = {}, IsSource = true }
	end

	-- segue a saída de cada produtor pelas esteiras até a próxima máquina
	local function follow(n)
		local travel = n.Rot
		local d = DIRS[travel]
		local c, r = n.Col + d[1], n.Row + d[2]
		local path = {}
		local seen = {}
		for _ = 1, 200 do
			if c < 0 or c >= G.SourceCol or r < 0 or r >= rows then
				return nil, path
			end
			local k = key(c, r)
			if seen[k] then
				return nil, path -- laço de esteiras
			end
			seen[k] = true
			local o = cells[k]
			if not o then
				return nil, path
			end
			if o.Type == "Esteira" then
				if (o.Rot + 2) % 4 == travel then
					return nil, path -- entrou pela frente da esteira
				end
				table.insert(path, o)
				travel = o.Rot
				d = DIRS[travel]
				c, r = c + d[1], r + d[2]
			else
				local kind = kindOf(o.Type)
				if kind == "Tank" then
					return nodes[o.Id], path -- tanque aceita de qualquer lado
				elseif kind == "Helper" then
					return nil, path
				elseif o.Rot == travel then
					return nodes[o.Id], path -- entra por trás da máquina
				end
				return nil, path
			end
		end
		return nil, path
	end

	for _, n in nodes do
		local kind = kindOf(n.Type)
		if kind ~= "Tank" and kind ~= "Helper" then
			n.Down, n.Path = follow(n)
			if n.Down then
				table.insert(n.Down.Ups, n)
			end
		end
	end

	-- ritmo de saída (por minuto) e o tipo de item, com memo e proteção contra ciclos
	local function resolve(n)
		if n.Done then
			return n.Out, n.Item
		end
		if n.Visiting then
			return 0, nil
		end
		n.Visiting = true
		local kind = kindOf(n.Type)
		if kind == "Source" then
			n.Out, n.Item = math.huge, { Raw = true, Washed = false, Mult = 1 }
		elseif kind == "Helper" then
			n.Out, n.Item = capacity(n.M), { Raw = false, Washed = false, Mult = 1 }
			n.Status = "ToBucket"
		else
			local inRate, washed, multSum = 0, true, 0
			for _, u in n.Ups do
				local rate, item = resolve(u)
				if rate > 0 and accepts(n, item) then
					inRate += rate
					washed = washed and item.Washed
					if rate < math.huge then
						multSum += item.Mult * rate
					end
				elseif rate > 0 and u.Down == n then
					u.Rejected = true
				end
			end
			local mult = if inRate > 0 and inRate < math.huge then multSum / inRate else 1
			n.In = inRate
			if inRate <= 0 then
				n.Out, n.Item = 0, nil
			elseif kind == "Tank" then
				n.Out, n.Item = inRate, { Raw = false, Washed = true, Mult = mult }
			else
				local def = Config.MachinesById[n.Type]
				local out = math.min(inRate, capacity(n.M))
				if kind == "Peeler" then
					n.Item = { Raw = false, Washed = false, Mult = 1 }
				elseif kind == "Washer" then
					n.Item = { Raw = false, Washed = true, Mult = mult }
				else -- Processor: fritas x3 / purê x5 (não acumulam: vale o maior)
					n.Item = { Raw = false, Washed = washed, Mult = math.max(mult, def.ValueMultiplier or 1) }
				end
				n.Out = out
			end
		end
		n.Visiting = false
		n.Done = true
		return n.Out, n.Item
	end
	for _, n in nodes do
		resolve(n)
	end

	-- destinos, estados e fluxo nas esteiras
	local result = { Bucket = {}, TankRate = 0, TankMult = 1, TankCapacity = 0, Nodes = nodes, Flow = {} }
	local tankMultSum = 0
	for _, n in nodes do
		local kind = kindOf(n.Type)
		if kind == "Tank" then
			result.TankCapacity += Config.MachinesById.Tanque.Capacity
			if n.Out > 0 then
				result.TankRate += n.Out
				tankMultSum += n.Out * n.Item.Mult
				n.Status = "Ok"
			else
				n.Status = "Idle"
			end
		elseif kind == "Helper" then
			table.insert(result.Bucket, { Rate = n.Out, Mult = 1 })
		elseif kind ~= "Source" then
			if n.Out <= 0 then
				n.Status = "NoInput"
			elseif n.Down and n.Rejected then
				n.Status = if kindOf(n.Down.Type) == "Tank" then "NeedsWash" else "Blocked"
				n.Out = 0
			elseif n.Down then
				n.Status = if kindOf(n.Down.Type) == "Tank" then "ToTank" else "Ok"
			else
				n.Status = "ToBucket"
				table.insert(result.Bucket, { Rate = n.Out, Mult = n.Item.Mult })
			end
		end
		-- fluxo visível nas esteiras do caminho
		if n.Path then
			local flow = n.Out
			if n.IsSource then
				flow = if n.Down and n.Down.In and n.Down.In > 0 then math.min(capacity(n.Down.M), 60) else 0
			end
			if flow == math.huge then
				flow = 0
			end
			for _, belt in n.Path do
				result.Flow[belt.Id] = (result.Flow[belt.Id] or 0) + flow
			end
		end
	end
	if result.TankRate > 0 then
		result.TankMult = tankMultSum / result.TankRate
	end
	return result
end

-- Valor de uma batata de máquina: base x 85% x multiplicador do produto x M (permanente).
function MachineService.ItemValue(player: Player, mult: number): number
	return R.BaseValue * R.MaxYield * mult * S.Peel.GlobalMultiplier(player)
end

-- Moedas/min que chegam sozinhas ao Rei (tanque -> carrinho), limitadas pelo carrinho.
function MachineService.AutoCoinsPerMinute(player: Player): number
	local data = S.Data.Get(player)
	if not data then
		return 0
	end
	local prod = MachineService.Compute(data)
	local d = Config.Delivery
	local cartMax = Config.Station.CartCapacity / (d.CartTravelTime + d.CartReturnTime) * 60
	-- descascador automático da esteira + (legado) grade de máquinas
	local belt = if S.Belt then S.Belt.AutoCoinsPerMinute(player) else 0
	return belt + math.min(prod.TankRate, cartMax) * MachineService.ItemValue(player, prod.TankMult)
end

-- ---------------------------------------------------------------- instâncias

local function cellCFrame(K, col: number, row: number, rot: number): CFrame
	return K.Model:GetPivot()
		* CFrame.new(-12 + G.Cell * col, FLOOR, 16 + G.Cell * row)
		* CFrame.Angles(0, -rot * math.pi / 2, 0)
end
MachineService.CellCFrame = cellCFrame

local function stateOf(K)
	local st = kitchenState[K]
	if not st then
		st = { Models = {}, Prod = nil, Acc = { Bucket = {}, Tank = 0 } }
		kitchenState[K] = st
	end
	return st
end

local function spawnModel(K, m)
	local st = stateOf(K)
	local old = st.Models[m.Id]
	if old then
		old:Destroy()
	end
	local model = MachineModels.Build(m.Type, m.Level or 1)
	model.Name = m.Type .. "_" .. m.Id
	model:SetAttribute("MachineId", m.Id)
	model:SetAttribute("Type", m.Type)
	model:SetAttribute("Level", m.Level or 1)
	model:SetAttribute("Rot", m.Rot)
	model:SetAttribute("Col", m.Col)
	model:SetAttribute("Row", m.Row)
	model:PivotTo(cellCFrame(K, m.Col, m.Row, m.Rot))
	model.Parent = K.Model:FindFirstChild("Machines")
	st.Models[m.Id] = model
	-- cano do tanque até o carrinho (o cliente esconde quando o carrinho viaja)
	if m.Type == "Tanque" then
		local out = model:FindFirstChild("PipeOut", true) :: Attachment?
		local root = K.Cart.Root :: BasePart
		local target = root:FindFirstChild("PipeIn") :: Attachment?
		if not target then
			target = Instance.new("Attachment")
			target.Name = "PipeIn"
			target.Position = Vector3.new(0, 1.8, 1.6)
			target.Parent = root
		end
		if out then
			local beam = Instance.new("Beam")
			beam.Name = "Pipe"
			beam.Attachment0 = out
			beam.Attachment1 = target
			beam.Width0 = 0.5
			beam.Width1 = 0.5
			beam.FaceCamera = true
			beam.Color = ColorSequence.new(Color3.fromRGB(70, 60, 52))
			beam.Transparency = NumberSequence.new(0)
			beam.LightInfluence = 1
			beam.CurveSize0 = 6
			beam.CurveSize1 = -2
			beam.Segments = 16
			beam.Parent = model
		end
	end
	return model
end

function MachineService.ClearKitchen(K)
	local st = kitchenState[K]
	if st then
		for _, model in st.Models do
			model:Destroy()
		end
	end
	kitchenState[K] = nil
	local folder = K.Model:FindFirstChild("Machines")
	if folder then
		folder:ClearAllChildren()
	end
end

local STATUS_TEXT = Strings.Status

-- Recalcula o fluxo e atualiza placas/atributos das máquinas.
function MachineService.Recompute(player: Player)
	local K = S.Kitchen.GetOwnedKitchen(player)
	local data = S.Data.Get(player)
	if not K or not data then
		return
	end
	local st = stateOf(K)
	local prod = MachineService.Compute(data)
	st.Prod = prod
	st.Acc.Bucket = {}
	for _, m in data.Machines do
		local model = st.Models[m.Id]
		if model then
			local def = Config.MachinesById[m.Type]
			if m.Type == "Esteira" then
				model:SetAttribute("Flow", prod.Flow[m.Id] or 0)
			else
				local n = prod.Nodes[m.Id]
				local rate = if n and n.Out and n.Out < math.huge then n.Out else 0
				local status = (n and n.Status) or "Idle"
				model:SetAttribute("Rate", rate)
				model:SetAttribute("Status", status)
				local label = model:FindFirstChild("Label", true) :: TextLabel?
				if label then
					local lvl = if def.NoLevels then "" else " " .. string.format(Strings.Level, m.Level or 1)
					local line2 = if rate > 0 then string.format(Strings.PerMin, Format.Dec(rate, 1)) .. " · " .. STATUS_TEXT[status] else STATUS_TEXT[status]
					label.Text = def.Name .. lvl .. "\n" .. line2
					label.TextColor3 = if status == "Ok" or status == "ToTank" or status == "ToBucket"
						then Color3.fromRGB(228, 214, 186)
						else Color3.fromRGB(200, 90, 70)
				end
			end
		end
	end
	player:SetAttribute("AutoPerMin", prod.TankRate)
	player:SetAttribute("TankCapacity", prod.TankCapacity)
end

function MachineService.RebuildAll(player: Player)
	local K = S.Kitchen.GetOwnedKitchen(player)
	local data = S.Data.Get(player)
	if not K or not data then
		return
	end
	MachineService.ClearKitchen(K)
	for _, m in data.Machines do
		spawnModel(K, m)
	end
	MachineService.Recompute(player)
end

-- ---------------------------------------------------------------- ações do jogador

local function publishInventory(player: Player)
	local data = S.Data.Get(player)
	local parts = {}
	for id, n in data.Inventory do
		if n > 0 then
			table.insert(parts, id .. ":" .. n)
		end
	end
	player:SetAttribute("Inventory", table.concat(parts, ","))
	player:SetAttribute("Wings", data.Wings)
	local tankCount = data.Tank.Count
	player:SetAttribute("TankCount", tankCount)
end
MachineService.PublishInventory = publishInventory

local function findMachine(data, id: any)
	for i, m in data.Machines do
		if m.Id == id then
			return m, i
		end
	end
	return nil, nil
end

local function cellFree(data, col: number, row: number, ignoreId: string?): boolean
	for _, m in data.Machines do
		if m.Col == col and m.Row == row and m.Id ~= ignoreId then
			return false
		end
	end
	return true
end

local function validCell(data, col: any, row: any): boolean
	return typeof(col) == "number" and typeof(row) == "number" and col == math.floor(col) and row == math.floor(row)
		and col >= 0 and col < G.SourceCol and row >= 0 and row < data.Wings * G.RowsPerWing
end

local function place(player: Player, typeId: any, col: any, row: any, rot: any)
	local data = S.Data.Get(player)
	local K = S.Kitchen.GetOwnedKitchen(player)
	if not data or not K or typeof(typeId) ~= "string" or not Config.MachinesById[typeId] then
		return { Ok = false }
	end
	if (data.Inventory[typeId] or 0) <= 0 then
		return { Ok = false, Reason = Strings.BuildEmpty }
	end
	if typeof(rot) ~= "number" then
		rot = 0
	end
	rot = math.floor(rot) % 4
	if not validCell(data, col, row) or not cellFree(data, col, row) then
		return { Ok = false, Reason = Strings.CantPlace }
	end
	data.Inventory[typeId] -= 1
	local m = { Id = tostring(data.NextMachineId), Type = typeId, Col = col, Row = row, Rot = rot, Level = 1 }
	data.NextMachineId += 1
	table.insert(data.Machines, m)
	spawnModel(K, m)
	MachineService.Recompute(player)
	publishInventory(player)
	return { Ok = true, Id = m.Id }
end

local function rotate(player: Player, id: any)
	local data = S.Data.Get(player)
	local K = S.Kitchen.GetOwnedKitchen(player)
	local m = data and findMachine(data, id)
	if not m or not K then
		return { Ok = false }
	end
	m.Rot = (m.Rot + 1) % 4
	spawnModel(K, m)
	MachineService.Recompute(player)
	return { Ok = true }
end

local function pickUp(player: Player, id: any)
	local data = S.Data.Get(player)
	local K = S.Kitchen.GetOwnedKitchen(player)
	local m, i = nil, nil
	if data then
		m, i = findMachine(data, id)
	end
	if not m or not K then
		return { Ok = false }
	end
	table.remove(data.Machines, i)
	-- volta para a mochila com o nível perdido (simplificação: níveis ficam na máquina colocada)
	data.Inventory[m.Type] = (data.Inventory[m.Type] or 0) + 1
	local st = stateOf(K)
	if st.Models[m.Id] then
		st.Models[m.Id]:Destroy()
		st.Models[m.Id] = nil
	end
	MachineService.Recompute(player)
	publishInventory(player)
	return { Ok = true, Refund = (m.Level or 1) > 1 }
end

local function move(player: Player, id: any, col: any, row: any)
	local data = S.Data.Get(player)
	local K = S.Kitchen.GetOwnedKitchen(player)
	local m = data and findMachine(data, id)
	if not m or not K or not validCell(data, col, row) or not cellFree(data, col, row, m.Id) then
		return { Ok = false, Reason = Strings.CantPlace }
	end
	m.Col, m.Row = col, row
	spawnModel(K, m)
	MachineService.Recompute(player)
	return { Ok = true }
end

local function upgrade(player: Player, id: any)
	local data = S.Data.Get(player)
	local K = S.Kitchen.GetOwnedKitchen(player)
	local m = data and findMachine(data, id)
	if not m or not K then
		return { Ok = false }
	end
	local cost = MachineService.UpgradeCost(data, m.Type, m.Level or 1)
	if not cost then
		return { Ok = false, Reason = Strings.MaxLevel }
	end
	if not S.Economy.Spend(player, cost, "Upgrade:" .. m.Type) then
		return { Ok = false, Reason = Strings.NotEnough }
	end
	m.Level = (m.Level or 1) + 1
	spawnModel(K, m)
	MachineService.Recompute(player)
	return { Ok = true, Level = m.Level }
end

function MachineService.BuyWing(player: Player)
	local data = S.Data.Get(player)
	local K = S.Kitchen.GetOwnedKitchen(player)
	if not data or not K or data.Wings >= G.Wings then
		return { Ok = false }
	end
	local w = data.Wings + 1
	if not S.Economy.Spend(player, G.WingCosts[w], "Wing" .. w) then
		S.Kitchen.Notify(player, Strings.NotEnough)
		return { Ok = false, Reason = Strings.NotEnough }
	end
	data.Wings = w
	S.Kitchen.ApplyWings(K, w)
	publishInventory(player)
	MachineService.Recompute(player)
	S.Kitchen.Notify(player, string.format(Strings.WingBought, w))
	S.Bus.Fire("WingBought", player, w)
	return { Ok = true }
end

-- Compra de máquina (pela Loja): vai para a mochila.
function MachineService.Buy(player: Player, typeId: string, qty: number)
	local data = S.Data.Get(player)
	local def = Config.MachinesById[typeId]
	if not data or not def then
		return { Ok = false }
	end
	qty = math.clamp(math.floor(qty), 1, 20)
	if def.Kind == "Helper" and countOf(data, typeId) + qty > MachineService.HelperLimit(player) then
		return { Ok = false, Reason = Strings.HelperLimit }
	end
	local cost = MachineService.BuyCost(data, typeId) * qty
	if not S.Economy.Spend(player, cost, "Machine:" .. typeId) then
		return { Ok = false, Reason = Strings.NotEnough }
	end
	data.Inventory[typeId] = (data.Inventory[typeId] or 0) + qty
	publishInventory(player)
	S.Bus.Fire("Purchased", player, typeId)
	return { Ok = true }
end

-- ---------------------------------------------------------------- tick de 1 s

local function tickKitchen(player: Player, dt: number)
	local K = S.Kitchen.GetOwnedKitchen(player)
	local data = S.Data.Get(player)
	if not K or not data then
		return
	end
	local st = stateOf(K)
	local prod = st.Prod
	if not prod then
		return
	end
	-- saídas que despejam no balde da mesa (ajudantes e máquinas sem tanque)
	for i, stream in prod.Bucket do
		local acc = (st.Acc.Bucket[i] or 0) + stream.Rate / 60 * dt
		local n = math.floor(acc)
		if n > 0 then
			local ok = S.Kitchen.AddMachinePotatoes(K, n, MachineService.ItemValue(player, stream.Mult))
			acc -= ok
			if ok < n then
				acc = math.min(acc, 1) -- balde cheio: a produção espera
			end
		end
		st.Acc.Bucket[i] = acc
	end
	-- tanque
	local tank = data.Tank
	if prod.TankRate > 0 then
		st.Acc.Tank += prod.TankRate / 60 * dt
		local n = math.floor(st.Acc.Tank)
		local space = prod.TankCapacity - tank.Count
		local k = math.min(n, space)
		if k > 0 then
			tank.Count += k
			tank.Value += k * MachineService.ItemValue(player, prod.TankMult)
		end
		st.Acc.Tank -= n
		if k < n then
			st.Acc.Tank = math.min(st.Acc.Tank, 1)
		end
	end
	-- tanque -> carrinho pelo cano
	if tank.Count > 0 then
		local each = tank.Value / tank.Count
		local moved = S.Kitchen.LoadCart(K, tank.Count, each)
		if moved > 0 then
			tank.Count -= moved
			tank.Value = math.max(0, tank.Value - moved * each)
		end
	end
	if tank.Count ~= player:GetAttribute("TankCount") then
		player:SetAttribute("TankCount", tank.Count)
		-- visor de nível dos tanques
		local fill = if prod.TankCapacity > 0 then tank.Count / prod.TankCapacity else 0
		for _, m in data.Machines do
			if m.Type == "Tanque" and st.Models[m.Id] then
				local level = st.Models[m.Id]:FindFirstChild("Level") :: BasePart?
				local window = st.Models[m.Id]:FindFirstChild("Window") :: BasePart?
				if level and window then
					local h = math.max(0.05, window.Size.Y * fill)
					level.Size = Vector3.new(level.Size.X, h, level.Size.Z)
					level.CFrame = window.CFrame * CFrame.new(0, -window.Size.Y / 2 + h / 2, 0.05)
				end
			end
		end
	end
end

-- ---------------------------------------------------------------- ganho offline

local function grantOffline(player: Player, data)
	if data.LastSeen <= 0 then
		return
	end
	local elapsed = os.time() - data.LastSeen
	local capHours = S.Monetization.OfflineHours(player) -- 2 h grátis, 8 h com o passe
	elapsed = math.clamp(elapsed, 0, capHours * 3600)
	if elapsed < 60 then
		return
	end
	local perMin = MachineService.AutoCoinsPerMinute(player)
	local amount = perMin * (elapsed / 60) * Config.Economy.OfflineRate
	if amount >= 1 then
		local paid = S.Economy.Add(player, amount, "Offline")
		local minutes = math.floor(elapsed / 60)
		local text = if minutes >= 60 then string.format("%dh%02d", minutes // 60, minutes % 60) else string.format("%d min", minutes)
		task.delay(3, function()
			Remotes.Reward:FireClient(player, "Offline", { Amount = paid, Time = text })
			S.Bus.Fire("OfflineReturn", player)
		end)
	end
end

-- ---------------------------------------------------------------- init

function MachineService.Init(services)
	S = services
	Remotes.BuildRequest.OnServerInvoke = function(player: Player, action: any, a: any, b: any, c: any, d: any)
		local st = S.Session.GetState(player)
		if st == "Loading" or st == nil then
			return { Ok = false }
		end
		if action == "Place" then
			return place(player, a, b, c, d)
		elseif action == "Rotate" then
			return rotate(player, a)
		elseif action == "PickUp" then
			return pickUp(player, a)
		elseif action == "Move" then
			return move(player, a, b, c)
		elseif action == "Upgrade" then
			return upgrade(player, a)
		elseif action == "BuyWing" then
			return MachineService.BuyWing(player)
		elseif action == "SetTheme" and typeof(a) == "string" then
			return S.Rebirth.SetTheme(player, a)
		elseif action == "Rebirth" then
			return S.Rebirth.DoRebirth(player)
		elseif action == "BuyTalent" and typeof(a) == "string" then
			return S.Rebirth.BuyTalent(player, a)
		end
		return { Ok = false }
	end

	S.Bus.Connect("Loaded", function(player, data)
		publishInventory(player)
		MachineService.RebuildAll(player)
		grantOffline(player, data)
	end)

	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(R.TickInterval)
			local now = os.clock()
			local dt = math.min(now - last, 5)
			last = now
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(tickKitchen, player, dt)
				if not ok then
					warn("[MachineService] tick:", err)
				end
			end
		end
	end)
end

return MachineService
