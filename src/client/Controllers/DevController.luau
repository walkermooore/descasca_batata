-- DevController: botão "TESTE" com atalhos para testar (moedas, itens, melhorias, tipos
-- de batata...). Só aparece se o servidor marcou o jogador com IsDev (Studio, dono ou Admin).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local player = Players.LocalPlayer

local Dev = {}

local C
local T
local panel: Frame
local toggle: TextButton

local BUTTONS = {
	{ "+1.000 moedas", "Coins", 1000 },
	{ "+100 mil moedas", "Coins", 100000 },
	{ "+10 mi moedas", "Coins", 10000000 },
	{ "Todas ferramentas e itens", "AllTools" },
	{ "Equipar a melhor faca", "BestTool" },
	{ "Voltar p/ faca cega", "StarterTool" },
	{ "Melhorias no máximo", "MaxUpgrades" },
	{ "Zerar melhorias", "ResetUpgrades" },
	{ "Encher o carrinho", "FillCart" },
	{ "Pular tutorial", "SkipTutorial" },
	{ "Reiniciar tutorial", "RestartTutorial" },
	{ "Próx.: dourada", "NextType", "Dourada" },
	{ "Próx.: grande", "NextType", "Grande" },
	{ "Próx.: torta", "NextType", "Torta" },
	{ "Próx.: podre", "NextType", "Podre" },
	{ "+5 chaves/fragmentos", "Keys" },
	{ "Todos os passes", "AllPasses" },
	{ "Meta de rebirth", "Delivered" },
	{ "Zerar progresso", "ResetProgress" },
}

local function build()
	local gui = C.HUD.Gui()
	toggle = Instance.new("TextButton")
	toggle.Name = "DevButton"
	toggle.AnchorPoint = Vector2.new(1, 0)
	toggle.Position = UDim2.new(1, -66, 0, 6)
	toggle.Size = UDim2.fromOffset(84, 46)
	toggle.Text = "TESTE"
	toggle.Font = T.Font
	toggle.TextScaled = true
	toggle.TextColor3 = Color3.fromRGB(20, 20, 20)
	toggle.BackgroundColor3 = Color3.fromRGB(214, 170, 40)
	toggle.Visible = false
	toggle.Parent = gui
	C.HUD.Corner(toggle, 8)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.Parent = toggle

	panel = Instance.new("Frame")
	panel.Name = "DevPanel"
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Position = UDim2.new(1, -12, 0, 58)
	panel.Size = UDim2.fromOffset(420, 390)
	panel.BackgroundColor3 = T.Panel
	panel.BackgroundTransparency = 0.04
	panel.Visible = false
	panel.ZIndex = 40
	panel.Parent = gui
	C.HUD.Corner(panel, 10)
	C.HUD.Stroke(panel, Color3.fromRGB(214, 170, 40), 2)
	local scale = Instance.new("UIScale")
	scale.Parent = panel
	local function fit()
		local vp = Workspace.CurrentCamera.ViewportSize
		scale.Scale = math.min(1, (vp.Y - 80) / 400, (vp.X - 30) / 430)
	end
	fit()
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	C.HUD.Label(panel, { Text = "MENU DE TESTE", Font = T.FontTitle, TextColor3 = T.Gold, Size = UDim2.new(1, -20, 0, 26), Position = UDim2.fromOffset(10, 6) })
	local grid = Instance.new("Frame")
	grid.BackgroundTransparency = 1
	grid.Position = UDim2.fromOffset(10, 38)
	grid.Size = UDim2.new(1, -20, 1, -48)
	grid.Parent = panel
	local gl = Instance.new("UIGridLayout")
	gl.CellSize = UDim2.new(0.5, -4, 0, 30)
	gl.CellPadding = UDim2.fromOffset(6, 5)
	gl.SortOrder = Enum.SortOrder.LayoutOrder
	gl.Parent = grid
	for i, spec in BUTTONS do
		local b = Instance.new("TextButton")
		b.LayoutOrder = i
		b.Text = spec[1]
		b.Font = T.Font
		b.TextScaled = true
		b.TextColor3 = T.Bone
		b.BackgroundColor3 = if spec[2] == "ResetProgress" then T.Blood else T.PanelLight
		b.Parent = grid
		C.HUD.Corner(b, 5)
		local p = Instance.new("UIPadding")
		p.PaddingTop = UDim.new(0, 5)
		p.PaddingBottom = UDim.new(0, 5)
		p.Parent = b
		b.Activated:Connect(function()
			local ok, res = pcall(function()
				return Remotes.DevRequest:InvokeServer(spec[2], spec[3])
			end)
			if ok and res and res.Text then
				C.HUD.Toast(res.Text, if res.Ok then T.Gold else T.RustBright)
			end
		end)
	end
	toggle.Activated:Connect(function()
		panel.Visible = not panel.Visible
	end)
end

function Dev.Init(controllers)
	C = controllers
	T = C.HUD.Theme
	build()
	local function refresh()
		toggle.Visible = player:GetAttribute("IsDev") == true
		if not toggle.Visible then
			panel.Visible = false
		end
	end
	player:GetAttributeChangedSignal("IsDev"):Connect(refresh)
	refresh()
end

return Dev
