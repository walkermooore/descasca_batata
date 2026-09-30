-- Localization (Etapa 8): traduz textos em português para inglês ou espanhol usando o
-- dicionário de Translations. Funciona com texto exato e com padrões ("%s"/"%d"): a parte
-- variável é capturada e também traduzida (ex.: "Cozinha de %s", "%s N%d").
-- Textos com várias linhas ou partes separadas por " · " são traduzidos pedaço por pedaço.

local Translations = require(script.Parent:WaitForChild("Translations"))

local Localization = {}

local LANGS = { en = 2, es = 3 }
local MAGIC = "[%^%$%(%)%%%.%[%]%*%+%-%?]"

local exact = { en = {}, es = {} }
local patterns = {}

-- "Cozinha de %s" -> "^Cozinha de (.-)$"; só %s e %d são variáveis, o resto é literal.
local function compile(fmt: string)
	local out, literal, prefix = {}, 0, nil
	local i = 1
	while i <= #fmt do
		local two = fmt:sub(i, i + 1)
		if two == "%s" or two == "%d" then
			prefix = prefix or fmt:sub(1, i - 1)
			-- %d só aceita números (senão "%s N%d" pegaria o N de "NOTHING")
			table.insert(out, if two == "%d" then "(%-?[%d%.,]+)" else "(.-)")
			i += 2
		else
			local c = fmt:sub(i, i)
			table.insert(out, if c:match(MAGIC) then "%" .. c else c)
			literal += 1
			i += 1
		end
	end
	return "^" .. table.concat(out) .. "$", literal, prefix or fmt
end

for _, e in Translations do
	local pt = e[1]
	if pt:find("%%[sd]") then
		local pat, literal, prefix = compile(pt)
		table.insert(patterns, { Pattern = pat, Literal = literal, Prefix = prefix, en = e[2], es = e[3] })
	else
		exact.en[pt] = e[2]
		exact.es[pt] = e[3]
	end
end
-- os mais específicos (mais texto fixo) primeiro
table.sort(patterns, function(a, b)
	return a.Literal > b.Literal
end)

local function fill(target: string, caps: { string }): string
	local n = 0
	return (target:gsub("%%[sd]", function()
		n += 1
		return caps[n] or ""
	end))
end

local cache = { en = {}, es = {} }
local cacheSize = 0

local translate

local function viaPattern(text: string, lang: string, depth: number): string?
	for _, p in patterns do
		if p.Prefix == "" or text:sub(1, #p.Prefix) == p.Prefix then
			local caps = { text:match(p.Pattern) }
			if #caps > 0 then
				for i, c in caps do
					caps[i] = translate(c, lang, depth + 1)
				end
				return fill(p[lang], caps)
			end
		end
	end
	return nil
end

local SEPARATORS = { "\n", "   ·   ", "  ·  ", " · ", " + " }

function translate(text: string, lang: string, depth: number?): string
	depth = depth or 0
	if depth > 3 or text == "" or not text:find("%a") then
		return text
	end
	local hit = exact[lang][text]
	if hit then
		return hit
	end
	-- espaços nas pontas (rótulos com recuo) não atrapalham
	local lead, core, trail = text:match("^(%s*)(.-)(%s*)$")
	if core ~= text and exact[lang][core] then
		return lead .. exact[lang][core] .. trail
	end
	local r = viaPattern(text, lang, depth)
	if r then
		return r
	end
	for _, sep in SEPARATORS do
		if text:find(sep, 1, true) then
			local parts = string.split(text, sep)
			local changed = false
			for i, part in parts do
				local t = translate(part, lang, depth + 1)
				if t ~= part then
					parts[i] = t
					changed = true
				end
			end
			if changed then
				return table.concat(parts, sep)
			end
		end
	end
	return text
end

-- lang: "pt" (original), "en" ou "es".
function Localization.Translate(text: string, lang: string): string
	if not LANGS[lang] or type(text) ~= "string" then
		return text
	end
	local c = cache[lang][text]
	if c then
		return c
	end
	local r = translate(text, lang, 0)
	if cacheSize > 4000 then
		cache = { en = {}, es = {} }
		cacheSize = 0
	end
	cache[lang][text] = r
	cacheSize += 1
	return r
end

-- "pt-br" -> "pt", "es-mx" -> "es"; qualquer outro idioma cai no inglês.
function Localization.FromLocale(localeId: string?): string
	local code = string.lower(string.sub(localeId or "pt", 1, 2))
	if code == "pt" or code == "es" then
		return code
	end
	return "en"
end

return Localization
