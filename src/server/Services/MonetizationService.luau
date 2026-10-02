-- MonetizationService (seções 8 e 10). Regra fixa: o pago economiza tempo ou dá estilo;
-- nenhum conteúdo fica trancado atrás de Robux.
--   * Game Passes: posse checada ao entrar e na compra; efeitos consultados pelos outros serviços.
--   * Developer Products: ProcessReceipt idempotente (grava o PurchaseId num livro-caixa antes
--     de confirmar; se já existe, só confirma).
--   * Assinatura Clube do Chef, vídeo recompensado e regras de oferta.
-- IDs ficam no Config; ID 0 (ou "") = ainda não criado no Creator Hub: o item fica desligado.

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = ReplicatedStorage.Remotes

local MonetizationService = {}

local S
local owned: { [Player]: { [string]: boolean } } = {}
local subscribed: { [Player]: boolean } = {}
local sessionStart: { [Player]: number } = {}
local popupsShown: { [Player]: number } = {}
local ledger: DataStore? = nil
local memoryLedger: { [string]: boolean } = {}
local earnedWindow: { [Player]: { { T: number, N: number } } } = {}

-- fontes de Moedas que contam como "produção" (recebem Moedas x2, VIP, boosts, assinatura)
local PRODUCTION = { Delivery = true, HelperShare = true, Order = true, Offline = true, Compost = true, GiantOrder = true, Discard = true, Race = true }

-- ---------------------------------------------------------------- passes

function MonetizationService.HasPass(player: Player, id: string): boolean
	local set = owned[player]
	return set ~= nil and set[id] == true
end

local function publishPasses(player: Player)
	local list = {}
	for id, v in owned[player] or {} do
		if v then
			table.insert(list, id)
		end
	end
	player:SetAttribute("Passes", table.concat(list, ","))
	player:SetAttribute("VIP", MonetizationService.HasPass(player, "VIP"))
	player:SetAttribute("Subscribed", subscribed[player] == true)
end

-- Efeitos de entrega única e de estado ao ganhar um passe.
local function onPassGranted(player: Player, id: string)
	local data = S.Data.Get(player)
	if not data then
		return
	end
	if id == "KitInicial" and not data.PassGrants.KitInicial then
		data.PassGrants.KitInicial = true
		data.OwnedTools.FacaCozinha = true
		data.Items.Luvas = true
		if Config.ToolsById[data.Tool].Tier < Config.ToolsById.FacaCozinha.Tier then
			data.Tool = "FacaCozinha"
		end
		S.Economy.Add(player, 5000, "Pass:KitInicial")
	end
	S.Session.Publish(player)
	S.Session.RefreshMovement(player)
	S.Kitchen.RefreshOwner(player)
	S.Avatar.Refresh(player)
	S.Machines.Recompute(player)
	publishPasses(player)
	if S.Perks then
		S.Perks.Refresh(player)
	end
end

function MonetizationService.GrantPass(player: Player, id: string)
	owned[player] = owned[player] or {}
	if owned[player][id] then
		return
	end
	owned[player][id] = true
	onPassGranted(player, id)
end

local function checkPasses(player: Player)
	owned[player] = owned[player] or {}
	for _, p in Config.GamePasses do
		if p.PassId and p.PassId ~= 0 then
			local ok, has = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, p.PassId)
			end)
			if ok and has then
				owned[player][p.Id] = true
			end
		end
	end
	for id in owned[player] do
		onPassGranted(player, id)
	end
	publishPasses(player)
end

-- ---------------------------------------------------------------- multiplicadores

local function boostMult(player: Player): number
	local data = S.Data.Get(player)
	if data and data.Boost.Until > os.time() then
		return data.Boost.Mult
	end
	return 1
end

-- Multiplicador sobre Moedas de produção (passes, boost, assinatura).
function MonetizationService.EarnMultiplier(player: Player, source: string): number
	if not PRODUCTION[source] then
		return 1
	end
	local m = 1
	if MonetizationService.HasPass(player, "MoedasX2") then
		m *= Config.GamePassesById.MoedasX2.CoinMultiplier
	end
	if MonetizationService.HasPass(player, "VIP") then
		m *= 1 + Config.GamePassesById.VIP.CoinBonus
	end
	if subscribed[player] then
		m *= 1 + Config.Subscription.ProductionBonus
	end
	if S.Retention then
		m *= S.Retention.ServerBoost() -- Admin Abuse ao vivo
	end
	return m * boostMult(player)
end

