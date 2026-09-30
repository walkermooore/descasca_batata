-- BeltAnimator: anima a esteira da cozinha no cliente.
--   * Batatas: o servidor cria cada uma no início com T0 (hora do servidor) e Dur; aqui ela
--     anda pelo caminho P1..Pn. Com o carrinho fora/cheio ela para na ponta (atributo Wait).
--   * Ripas da lona correm na velocidade da esteira (atributo BeltSpeed da cozinha).
--   * Tambor do descascador automático gira quando está ligado.
-- Só anima cozinhas perto da câmera.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local BeltAnimator = {}

local belts = {} -- Model(K) -> info

local function pathOf(belt: Model)
	local root = belt:FindFirstChild("BeltRoot")
	local pts = {}
	local i = 1
	while root and root:FindFirstChild("P" .. i) do
		table.insert(pts, (root :: any)["P" .. i].WorldPosition)
		i += 1
	end
	local cum = { 0 }
	for j = 2, #pts do
		cum[j] = cum[j - 1] + (pts[j] - pts[j - 1]).Magnitude
	end
	return pts, cum, cum[#cum] or 0
end

-- Posição e direção a uma distância d do início.
local function at(info, d: number): (Vector3, Vector3)
	local pts, cum = info.Pts, info.Cum
	d = math.clamp(d, 0, info.Len)
	for j = 2, #pts do
		if d <= cum[j] or j == #pts then
			local seg = cum[j] - cum[j - 1]
			local a = if seg > 0 then (d - cum[j - 1]) / seg else 0
			return pts[j - 1]:Lerp(pts[j], a), (pts[j] - pts[j - 1]).Unit
		end
	end
	return pts[1], Vector3.zAxis
end

local function track(K: Instance)
	if not K:IsA("Model") or belts[K] then
		return
	end
	local belt = K:WaitForChild("Belt", 10)
	if not belt then
		return
	end
	belt:WaitForChild("BeltRoot", 10)
	local pts, cum, len = pathOf(belt :: Model)
	if #pts < 2 then
		return
	end
	local info = { K = K, Belt = belt, Pts = pts, Cum = cum, Len = len, Cleats = {} }
	-- distância inicial de cada ripa ao longo do caminho (projeção no segmento mais próximo)
	local folder = belt:FindFirstChild("Cleats")
	if folder then
		for _, c in folder:GetChildren() do
			if c:IsA("BasePart") then
				local best, bestDist = 0, math.huge
				for j = 2, #pts do
					local a, b = pts[j - 1], pts[j]
					local ab = b - a
					local t = math.clamp((c.Position - a):Dot(ab) / ab:Dot(ab), 0, 1)
					local dist = (a + ab * t - c.Position).Magnitude
					if dist < bestDist then
						best, bestDist = cum[j - 1] + ab.Magnitude * t, dist
					end
				end
				table.insert(info.Cleats, { Part = c, D0 = best, Offset = c.Position.Y - at(info, best).Y })
			end
		end
	end
	-- ponto da esteira onde fica o cortador de fritas (dali em diante a batata vira fritas)
	local cutter = belt:FindFirstChild("Cutter")
	if cutter then
		local cpos = cutter:GetPivot().Position
		local best, bestDist = len, math.huge
		for j = 2, #pts do
			local a, b = pts[j - 1], pts[j]
			local ab = b - a
			local t = math.clamp((cpos - a):Dot(ab) / ab:Dot(ab), 0, 1)
			local dist = (a + ab * t - cpos).Magnitude
			if dist < bestDist then
				best, bestDist = cum[j - 1] + ab.Magnitude * t, dist
			end
		end
		info.CutterD = best
	end
	local auto = belt:FindFirstChild("AutoPeeler")
	info.Drum = auto and auto:FindFirstChild("Drum")
	info.DrumCF = info.Drum and info.Drum.CFrame
	-- tambor grande e prensa do purê
	local big = belt:FindFirstChild("Drum")
	info.BigDrum = big
	info.BigParts = {}
	if big then
		for _, n in { "DrumBody", "Ring" } do
			for _, p in big:GetChildren() do
				if p.Name == n then
					table.insert(info.BigParts, { Part = p, CF = p.CFrame })
				end
			end
		end
	end
	local masher = belt:FindFirstChild("Masher")
	info.Masher = masher
	info.MasherParts = {}
	if masher then
		for _, n in { "Piston", "Press" } do
			local p = masher:FindFirstChild(n)
			if p then
				table.insert(info.MasherParts, { Part = p, CF = p.CFrame })
			end
		end
	end
	belts[K] = info
end

local function step()
	local now = Workspace:GetServerTimeNow()
	local camPos = Workspace.CurrentCamera.CFrame.Position
	local t = os.clock()
	for K, info in belts do
		if not K.Parent then
			belts[K] = nil
			continue
		end
		if (info.Pts[1] - camPos).Magnitude > 110 then
			continue
		end
		local speed = K:GetAttribute("BeltSpeed") or 3
		-- ripas correndo
		for _, c in info.Cleats do
			local d = (c.D0 + t * speed) % info.Len
			local pos, dir = at(info, d)
			c.Part.CFrame = CFrame.lookAt(pos + Vector3.new(0, c.Offset, 0), pos + Vector3.new(0, c.Offset, 0) + dir)
		end
		-- batatas
		local items = info.Belt:FindFirstChild("Items")
		if items then
			local endPos, endDir = at(info, info.Len)
			for _, p in items:GetChildren() do
				if p:IsA("BasePart") then
					local t0, dur = p:GetAttribute("T0"), p:GetAttribute("Dur")
					if t0 and dur then
						local wait = p:GetAttribute("Wait")
						local pos, dir
						local a = math.clamp((now - t0) / dur, 0, 1)
						if wait and a >= 1 then
							pos, dir = endPos - endDir * 0.62 * (wait - 1), endDir
						else
							pos, dir = at(info, a * info.Len)
						end
						-- passou pelo cortador: vira um montinho de fritas douradas (só visual, neste cliente)
						if info.CutterD and K:GetAttribute("CutterOn") and a * info.Len >= info.CutterD and not p:GetAttribute("Fries") then
							p:SetAttribute("Fries", true)
							p.Color = Color3.fromRGB(214, 170, 72)
							p.Size = Vector3.new(0.9, 0.35, 0.9)
						end
						local side = dir:Cross(Vector3.yAxis).Unit * (p:GetAttribute("Lane") or 0)
						local roll = if wait and a >= 1 then 0 else a * info.Len * 1.5
						p.CFrame = CFrame.lookAt(pos + side, pos + side + dir) * CFrame.Angles(-roll, 0, 0)
					end
				end
			end
		end
		if info.BigDrum and info.BigDrum:GetAttribute("Active") then
			for _, it in info.BigParts do
				it.Part.CFrame = it.CF * CFrame.Angles(t * 2.5, 0, 0)
			end
		end
		if info.Masher and info.Masher:GetAttribute("Active") then
			local down = math.max(0, math.sin(t * 5)) * 0.9
			for _, it in info.MasherParts do
				it.Part.CFrame = it.CF * CFrame.new(0, -down, 0)
			end
		end
		-- tambor do descascador automático
		local auto = info.Belt:FindFirstChild("AutoPeeler")
		if info.Drum and auto and auto:GetAttribute("Active") then
			info.Drum.CFrame = info.DrumCF * CFrame.Angles(t * 6, 0, 0)
		end
	end
end

function BeltAnimator.Init()
	local folder = Workspace:WaitForChild("Kitchens")
	for _, K in folder:GetChildren() do
		task.spawn(track, K)
	end
	folder.ChildAdded:Connect(function(K)
		task.spawn(track, K)
	end)
	RunService.RenderStepped:Connect(step)
end

return BeltAnimator
