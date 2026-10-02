-- ActionController: decide quais botões de ação aparecem (seção 2.3) e liga teclas/controle.
--   Segurando batata perto da mesa (4 studs): Descascar [F / RT] + Largar [G / B]
--   Descascando: Parar [Q / B]
--   Segurando batata descascada perto da esteira: Colocar na esteira [E / X]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local player = Players.LocalPlayer

local Actions = {}

local C
local visible = {}

local DEFS = {}
DEFS.Peel = {
	Id = "Peel",
	Label = Strings.Peel,
	Key = Enum.KeyCode.F,
	Pad = Enum.KeyCode.ButtonR2,
	KeyText = "F",
	PadText = "RT",
	Primary = true,
	Run = function()
		if not C.Kitchen.CanAcceptPotato() then
			C.HUD.Toast(Strings.EmptyBucket, C.HUD.Theme.RustBright)
			return
		end
		Remotes.PeelAction:FireServer("Start")
	end,
}
DEFS.Drop = {
	Id = "Drop",
	Label = Strings.Drop,
	Key = Enum.KeyCode.G,
	Pad = Enum.KeyCode.ButtonB,
	KeyText = "G",
	PadText = "B",
	Run = function()
		Remotes.PeelAction:FireServer("Drop")
	end,
}
DEFS.Stop = {
	Id = "Stop",
	Label = Strings.Stop,
	Key = Enum.KeyCode.Q,
	Pad = Enum.KeyCode.ButtonB,
	KeyText = "Q",
	PadText = "B",
	Run = function()
		Remotes.PeelAction:FireServer("Stop")
	end,
}
DEFS.Discard = {
	Id = "Discard",
	Label = Strings.Discard,
	Key = Enum.KeyCode.X,
	Pad = Enum.KeyCode.ButtonY,
	KeyText = "X",
	PadText = "Y",
	Run = function()
		Remotes.PeelAction:FireServer("Discard")
	end,
}
DEFS.Belt = {
	Id = "Belt",
	Label = Strings.PlaceOnBelt,
	Key = Enum.KeyCode.E,
	Pad = Enum.KeyCode.ButtonX,
	KeyText = "E",
	PadText = "X",
	Primary = true,
	Run = function()
		Remotes.PeelAction:FireServer("PlaceBelt")
	end,
}

local function compute()
	local state = player:GetAttribute("State")
	local list = {}
	if player:GetAttribute("InDuel") then
		return list -- no duelo não dá para parar nem soltar a batata
	end
	local near = C.Kitchen.DistanceToTable() <= Config.Interaction.PeelRange
	-- batata podre: descartar na lixeira da mesa
	if (state == "Holding" or state == "Peeling") and near and player:GetAttribute("HeldType") == "Podre" then
		table.insert(list, DEFS.Discard)
	end
	if state == "Holding" then
		if player:GetAttribute("HeldPeeled") then
			-- batata pronta: levar até o funil da esteira
			if C.Kitchen.DistanceToBelt() <= 10 then
				table.insert(list, DEFS.Belt)
			end
		elseif near then
			table.insert(list, DEFS.Peel)
		end
		table.insert(list, DEFS.Drop)
	elseif state == "Peeling" then
		table.insert(list, DEFS.Stop)
	end
	return list
end

function Actions.Init(controllers)
	C = controllers
	task.spawn(function()
		while true do
			visible = compute()
			C.HUD.SetActions(visible)
			task.wait(0.1)
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed and input.UserInputType == Enum.UserInputType.Keyboard then
			return -- digitando no chat
		end
		for _, a in visible do
			if input.KeyCode == a.Key or input.KeyCode == a.Pad then
				a.Run()
				return
			end
		end
	end)
end

return Actions