function MonetizationService.GoldenMultiplier(player: Player): number
	return if MonetizationService.HasPass(player, "SorteDourada") then 1 + Config.GamePassesById.SorteDourada.GoldenBonus else 1
end

function MonetizationService.SpeedMultiplier(player: Player): number
	return if MonetizationService.HasPass(player, "CarrinhoTurbo") then 1 + Config.GamePassesById.CarrinhoTurbo.SpeedBonus else 1
end

function MonetizationService.CapacityMultiplier(player: Player?): number
	return if player and MonetizationService.HasPass(player, "BaldeGigante") then 1.5 else 1
end

function MonetizationService.ExtraHelpers(player: Player): number
	return if MonetizationService.HasPass(player, "MaisAjudantes") then Config.GamePassesById.MaisAjudantes.ExtraSlots else 0
end

function MonetizationService.OfflineHours(player: Player): number
	return if MonetizationService.HasPass(player, "GanhoOffline8h") then Config.Economy.OfflineHoursPass else Config.Economy.OfflineHoursFree
end

local function setBoost(player: Player, mult: number, minutes: number)
	local data = S.Data.Get(player)
	if not data then
		return
	end
	local now = os.time()
	-- boosts iguais somam tempo; um maior substitui
	if data.Boost.Until > now and data.Boost.Mult == mult then
		data.Boost.Until += minutes * 60
	else
		data.Boost = { Mult = math.max(mult, if data.Boost.Until > now then data.Boost.Mult else 1), Until = now + minutes * 60 }
	end
	player:SetAttribute("BoostMult", data.Boost.Mult)
	player:SetAttribute("BoostEnds", data.Boost.Until)
end
MonetizationService.SetBoost = setBoost

-- Produção atual por minuto (para os Sacos de Moedas): o maior entre a automática e o que o
-- jogador ganhou nos últimos 10 min. Assim o saco nunca fica obsoleto.
function MonetizationService.ProductionPerMinute(player: Player): number
	local auto = S.Machines.AutoCoinsPerMinute(player)
	local list = earnedWindow[player] or {}
	local now = os.clock()
	local sum = 0
	for _, e in list do
		if now - e.T <= 600 then
			sum += e.N
		end
	end
	return math.max(auto, sum / 10, 50)
end

function MonetizationService.NoteEarned(player: Player, n: number)
	earnedWindow[player] = earnedWindow[player] or {}
	local list = earnedWindow[player]
	table.insert(list, { T = os.clock(), N = n })
	while #list > 0 and os.clock() - list[1].T > 600 do
		table.remove(list, 1)
	end
end

-- ---------------------------------------------------------------- produtos

local GRANT = {}

local function grantProduct(player: Player, def): boolean
	local data = S.Data.Get(player)
	if not data then
		return false
	end
	if def.Minutes then
		local amount = MonetizationService.ProductionPerMinute(player) * def.Minutes
		local paid = S.Economy.Add(player, amount, "Product:" .. def.Id)
		Remotes.Reward:FireClient(player, "Product", { Title = def.Name, Text = "+" .. Format.Int(paid) .. " Moedas", Amount = paid })
	elseif def.BoostMult then
		setBoost(player, def.BoostMult, def.BoostMinutes)
		Remotes.Reward:FireClient(player, "Product", { Title = def.Name, Text = string.format("Produção x%d por %d min", def.BoostMult, def.BoostMinutes) })
	elseif def.GoldenWithin then
		data.GoldenPity = def.GoldenWithin
		Remotes.Reward:FireClient(player, "Product", { Title = def.Name, Text = "Uma batata dourada virá nas próximas " .. def.GoldenWithin })
	elseif def.GoldenNext then
		data.GoldenForced = (data.GoldenForced or 0) + def.GoldenNext
		Remotes.Reward:FireClient(player, "Product", { Title = def.Name, Text = "As próximas " .. def.GoldenNext .. " batatas serão douradas" })
	elseif def.ServerBoostMult then
		S.Retention.StartServerBoost(def.ServerBoostMult, def.ServerBoostMinutes)
		for _, p in Players:GetPlayers() do
			Remotes.Reward:FireClient(p, "Product", {
				Title = def.Name,
				Text = string.format("%s pagou um banquete: Moedas x%d para todos por %d min!", player.DisplayName, def.ServerBoostMult, def.ServerBoostMinutes),
			})
		end
	elseif def.Id == "PedidoRelampago" then
		S.Orders.ForceOffer(player)
		Remotes.Reward:FireClient(player, "Product", { Title = def.Name, Text = "Um pedido especial chegou ao quadro" })
	elseif def.Id == "PassePremium" then
		S.Retention.GrantPremium(player)
		Remotes.Reward:FireClient(player, "Product", { Title = def.Name, Text = "Trilha premium liberada nesta temporada" })
	else
		return false
	end
	S.Bus.Fire("ProductPurchased", player, def.Id)
	return true
