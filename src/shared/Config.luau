-- Config: TODOS os números do GDD num só lugar, para balancear sem mexer em código.
-- Seções referem-se ao "GDD — Potato Please (versão Roblox)".

local Config = {}

Config.Version = "0.8.0 (Etapa 8: testes, segurança e idiomas)"

-- Ajustes de desenvolvimento (não são números de design)
Config.Dev = {
	-- Tipos sorteados na pilha (a Dourada tem sorteio próprio, seção 2.9)
	EnabledPotatoTypes = { "Comum", "Grande", "Torta", "Podre" },
	StartingTool = "FacaCega",
	StartingCoins = 0,
	DebugPeel = false, -- imprime cada passada no Output
}

-- Recursos ligados/desligados. Build = grade de máquinas nas alas (trocada pela esteira da cozinha).
Config.Features = {
	Build = false,
	DevMenu = true, -- menu de testes (só aparece no Studio, para o dono do jogo e para Admins)
}

-- 1. Ficha do jogo
Config.Server = {
	MaxPlayers = 12,
	KitchensPerServer = 6,
	MaxPlayersPerKitchen = 4,
}

-- 2.2 Estação de trabalho
Config.Station = {
	PileGapFromTable = 3, -- studs à esquerda da mesa
	PileMaxVisible = 30,
	PileRefillInterval = 0.5, -- s por batata
	TableSize = Vector3.new(6, 3, 3), -- 6 x 3 studs, altura 3
	TrayCapacity = 5,
	BucketCapacity = 10,
	CartCapacity = 5, -- nível 1; a melhoria "Carrinho maior" aumenta (Config.Upgrades)
	BeltMaxItems = 14, -- batatas na esteira ao mesmo tempo
	CartDistanceFromTable = 12,
	MaxLoosePotatoes = 80, -- 2.12 / 10: física por cozinha
}

-- 2.3 / 2.4 Interação e estados
Config.Interaction = {
	PromptRange = 8,
	PeelRange = 4, -- botão Descascar aparece a até 4 studs da mesa
	ServerRangeTolerance = 1.5, -- folga de latência na validação do servidor
	CarryBucketSpeedFactor = 0.8,
	HandsWithoutGloves = 1,
	HandsWithGloves = 2,
}

-- 2.5 Descascar
Config.Peel = {
	CameraTransition = 0.3,
	PotatoScreenHeight = 0.40, -- batata ocupa 40% da altura da tela
	CameraFieldOfView = 70,
	CloseupA = 1.2, -- semi-eixo longo da batata em close (studs)
	CloseupB = 0.8, -- semi-eixo curto

	MinCoverage = 0.70, -- passada precisa cobrir 70% da faixa
	MinDuration = 0.15, -- abaixo disso é descartada (anti-macro)
	MaxDuration = 1.0, -- acima disso é cancelada
	StripRotateTime = 0.15,
	StripDebrisLifetime = 3,
	MaxStrokesPerSecond = 5, -- humano chega a ~3/s; acima disso é script
	-- detector de bot: N passadas seguidas perfeitas com duração quase idêntica = suspeito (só registra)
	BotWindow = 30,
	BotDurationSpread = 0.02,

	Results = {
		Perfect = { MinPrecision = 0.90, Yield = 1.00 },
		Good = { MinPrecision = 0.60, Yield = 0.85 },
		Bad = { MinPrecision = 0.00, Yield = 0.60 },
	},

	ComboExpire = 5, -- s sem passada
	ComboTiers = {
		{ Min = 0, Mult = 1 },
		{ Min = 10, Mult = 1.5 },
		{ Min = 25, Mult = 2 },
		{ Min = 50, Mult = 3 },
		{ Min = 100, Mult = 4, RequiresToolTier = 4 }, -- só com Descascador duplo ou superior
	},
	ComboPitchStep = 2 ^ (2 / 12), -- "o som sobe um tom" a cada faixa de combo

	FinishGlowTime = 0.2,
	FinishFlyTime = 0.4,

	Assisted = { GreenBonus = 0.20, MaxYield = 0.85, ComboDisabled = true },
	TutorialGreenMultiplier = 2, -- 2.11 (Etapa 2)

	-- Descascar livre (como no Potato Please original): a faca tira uma tira de casca por onde
	-- passar, em qualquer direção; a batata gira nos dois eixos. Sem minigame.
	-- A casca é dividida em muitas faixas verticais finas: cada passada tira uma faixa, então é
	-- preciso girar a batata e passar várias vezes. Passar onde já não tem casca raspa a polpa
	-- e só tira pontos (rendimento). Passadas limpas seguidas sobem o combo.
	Free = {
		Segments = 12, -- pedaços ao longo de cada coluna (de ponta a ponta)
		Layers = 1, -- uma passada tira a casca daquele pedaço
		KnifeWidth = 2, -- faixas que a faca pega de uma vez (ferramentas melhores pegam mais)
		FinishFraction = 0.9, -- com 90% da casca tirada a batata está pronta
		FleshPenalty = 0.005, -- cada pedaço de polpa raspado tira 0,5%
		BadPenalty = 0.02, -- passada que foi quase só polpa tira mais 2%
		MinYield = 0.5,
		CleanMinHits = 4, -- passada limpa (combo +1): tirou pelo menos 4 camadas sem raspar polpa
		MaxPatchesPerSecond = 200, -- anti-script (grade fina: uma passada toca muitos pedaços)
		MinDuration = 0.05,
		MaxDuration = 2.5,
		ChunkSeconds = 1.0, -- arrasto longo é enviado em pedaços de 1 s
		RotateSpeed = 2.6, -- rad/s ao girar com A/D
		TiltSpeed = 1.8, -- rad/s ao inclinar com W/S
		MaxTilt = math.rad(75), -- dá para virar a ponta de cima/baixo para a câmera
	},
}

