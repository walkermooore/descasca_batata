-- CartAnimator: anima os carrinhos de entrega no cliente a partir dos atributos do servidor
-- (CartState + CartStateStart). O servidor só troca estados e números (seção 10).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local CartAnimator = {}

local carts = {}

local function ease(a: number): number
	return -(math.cos(math.pi * a) - 1) / 2
end

local function track(K: Model)
	local cart = K:WaitForChild("Cart", 10) :: Model?
	if not cart then
		return
	end
	local root = cart:WaitForChild("Root") :: BasePart
	local flag = cart:WaitForChild("Flag") :: BasePart
	local countGui = root:WaitForChild("CountGui", 10) :: BillboardGui?
	local home = cart:GetPivot()
	local endPos = K:GetAttribute("CartEnd") or (home.Position + Vector3.new(0, 0, -56))
	carts[K] = {
		Model = cart,
		Home = home,
		End = home + (endPos - home.Position),
		FlagLocal = root.CFrame:ToObjectSpace(flag.CFrame),
		Flag = flag,
		CountGui = countGui,
		AtHome = true,
		FlagUp = false,
	}
end

local function step()
	local now = Workspace:GetServerTimeNow()
	local workIdx = Players.LocalPlayer:GetAttribute("KitchenIndex")
	for K, c in carts do
		if not K.Parent or not c.Model.Parent then
			carts[K] = nil -- saiu do streaming; volta pelo ChildAdded
			continue
		end
		-- o contador "0/5" só aparece para quem trabalha nesta cozinha (dono ou convidado)
		if c.CountGui then
			local mine = workIdx ~= nil and workIdx ~= 0 and K:GetAttribute("KitchenIndex") == workIdx
			if c.CountGui.Enabled ~= mine then
				c.CountGui.Enabled = mine
			end
		end
		local state = K:GetAttribute("CartState") or "Home"
		local start = K:GetAttribute("CartStateStart") or 0
		local full = K:GetAttribute("CartFull") == true
		local cf
		if state == "ToKing" then
			local a = math.clamp((now - start) / (K:GetAttribute("CartTravel") or Config.Delivery.CartTravelTime), 0, 1)
			cf = c.Home:Lerp(c.End, ease(a))
		elseif state == "Returning" then
			local a = math.clamp((now - start) / (K:GetAttribute("CartReturn") or Config.Delivery.CartReturnTime), 0, 1)
			cf = c.End:Lerp(c.Home, ease(a))
		end
		if cf then
			c.Model:PivotTo(cf)
			c.AtHome = false
		elseif not c.AtHome then
			c.Model:PivotTo(c.Home)
			c.AtHome = true
		end
		-- bandeirinha sobe quando o carrinho está cheio
		local up = full and state ~= "Returning"
		if cf or up ~= c.FlagUp then
			c.FlagUp = up
			c.Flag.CFrame = c.Model:GetPivot() * c.FlagLocal * CFrame.new(0, if up then 1.3 else 0, 0)
		end
	end
end

function CartAnimator.Init()
	local folder = Workspace:WaitForChild("Kitchens")
	for _, K in folder:GetChildren() do
		task.spawn(track, K)
	end
	folder.ChildAdded:Connect(track)
	RunService.RenderStepped:Connect(step)
end

return CartAnimator
