-- RebirthService: "Nova Temporada" (seção 3).
--   * Ao entregar a meta de batatas na temporada, o jogador pode reiniciar Moedas, ferramentas,
--     máquinas e alas (itens de coleta ficam: não são "ferramentas" nem "máquinas" no GDD).
--   * Ganha Sementes de Ouro e +25% de Moedas permanente por rebirth.
--   * Sementes compram talentos; cada rebirth libera uma cozinha temática e muda o cardápio do Rei.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Strings = require(ReplicatedStorage.Shared.Strings)
local Remotes = ReplicatedStorage.Remotes

local RebirthService = {}

local S

function RebirthService.SeedsFor(data): number
	local rb = Config.Rebirth
	local extra = math.max(0, data.Stats.SeasonDelivered - rb.PotatoesRequired)
	return rb.SeedsBase + math.floor(extra / rb.SeedsPerExtra)
end

function RebirthService.CanRebirth(data): boolean
	return data.Stats.SeasonDelivered >= Config.Rebirth.PotatoesRequired
end

function RebirthService.Multiplier(data): number
	return 1 + data.Rebirths * Config.Rebirth.MultiplierPerRebirth
end

function RebirthService.ThemeUnlocked(data, themeId: string): boolean
	local t = Config.Themes[themeId]
	return t ~= nil and data.Rebirths >= t.Rebirths
end

function RebirthService.Publish(player: Player)
	local data = S.Data.Get(player)
	if not data then
		return
	end
	player:SetAttribute("Rebirths", data.Rebirths)
	player:SetAttribute("Seeds", data.Seeds)
	player:SetAttribute("SeasonDelivered", data.Stats.SeasonDelivered)
	player:SetAttribute("Theme", data.Theme)
	local t = {}
	for id, lvl in data.Talents do
		table.insert(t, id .. ":" .. lvl)
	end
	player:SetAttribute("Talents", table.concat(t, ","))
end

function RebirthService.SetTheme(player: Player, themeId: string)
	local data = S.Data.Get(player)
	local K = S.Kitchen.GetOwnedKitchen(player)
	if not data or not K or not RebirthService.ThemeUnlocked(data, themeId) then
		return { Ok = false }
	end
	data.Theme = themeId
	S.Kitchen.ApplyTheme(K, themeId)
	RebirthService.Publish(player)
	return { Ok = true }
end

function RebirthService.BuyTalent(player: Player, id: string)
	local data = S.Data.Get(player)
	local talent = Config.TalentsById[id]
	if not data or not talent then
		return { Ok = false }
	end
	local lvl = data.Talents[id] or 0
	local cost = talent.Costs[lvl + 1]
	if not cost then
		return { Ok = false, Reason = Strings.MaxLevel }
	end
	if data.Seeds < cost then
		return { Ok = false, Reason = "Sementes insuficientes" }
	end
	data.Seeds -= cost
	data.Talents[id] = lvl + 1
	RebirthService.Publish(player)
	return { Ok = true }
end

function RebirthService.DoRebirth(player: Player)
	local data = S.Data.Get(player)
	local K = S.Kitchen.GetOwnedKitchen(player)
	local st = S.Session.GetState(player)
	if not data or not K then
		return { Ok = false }
	end
	if not RebirthService.CanRebirth(data) then
		return { Ok = false, Reason = Strings.SeasonNotReady }
	end
	if st ~= "Free" then
		return { Ok = false, Reason = "Largue o que está segurando primeiro" }
	end
	local seeds = RebirthService.SeedsFor(data)
	data.Rebirths += 1
	data.Seeds += seeds
	-- reinicia Moedas, ferramentas, máquinas e alas
	data.Coins = 0
	data.Tool = "FacaCega"
	data.OwnedTools = { FacaCega = true }
	data.Machines = {}
	data.Inventory = {}
	data.Tank = { Count = 0, Value = 0 }
	data.Upgrades = { Cart = 1, Belt = 1, AutoPeel = 1 } -- melhorias da esteira são as "máquinas" agora
	data.Wings = math.min(Config.Grid.Wings, (data.Talents.EspacoExtra or 0) * Config.TalentsById.EspacoExtra.PerLevel)
	data.Stats.SeasonDelivered = 0
	-- libera a próxima cozinha temática e já a usa
	local themes = Config.Rebirth.Themes
	local unlocked = themes[math.min(data.Rebirths + 1, #themes)]
	if unlocked and RebirthService.ThemeUnlocked(data, unlocked) then
		data.Theme = unlocked
	end

	S.Economy.Refresh(player)
	S.Session.Publish(player)
	S.Kitchen.ApplyWings(K, data.Wings)
	S.Kitchen.ApplyTheme(K, data.Theme)
	S.Machines.PublishInventory(player)
	S.Machines.RebuildAll(player)
	S.Belt.Clear(K)
	S.Belt.PublishUpgrades(player)
	S.Kitchen.RefreshOwner(player)
	S.Avatar.Refresh(player)
	RebirthService.Publish(player)
	Remotes.Reward:FireClient(player, "Rebirth", { Season = data.Rebirths + 1, Seeds = seeds, Theme = Config.Themes[data.Theme].Name })
	S.Bus.Fire("Rebirth", player, data.Rebirths)
	return { Ok = true }
end

function RebirthService.Init(services)
	S = services
	S.Bus.Connect("Loaded", function(player)
		RebirthService.Publish(player)
	end)
end

return RebirthService
