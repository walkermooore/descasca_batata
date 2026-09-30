-- MachineAnimator: anima as máquinas no cliente a partir dos atributos do servidor
-- (Rate, Flow). O servidor só troca números (seção 10).

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Animator = {}

local C
local tracked = {} -- model -> estado
local balls = {} -- bolinhas nas esteiras
local BELT_SPEED = 4 -- studs/s
local MAX_BALLS = 250

local function newBall(): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = Vector3.new(0.5, 0.4, 0.6)
	p.Color = Color3.fromRGB(196, 150, 96)
	p.Material = Enum.Material.SmoothPlastic
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Parent = p
	p.Parent = C.Effects.Folder()
	return p
end

local function track(model: Instance)
	if not model:IsA("Model") or tracked[model] then
		return
	end
	local st = { Angle = 0, Timer = 0 }
	for _, name in { "Drum", "Piston", "Mixer", "Potato" } do
		local p = model:FindFirstChild(name) :: BasePart?
		if p then
			st[name] = p
			st[name .. "CF"] = p.CFrame
		end
	end
	st.Emitters = {}
	for _, d in model:GetDescendants() do
		if d:IsA("ParticleEmitter") then
			table.insert(st.Emitters, d)
		end
	end
	st.Pipe = model:FindFirstChild("Pipe")
	tracked[model] = st
end

local function watchKitchen(K: Instance)
	local folder = K:WaitForChild("Machines", 10)
	if not folder then
		return
	end
	for _, m in folder:GetChildren() do
		track(m)
	end
	folder.ChildAdded:Connect(function(m)
		task.wait() -- espera as peças replicarem
		track(m)
	end)
end

local function step(dt: number)
	local t = os.clock()
	for model, st in tracked do
		if not model.Parent then
			tracked[model] = nil
			continue
		end
		local rate = model:GetAttribute("Rate") or 0
		local on = rate > 0
		local speed = math.clamp(rate / 15, 0.4, 4)
		if st.Drum and on then
			st.Angle += dt * 5 * speed
			st.Drum.CFrame = st.DrumCF * CFrame.Angles(st.Angle, 0, 0)
		end
		if st.Mixer and on then
			st.Angle += dt * 4 * speed
			st.Mixer.CFrame = st.MixerCF * CFrame.Angles(0, st.Angle, 0)
		end
		if st.Piston then
			local y = if on then -0.7 * math.abs(math.sin(t * 3 * speed)) else 0
			st.Piston.CFrame = st.PistonCF * CFrame.new(0, y, 0)
		end
		if st.Potato and on then
			st.Potato.CFrame = st.PotatoCF * CFrame.new(0, 0.12 * math.abs(math.sin(t * 5)), 0) * CFrame.Angles(0, t * 2, 0)
		end
		for _, e in st.Emitters do
			if e.Enabled ~= on then
				e.Enabled = on
			end
		end
		-- cano do tanque some enquanto o carrinho viaja
		if st.Pipe then
			local K = model:FindFirstAncestorWhichIsA("Model")
			while K and K:GetAttribute("KitchenIndex") == nil do
				K = K:FindFirstAncestorWhichIsA("Model")
			end
			st.Pipe.Enabled = K == nil or (K:GetAttribute("CartState") or "Home") == "Home"
		end
		-- esteiras: batatas correndo na direção da seta
		local flow = model:GetAttribute("Flow")
		if flow and flow > 0 and #balls < MAX_BALLS then
			st.Timer -= dt
			if st.Timer <= 0 then
				st.Timer = math.clamp(60 / flow, 0.25, 6)
				local base = model:GetPivot()
				local y = model:GetAttribute("BeltY") or 0.62
				table.insert(balls, { Part = newBall(), From = base * CFrame.new(-2, y, 0), To = base * CFrame.new(2, y, 0), T = 0 })
			end
		end
	end
	for i = #balls, 1, -1 do
		local b = balls[i]
		b.T += dt * BELT_SPEED / 4
		if b.T >= 1 then
			b.Part:Destroy()
			table.remove(balls, i)
		else
			b.Part.CFrame = b.From:Lerp(b.To, b.T) * CFrame.Angles(0, 0, -b.T * 6)
		end
	end
end

function Animator.Init(controllers)
	C = controllers
	local folder = Workspace:WaitForChild("Kitchens")
	for _, K in folder:GetChildren() do
		task.spawn(watchKitchen, K)
	end
	folder.ChildAdded:Connect(watchKitchen)
	RunService.RenderStepped:Connect(step)
end

return Animator
