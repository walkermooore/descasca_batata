-- ClientMain: inicializa os controladores do cliente na ordem certa.

local Controllers = script.Parent:WaitForChild("Controllers")

local ORDER = {
	{ "Kitchen", "KitchenClient" },
	{ "Effects", "EffectsController" },
	{ "HUD", "HUDController" },
	{ "Actions", "ActionController" },
	{ "Prompts", "PromptController" },
	{ "Cart", "CartAnimator" },
	{ "BeltAnim", "BeltAnimator" },
	{ "Shop", "ShopController" },
	{ "Build", "BuildController" },
	{ "Season", "SeasonController" },
	{ "Diary", "DiaryController" },
	{ "Machines", "MachineAnimator" },
	{ "Social", "SocialController" },
	{ "Events", "EventController" },
	{ "Ambience", "AmbienceController" },
	{ "Rewards", "RewardController" },
	{ "Orders", "OrderController" },
	{ "Tutorial", "TutorialController" },
	{ "Peel", "PeelController" },
	{ "Dev", "DevController" },
	{ "Localizer", "LocalizerController" }, -- por último: traduz o que os outros criaram
}

-- Cada controlador carrega isolado: um erro num deles não derruba a interface inteira.
local C = {}
for _, entry in ORDER do
	local ok, mod = pcall(require, Controllers:WaitForChild(entry[2]))
	if ok then
		C[entry[1]] = mod
	else
		warn("[ClientMain] falhou ao carregar", entry[2], mod)
		C[entry[1]] = {}
	end
end
for _, entry in ORDER do
	local mod = C[entry[1]]
	if mod.Init then
		local ok, err = pcall(mod.Init, C)
		if not ok then
			warn("[ClientMain] falhou ao iniciar", entry[2], err)
		end
	end
end

-- Só no Studio: permite simular passadas pela linha de comando / testes automatizados.
if game:GetService("RunService"):IsStudio() then
	local bf = Instance.new("BindableFunction")
	bf.Name = "SpudDebugStroke"
	bf.OnInvoke = function(first, ...)
		if first == "release" then
			return C.Peel.DebugRelease()
		end
		return C.Peel.DebugStroke(first, ...)
	end
	bf.Parent = script
end