-- 2.6 Balde, carrinho e entrega
Config.Delivery = {
	DumpTime = 1,
	CartTravelTime = 8,
	CartReturnTime = 4,
	GiantBucketBonus = 0.5, -- passe Balde Gigante
	BigBucketCapacity = 25,
	TankCapacity = 100,
}

-- 2.7 Tipos de batata
Config.Potatoes = {
	-- casca terrosa e fosca (SkinMaterial) contra a polpa clara e lisa: dá para ver o que já foi descascado
	Comum = {
		Name = "Batata", Chance = 0.80, Strips = 16, BaseValue = 12, WorldScale = 1, CloseupA = 1.2, CloseupB = 0.8,
		SkinColor = Color3.fromRGB(112, 76, 44), SpotColor = Color3.fromRGB(58, 38, 22), FleshColor = Color3.fromRGB(190, 170, 124), SkinMaterial = "Ground",
	},
	Grande = {
		Name = "Batata grande", Plural = "batatas grandes", Chance = 0.12, Strips = 20, BaseValue = 25, WorldScale = 1.5, CloseupA = 1.2, CloseupB = 1.0,
		SkinColor = Color3.fromRGB(104, 70, 42), SpotColor = Color3.fromRGB(56, 36, 22), FleshColor = Color3.fromRGB(190, 170, 124), SkinMaterial = "Ground",
	},
	Torta = {
		Name = "Batata torta", Plural = "batatas tortas", Chance = 0.06, Strips = 16, BaseValue = 18, WorldScale = 1, CloseupA = 1.25, CloseupB = 0.78,
		WobbleAmplitude = 0.20, WobblePeriod = 1.2, -- faixa verde oscila 20% da largura, ciclo 1,2 s
		SkinColor = Color3.fromRGB(116, 58, 40), SpotColor = Color3.fromRGB(64, 30, 22), FleshColor = Color3.fromRGB(190, 170, 124), SkinMaterial = "Ground",
	},
	Podre = {
		Name = "Batata podre", Chance = 0.018, Strips = 16, BaseValue = 0, DiscardValue = 15, WorldScale = 1, CloseupA = 1.2, CloseupB = 0.8,
		-- pode ser descascada, mas a 1ª passada zera o combo e a batata passa a valer 0
		SkinColor = Color3.fromRGB(120, 110, 130), SpotColor = Color3.fromRGB(80, 110, 60), FleshColor = Color3.fromRGB(150, 140, 110),
	},
	Dourada = {
		Name = "Batata dourada", Chance = 0.002, Strips = 16, BaseValue = 400, WorldScale = 1, CloseupA = 1.2, CloseupB = 0.8,
		SkinColor = Color3.fromRGB(240, 196, 60), SpotColor = Color3.fromRGB(255, 240, 150), FleshColor = Color3.fromRGB(255, 252, 240),
	},
}
Config.PotatoOrder = { "Comum", "Grande", "Torta", "Podre", "Dourada" }

-- 2.8 Pedidos do Rei
Config.Orders = {
	Interval = 180,
	MaxActivePerPlayer = 1,
	RewardMultiplier = 2,
	Pool = {
		{ Id = "Qty15", Kind = "Count", Count = 15, Time = 120 },
		{ Id = "Big5", Kind = "CountType", Type = "Grande", Count = 5, Time = 180 },
		{ Id = "Clean15", Kind = "CountYield", Yield = 0.95, Count = 15, Time = 240 },
		{ Id = "Qty25", Kind = "Count", Count = 25, Time = 180 },
	},
	-- "Cada rebirth muda o cardápio do Rei": pedidos extras a partir do rebirth indicado
	RebirthPool = {
		{ Id = "Torta8", Kind = "CountType", Type = "Torta", Count = 8, Time = 300, MinRebirths = 1 },
		{ Id = "Qty40", Kind = "Count", Count = 40, Time = 240, MinRebirths = 1 },
		{ Id = "Clean30", Kind = "CountYield", Yield = 0.95, Count = 30, Time = 300, MinRebirths = 2 },
		{ Id = "Big15", Kind = "CountType", Type = "Grande", Count = 15, Time = 300, MinRebirths = 3 },
	},
}

-- 2.9 Batatas douradas
Config.Golden = {
	BaseChance = 1 / 500,
	LaserChance = 1 / 400,
	LuckPassBonus = 0.5,
	GoldenHourMultiplier = 5,
	KeyChance = 0.30, -- 70% fragmento
	ChestProductionMinutes = 30,
	ChestMinimum = 500,
	FragmentsPerRoom = 5,
	RoomOpen = false, -- Horta Proibida fechada por enquanto (portão do lobby mostra "EM BREVE")
	RoomCoinBonus = 0.05,
}

