-- Format: números no padrão pt-BR (1.234 / 4,25 / x1,5)

local Format = {}

function Format.Int(n: number): string
	n = math.floor(n + 0.5)
	local s = tostring(math.abs(n))
	local out = (s:reverse():gsub("(%d%d%d)", "%1.")):reverse()
	if out:sub(1, 1) == "." then
		out = out:sub(2)
	end
	return (n < 0 and "-" or "") .. out
end

function Format.Dec(n: number, places: number?): string
	local s = string.format("%." .. (places or 2) .. "f", n)
	return (s:gsub("%.", ","))
end

-- Moedas: inteiros acima de 100, duas casas abaixo (valores por batata são pequenos)
function Format.Coins(n: number): string
	if math.abs(n) >= 100 then
		return Format.Int(n)
	end
	local s = Format.Dec(n, 2)
	s = s:gsub(",00$", "")
	return s
end

function Format.Mult(m: number): string
	if m == math.floor(m) then
		return "x" .. tostring(m)
	end
	return "x" .. Format.Dec(m, 1)
end

return Format
