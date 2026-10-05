-- OrderService: Pedidos do Rei (seção 2.8).
--   * Um pedido novo aparece no quadro da cozinha a cada 3 min; aceitar é opcional.
--   * No máximo 1 pedido ativo por jogador.
--   * Cumprido o pedido, as batatas daquele pedido pagam o dobro (bônus = soma dos valores).
--   * Falhar não tira nada: o pedido some e o próximo chega em 3 min.
-- Estado publicado em atributos: OrderState (None/Offer/Active), OrderText, OrderProgress,
-- OrderTarget, OrderDeadline (horário do servidor).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Strings = require(ReplicatedStorage.Shared.Strings)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = ReplicatedStorage.Remotes

local OrderService = {}

local S
local states: { [Player]: any } = {}
local rng = Random.new()

local function timeText(sec: number): string
	if sec % 60 == 0 then
		return string.format("%d min", sec // 60)
	end
	return string.format("%d:%02d", sec // 60, sec % 60)
end

function OrderService.Describe(def): string
	if def.Kind == "Count" then
		return string.format(Strings.OrderCount, def.Count, timeText(def.Time))
	elseif def.Kind == "CountType" then
		local pdef = Config.Potatoes[def.Type]
		return string.format(Strings.OrderCountType, def.Count, (pdef and pdef.Plural) or def.Type, timeText(def.Time))
	elseif def.Kind == "CountYield" then
		return string.format(Strings.OrderCountYield, def.Count, timeText(def.Time))
	end
	return string.format(Strings.OrderCombo, def.Count)
end

local function publish(player: Player)
	local st = states[player]
	if not st then
		return
	end
	local state = if st.Active then "Active" elseif st.Offer then "Offer" else "None"
	local def = (st.Active and st.Active.Def) or st.Offer
	player:SetAttribute("OrderState", state)
	player:SetAttribute("OrderText", def and OrderService.Describe(def) or nil)
	player:SetAttribute("OrderProgress", st.Active and st.Active.Progress or 0)
	player:SetAttribute("OrderTarget", def and def.Count or 0)
	player:SetAttribute("OrderDeadline", st.Active and st.Active.Deadline or 0)
	-- quadro de cortica da cozinha
	local K = S.Kitchen.GetOwnedKitchen(player)
	if K and K.BoardText then
		if state == "Active" then
			K.BoardText.Text = string.format(Strings.OrderBoardActive, OrderService.Describe(def), st.Active.Progress, def.Count)
		elseif state == "Offer" then
			K.BoardText.Text = string.format(Strings.OrderBoardOffer, OrderService.Describe(def))
		else
			K.BoardText.Text = Strings.OrderBoardIdle
		end
	end
end

local function newOffer(player: Player)
	local st = states[player]
	-- cada rebirth muda o cardápio do Rei
	local pool = table.clone(Config.Orders.Pool)
	local data = S.Data.Get(player)
	local rebirths = data and data.Rebirths or 0
	for _, def in Config.Orders.RebirthPool do
		if rebirths >= def.MinRebirths then
			table.insert(pool, def)
		end
	end
	local def = pool[rng:NextInteger(1, #pool)]
	-- evita repetir o mesmo pedido em seguida
	if st.LastId == def.Id and #pool > 1 then
		def = pool[(table.find(pool, def) :: number) % #pool + 1]
	end
	st.LastId = def.Id
	st.Offer = def
	st.OfferExpires = os.clock() + Config.Orders.Interval
	publish(player)
	S.Kitchen.Notify(player, Strings.OrderNew)
end

local function finish(player: Player, success: boolean)
	local st = states[player]
	local a = st.Active
	st.Active = nil
	st.NextOfferAt = os.clock() + Config.Orders.Interval
	if success then
		local bonus = a.Value * (Config.Orders.RewardMultiplier - 1)
		local paid = S.Economy.Add(player, math.max(1, bonus), "Order")
		local data = S.Data.Get(player)
		if data then
			data.Stats.OrdersCompleted += 1
		end
		S.Bus.Fire("OrderDone", player)
		Remotes.Reward:FireClient(player, "Order", { Amount = paid, Text = OrderService.Describe(a.Def) })
	else
		Remotes.Reward:FireClient(player, "OrderFailed", { Text = OrderService.Describe(a.Def) })
	end
	publish(player)
end

function OrderService.Accept(player: Player)
	local st = states[player]
	if not st or not st.Offer or st.Active then
		return
	end
	local def = st.Offer
	st.Offer = nil
	st.Active = {
		Def = def,
		Progress = 0,
		Value = 0,
		Deadline = Workspace:GetServerTimeNow() + (def.Time or Config.Orders.Interval),
	}
	publish(player)
end

-- Pedido Relâmpago (produto): um pedido novo agora, mesmo fora do ciclo de 3 min.
function OrderService.ForceOffer(player: Player)
	local st = states[player]
	if st and not st.Active then
		st.Enabled = true
		newOffer(player)
	end
end

-- Libera os pedidos (chamado quando o tutorial termina ou ao entrar com tutorial feito).
function OrderService.StartFor(player: Player, delay: number?)
	local st = states[player]
	if st and not st.Enabled then
		st.Enabled = true
		st.NextOfferAt = os.clock() + (delay or 0)
	end
end

local function onPotatoFinished(player: Player, info)
	local st = states[player]
	local a = st and st.Active
	if not a then
		return
	end
	local def = a.Def
	local counts = false
	if def.Kind == "Count" then
		counts = not info.Spoiled
	elseif def.Kind == "CountType" then
		counts = info.Type == def.Type
	elseif def.Kind == "CountYield" then
		counts = info.AvgYield >= (def.Yield or 1) - 1e-6
	elseif def.Kind == "Combo" then
		a.Value += info.Value -- todas as batatas feitas durante o pedido
	end
	if counts then
		a.Progress += 1
		a.Value += info.Value
	end
	if a.Progress >= def.Count then
		finish(player, true)
	else
		publish(player)
	end
end

local function onCombo(player: Player, combo: number)
	local st = states[player]
	local a = st and st.Active
	if a and a.Def.Kind == "Combo" and combo > a.Progress then
		a.Progress = combo
		if a.Progress >= a.Def.Count then
			finish(player, true)
		else
			publish(player)
		end
	end
end

function OrderService.Init(services)
	S = services
	S.Bus.Connect("Loaded", function(player, data)
		states[player] = { Enabled = false, NextOfferAt = math.huge }
		publish(player)
		if data.Tutorial.Step >= 100 then
			OrderService.StartFor(player, 20)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
	S.Bus.Connect("PotatoFinished", onPotatoFinished)
	-- batatas das máquinas (descascador automático, tambor) também contam no pedido
	S.Bus.Connect("MachinePotato", function(player, item)
		onPotatoFinished(player, { Type = item.Type, AvgYield = Config.MachineRules.MaxYield, Value = item.Value, Spoiled = false })
	end)
	Remotes.OrderAction.OnServerEvent:Connect(function(player, action)
		if action == "Accept" then
			OrderService.Accept(player)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.clock()
			local serverNow = Workspace:GetServerTimeNow()
			for player, st in states do
				if st.Active then
					if serverNow > st.Active.Deadline then
						finish(player, false)
					end
				elseif st.Enabled then
					if st.Offer and now > st.OfferExpires then
						newOffer(player) -- a cada 3 min chega um pedido novo
					elseif not st.Offer and now >= st.NextOfferAt then
						newOffer(player)
					end
				end
			end
		end
	end)
end

return OrderService