-- 2.10 / 3 Automação
Config.MachineRules = {
	MaxYield = 0.85, -- batata de máquina nunca passa de 85% nem recebe combo
	BaseValue = 12, -- valor base de uma batata de máquina (Comum)
	CostGrowth = 1.15, -- custo de cada nível cresce x1,15
	ProductionGrowth = 1.10, -- produção de cada nível cresce x1,10
	UpgradeCostFactor = 0.25, -- nível 2 custa 25% do preço da máquina (ASSUNÇÃO: o GDD não define)
	MaxLevel = 10,
	TickInterval = 1,
	MaxHelpers = 2, -- vagas de Ajudante (+2 com o passe Mais Ajudantes)
}

-- Grade das alas (3. "expandido em 4 alas"): células de 4 studs, 7 colunas x 3 linhas por ala.
-- A coluna 6 de cada linha é a Calha da pilha (fonte de batatas cruas).
Config.Grid = {
	Cell = 4,
	Cols = 7,
	RowsPerWing = 3,
	Wings = 4,
	SourceCol = 6,
	WingCosts = { 10000, 50000, 200000, 800000 }, -- ASSUNÇÃO: o GDD não define
}
-- Kind: Helper (independente, vai ao balde), Peeler (cru -> descascada), Washer (lava),
-- Processor (multiplica valor), Tank (recebe lavadas e despeja no carrinho), Conveyor.
Config.Machines = {
	{ Id = "Ajudante", Kind = "Helper", Name = "Ajudante aprendiz", Cost = 20000, PerMinute = 4, Desc = "Ocupa uma mesa extra, pega da pilha e descasca 4 batatas/min direto no balde." },
	{ Id = "Tanque", Kind = "Tank", Name = "Tanque", Cost = 15000, Capacity = 100, NoLevels = true, Desc = "Recebe batatas lavadas e despeja no carrinho por um cano. Com ele, o carrinho parte sozinho." },
	{ Id = "Esteira", Kind = "Conveyor", Name = "Esteira (segmento)", Cost = 5000, NoLevels = true, Desc = "Leva batatas de uma célula para a próxima, na direção da seta." },
	{ Id = "Tambor", Kind = "Peeler", Name = "Tambor descascador", Cost = 80000, PerMinute = 15, Desc = "Recebe batatas da Calha por esteira e descasca 15/min (rendimento 85%)." },
	{ Id = "Lavadora", Kind = "Washer", Name = "Lavadora automática", Cost = 150000, PerMinute = 30, Desc = "Lava 30/min. Só batata lavada entra no Tanque; sem ela, o tambor despeja no balde." },
	{ Id = "LinhaCorte", Kind = "Processor", Name = "Linha de corte", Cost = 500000, PerMinute = 20, ValueMultiplier = 3, Desc = "20 batatas descascadas/min viram fritas: valem 3x." },
	{ Id = "FabricaPure", Kind = "Processor", Name = "Fábrica de purê", Cost = 2000000, PerMinute = 40, ValueMultiplier = 5, Desc = "40 batatas descascadas/min viram purê: valem 5x." },
}
Config.MachinesById = {}
for _, m in Config.Machines do
	Config.MachinesById[m.Id] = m
end

-- 3. Ferramentas de mão (Tier = cor de tier da seção 7.1)
Config.Tools = {
	{ Id = "FacaCega", Name = "Faca cega", Cost = 0, Tier = 1, StripsPerStroke = 1, GreenWidth = 0.30, Desc = "Lâmina lascada. Melhor que nada." },
	{ Id = "FacaCozinha", Name = "Faca de cozinha", Cost = 120, Tier = 2, StripsPerStroke = 1, GreenWidth = 0.40, ValueBonus = 0.10, Desc = "Lâmina afiada: corte mais limpo e +10% no valor de cada batata." },
	{ Id = "DescascadorY", Name = "Descascador em Y", Cost = 600, Tier = 3, StripsPerStroke = 2, GreenWidth = 0.45, RotateTime = 0.10, Desc = "Tira 2 faixas por passada." },
	{ Id = "DescascadorDuplo", Name = "Descascador duplo", Cost = 4000, Tier = 4, StripsPerStroke = 3, GreenWidth = 0.55, Desc = "Tira 3 faixas por passada." },
	{ Id = "LaminaVapor", Name = "Lâmina a vapor", Cost = 25000, Tier = 5, StripsPerStroke = 4, GreenWidth = 0.60, CompostPerStrip = 1, Desc = "Tira 4 faixas. Cada faixa vira adubo (+1 Moeda)." },
	{ Id = "Laser", Name = "Laser de cozinha", Cost = 150000, Tier = 6, StripsPerStroke = 6, GreenWidth = 0.70, GoldenChance = 1 / 400, Desc = "Tira 6 faixas. Batata dourada: 1 em 400." },
}
Config.ToolsById = {}
for _, t in Config.Tools do
	Config.ToolsById[t.Id] = t
end

Config.Collection = {
	{ Id = "Luvas", Name = "Luvas", Cost = 250, Hands = 2, Tab = "Ferramentas", Desc = "Segure 2 batatas. Ao terminar uma, ela vai sozinha para a esteira e a segunda já entra no modo Descascar." },
	{ Id = "CarrinhoMao", Name = "Carrinho de mão", Cost = 1500, Stock = 20, Tab = "Ferramentas", Desc = "Leva 20 batatas da pilha. Cada uma pronta vai sozinha para a esteira e a próxima já vem para a mão." },
	{ Id = "Aspirador", Name = "Aspirador de batata", Cost = 8000, Radius = 6, Tab = "Ferramentas", Desc = "Puxa batatas soltas num raio de 6 studs." },
}

