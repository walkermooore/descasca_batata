-- ShopService: compras com Moedas (ferramentas e itens de coleta) e equipar ferramentas.
-- Passes e cosméticos (Robux) entram na Etapa 6 via MonetizationService.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Strings = require(ReplicatedStorage.Shared.Strings)
local Remotes = ReplicatedStorage.Remotes

local ShopService = {}

local S

local function equip(player: Player, toolId: string)
	local data = S.Data.Get(player)
	data.Tool = toolId
	S.Session.Publish(player)
	S.Avatar.Refresh(player)
end

local function buy(player: Player, id: string, qty: number)
	local data = S.Data.Get(player)
	if not data then
		return { Ok = false, Reason = "Loading" }
	end
	if Config.MachinesById[id] then
		return S.Machines.Buy(player, id, qty)
	end
	local tool = Config.ToolsById[id]
	if tool then
		if data.OwnedTools[id] then
			return { Ok = false, Reason = "Owned" }
		end
		if not S.Economy.Spend(player, tool.Cost, "Tool:" .. id) then
			return { Ok = false, Reason = Strings.NotEnough }
		end
		data.OwnedTools[id] = true
		-- equipa automaticamente se for melhor que a atual
		local current = Config.ToolsById[data.Tool]
		if not current or tool.Tier > current.Tier then
			equip(player, id)
		else
			S.Session.Publish(player)
		end
		S.Bus.Fire("Purchased", player, id)
		return { Ok = true }
	end
	local item = Config.CollectionById[id]
	if item then
		if item.Soon then
			return { Ok = false, Reason = Strings.Soon }
		end
		if data.Items[id] then
			return { Ok = false, Reason = "Owned" }
		end
		if not S.Economy.Spend(player, item.Cost, "Item:" .. id) then
			return { Ok = false, Reason = Strings.NotEnough }
		end
		data.Items[id] = true
		S.Session.Publish(player)
		S.Kitchen.RefreshOwner(player)
		S.Avatar.Refresh(player)
		S.Bus.Fire("Purchased", player, id)
		return { Ok = true }
	end
	return { Ok = false, Reason = Strings.Soon }
end

function ShopService.Init(services)
	S = services
	Remotes.ShopRequest.OnServerInvoke = function(player: Player, action: any, id: any, qty: any)
		if typeof(action) ~= "string" or typeof(id) ~= "string" then
			return { Ok = false }
		end
		if action == "Buy" then
			return buy(player, id, if typeof(qty) == "number" then qty else 1)
		elseif action == "Upgrade" then
			return S.Belt.BuyUpgrade(player, id)
		elseif action == "Equip" then
			local data = S.Data.Get(player)
			if data and data.OwnedTools[id] and Config.ToolsById[id] then
				equip(player, id)
				return { Ok = true }
			end
		end
		return { Ok = false }
	end
end

return ShopService
