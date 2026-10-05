-- DevService: menu de testes (moedas, itens, melhorias, tipos de batata...).
-- Só funciona no Studio, para o dono do jogo (CreatorId) ou para quem está em Config.Admins,
-- e só com Config.Features.DevMenu ligado. Tudo validado aqui no servidor.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = ReplicatedStorage.Remotes

local DevService = {}

local S

function DevService.Allowed(player: Player): boolean
	if not Config.Features.DevMenu then
		return false
	end
	if RunService:IsStudio() then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId then
		return true
	end
	return table.find(Config.Admins, player.UserId) ~= nil
end

local function refreshAll(player: Player)
	S.Session.Publish(player)
	S.Economy.Refresh(player)
	S.Belt.PublishUpgrades(player)
	S.Kitchen.RefreshOwner(player)
	S.Avatar.Refresh(player)
	S.Session.RefreshMovement(player)
end

local ACTIONS = {}

ACTIONS.Coins = function(player, data, n)
	n = if typeof(n) == "number" then math.clamp(n, 1, 1e9) else 1000
	data.Coins += n
	S.Economy.Refresh(player)
	return "+" .. n .. " moedas"
end

ACTIONS.AllTools = function(player, data)
	for _, t in Config.Tools do
		data.OwnedTools[t.Id] = true
	end
	for _, c in Config.Collection do
		if not c.Soon then
			data.Items[c.Id] = true
		end
	end
	refreshAll(player)
	return "Todas as ferramentas e itens liberados (equipe na Loja)"
end

ACTIONS.BestTool = function(player, data)
	local best = Config.Tools[#Config.Tools]
	data.OwnedTools[best.Id] = true
	data.Tool = best.Id
	refreshAll(player)
	return "Equipado: " .. best.Name
end

ACTIONS.StarterTool = function(player, data)
	data.Tool = "FacaCega"
	refreshAll(player)
	return "Equipado: Faca cega"
end

ACTIONS.MaxUpgrades = function(player, data)
	for _, u in Config.Upgrades do
		data.Upgrades[u.Id] = #u.Levels
	end
	refreshAll(player)
	return "Melhorias no máximo"
end

ACTIONS.ResetUpgrades = function(player, data)
	data.Upgrades = { Cart = 1, Belt = 1, AutoPeel = 1 }
	refreshAll(player)
	return "Melhorias zeradas"
end

ACTIONS.SkipTutorial = function(player, data)
	data.Tutorial.Step = 100
	S.Session.Publish(player)
	S.Orders.StartFor(player, 0)
	return "Tutorial pulado"
end

ACTIONS.RestartTutorial = function(player, data)
	data.Tutorial = { Step = 1, Peeled = 0 }
	S.Session.Publish(player)
	return "Tutorial reiniciado"
end

ACTIONS.NextType = function(player, data, ptype)
	if typeof(ptype) ~= "string" or not Config.Potatoes[ptype] then
		return "Tipo inválido"
	end
	S.Peel.DebugForceType(player, ptype)
	return "Próxima batata: " .. Config.Potatoes[ptype].Name
end

ACTIONS.FillCart = function(player, data)
	local K = S.Kitchen.GetOwnedKitchen(player)
	if not K then
		return "Sem cozinha"
	end
	local n = 0
	while S.Kitchen.AddToCart(K, { Value = 5, Type = "Comum" }) do
		n += 1
		if n > 200 then
			break
		end
	end
	return "Carrinho cheio (+" .. n .. ")"
end

ACTIONS.Keys = function(player, data)
	data.Keys += 5
	data.Fragments = math.min(data.Fragments + 5, Config.Golden.FragmentsPerRoom)
	S.Session.Publish(player)
	return "+5 chaves e fragmentos"
end

ACTIONS.AllPasses = function(player, data)
	for _, p in Config.GamePasses do
		S.Monetization.GrantPass(player, p.Id)
	end
	return "Todos os passes (só nesta sessão)"
end

ACTIONS.NoPasses = function(player, data)
	for _, p in Config.GamePasses do
		S.Monetization.RevokePass(player, p.Id)
	end
	return "Passes desligados (só nesta sessão)"
end

-- um passe por vez: liga se não tem, desliga se já tem (só nesta sessão)
ACTIONS.TogglePass = function(player, data, id)
	local def = typeof(id) == "string" and Config.GamePassesById[id]
	if not def then
		return "Passe desconhecido"
	end
	if S.Monetization.HasPass(player, id) then
		S.Monetization.RevokePass(player, id)
		return def.Name .. ": desligado"
	end
	S.Monetization.GrantPass(player, id)
	return def.Name .. ": ligado"
end

-- simula a compra de um pacote (sem cobrar Robux)
ACTIONS.Product = function(player, data, id)
	local def = typeof(id) == "string" and Config.ProductsById[id]
	if not def then
		return "Pacote desconhecido"
	end
	if not S.Monetization.DebugGrantProduct(player, id) then
		return def.Name .. ": sem efeito para testar"
	end
	return def.Name .. ": entregue"
end

ACTIONS.Delivered = function(player, data)
	data.Stats.SeasonDelivered += Config.Rebirth.PotatoesRequired
	S.Rebirth.Publish(player)
	player:SetAttribute("SeasonDelivered", data.Stats.SeasonDelivered)
	return "Meta de rebirth atingida"
end

ACTIONS.ResetProgress = function(player, data)
	data.Coins = 0
	data.Tool = "FacaCega"
	data.OwnedTools = { FacaCega = true }
	data.Items = {}
	data.Upgrades = { Cart = 1, Belt = 1, AutoPeel = 1 }
	data.Tutorial = { Step = 1, Peeled = 0 }
	S.Session.ResetHands(player)
	refreshAll(player)
	return "Progresso zerado (como um jogador novo)"
end

function DevService.Init(services)
	S = services
	Remotes.DevRequest.OnServerInvoke = function(player: Player, action: any, arg: any)
		if not DevService.Allowed(player) or typeof(action) ~= "string" or not ACTIONS[action] then
			return { Ok = false }
		end
		local data = S.Data.Get(player)
		if not data then
			return { Ok = false }
		end
		local ok, text = pcall(ACTIONS[action], player, data, arg)
		if not ok then
			warn("[DevService]", action, text)
			return { Ok = false, Text = "Erro: " .. tostring(text) }
		end
		return { Ok = true, Text = text }
	end
	S.Bus.Connect("Loaded", function(player)
		player:SetAttribute("IsDev", DevService.Allowed(player))
	end)
end

return DevService