-- Melhorias da cozinha (compradas na Loja, aba Cozinha). Nível 1 é o inicial (sem custo).
Config.Upgrades = {
	{
		Id = "Cart", Name = "Carrinho maior", Unit = "batatas por viagem",
		Desc = "Mais batatas por viagem ao Rei.",
		Levels = { { Value = 5 }, { Value = 10, Cost = 80 }, { Value = 20, Cost = 400 }, { Value = 35, Cost = 1500 }, { Value = 50, Cost = 5000 }, { Value = 80, Cost = 20000 }, { Value = 120, Cost = 80000 }, { Value = 180, Cost = 250000 }, { Value = 260, Cost = 800000 }, { Value = 380, Cost = 2500000 }, { Value = 500, Cost = 8000000 } },
	},
	{
		Id = "AutoSend", Name = "Despacho automático", Unit = "", Toggle = true,
		Desc = "Um sino no carrinho: quando ele enche, parte sozinho para o Rei. Sem ele, aperte Enviar.",
		Levels = { { Value = 0 }, { Value = 1, Cost = 400 } },
	},
	{
		Id = "Feeder", Name = "Alimentador automático", Unit = "", Toggle = true,
		Desc = "Uma calha traz a próxima batata direto para a sua mão e a pronta vai sozinha para a esteira. É só descascar.",
		Levels = { { Value = 0 }, { Value = 1, Cost = 700 } },
	},
	{
		Id = "Belt", Name = "Esteira mais rápida", Unit = "studs/s",
		Desc = "A esteira leva as batatas até o carrinho mais depressa.",
		Levels = { { Value = 3 }, { Value = 4.5, Cost = 100 }, { Value = 6.5, Cost = 500 }, { Value = 9, Cost = 2500 }, { Value = 13, Cost = 12000 } },
	},
	{
		Id = "Washer", Name = "Lavadora na esteira", Unit = "% de valor",
		Desc = "As batatas tomam um banho no caminho do carrinho e valem mais.",
		Levels = { { Value = 0 }, { Value = 25, Cost = 300 }, { Value = 50, Cost = 1500 }, { Value = 100, Cost = 8000 }, { Value = 150, Cost = 40000 } },
	},
	{
		Id = "AutoPeel", Name = "Descascador automático", Unit = "batatas/min",
		Desc = "Uma máquina ao lado da esteira descasca sozinha, mesmo com você fora (rendimento 85%).",
		Levels = { { Value = 0 }, { Value = 2, Cost = 500 }, { Value = 5, Cost = 2500 }, { Value = 10, Cost = 10000 }, { Value = 20, Cost = 40000 }, { Value = 40, Cost = 150000 }, { Value = 70, Cost = 500000 } },
	},
	{
		Id = "Cutter", Name = "Cortador de fritas", Unit = "x valor",
		Desc = "Corta as batatas em fritas antes do carrinho. Fritas valem mais para o Rei.",
		Levels = { { Value = 1 }, { Value = 1.5, Cost = 2000 }, { Value = 2, Cost = 10000 }, { Value = 3, Cost = 50000 }, { Value = 5, Cost = 250000 } },
	},
	{
		Id = "Drum", Name = "Tambor descascador", Unit = "batatas/min",
		Desc = "Um tambor giratório enorme que descasca muitas batatas de uma vez e despeja na esteira.",
		Levels = { { Value = 0 }, { Value = 15, Cost = 20000 }, { Value = 35, Cost = 80000 }, { Value = 70, Cost = 300000 }, { Value = 140, Cost = 1200000 } },
	},
	{
		Id = "Masher", Name = "Amassador de purê", Unit = "x valor",
		Desc = "Vira as batatas em purê para o banquete do Rei antes do carrinho. Purê vale muito mais.",
		Levels = { { Value = 1 }, { Value = 1.5, Cost = 40000 }, { Value = 2, Cost = 200000 }, { Value = 3, Cost = 1000000 } },
	},
}
Config.UpgradesById = {}
for _, u in Config.Upgrades do
	Config.UpgradesById[u.Id] = u
end
Config.CollectionById = {}
for _, c in Config.Collection do
	Config.CollectionById[c.Id] = c
end

-- 6. Loja (abas)
Config.ShopTabs = {
	{ Id = "Ferramentas", Label = "Ferramentas" },
	{ Id = "Cozinha", Label = "Cozinha" },
	{ Id = "Passes", Label = "Passes" },
	{ Id = "Cosmeticos", Label = "Cosméticos" },
}

-- 2.11 Tutorial
Config.Tutorial = {
	PotatoesToPeel = 3, -- a 1ª com ajuda + 2 sem ajuda (começo mais leve)
	TopUpCoins = 120,
	HighlightTool = "FacaCozinha",
	HandStrips = 2, -- mão animada nas 2 primeiras faixas
}

-- 10. Dados
Config.Data = {
	StoreName = "SpudShift_Player_v1",
	LockStaleSeconds = 180, -- trava sem autosave há 3 min é considerada abandonada
	LoadRetries = 6,
	RetryWait = 5,
}

