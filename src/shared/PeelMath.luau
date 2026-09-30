-- PeelMath: regras puras do descascar (seção 2.5). Usado pelo servidor (autoridade)
-- e pelo cliente (previsão visual imediata), para os dois sempre concordarem.

local Config = require(script.Parent.Config)

local PeelMath = {}

local RESULT_ORDER = { "Perfect", "Good", "Bad" }

function PeelMath.Classify(precision: number, assisted: boolean?): (string, number)
	local results = Config.Peel.Results
	local name = "Bad"
	for _, n in RESULT_ORDER do
		if precision >= results[n].MinPrecision then
			name = n
			break
		end
	end
	local yield = results[name].Yield
	if assisted then
		yield = math.min(yield, Config.Peel.Assisted.MaxYield)
	end
	return name, yield
end

-- Perfeita +1, Boa mantém, Ruim zera. Precisão assistida desativa o combo.
function PeelMath.NextCombo(combo: number, result: string, assisted: boolean?): number
	if assisted and Config.Peel.Assisted.ComboDisabled then
		return 0
	end
	if result == "Perfect" then
		return combo + 1
	elseif result == "Bad" then
		return 0
	end
	return combo
end

-- Retorna multiplicador e índice da faixa de combo (1..5).
function PeelMath.ComboMultiplier(combo: number, toolTier: number?): (number, number)
	local tiers = Config.Peel.ComboTiers
	for i = #tiers, 1, -1 do
		local t = tiers[i]
		if combo >= t.Min and (t.RequiresToolTier == nil or (toolTier or 1) >= t.RequiresToolTier) then
			return t.Mult, i
		end
	end
	return 1, 1
end

-- Largura da faixa verde como fração da largura da faixa de casca.
function PeelMath.GreenWidth(toolId: string?, assisted: boolean?, tutorial: boolean?): number
	local tool = Config.ToolsById[toolId or ""] or Config.Tools[1]
	local w = tool.GreenWidth
	if tutorial then
		w *= Config.Peel.TutorialGreenMultiplier
	end
	if assisted then
		w += Config.Peel.Assisted.GreenBonus
	end
	return math.clamp(w, 0.05, 0.95)
end

-- Valor = V_base x R x C x M
function PeelMath.PotatoValue(baseValue: number, avgYield: number, comboMult: number, permanentMult: number): number
	return baseValue * avgYield * comboMult * permanentMult
end

function PeelMath.ToolFor(toolId: string?)
	return Config.ToolsById[toolId or ""] or Config.Tools[1]
end

return PeelMath
