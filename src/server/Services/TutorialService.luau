-- TutorialService: primeiros 3 minutos (seção 2.11), guiado pelo Chef Tubérculo.
--   1 pegar batata  -> 2 descascar a 1ª (faixa verde 2x, mão animada)
--   3 descascar mais 4 -> 4 levar o balde ao carrinho -> 5 enviar ao Rei
--   6 (entregou) o Chef completa o saldo até 150 e a loja destaca a Faca de cozinha
--   comprar a faca -> fim (100) e o primeiro pedido do Rei aparece no quadro.
-- O passo vive no save (Tutorial.Step) e é publicado no atributo TutorialStep.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Strings = require(ReplicatedStorage.Shared.Strings)
local Remotes = ReplicatedStorage.Remotes

local TutorialService = {}

local DONE = 100
local S

local function setStep(player: Player, step: number)
	local data = S.Data.Get(player)
	if not data then
		return
	end
	data.Tutorial.Step = step
	S.Session.Publish(player)
	S.Bus.Fire("TutorialStep", player, step)
	if step == DONE then
		S.Orders.StartFor(player, 0)
	end
end

local function step(player: Player): number
	local data = S.Data.Get(player)
	return data and data.Tutorial.Step or DONE
end

function TutorialService.Init(services)
	S = services

	-- saiu entre a compra e o fim: conclui na próxima entrada
	S.Bus.Connect("Loaded", function(player, data)
		if data.Tutorial.Step == 7 then
			setStep(player, DONE)
		end
	end)

	S.Bus.Connect("PotatoPicked", function(player)
		if step(player) == 1 then
			setStep(player, 2)
		end
	end)

	S.Bus.Connect("PotatoFinished", function(player)
		local st = step(player)
		if st ~= 2 and st ~= 3 then
			return
		end
		local data = S.Data.Get(player)
		data.Tutorial.Peeled += 1
		if data.Tutorial.Peeled >= Config.Tutorial.PotatoesToPeel then
			setStep(player, 4)
		else
			setStep(player, 3)
		end
	end)

	S.Bus.Connect("BeltPlaced", function(player)
		if step(player) == 4 then
			setStep(player, 5)
		end
	end)

	S.Bus.Connect("Delivered", function(player)
		local st = step(player)
		if st == 4 or st == 5 then
			-- o Rei aparece agradecendo e o Chef completa o saldo até 150
			Remotes.Reward:FireClient(player, "King", { Text = Strings.KingTutorial })
			task.wait(2.5)
			local missing = Config.Tutorial.TopUpCoins - S.Economy.Get(player)
			if missing > 0 then
				S.Economy.Add(player, missing, "Tutorial")
			end
			setStep(player, 6)
		end
	end)

	S.Bus.Connect("Purchased", function(player, itemId)
		if step(player) == 6 and itemId == Config.Tutorial.HighlightTool then
			setStep(player, 7)
			task.wait(6)
			setStep(player, DONE)
		end
	end)
end

return TutorialService
