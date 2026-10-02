# Descasca Batata (Potato Please — versão Roblox)

Jogo de Roblox inspirado no *Potato Please*: um campo de trabalho sombrio a serviço do Rei Glutão.
O jogador pega batatas do monte, descasca cada uma à mão, coloca na esteira e a esteira leva até o
carrinho, que vai ao Salão do Rei e paga em Moedas. Com as Moedas compra facas melhores e melhorias
da cozinha (carrinho maior, esteira mais rápida, descascador automático).

## Estrutura

| Pasta | Vai para | O que tem |
| --- | --- | --- |
| `src/server` | `ServerScriptService` | `Main` inicia os serviços em `Services/` (dados, economia, cozinha, esteira, descascar, pedidos, loja, social, eventos, monetização, retenção, analytics, menu de teste) |
| `src/client` | `StarterPlayer.StarterPlayerScripts` | `ClientMain` inicia os controladores em `Controllers/` (HUD, descascar livre, esteira, loja, diário, idiomas...) |
| `src/shared` | `ReplicatedStorage.Shared` | `Config` (todos os números de design), regras do descascar, textos e traduções (pt/en/es) |

Os `RemoteEvent`/`RemoteFunction` de `ReplicatedStorage.Remotes` são criados pelo `default.project.json`.

## Duelo de Descasque (PvP)

Arena a leste da praça (`Workspace.World.Arena`): dois jogadores sentam nas mesas frente a frente,
descascam por 60 s e quem fizer mais batatas vence (Moedas + ranking semanal "Duelos vencidos").
O guarda do Rei atira em quem perde. Só jogador contra jogador. Lógica em
`src/server/Services/DuelService.luau` e tela em `src/client/Controllers/DuelController.luau`.

## O que NÃO está aqui

O mapa (cozinhas, esteiras, pátio, Salão do Rei, terreno, cerca, torres) e os modelos/malhas
(`ServerStorage.Models`, `ReplicatedStorage.Art`) vivem no arquivo do place (`.rbxl`), não em código.
Para ter o jogo completo, salve o place pelo Studio (**Arquivo → Salvar em arquivo**) e mantenha o
`.rbxl` junto (ou publique no Roblox). Os scripts deste repositório são a fonte do código.

## Como usar com Rojo

1. Instale o [Rojo](https://rojo.space) (CLI e plugin do Studio).
2. Abra o place do jogo no Studio.
3. Nesta pasta, rode `rojo serve` e clique em **Connect** no plugin do Rojo.

## Testar

- **Play** no Studio. O botão amarelo **TESTE** (só no Studio, para o dono ou admins) dá moedas,
  ferramentas, melhorias, tipos de batata e reinicia o tutorial.
- DataStore, rankings e compras com Robux só funcionam com o place publicado e o acesso às APIs ligado.
- IDs de Game Passes e Developer Products ficam em `src/shared/Config.luau` (0 = ainda não criado).