-- 3. Rebirth "Nova Temporada"
Config.Rebirth = {
	-- GDD: 1.000.000. Com carrinho de 50 e viagem de 8 s + 4 s o teto é ~250 batatas/min,
	-- então 1M levaria ~66 h (o GDD quer 2-3 h). Ajustado até rebalancear:
	PotatoesRequired = 10000,
	MultiplierPerRebirth = 0.25, -- +25% permanente por rebirth
	SeedsBase = 10, -- Sementes de Ouro por rebirth (ASSUNÇÃO)
	SeedsPerExtra = 1000, -- +1 Semente a cada 1.000 batatas além da meta
	Themes = { "Castelo", "NavioPirata", "EstacaoEspacial", "Vulcao" },
}

-- Talentos comprados com Sementes de Ouro
Config.Talents = {
	{ Id = "MaoLeve", Name = "Mão leve", Desc = "-20% de perda ao raspar polpa por nível.", PerLevel = 0.2, Costs = { 3, 6, 12, 24 } },
	{ Id = "MaquinasBaratas", Name = "Máquinas mais baratas", Desc = "-8% no custo de máquinas e melhorias por nível.", PerLevel = 0.08, Costs = { 4, 8, 16, 32, 64 } },
	{ Id = "SorteDourada", Name = "Sorte dourada", Desc = "+15% de chance de batata dourada por nível.", PerLevel = 0.15, Costs = { 3, 6, 12, 24, 48 } },
	{ Id = "EspacoExtra", Name = "Espaço extra", Desc = "Cada temporada começa com +1 ala liberada por nível.", PerLevel = 1, Costs = { 5, 15, 40, 100 } },
}
Config.TalentsById = {}
for _, t in Config.Talents do
	Config.TalentsById[t.Id] = t
end

-- 7.7 Cozinhas temáticas (trocam só paredes, piso, acabamento e luz). Versões sombrias.
Config.Themes = {
	-- Tema inicial no estilo do Potato Please original: bunker militar, parede em dois tons
	-- (reboco bege em cima, verde-escuro embaixo), piso de concreto, luz fluorescente fria.
	Castelo = { Name = "Bunker de Descascamento", Rebirths = 0, Wall = { "Plaster", Color3.fromRGB(150, 140, 120) }, Lower = { "Plaster", Color3.fromRGB(44, 60, 50) }, Floor = { "Concrete", Color3.fromRGB(70, 68, 64) }, Trim = { "Metal", Color3.fromRGB(46, 52, 50) }, Light = Color3.fromRGB(175, 228, 240) },
	NavioPirata = { Name = "Porão do Navio Pirata", Rebirths = 1, Lower = { "Wood", Color3.fromRGB(38, 28, 20) }, Wall = { "WoodPlanks", Color3.fromRGB(50, 36, 26) }, Floor = { "WoodPlanks", Color3.fromRGB(42, 32, 22) }, Trim = { "Wood", Color3.fromRGB(33, 24, 18) }, Light = Color3.fromRGB(255, 170, 90) },
	EstacaoEspacial = { Name = "Estação Espacial", Rebirths = 2, Lower = { "Metal", Color3.fromRGB(40, 46, 54) }, Wall = { "DiamondPlate", Color3.fromRGB(58, 63, 68) }, Floor = { "Metal", Color3.fromRGB(44, 46, 51) }, Trim = { "CorrodedMetal", Color3.fromRGB(52, 68, 82) }, Light = Color3.fromRGB(130, 170, 255) },
	Vulcao = { Name = "Cozinha do Vulcão", Rebirths = 3, Lower = { "CrackedLava", Color3.fromRGB(70, 30, 20) }, Wall = { "Basalt", Color3.fromRGB(34, 28, 27) }, Floor = { "Slate", Color3.fromRGB(39, 32, 28) }, Trim = { "CrackedLava", Color3.fromRGB(120, 50, 30) }, Light = Color3.fromRGB(255, 100, 40) },
}

-- 4. Economia
Config.Economy = {
	OfflineHoursFree = 2,
	OfflineHoursPass = 8,
	OfflineRate = 0.25,
	AutosaveInterval = 60,
}

-- 5. Social
Config.Social = {
	HelperShare = 0.30, -- cada ajudante recebe 30% do que produziu, sem descontar do dono
	TeamBonusPerFriend = 0.10, -- +10% de produção por amigo na cozinha
	TeamBonusMax = 0.30,
	InviteSeconds = 30,
	LikesPerDay = 1, -- cada jogador curte cada cozinha 1x por dia
	PingCooldown = 2,
}

-- Pedido Gigante do Rei: evento de servidor com meta comum; ao bater a meta, todos ganham um baú.
Config.GiantOrder = {
	Interval = 20 * 60,
	FirstDelay = 8 * 60, -- primeiro evento após o servidor abrir (ASSUNÇÃO)
	Duration = 5 * 60, -- ASSUNÇÃO: o GDD não define a duração
	GoalPerPlayer = 40,
	MinGoal = 60,
	RewardMinutes = 15, -- baú = 15 min da produção automática, mínimo abaixo
	RewardMin = 500,
	KingSteps = 5, -- o Rei cresce em 5 etapas
	KingMaxScale = 1.6,
}

