-- Bus: eventos de jogo entre serviços do servidor (tutorial, pedidos, estatísticas)
-- sem que um serviço precise conhecer o outro.
--   PotatoPicked(player, P)      PotatoFinished(player, info)   ComboChanged(player, combo)
--   BucketDumped(player, count)  CartSent(player)               Delivered(player, amount, count)
--   Purchased(player, itemId)     MachinePotato(owner, item)

local Bus = {}

local listeners: { [string]: { (...any) -> () } } = {}

function Bus.Connect(name: string, fn: (...any) -> ())
	listeners[name] = listeners[name] or {}
	table.insert(listeners[name], fn)
end

function Bus.Fire(name: string, ...)
	for _, fn in listeners[name] or {} do
		task.spawn(fn, ...)
	end
end

function Bus.Init() end

return Bus
