-- PotatoGeometry: matemática da batata em close.
-- A batata é um elipsóide com semi-eixo longo A (eixo Y local) e curto B (X/Z).
-- Faixas são meridianos: faixa i fica no ângulo phi_i em torno do eixo Y.
-- Convenção: phi = 0 aponta para -Z local (LookVector), que é o lado virado para a câmera.
--   Surface(theta, phi) = (B cos(theta) sin(phi), A sin(theta), -B cos(theta) cos(phi))
-- theta vai de -pi/2 (ponta de baixo) a +pi/2 (ponta de cima).

local Geo = {}

Geo.THETA_MAX = math.rad(80) -- as pontas acima disso são "tampinhas"

function Geo.StripAngle(index: number, strips: number): number
	return (index - 1) * (2 * math.pi / strips)
end

function Geo.Surface(theta: number, phi: number, a: number, b: number): Vector3
	local c = math.cos(theta)
	return Vector3.new(b * c * math.sin(phi), a * math.sin(theta), -b * c * math.cos(phi))
end

function Geo.Normal(theta: number, phi: number, a: number, b: number): Vector3
	local p = Geo.Surface(theta, phi, a, b)
	return Vector3.new(p.X / (b * b), p.Y / (a * a), p.Z / (b * b)).Unit
end

-- Direção circunferencial (largura da faixa) no ângulo phi.
function Geo.Across(phi: number): Vector3
	return Vector3.new(math.cos(phi), 0, math.sin(phi))
end

-- Meia-largura da faixa no equador (studs).
function Geo.HalfStripWidth(b: number, strips: number, theta: number?): number
	return b * math.cos(theta or 0) * math.sin(math.pi / strips)
end

-- Interseção raio x elipsóide. Retorna o ponto em espaço LOCAL da batata, ou nil.
function Geo.RayHit(rootCF: CFrame, a: number, b: number, origin: Vector3, dir: Vector3): Vector3?
	local o = rootCF:PointToObjectSpace(origin)
	local d = rootCF:VectorToObjectSpace(dir)
	local os = Vector3.new(o.X / b, o.Y / a, o.Z / b)
	local ds = Vector3.new(d.X / b, d.Y / a, d.Z / b)
	local A = ds:Dot(ds)
	local B = 2 * os:Dot(ds)
	local C = os:Dot(os) - 1
	local disc = B * B - 4 * A * C
	if disc < 0 then
		return nil
	end
	local s = (-B - math.sqrt(disc)) / (2 * A)
	if s < 0 then
		return nil
	end
	return o + d * s
end

-- Mede um ponto local em relação ao meridiano central phiCenter:
--   theta  = altura ao longo da faixa (-pi/2..pi/2)
--   lateral = distância (studs) até o plano do meridiano; math.huge se estiver no lado de trás.
function Geo.Measure(p: Vector3, a: number, b: number, phiCenter: number): (number, number)
	local theta = math.asin(math.clamp(p.Y / a, -1, 1))
	local across = Geo.Across(phiCenter)
	local front = p.X * math.sin(phiCenter) - p.Z * math.cos(phiCenter)
	if front < 0 then
		return theta, math.huge
	end
	return theta, p.X * across.X + p.Z * across.Z
end

-- Ponto na superfície a partir de (theta, lateral) em torno de phiCenter (usado pelo controle).
function Geo.FromMeasure(theta: number, lateral: number, phiCenter: number, a: number, b: number): Vector3
	local r = math.max(b * math.cos(theta), 1e-3)
	local dphi = math.asin(math.clamp(lateral / r, -1, 1))
	return Geo.Surface(theta, phiCenter + dphi, a, b)
end

-- Distância horizontal de um ponto até a caixa do tampo da mesa.
function Geo.DistanceToBox(part: BasePart, pos: Vector3): number
	local p = part.CFrame:PointToObjectSpace(pos)
	local hx, hz = part.Size.X / 2, part.Size.Z / 2
	local dx = math.max(math.abs(p.X) - hx, 0)
	local dz = math.max(math.abs(p.Z) - hz, 0)
	return math.sqrt(dx * dx + dz * dz)
end

return Geo