-- Corrida de Descascar: 60 s, 1v1 até 4 jogadores; vence quem descascar mais com precisão.
-- Pontos = soma do rendimento das faixas descascadas à mão durante a corrida.
Config.Race = {
	Duration = 60,
	MinPlayers = 2,
	MaxPlayers = 4,
	LobbySeconds = 15,
	Rewards = { 600, 300, 150, 75 },
	LeaveDistance = 30, -- studs: quem entrou pelo portal e se afasta disso sai da fila
}

-- Zona proibida em frente ao castelo do Rei: aviso ao entrar; quem fica Grace segundos leva tiro.
Config.Castle = {
	ZoneMaxZ = -54, -- z menor que isto = perto do castelo
	ZoneMinX = -110,
	ZoneMaxX = 110,
	Grace = 3, -- s (contagem vermelha na tela)
}

-- Duelo de Descasque (arena ao lado do lobby): dois jogadores em mesas frente a frente;
-- quem descascar mais batatas no tempo vence. O guarda do Rei atira em quem perder.
Config.Duel = {
	Duration = 60, -- s de descasque
	Countdown = 4, -- s de contagem antes de começar
	WinCoins = 250, -- prêmio base de quem vence
	StreakBonus = 50, -- +50 por vitória seguida
	MaxStreakBonus = 500,
	TieCoins = 60, -- empate: os dois ganham isto e ninguém leva tiro
	ShotDelay = 1.6, -- s entre o resultado e o tiro
	SeatRange = 9, -- se o jogador se afastar mais que isto da mesa, desiste

}

-- Rankings (OrderedDataStore). Semana começa na segunda-feira 00:00 UTC.
Config.Rankings = {
	Boards = {
		{ Id = "Clean", Label = "Batatas perfeitas da semana", Weekly = true },
		{ Id = "Duels", Label = "Duelos vencidos na semana", Weekly = true },
		{ Id = "Race", Label = "Corrida da semana", Weekly = true },
		{ Id = "Rebirths", Label = "Rebirths", Weekly = false },
	},
	Top = 10,
	RefreshSeconds = 90,
	MaxFriends = 30,
}

Config.Pings = {
	{ Id = "Help", Text = "Ajuda aqui!" },
	{ Id = "Bucket", Text = "Esteira cheia!" },
	{ Id = "Thanks", Text = "Valeu!" },
	{ Id = "Go", Text = "Bora descascar!" },
	{ Id = "King", Text = "O Rei tá com fome!" },
}
Config.Emotes = { "wave", "point", "cheer", "dance" }

-- 7.1 Cores de tier
Config.TierColors = {
	Color3.fromRGB(150, 150, 150), -- cinza
	Color3.fromRGB(133, 94, 66), -- marrom
	Color3.fromRGB(90, 170, 80), -- verde
	Color3.fromRGB(70, 130, 220), -- azul
	Color3.fromRGB(150, 80, 200), -- roxo
	Color3.fromRGB(235, 190, 50), -- dourado
}
-- "Faixa verde intocável": nenhuma skin pode mudar essa cor.
Config.GreenZoneColor = Color3.fromRGB(70, 215, 90)

-- 8. Monetização (preços em Robux; entra na Etapa 6)
Config.GamePasses = {
	-- PassId = 0: ainda não criado no Creator Hub (aparece como "Em breve" e fica desligado).
	-- OfferAt: momento de "dor" em que o jogo pode oferecer o passe (seção 8).
	{ Id = "KitInicial", PassId = 0, Name = "Kit Inicial do Aprendiz", Price = 99, OfferAt = "FirstDelivery", Desc = "Faca de cozinha, luvas e 5.000 Moedas." },
	{ Id = "BaldeGigante", PassId = 0, Name = "Balde Gigante", Price = 149, OfferAt = "BucketFull", Desc = "+50% de capacidade no carrinho." },
	{ Id = "CarrocaReal", PassId = 0, Name = "Carroça Real", Price = 249, CapacityBonus = 1, Desc = "+100% de capacidade no carrinho (soma com o Balde Gigante)." },
	{ Id = "CarrinhoTurbo", PassId = 0, Name = "Carrinho Turbo", Price = 99, SpeedBonus = 0.40, OfferAt = "WingBought", Desc = "+40% de velocidade ao andar e no carrinho." },
	{ Id = "GanhoOffline8h", PassId = 0, Name = "Ganho Offline 8h", Price = 199, OfferAt = "OfflineReturn", Desc = "Ganho offline passa de 2h para 8h." },
	{ Id = "AutoDescascar", PassId = 0, Name = "Auto-Descascar", Price = 249, OfferAt = "Played30", Desc = "Segurar o botão descasca sozinho (rendimento máx. 85%)." },
	{ Id = "MaisAjudantes", PassId = 0, Name = "Mais Ajudantes", Price = 299, ExtraSlots = 2, OfferAt = "FirstHelper", Desc = "+2 vagas de ajudante." },
	{ Id = "VIP", PassId = 0, Name = "VIP da Cozinha Real", Price = 299, CoinBonus = 0.20, OfferAt = "FirstRebirth", Desc = "+20% Moedas, tag no chat, área VIP." },
	{ Id = "SorteDourada", PassId = 0, Name = "Sorte Dourada", Price = 349, GoldenBonus = 0.5, OfferAt = "FirstGolden", Desc = "+50% de chance de batata dourada." },
	{ Id = "MoedasX2", PassId = 0, Name = "Moedas x2", Price = 399, CoinMultiplier = 2, Desc = "Dobra todas as Moedas, para sempre." },
	{ Id = "ChefLendario", PassId = 0, Name = "Chef Lendário", Price = 199, Desc = "Chapéu de chef dourado e rastro brilhante ao andar." },
	{ Id = "BatataPet", PassId = 0, Name = "Batata de Estimação", Price = 149, Desc = "Uma batatinha de chapéu que segue você por todo o acampamento." },
	{ Id = "FacaDeOuro", PassId = 0, Name = "Faca de Ouro do Rei", Price = 129, Desc = "Sua faca vira ouro e solta faíscas ao descascar (só visual)." },
	{ Id = "CarrinhoDeOuro", PassId = 0, Name = "Carrinho de Ouro", Price = 99, Desc = "O carrinho da sua cozinha brilha em ouro (só visual)." },
	{ Id = "Duelista", PassId = 0, Name = "Duelista do Rei", Price = 199, DuelCoinBonus = 1, Desc = "+100% de Moedas ao vencer duelos e coroa de duelista na cabeça." },
	{ Id = "MaquinasTurbo", PassId = 0, Name = "Máquinas Turbo", Price = 249, AutoBonus = 0.5, Desc = "Descascador automático e tambor produzem +50% batatas." },
}
Config.GamePassesById = {}
for _, p in Config.GamePasses do
	Config.GamePassesById[p.Id] = p
