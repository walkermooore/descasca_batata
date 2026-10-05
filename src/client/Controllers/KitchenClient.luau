-- KitchenClient: acesso à cozinha do jogador local e leitura dos atributos replicados.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Geo = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PotatoGeometry"))
local Config = require(ReplicatedStorage.Shared:WaitForChild("Config"))

local player = Players.LocalPlayer

local KitchenClient = {}

function KitchenClient.GetMine(): Model?
	local idx = player:GetAttribute("KitchenIndex")
	if not idx or idx == 0 then
		return nil
	end
	local folder = Workspace:FindFirstChild("Kitchens")
	return folder and folder:FindFirstChild("Kitchen" .. idx) :: Model?
end

-- Cozinha que o jogador possui (construção, alas, temas). GetMine = onde ele trabalha agora.
function KitchenClient.GetOwned(): Model?
	local idx = player:GetAttribute("OwnKitchenIndex")
	if not idx or idx == 0 then
		return nil
	end
	local folder = Workspace:FindFirstChild("Kitchens")
	return folder and folder:FindFirstChild("Kitchen" .. idx) :: Model?
end

function KitchenClient.TableTop(K: Model): BasePart
	return (K :: any).Station.Table.TableTop
end

function KitchenClient.DistanceToTable(): number
	local K = KitchenClient.GetMine()
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not K or not hrp then
		return math.huge
	end
	return Geo.DistanceToBox(KitchenClient.TableTop(K), hrp.Position)
end

function KitchenClient.CanAcceptPotato(): boolean
	return KitchenClient.GetMine() ~= nil -- a esteira substituiu o balde: sempre dá para descascar
end

-- Distância até o funil da esteira (onde a batata descascada é colocada).
function KitchenClient.DistanceToBelt(): number
	local K = KitchenClient.GetMine()
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local belt = K and K:FindFirstChild("Belt")
	local hopper = belt and belt:FindFirstChild("Hopper") :: BasePart?
	if not hopper or not hrp then
		return math.huge
	end
	return (hopper.Position - hrp.Position).Magnitude
end

-- A cozinha onde trabalho já tem esteira? (começa sem; é a primeira compra da aba Cozinha)
function KitchenClient.HasBelt(): boolean
	local K = KitchenClient.GetMine()
	return K ~= nil and K:GetAttribute("HasBelt") == true
end

-- Distância até o carrinho (sem esteira, a batata pronta vai na mão até ele).
function KitchenClient.DistanceToCart(): number
	local K = KitchenClient.GetMine()
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local cart = K and K:FindFirstChild("Cart")
	local root = cart and cart:FindFirstChild("Root") :: BasePart?
	if not root or not hrp then
		return math.huge
	end
	return (root.Position - hrp.Position).Magnitude
end

return KitchenClient
