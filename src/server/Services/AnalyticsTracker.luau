-- AnalyticsTracker (seção 10, Etapa 8): eventos do painel de Analytics do Roblox.
--   * Funil de entrada (onboarding): do primeiro login ao fim do tutorial e às primeiras metas.
--   * Funil de compra: oferta mostrada -> janela de compra aberta -> compra concluída.
--   * Eventos personalizados: rebirth, ala, pedido, dourada, bot suspeito, etc.
-- A economia (fontes e gastos de Moedas) já é registrada pelo EconomyService.
-- Tudo em pcall: analytics nunca pode quebrar o jogo.

local AnalyticsService = game:GetService("AnalyticsService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local AnalyticsTracker = {}

local S
local onboardingDone: { [Player]: { [number]: boolean } } = {}
local purchaseSession: { [Player]: string } = {}

-- Passos do funil de entrada (números fixos: o painel agrupa por eles).
local ONBOARDING = {
	{ Step = 1, Name = "Entrou no jogo" },
	{ Step = 2, Name = "Pegou a 1a batata" },
	{ Step = 3, Name = "Descascou a 1a batata" },
	{ Step = 4, Name = "Descascou 5 batatas" },
	{ Step = 5, Name = "Despejou o balde" },
	{ Step = 6, Name = "Entregou ao Rei" },
	{ Step = 7, Name = "Comprou a faca" },
	{ Step = 8, Name = "Terminou o tutorial" },
	{ Step = 9, Name = "Cumpriu o 1o pedido" },
	{ Step = 10, Name = "Liberou a 1a ala" },
	{ Step = 11, Name = "Primeiro rebirth" },
}
-- passo do tutorial (TutorialService) -> passo do funil
local FROM_TUTORIAL = { [2] = 2, [3] = 3, [4] = 4, [5] = 5, [6] = 6, [7] = 7, [100] = 8 }

local function onboarding(player: Player, step: number)
	local done = onboardingDone[player]
	if not done then
		done = {}
		onboardingDone[player] = done
	end
	if done[step] then
		return
	end
	done[step] = true
	local def = ONBOARDING[step]
	pcall(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, step, def and def.Name or tostring(step))
	end)
end
AnalyticsTracker.Onboarding = onboarding

function AnalyticsTracker.Custom(player: Player, name: string, value: number?)
	pcall(function()
		AnalyticsService:LogCustomEvent(player, name, value or 1)
	end)
end

-- Funil de compra: 1 oferta mostrada, 2 janela aberta, 3 comprado. Cada oferta abre uma sessão.
function AnalyticsTracker.PurchaseStep(player: Player, step: number, itemId: string)
	if step == 1 or not purchaseSession[player] then
		purchaseSession[player] = HttpService:GenerateGUID(false)
	end
	local names = { "Oferta mostrada", "Janela de compra", "Comprado" }
	pcall(function()
		AnalyticsService:LogFunnelStepEvent(player, "Compras", purchaseSession[player], step, names[step] .. ": " .. itemId)
	end)
	if step == 3 then
		purchaseSession[player] = nil
	end
end

function AnalyticsTracker.Init(services)
	S = services
	local B = S.Bus
	B.Connect("Loaded", function(player, data)
		-- quem já passou do tutorial não repete o funil
		if data.Tutorial.Step >= 100 then
			onboardingDone[player] = { [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [7] = true, [8] = true }
		else
			onboarding(player, 1)
		end
		AnalyticsTracker.Custom(player, "Sessao", data.Sessions)
	end)
	B.Connect("TutorialStep", function(player, step)
		local f = FROM_TUTORIAL[step]
		if f then
			onboarding(player, f)
		end
	end)
	B.Connect("OrderDone", function(player)
		onboarding(player, 9)
		AnalyticsTracker.Custom(player, "PedidoCumprido")
	end)
	B.Connect("WingBought", function(player, w)
		if w == 1 then
			onboarding(player, 10)
		end
		AnalyticsTracker.Custom(player, "AlaLiberada", w)
	end)
	B.Connect("Rebirth", function(player)
		onboarding(player, 11)
		AnalyticsTracker.Custom(player, "Rebirth")
	end)
	B.Connect("GoldenFound", function(player)
		AnalyticsTracker.Custom(player, "BatataDourada")
	end)
	B.Connect("RaceFinished", function(player)
		AnalyticsTracker.Custom(player, "CorridaTerminada")
	end)
	B.Connect("ProductPurchased", function(player, id)
		AnalyticsTracker.PurchaseStep(player, 3, id)
	end)
	Players.PlayerRemoving:Connect(function(player)
		onboardingDone[player] = nil
		purchaseSession[player] = nil
	end)
end

return AnalyticsTracker
