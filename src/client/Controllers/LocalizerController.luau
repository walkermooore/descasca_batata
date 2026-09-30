-- LocalizerController (Etapa 8): mostra o jogo em português, inglês ou espanhol.
-- O código do jogo continua escrevendo em português; aqui cada texto que aparece na tela,
-- nas placas do mapa e nos prompts é traduzido na hora (Shared.Localization).
-- O idioma vem do Roblox do jogador e pode ser trocado na engrenagem.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Localization = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Localization"))

local player = Players.LocalPlayer

local Localizer = {}

local lang = "pt"
-- texto original (português) de cada propriedade traduzida, para poder trocar de idioma
local original: { [Instance]: { [string]: string } } = setmetatable({}, { __mode = "k" }) :: any
-- último texto que NÓS escrevemos: os sinais do Roblox chegam atrasados (modo Deferred),
-- então o aviso da nossa própria escrita tem que ser reconhecido pelo conteúdo
local written: { [Instance]: { [string]: string } } = setmetatable({}, { __mode = "k" }) :: any

local function write(obj: Instance, prop: string, value: string)
	local w = written[obj]
	if not w then
		w = {}
		written[obj] = w
	end
	w[prop] = value
	local o: any = obj
	o[prop] = value
end

local function setProp(obj: Instance, prop: string)
	local current = (obj :: any)[prop]
	if type(current) ~= "string" then
		return
	end
	local w = written[obj]
	if w and w[prop] == current then
		return -- eco da nossa própria tradução
	end
	local store = original[obj]
	if not store then
		store = {}
		original[obj] = store
	end
	store[prop] = current
	local t = if lang == "pt" then current else Localization.Translate(current, lang)
	if t ~= current then
		write(obj, prop, t)
	elseif w then
		w[prop] = nil
	end
end

local PROPS = {
	TextLabel = { "Text" },
	TextButton = { "Text" },
	TextBox = { "PlaceholderText" }, -- o que o jogador digita não é traduzido
	ProximityPrompt = { "ActionText", "ObjectText" },
}

local function watch(obj: Instance)
	local props = PROPS[obj.ClassName]
	if not props then
		return
	end
	for _, prop in props do
		setProp(obj, prop)
		obj:GetPropertyChangedSignal(prop):Connect(function()
			setProp(obj, prop) -- o jogo escreveu um texto novo (em português)
		end)
	end
end

local function retranslateAll()
	for obj, store in original do
		for prop, pt in store do
			local t = if lang == "pt" then pt else Localization.Translate(pt, lang)
			if (obj :: any)[prop] ~= t then
				write(obj, prop, t)
			end
		end
	end
end

function Localizer.Lang(): string
	return lang
end

function Localizer.SetLang(l: string)
	if l ~= lang then
		lang = l
		player:SetAttribute("Lang", l)
		retranslateAll()
	end
end

local NAMES = { pt = "Português", en = "English", es = "Español" }
local ORDER = { "pt", "en", "es" }

-- botão de idioma no painel da engrenagem
local function addLanguageButton(C)
	local gui = C.HUD.Gui()
	local panel = gui:FindFirstChild("SettingsPanel") :: Frame?
	if not panel then
		return
	end
	local T = C.HUD.Theme
	panel.Size = UDim2.fromOffset(panel.Size.X.Offset, panel.Size.Y.Offset + 44)
	local b = Instance.new("TextButton")
	b.Name = "Language"
	b.Size = UDim2.new(1, -24, 0, 32)
	b.Position = UDim2.new(0, 12, 1, -40)
	b.Font = T.Font
	b.TextScaled = true
	b.TextColor3 = T.Bone
	b.BackgroundColor3 = T.PanelLight
	b.Parent = panel
	C.HUD.Corner(b, 6)
	local function refresh()
		b.Text = "Idioma / Language: " .. NAMES[lang]
	end
	refresh()
	b.Activated:Connect(function()
		local i = table.find(ORDER, lang) or 1
		Localizer.SetLang(ORDER[i % #ORDER + 1])
		refresh()
	end)
end

function Localizer.Init(C)
	lang = Localization.FromLocale(player.LocaleId)
	player:SetAttribute("Lang", lang)
	local pg = player:WaitForChild("PlayerGui")
	for _, root in { pg, Workspace } do
		for _, d in root:GetDescendants() do
			watch(d)
		end
		root.DescendantAdded:Connect(watch)
	end
	addLanguageButton(C)
end

return Localizer