end

-- Developer Products (seção 8). ProductId = 0: ainda não criado no Creator Hub.
Config.Products = {
	{ Id = "SacoP", ProductId = 0, Name = "Saco de Moedas P", Price = 49, Minutes = 15, Desc = "15 min da sua produção atual." },
	{ Id = "SacoM", ProductId = 0, Name = "Saco de Moedas M", Price = 149, Minutes = 60, Desc = "1 hora da sua produção atual." },
	{ Id = "SacoG", ProductId = 0, Name = "Saco de Moedas G", Price = 399, Minutes = 240, Desc = "4 horas da sua produção atual." },
	{ Id = "SacoXG", ProductId = 0, Name = "Saco de Moedas XG", Price = 999, Minutes = 720, Desc = "12 horas da sua produção atual." },
	{ Id = "Boost2", ProductId = 0, Name = "Boost x2 (30 min)", Price = 39, BoostMult = 2, BoostMinutes = 30, Desc = "Dobra a produção por 30 minutos." },
	{ Id = "Boost3", ProductId = 0, Name = "Boost x3 (60 min)", Price = 99, BoostMult = 3, BoostMinutes = 60, Desc = "Triplica a produção por 1 hora." },
	{ Id = "Bussola", ProductId = 0, Name = "Bússola Dourada", Price = 49, GoldenWithin = 50, Desc = "Garante uma batata dourada nas próximas 50." },
	{ Id = "PedidoRelampago", ProductId = 0, Name = "Pedido Relâmpago", Price = 25, Desc = "Chama um pedido especial do Rei agora." },
	{ Id = "PassePremium", ProductId = 0, Name = "Passe de Temporada Premium", Price = 499, Desc = "Trilha premium do passe de temporada." },
	{ Id = "CaixaDourada", ProductId = 0, Name = "Caixa de Batatas Douradas", Price = 99, GoldenNext = 3, Desc = "As próximas 3 batatas que você pegar serão douradas." },
	{ Id = "DespachoExpresso", ProductId = 0, Name = "Despacho Expresso", Price = 25, ExpressTrips = 10, Desc = "As próximas 10 viagens do carrinho vão e voltam na hora." },
	{ Id = "Banquete", ProductId = 0, Name = "Banquete do Rei", Price = 199, ServerBoostMult = 2, ServerBoostMinutes = 15, Desc = "O SERVIDOR INTEIRO ganha Moedas x2 por 15 min, e seu nome é anunciado." },
}
Config.ProductsById = {}
for _, p in Config.Products do
	Config.ProductsById[p.Id] = p
end

-- Assinatura "Clube do Chef" (ID de assinatura do Creator Hub, formato "EXP-..."; vazio = desligada)
Config.Subscription = {
	Id = "",
	Name = "Clube do Chef",
	ProductionBonus = 0.10,
	DailyBoostMult = 2,
	DailyBoostMinutes = 30,
	Desc = "1 Boost x2 por dia, +10% de produção, avental exclusivo do mês, baú diário extra.",
}

-- Regras de oferta (seção 8): nada nos primeiros 5 min; no máximo 1 pop-up por sessão; sempre fechável.
Config.Offers = {
	NoOffersFirstSeconds = 5 * 60,
	MaxPopupsPerSession = 1,
}

-- ---------------------------------------------------------------- 9. Retenção e LiveOps

-- Login diário: 7 dias crescentes; o 7º dá um cosmético. Perder um dia não zera, só pausa.
Config.Login = {
	Rewards = {
		{ Coins = 500 }, { Coins = 1000 }, { Coins = 1500, Keys = 1 }, { Coins = 2500 },
		{ Coins = 4000, Boost = { Mult = 2, Minutes = 15 } }, { Coins = 6000 },
		{ Coins = 8000, Cosmetic = "AventalDoRei" },
	},
}

