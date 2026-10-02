-- PerksService: o que os passes premium mostram no mundo.
--   BatataPet       batatinha de chapéu que segue o jogador (física do jogador: segue sem engasgo)
--   ChefLendario    chapéu de chef dourado + rastro brilhante
--   Duelista        coroa de duelista na cabeça
--   CarrinhoDeOuro  brilho dourado no carrinho da cozinha do jogador
-- A Faca de Ouro é só no cliente (PeelController lê o atributo Passes).

local Players = game:GetService("Players")

local PerksService = {}

local S
local GOLD = Color3.fromRGB(230, 186, 70)
local goldCart: { [Player]: Highlight } = {}

local function part(parent: Instance, size: Vector3, color: Color3, mat: Enum.Material, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Size = size
	p.Color = color
	p.Material = mat
	if shape then
		p.Shape = shape
	end
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.Parent = parent
	return p
end

local function weld(a: BasePart, b: BasePart, c0: CFrame)
	local w = Instance.new("Weld")
	w.Part0 = a
	w.Part1 = b
	w.C0 = c0
	w.Parent = b
end

-- Batatinha: um corpo (raiz com física) e o resto soldado nela.
local function makePet(char: Model, folder: Folder)
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return
	end
	local body = part(folder, Vector3.new(1.3, 1.1, 1.6), Color3.fromRGB(150, 108, 64), Enum.Material.Ground)
	body.Name = "PetBody"
	body.Massless = false
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = body
	body.CFrame = hrp.CFrame * CFrame.new(2.5, 0, 2)
	for _, s in { -1, 1 } do
		local eye = part(folder, Vector3.new(0.26, 0.26, 0.1), Color3.fromRGB(245, 240, 230), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		weld(body, eye, CFrame.new(0.24 * s, 0.18, -0.72))
		local pupil = part(folder, Vector3.new(0.12, 0.12, 0.06), Color3.fromRGB(20, 18, 16), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		weld(body, pupil, CFrame.new(0.24 * s, 0.17, -0.79))
		local foot = part(folder, Vector3.new(0.35, 0.18, 0.45), Color3.fromRGB(120, 84, 50), Enum.Material.Ground)
		weld(body, foot, CFrame.new(0.35 * s, -0.55, -0.1))
	end
	local smile = part(folder, Vector3.new(0.34, 0.06, 0.06), Color3.fromRGB(60, 34, 24), Enum.Material.SmoothPlastic)
	weld(body, smile, CFrame.new(0, -0.08, -0.79))
	-- chapéuzinho de chef
	local brim = part(folder, Vector3.new(0.18, 0.75, 0.75), Color3.fromRGB(236, 232, 222), Enum.Material.Fabric, Enum.PartType.Cylinder)
	weld(body, brim, CFrame.new(0, 0.6, 0.05) * CFrame.Angles(0, 0, math.rad(90)))
	local puff = part(folder, Vector3.new(0.7, 0.55, 0.7), Color3.fromRGB(240, 236, 228), Enum.Material.Fabric, Enum.PartType.Ball)
	weld(body, puff, CFrame.new(0, 0.85, 0.05))

	-- segue o jogador: posição atrás/ao lado, girando para a mesma direção
	local a0 = Instance.new("Attachment")
	a0.Parent = body
	local a1 = Instance.new("Attachment")
	a1.Name = "PetSlot"
	a1.Position = Vector3.new(2.6, -1.9, 2.2)
	a1.Parent = hrp
	local ap = Instance.new("AlignPosition")
	ap.Attachment0 = a0
	ap.Attachment1 = a1
	ap.MaxForce = 4000
	ap.Responsiveness = 18
	ap.Parent = body
	local ao = Instance.new("AlignOrientation")
	ao.Attachment0 = a0
	ao.Attachment1 = a1
	ao.MaxTorque = 4000
	ao.Responsiveness = 18
	ao.Parent = body
	body.Parent = folder
	pcall(function()
		body:SetNetworkOwner(Players:GetPlayerFromCharacter(char))
	end)
end

local function makeChefHat(head: BasePart, folder: Folder)
	local top = head.Size.Y / 2
	local band = part(folder, Vector3.new(0.5, 1.25, 1.25), GOLD, Enum.Material.Metal, Enum.PartType.Cylinder)
	weld(head, band, CFrame.new(0, top + 0.2, 0) * CFrame.Angles(0, 0, math.rad(90)))
	local puff = part(folder, Vector3.new(1.5, 1.1, 1.5), Color3.fromRGB(250, 246, 236), Enum.Material.Fabric, Enum.PartType.Ball)
	weld(head, puff, CFrame.new(0, top + 0.85, 0))
	local sp = Instance.new("Sparkles")
	sp.SparkleColor = GOLD
	sp.Parent = band
end

-- rastro brilhante entre os pés
local function makeTrail(hrp: BasePart)
	local a = Instance.new("Attachment")
	a.Position = Vector3.new(0, -2.6, 0.4)
	a.Parent = hrp
	local b = Instance.new("Attachment")
	b.Position = Vector3.new(0, -2.0, 0.4)
	b.Parent = hrp
	local tr = Instance.new("Trail")
	tr.Attachment0 = a
	tr.Attachment1 = b
	tr.Lifetime = 0.6
	tr.Color = ColorSequence.new(GOLD, Color3.fromRGB(255, 240, 180))
	tr.Transparency = NumberSequence.new(0.3, 1)
	tr.LightEmission = 0.6
	tr.Parent = hrp
	tr.Name = "PerkTrail"
	a.Name = "PerkTrailA"
	b.Name = "PerkTrailB"
end

local function makeCrown(head: BasePart, folder: Folder)
	local top = head.Size.Y / 2
	local ring = part(folder, Vector3.new(0.35, 1.15, 1.15), GOLD, Enum.Material.Metal, Enum.PartType.Cylinder)
	weld(head, ring, CFrame.new(0, top + 0.1, 0) * CFrame.Angles(0, 0, math.rad(90)))
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		local spike = part(folder, Vector3.new(0.16, 0.38, 0.16), GOLD, Enum.Material.Metal)
		weld(head, spike, CFrame.new(math.cos(a) * 0.5, top + 0.42, math.sin(a) * 0.5))
		if i % 2 == 0 then
			local gem = part(folder, Vector3.new(0.14, 0.14, 0.14), Color3.fromRGB(176, 40, 40), Enum.Material.Neon, Enum.PartType.Ball)
			weld(head, gem, CFrame.new(math.cos(a) * 0.58, top + 0.12, math.sin(a) * 0.58))
		end
	end
end

local function refreshCart(player: Player)
	local want = S.Monetization.HasPass(player, "CarrinhoDeOuro")
	local K = S.Kitchen.GetOwnedKitchen(player)
	local cart = K and K.Model and K.Model:FindFirstChild("Cart")
	local h = goldCart[player]
	if h and (not want or not cart or h.Parent ~= cart) then
		h:Destroy()
		goldCart[player] = nil
		h = nil
	end
	if want and cart and not h then
		local hl = Instance.new("Highlight")
		hl.Name = "GoldCart"
		hl.FillColor = GOLD
		hl.FillTransparency = 0.45
		hl.OutlineColor = Color3.fromRGB(255, 220, 120)
		hl.OutlineTransparency = 0.2
		hl.DepthMode = Enum.HighlightDepthMode.Occluded
		hl.Parent = cart
		goldCart[player] = hl
		local root = cart:FindFirstChild("Root")
		if root and not root:FindFirstChild("GoldSparkles") then
			local sp = Instance.new("Sparkles")
			sp.Name = "GoldSparkles"
			sp.SparkleColor = GOLD
			sp.Parent = root
		end
	elseif not want and cart then
		local root = cart:FindFirstChild("Root")
		local sp = root and root:FindFirstChild("GoldSparkles")
		if sp then
			sp:Destroy()
		end
	end
end

function PerksService.Refresh(player: Player)
	local char = player.Character
	if char then
		local old = char:FindFirstChild("Perks")
		if old then
			old:Destroy()
		end
		local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hrp then
			for _, n in { "PerkTrail", "PerkTrailA", "PerkTrailB", "PetSlot" } do
				local x = hrp:FindFirstChild(n)
				if x then
					x:Destroy()
				end
			end
		end
		local head = char:FindFirstChild("Head") :: BasePart?
		local folder = Instance.new("Folder")
		folder.Name = "Perks"
		folder.Parent = char
		if head and hrp then
			-- coroa de duelista tem prioridade sobre o chapéu (os dois não cabem na cabeça)
			if S.Monetization.HasPass(player, "Duelista") then
				makeCrown(head, folder)
			elseif S.Monetization.HasPass(player, "ChefLendario") then
				makeChefHat(head, folder)
			end
			if S.Monetization.HasPass(player, "ChefLendario") then
				makeTrail(hrp)
			end
			if S.Monetization.HasPass(player, "BatataPet") then
				makePet(char, folder)
			end
		end
	end
	refreshCart(player)
end

function PerksService.Init(services)
	S = services
	local function hook(player: Player)
		player.CharacterAdded:Connect(function(char)
			char:WaitForChild("HumanoidRootPart", 10)
			char:WaitForChild("Head", 10)
			task.wait(0.5)
			PerksService.Refresh(player)
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in Players:GetPlayers() do
		hook(p)
	end
	S.Bus.Connect("Loaded", function(player)
		task.delay(2, function()
			if player.Parent then
				PerksService.Refresh(player)
			end
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		local h = goldCart[player]
		if h then
			local cart = h.Parent
			h:Destroy()
			local root = cart and cart:FindFirstChild("Root")
			local sp = root and root:FindFirstChild("GoldSparkles")
			if sp then
				sp:Destroy()
			end
		end
		goldCart[player] = nil
	end)
end

return PerksService