end
GRANT.Product = grantProduct

local function productByAssetId(assetId: number)
	for _, p in Config.Products do
		if p.ProductId ~= 0 and p.ProductId == assetId then
			return p
		end
	end
	return nil
end

local function ledgerHas(purchaseId: string): boolean
	if memoryLedger[purchaseId] then
		return true
	end
	if not ledger then
		return false
	end
	local ok, v = pcall(function()
		return (ledger :: DataStore):GetAsync(purchaseId)
	end)
	return ok and v ~= nil
end

local function ledgerWrite(purchaseId: string, userId: number): boolean
	memoryLedger[purchaseId] = true
	if not ledger then
		return true
	end
	local ok = pcall(function()
		(ledger :: DataStore):SetAsync(purchaseId, { UserId = userId, Time = os.time() })
	end)
	return ok
end

-- Idempotente: se o PurchaseId já está no livro-caixa, só confirma (sem entregar de novo).
local function processReceipt(info)
	local purchaseId = tostring(info.PurchaseId)
	if ledgerHas(purchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local player = Players:GetPlayerByUserId(info.PlayerId)
	local def = productByAssetId(info.ProductId)
	if not player or not def or not S.Data.Get(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if not grantProduct(player, def) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	-- grava o save com o item e depois o livro-caixa; se falhar, o Roblox tenta de novo
	if not S.Data.SaveNow(player) or not ledgerWrite(purchaseId, info.PlayerId) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	-- só conta uma vez (depois do livro-caixa): Robux gastos por produto
	S.Analytics.Custom(player, "Robux:" .. def.Id, info.CurrencySpent or 0)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- ---------------------------------------------------------------- assinatura e anúncio

local function checkSubscription(player: Player)
	local id = Config.Subscription.Id
	if id == "" then
		return
	end
	local ok, status = pcall(function()
		return MarketplaceService:GetUserSubscriptionStatusAsync(player, id)
	end)
	subscribed[player] = ok and status and status.IsSubscribed == true
	publishPasses(player)
	-- 1 Boost x2 por dia
	local data = S.Data.Get(player)
	local today = math.floor(os.time() / 86400)
	if subscribed[player] and data and data.SubDaily ~= today then
		data.SubDaily = today
		setBoost(player, Config.Subscription.DailyBoostMult, Config.Subscription.DailyBoostMinutes)
		Remotes.Reward:FireClient(player, "Product", { Title = Config.Subscription.Name, Text = "Seu Boost x2 diário está ativo" })
	end
end

function MonetizationService.IsSubscribed(player: Player): boolean
	return subscribed[player] == true
end

-- Vídeo recompensado: concede o boost só depois do callback de conclusão.
local function watchAd(player: Player)
	local cfg = Config.RewardedVideo
	local data = S.Data.Get(player)
	if not cfg.Enabled or not data then
		return { Ok = false, Reason = "Em breve" }
	end
	local today = math.floor(os.time() / 86400)
	if data.AdsToday.Day ~= today then
		data.AdsToday = { Day = today, Count = 0 }
	end
	if data.AdsToday.Count >= cfg.MaxPerDay then
		return { Ok = false, Reason = "Limite de vídeos de hoje atingido" }
	end
	local ok, completed = pcall(function()
		local AdService = game:GetService("AdService") :: any
		return AdService:ShowRewardedVideoAdAsync(player)
	end)
	if ok and completed then
		data.AdsToday.Count += 1
		setBoost(player, cfg.BoostMult, cfg.BoostMinutes)
		return { Ok = true }
	end
	return { Ok = false, Reason = "Vídeo indisponível agora" }
end

-- ---------------------------------------------------------------- ofertas
-- Nada na primeira sessão (seção 6) nem nos primeiros 5 min (seção 8); no máximo 1 pop-up por
-- sessão; cada oferta só aparece uma vez; nasce de um momento de "dor" do jogo.
function MonetizationService.TryOffer(player: Player, trigger: string)
	local data = S.Data.Get(player)
	if not data or data.Sessions <= 1 then
		return
	end
	if os.clock() - (sessionStart[player] or os.clock()) < Config.Offers.NoOffersFirstSeconds then
		return
	end
	if (popupsShown[player] or 0) >= Config.Offers.MaxPopupsPerSession then
		return
	end
	for _, p in Config.GamePasses do
		if p.OfferAt == trigger and p.PassId ~= 0 and not MonetizationService.HasPass(player, p.Id) and not data.OfferFlags[p.Id] then
			data.OfferFlags[p.Id] = true
			popupsShown[player] = (popupsShown[player] or 0) + 1
			S.Analytics.PurchaseStep(player, 1, p.Id)
			Remotes.Offer:FireClient(player, p.Id)
			return
		end
	end
end

-- ---------------------------------------------------------------- init

function MonetizationService.Init(services)
	S = services
	if not RunService:IsStudio() or pcall(function() return DataStoreService:GetDataStore("__probe"):GetAsync("x") end) then
		local ok, store = pcall(function()
			return DataStoreService:GetDataStore("SpudShift_Purchases" .. (if RunService:IsStudio() then "_Studio" else ""))
		end)
		ledger = if ok then store else nil
	end
	MarketplaceService.ProcessReceipt = processReceipt

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end
		for _, p in Config.GamePasses do
			if p.PassId == passId then
				S.Analytics.PurchaseStep(player, 3, p.Id)
				MonetizationService.GrantPass(player, p.Id)
				Remotes.Reward:FireClient(player, "Product", { Title = p.Name, Text = "Passe ativado!" })
			end
		end
	end)
	pcall(function()
		Players.UserSubscriptionStatusChanged:Connect(function(player)
			checkSubscription(player)
		end)
	end)

	Remotes.Store.OnServerInvoke = function(player: Player, action: any, id: any)
		if action == "PromptPass" and typeof(id) == "string" then
			local p = Config.GamePassesById[id]
			if p and p.PassId ~= 0 then
				S.Analytics.PurchaseStep(player, 2, id)
				MarketplaceService:PromptGamePassPurchase(player, p.PassId)
				return { Ok = true }
			end
		elseif action == "PromptProduct" and typeof(id) == "string" then
			local p = Config.ProductsById[id]
			if p and p.ProductId ~= 0 then
				S.Analytics.PurchaseStep(player, 2, id)
				MarketplaceService:PromptProductPurchase(player, p.ProductId)
				return { Ok = true }
			end
		elseif action == "PromptSubscription" then
			if Config.Subscription.Id ~= "" then
				pcall(function()
					MarketplaceService:PromptSubscriptionPurchase(player, Config.Subscription.Id)
				end)
				return { Ok = true }
			end
		elseif action == "WatchAd" then
			return watchAd(player)
		end
		return { Ok = false, Reason = "Em breve" }
	end

	S.Bus.Connect("Loaded", function(player, data)
		data.Sessions += 1
		sessionStart[player] = os.clock()
		player:SetAttribute("BoostMult", if data.Boost.Until > os.time() then data.Boost.Mult else 1)
		player:SetAttribute("BoostEnds", data.Boost.Until)
		checkPasses(player)
		checkSubscription(player)
		-- oferta após 30 min de jogo
		task.delay(30 * 60, function()
			if player.Parent then
				MonetizationService.TryOffer(player, "Played30")
			end
		end)
	end)
	-- momentos de "dor" que geram oferta
	S.Bus.Connect("Delivered", function(player)
		MonetizationService.TryOffer(player, "FirstDelivery")
	end)
	S.Bus.Connect("BucketFull", function(player)
		MonetizationService.TryOffer(player, "BucketFull")
	end)
	S.Bus.Connect("Purchased", function(player, id)
		if id == "Ajudante" then
			MonetizationService.TryOffer(player, "FirstHelper")
		end
	end)
	S.Bus.Connect("Rebirth", function(player)
		MonetizationService.TryOffer(player, "FirstRebirth")
	end)
	S.Bus.Connect("GoldenFound", function(player)
		MonetizationService.TryOffer(player, "FirstGolden")
	end)
	S.Bus.Connect("WingBought", function(player)
		MonetizationService.TryOffer(player, "WingBought")
	end)
	S.Bus.Connect("OfflineReturn", function(player)
		MonetizationService.TryOffer(player, "OfflineReturn")
	end)

	Players.PlayerRemoving:Connect(function(player)
		owned[player] = nil
		subscribed[player] = nil
		sessionStart[player] = nil
		popupsShown[player] = nil
		earnedWindow[player] = nil
	end)
end

return MonetizationService
