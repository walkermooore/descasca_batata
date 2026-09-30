-- Main: inicializa os serviços do servidor na ordem certa.
-- Cada serviço recebe a tabela de serviços para falar com os outros sem require circular.

local Folder = script.Parent:WaitForChild("Services")

local ORDER = {
	{ "Bus", "Bus" },
	{ "Data", "DataService" },
	{ "Session", "SessionService" },
	{ "Economy", "EconomyService" },
	{ "Kitchen", "KitchenService" },
	{ "Belt", "BeltService" },
	{ "Peel", "PeelService" },
	{ "Rewards", "RewardService" },
	{ "Orders", "OrderService" },
	{ "Tutorial", "TutorialService" },
	{ "Shop", "ShopService" },
	{ "Avatar", "AvatarService" },
	{ "Machines", "MachineService" },
	{ "Rebirth", "RebirthService" },
	{ "Social", "SocialService" },
	{ "Ranking", "RankingService" },
	{ "Events", "EventService" },
	{ "Monetization", "MonetizationService" },
	{ "Retention", "RetentionService" },
	{ "Analytics", "AnalyticsTracker" },
	{ "Dev", "DevService" },
}

local Services = {}
for _, entry in ORDER do
	Services[entry[1]] = require(Folder:WaitForChild(entry[2]))
end
Services.Race = Services.Events -- a Corrida de Descascar vive no EventService
-- conecta os ouvintes do Bus antes de os jogadores começarem a carregar
for i = #ORDER, 1, -1 do
	local name = ORDER[i][1]
	if name ~= "Data" and name ~= "Session" and name ~= "Economy" and name ~= "Kitchen" then
		Services[name].Init(Services)
	end
end
for _, name in { "Economy", "Kitchen", "Session", "Data" } do
	Services[name].Init(Services)
end

-- Só no Studio: comandos de teste (moedas, forçar tipo de batata, pular tutorial).
if game:GetService("RunService"):IsStudio() then
	local bf = Instance.new("BindableFunction")
	bf.Name = "SpudDebugServer"
	bf.OnInvoke = function(cmd: string, player: Player, arg: any)
		if cmd == "coins" then
			return Services.Economy.Add(player, arg, "Debug")
		elseif cmd == "force" then
			Services.Peel.DebugForceType(player, arg)
		elseif cmd == "skipTutorial" then
			local data = Services.Data.Get(player)
			data.Tutorial.Step = 100
			Services.Session.Publish(player)
			Services.Orders.StartFor(player, 0)
		elseif cmd == "giant" then
			Services.Events.DebugStartGiant()
		elseif cmd == "grantPass" then
			Services.Monetization.GrantPass(player, arg)
		elseif cmd == "deliverEvent" then
			Services.Bus.Fire("Delivered", player, 0, arg)
		elseif cmd == "delivered" then
			local data = Services.Data.Get(player)
			data.Stats.SeasonDelivered += arg
			Services.Rebirth.Publish(player)
		elseif cmd == "data" then
			return game:GetService("HttpService"):JSONEncode(Services.Data.Get(player))
		end
		return true
	end
	bf.Parent = script
end

print("[Spud Shift] servidor pronto -", require(game.ReplicatedStorage.Shared.Config).Version)