-- Missões: 3 diárias e 5 semanais sorteadas destes pools. Kind = o que conta progresso.
Config.Missions = {
	DailyCount = 3,
	WeeklyCount = 5,
	Daily = {
		{ Id = "Clean10", Kind = "Clean", Target = 10, Text = "Descasque 10 batatas quase perfeitas (95%+)", Coins = 800, XP = 60 },
		{ Id = "Peel25", Kind = "Peel", Target = 25, Text = "Descasque 25 batatas à mão", Coins = 1000, XP = 60 },
		{ Id = "Deliver40", Kind = "Deliver", Target = 40, Text = "Entregue 40 batatas ao Rei", Coins = 1200, XP = 60 },
		{ Id = "Earn3000", Kind = "Earn", Target = 3000, Text = "Ganhe 3.000 Moedas com entregas", Coins = 900, XP = 60 },
		{ Id = "Cart6", Kind = "Cart", Target = 6, Text = "Mande 6 carrinhos cheios ao Rei", Coins = 800, XP = 50 },
		{ Id = "Upgrade1", Kind = "Upgrade", Target = 1, Text = "Compre 1 melhoria da cozinha", Coins = 700, XP = 50 },
		{ Id = "Order1", Kind = "Order", Target = 1, Text = "Cumpra 1 pedido do Rei", Coins = 900, XP = 60 },
		{ Id = "Help10", Kind = "HelpMinutes", Target = 10, Text = "Ajude um amigo por 10 min", Coins = 1000, XP = 70 },
		{ Id = "Discard1", Kind = "Discard", Target = 1, Text = "Jogue uma batata podre na lixeira", Coins = 500, XP = 40 },
	},
	Weekly = {
		{ Id = "Clean150", Kind = "Clean", Target = 150, Text = "Descasque 150 batatas quase perfeitas (95%+)", Coins = 8000, XP = 250 },
		{ Id = "Earn50000", Kind = "Earn", Target = 50000, Text = "Ganhe 50.000 Moedas com entregas", Coins = 9000, XP = 250 },
		{ Id = "Deliver500", Kind = "Deliver", Target = 500, Text = "Entregue 500 batatas ao Rei", Coins = 10000, XP = 250 },
		{ Id = "Peel200", Kind = "Peel", Target = 200, Text = "Descasque 200 batatas à mão", Coins = 9000, XP = 250 },
		{ Id = "Orders5", Kind = "Order", Target = 5, Text = "Cumpra 5 pedidos do Rei", Coins = 7000, XP = 200 },
		{ Id = "Golden1", Kind = "Golden", Target = 1, Text = "Encontre uma batata dourada", Coins = 6000, XP = 200 },
		{ Id = "Race3", Kind = "Race", Target = 3, Text = "Termine 3 Corridas de Descascar", Coins = 6000, XP = 200 },
		{ Id = "Help60", Kind = "HelpMinutes", Target = 60, Text = "Ajude amigos por 60 min", Coins = 9000, XP = 250 },
	},
}

-- Baú do Rei: abre a cada 4 horas online.
Config.KingChest = { OnlineSeconds = 4 * 3600, ProductionMinutes = 20, Minimum = 1000 }

-- Temporada (8 semanas) e passe de 40 níveis. XP vem de jogar, não de pagar.
Config.Season = {
	Id = 1,
	Name = "Temporada 1: A Fome do Rei",
	EndsAt = 0, -- os.time() do fim (0 = sem data definida ainda)
	Levels = 40,
	XPPerLevel = 150,
	XP = { PotatoPeeled = 3, PotatoDelivered = 1, OrderDone = 40, RaceDone = 30 },
}

-- Hora Dourada: fins de semana, 2 h, chance de batata dourada x5 (horário em UTC).
Config.GoldenHour = { WeekDays = { [1] = true, [7] = true }, StartHourUTC = 22, Hours = 2, Multiplier = 5 }

-- Códigos de resgate (divulgados no Discord e X). Chave em MAIÚSCULAS.
Config.Codes = {
	BATATA = { Coins = 1000 },
	REIGLUTAO = { Boost = { Mult = 2, Minutes = 15 } },
}

-- Admin Abuse ao vivo: quem está aqui pode ativar multiplicadores no servidor.
Config.Admins = {} -- userIds, ex.: { 7303938680 }

-- Vídeo recompensado (seção 8): desligado até configurar o Rewarded Video no Creator Hub.
Config.RewardedVideo = {
	Enabled = false,
	BoostMult = 2,
	BoostMinutes = 15,
	MaxPerDay = 3,
}

-- Sons provisórios (Creator Store). Trocar na Etapa 5.
Config.Sounds = {
	Crunch = { Id = "rbxassetid://9113959343", Volume = 0.7 },
	Squish = { Id = "rbxassetid://90416226721742", Volume = 0.8 },
	Splash = { Id = "rbxassetid://9117947974", Volume = 0.6 },
	Coins = { Id = "rbxassetid://135483737426662", Volume = 0.6 },
	ComboUp = { Id = "rbxassetid://3406813517", Volume = 0.5 },
}

-- Trilha (Creator Store). Normal: ambiente medieval sombrio; evento: percussão tensa.
Config.Music = {
	Main = { Id = "rbxassetid://80572944177540", Volume = 0.35 },
	Event = { Id = "rbxassetid://95653883147560", Volume = 0.45 },
	Fade = 2,
}

return Config
