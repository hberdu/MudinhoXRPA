<#
  MudinhoX RPA - loop: /k37 -> play (MU Helper) -> espera level 350 -> /resetar -> repete.
  Stats: distribui de 5k em 5k ate 32767, na ordem energia, agilidade, forca, vitalidade. Atributos cheios -> /darmr e entra de novo.
  Level parado (miss infinito) -> religa o helper. De vez em quando faz algo "humano". Captcha: resolve sozinho (compara imagens);
  se nao tiver certeza, toast + beep e espera voce.

  Uso:   duplo clique em "MudinhoX RPA.cmd"  (abre janelinha com log e botao PARAR; pede admin porque o jogo roda como admin)
         parar por fora: crie o arquivo stop.flag na pasta. Log completo em rpa.log.
         powershell -ExecutionPolicy Bypass -File .\mudinhox_rpa.ps1 -Check              (le level/botao/captcha, nao clica)
         powershell -ExecutionPolicy Bypass -File .\mudinhox_rpa.ps1 -TestImage x.png    (testa solver num print salvo)
         powershell -ExecutionPolicy Bypass -File .\mudinhox_rpa.ps1 -TestInv          (com o inventario ABERTO: salva print e mostra as celulas ocupadas)
         powershell -ExecutionPolicy Bypass -File .\mudinhox_rpa.ps1 -TestMix          (com o modal de mix ABERTO: mostra o que o OCR le e a cor de cada opcao)
         powershell -ExecutionPolicy Bypass -File .\mudinhox_rpa.ps1 -TestVisao        (regressao das funcoes de leitura contra os prints de fixtures\)
         powershell -ExecutionPolicy Bypass -File .\mudinhox_rpa.ps1 -Preflight        (NO SPOT, em PowerShell ADMIN: valida level/mapa/status/inventario de uma vez)
  Requisito: o jogo precisa estar visivel na hora da leitura. Se outra janela estiver na frente, o bot traz o jogo
  por ~1s, le, e devolve o foco pra janela que voce estava usando (nesse caso le a cada 60s em vez de 10s).
#>
param([switch]$Check, [string]$TestImage, [string]$TestStatus = "", [switch]$TestInv, [switch]$TestMix, [switch]$TestNpc, [switch]$TestVisao, [switch]$Preflight, [switch]$TestStatMin)
# UM CLIENTE SO. Houve um modo multibox (-Slot 1..N, um processo por cliente, mutex global de entrada, arquivos
# por slot, mascara das janelinhas dos outros). Saiu em 12/09 a pedido: sempre um cliente. O que ele deixou de
# heranca e o caminho de leitura sem foco (Ver-Janela + Janela-Na-Frente), que virou o caminho unico - nasceu
# pra caber quatro bots no mesmo primeiro plano, mas o que ele resolve de verdade e nao roubar a sua tela.

# ---------- CONFIG (coordenadas relativas a area cliente do jogo, 1920x1009) ----------
$TargetLevel   = 350     # level pra resetar: o MINIMO que o servidor aceita, e e de proposito. NAO SUBIR.
                         # A razao e do jogo, nao do bot: quanto MAIOR o level, mais devagar ele sobe. Entao os
                         # levels entre 350 e o alvo maior sao os mais caros do ciclo, e os pontos a mais que
                         # eles rendem no reset nao pagam o tempo. Resetar no piso e o ciclo mais curto possivel.
                         # Ha um A/B antigo (350 vs 380) no historico que parece dizer o contrario - ignore-o: os
                         # dois bracos rodaram em SEQUENCIA, nao intercalados, entao mediram noites diferentes e
                         # nao o alvo. Foi por isso que o $AutoTune ficou desligado.
                         # Se um dia isto for testado de novo, tem que ser intercalando reset a reset.
$PollSec       = 6       # intervalo de leitura do level com o jogo na frente
$PollNearSec   = 2       # perto do level alvo le a cada N seg: o level sobe ~150 entre leituras e o reset saia com 400 em vez de 350 (farm jogado fora)
$PollNearFrom  = 0.82    # "perto" = a partir de N% do $TargetLevel
$NoFocusRead   = $true   # JOGO NOUTRO MONITOR, sempre visivel. Liga o modo "nao brigo por foco nem pelo seu mouse":
                         #  - LE (level, mapa, status, captcha) sem trazer o jogo pra frente. E a maior parte do que o bot faz
                         #  - o Hold-Focus para de trazer o jogo UMA VEZ POR VOLTA do loop; so quem manda comando pede foco
                         #  - o ponteiro do mouse volta pra onde voce deixou depois de cada clique
                         #  - o "humano: mexe o mouse" e pulado (arrastaria o SEU ponteiro por varios segundos)
                         # Em troca voce garante que a janela do jogo fica visivel e destapada: sem foco pra conferir,
                         # uma janela por cima dela vira leitura de lixo. $false = comportamento antigo (jogo em 1 monitor so).
$PollBgSec     = 60      # intervalo quando outra janela esta na frente (cada leitura rouba o foco por ~1s)
# ---------- QUAL JANELA E O JOGO ----------
$GameProc      = 'mudx'   # processo do cliente DESKTOP. Usado quando $GameTitle esta vazio.
$GameTitle     = ''       # DEFAULT: considerar o jogo em aberto como cliente desktop (mudx), como fazia antes.
                          # Se quiser forcar a deteccao pela aba do navegador, use um regex do titulo da aba (ex.: '(?i)\[GAME\]\s*MudinhoX').
                          # Vazio = cliente desktop, por $GameProc.
                          # Preenchido = procura por titulo em QUALQUER processo (Chrome/Edge), e a aba precisa estar ativa.
                          # Rodando na VM, o bot tem que rodar DENTRO dela: do host a VM e uma janela opaca so -
                          # daria pra capturar os pixels, mas nao pra mirar a janela do navegador la dentro,
                          # nem pra conferir foco.
$WarpCmd       = '/k37'   # comando de teleporte pro spot de farm normal (troque aqui se mudar de spot). Era /s18 (Stadium)
$WarmupCmd     = '/losttower5'   # apos /darmr o personagem volta fraco em Lorencia: farma AQUI (Lost Tower 5) ate juntar os primeiros resets
$WarmupResets  = 3           # quantos resets fazer no modo warmup (pos-darmr) antes de voltar ao spot normal ($WarpCmd).
                             # Era 10, depois 3. Chegou a ir pra 2 em 08/09 e voltou pra 3 no rollback daquele lote.
                             # Medido em 9 master resets: o warmup e o MAIOR ponto isolado de demora - 13.9 min de um
                             # MR de 41.8 (33%) pra fazer 3 dos ~23 resets. Cada reset la custa 255s contra 74s no
                             # $WarpCmd. Vale reduzir de novo, mas UMA mudanca por vez e com o bot medido depois.
$WarmupTeste   = $false  # TESTA o spot normal logo apos o /darmr: fechou um reset la em ate $WarmupTesteSec, pula o
                         # warmup inteiro; estourou, cai pro Lost Tower e faz os $WarmupResets normalmente.
                         # Ligado em 08/09 junto com outras 2 mudancas e revertido no mesmo dia - NAO por culpa dele:
                         # o lote inteiro voltou porque o painel de status parou de abrir e nao deu pra isolar qual
                         # das tres causou. Este e o candidato mais promissor pra tentar de novo, SOZINHO.
$MrsPorDia     = 0       # COTA DIARIA de master resets. 0 = SEM LIMITE (pedido do usuario em 07/09: "o maximo possivel").
                         # A cota foi criada quando o bot fazia 6 MR/dia e o limite de 10 nunca encostava; depois que o
                         # captcha e a cauda foram corrigidos ele passou pra ~0.61h por MR (~39/dia) e o teto passou a
                         # morder antes do meio-dia. O mecanismo continua inteiro aqui: e so por um numero > 0 de volta.
                         # Com valor > 0: batendo a cota o bot PARA DE RESETAR e cai no modo joias (farma, mixa, repete)
                         # ate virar o dia; a meia-noite ele volta sozinho ao ciclo de reset. 0 = sem limite.
                         # A contagem e por DIA DO CALENDARIO e mora no estado.txt (mrsDia/mrsDiaData): reiniciar o bot
                         # nao fura a cota, e maquina desligada a noite toda tambem nao - o que vale e a data.
                         # NAO encerra o processo: sem watchdog, bot fechado nao volta sozinho no dia seguinte.
$WarmupTesteSec = 300    # o teste falha se o primeiro ciclo no spot normal passar disso (ciclo saudavel la e 70-110s; ate o Lost Tower fecha em ~220s). Estourou = char fraco demais, cai pro warmup
$WarpMap       = 'kant'      # 4 primeiras letras do nome que o minimapa mostra no spot do $WarpCmd - o /k37 cai em KANTURU (confirmado no log de 12:01). VAZIO = o bot APRENDE no primeiro teleporte e grava no estado.txt.
                             # Era 'stad' (Stadium, do /s18). Chutar o nome errado e pior que nao saber: o bot acha que nunca chegou e re-teleporta a noite toda.
                             # Pra reaprender depois de trocar de spot: deixe vazio aqui, ou apague a linha warpMap= do estado.txt
$WarmupMap     = 'lost'      # nome esperado do mapa do  (Lost Tower). Serve pra qualquer andar: o minimapa diz so 'Lost Tower'. Evita aceitar mapa errado (ex AIDA) como spot
$WarpWaitSec   = 9       # espera apos o teleporte (dar tempo do mapa trocar)
$ResetWaitSec  = 8       # sem captcha e level ainda alto apos N seg -> reenvia /resetar. Era 15: no log 83 dos 179 /resetar se perderam (o REENVIO funciona quase sempre na hora), entao esperar 15s so jogava ~20 min fora
$ResetRetries  = 2       # apos N reenvios de /resetar avisa (mas NUNCA para de reenviar)
$ResetStuckMin = 5       # preso no reset por N minutos -> reinicia o ciclo (re-warp) em vez de ficar so avisando
$RenotifySec   = 120     # re-avisa a cada N segundos enquanto espera humano
$StatCmds      = @(      # ciclo: /f apos 3min, /a apos +2min, /v apos +2min, /e apos +3min, repete. Atributo ja cheio e pulado.
  @{ Cmd = '/f'; AfterSec = 180; Key = 'For' },   # /darmr exige TODOS os atributos no maximo, entao vitalidade tambem entra no ciclo
  @{ Cmd = '/a'; AfterSec = 120; Key = 'Agi' },
  @{ Cmd = '/v'; AfterSec = 120; Key = 'Vit' },
  @{ Cmd = '/e'; AfterSec = 180; Key = 'Ene' }
)
$StatOrder     = 'Ene','Agi','For','Vit'          # ordem de distribuicao: energia -> agilidade -> forca -> vitalidade
$StatStep      = 5000    # sobe de 5k em 5k: 5000, 10000, ... 30000 e por fim o cap. Etapas montadas logo abaixo de $StatMaxValue
$StatMaxLeftover = 10000 # nao pode sobrar mais que isso de pontos nao distribuidos; acima disso o bot avisa em vez de continuar resetando
$StatMinAvail  = 1       # menos que isso de pontos disponiveis: nao distribui (1 = sempre tenta; um atributo pode fechar o cap com poucos pontos)
$StatMinCmd    = 1000    # piso do /a. Perigo REAL: /a com valor pequeno (<100) teleporta pra AIDA. Nao baixe.
$StatMinOutros = 1000    # piso INICIAL de /f /v /e. Sempre foi PRECAUCAO NUNCA TESTADA - so o /a tem perigo real (abaixo de 100 teleporta pra AIDA). Ver $StatMinAprende logo abaixo
$StatMinAprende = $true  # o bot testa UMA vez, com /f, se o servidor aceita valor abaixo do piso; aceitou -> $StatMinOutros cai pra $StatMinTeste e o veredito vai pro estado.txt (nunca retesta).
                         # Motivo medido: 2109 das 3551 leituras de status do log nao renderam UM comando - os pontos chegam em blocos de ~600-900 e o piso de 1000 recusava tudo. Maior desperdicio do projeto.
                         # $false = nao testa e ignora o que ja foi aprendido (volta a valer o valor fixo acima). O -TestStatMin continua servindo pra conferir na mao.
$StatMinTeste  = 100     # valor minimo que o teste exige ter em maos (mandar /f 16 e concluir "servidor recusa" seria mentira: talvez ele so recuse ABAIXO de 100) e piso adotado se ele aceitar.
                         # Nao precisa ser menor: fechar o cap exato ja ignora o piso (ver $piso em Plan-Stats), entao 100 destrava a distribuicao normal sem extrapolar o que foi provado
$StatPertoDoMax = 30000  # com os 4 atributos acima disso, o piso por comando cai pra $StatMinPerto e o status e lido a cada $StatEveryNearSec
$StatMinPerto  = 500     # piso reduzido na reta final: o que importa la e FECHAR o cap pro /darmr, nao economizar comando
$StatMinAgi    = 100     # o /a NUNCA vai abaixo disso, nem na reta final: abaixo de 100 ele teleporta o char pra AIDA (perigo documentado, medido)
$StatEveryNearSec = 5    # perto do maximo le o status a cada N seg (em vez de $StatEverySec): os ultimos pontos e que destravam o /darmr
$StatEverySec  = 15      # distribui os pontos a cada N seg enquanto upa (alem de logo apos cada reset e antes de cada /resetar)
                         # Foi pra 35 na teoria de que "comando = leitura" e que esperar mais renderia comandos
                         # maiores. MEDIDO depois, em 80 resets: nao rendeu NADA - 99s por reset contra os 100s de
                         # antes, e 9.4 comandos contra 10.9. A teoria estava errada porque a mediana entre
                         # leituras e 3s, nao $StatEverySec: quem manda e o laco interno do Distribute-Points e o
                         # $StatEveryNearSec da reta final. Este intervalo quase nao aparece.
                         # O que ele fez de verdade foi DOBRAR todo intervalo cego: o recuo do Tick-Stats
                         # multiplica esta base, entao uma leitura vazia passou de 30s pra 70s de silencio. Um
                         # ciclo do log ficou 77s sem olhar atributo nem level com o char ja passando do alvo.
$StatMaxSec    = 90      # teto: mesmo com o level parado (ou ilegivel), rele o status a cada N seg
$StatCongeladoN = 2      # N leituras de status IDENTICAS (4 atributos + pontos) com o level andando entre elas = painel velho na tela -> destrava. Em 01/09 ficou 12 min com "752 pontos" congelados e so o $SemProgressoMin pegou
$StatRoundSec  = 0.25    # espera entre uma rodada de distribuicao e a releitura do status (era 0.5; a releitura ja custa ~1s de captura+OCR, nao precisa de folga por cima)
# Velocidade do teclado/chat. 40/40 e o valor testado que NAO embaralha - nao baixe (ja fez /s18 sair invalido e queimar 4 warps).
$KeyHoldMs     = 40      # tempo segurando cada tecla ao digitar
$KeyGapMs      = 40      # pausa entre uma tecla e a proxima
$KeyClearMs    = 12      # backspaces pra limpar o chat (sao 30 seguidos, e so apagar: aguenta ser rapido)
$ChatOpenMs    = 130     # espera a caixa de chat abrir antes de digitar
$ChatSendMs    = 70      # espera em volta do Enter que envia
                          # Regiao do painel de status (C), que abre encostado na ESQUERDA. Em FRACAO da area
                          # cliente (era 500x760 em pixel). Largura 0.45 e nao 0.26 (o equivalente ao desktop): na web o painel
                          # ocupa x 0.15-0.39, e cortar em 0.26 deixava o botao "Pontos: 244" de fora. Isto e so otimizacao: se o recorte nao pegar o painel,
                          # o Ocr-Status cai pra tela inteira sozinho - por isso errar aqui custa tempo, nao leitura.
$StatPanelFrac = @{ W = 0.45; H = 0.80 }
$StatPanelScale = 2      # 2x: na resolucao nativa o OCR nao le o painel; em 3x tambem falha (imagem grande demais). Medido, nao chutado
$StatMaxValue  = 32767   # atributo cheio (cap real do servidor). /darmr SO funciona com Forca, Agilidade, Vitalidade E Energia TODOS = 32767; abaixo disso o jogo recusa ("precisa 32767 em todos status")
$StatStages    = @(1..([Math]::Floor(($StatMaxValue - 1) / $StatStep)) | % { $_ * $StatStep }) + $StatMaxValue   # 5000,10000,...,30000,32767
$StatusKey     = 0x43    # C = janela de status
$HotkeyHoldMs  = 150     # hotkey (C) segurada mais tempo que tecla de texto
                          # Fallback CEGO pra entrar com o personagem apos /darmr (centro embaixo), em fracao.
                          # So e usado depois do OCR falhar, e nunca numa tela com $LoginDangerWords - 'CRIAR NOVA
                          # CONTA' fica logo abaixo e um clique errado ali cria conta.
$LoginBtnFrac  = @{ X = 0.50; YFromBottom = 0.068 }
                                          # Y medido a partir da BASE da area cliente (era Y=940 cravado, calibrado numa altura de 1009). Numa janela de outra altura o
                                          # clique cego escorregava - e logo ali embaixo mora o "CRIAR NOVA CONTA". Todo o resto do layout ja e ancorado no topo ou na base.
$LoginWords    = 'Entrar|Conectar|Iniciar|Jogar|Selecionar|Enter|Start|Login'   # tela de selecao de PERSONAGEM
$LoginServerWords = '(?i)server vip gold'   # tela de selecao de SERVIDOR: regex do botao a clicar (ex 'Server Principal'). Vazio = nao clica, avisa
$LoginDangerWords = '(?i)(criar nova conta|create account|^sair$|delete)'   # se isso esta na tela, NUNCA clicar em coordenada chutada
                          # Caixa de chat aberta: bordas VERMELHAS em cima e embaixo. Tudo em FRACAO da area
                          # cliente (era $ChatBox em pixel: X 870..1130, 80..130 da base - so valia em 1920x1009).
                          # MinRun e o comprimento minimo da corrida vermelha CONTINUA, em fracao da largura: e
                          # o que separa a borda (linha longa) do orbe de vida (redondo, corrida curta por linha).
$ChatFaixa     = @{ X1 = 0.30; X2 = 0.70; Y1FromBottom = 0.20; Y2FromBottom = 0.05; MinRun = 0.06 }
# SEGUNDA prova de que o chat esta aberto, por TEXTO. A borda vermelha do $ChatFaixa existe num estado do chat e
# nao existe noutro - em 15/09 a caixa estava aberta na tela e a faixa inteira tinha 4px de vermelho contra os
# 115 exigidos. A palavra separou os dois grupos em 7 imagens sem um erro: aparece nas 3 com chat aberto
# (inclusive a de hoje, sem borda) e em nenhuma das 4 com chat fechado. Faixa larga porque a caixa MUDA DE LUGAR
# entre os estados (um recorte estreito pegou 2 de 3). Custo medido: 56ms, e so paga quando a borda diz fechado.
$ChatTxtWords  = '(?i)whisper'
$ChatTxtFaixa  = 0.22    # fracao da ALTURA, a partir da base, onde procurar a palavra
# Miss infinito. A METRICA DO PROPRIO BOT aponta 'stall' como 23-27% de TODO o tempo (113 disparos numa sessao),
# e a maior parte disso e latencia de DETECCAO, nao a recuperacao. Por isso duas condicoes em vez de um relogio so:
$StallReads    = 3       # N LEITURAS seguidas com o level identico. E o sinal forte, e imune a OCR: uma leitura que falhou nao entra na conta (antes ela empurrava o relogio como se o level estivesse parado)
$LevelBoxMiss  = 3       # N leituras SEGUIDAS falhando antes de jogar fora a caixa calibrada do level. Uma falha e ruido
                         # de OCR (dano por cima do numero, efeito, frame no meio do desenho): descartar na primeira
                         # gerou 53 recalibracoes em 1003 linhas, sempre pro MESMO lugar, cada uma custando uma
                         # leitura de status forcada. Mesma licao do $StallReads aqui em cima.
$StallMinSec   = 15      # ...e pelo menos N seg. Piso de seguranca pra logo apos o reset, quando o char esta fraco e demora mesmo pra subir um level. Era 40 fixo (antes 75): 40s x 113 disparos = ~75 min so esperando pra perceber
$CityWords     = 'lorencia|noria|devias|elbeland|lorenmarket|karutan|elveland'   # mapas-cidade onde NAO se farma (personagem cai aqui apos reset). Qualquer outro mapa = spot de farm (ex Stadium do /s18)
# teleporte confirmado quando o mapa e um spot de farm (nao-cidade). $farmMap guarda o ultimo spot.
                          # $MapLabel REMOVIDO em 12/09: o rotulo do minimapa nao e mais procurado por coordenada.
                          # O Read-Map acha ele pelo padrao "numero,numero" (a coordenada do char no minimapa, que
                          # nada mais na tela tem) e pega o nome do mapa a esquerda - entao funciona em 1920x1009
                          # e em 1024x720 sem nenhum ajuste. A caixa achada fica em cache ($script:mapaBox) pra
                          # nao pagar OCR de tela cheia a cada leitura, e se invalida sozinha quando para de servir.
$WarpTries     = 4       # reenvia o comando de warp ate N vezes se o mapa nao mudar, depois avisa e segue
$PlayTries     = 3       # clica no play ate N vezes; se nao ligar, para de clicar (nao insiste cego)
$HumanMinSec   = 120; $HumanMaxSec = 420   # a cada X seg (aleatorio) faz algo "humano": anda um pouco, abre/fecha janela, mexe o mouse
# Modos de teste escrevem em OUTRO arquivo. Analisar o rpa.log e como todo bug serio deste projeto foi achado,
# e cada -TestVisao despejava ~30 linhas de "OK ..." no meio do log do bot, quebrando as contagens.
$LogFile       = Join-Path $PSScriptRoot $(if($Check -or $TestImage -or $TestStatus -or $TestInv -or $TestMix -or $TestNpc -or $TestVisao -or $TestStatMin){ 'testes.log' } else { 'rpa.log' })
$StopFile      = Join-Path $PSScriptRoot 'stop.flag'
$HeartbeatFile = Join-Path $PSScriptRoot 'heartbeat.txt'   # o bot bate aqui a cada volta; serve pra nao subir dois bots no mesmo cliente
$AtivoGapMax   = 120     # buraco maior que N seg entre voltas = o bot esteve PARADO; nao conta como tempo ativo nas metricas
$HeartbeatVivoSec = 180  # heartbeat mais novo que isso = tem bot vivo (impede duas instancias no mesmo jogo)
$SemProgressoMax = 3     # apos N ciclos seguidos sem progresso, o bot REINICIA A SI MESMO (ja elevado: nao pede UAC de novo)
$AutoRestart   = $true   # $false = nunca relanca a si mesmo; sem progresso $SemProgressoMax vezes ele so PARA. Unico caminho que ainda cria processo sozinho - e so com o bot rodando (fechar a janela ja o desliga antes)
$WatchdogTask  = 'MudinhoX RPA Watchdog'   # Tarefa Agendada do watchdog ANTIGO. Ele foi removido (nao queremos nada rodando depois que voce fecha); isto so serve pra APAGAR a tarefa que ficou instalada em quem ja rodou a versao velha
$EstadoFile    = Join-Path $PSScriptRoot 'estado.txt'   # fase + contagem de warmup, pra sobreviver a reinicio do bot
$LogMaxMB      = 5       # rpa.log maior que isso no start vira .bak (a pasta sincroniza no OneDrive)
$LogKeepBaks   = 5       # quantos .bak manter
$WarmupFile    = Join-Path $PSScriptRoot 'warmup.flag'   # se existir no start, o bot comeca em modo warmup () — use apos dar MR manualmente
# Captcha: offsets a partir do centro do texto "Selecione a mesma imagem abaixo:" (achado por OCR)
$CapRefDy      = -80                          # imagem de referencia (acima do texto)
$CapRowDy      = 80, 210                      # 2 linhas de opcoes
$CapColDx      = -260, -130, 0, 130, 260      # 5 colunas
$CapConfirmDy  = 355                          # botao Confirmar
$CapMaxTries   = 2       # errou N vezes -> para de tentar (nao arrisca a proxima)
$CapKeepShots  = 40      # quantos prints de captcha manter. Sem isso a pasta (dentro do OneDrive) chegou a 4.9GB / 2640 arquivos
$CapCiclosMax  = 200     # quantas duracoes de ciclo guardar pra mediana (array em PowerShell realoca a cada +=)
$CapKillGame   = $false  # $true volta a regra antiga (fecha o mudx.exe e encerra). $false = pausa e espera voce
$CapSelHalf    = 61                           # distancia do centro ate a borda vermelha (3px) da opcao selecionada; varre +-5px
$WalkDist      = 140                          # apos /icarus anda ~4 passos (pixels a partir do centro) numa direcao aleatoria a cada chegada, antes do play
$CapAncoraWords = '(?i)selecione.{0,20}mesma.{0,20}imagem'   # a FRASE do captcha ("Selecione a mesma imagem abaixo:").
                                              # NAO afrouxar pra so "Selecione": o dialogo do mix diz "Selecione o
                                              # metodo de combinacao" e virava captcha fantasma (ver Find-Captcha).
$CapConfidence = 0.65                         # melhor precisa ser < N% do segundo, senao nao chuta. Era 0.5, e ESSE era o gargalo do MR:
                                              # captcha nao resolvido TRAVA o jogo (o char nao farma, o /resetar nao pega), e o bot ficava
                                              # relendo a mesma imagem estatica a cada 5s pra sempre. No MR #30 foram 12 captchas distintos,
                                              # 192 linhas de "ambiguo" e 4 travados - o MR levou 4.59h contra os 0.71h do MR #15.
                                              # Razoes medidas (melhor/segundo): 0.132 0.199 0.218 0.431 0.487 0.493 passavam;
                                              # 0.503 0.504 0.514 0.515 eram RECUSADOS - e o de 0.515 foi aberto na mao: a resposta estava CERTA.
                                              # Lixo de verdade (cursor tapando a opcao certa, 04/09) deu 0.98, bem longe daqui.
                                              # Errar nao e barato mas e limitado: o bot confere a borda vermelha depois de clicar e PAUSA
                                              # apos $CapMaxTries erros. Nao clicar custou ~1h por captcha travado.
$CaptchaShotDir = Join-Path $PSScriptRoot 'captcha'   # print salvo aqui a cada captcha
$FixtureDir    = Join-Path $PSScriptRoot 'fixtures'   # prints guardados pro -TestVisao (regressao das funcoes de leitura de tela)
# Mensagens do jogo (faixa acima da caixa de chat). O servidor responde tudo por texto e o bot ignorava:
# "Voce adicionou N pontos", "Bem-vindo(a) a Lorencia", "Resta ainda N Golden Tantalo vivo(s)".
                          # Faixa das mensagens em FRACAO da area cliente (era $MsgBox em pixel: X=760 W=400,
                          # 250..135 da base - so valia em 1920x1009). Uniao medida dos dois layouts com folga:
                          # desktop x 0.40-0.60 / y 0.13-0.25 da base, web x 0.32-0.68 / y 0.19-0.30.
$MsgFaixa      = @{ X1 = 0.25; X2 = 0.75; Y1FromBottom = 0.35; Y2FromBottom = 0.08 }
$MsgCheckSec   = 20      # le as mensagens a cada N seg (recorte pequeno, usa a captura que ja existe)
$MsgInvWords   = '(?i)(invent.rio.{0,12}cheio|espa.o insuficiente|inventory full)'   # inventario cheio -> vai mixar
# "Voce nao pode se mover neste momento": o servidor recusa QUALQUER /warp enquanto ha janela de NPC aberta. Em
# 12/09 o mix desistiu com o dialogo de confirmar na tela e o bot mandou /k37 por 54 MINUTOS levando essa
# resposta, sem nunca tentar fechar nada. Duas palavras, porque o OCR massacra o resto: as tres leituras reais
# foram 'Vocó não podo se mover nosto momento', 'voco nao poao so mover nosto momento' e a forma correta.
$MsgTravadoWords = '(?i)s[eo]\s+mover'   # + 'moment' (conferido junto, pra nao casar com outra frase que tenha "se mover")
# "Voce precisa de estar no level 350 para resetar!" - o servidor DIZ o piso, e o bot aprende dai (ver o
# reenvio do /resetar). O regex antigo pedia a palavra "level" e a palavra "resetar" literais e por isso NUNCA
# casou: o OCR le "Iovol"/"lovol"/"levei"/"leve!" e "rosetar"/"resetad". Ficaram 6 avisos do servidor no log
# sem nenhum aprendizado, com o alvo parado abaixo do exigido e um reenvio de /resetar sobrando a cada reset.
# Ancora no que o OCR acerta: o NUMERO colado em "para r?seta?". As letras de dentro e que ele erra.
$MsgMinResetWords = '(?i)(\d{2,4})\s*para\s*r[eo0]s[eo0]ta'
$ClientEsperado = @{ W = 1920; H = 1009 }   # resolucao pra qual as coordenadas fixas foram calibradas; muda isso se recalibrar noutra
$SemProgressoMin = 12    # sem ganhar UM ponto por N min = travou em algo que a gente ainda nao previu -> avisa e reinicia o ciclo
$LogLevelDelta = 40      # so loga o level quando ele salta N (ou cai = reset). Com poll de 2s, logar todo tick so enche o arquivo
$UiLogMaxChars = 60000   # teto do log da janelinha (o TextBox crescia sem limite rodando dias seguidos)
$AutoTune      = $false  # A/B do alvo DESLIGADO, e nao e "ainda nao ligamos": a resposta ja e conhecida. Level
                         # alto sobe mais devagar, entao o alvo certo e o piso do servidor - ver $TargetLevel.
                         # Ligar isto faria o bot passar resets medindo um alvo maior que ja se sabe pior.
$AutoTuneAlvos = 350, 380   # alvos que ele testaria. NAO usar abaixo de $LevelMinReset: o servidor recusa e o /resetar so vira reenvio ate o char passar do minimo sozinho
$LevelMaximo   = 400     # teto de level do servidor ("voce esta no nivel maximo"). No modo joias o char fica parado nele, entao o detector de miss infinito nao pode usar o level la
$LevelMinReset = 350     # level minimo pra resetar, confirmado pela mensagem do servidor ("Voce precisa de estar
                         # no level 350 para resetar!"). Valor so de PARTIDA: quem manda e o servidor, e o bot
                         # aprende dos dois lados - a mensagem de recusa sobe o piso, um reset aceito de primeira
                         # abaixo dele o baixa. Servidor que mude a regra nao exige mexer aqui.
$ResetRetestResets = 20  # PISO APRENDIDO NAO PODE SER DEFINITIVO. Quando o servidor recusa o alvo do CONFIG, o bot
                         # sobe o piso pro que a mensagem disser - e isso ja ficou gravado no estado.txt pra
                         # sempre. Errado: a exigencia pode cair (evento, mudanca de regra, item que desconta
                         # level), e o bot nunca mais tentaria o alvo pedido. A cada N resets ele tenta de novo;
                         # se o servidor aceitar, o piso CAI na hora, sozinho.
                         # Custo de um teste que falha: um /resetar recusado (~11s), uma vez a cada ~MR inteiro.
# O ALVO DO CONFIG, guardado antes que alguem mexa. O $TargetLevel e mutavel em runtime (o aprendizado do piso e
# o Load-Estado escrevem nele), entao depois da primeira recusa ele NAO e mais o que esta escrito aqui em cima -
# e o que o servidor impos. Sem esta copia nao ha como voltar pro alvo pedido, nem como saber qual era.
$TargetLevelConfig = $TargetLevel
                         # O bot re-aprende sozinho pela mensagem do servidor se estiver errado - mas so pra CIMA
                         # (ver Master-Reset), entao um valor baixo demais se corrige e um alto demais nao.
                         # ATENCAO: o Load-Estado restaura minReset= do estado.txt SEMPRE (diferente do alvo=, que so
                         # entra com $AutoTune). Trocar aqui sem limpar a linha do estado nao adianta.
$AutoTuneResets = 15     # resets por alvo antes de comparar
$MetricsEvery  = 5       # a cada N resets loga resumo: resets/h, pontos/h e ETA do master reset
$JitterPct     = 0.25    # varia +-25% os intervalos (stats, inventario, mensagens, poll). Valores dos stats seguem EXATOS - so o RITMO varia
# Mix de joias: inventario cheio -> /mixer -> clica no NPC -> "Mixar Joias" -> clica cada tipo em VERDE -> volta pro farm
$MixCmd        = '/mixer'
$MixNpcWords   = '(?i)^(lahap|mixador|mixer|goblin|joalheiro)'   # nome do NPC. So aparece com o mouse EM CIMA dele, entao serve de CONFIRMACAO do hover, nao de busca
                          # Onde o Lahap fica, em FRACAO do CANVAS (era $MixNpcPos cravado em 805,285 - so valia
                          # em 1920x1009). Fracao do CANVAS e nao da area cliente: na web a barra do navegador
                          # empurra tudo pra baixo. So serve de PONTO DE PARTIDA - quem autoriza o clique e
                          # sempre o OCR do nome no hover, e o ponto confirmado fica guardado pra proxima vez.
$MixNpcFrac    = @{ X = 0.42; Y = 0.28 }
$MixNpcSweep   = 0, -45, 45, -90, 90, -140, 140   # deslocamentos tentados em volta do ponto de partida. Mais
                          # largo desde 12/09: o ponto agora e estimado por fracao, nao medido a dedo, entao a
                          # varredura precisa cobrir o erro da estimativa.
$MixNpcNameDy  = -70      # o nome aparece ~70px ACIMA do cursor; o OCR le so essa faixa (rapido)
$MixMenuWords  = '(?i)^mixar$'   # botao "Mixar Joias" do modal do NPC. Ancora no "Mixar" sozinho (o texto de descricao e "mixar/dissolver"); entre os que casam, vale o MAIS DE BAIXO (o de cima e o titulo da janela)
$MixJewels     = @(       # tipos da lista, na ordem; Pat = como o OCR pode ler o rotulo
  @{ Name = 'Soul';     Pat = "(?i)^soul" },
  @{ Name = 'Life';     Pat = "(?i)^life" },
  @{ Name = 'Creation'; Pat = "(?i)^creation" },
  @{ Name = 'Chaos';    Pat = "(?i)^chaos" }
)
$MixSucessoWords = '(?i)(sucesso|voc. mixou|mixou [0-9])'   # resposta do jogo apos o mix; confirma que aconteceu de verdade
$MixConfirmTentativas = 5   # o dialogo de confirmacao demora um tempo VARIAVEL: procura ate N vezes (1s cada) em vez de olhar uma vez
$MixConfirmWords = '(?i)^confirmar$'   # 2o dialogo do mix: "Deseja continuar?" com CONFIRMAR/CANCELAR. NUNCA casar com CANCELAR
$MixCancelWords  = '(?i)^cancelar$'    # o outro botao do mesmo dialogo. SAIDA quando o CONFIRMAR nao e achado:
                                       # desistir com o dialogo na tela trava o char inteiro (ver o bloco do mix).
$CursorParkX   = 40      # canto pra onde o mouse e levado antes de ler a tela (o ponteiro aparece na captura e some com o texto debaixo)
$CursorParkY   = 400
# "Selecione a Jewel que voce quer mixar" so existe na tela da LISTA (nao no 1o modal, nem no chat).
# Antes eu procurava nomes de joia soltos - e o CHAT casava ("Sucesso! voce mixou N Life Points", "Obtido Jewel of
# Soul"), entao o bot achava que a lista continuava aberta, nao reabria o modal e mixava so a primeira joia.
$MixListaWords = '(?i)selecione'
$MixWaitSec    = 2        # espera entre o mix de um tipo e o proximo. Era 5: quem tolera UI lenta e o Achar-Ate do
                          # Abrir-Modal-Mix, que PROCURA o menu ate $MixConfirmTentativas vezes em vez de olhar uma vez.
                          # O sleep grande aqui so somava em cima disso (11.5s por joia com a espera do "Sucesso!" junto).
$MixRounds     = 12      # no maximo N voltas (a lista tem 7 opcoes; sobra folga)
$InvKey        = 0x56     # V = inventario
# A grade do inventario e localizada DINAMICAMENTE pelo titulo da janela: o painel abriu em (1317,408) na
# calibracao e em (607,333) depois - nao tem posicao fixa. Offsets medidos nos dois prints; a celula (34.4px) bate.
$InvTituloWords = '(?i)^invent'   # titulo da janela; acha-lo tambem prova que o painel esta aberto
$InvGridDx     = -133    # do CENTRO do titulo ate a borda esquerda da 1a celula
$InvGridDy     = 296     # do TOPO do titulo ate o topo da 1a celula
$InvCellPx     = 34.4    # lado da celula (fracionario: arredondar acumula erro na 8a coluna)
$InvCellLit    = 210      # soma R+G+B acima disso = pixel "com item" (celula vazia e escura)
$InvCellMin    = 10       # N pixels claros na celula = ocupada
$InvFreeMin    = 4        # so informativo agora (-Preflight/-TestInv): quantas celulas livres ainda contam como "vazio"
$JoiasFarmMax  = 8       # modo JOIAS: vai mixar a cada N min. E o gatilho PRINCIPAL: a contagem de celulas depende de alinhamento e a ancora oscila, entao nao da pra confiar nela pra adiar o mix
$MixEveryMin   = 25      # ciclo NORMAL (reset/master reset): mixa a cada N min sem parar de resetar. 0 = so pelo aviso do jogo e pelo botao.
                         # Existe porque o aviso "inventario cheio" NUNCA foi lido: 0 ocorrencias no rpa.log inteiro, contra 68 pausas manuais suas pra mixar na mao.
                         # Custo medido: um mix leva 30-70s (ida pro /mixer, mix, warp de volta, play), ~3% do tempo a cada 25 min.
$InvUsarMenu   = $true   # se a tecla nao abrir o inventario, tenta pelo MENU do jogo (botao de 3 barras no topo direito)
                          # Botao de 3 barras (menu do jogo), canto superior direito do CANVAS - em fracao, e do
                          # canvas e nao da area cliente porque na web a barra do navegador empurra tudo pra baixo.
$InvMenuFrac   = @{ X = 0.983; Y = 0.023 }
$InvMenuClickDy = -45    # no menu, o item e um ICONE com o rotulo EMBAIXO: o OCR acha o texto, mas o clicavel esta ACIMA dele
$InvMenuWords  = '(?i)^invent'   # item do menu que abre o inventario
$InvMaxFalhas  = 3       # apos N falhas seguidas de abrir o inventario, desiste (nao fica apertando tecla desconhecida no personagem)
# ---------------------------------------------------------------------------------------

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Runtime.WindowsRuntime
[void][Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType=WindowsRuntime]
[void][Windows.Graphics.Imaging.BitmapDecoder, Windows.Foundation, ContentType=WindowsRuntime]
[void][Windows.Storage.Streams.InMemoryRandomAccessStream, Windows.Foundation, ContentType=WindowsRuntime]
[void][Windows.Storage.Streams.DataWriter, Windows.Foundation, ContentType=WindowsRuntime]
[void][Windows.Globalization.Language, Windows.Foundation, ContentType=WindowsRuntime]
[void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType=WindowsRuntime]
[void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType=WindowsRuntime]
Add-Type @"
using System; using System.Runtime.InteropServices; using System.Text; using System.Collections.Generic;
public class W {
  // VERSAO WEB: achar a janela do jogo pelo Get-Process/MainWindowTitle NAO funciona. O Chrome e multi-processo
  // e o MainWindowTitle expoe UMA janela por processo - com o jogo aberto, a unica janela do Chrome que aparecia
  // era a barra "... is sharing a window.". Entao enumera as JANELAS de verdade, com EnumWindows.
  [DllImport("user32.dll")] private static extern bool EnumWindows(EnumProc cb, IntPtr p);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] private static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] private static extern IntPtr GetWindow(IntPtr h, uint cmd);
  private delegate bool EnumProc(IntPtr h, IntPtr p);
  public static List<IntPtr> JanelasVisiveis(out List<string> titulos){
    var hs = new List<IntPtr>(); var ts = new List<string>();
    EnumWindows(delegate(IntPtr h, IntPtr p){
      if(!IsWindowVisible(h)) return true;
      if(GetWindow(h, 4) != IntPtr.Zero) return true;   // GW_OWNER: pula popups/dialogos, fica so janela de topo
      var sb = new StringBuilder(512); GetWindowTextW(h, sb, sb.Capacity);
      var t = sb.ToString(); if(t.Length == 0) return true;
      hs.Add(h); ts.Add(t); return true;
    }, IntPtr.Zero);
    titulos = ts; return hs;
  }
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
  // SUBIR a janela na pilha SEM roubar o teclado (SWP_NOACTIVATE). E o que separa "preciso ver" de
  // "preciso digitar": ver custa ms e nao tira o foco de onde voce esta; digitar exige primeiro plano de verdade.
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int w, int hh, uint flags);
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);   // quem esta REALMENTE nesses pixels?
  [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint fl);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr pid);
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte sc, uint fl, UIntPtr ex);
  [DllImport("user32.dll")] public static extern void mouse_event(uint fl, int dx, int dy, uint data, UIntPtr ex);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] public static extern short VkKeyScan(char c);
  [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint code, uint type);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X,Y; }
}
"@
Add-Type -ReferencedAssemblies System.Drawing @"
using System; using System.Drawing; using System.Drawing.Imaging; using System.Runtime.InteropServices;
public class Img {
  // menor soma de diferencas absolutas entre a (template) e b (janela maior), testando todos os deslocamentos
  public static long MinSad(Bitmap a, Bitmap b){
    long best = long.MaxValue;
    var ra = a.LockBits(new Rectangle(0,0,a.Width,a.Height), ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
    var rb = b.LockBits(new Rectangle(0,0,b.Width,b.Height), ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
    byte[] da = new byte[ra.Stride*a.Height], db = new byte[rb.Stride*b.Height];
    Marshal.Copy(ra.Scan0, da, 0, da.Length); Marshal.Copy(rb.Scan0, db, 0, db.Length);
    for (int oy = 0; oy <= b.Height-a.Height; oy++) for (int ox = 0; ox <= b.Width-a.Width; ox++) {
      long s = 0;
      for (int y = 0; y < a.Height && s < best; y++) for (int x = 0; x < a.Width*3; x++) s += Math.Abs(da[y*ra.Stride+x] - db[(y+oy)*rb.Stride+ox*3+x]);
      if (s < best) best = s;
    }
    a.UnlockBits(ra); b.UnlockBits(rb); return best;
  }
  // varre a area util somando pixels "dourados" em blocos de 'cell' px; devolve {x,y,contagem} do bloco mais dourado
  // (x=y=0 quando nenhum bloco passou de minCount). Ignora um raio 'selfR' em volta de (cx,cy): e o proprio personagem.
  public static void Invert(Bitmap a){
    var r = a.LockBits(new Rectangle(0,0,a.Width,a.Height), ImageLockMode.ReadWrite, PixelFormat.Format24bppRgb);
    byte[] d = new byte[r.Stride*a.Height]; Marshal.Copy(r.Scan0, d, 0, d.Length);
    for (int i = 0; i < d.Length; i++) d[i] = (byte)(255 - d[i]);
    Marshal.Copy(d, 0, r.Scan0, d.Length); a.UnlockBits(r);
  }
}
"@

# ---------- UI / log / espera ----------
$script:stop = $false; $script:paused = $false; $script:ui = $null; $script:logW = $null
# rotaciona o log antes de abrir: a pasta sincroniza no OneDrive e ja tinha .bak de centenas de KB
try {
  $lf = Get-Item $LogFile -ErrorAction SilentlyContinue
  if($lf -and $lf.Length -gt ($LogMaxMB * 1MB)){ Move-Item $LogFile (Join-Path $PSScriptRoot ("rpa_{0}.log.bak" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))) -Force }
  Get-ChildItem $PSScriptRoot -Filter 'rpa_*.log.bak' -ErrorAction SilentlyContinue | sort LastWriteTime -Descending | select -Skip $LogKeepBaks | Remove-Item -Force -ErrorAction SilentlyContinue
} catch {}
try { $script:logW = New-Object System.IO.StreamWriter([System.IO.FileStream]::new($LogFile, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)); $script:logW.AutoFlush = $true } catch {}
# Contadores DA SESSAO (deste processo). Os $script:resets/$script:mrs nao servem pra isso: o primeiro e zerado
# a cada /darmr (mede o MR atual) e o segundo vem do estado.txt, acumulado da vida inteira do personagem.
$script:resetsSessao = 0; $script:mrsSessao = 0
$script:ptsTotal = 4 * $StatMaxValue   # 131068: os 4 atributos do zero ao cap. Denominador da barra
$script:ptsNeeded = -1   # -1 = status ainda nao lido. Precisa existir ANTES do primeiro Log: sem isto $null -lt 0 e falso e a barra abriria em 100%
function Progresso-MR {   # fracao 0..1 do caminho ate o proximo /darmr. 0 enquanto o status nao foi lido ($ptsNeeded = -1)
  if($script:ptsNeeded -lt 0 -or $script:ptsTotal -le 0){ return 0.0 }
  [Math]::Max(0.0, [Math]::Min(1.0, ($script:ptsTotal - $script:ptsNeeded) / $script:ptsTotal))
}
function Log($m){
  $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m; Write-Host $line
  if($script:logW){ try { $script:logW.WriteLine($line) } catch {} } else { try { Add-Content -Path $LogFile -Value $line -Encoding UTF8 } catch {} }
  if($script:ui -and -not $script:ui.IsDisposed){
    # Painel atualizado aqui e nao num tick proprio: o Log ja roda a cada evento do bot e ja faz o DoEvents,
    # entao a barra nunca fica velha e nao precisa de mais nada agendado.
    $pct = Progresso-MR
    Set-Barra $pct
    # Texto encurtado junto com a janela: a versao longa nao cabia nos 284px e truncava justo no numero do fim.
    # RESETS no lugar dos pontos: "faltam 49806" nao diz nada sobre quanto falta esperar, e "~5 resets" diz -
    # e o numero e medido, nao suposto (ver Resets-Faltando). Com poucos resets medidos ainda sai '?'.
    # Separador '·' e nao '|': a barra vertical vira uma cerca de tracinhos e puxa o olho pra si. E sem repetir
    # "MR" antes da porcentagem - a barra dourada esta logo acima, nao ha o que confundir.
    $fr = Resets-Faltando
    $script:contador.Text = ("{0} resets  ·  {1} MR  ·  {2:0.0}%  ·  faltam {3}" -f `
      $script:resetsSessao, $script:mrsSessao, ($pct * 100), $(if($null -ne $fr){ "~$fr" } else { '?' }))
    # o TextBox crescia sem limite: rodando dias seguidos a janela fica pesada. Corta pela metade quando passa do teto.
    if($script:logBox.TextLength -gt $UiLogMaxChars){ $script:logBox.Text = $script:logBox.Text.Substring($script:logBox.TextLength - [int]($UiLogMaxChars/2)) }
    $script:logBox.AppendText("$line`r`n"); [System.Windows.Forms.Application]::DoEvents()
  }
}
$script:ativoSeg = 0.0; $script:tickLast = $null
$script:pausaSeg = 0.0   # segundos que VOCE deixou o bot pausado dentro do ciclo atual; sai da duracao do ciclo (ver "reset feito")
function Bater-Heartbeat {   # prova de vida pro watchdog E acumulador de TEMPO ATIVO
  # pontos/h precisa dividir pelo tempo em que o bot REALMENTE rodou. Usando relogio de parede, as 6h que ele
  # passou travado em 01/09 entraram como tempo produtivo e afundaram a taxa (19527 pts/h contra 147116 reais).
  $agora = Get-Date
  if($script:tickLast){
    $d = ($agora - $script:tickLast).TotalSeconds
    if($d -gt 0 -and $d -lt $AtivoGapMax){ $script:ativoSeg += $d }   # buraco maior que isso = bot estava parado, nao conta
  }
  $script:tickLast = $agora
  try { $agora.Ticks | Set-Content -Path $HeartbeatFile -Encoding ASCII } catch {}
}
function Heartbeat-Fresco {   # $true se OUTRA instancia bateu o heartbeat ha pouco (evita dois bots no mesmo jogo)
  if(-not (Test-Path $HeartbeatFile)){ return $false }
  try { $t = [datetime]::new([long](Get-Content $HeartbeatFile -Raw).Trim()); return ((Get-Date) - $t).TotalSeconds -lt $HeartbeatVivoSec } catch { return $false }
}
$script:stopReason = 'usuario'   # POR QUE parou. O log dizia "parado pelo usuario" ate quando era erro ou reinicio proprio, e ai nao dava pra saber o que tinha acontecido de madrugada
function Check-Stop {
  if(-not $script:stop -and (Test-Path $StopFile)){ $script:stop = $true; $script:stopReason = 'stop.flag' }
  if(-not $script:stop){ return }
  Log "parado ($script:stopReason)"
  # Consome o flag e o heartbeat: parou, acabou. Nao existe mais watchdog lendo isto - nada relanca o bot depois
  # que ele sai, e um flag esquecido no disco so atrapalharia a proxima abertura.
  Remove-Item $StopFile,$HeartbeatFile -ErrorAction SilentlyContinue
  if($script:logW){ $script:logW.Dispose() }; if($script:ui){ $script:ui.Dispose() }
  exit
}
function Pause-Gate {   # congela o bot enquanto PAUSADO e LIBERA o foco pra voce mixar joias no NPC; re-adquire ao retomar
  if(-not $script:paused){ return }
  $pausouEm = Get-Date
  $wasHeld = $script:focusHeld; if($wasHeld){ Release-Focus }   # solta o jogo pra voce interagir
  # Pausado NAO e morto: sem bater o heartbeat, o watchdog ve 180s de silencio, mata o processo e relanca -
  # desfazendo a pausa que voce pediu. Bate direto no arquivo (nao via Bater-Heartbeat) porque aquele acumula
  # TEMPO ATIVO, e tempo parado no NPC nao pode entrar em pontos/h.
  $i = 0
  while($script:paused -and -not $script:stop){
    if($script:ui){ [System.Windows.Forms.Application]::DoEvents() }
    Check-Stop
    if($i++ % 25 -eq 0){ try { (Get-Date).Ticks | Set-Content -Path $HeartbeatFile -Encoding ASCII } catch {} }   # ~5s, nao a cada 200ms
    Start-Sleep -Milliseconds 200
  }
  $script:tickLast = Get-Date   # zera a base do tempo ativo: os minutos parados no NPC nao entram em pontos/h
  $script:ptsLastGain = Get-Date   # tempo pausado nao conta como "sem progresso" (senao o watchdog dispara na hora que voce retoma)
  # ...e nem na DURACAO DO CICLO. Sem isto os 3 piores ciclos da sessao passada (1058s, 996s, 977s = 8% do tempo)
  # eram voce pausado no NPC, entravam sem etiqueta na mediana e a metrica culpava um "?" que nao existe.
  $script:pausaSeg += ((Get-Date) - $pausouEm).TotalSeconds
  if($wasHeld -and -not $script:stop){ Hold-Focus }   # retomou: re-traz o jogo pro bloco continuar
}
function Wait([double]$sec){   # Start-Sleep que mantem a janelinha viva e obedece PARAR/PAUSAR
  Pause-Gate
  $end = (Get-Date).AddSeconds($sec)
  do {
    if($script:ui){ [System.Windows.Forms.Application]::DoEvents() }
    Check-Stop
    if($script:paused){ Pause-Gate; $end = (Get-Date).AddSeconds($sec) }   # pausou no meio da espera: segura e reinicia a contagem ao retomar
    Start-Sleep -Milliseconds 100
  } while((Get-Date) -lt $end)
}
function Canto-Da-Tela-Do-Jogo([int]$alturaJanela){
  # Canto INFERIOR ESQUERDO do monitor DO JOGO. Duas razoes: ali nao cobre nada que o bot le (play=topo-esq,
  # minimapa=topo-dir, inventario=dir, chat/level=centro-baixo), e com o jogo noutro monitor a janelinha nao tem
  # o que fazer na frente do que VOCE esta usando. PrimaryScreen nao serve: aqui o monitor 2 fica em X NEGATIVO
  # (-1920..0), entao a conta antiga jogava a janela pro monitor errado. Jogo fechado ainda -> primario.
  $t = $null
  try { $t = [System.Windows.Forms.Screen]::FromHandle((Get-Game)) } catch { }
  if(-not $t){ $t = [System.Windows.Forms.Screen]::PrimaryScreen }
  $wa = $t.WorkingArea
  # Canto INFERIOR ESQUERDO: e a unica area que o bot nao le. O Capture-Raw pinta a janelinha de preto em toda
  # captura, mas ler PRETO nao serve de nada - por cima da faixa de mensagens ou do chat o Read-Level falharia do
  # mesmo jeito. Entao ela fica onde nao ha nada pra ler.
  New-Object System.Drawing.Point(($wa.X + 10), ($wa.Y + $wa.Height - $alturaJanela - 10))
}
# ---------- PALETA E DESENHO DA HUD ----------
# Copiada da HUD do proprio MudinhoX: pedra escura em degrade, moldura de bronze com cravos nos cantos, ouro nos
# numeros, fonte SERIFADA. Nao e so enfeite - a janelinha vive POR CIMA do jogo, e retangulo chapado com Segoe UI
# ao lado daquela HUD grita "programa de fora". O que da o ar do jogo e o RELEVO: nada la e chapado, tudo tem
# luz em cima e sombra embaixo (placa saliente) ou o contrario (buraco escavado).
# QUASE PRETO. A primeira versao saiu marrom-clara e parecia um tema de programa, nao a HUD: no jogo o painel e
# escuro a ponto de sumir, e o OURO aparece SO onde ha informacao (a barra de XP, os numeros). O ouro espalhado
# em moldura, cravos e texto e o que fazia a janela gritar. Regra daqui pra frente: pedra quase preta, um unico
# filete de bronze, e o dourado reservado pra barra.
$HudPedraTopo = [System.Drawing.Color]::FromArgb(28,23,17)    # degrade da pedra: um tom acima do preto em cima
$HudPedraBase = [System.Drawing.Color]::FromArgb(9,7,5)       #                   preto embaixo
$HudPoco      = [System.Drawing.Color]::FromArgb(5,4,3)       # fundo de buraco escavado (trilho, caixa de log)
$HudBronzeEsc = [System.Drawing.Color]::FromArgb(24,18,9)     # sombra do metal
$HudBronze    = [System.Drawing.Color]::FromArgb(92,72,32)    # metal da moldura (apagado: e contorno, nao enfeite)
$HudOuro      = [System.Drawing.Color]::FromArgb(198,156,52)  # barra cheia - o unico dourado forte da janela
$HudOuroClaro = [System.Drawing.Color]::FromArgb(224,192,116) # brilho no topo da barra
$HudTitulo    = [System.Drawing.Color]::FromArgb(150,120,58)  # titulo: bronze, nao ouro - e rotulo, nao informacao
$HudCreme     = [System.Drawing.Color]::FromArgb(198,182,146) # numeros
$HudLog       = [System.Drawing.Color]::FromArgb(122,110,84)  # log: apagado, pra nao competir com os numeros
# Os botoes sao os DOIS maiores blocos de cor da janela: um tom a mais neles pesa mais que em qualquer outro
# lugar, e eram eles que ainda puxavam o olho depois da janela inteira escurecer. Ficam quase na cor da pedra -
# o que os separa dela e o RELEVO (luz em cima, sombra embaixo), nao o brilho. O vermelho do PARAR fica so
# insinuado; ele precisa ser reconhecivel, nao chamativo.
$HudSangue    = [System.Drawing.Color]::FromArgb(28,10,7)     # PARAR
$HudSangueCl  = [System.Drawing.Color]::FromArgb(52,18,12)
$HudOliva     = [System.Drawing.Color]::FromArgb(14,22,9)     # RETOMAR (pausado)
$HudOlivaCl   = [System.Drawing.Color]::FromArgb(28,44,17)
$HudPlaca     = [System.Drawing.Color]::FromArgb(12,10,6)     # placa de botao normal
$HudPlacaCl   = [System.Drawing.Color]::FromArgb(27,22,13)
# Serifada: e o que mais separa "HUD de jogo" de "formulario do Windows". Palatino Linotype vem com o Windows;
# se faltar, o WinForms cai numa serifada sozinho - que e exatamente o fallback que se quer.
function Hud-Fonte([single]$tam,[string]$estilo='Bold'){ New-Object System.Drawing.Font('Palatino Linotype',$tam,[System.Drawing.FontStyle]$estilo) }
function Hud-Grad($g,$r,$c1,$c2){   # degrade vertical
  if($r.Width -le 0 -or $r.Height -le 0){ return }
  $b = New-Object System.Drawing.Drawing2D.LinearGradientBrush($r,$c1,$c2,90.0)
  $g.FillRectangle($b,$r); $b.Dispose()
}
function Hud-Relevo($g,$r,$claro,$escuro){   # luz em cima/esquerda, sombra embaixo/direita = placa SALIENTE
  if($r.Width -le 1 -or $r.Height -le 1){ return }   # invertendo as cores, o mesmo desenho vira buraco ESCAVADO
  $pc = New-Object System.Drawing.Pen($claro); $pe = New-Object System.Drawing.Pen($escuro)
  $x2 = $r.Right - 1; $y2 = $r.Bottom - 1
  $g.DrawLine($pc,$r.X,$r.Y,$x2,$r.Y); $g.DrawLine($pc,$r.X,$r.Y,$r.X,$y2)
  $g.DrawLine($pe,$r.X,$y2,$x2,$y2);   $g.DrawLine($pe,$x2,$r.Y,$x2,$y2)
  $pc.Dispose(); $pe.Dispose()
}
function Hud-Str($g,[string]$t,$fonte,$cor,[single]$x,[single]$y){   # texto com sombra dura atras
  # Todo numero da HUD do jogo tem contorno escuro - e o que o faz legivel por cima de qualquer cenario, e o que
  # faz falta quando nao esta la (o texto "flutua" e parece etiqueta de formulario).
  $s = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(200,0,0,0))
  $g.DrawString($t,$fonte,$s,($x+1),($y+1)); $s.Dispose()
  $s = New-Object System.Drawing.SolidBrush($cor); $g.DrawString($t,$fonte,$s,$x,$y); $s.Dispose()
}
function Hud-StrEsp($g,[string]$t,$fonte,$cor,[single]$x,[single]$y,[single]$esp){   # letra a letra, espacada
  # Titulo de jogo e espacado; GDI+ nao tem letter-spacing, entao desenha caractere por caractere.
  # DEVOLVE onde parou: sem isso o proximo texto so podia ser posicionado por chute, e o "RPA" saiu por cima do
  # "MUDINHOX" na primeira tentativa - a largura espacada nao da pra prever no olho.
  $fmt = [System.Drawing.StringFormat]::GenericTypographic
  foreach($ch in $t.ToCharArray()){
    Hud-Str $g "$ch" $fonte $cor $x $y
    $x += $g.MeasureString("$ch",$fonte,[System.Drawing.PointF]::Empty,$fmt).Width + $esp
  }
  $x
}
function Hud-Moldura($g,$r){   # moldura MINIMA: preto por fora, um filete de bronze por dentro. Nada mais.
  # A primeira versao tinha moldura de 3 filetes e cravos de ouro nos cantos. Parecia mais uma borda de site
  # "medieval" do que a HUD do jogo - la o painel simplesmente termina no escuro. Ornamento que nao carrega
  # informacao e exatamente o que fazia a janela parecer feita por fora.
  $pp = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(4,3,2))
  $g.DrawRectangle($pp,$r.X,$r.Y,$r.Width-1,$r.Height-1); $pp.Dispose()
  $pb = New-Object System.Drawing.Pen($HudBronzeEsc)
  $g.DrawRectangle($pb,($r.X+1),($r.Y+1),($r.Width-3),($r.Height-3)); $pb.Dispose()
}
function Hud-Placa([string]$txt,[int]$x,[int]$y,[int]$w,[int]$h,$topo,$base){
  # Botao = PLACA DE METAL saliente, nao retangulo chapado. O Button do WinForms entra so como casca (clique,
  # hover, teclado) e o desenho e todo nosso: degrade, relevo e texto serifado com sombra.
  $b = New-Object System.Windows.Forms.Button
  $b.SetBounds($x,$y,$w,$h); $b.FlatStyle = 'Flat'; $b.FlatAppearance.BorderSize = 0
  $b.BackColor = $base; $b.Text = ''; $b.TabStop = $false
  $b.FlatAppearance.MouseOverBackColor = $base; $b.FlatAppearance.MouseDownBackColor = $base   # o hover e desenhado, nao pintado pelo WinForms
  # O estado do desenho vai na Tag: o scriptblock do Paint roda depois, fora desta chamada, e nao enxerga os
  # parametros dela. Sem isto os dois botoes sairiam com a cor do ultimo criado.
  $b.Tag = @{ Texto = $txt; Topo = $topo; Base = $base; Aceso = $false }
  $b.Add_Paint({
    param($s,$e)
    $g = $e.Graphics; $g.TextRenderingHint = 'AntiAlias'; $r = $s.ClientRectangle; $t = $s.Tag
    $ct = $t.Topo
    if($t.Aceso){ $ct = [System.Drawing.Color]::FromArgb([Math]::Min(255,$ct.R+34),[Math]::Min(255,$ct.G+34),[Math]::Min(255,$ct.B+34)) }
    Hud-Grad $g $r $ct $t.Base
    Hud-Relevo $g $r $HudBronze $HudBronzeEsc
    $fo = Hud-Fonte 8.5
    $m = $g.MeasureString($t.Texto,$fo)
    Hud-Str $g $t.Texto $fo $HudCreme (($r.Width - $m.Width)/2) (($r.Height - $m.Height)/2)
    $fo.Dispose()
  })
  $b.Add_MouseEnter({ param($s,$e) $s.Tag.Aceso = $true;  $s.Invalidate() })
  $b.Add_MouseLeave({ param($s,$e) $s.Tag.Aceso = $false; $s.Invalidate() })
  $b
}
function Set-Barra([double]$pct){   # barra do MR: guarda a fracao e repinta
  # O ProgressBar do WinForms ignora BackColor/ForeColor com visual styles e sai sempre verde do Windows - a
  # unica cor que a HUD do jogo nao tem em lugar nenhum. Aqui ela e desenhada no Paint do painel.
  $script:barraPct = [Math]::Max(0.0,[Math]::Min(1.0,$pct))   # trava: fracao fora de 0..1 daria largura negativa
  if($script:barraBox -and -not $script:barraBox.IsDisposed){ $script:barraBox.Invalidate() }
}
$script:barraPct = 0.0
function Show-Ui {
  $f = New-Object System.Windows.Forms.Form
  # Janelinha COMPACTA (300x200). Nao e so estetica: o Capture-Raw pinta a area dela de PRETO em toda captura pra
  # ela nao sujar o OCR, entao janela menor = menos tela do jogo cega, e o Fugir-Da-Area precisa move-la menos.
  # SEM MOLDURA DO WINDOWS: a barra de titulo cinza era o que mais entregava "isto nao e o jogo". Some com ela o
  # X e o arrastar, entao os dois voltam aqui - PARAR fecha a janela (e o FormClosing faz a parada limpa), e o
  # arrasto e o proprio mouse sobre a pedra. Fechar pelo console continua sendo o que NAO se deve fazer: mata o
  # processo sem salvar o estado, e foi assim que o char ficou inconsistente duas vezes (08/09 e 09/09).
  $f.Text = 'MudinhoX RPA'   # nao aparece mais na tela, mas e o que identifica a janela pro Windows
  $f.Width = 300; $f.Height = 188; $f.TopMost = $true; $f.FormBorderStyle = 'None'
  $f.BackColor = $HudPedraBase; $f.ForeColor = $HudCreme
  # AutoScaleMode 'None' ANTES da fonte: o padrao e 'Font', que reescala os controles filhos a partir da fonte do
  # formulario. Como a grade abaixo esta em pixel fixo, escala automatica so teria como estragar.
  $f.AutoScaleMode = 'None'
  $f.Font = Hud-Fonte 8 'Regular'
  $f.StartPosition = 'Manual'; $f.Location = Canto-Da-Tela-Do-Jogo $f.Height
  # Fundo: degrade de pedra + moldura + titulo espacado + filete separando o cabecalho.
  $f.Add_Paint({
    param($s,$e)
    $g = $e.Graphics; $g.SmoothingMode = 'None'; $g.TextRenderingHint = 'AntiAlias'
    $r = $s.ClientRectangle
    Hud-Grad $g $r $HudPedraTopo $HudPedraBase
    Hud-Moldura $g $r
    # Titulo em BRONZE apagado e pequeno: e rotulo, nao informacao. Ouro aqui competia com a barra, que e a
    # unica coisa da janela que vale olhar de longe. O "RPA" saiu junto - nao dizia nada que o titulo ja nao diga.
    $null = Hud-StrEsp $g 'MUDINHOX' (Hud-Fonte 8) $HudTitulo 10 5 3.0
    $pl = New-Object System.Drawing.Pen($HudBronzeEsc); $g.DrawLine($pl,9,21,($r.Width-10),21); $pl.Dispose()
  })
  # ARRASTAR pela pedra: sem barra de titulo, e o unico jeito de sair da frente de algo que voce quer ver.
  # (O Fugir-Da-Area move a janela por conta propria quando ela tapa o que o bot precisa LER; isto e pra voce.)
  $f.Add_MouseDown({ param($s,$e) if($e.Button -eq 'Left'){ $script:dragDe = [System.Windows.Forms.Cursor]::Position; $script:dragEm = $script:ui.Location } })
  $f.Add_MouseMove({ param($s,$e)
    if($script:dragDe){
      $p = [System.Windows.Forms.Cursor]::Position
      $script:ui.Location = New-Object System.Drawing.Point(($script:dragEm.X + $p.X - $script:dragDe.X), ($script:dragEm.Y + $p.Y - $script:dragDe.Y))
    } })
  $f.Add_MouseUp({ $script:dragDe = $null })
  # SO PAUSAR e PARAR. Os outros seis (TUDO+MR, Warmup, Normal, MIXAR JA, MODO JOIAS, MODO DRAGOES) sairam a
  # pedido do usuario em 12/09: o mix ja dispara sozinho pelo $MixEveryMin, a fase e decidida pelo proprio bot,
  # e o modo dragoes foi removido inteiro.
  $script:btnPause = Hud-Placa 'PAUSAR' 10 27 136 21 $HudPlacaCl $HudPlaca
  $btnParar        = Hud-Placa 'PARAR' 154 27 136 21 $HudSangueCl $HudSangue
  # Barra = caminho ate o proximo /darmr (os 4 atributos do zero ao cap), NAO "quantos resets faltam": reset e so
  # o meio de juntar pontos, e quantos cabem num MR muda com o alvo, com o spot e com a fase. Pontos e o que conta.
  # (A PROJECAO de resets aparece no texto abaixo, que e onde ela pode vir acompanhada do "~".)
  $script:barraBox = New-Object System.Windows.Forms.Panel; $script:barraBox.SetBounds(10,54,280,9)
  $script:barraBox.BackColor = $HudPedraBase
  $script:barraBox.Add_Paint({
    param($s,$e)
    $g = $e.Graphics; $r = $s.ClientRectangle
    # buraco escavado (relevo invertido) com o poco escuro dentro
    $g.FillRectangle((New-Object System.Drawing.SolidBrush($HudPoco)),$r)
    Hud-Relevo $g $r $HudBronzeEsc $HudBronze
    $w = [int](($r.Width - 4) * $script:barraPct)
    if($w -gt 0){
      $fr = New-Object System.Drawing.Rectangle(2,2,$w,($r.Height-4))
      # ouro claro em cima, ouro embaixo: a barra de XP do jogo e lustrosa, nao um bloco de cor
      Hud-Grad $g $fr $HudOuroClaro $HudOuro
      $pl = New-Object System.Drawing.Pen($HudOuroClaro); $g.DrawLine($pl,2,2,(1+$w),2); $pl.Dispose()
    }
    # SEM numero dentro da barra: creme sobre ouro nao se le, e a linha logo abaixo ja diz "MR 62.0%" - eram dois
    # lugares mostrando o mesmo, e o pior deles ficava por cima do unico elemento colorido da janela.
  })
  $script:contador = New-Object System.Windows.Forms.Label; $script:contador.SetBounds(10,67,280,14); $script:contador.Text = '0 resets | 0 MR'
  $script:contador.ForeColor = $HudCreme; $script:contador.BackColor = [System.Drawing.Color]::Transparent
  $script:contador.Font = Hud-Fonte 8
  $script:contador.TextAlign = 'MiddleCenter'
  # Caixa do log num buraco escavado: painel desenha o relevo, o TextBox mora 3px pra dentro.
  $poco = New-Object System.Windows.Forms.Panel; $poco.SetBounds(10,85,280,93); $poco.BackColor = $HudPoco
  $poco.Add_Paint({ param($s,$e) Hud-Relevo $e.Graphics $s.ClientRectangle $HudBronzeEsc $HudBronze })
  # SEM barra de rolagem: o scrollbar do WinForms nao aceita cor e sai branco do sistema - de longe o que mais
  # destoava. O historico de verdade esta no rpa.log, que e onde toda analise deste projeto acontece, e o
  # AppendText ja mantem a ultima linha visivel.
  $script:logBox = New-Object System.Windows.Forms.TextBox; $script:logBox.SetBounds(3,3,274,87)
  # TabStop off: sem moldura do Windows ele era o primeiro controle focavel da janela, pegava o foco ao abrir e
  # aparecia com TODO o texto selecionado em azul do sistema - a cor mais fora de lugar possivel aqui.
  $script:logBox.TabStop = $false
  $script:logBox.Multiline = $true; $script:logBox.ReadOnly = $true; $script:logBox.ScrollBars = 'None'
  $script:logBox.BorderStyle = 'None'; $script:logBox.BackColor = $HudPoco; $script:logBox.ForeColor = $HudLog
  $script:logBox.Font = New-Object System.Drawing.Font('Consolas', 7)
  $poco.Controls.Add($script:logBox)
  $script:btnPause.Add_Click({
    $script:paused = -not $script:paused
    $script:btnPause.Tag.Texto = $(if($script:paused){ 'RETOMAR' } else { 'PAUSAR' })
    $script:btnPause.Tag.Topo  = $(if($script:paused){ $HudOlivaCl } else { $HudPlacaCl })
    $script:btnPause.Tag.Base  = $(if($script:paused){ $HudOliva }   else { $HudPlaca })
    $script:btnPause.Invalidate()
    Log $(if($script:paused){ 'PAUSADO pelo usuario (clique RETOMAR pra voltar)' } else { 'retomado pelo usuario' })
  })
  # PARAR = fechar a janela, a pedido: um caminho so de saida, e ele passa pelo FormClosing (parada limpa).
  $btnParar.Add_Click({ $script:stopReason = 'usuario'; $script:stop = $true; $script:ui.Close() })
  $f.Add_FormClosing({ if(-not $script:stop){ $script:stopReason = 'janela fechada'; $script:stop = $true } })
  $f.Controls.AddRange(@($script:btnPause,$btnParar,$script:barraBox,$script:contador,$poco)); $f.Show(); $script:ui = $f
}

# ---------- janela do jogo / foco ----------
function Is-Admin { ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) }
function Limpar-Watchdog {
  # O watchdog FOI REMOVIDO. Ele era uma Tarefa Agendada de 3 em 3 min que relancava o bot - e relancava tambem
  # o que voce tinha mandado parar, abrindo PowerShell sozinho a madrugada inteira. Nada deste projeto pode
  # continuar rodando depois que voce fecha a janela.
  # Isto aqui so desinstala a tarefa que ficou pra tras de quem ja rodou a versao antiga. O bot ja esta elevado
  # no start, entao apaga sem pedir UAC. Some do codigo quando nao houver mais maquina com a tarefa instalada.
  if(-not (Is-Admin)){ return }
  $null = schtasks /query /tn "$WatchdogTask" 2>&1
  if($LASTEXITCODE -ne 0){ return }   # nao existe: nada a fazer
  $out = schtasks /delete /tn "$WatchdogTask" /f 2>&1
  if($LASTEXITCODE -eq 0){ Log "removi a Tarefa Agendada '$WatchdogTask' (watchdog antigo): nada mais relanca o bot sozinho" }
  else { Log "nao consegui remover a tarefa do watchdog antigo: $out" }
}
function Game-IsAdmin {   # processo elevado nao expoe o Path pra processo comum
  # Na versao WEB o jogo e uma aba do navegador, que NAO roda elevado - some a exigencia de admin que ja custou
  # duas noites aqui (teclas descartadas em silencio). Entao nesse modo a resposta e sempre "nao e elevado".
  if($GameTitle){ return $false }
  -not (Get-Process $GameProc -ErrorAction SilentlyContinue | select -First 1).Path
}
$script:gameH = [IntPtr]::Zero
function Get-Game {   # handle da janela do jogo, EM CACHE: enumerar janela/processo e caro e isto e chamado ~6x por comando
  if($script:gameH -ne [IntPtr]::Zero -and [W]::IsWindow($script:gameH)){ return $script:gameH }
  # VERSAO WEB: o jogo roda numa aba do navegador, entao o processo e 'chrome'/'msedge' e quem identifica e o
  # TITULO da janela. Com $GameTitle preenchido a busca passa a ser por titulo, em qualquer processo.
  # O @( ) EXTERNO nao e decorativo. Sem ele o valor sai do bloco `if` pela pipeline, que DESENROLA o array: com
  # exatamente uma janela casando, $todas virava um PSCustomObject solto - e $obj.Count num PSCustomObject
  # devolve $null, nao 1. Resultado: "nao achei janela" com o jogo aberto na tela, e SO com 1 cliente (com 2+ o
  # array sobrevivia) e SO na web (Get-Process devolve Process, que tem Count=1 de verdade).
  $todas = @(if($GameTitle){
      # EnumWindows, nao Get-Process: o Chrome e multi-processo e o MainWindowTitle expoe UMA janela por
      # processo. Com o jogo aberto numa aba, a unica janela de chrome que aparecia por ali era a barra
      # "... is sharing a window." - a do jogo nao. Aqui varre as janelas de verdade.
      $ts = $null; $hs = [W]::JanelasVisiveis([ref]$ts)
      for($k = 0; $k -lt $hs.Count; $k++){ if($ts[$k] -match $GameTitle){ [pscustomobject]@{ H = $hs[$k]; T = $ts[$k] } } }
    } else {
      Get-Process $GameProc -ErrorAction SilentlyContinue | ? { $_.MainWindowHandle -ne 0 } |
        % { [pscustomobject]@{ H = $_.MainWindowHandle; T = $_.MainWindowTitle } }
    })
  if(-not $todas.Count){
    if(-not $GameTitle){ throw "MudinhoX ($GameProc.exe) nao esta rodando" }
    # O titulo da janela de um navegador e o da ABA ATIVA. Com o jogo numa aba de fundo nao existe janela com esse
    # titulo - e nem adiantaria achar: aba de fundo nao renderiza, a captura sairia velha/preta. Entao, quando ha
    # navegador aberto mas nenhum casa, o problema e a aba, nao a janela; vale dizer isso em vez de "nao achei".
    $ts2 = $null; $null = [W]::JanelasVisiveis([ref]$ts2)
    $nav = @($ts2 | ? { $_ -match '(?i)(google chrome|microsoft.\s*edge)$' })
    if($nav.Count){ throw "o jogo nao esta na aba ATIVA de nenhum navegador (aba de fundo nao renderiza). Abertos: $($nav -join ' | ')" }
    throw "nenhuma janela com titulo casando '$GameTitle' (o jogo web esta aberto?)"
  }
  if($todas.Count -gt 1){ Log "atencao: $($todas.Count) janelas casam '$GameTitle', usando a primeira ($($todas[0].T))" }
  $script:gameH = $todas[0].H; $script:gameH
}
function Set-Foreground($h){   # traz janela pra frente sem teclas sinteticas (AttachThreadInput); fallback: toque no Alt
  if(-not $h -or -not [W]::IsWindow($h) -or [W]::GetForegroundWindow() -eq $h){ return }
  [W]::ShowWindow($h, $(if([W]::IsIconic($h)){ 9 } else { 5 })) | Out-Null   # SW_RESTORE / SW_SHOW: sem isso o SetForegroundWindow e ignorado
  $me = [W]::GetCurrentThreadId(); $fg = [W]::GetWindowThreadProcessId([W]::GetForegroundWindow(),[IntPtr]::Zero)
  [W]::AttachThreadInput($me,$fg,$true) | Out-Null; [W]::SetForegroundWindow($h) | Out-Null; [W]::AttachThreadInput($me,$fg,$false) | Out-Null
  if([W]::GetForegroundWindow() -ne $h){ [W]::keybd_event(0x12,0,0,[UIntPtr]::Zero); [W]::SetForegroundWindow($h) | Out-Null; [W]::keybd_event(0x12,0,2,[UIntPtr]::Zero) }
  Start-Sleep -Milliseconds 500
}
$script:gameWasFg = $true   # jogo ja estava na frente antes do Focus-Game (define o ritmo do poll)
$script:gameFg = $false     # jogo ficou na frente apos o Focus-Game (Windows nega se voce esta digitando em outra janela)
function Is-OwnUi($h){ $script:ui -and -not $script:ui.IsDisposed -and $h -eq $script:ui.Handle }   # janela do proprio bot nao conta como "outra janela"
$script:focusHeld = $false; $script:focusPrev = $null   # bloco de foco: traz o jogo 1x, faz tudo, devolve 1x (menos "pisca" com voce numa janela por cima)
function Focus-Game {
  $h = Get-Game
  if($script:focusHeld){   # dentro de um bloco: nao mexe no prev nem devolve; so garante o jogo na frente
    $script:gameFg = ([W]::GetForegroundWindow() -eq $h); if(-not $script:gameFg){ Set-Foreground $h; $script:gameFg = ([W]::GetForegroundWindow() -eq $h) }; return $script:focusPrev
  }
  $prev = [W]::GetForegroundWindow(); $script:gameWasFg = ($prev -eq $h) -or (Is-OwnUi $prev); Set-Foreground $h; $script:gameFg = ([W]::GetForegroundWindow() -eq $h); $prev
}
function Restore-Focus($prev){   # dentro de bloco nao devolve; senao devolve pra janela anterior (nao a do bot)
  if($script:focusHeld){ return }
  if($prev -and $prev -ne (Get-Game) -and -not (Is-OwnUi $prev)){ Set-Foreground $prev }
}
function Hold-Focus {   # inicia bloco: guarda a janela do usuario, traz o jogo 1x
  if($script:focusHeld){ return }
  $script:focusPrev = [W]::GetForegroundWindow(); $script:gameWasFg = ($script:focusPrev -eq (Get-Game)) -or (Is-OwnUi $script:focusPrev)
  $script:focusHeld = $true
  # Com o jogo noutro monitor NAO adianta puxar o jogo aqui: quase toda volta do loop e so LEITURA, e o
  # $NoFocusRead ja le sem foco. Quem precisa de foco (Send-Chat, Click-Client, Read-Status) chama Focus-Game
  # sozinho, e o Release-Focus devolve no fim do bloco. Antes o foco era roubado uma vez POR VOLTA, sempre -
  # era isso que fazia o bot brigar com voce mesmo quando so ia ler o level.
  if(-not $NoFocusRead){ $null = Focus-Game }
}
function Release-Focus {   # fim do bloco: devolve o foco pra janela do usuario (1x)
  if(-not $script:focusHeld){ return }
  $script:focusHeld = $false; Restore-Focus $script:focusPrev
}
function Client-Origin { $h = Get-Game; $pt = New-Object W+POINT; [W]::ClientToScreen($h,[ref]$pt) | Out-Null; $pt }
# ---------- ver a janela sem roubar o teclado ----------
function Ver-Janela {   # sobe a janela do jogo na pilha, SEM ativar. Barato (ms) e nao tira o foco de onde voce esta.
  # A leitura sai de CopyFromScreen, que pega o que esta NA TELA: com outra janela por cima, le lixo. Trazer pra
  # ver com SetForegroundWindow custaria o foco do sistema inteiro e ~2s (e o seu teclado no meio da digitacao);
  # aqui e so Z-order. VER e DIGITAR sao coisas diferentes - so digitar exige primeiro plano de verdade (medido:
  # PostMessage e AttachThreadInput+SetFocus nao funcionam neste cliente, ver test_entrada_sem_foco.ps1).
  # SEMPRE sobe, sem perguntar antes. Houve aqui um atalho que pulava o SetWindowPos quando o WindowFromPoint do
  # CENTRO ja dizia "e o jogo" - economizava 60ms por captura. Custou 13/09: o centro nao prova que o RESTO da
  # janela esta destapado, e com o jogo nao sendo mais trazido pra cima a leitura passou a pegar tela de outra
  # janela (5 leituras recusadas com "a captura pegou outra janela"). 60ms nao pagam isso.
  # HWND_TOP=0, SWP_NOSIZE=1 | SWP_NOMOVE=2 | SWP_NOACTIVATE=0x10 = 0x13
  [W]::SetWindowPos((Get-Game), [IntPtr]::Zero, 0,0,0,0, 0x13) | Out-Null
  Start-Sleep -Milliseconds 60   # o compositor precisa de um frame pra desenhar por cima do que estava na frente
}
# Houve aqui uma Janela-Na-Frente: WindowFromPoint no centro da area cliente, pra provar que os pixels eram mesmo
# do jogo. Fazia sentido no MULTIBOX, onde dois clientes empilhados no mesmo ponto da tela liam um o jogo do
# outro. Com um cliente so ela nunca pegou nada de verdade e produziu falso negativo: 13/09, 5 leituras boas
# recusadas e a distribuicao parada no meio. Saiu junto com o multibox, um dia atrasada.
$script:capOk = $true   # a ultima captura foi mesmo do jogo? (Read-Status/Inv-Free usam pra nao ler nem salvar print de outra janela)
function Capture-Raw {   # bitmap da area cliente, sem mexer no foco (so chamar com o jogo na frente). Janelinha do bot fica preta (nao suja OCR/pixels)
  $h = Get-Game; $b = $null
  # Janela fechando/minimizando devolve area cliente 0x0, e New-Object Bitmap(0,0) estoura com "Parametro
  # invalido" - erro que o catch do loop principal trata como fatal e PARA o bot. Visto ao vivo, num restart do
  # mudx. Com a mensagem 'nao esta rodando' ele cai no caminho que ja existe: espera o cliente voltar e retoma.
  $c0 = New-Object W+RECT; [W]::GetClientRect($h,[ref]$c0) | Out-Null
  if($c0.R -le 0 -or $c0.B -le 0){ $script:gameH = [IntPtr]::Zero; throw "MudinhoX (mudx.exe) nao esta rodando: janela sem area cliente (minimizada ou fechando)" }
  Ver-Janela   # sobe a janela do jogo (sem roubar teclado) antes de fotografar
  for($i = 0; $i -lt 2; $i++){
    $c = New-Object W+RECT; [W]::GetClientRect($h,[ref]$c) | Out-Null; $o = Client-Origin
    $b = New-Object System.Drawing.Bitmap($c.R,$c.B); $g = [System.Drawing.Graphics]::FromImage($b)
    $g.CopyFromScreen($o.X,$o.Y,0,0,$b.Size)
    if($script:ui -and -not $script:ui.IsDisposed){ $r = $script:ui.Bounds; $g.FillRectangle([System.Drawing.Brushes]::Black, $r.X-$o.X, $r.Y-$o.Y, $r.Width, $r.Height) }
    $g.Dispose()
    # confere DEPOIS da foto: so checar antes nao basta, outra janela sobe no meio e o bot acaba lendo (e salvando print d)a tela do usuario
    # Este teste ja foi o WindowFromPoint do centro da area cliente (herdado do multibox, onde dois clientes
    # empilhados no mesmo ponto liam um o jogo do outro). Com UM cliente ele so produziu falso negativo: em
    # 13/09 recusou 5 leituras boas com "a captura pegou outra janela" e parou a distribuicao no meio. O
    # $NoFocusRead ja carrega a promessa que importa aqui - o jogo fica destapado noutro monitor -, e o
    # Ver-Janela acima sobe a janela antes de toda foto.
    $script:capOk = $NoFocusRead -or ([W]::GetForegroundWindow() -eq $h)
    if($script:capOk){ return $b }
    $b.Dispose(); $b = $null
    if($i -eq 0){ Set-Foreground $h; Start-Sleep -Milliseconds 250 }   # uma re-tentativa; se ainda nao vier pra frente, devolve a foto marcada como suspeita
  }
  $c = New-Object W+RECT; [W]::GetClientRect($h,[ref]$c) | Out-Null; $o = Client-Origin
  $b = New-Object System.Drawing.Bitmap($c.R,$c.B); $g = [System.Drawing.Graphics]::FromImage($b)
  $g.CopyFromScreen($o.X,$o.Y,0,0,$b.Size); $g.Dispose(); $script:capOk = $false; $b
}
function Capture-Game {   # bitmap da area cliente, ou $null se o jogo nao ficou na frente (nunca le/clica em outra janela)
  if($NoFocusRead){ $script:gameWasFg = $true; return Capture-Raw }   # jogo sempre visivel: LER nao precisa roubar o foco (comandos ainda precisam)
  $prev = Focus-Game
  if(-not $script:gameFg){ Restore-Focus $prev; Log "jogo nao esta na frente (outra janela ativa), pulando leitura"; return $null }
  $b = Capture-Raw; Restore-Focus $prev; $b
}

# ---------- input ----------
$script:teclaAviso = $null
function Press-Vk([int]$vk,[int]$hold=$KeyHoldMs,[int]$gap=$KeyGapMs){
  # REDE DE SEGURANCA: keybd_event e GLOBAL, vai pra janela que estiver na frente. Com o jogo noutro monitor o
  # bot passa a maior parte do tempo sem o foco, e um ESC/Enter/C perdido cairia no que VOCE esta fazendo.
  # A guarda fica AQUI, no primitivo, e nao em cada chamador: assim nenhum caminho novo pode esquecer dela.
  # Nao devolve valor de proposito - Press-Vk e chamado como statement dentro de funcoes cujo retorno importa.
  if([W]::GetForegroundWindow() -ne (Get-Game)){
    if(-not $script:teclaAviso -or ((Get-Date) - $script:teclaAviso).TotalSeconds -ge 60){
      $script:teclaAviso = Get-Date; Log "tecla ignorada: o jogo nao esta na frente (nao digito na sua janela)"
    }
    return
  }
  $sc = [W]::MapVirtualKey($vk,0); [W]::keybd_event($vk,$sc,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds $hold; [W]::keybd_event($vk,$sc,2,[UIntPtr]::Zero); Start-Sleep -Milliseconds $gap
}
function Clear-ChatLine { 1..30 | % { Press-Vk 0x08 $KeyClearMs $KeyClearMs } }   # apaga residuo da caixa de chat (30 backspaces: o gap normal aqui custava 2.4s)
function Type-Text([string]$s){   # $KeyHoldMs de hold + $KeyGapMs de gap por tecla (abaixo de ~30ms comeca a embaralhar)
  foreach($ch in $s.ToCharArray()){
    $k = [W]::VkKeyScan($ch); $vk = $k -band 0xFF; $shift = ($k -shr 8) -band 1
    if($shift){ [W]::keybd_event(0x10,0x2A,0,[UIntPtr]::Zero) }
    Press-Vk $vk
    if($shift){ [W]::keybd_event(0x10,0x2A,2,[UIntPtr]::Zero) }
  }
}
function Chat-Open($img){   # caixa de chat aberta = bordas vermelhas em cima e embaixo (Enter alterna, entao o estado PRECISA estar certo)
  # Antes checava DUAS linhas exatas (111 e 87 a partir da base). Medido num print de falha real: as bordas estavam
  # em 117-118 e 92-93 - a caixa desceu ~6px e as duas linhas fixas deram ZERO vermelho. Com isso Chat-Open dizia
  # "fechada" com a caixa aberta, o Close-Chat nao fechava, e o C do status virava LETRA dentro do chat.
  # Era a causa do "nao consegui ler o status" a sessao inteira. Agora varre a FAIXA e conta linhas vermelhas.
  # 12/09: a FAIXA e a largura viraram FRACAO da area cliente. A borda nao e texto, entao nao ha OCR possivel -
  # mas dava pra parar de cravar pixel. O que identifica a caixa e uma LINHA VERMELHA CONTINUA e longa: o orbe
  # de vida tambem e vermelho, so que redondo, entao a corrida continua dele por linha e curta. E o comprimento
  # da corrida, em fracao da largura, que separa os dois - nao a posicao.
  $own = -not $img; if($own){ $img = Capture-Raw }
  $linhas = 0
  try {
    $x1 = [int]($img.Width * $ChatFaixa.X1); $x2 = [int]($img.Width * $ChatFaixa.X2)
    $yIni = [int]($img.Height * $ChatFaixa.Y1FromBottom); $yFim = [int]($img.Height * $ChatFaixa.Y2FromBottom)
    $minRun = [int]($img.Width * $ChatFaixa.MinRun)
    for($yb = $yIni; $yb -ge $yFim; $yb--){
      $y = $img.Height - $yb
      if($y -lt 0 -or $y -ge $img.Height){ continue }
      $run = 0; $maior = 0
      for($x = $x1; $x -le $x2 -and $x -lt $img.Width; $x += 4){   # passo 4: a borda e linha continua, nao precisa de todo pixel
        $p = $img.GetPixel($x,$y)
        if($p.R -gt 150 -and $p.G -lt 100 -and $p.B -lt 100){ $run += 4; if($run -gt $maior){ $maior = $run } } else { $run = 0 }
      }
      if($maior -ge $minRun){ $linhas++ }
    }
  } catch { $linhas = 0 }
  $aberta = ($linhas -ge 2)   # borda de cima + borda de baixo
  # SEGUNDA PROVA, por TEXTO. A borda vermelha existe num estado do chat e NAO existe noutro: no print de
  # 15/09 02:17 a caixa estava visivelmente aberta ("Whisper" e "Digite sua mensagem" na tela) e a faixa inteira
  # tinha no maximo 4px de corrida vermelha contra os 115 exigidos - o detector dizia FECHADO.
  # O estrago disso e grande e silencioso: com o chat aberto a tecla C vira LETRA, o painel de status nunca abre
  # ("nao abriu em 6 tentativas") e o /resetar vira hotkey. E o caminho que existia pra corrigir - o
  # Unstick-Tudo fechar o chat - so roda se esta funcao acertar.
  # A palavra "Whisper" separou os dois grupos em 7 imagens, sem um erro: aparece nas 3 com chat aberto
  # (inclusive a de hoje, sem borda) e em NENHUMA das 4 fechadas. Custa 56ms medidos, e so e paga quando a
  # borda ja disse "fechado" - com o chat aberto de verdade a borda costuma resolver antes.
  if(-not $aberta){
    try {
      $h = [int]($img.Height * $ChatTxtFaixa); $y0 = $img.Height - $h
      if($h -gt 8){
        $c = Crop-Bitmap $img 0 $y0 $img.Width $h
        $txt = (Ocr-Bitmap $c).Text; $c.Dispose()
        if($txt -match $ChatTxtWords){ $aberta = $true }
      }
    } catch {}
  }
  if($own){ $img.Dispose() }
  $aberta
}
function Close-Chat { if(Chat-Open){ Clear-ChatLine; Press-Vk 0x0D; Start-Sleep -Milliseconds 200 } }   # apaga residuo e fecha (Enter vazio fecha); chamar com o jogo na frente
$script:semFgDesde = $null; $script:semFgN = 0
function Send-Chat([string]$text){   # $false se o jogo nao ficou na frente (nao digita em outra janela)
  $prev = Focus-Game
  if(-not $script:gameFg){
    # NAO insiste mais forte de proposito: o Windows recusa o primeiro plano pra processo de fundo justamente
    # quando VOCE esta usando o PC, e roubar a tela nessa hora e o que o bot nao pode fazer. Ele espera.
    # Mas 53 linhas identicas (9min20 em 12/09) enterravam o resto do log, e o log e como todo bug serio deste
    # projeto foi achado. Entao loga a PRIMEIRA e o fim, com o custo medido.
    $script:semFgN++
    if($script:semFgN -eq 1){ $script:semFgDesde = Get-Date; Log "jogo nao esta na frente, nao enviei '$text' (esperando a janela liberar; so aviso de novo quando voltar)" }
    return $false
  }
  if($script:semFgN){
    Log "jogo voltou pra frente apos $([Math]::Round(((Get-Date) - $script:semFgDesde).TotalMinutes,1)) min e $($script:semFgN) comando(s) nao enviado(s)"
    $script:semFgN = 0
  }
  $img = Capture-Raw   # uma captura so decide o estado da caixa (antes eram duas, uma por Chat-Open)
  $aberta = Chat-Open $img; $img.Dispose()
  if($aberta){ Clear-ChatLine } else { Press-Vk 0x0D; Start-Sleep -Milliseconds $ChatOpenMs }   # ja aberta (residuo seu?) -> so apaga; fechada -> Enter abre
  Log "chat: $text"; Type-Text $text; Start-Sleep -Milliseconds $ChatSendMs; Press-Vk 0x0D
  Start-Sleep -Milliseconds $ChatSendMs; if(Chat-Open){ Press-Vk 0x0D }   # se continuou aberta apos enviar, Enter vazio fecha (senao letras viram hotkey)
  Restore-Focus $prev; $true
}
function Click-Client([int]$x,[int]$y,[switch]$KeepFocus){   # $false se o jogo nao ficou na frente. -KeepFocus: nao MEXE no foco (varios cliques em sequencia) - mas continua CONFERINDO
  if($KeepFocus){
    # -KeepFocus nao pode significar "clica sem olhar": se a janela do usuario subiu, o clique cairia DENTRO do programa dele
    if([W]::GetForegroundWindow() -ne (Get-Game)){ Log "jogo nao esta na frente, nao cliquei (KeepFocus)"; return $false }
  } else { $prev = Focus-Game; if(-not $script:gameFg){ Log "jogo nao esta na frente, nao cliquei"; return $false } }
  # Com o jogo noutro monitor o ponteiro e SEU: guarda onde estava e devolve depois do clique. Devolver so
  # DEPOIS do mouse_up - mexer antes disso e clique que o jogo nao registra.
  $volta = $null
  if($NoFocusRead){ $pc = New-Object W+POINT; if([W]::GetCursorPos([ref]$pc)){ $volta = $pc } }
  $o = Client-Origin; [W]::SetCursorPos($o.X+$x,$o.Y+$y) | Out-Null; Start-Sleep -Milliseconds 80
  [W]::mouse_event(2,0,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 50; [W]::mouse_event(4,0,0,0,[UIntPtr]::Zero)
  if($volta){ Start-Sleep -Milliseconds 60; [W]::SetCursorPos($volta.X,$volta.Y) | Out-Null }
  if(-not $KeepFocus){ Restore-Focus $prev }; $true
}

# ---------- leitura de tela ----------
$asTask = [System.WindowsRuntimeSystemExtensions].GetMethods() | ? { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' } | select -First 1
function Await($op,$type){ $t = $asTask.MakeGenericMethod($type).Invoke($null,@($op)); $t.Wait(); $t.Result }
$ocr = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage((New-Object Windows.Globalization.Language('pt-BR')))
function Ocr-Bitmap([System.Drawing.Bitmap]$b){   # retorna OcrResult (.Text, .Lines[].Words[].BoundingRect)
  $ms = New-Object System.IO.MemoryStream; $b.Save($ms,[System.Drawing.Imaging.ImageFormat]::Bmp)
  $ras = New-Object Windows.Storage.Streams.InMemoryRandomAccessStream
  $dw = New-Object Windows.Storage.Streams.DataWriter($ras.GetOutputStreamAt(0)); $dw.WriteBytes($ms.ToArray())
  $null = Await ($dw.StoreAsync()) ([uint32]); $null = Await ($dw.FlushAsync()) ([bool])
  $dec = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($ras)) ([Windows.Graphics.Imaging.BitmapDecoder])
  $sb  = Await ($dec.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
  Await ($ocr.RecognizeAsync($sb)) ([Windows.Media.Ocr.OcrResult])
}
function Crop-Bitmap($src,[int]$x,[int]$y,[int]$w,[int]$h,[int]$scale=1,[int]$pad=0){   # pad = margem branca em volta (ajuda o OCR)
  $o = New-Object System.Drawing.Bitmap(($w*$scale+2*$pad),($h*$scale+2*$pad)); $g = [System.Drawing.Graphics]::FromImage($o)
  if($pad){ $g.Clear([System.Drawing.Color]::White) }
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.DrawImage($src,(New-Object System.Drawing.Rectangle($pad,$pad,($w*$scale),($h*$scale))),(New-Object System.Drawing.Rectangle($x,$y,$w,$h)),[System.Drawing.GraphicsUnit]::Pixel)
  $g.Dispose(); $o
}
# OCR do Windows e caprichoso com numeros curtos (x8 sem margem le quase tudo mas falha em "400"; x4 com margem le 400 mas
# confunde 7 com 1). Le nas 4 variantes e vota; empate = ordem abaixo (mais confiavel primeiro).
$LevelOcrVariants = @( @{S=8;Pad=0;Inv=$false}, @{S=8;Pad=40;Inv=$true}, @{S=4;Pad=40;Inv=$false}, @{S=4;Pad=0;Inv=$false} )
# O rotulo do minimapa e "Nome X,Y" (ex "Lorencia 132,125"). A COORDENADA e a ancora: nenhuma outra coisa na
# tela tem a forma "numero,numero" grudada. Achando ela, o nome do mapa e a palavra a ESQUERDA na mesma linha -
# mesma ideia do Parse-Attrs, que acha "Forca" e pega o numero a direita.
# Assim o rotulo e encontrado ONDE ELE ESTIVER: serve pro cliente desktop em 1920x1009 e pra aba do Chrome em
# 1024x720, sem $MapLabel cravado e sem recalibrar quando a janela muda de tamanho.
$script:mapaBox = $null   # onde o rotulo foi achado da ultima vez (evita OCR de tela cheia a cada leitura)
function Achar-Rotulo-Mapa($img){   # devolve @{Nome; Box} ou $null. OCR da tela toda - caro, entao o chamador cacheia
  $ws = @((Ocr-Bitmap $img).Lines | % { $_.Words })
  # topo primeiro: o minimapa fica em cima e uma mensagem de chat com "12,5" cairia embaixo
  foreach($co in ($ws | ? { $_.Text -match '^\d{1,4},\d{1,4}$' } | sort { $_.BoundingRect.Y })){
    $yc = $co.BoundingRect.Y + $co.BoundingRect.Height/2
    $nome = $ws | ? {
        $_.Text -match '^[A-Za-z]{3,}$' -and $_.BoundingRect.X -lt $co.BoundingRect.X -and
        [Math]::Abs(($_.BoundingRect.Y + $_.BoundingRect.Height/2) - $yc) -lt ($co.BoundingRect.Height + 6)
      } | sort { -$_.BoundingRect.X } | select -First 1   # a palavra imediatamente a esquerda
    if($nome){
      $r = $nome.BoundingRect
      return @{ Nome = ($nome.Text -replace '[^A-Za-z]','').ToLower()
                Box  = @{ X = [int]$r.X - 8; Y = [int]$r.Y - 6; W = [int]$r.Width + 60; H = [int]$r.Height + 12 } }
    }
  }
  $null
}
function Read-Map($img){   # nome do mapa (rotulo do minimapa) em minusculo, ou '' se nao leu. Com $img=$null captura sozinho
  $own = -not $img; if($own){ $img = Capture-Game }; if(-not $img){ return '' }
  $out = ''
  try {
    # 1) caixa que ja funcionou: recorte pequeno, barato. E o caminho normal.
    if($script:mapaBox){
      $b = $script:mapaBox
      if($b.X -ge 0 -and $b.Y -ge 0 -and ($b.X + $b.W) -le $img.Width -and ($b.Y + $b.H) -le $img.Height){
        $c = Crop-Bitmap $img $b.X $b.Y $b.W $b.H 4
        $out = ((Ocr-Bitmap $c).Text -replace '[^A-Za-z]','').ToLower(); $c.Dispose()
      }
      if(-not $out){ $script:mapaBox = $null }   # mudou de lugar (ou janela redimensionada): procura de novo
    }
    # 2) nao tinha caixa, ou ela parou de servir: acha o rotulo na tela inteira e GUARDA onde estava
    if(-not $out){
      $achou = Achar-Rotulo-Mapa $img
      if($achou){ $out = $achou.Nome; $script:mapaBox = $achou.Box }
    }
  } catch { $out = '' }
  if($own){ $img.Dispose() }
  if(-not $out){ Unblock-MapLabel }   # nao leu nada: pode ser a JANELA DO BOT em cima do rotulo (Capture-Raw pinta ela de preto)
  $out
}
function Fugir-Da-Area([int]$x,[int]$y,[int]$w,[int]$h,[string]$oque){   # a janelinha do bot e pintada de PRETO na captura:
  # se ela cobre algo que o bot precisa LER, ele se cega sozinho. Ja aconteceu com o rotulo do minimapa e com a
  # grade do inventario. Aqui ela foge pro canto inferior esquerdo, que nao tem nada lido (play=topo-esq,
  # minimapa=topo-dir, inventario=dir, chat e level=centro-baixo).
  if(-not $script:ui -or $script:ui.IsDisposed){ return $false }
  $o = Client-Origin; $r = $script:ui.Bounds
  $ax = $o.X + $x; $ay = $o.Y + $y
  if($r.Left -lt ($ax + $w) -and $r.Right -gt $ax -and $r.Top -lt ($ay + $h) -and $r.Bottom -gt $ay){
    $script:ui.Location = Canto-Da-Tela-Do-Jogo $script:ui.Height   # canto do monitor DO JOGO (era o primario, que com o jogo no monitor 2 e o lado errado)
    Log "janela do bot estava em cima de: $oque (o bot se cegava sozinho). Movi pro canto inferior esquerdo."
    return $true
  }
  $false
}
function Unblock-Areas {   # chamado quando uma leitura falha, e no start
  # Rotulo do minimapa: usa ONDE ELE FOI ACHADO (Read-Map guarda em $script:mapaBox). Antes era o $MapLabel
  # cravado, que so valia em 1920x1009 - na aba do Chrome em 1024x720 apontaria pro lugar errado.
  if($script:mapaBox){ $b = $script:mapaBox; $null = Fugir-Da-Area $b.X $b.Y $b.W $b.H 'rotulo do minimapa' }
  # A grade do inventario nao tem posicao fixa e nao ha ancora enquanto ela esta FECHADA, entao aqui e a regiao
  # onde ela costuma abrir - mas em FRACAO da area cliente, nao em pixel. Da os mesmos ~(560,300,1060,420) em
  # 1920x1009 e acompanha sozinho qualquer outro tamanho de janela.
  try {
    $c = New-Object W+RECT; [W]::GetClientRect((Get-Game),[ref]$c) | Out-Null
    if($c.R -gt 0 -and $c.B -gt 0){
      $null = Fugir-Da-Area ([int]($c.R*0.29)) ([int]($c.B*0.30)) ([int]($c.R*0.55)) ([int]($c.B*0.42)) 'area onde o inventario costuma abrir'
    }
  } catch {}
}
function Unblock-MapLabel { Unblock-Areas }   # nome antigo, mantido pelos chamadores
function Pixels-Sao-Do-Jogo {   # os pixels da area cliente sao MESMO da janela do jogo?
  # Pergunta ao Windows quem esta nos pixels, em vez de confiar no Z-order que o Ver-Janela pediu: uma janela
  # TopMost de outro programa continua por cima. Usada SO pra decidir se um print pode ir pro disco.
  # A assimetria e de proposito. Pra LER, este teste ja deu falso negativo e travou leitura boa (13/09), entao
  # la vale o teste simples. Pra SALVAR e o contrario: falso negativo custa um diagnostico perdido, falso
  # positivo grava a TELA DO USUARIO num diretorio que sincroniza pra nuvem. Na duvida, nao salva.
  try {
    $h = Get-Game; $c = New-Object W+RECT; [W]::GetClientRect($h,[ref]$c) | Out-Null
    if($c.R -le 0 -or $c.B -le 0){ return $false }
    $o = Client-Origin; $p = New-Object W+POINT
    $p.X = $o.X + [int]($c.R/2); $p.Y = $o.Y + [int]($c.B/2)
    $w = [W]::WindowFromPoint($p)
    if($w -eq [IntPtr]::Zero){ return $false }
    ($w -eq $h) -or ([W]::GetAncestor($w, 2) -eq $h)   # GA_ROOT=2: o ponto pode cair num controle filho do jogo
  } catch { $false }
}
function Salvar-Print($img, [string]$nome){   # grava print de diagnostico SO se a tela for mesmo a do jogo
  # Em 15/09 o captcha\status_ultimo.png guardado nesta pasta era a tela do VS CODE do usuario. O Read-Status
  # salva o print justamente quando FALHA - e ele falha quando o jogo perdeu o foco, ou seja, exatamente quando
  # ha outra janela por cima. Sem guarda, o diagnostico virava captura de tela alheia, num diretorio que pode
  # estar sincronizando pra nuvem. Ja tinha acontecido antes e a protecao morava no $capOk; quando o
  # $NoFocusRead passou a dispensar foco, o $capOk virou sempre-verdadeiro e a protecao sumiu junto.
  if(-not $img){ return '' }
  if(-not (Pixels-Sao-Do-Jogo)){ Log "print '$nome' NAO salvo: a tela nao e a do jogo agora (nao gravo a sua janela)"; return '' }
  New-Item -ItemType Directory -Force $CaptchaShotDir | Out-Null
  $f = Join-Path $CaptchaShotDir $nome
  try { $img.Save($f) } catch { return '' }
  $f
}
function Save-Shot([string]$nome){   # print pra diagnostico; descarta se a tela nao for a do jogo
  $img = Capture-Game; if(-not $img){ return '' }
  $f = Salvar-Print $img $nome; $img.Dispose(); $f
}
$script:modo = 'reset'   # 'reset' = ciclo normal (farm/reset/darmr). 'joias' = farma ate encher, mixa, repete
$script:farmMap = ''; $script:phase = 'normal'; $script:warmupCount = 0; $script:restartCycle = $false; $script:forceMR = $false
# Cota diaria de master resets. mrsDia conta os de HOJE (mrs, do estado, e da vida inteira do char). cotaJoias
# lembra que foi a COTA que ligou o modo joias - sem isso, virar o dia arrancaria voce de um modo joias que
# VOCE escolheu. Os tres vao pro estado.txt: reiniciar o bot nao pode ser jeito de furar a cota.
$script:mrsDia = 0; $script:mrsDiaData = ''; $script:cotaJoias = $false
function Hoje { (Get-Date).ToString('yyyy-MM-dd') }
# Sync-BotoesModo REMOVIDO em 12/09 junto com os botoes de modo. Ela existia pra manter texto e cor dos botoes
# coerentes com o $script:modo (de seis lugares que faziam isso na mao). Sem botoes, o modo nao tem o que
# refletir - mas o MODO em si continua, porque o descanso da cota diaria usa 'joias'.
# Virou um log: quando o BOT troca de modo sozinho, isso tem que aparecer em algum lugar.
function Sync-BotoesModo { Log "modo agora: $($script:modo)" }
function Cota-Rolar {   # virou o dia? zera a cota de master resets e, se foi ELA que ligou o modo joias, volta a resetar
  if($script:mrsDiaData -eq (Hoje)){ return }
  $ontem = $script:mrsDiaData; $script:mrsDiaData = Hoje
  if($ontem){ Log "cota diaria: virou o dia ($ontem -> $($script:mrsDiaData)), zerando os $($script:mrsDia) master resets contados" }
  $script:mrsDia = 0
  if($script:cotaJoias){
    $script:cotaJoias = $false
    if($script:modo -eq 'joias'){ $script:modo = 'reset'; $script:restartCycle = $true; Sync-BotoesModo }   # so sai do joias se ainda estiver nele (voce pode ter trocado na mao)
    Log "cota diaria: descanso terminado, voltando ao ciclo de reset/master reset"
    Notify "MudinhoX" "Dia novo: cota de $MrsPorDia master resets zerada, voltei a resetar."
  }
  Save-Estado
}
function Save-Estado {   # fase/warmup E as metricas do MR. Medir um MR leva horas e reiniciar o bot zerava tudo.
  try {
    @(
      "fase=$($script:phase)"
      "modo=$($script:modo)"
      "warmup=$($script:warmupCount)"
      "spotTeste=$(if($script:spotTeste){1}else{0})"
      "spotTesteIni=$($script:spotTesteIni.Ticks)"
      "resets=$($script:resets)"
      "ptsSent=$($script:ptsSent)"
      "runStart=$($script:runStart.Ticks)"
      "ativoSeg=$([int]$script:ativoSeg)"
      "joiasMix=$($script:joiasMix)"
      "joiasCiclos=$($script:joiasCiclos)"
      "mrs=$($script:mrs)"
      "mrsDia=$($script:mrsDia)"
      "mrsDiaData=$($script:mrsDiaData)"
      "cotaJoias=$(if($script:cotaJoias){1}else{0})"
      "mrStart=$($script:mrStart.Ticks)"
      "mixLast=$($script:mixLast.Ticks)"
      "ciclos=$(@($script:ciclos) -join ",")"
      "alvo=$TargetLevel"
      "tuneOn=$(if($script:tuneOn){1}else{0})"
      # Progresso do A/B. Sem isto o experimento NUNCA termina: cada restart zerava o contador do braco, e com
      # 15 resets por braco e o bot caindo de tempos em tempos, o log de 11h so registrou o 1o braco fechando.
      "tuneArm=$($script:tuneArm)"
      "tuneResets=$($script:tuneResets)"
      "tunePts=$($script:tunePts)"
      "tuneAtivo0=$([int]$script:tuneAtivo0)"
      # @(...) e o ? antes do %: `$null | %{}` roda o bloco UMA vez com $_ nulo, e $_[0] em $null lanca
      # "Cannot index into a null array" - o try/catch do Save-Estado engolia e o estado.txt inteiro nao era escrito.
      "tuneRes=$(@(@($script:tuneRes) | ? { $_ } | % { "$($_[0]):$($_[1])" }) -join '|')"
      "minReset=$($script:LevelMinReset)"
      # Nome do mapa do spot, aprendido no primeiro teleporte quando o $WarpMap do CONFIG esta vazio.
      # Junto com o comando: se voce trocar o $WarpCmd, o nome antigo nao pode continuar valendo.
      "warpCmd=$WarpCmd"
      "warpMap=$WarpMap"
      # Veredito do servidor sobre comando abaixo do piso (0 nao perguntei / 1 aceita / -1 recusa). E uma
      # pergunta que se faz UMA vez na vida: sem gravar, cada restart gastaria um /f e uma leitura de status.
      "statMinOk=$($script:statMinOk)"
      # Memoria dos atributos. Sem isto, reiniciar o bot apaga o unico valor que ele tem de uma linha que o OCR
      # nao le - e a distribuicao inteira volta a travar ate o proximo (improvavel) acerto do OCR.
      "statCarry=$(@(@('For','Agi','Vit','Ene') | ? { $null -ne $script:stCarry[$_] } | % { "$_`:$($script:stCarry[$_])" }) -join '|')"
    ) | Set-Content -Path $EstadoFile -Encoding ASCII
  } catch {}
}
function Load-Estado {
  if(-not (Test-Path $EstadoFile)){ return }
  try {
    $txt = (Get-Content $EstadoFile -Raw).Trim()
    if($txt -notmatch '='){   # formato antigo "fase warmup"
      $p = $txt -split '\s+'
      if($p[0] -in 'normal','warmup'){ $script:phase = $p[0]; $script:warmupCount = [int]$p[1] }
    } else {
      $kv = @{}; foreach($l in ($txt -split "`r?`n")){ if($l -match '^(\w+)=(.*)$'){ $kv[$Matches[1]] = $Matches[2] } }
      if($kv.fase -in 'normal','warmup'){ $script:phase = $kv.fase }
      # 'dragoes' saiu da lista em 12/09 junto com o modo. Um estado.txt antigo com modo=dragoes cai fora daqui
      # e o bot comeca em 'reset' - que e o certo, porque o Ciclo-Dragoes nao existe mais pra atender.
      if($kv.modo -in 'reset','joias'){ $script:modo = $kv.modo }
      if($kv.warmup){ $script:warmupCount = [int]$kv.warmup }
      # O teste do spot normal atravessa restart: sem isto, uma queda no meio do teste voltaria o bot pro warmup
      # (ou o deixaria testando pra sempre, com o relogio zerado a cada start).
      if($kv.spotTeste){ $script:spotTeste = ($kv.spotTeste -eq '1') }
      if($kv.spotTesteIni){ $script:spotTesteIni = [datetime]::new([long]$kv.spotTesteIni) }
      if($kv.resets){ $script:resets = [int]$kv.resets }
      if($kv.ptsSent){ $script:ptsSent = [int]$kv.ptsSent }
      if($kv.mrs){ $script:mrs = [int]$kv.mrs }
      # Cota do dia: so vale se for do MESMO dia. Estado de ontem entra zerado - e por isso que o bot "volta
      # sozinho no dia seguinte" mesmo se a maquina tiver ficado desligada a noite toda.
      if($kv.mrsDiaData -eq (Hoje)){
        if($kv.mrsDia){ $script:mrsDia = [int]$kv.mrsDia }
        if($kv.cotaJoias){ $script:cotaJoias = ($kv.cotaJoias -eq '1') }
      } elseif($kv.mrsDia -and [int]$kv.mrsDia -gt 0){
        Log "cota diaria: o estado e de $($kv.mrsDiaData), hoje e $(Hoje) - contagem de master resets zerada"
        if($kv.cotaJoias -eq '1' -and $script:modo -eq 'joias'){ $script:modo = 'reset'; Log "cota diaria: o modo joias tinha sido a COTA de ontem, voltando ao ciclo de reset" }
      }
      $script:mrsDiaData = Hoje
      if($kv.runStart){ $script:runStart = [datetime]::new([long]$kv.runStart) }
      if($kv.ativoSeg){ $script:ativoSeg = [double]$kv.ativoSeg }
      if($kv.joiasMix){ $script:joiasMix = [int]$kv.joiasMix }
      if($kv.joiasCiclos){ $script:joiasCiclos = [int]$kv.joiasCiclos }
      if($kv.mrStart){ $script:mrStart = [datetime]::new([long]$kv.mrStart) }
      # O relogio do mix TEM que sobreviver a reinicio. Ele vivia so em memoria, entao cada abertura do bot
      # voltava o contador a zero - e com $MixEveryMin em 25 min bastava reabrir mais cedo que isso pra ele
      # NUNCA chegar. Medido em 15/09: 15 reinicios num dia, maior janela ininterrupta de 14 min, ZERO mixagens
      # numa sessao inteira. "25 min farmando" e propriedade do inventario do personagem, nao do processo -
      # entao mora no estado.txt junto com o resto do estado do MR.
      if($kv.mixLast){ $script:mixLast = [datetime]::new([long]$kv.mixLast) }
      if($kv.ciclos){ $script:ciclos = @($kv.ciclos -split "," | ? { $_ }) }
      # O alvo do estado.txt so vale quando foi o A/B que o escolheu. Com $AutoTune desligado quem manda e o
      # CONFIG - senao um alvo antigo gravado pelo experimento sobrescreveria a sua decisao pra sempre.
      if($kv.alvo -and $AutoTune){ $script:TargetLevel = [int]$kv.alvo }
      if($kv.tuneOn -eq "0"){ $script:tuneOn = $false; Log "autotune ja concluido antes: alvo $($script:TargetLevel)" }
      if($kv.tuneArm){ $script:tuneArm = [int]$kv.tuneArm }
      if($kv.tuneResets){ $script:tuneResets = [int]$kv.tuneResets }
      if($kv.tunePts){ $script:tunePts = [int]$kv.tunePts }
      if($kv.tuneAtivo0){ $script:tuneAtivo0 = [double]$kv.tuneAtivo0 }
      if($kv.tuneRes){ $script:tuneRes = @($kv.tuneRes -split '\|' | ? { $_ -match '^(\d+):(-?\d+)$' } | % { ,@([int]$Matches[1], [int]$Matches[2]) }) }
      if($kv.minReset){ $script:LevelMinReset = [int]$kv.minReset }
      # Mapa aprendido: so vale se o CONFIG deixou vazio (nome fixo no CONFIG sempre manda) E se foi aprendido
      # pro comando de warp ATUAL - trocou o $WarpCmd, o nome antigo nao serve e ele aprende de novo.
      if($kv.warpMap -and -not $WarpMap -and $kv.warpCmd -eq $WarpCmd){ $script:WarpMap = $kv.warpMap; Log "mapa do spot ($WarpCmd) retomado do estado.txt: '$WarpMap'" }
      # Piso de /f /v /e: nao guarda o VALOR, guarda o veredito - assim mexer no $StatMinTeste do CONFIG vale na hora
      # e desligar o $StatMinAprende volta pro piso fixo sem precisar editar o estado.txt.
      if($kv.statCarry){ foreach($par in ($kv.statCarry -split '\|')){ if($par -match '^(For|Agi|Vit|Ene):(\d+)$'){ $script:stCarry[$Matches[1]] = [int]$Matches[2] } } }
      if($StatMinAprende -and $kv.statMinOk){
        $script:statMinOk = [int]$kv.statMinOk
        if($script:statMinOk -eq 1){ $script:StatMinOutros = $StatMinTeste; Log "piso de /f /v /e: o servidor ja tinha aceitado abaixo de 1000, usando $StatMinTeste" }
      }
    }
    Log "estado retomado: fase $($script:phase), warmup $($script:warmupCount)/$WarmupResets, $($script:resets) resets e $($script:ptsSent) pontos acumulados neste MR"
  } catch { Log "estado.txt ilegivel, comecando do zero: $_" }
}
function Same-Map($a,$b){ $a -and $b -and $a.Substring(0,[Math]::Min(4,$a.Length)) -eq $b.Substring(0,[Math]::Min(4,$b.Length)) }   # mesmo mapa pelos 4 primeiros caracteres (tolera ruido do OCR nas coords/fim)
function Close-Popup {   # ESC fecha popup do jogo (ex "precisa estar fora da cidade" apos /darmr) - mas com NADA
  # aberto o ESC ABRE o menu principal (Shop / Inventario / Personagem / ... / Sair), e esse painel tapa o
  # MINIMAPA. Dois ESC as cegas eram um a mais sempre que o primeiro fechava alguma coisa: em 04/09 o mix
  # terminou com a lista aberta, o 1o ESC fechou a lista, o 2o abriu o menu, e o bot passou 4+ min cego em
  # "NAO CONSEGUI LER o nome do mapa" reenviando /k37 pra um minimapa tapado. Entao aperta e CONFERE.
  # Os dois ESC de sempre ficam: fecham popup empilhado no MEIO da tela, que o sensor abaixo nao enxerga.
  Press-Vk 0x1B; Start-Sleep -Milliseconds 300; Press-Vk 0x1B
  # Sensor: o proprio rotulo do minimapa. Menu do jogo aberto = rotulo tapado = Read-Map vazio -> mais um ESC fecha.
  Start-Sleep -Milliseconds 450
  for($i = 0; $i -lt 2 -and -not (Read-Map $null); $i++){ Press-Vk 0x1B; Start-Sleep -Milliseconds 450 }
  if(-not (Read-Map $null)){ Log "ESC: minimapa continua ilegivel (menu do jogo aberto? minimapa recolhido?)" }
}
function Is-FarmMap($m){ $m -and ($m -notmatch $CityWords) }   # nao e cidade conhecida
function Spot-Map { if($script:phase -eq 'warmup'){ $WarmupMap } else { $WarpMap } }   # nome esperado do spot da fase atual
function In-Farm($img){ Same-Map (Read-Map $img) (Spot-Map) }   # $true so se esta no spot CORRETO da fase (nao qualquer mapa; ex AIDA nao conta)
# ---------- LEVEL sem coordenada cravada ----------
# O numero do level na HUD e um numero SOLTO: nao tem rotulo do lado pra ancorar, e nem posicao comparavel entre
# o cliente desktop e a aba do navegador (medido: 0.56 da largura no desktop, 0.62 na web - fracao tambem nao
# transfere). Entao ele se AUTO-CALIBRA: o painel de status mostra "Level: 400" com rotulo, e isso e verdade
# absoluta. Sabendo o numero certo, o bot procura ele na tela inteira, descarta a ocorrencia que esta colada no
# rotulo (essa e a do painel) e guarda onde estava a outra - a da HUD. Dai em diante le so daquele recorte,
# barato igual antes. Se o recorte parar de dar numero plausivel, a caixa e jogada fora e ele recalibra.
$script:lvlBox = $null
$script:lvlBoxMiss = 0   # falhas SEGUIDAS da caixa calibrada. So descarta ao chegar em $LevelBoxMiss - uma falha e ruido de OCR
function Get-Level-Painel($words){   # level pelo ROTULO do painel. 'Levei:' e como o OCR le "Level:" nos 3 fixtures
  $lab = $words | ? { $_.Text -match '(?i)^(level|levei|lvl|n.vel)' } | select -First 1; if(-not $lab){ return $null }
  $yc = $lab.BoundingRect.Y + $lab.BoundingRect.Height/2
  $n = $words | ? { $_.Text -match '^\d{1,4}$' -and $_.BoundingRect.X -gt $lab.BoundingRect.X -and
                    [Math]::Abs(($_.BoundingRect.Y + $_.BoundingRect.Height/2) - $yc) -lt ($lab.BoundingRect.Height + 6) } |
       sort { $_.BoundingRect.X } | select -First 1
  if($n){ [int]$n.Text } else { $null }
}
$LevelFaixaBase = 0.18   # fracao da ALTURA, de baixo pra cima, onde a HUD mostra o level. Nao e coordenada
                         # calibrada: e onde a barra inferior fica em qualquer layout (desktop 8% da base, web 6%).
                         # 18% da folga pros dois sem alcancar o chat nem o mundo.
function Calibrar-LevelBox($img, [int]$lvlReal){   # acha o mesmo numero na HUD e guarda o recorte
  # NAO da pra procurar na tela toda: medido, o OCR do Windows NAO enxerga o numero solto da HUD na resolucao
  # nativa - mesma limitacao que ja obrigava o Ocr-Status a ampliar o painel 2x. Entao recorta a FAIXA INFERIOR
  # (fracao da altura, nao pixel) e amplia. E um crop so, barato, e serve nos dois layouts.
  if($lvlReal -le 0){ return $false }
  $fy = [int]($img.Height * (1 - $LevelFaixaBase)); $fh = $img.Height - $fy
  if($fh -le 0){ return $false }
  try {
    $c = Crop-Bitmap $img 0 $fy $img.Width $fh 3
    $ws = @((Ocr-Bitmap $c).Lines | % { $_.Words }); $esc = $c.Width / [double]$img.Width; $c.Dispose()
    foreach($w in ($ws | ? { $_.Text -match "^$lvlReal$" })){
      # as coordenadas voltam na escala do recorte AMPLIADO: desfaz a ampliacao e soma o deslocamento da faixa
      $r = $w.BoundingRect
      $x = [int]($r.X / $esc); $y = [int]($r.Y / $esc) + $fy
      $ww = [int]($r.Width / $esc); $hh = [int]($r.Height / $esc)
      $script:lvlBox = @{ X = [Math]::Max(0, $x - 12); Y = [Math]::Max(0, $y - 8); W = $ww + 34; H = $hh + 16 }
      $script:lvlBoxMiss = 0   # caixa nova comeca com a ficha limpa, senao ela ja nasceria a uma falha do descarte
      Log "level: caixa calibrada em ($($script:lvlBox.X),$($script:lvlBox.Y)) pelo painel (level $lvlReal)"
      return $true
    }
  } catch {}
  $false
}
function Read-Level($img){
  $own = -not $img; if($own){ $img = Capture-Game }; if(-not $img){ return $null }
  $out = $null
  try {
    if($script:lvlBox){
      $b = $script:lvlBox
      if($b.X -ge 0 -and $b.Y -ge 0 -and ($b.X + $b.W) -le $img.Width -and ($b.Y + $b.H) -le $img.Height){
        $reads = @()
        foreach($v in $LevelOcrVariants){
          $c = Crop-Bitmap $img $b.X $b.Y $b.W $b.H $v.S $v.Pad; if($v.Inv){ [Img]::Invert($c) }
          $txt = (Ocr-Bitmap $c).Text; $c.Dispose()
          if($txt -match '\d+'){ $reads += [int]$Matches[0] }
        }
        # so aceita numero PLAUSIVEL: o recorte pode ter pegado dano, vida ou coordenada se a janela mudou
        $reads = @($reads | ? { $_ -ge 1 -and $_ -le $LevelMaximo })
        if($reads.Count){ $out = [int]($reads | Group-Object | Sort-Object Count -Descending | Select-Object -First 1).Name }
      }
      if($null -eq $out){
        # UMA leitura falha NAO condena a caixa. O OCR falha de vez em quando sozinho - numero de dano por cima,
        # efeito de skill, frame no meio do desenho -, e jogar a caixa fora na primeira falha criou um churn:
        # medido em 15/09, 53 perdas em 1003 linhas de log, com a caixa VIVENDO 4s de mediana e sendo
        # recalibrada sempre pro MESMO lugar (1121,932 em 45 das 57 vezes). Ou seja: a caixa estava certa e o
        # bot a descartava por ruido, pagando uma leitura de status forcada (~3s, abre e fecha o painel) a cada
        # vez. E a mesma licao do $StallReads do Check-Progress: leituras seguidas sao o sinal forte, uma nao e.
        # Custo de errar pro outro lado: se a caixa estiver MESMO invalida (a janela mudou), ficam $LevelBoxMiss
        # leituras ate perceber - ~4s no poll rapido. Barato perto de 53 recalibracoes.
        $script:lvlBoxMiss++
        if($script:lvlBoxMiss -ge $LevelBoxMiss){
          $script:lvlBox = $null; $script:statDue = Get-Date; $script:forcaStat = $true
          Log "level: a caixa calibrada falhou $($script:lvlBoxMiss)x seguidas - recalibrando agora"
        }
      }
      else { $script:lvlBoxMiss = 0 }   # leu: a caixa esta viva, esquece as falhas anteriores
    }
  } catch { $out = $null; $script:lvlBox = $null }
  if($own){ $img.Dispose() }
  $out
}
# ---------- BOTAO PLAY/PAUSE sem coordenada cravada ----------
# Nao e texto: e um icone (triangulo VERDE = parado, barras VERMELHAS = rodando). OCR nao serve. Mas da pra
# parar de cravar o ponto: o botao e a unica coisa fortemente verde OU vermelha no CANTO SUPERIOR ESQUERDO,
# e e pequeno. Entao varre esse canto (em FRACAO da area cliente) procurando a maior concentracao, guarda onde
# achou e reusa - mesma ideia da caixa do level.
$PlayCanto     = @{ X = 0.20; Y = 0.35 }   # fracao da area cliente varrida no canto sup. esquerdo. Generoso de
                                           # proposito: na web a barra do navegador empurra o canvas pra baixo
                                           # (o botao sai de y=33 no desktop pra ~116 na aba do Chrome).
$PlayCell      = 12                        # lado do quadradinho agregador, em px
$script:playBox = $null
$script:playBoxMiss = 0   # leituras SEGUIDAS com a caixa do play ilegivel; so descarta ao chegar em $LevelBoxMiss
$PlayAcimaDoMapa = 80   # px que o topo do canvas fica ACIMA do rotulo do minimapa
function Topo-Do-Canvas($img){   # primeira linha que e JOGO, nao enfeite do navegador
  # No cliente desktop a area cliente E o jogo: 0. Na aba do navegador, abas + barra de endereco ocupam o topo
  # (~85px) e a busca do play sem isso acha FAVICON colorido de aba.
  # Separar por brilho NAO funciona: a barra de abas do Chrome no tema escuro e tao escura quanto o jogo.
  # O que funciona e ancorar no rotulo do minimapa, que o Read-Map ja localiza: ele fica ~68px abaixo do topo do
  # canvas no desktop e ~85px na web. Descontar 80 poe o corte logo acima do rotulo nos dois casos.
  # Sem rotulo conhecido ainda, devolve 0 - que e o certo pro desktop e so deixa a busca mais larga na web.
  if($script:mapaBox){ return [Math]::Max(0, [int]$script:mapaBox.Y - $PlayAcimaDoMapa) }
  0
}
function Achar-Botao-Play($img){   # devolve @{X;Y;Estado} do centro do botao, ou $null
  $y0 = Topo-Do-Canvas $img
  $w = [int]($img.Width * $PlayCanto.X); $h = $y0 + [int](($img.Height - $y0) * $PlayCanto.Y)
  if($w -le $PlayCell -or ($h - $y0) -le $PlayCell){ return $null }
  $melhor = $null
  for($cy = $y0; $cy -lt ($h - $PlayCell); $cy += [int]($PlayCell/2)){
    for($cx = 0; $cx -lt ($w - $PlayCell); $cx += [int]($PlayCell/2)){
      $r = 0; $g = 0
      for($x = $cx; $x -lt ($cx + $PlayCell); $x += 2){ for($y = $cy; $y -lt ($cy + $PlayCell); $y += 2){
        $p = $img.GetPixel($x,$y)
        if($p.R -gt 120 -and $p.G -lt 100 -and $p.B -lt 100){ $r++ } elseif($p.G -gt 140 -and $p.R -lt 140 -and $p.B -lt 140){ $g++ }
      } }
      # Exigente de proposito: o quadradinho tem 36 amostras (12x12 passo 2) e o botao e SOLIDO, entao enche
      # quase tudo. Limiar baixo pegava barra de vida e favicon. Clicar no lugar errado e pior que nao achar -
      # 'unknown' o Start-Helper ja trata (espera sem clicar).
      $tot = [Math]::Max($r,$g)
      # Entre os que passam do limiar, vence o MAIS ALTO (e, empatando, o mais a esquerda) - nao o mais forte.
      # Escolher pelo tamanho do borrao fazia o orbe de vida e outros blocos coloridos da HUD ganharem do botao,
      # que e pequeno: das 20 buscas do log, 11 devolveram coordenada errada - (72,96), (348,60), (252,204)... -
      # e como o resultado vai pro cache ($script:playBox), a posicao errada ficava valendo. O estado lido dali e
      # chute, e 'running' falso e o pior deles: o bot nao clica no play e o char passa o ciclo sem farmar.
      # O botao mora no ALTO do canvas; essa e a informacao que a regiao ja tentava dizer e que o "maior" anulava.
      if($tot -ge 20 -and (-not $melhor -or $cy -lt $melhor.Cy -or ($cy -eq $melhor.Cy -and $cx -lt $melhor.Cx))){
        $melhor = @{ X = $cx + [int]($PlayCell/2); Y = $cy + [int]($PlayCell/2); Cx = $cx; Cy = $cy; Tot = $tot
                     Estado = $(if($r -ge $g){ 'running' } else { 'stopped' }) }
      }
    }
  }
  $melhor
}
function Get-HelperState($img){   # pausa = barras vermelhas; play = triangulo verde
  $own = -not $img; if($own){ $img = Capture-Game }; if(-not $img){ return 'unknown' }
  $out = 'unknown'
  try {
    # com a caixa ja conhecida, conta so ali - barato, igual ao que era com o $PlayBtn cravado
    if($script:playBox){
      $b = $script:playBox; $red = 0; $green = 0
      for($x = $b.X-11; $x -le $b.X+11; $x++){ for($y = $b.Y-13; $y -le $b.Y+13; $y++){
        if($x -lt 0 -or $y -lt 0 -or $x -ge $img.Width -or $y -ge $img.Height){ continue }
        $p = $img.GetPixel($x,$y)
        if($p.R -gt 120 -and $p.G -lt 100 -and $p.B -lt 100){ $red++ } elseif($p.G -gt 140 -and $p.R -lt 140 -and $p.B -lt 140){ $green++ }
      } }
      if($red -gt 10){ $out = 'running' } elseif($green -gt 10){ $out = 'stopped' }
      # UMA leitura 'unknown' nao condena a caixa - mesma licao do $LevelBoxMiss e do $StallReads. O botao fica
      # ilegivel de passagem (efeito por cima, frame no meio do desenho), e descartar na primeira fazia a busca
      # rodar de novo e travar numa posicao ERRADA: o log de 15/09 mostra a caixa pulando entre (78,30), que e a
      # certa, e (48,42), repetidamente. Posicao errada em cache vira estado chutado, e o pior deles e um
      # 'running' falso - o bot nao religa o helper e o char passa o ciclo sem farmar.
      if($out -eq 'unknown'){
        $script:playBoxMiss++
        if($script:playBoxMiss -ge $LevelBoxMiss){ $script:playBox = $null; $script:playBoxMiss = 0 }   # sumiu de vez: procura de novo
      }
      else { $script:playBoxMiss = 0 }
    }
    if($out -eq 'unknown'){
      $achou = Achar-Botao-Play $img
      if($achou){
        $script:playBox = @{ X = $achou.X; Y = $achou.Y }; $out = $achou.Estado
        Log "play: botao localizado em ($($achou.X),$($achou.Y)) - estado '$out'"
      }
    }
  } catch { $out = 'unknown' }
  if($own){ $img.Dispose() }
  $out
}
function Play-XY {   # onde clicar pra ligar/desligar o helper. Sem caixa conhecida ainda, procura uma vez.
  if(-not $script:playBox){ $img = Capture-Game; if($img){ $null = Get-HelperState $img; $img.Dispose() } }
  if($script:playBox){ $script:playBox } else { $null }
}

# ---------- captcha ----------
function Find-Captcha($img){   # centro do texto "Selecione a mesma imagem abaixo:" ou $null
  # A ancora e a FRASE, nao a palavra "Selecione" sozinha. Casar so com ela pegava o dialogo do MIX, que diz
  # "Selecione o metodo de combinacao": o bot entao interrompia a mixagem pra resolver um captcha que nao
  # existia, comparava pedacos quaisquer da tela (dai as razoes de 0.99 - empate entre duas coisas que nao sao
  # opcao de captcha nenhuma), nao tinha certeza e CHAMAVA VOCE. Medido em 15/09: 3 dos 4 "captchas" do log
  # eram isso, e o print salvo mostrava o inventario e o painel de combinacao abertos, sem captcha na tela.
  # O .{0,20} entre as palavras e folga pro OCR, que come letra e junta palavra.
  $line = (Ocr-Bitmap $img).Lines | ? { $_.Text -match $CapAncoraWords } | select -First 1
  if(-not $line){ return $null }
  $r = $line.Words | % { $_.BoundingRect }
  $x1 = ($r | % { $_.X } | measure -Minimum).Minimum; $x2 = ($r | % { $_.X + $_.Width } | measure -Maximum).Maximum
  $y1 = ($r | % { $_.Y } | measure -Minimum).Minimum; $y2 = ($r | % { $_.Y + $_.Height } | measure -Maximum).Maximum
  @{ X = [int](($x1+$x2)/2); Y = [int](($y1+$y2)/2) }
}
function Score-Captcha($img,$a){   # cada opcao contra a imagem de referencia (SAD: quanto MENOR, mais parecida)
  $ref = Crop-Bitmap $img ($a.X-40) ($a.Y+$CapRefDy-40) 80 80
  $cands = foreach($dy in $CapRowDy){ foreach($dx in $CapColDx){
    $o = Crop-Bitmap $img ($a.X+$dx-48) ($a.Y+$dy-48) 96 96; $s = [Img]::MinSad($ref,$o); $o.Dispose()
    [pscustomobject]@{ X = $a.X+$dx; Y = $a.Y+$dy; S = $s }
  } }
  $ref.Dispose(); $cands | sort S
}
function Solve-Captcha($img,$a,[switch]$NoClick){   # $true se clicou (ou, com -NoClick, se teria certeza)
  $c = Score-Captcha $img $a
  Log ("captcha: melhor ({0},{1}) score={2} | segundo score={3}" -f $c[0].X,$c[0].Y,$c[0].S,$c[1].S)
  # Ambiguo? Antes de desistir, tira OUTRA foto com o PONTEIRO FORA DO CAMINHO. O cursor aparece na captura e a
  # seta cobre um pedaco do quadradinho embaixo dele - o mesmo problema que o Tirar-Cursor ja resolvia no mix.
  # Em 04/09 o ponteiro parou em cima da opcao CERTA e o bot ficou preso das 06:09 as 07:00+, reiniciando sozinho
  # no meio: score 320229 contra 327168 no segundo (0.98). Um acerto de verdade fica em 23-68 mil, 0.07-0.18 do
  # segundo - o $CapConfidence estava certo em recusar, quem estava errado era a foto.
  # -NoClick nao entra aqui: e o caminho do -TestImage/-Preflight, que roda sobre um PNG salvo e pode nem ter jogo aberto.
  if(-not $NoClick -and $c[0].S -gt $CapConfidence * $c[1].S){
    $volta = $null
    if($NoFocusRead){ $pc = New-Object W+POINT; if([W]::GetCursorPos([ref]$pc)){ $volta = $pc } }   # o ponteiro e SEU: devolve onde estava
    Tirar-Cursor
    $img2 = Capture-Raw
    try {
      $a2 = Find-Captcha $img2
      if($a2){
        $c2 = Score-Captcha $img2 $a2
        Log ("captcha: 2a foto sem o ponteiro: melhor ({0},{1}) score={2} | segundo score={3}" -f $c2[0].X,$c2[0].Y,$c2[0].S,$c2[1].S)
        if($c2[0].S -le $CapConfidence * $c2[1].S){ $c = $c2 }
      }
    } finally { $img2.Dispose(); if($volta){ [W]::SetCursorPos($volta.X,$volta.Y) | Out-Null } }
  }
  if($c[0].S -gt $CapConfidence * $c[1].S){ Log "captcha: ambiguo, nao vou chutar"; return $(if($NoClick){ $false } else { 'ambiguo' }) }
  if($NoClick){ return $true }
  $prev = Focus-Game; if(-not $script:gameFg){ Restore-Focus $prev; return 'falhou' }
  $sel = $false
  for($k = 0; $k -lt 3 -and -not $sel; $k++){   # clica na opcao e confere que ficou com a borda vermelha antes de confirmar
    $null = Click-Client $c[0].X $c[0].Y -KeepFocus; Start-Sleep -Milliseconds 700
    $b = Capture-Raw; $sel = Option-Selected $b $c[0].X $c[0].Y; $b.Dispose()
  }
  if(-not $sel){ Log "captcha: opcao nao ficou selecionada apos 3 cliques"; Restore-Focus $prev; return 'falhou' }
  $null = Click-Client $a.X ($a.Y+$CapConfirmDy) -KeepFocus; Restore-Focus $prev; 'enviado'
}
function Option-Selected($img,[int]$x,[int]$y){   # borda vermelha (selecao) no topo da opcao
  $best = 0
  foreach($dy in -5..5){ $red = 0; foreach($dx in -50..50){ $p = $img.GetPixel($x+$dx, $y-$CapSelHalf+$dy); if($p.R -gt 150 -and $p.G -lt 100 -and $p.B -lt 100){ $red++ } }; if($red -gt $best){ $best = $red } }
  $best -gt 60
}
function Podar-Shots {   # cada print tem 2-4MB e a pasta esta DENTRO do OneDrive: sem poda virou 4.9GB / 2640 arquivos sincronizando pra nuvem
  try {
    $velhos = @(Get-ChildItem $CaptchaShotDir -Filter 'captcha_*.png' -EA SilentlyContinue | sort LastWriteTime -Descending | select -Skip $CapKeepShots)
    if($velhos.Count){ $mb = [int](($velhos | measure Length -Sum).Sum / 1MB); $velhos | Remove-Item -Force -EA SilentlyContinue; Log "podei $($velhos.Count) prints de captcha antigos (${mb}MB)" }
  } catch {}
}
function Save-CaptchaShot($img){
  New-Item -ItemType Directory -Force $CaptchaShotDir | Out-Null
  Podar-Shots
  $f = Join-Path $CaptchaShotDir ("captcha_{0}.png" -f (Get-Date -Format 'yyyyMMdd_HHmmss')); $img.Save($f); Log "print salvo: $f"
}
$script:capTries = 0; $script:capNotified = $null
function Handle-Captcha($img){   # $true se captcha esta na tela (tentou resolver ou avisou humano)
  if(-not $img){ return $false }
  $a = Find-Captcha $img
  if(-not $a){ $script:capTries = 0; $script:capNotified = $null; return $false }
  if($script:capTries -ge $CapMaxTries){   # errou N vezes: nao arrisca mais uma
    if($CapKillGame){   # regra antiga: fecha o jogo e para
      # $CapKillGame e $false por padrao; este caminho e a regra ANTIGA. Na versao web ele mataria o navegador
      # inteiro (todas as suas abas), entao aqui ele so para o bot e deixa o jogo aberto.
      Log "captcha: errei $CapMaxTries vezes -> $(if($GameTitle){ 'parando o bot (nao fecho o navegador)' } else { "fechando o jogo ($GameProc.exe) e parando" })"
      Notify "MudinhoX: CAPTCHA" "Errei o captcha $CapMaxTries vezes. Parei o bot."
      if(-not $GameTitle){ Get-Process $GameProc -ErrorAction SilentlyContinue | Stop-Process -Force }
      if($script:ui){ $script:ui.Dispose() }; exit
    }
    # padrao agora: PAUSA e espera voce. Matar o cliente perdia a sessao inteira, e parte dos erros vinha dos cliques
    # indo pra outra janela (bug de foco corrigido em 2026-08-31), nao do solver.
    if(-not $script:paused){
      Log "captcha: errei $CapMaxTries vezes -> PAUSANDO e esperando voce (nao vou arriscar a proxima)"
      Notify "MudinhoX: CAPTCHA" "Errei $CapMaxTries vezes. Bot PAUSADO - resolve o captcha e clique RETOMAR."
      $script:paused = $true
      if($script:ui -and -not $script:ui.IsDisposed){ $script:btnPause.Text = 'RETOMAR'; $script:btnPause.BackColor = 'ForestGreen' }
      $script:capTries = 0   # ao retomar, comeca a contagem de novo
    }
    return $true
  }
  Tag-Ciclo 'captcha'; Save-CaptchaShot $img
  $r = Solve-Captcha $img $a
  if($r -eq 'enviado'){ $script:capTries++; Log "captcha: tentativa $($script:capTries) enviada"; Wait 5; return $true }
  if($r -ne 'enviado' -and (-not $script:capNotified -or ((Get-Date) - $script:capNotified).TotalSeconds -ge $RenotifySec)){
    $motivo = if($r -eq 'ambiguo'){ "Nao tenho certeza da imagem." } else { "Cliquei mas a opcao nao ficou selecionada (o jogo pode ter perdido o foco)." }   # 'falhou' avisava NADA: o bot ficava preso no captcha em silencio
    Notify "MudinhoX: CAPTCHA" "$motivo Resolve ai que o bot continua sozinho."; $script:capNotified = Get-Date
  }
  $true
}

# ---------- notificacao ----------
function Notify-Once([string]$chave,[string]$title,[string]$msg){
  # Toast repetido treina o usuario a ignorar toast. No log de 14:49-14:55 o mesmo alerta saiu 23 vezes em 5,5
  # minutos - 23 toasts com som de alarme pro MESMO problema. Aqui cada assunto ($chave) so re-avisa a cada
  # $RenotifySec; o Log continua saindo toda vez, que e o que serve pra diagnostico depois.
  if(-not $script:avisos){ $script:avisos = @{} }
  $ultimo = $script:avisos[$chave]
  if($ultimo -and ((Get-Date) - $ultimo).TotalSeconds -lt $RenotifySec){ Log "AVISO ($chave, ja notificado): $msg"; return }
  $script:avisos[$chave] = Get-Date
  Notify $title $msg
}
function Notify([string]$title,[string]$msg){
  Log "NOTIFY: $title - $msg"
  try {
    $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
    $xml.LoadXml("<toast scenario='reminder'><visual><binding template='ToastGeneric'><text>$title</text><text>$msg</text></binding></visual><audio src='ms-winsoundevent:Notification.Looping.Alarm'/></toast>")
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe').Show((New-Object Windows.UI.Notifications.ToastNotification($xml)))
  } catch { Log "toast falhou: $_" }
  1..3 | % { [console]::Beep(1000,300); Start-Sleep -Milliseconds 150 }
}

# ---------- modos de teste ----------
if($TestImage){
  $img = [System.Drawing.Bitmap]::FromFile((Resolve-Path $TestImage))
  $a = Find-Captcha $img; if(-not $a){ Log "captcha NAO encontrado na imagem"; exit }
  Log "ancora em ($($a.X),$($a.Y))"; $ok = Solve-Captcha $img $a -NoClick; Log "resolveria: $ok"; exit
}
if($Check){
  $img = Capture-Game; if(-not $img){ Log "jogo nao ficou na frente, nada lido"; exit }; $a = Find-Captcha $img
  # "jogo na frente" mostrava o $gameWasFg, que o $NoFocusRead forca pra True - dizia sempre "True" mesmo com o
  # jogo noutro monitor e sem foco nenhum. Pergunta ao Windows na hora.
  $naFrente = [W]::GetForegroundWindow() -eq (Get-Game)
  Log "level lido: $(Read-Level $img) | helper: $(Get-HelperState $img) | captcha: $(if($a){"sim ($($a.X),$($a.Y))"}else{'nao'}) | jogo na frente: $naFrente$(if($NoFocusRead){' (NoFocusRead ligado: leitura nao precisa de foco)'}) | chat aberto: $(Chat-Open $img)"
  if($a){ $null = Solve-Captcha $img $a -NoClick }
  if((Game-IsAdmin) -and -not (Is-Admin)){ Log "AVISO: o jogo roda como administrador e eu nao -> Windows ignora meu teclado/mouse. O loop principal se eleva sozinho (aceite o UAC)." }
  exit
}

# ---------- admin ----------
# O jogo roda como administrador: o Windows descarta teclado/mouse sintetico vindo de processo comum (UIPI). Entao roda elevado.
if(-not (Is-Admin) -and -not ($TestInv -or $TestMix -or $TestNpc -or $TestVisao -or $Preflight -or $TestStatus -ne "")){   # -TestInv/-TestMix so LEEM a tela: nao precisam de admin (e elevar abriria janela oculta, sem saida no terminal)
  try { Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`"" }
  catch {
    # NUNCA usar MessageBox aqui: o processo roda com -WindowStyle Hidden, o dialogo fica invisivel e o processo
    # trava nele PARA SEMPRE - parecendo vivo pra quem so olha a lista de processos. Foi assim que o bot ficou
    # 6 horas parado em 01/09 (03:27 -> 09:09, zero linha de log). Loga, avisa por toast (nao bloqueia) e SAI.
    Log "UAC recusado ou falhou: nao consigo elevar. O bot precisa de admin porque o jogo roda elevado."
    Notify "MudinhoX RPA" "UAC recusado: o bot nao subiu. Instale o watchdog (instalar-watchdog.cmd) pra ele subir sem UAC."
  }
  exit
}

# ---------- loop principal ----------
$script:statDue = (Get-Date).AddSeconds($StatCmds[0].AfterSec)
$script:ptsLeft = 0
function Points-Needed($st){ (@($StatOrder | % { $StatMaxValue - [int]$st[$_] }) | measure -Sum).Sum }   # quantos pontos ainda faltam pra fechar os 4 atributos
function Stat-Stage($st){   # etapa atual = primeira meta (10k/20k/30k/cap) que algum atributo ainda nao alcancou
  foreach($s in $StatStages){ if($StatOrder | ? { [int]$st[$_] -lt $s }){ return $s } }
  $StatMaxValue
}
function Perto-Do-Max($st){ @('For','Agi','Vit','Ene' | ? { [int]$st[$_] -lt $StatPertoDoMax }).Count -eq 0 }   # os 4 na reta final
function Plan-Stats($st,[int]$p){   # TODOS os comandos que os $p pontos dao conta, ja atravessando as etapas (simula o efeito de cada comando).
  $sim = @{}; foreach($k in $StatOrder){ $sim[$k] = [int]$st[$k] }   # assim uma leitura de status rende ate 16 comandos, em vez de 1 leitura por etapa
  $perto = Perto-Do-Max $st   # na reta final o piso cai: o objetivo la e FECHAR o cap pro /darmr
  $out = @()
  for($etapa = 0; $etapa -le $StatStages.Count; $etapa++){
    $stage = Stat-Stage $sim; $mandou = $false
    foreach($k in $StatOrder){   # enche um atributo ate a meta da etapa antes de passar pro proximo (energia, agilidade, forca, vitalidade)
      if($p -le 0){ break }   # nao corta aqui pelo minimo de 1000: um atributo pode precisar de menos pra FECHAR o cap
      $faltaEtapa = $stage - $sim[$k]
      if($faltaEtapa -le 0){ continue }
      $faltaCap = $StatMaxValue - $sim[$k]
      $sc = $StatCmds | ? { $_.Key -eq $k } | select -First 1
      # /a tem perigo REAL documentado (abaixo de 100 teleporta pra AIDA). Pros outros o piso era so precaucao.
      # Na reta final ($StatPertoDoMax) o piso cai pra $StatMinPerto - inclusive no /a, que fica bem acima dos 100.
      # $StatMinPerto existe pra BAIXAR o piso na reta final (de 1000 pra 500). Depois que o servidor aceitou
      # abaixo do piso, o $StatMinOutros virou 100 - e ai pegar o $StatMinPerto direto SUBIA o piso de 100 pra
      # 500 justamente no trecho onde fechar o cap e tudo que importa. Foi o travamento de 04/09: F=30000
      # V=30000 (os 4 ja contam como "reta final"), 418 pontos em maos, 418 < 500, nenhum comando saiu. Ficaram
      # 31 min parados, o /darmr sem sair, e o bot se reiniciou sozinho por "sem progresso". Na reta final o
      # piso e o MENOR dos dois - nunca um piso maior que o do trecho normal.
      $minCmd = if($sc.Cmd -eq '/a'){ if($perto){ [Math]::Max($StatMinPerto, $StatMinAgi) } else { $StatMinCmd } }
                else { if($perto){ [Math]::Min($StatMinPerto, $StatMinOutros) } else { $StatMinOutros } }
      $amt = [Math]::Min($p, $faltaEtapa)
      # se o que falta pra fechar a etapa e menor que o minimo por comando, passa um pouco da meta (limitado pelo cap):
      # senao a etapa inteira TRAVA por causa de um atributo faltando <1000, e os pontos ficam empilhando pra sempre
      if($amt -lt $minCmd){ $amt = [Math]::Min($p, [Math]::Min($minCmd, $faltaCap)) }
      # NUNCA deixar um vao pequeno demais pra ser fechado depois. Foi o travamento de 14:54: A=32729, faltando 38,
      # e nenhum /a legal fecha 38 (piso 1000, e o proprio jogo recusa mandar mais do que cabe). Os outros 3 ja
      # estavam no cap, entao nao havia onde gastar: 33 mil pontos parados e o /darmr nunca saia.
      # /f /v /e podem fechar o vao com valor exato; o /a nao pode ir abaixo de 100, entao pra ele a saida e
      # NAO criar o vao - manda menos agora e deixa uma sobra que o proximo comando consegue mandar.
      $sobra = $faltaCap - $amt
      if($sobra -gt 0 -and $sobra -lt $minCmd){
        if($p -ge $faltaCap){ $amt = $faltaCap }             # da pra fechar agora: fecha
        elseif($sc.Cmd -eq '/a'){ $amt = $faltaCap - $minCmd }   # nao da: deixa um vao que o /a ainda consegue mandar depois
      }
      $piso = if($sc.Cmd -ne '/a' -and $amt -eq $faltaCap){ 1 } else { $minCmd }   # so manda abaixo do piso quando e pra FECHAR o cap (e nunca no /a)
      if($amt -lt $piso){ continue }
      $out += ("{0} {1}" -f $sc.Cmd, $amt); $p -= $amt; $sim[$k] += $amt; $mandou = $true
    }
    if(-not $mandou -or $p -le 0){ break }   # etapa nao rendeu nada (ou acabaram os pontos): para
  }
  ,$out
}
function Distribute-Points {   # le os 4 atributos + pontos e distribui em etapas, na ordem $StatOrder. VALIDA os valores: os 4 no cap -> /darmr.
  $prevP = -1; $stuck = 0
  for($guard = 0; $guard -lt 8 -and -not $script:stop; $guard++){   # cada volta = 1 leitura de status + o plano inteiro; 8 volta e sobra
    $st = Read-Status
    if(-not $st){ Tag-Ciclo 'status'; Log "stats: nao consegui ler o status"; return }
    # Painel congelado: os 4 atributos E os pontos identicos a leitura anterior, mas o LEVEL andou no meio.
    # Se o char esta upando, ponto TEM que entrar - leitura igual significa frame velho (o C nao reabriu, ou o OCR
    # pegou o painel que ficou na tela). Em 01/09 foram 12 min com "752 pontos" parados e o unico que pegou foi o
    # $SemProgressoMin, 12 min depois. So confere na 1a leitura da chamada: as de dentro do loop tem o mesmo level.
    if($guard -eq 0){
      $fp = "$($st.For)/$($st.Agi)/$($st.Vit)/$($st.Ene)/$($st.Pts)"
      if($fp -eq $script:stFp -and $script:lvlPrev -ne $script:stFpLvl){ $script:stFpN++ } else { $script:stFpN = 0 }
      $script:stFp = $fp; $script:stFpLvl = $script:lvlPrev
      if($script:stFpN -ge $StatCongeladoN){
        Log "stats: painel congelado ($fp) em $($script:stFpN + 1) leituras seguidas com o level andando - destravando"
        Tag-Ciclo 'congelado'; $script:stFpN = 0; Unstick-Tudo; return
      }
    }
    $script:ptsNeeded = Points-Needed $st
    if($script:ptsNeeded -le 0){ if($script:modo -eq 'joias'){ Log "stats: atributos no maximo, mas o modo JOIAS nao da /darmr"; return }; if($script:phase -eq 'warmup'){ Log "stats: atributos no maximo durante o warmup, seguindo sem /darmr"; return }; Log "stats: F=$($st.For) A=$($st.Agi) V=$($st.Vit) E=$($st.Ene) -> TODOS no maximo, /darmr"; Master-Reset; return }
    $script:pertoDoMax = Perto-Do-Max $st   # liga a leitura rapida: perto do cap sao os ultimos pontos que destravam o /darmr
    $p = [int]$st['Pts']; $script:ptsLeft = $p
    # O jogo SO mostra a linha "Pontos" quando ha pontos a distribuir (o print do painel confirma: Forca/Agilidade/
    # Vitalidade/Energia aparecem, "Pontos" nao). Entao Pts=-1 quase sempre significa ZERO, nao erro de leitura.
    # Zero ponto tambem e leitura que nao rendeu nada: entra no mesmo recuo (foram 84 destas no log anterior).
    if($p -lt 0){ Log "stats: F=$($st.For) A=$($st.Agi) V=$($st.Vit) E=$($st.Ene) - sem linha de Pontos (0 a distribuir)"; $script:statVazias++; return }
    if($p -lt $StatMinAvail){ $script:statVazias++; return }   # nada relevante a distribuir agora
    if($p -eq $prevP){ $stuck++ } else { $stuck = 0 }; $prevP = $p
    if($stuck -ge 2){ Log "stats: $p pontos nao baixam (faltam $($script:ptsNeeded) pontos pro cap). Parei pra nao repetir a toa."; return }
    $stage = Stat-Stage $st
    Log "stats: $p pontos | etapa $stage | F=$($st.For) A=$($st.Agi) V=$($st.Vit) E=$($st.Ene) | faltam $($script:ptsNeeded) pro cap"
    $plano = Plan-Stats $st $p
    if($plano.Count -eq 0){
      if($p -gt $StatMaxLeftover){
        # Diga O QUE FAZER. Quando o vao e menor que o piso do /a (100, por causa da AIDA) nenhum comando fecha:
        # so o botao "+" do painel resolve. O plano agora evita CRIAR esse vao, mas um char que ja chegou aqui
        # (ou um /a manual) precisa da mao. Antes o aviso era so "nao consigo distribuir".
        $encalhado = @('For','Agi','Vit','Ene' | ? { $StatMaxValue - [int]$st[$_] -gt 0 -and $StatMaxValue - [int]$st[$_] -lt $StatMinAgi })
        Log "stats: ALERTA - $p pontos sobrando (limite $StatMaxLeftover) e nao consigo gastar nenhum. F=$($st.For) A=$($st.Agi) V=$($st.Vit) E=$($st.Ene)"
        if($encalhado.Count){
          $det = ($encalhado | % { "$_ falta $($StatMaxValue - [int]$st[$_])" }) -join ', '
          Log "stats: $det - vao menor que $StatMinAgi, nenhum comando de chat fecha isso. Abra o status (C) e clique no '+' desse atributo."
          Notify-Once 'stat-encalhado' "MudinhoX" "Trava do /darmr: $det. Abra o status (C) e clique no '+' desse atributo - o chat nao fecha vao tao pequeno."
        } else { Notify-Once 'stat-parado' "MudinhoX" "$p pontos parados e nao consigo distribuir. Da uma olhada." }
      }
      else {
        # 2109 das 3551 leituras do log morreram exatamente aqui: os pontos chegam em blocos de ~600-900 e o piso
        # de 1000 recusava todos. Esse piso nunca foi testado contra o servidor - so o /a tem perigo documentado.
        # Em vez de depender de um -TestStatMin manual (que nunca foi rodado), o bot pergunta ao servidor UMA vez,
        # com /f, e grava o veredito. O teste so vale com $StatMinTeste pontos ou mais em maos: mandar /f 16 e
        # concluir "recusa" seria mentira, o servidor pode recusar so abaixo de 100.
        $testou = $false
        if($StatMinAprende -and $script:statMinOk -eq 0 -and $p -ge $StatMinTeste -and ([int]$st.For + $p) -le $StatMaxValue){
          $piso = $StatMinOutros
          Log "stats: perguntando ao servidor UMA vez se aceita abaixo do piso (/f $p, piso $piso). Veredito vai pro estado.txt."
          if(Send-Chat "/f $p"){
            Wait 3
            $d = Read-Status
            if($d -and ([int]$d.For - [int]$st.For) -eq $p){
              $script:StatMinOutros = $StatMinTeste; $script:statMinOk = 1; $testou = $true
              $script:ptsSent += $p; $script:ptsLastGain = Get-Date; $script:semProgresso = 0
              Log "stats: servidor ACEITOU /f $p -> piso de /f /v /e cai de $piso pra $StatMinTeste"
            } elseif($d){
              $script:statMinOk = -1; $testou = $true
              Log "stats: servidor RECUSOU /f $p (Forca $($st.For) -> $($d.For)) -> piso $piso mantido, nao pergunto de novo"
            }
            if($testou){ Save-Estado }
          }
        }
        if($testou){ continue }   # com o veredito na mao, refaz o plano ja com o piso novo
        # Mostrar o piso REAL, e de QUEM. Nao ha um piso so: /f /v /e usam o $StatMinOutros (que o servidor ja
        # deixou cair pra 100), mas o /a tem piso proprio de $StatMinCmd (1000, perigo da AIDA). A mensagem
        # antiga imprimia so o primeiro, entao "988 pontos; minimo 100" parecia absurdo - o que faltava eram
        # 1000 pro /a, unico atributo abaixo da etapa naquela hora. Sem dizer QUEM esta travado nao da pra saber
        # se o bot esta esperando ponto (normal) ou preso num piso que nunca vai ser alcancado.
        $etapa = Stat-Stage $st
        $trava = @()
        foreach($k in $StatOrder){
          if([int]$st[$k] -ge $etapa){ continue }   # ja cumpriu a etapa: nao e ele que esta segurando
          $sc = $StatCmds | ? { $_.Key -eq $k } | select -First 1
          $piso = if($sc.Cmd -eq '/a'){ if($script:pertoDoMax){ [Math]::Max($StatMinPerto, $StatMinAgi) } else { $StatMinCmd } }
                  else { if($script:pertoDoMax){ [Math]::Min($StatMinPerto, $StatMinOutros) } else { $StatMinOutros } }
          $trava += "$($sc.Cmd) precisa de $piso"
        }
        Log "stats: nada a distribuir agora ($p pontos em maos; $(if($trava.Count){ $trava -join ', ' } else { 'nenhum atributo abaixo da etapa' }))"
      }
      $script:statVazias++   # leitura que nao rendeu comando: da proxima vez espera mais (ver Tick-Stats)
      return
    }
    Log "stats: plano ($($plano.Count) comandos): $($plano -join ' | ')"
    $script:statVazias = 0   # rendeu comando: volta a ler no ritmo rapido
    foreach($cmd in $plano){   # acumula pra metrica de pontos/h e marca que houve progresso
      if($script:stop -or -not (Send-Chat $cmd)){ break }
      $qtd = [int](($cmd -split " ")[1])
      $script:ptsSent += $qtd; $script:ptsLastGain = Get-Date; $script:semProgresso = 0
      # Mantem viva a memoria do atributo: e o que permite seguir quando o OCR nao le a linha dele (ver Read-Status).
      $kc = ($StatCmds | ? { $_.Cmd -eq ($cmd -split ' ')[0] } | select -First 1).Key
      if($kc -and $null -ne $script:stCarry[$kc]){ $script:stCarry[$kc] += $qtd }
    }
    # REVERTIDO em 08/09. Aqui havia um atalho que pulava a releitura de status quando a sobra simulada
    # (pontos - soma do plano) ja estava abaixo do piso. Entrou no ar as 02:19 e a partir dessa sessao o painel
    # de status NUNCA MAIS abriu: 1789 leituras boas / 0 falhas na sessao anterior contra 0 boas / 84 falhas na
    # seguinte, e assim em todas depois. O char empilhou pontos contra a MEMORIA ($stCarry) e o MR nao fechava -
    # 284 resets num MR que fecha com ~21. Nao achei o mecanismo por leitura do codigo, e o custo de investigar
    # com o bot quebrado nao compensa o ~1 min por MR que o atalho economizava. Se voltar, volta com um teste
    # que exercite Read-Status de verdade, nao so o Plan-Stats.
    Wait $StatRoundSec
  }
}
# Le o status quando ha MOTIVO pra ler. Pontos so vem de subir de level - com o level parado, abrir a janela
# de novo so custa: rouba o foco, gasta 2-3s e loga "0 a distribuir". No log foram 84 leituras assim.
# O teto de tempo continua existindo porque o level as vezes nao e legivel (OCR) e nao da pra confiar so nele.
$script:statLvlLast = -1; $script:statMax = Get-Date; $script:pertoDoMax = $false; $script:statVazias = 0
$script:forcaStat = $false   # o Read-Level liga isto quando perde a caixa: a proxima leitura de status e obrigatoria
$script:stFp = ''; $script:stFpLvl = $null; $script:stFpN = 0   # assinatura da ultima leitura de status (detector de painel congelado)
$script:statMinOk = 0   # veredito do servidor sobre comando abaixo do piso: 0 = ainda nao perguntei, 1 = aceita, -1 = recusa. Vai pro estado.txt: a pergunta e feita UMA vez na vida
# Memoria dos 4 atributos: ultimo valor LIDO de cada um, somado ao que o bot mandou desde entao. Serve pra
# atravessar uma linha que o OCR nao enxerga (a Vitalidade neste cliente). Vai pro estado.txt.
$script:stCarry = @{}; $script:stParcial = @()
function Tick-Stats {   # so roda enquanto upa (nunca durante captcha)
  if((Get-Date) -lt $script:statDue){ return }
  # Na reta final o portao do level nao vale: com os 4 atributos perto do cap, o level pode nem subir mais e sao
  # justamente os ultimos pontos que liberam o /darmr. Entao la ele le rapido e sempre.
  $base = if($script:pertoDoMax){ $StatEveryNearSec } else { $StatEverySec }
  # Recuo progressivo: 149 das 264 leituras da sessao (56%) nao renderam UM comando - mediana de 556 pontos,
  # abaixo do piso. Cada uma abre a janela C, rouba o foco e gasta ~3s pra descobrir que nao da pra gastar nada.
  # Depois de N leituras vazias seguidas o intervalo dobra, ate o teto; a primeira leitura util zera o recuo.
  $teto = if($script:pertoDoMax){ $StatEveryNearSec * 4 } else { $StatMaxSec }   # perto do cap o recuo e curto: la a pressa vale
  $intervalo = [Math]::Min($teto, $base * [Math]::Pow(2, [Math]::Min($script:statVazias, 5)))
  # O portao do level NAO vale quando quem pediu a leitura foi o Read-Level, por ter perdido a caixa calibrada:
  # ali o $lvlPrev esta CONGELADO justamente porque o level nao pode ser lido, entao "mesmo level" seria sempre
  # verdade e o bot pularia a unica leitura capaz de recalibrar. Era esse o laco que deixava ate 116s cego.
  if(-not $script:pertoDoMax -and -not $script:forcaStat){
    $mesmoLevel = ($null -ne $script:lvlPrev -and $script:lvlPrev -eq $script:statLvlLast)
    if($mesmoLevel -and (Get-Date) -lt $script:statMax){ $script:statDue = (Get-Date).AddSeconds((Jit $intervalo)); return }
  }
  $script:forcaStat = $false
  $script:statLvlLast = $script:lvlPrev
  $script:statMax = (Get-Date).AddSeconds($StatMaxSec)
  Distribute-Points
  $script:statDue = (Get-Date).AddSeconds((Jit $intervalo))
}
$script:lvlPrev = $null; $script:lvlChangedAt = Get-Date; $script:lvlLogged = $null; $script:lvlSame = 0   # lvlSame = leituras BEM-SUCEDIDAS seguidas com o level identico
$script:stallPts = -1   # pontos disponiveis na ultima avaliacao de miss infinito (ver Check-Progress)
function Check-Progress([int]$lvl, $img){   # level parado: se saiu do spot, re-teleporta (retorna $false p/ reiniciar o ciclo); se esta no spot parado, religa helper (miss infinito). $true = segue normal
  if($lvl -ne $script:lvlPrev){ $script:lvlPrev = $lvl; $script:lvlChangedAt = Get-Date; $script:lvlSame = 0; return $true }
  $script:lvlSame++
  # DUAS condicoes, nao um relogio so. As leituras iguais sao o sinal forte e nao mentem: leitura que o OCR nao
  # conseguiu nem chega aqui, enquanto o relogio sozinho corria durante elas e acusava "parado" sem prova.
  # Os segundos sao o piso pra nao disparar cedo logo apos o reset, com o char fraco.
  $parado = [int]((Get-Date) - $script:lvlChangedAt).TotalSeconds
  if($script:lvlSame -lt $StallReads -or $parado -lt $StallMinSec){ return $true }
  # TERCEIRA condicao: os PONTOS DISPONIVEIS subiram? Entao o char esta matando, e nao esta travado - o level e
  # que anda em degraus (level alto, mob fraco, ou o proprio teto). O bot ja tem esse numero na mao, da ultima
  # leitura de status; nao custa uma captura a mais.
  # Medido no MR #15, o melhor do log: dos 19 ciclos, os 3 com miss infinito somaram 646s de EXCESSO sobre o p25
  # (61s) - um deles com 10 disparos seguidos e o char ganhando ponto o tempo todo (16, 32, 64...). Cada disparo
  # custa ESC + pausa + anda + religa helper. Era a maior causa isolada da cauda lenta, acima ate do captcha.
  # A base e atualizada SEMPRE, senao distribuir os pontos (que zera o disponivel) desligaria a guarda pro resto do ciclo.
  # GANHO ACUMULADO, nao saldo. Comparar $ptsLeft sozinho era auto-sabotagem: a distribuicao ZERA o saldo, entao
  # ~20s depois de todo /f /a /v /e a guarda via "0 pontos, nao subiu" e deixava o falso positivo passar. Medido:
  # 36 dos 105 disparos do log (34%) cairam ate 30s depois de um comando de distribuicao, com o char matando
  # normalmente - pontos entrando a 300-600 por leitura. E os ciclos marcados 'stall' somavam 51% de TODO o tempo
  # do bot (21 de 199 ciclos), contra 29% dos 122 ciclos limpos. Era a maior causa isolada da lentidao.
  # $ptsSent + $ptsLeft so cresce enquanto o char mata, e a distribuicao move valor de um pro outro sem mudar a soma.
  $ganho = $script:ptsSent + $script:ptsLeft
  if($ganho -le $script:stallPts){
    # A leitura de status pode estar velha (ate $StatEverySec), e decidir "travado" com numero velho e o erro
    # que essa guarda existe pra evitar. Aqui - e SO aqui, no caminho raro - vale pagar uma leitura fresca:
    # custa ~2.5s contra os ~17s de ESC + andar + religar helper que viriam a seguir, e so roda quando as outras
    # duas condicoes ja apontaram travamento (21 dos 541 resets do log).
    $fresco = Read-Status
    if($fresco){ $script:ptsLeft = [Math]::Max(0, [int]$fresco.Pts); $ganho = $script:ptsSent + $script:ptsLeft }
  }
  $subiu = ($ganho -gt $script:stallPts); $script:stallPts = $ganho
  if($subiu){ $script:lvlChangedAt = Get-Date; $script:lvlSame = 0; return $true }
  $script:lvlChangedAt = Get-Date; $script:lvlSame = 0
  # $null = : Start-Helper DEVOLVE $true/$false, e sem descartar isso a funcao saia com DOIS valores. O chamador
  # faz `if(-not (Check-Progress ...))` e um array de 2 itens e sempre "verdadeiro" em PowerShell: o $false daqui
  # era engolido e o ciclo NUNCA reiniciava depois de re-teleportar. Achado pelo self-check do test_ciclos.
  if(-not (In-Farm $img)){ Log "level parado e fora do spot: re-teleportando"; if(Warp-To-Spot){ $null = Start-Helper }; return $false }
  Log "level parado ha ${parado}s no spot ($StallReads leituras iguais, miss infinito): ESC + pausa + anda + despausa"
  Tag-Ciclo 'stall'
  $null = Focus-Game   # o Hold-Focus nao traz mais o jogo sozinho (ver $NoFocusRead) e o ESC abaixo precisa dele
  Close-Popup   # se o que travou foi uma janela/modal aberta por acidente, andar nao resolve - ESC resolve
  $pb = Play-XY; if($pb){ $null = Click-Client $pb.X $pb.Y }; Wait 2   # pausa o helper
  Walk-Forward                                          # anda um pouco (desbuga o miss infinito)
  $null = Start-Helper; $true                           # religa o ataque (descarta o retorno dele: quem responde aqui e o $true)
}
$script:humanDue = (Get-Date).AddSeconds((Get-Random -Minimum $HumanMinSec -Maximum $HumanMaxSec))
function Tick-Human {   # de vez em quando, em ordem aleatoria, faz algo que um humano faria (pra nao parecer bot 100% do tempo)
  if((Get-Date) -lt $script:humanDue){ return }
  $script:humanDue = (Get-Date).AddSeconds((Get-Random -Minimum $HumanMinSec -Maximum $HumanMaxSec))
  $prev = Focus-Game; if(-not $script:gameFg){ Restore-Focus $prev; return }
  $h = Get-Game; $c = New-Object W+RECT; [W]::GetClientRect($h,[ref]$c) | Out-Null; $cx = [int]($c.R/2); $cy = [int]($c.B/2)   # personagem fica no centro
  switch(Get-Random -Maximum 4){
    0 { $dx = Get-Random -Minimum -160 -Maximum 160; $dy = Get-Random -Minimum -110 -Maximum 110; Log "humano: anda ($dx,$dy) e volta"
        Restore-Focus $prev; $null = Click-Client ($cx+$dx) ($cy+$dy); Wait (Get-Random -Minimum 1.5 -Maximum 3.5); $null = Click-Client ($cx-$dx) ($cy-$dy); Wait 2; Start-Helper; return }
    1 { Log "humano: abre e fecha o status"; Close-Chat; Press-Vk $StatusKey $HotkeyHoldMs; Wait (Get-Random -Minimum 1 -Maximum 3); Press-Vk $StatusKey $HotkeyHoldMs }
    2 { # Este arrastaria o SEU ponteiro por ate ~5s. Com o jogo noutro monitor nao vale o disfarce: pula.
        if($NoFocusRead){ Log "humano: pulei o 'mexe o mouse' (jogo noutro monitor, o ponteiro e seu)"; break }
        Log "humano: mexe o mouse"; $o = Client-Origin; 1..(Get-Random -Minimum 3 -Maximum 8) | % { [W]::SetCursorPos($o.X + (Get-Random -Maximum $c.R), $o.Y + (Get-Random -Maximum $c.B)) | Out-Null; Start-Sleep -Milliseconds (Get-Random -Minimum 150 -Maximum 600) } }
    3 { Log "humano: abre e fecha o chat"; if(-not (Chat-Open)){ Press-Vk 0x0D; Wait (Get-Random -Minimum 1 -Maximum 3) }; Close-Chat }
  }
  Restore-Focus $prev
}
function Get-Points($words){   # numero na mesma linha do rotulo "Pontos". -1 se nao achou
  # O padrao aceita o rotulo MASTIGADO pelo OCR. Na versao web (game.mudinhox.com.br) os pontos sao um BOTAO
  # "Pontos: 244" e o OCR devolveu '%' + 'ritos:' + '244' - o "Pon" virou "%", entao `^pont` nao casava e o bot
  # lia "sem pontos" com 244 na tela. Ler ponto como zero e exatamente como um char empilhou 1.66 MILHAO deles.
  # `tos:?$` pega 'ritos:', 'ntos', 'Pontos'. Conferido no painel inteiro (web e desktop): nenhuma outra palavra
  # termina em "tos", entao afrouxar aqui nao cria falso positivo.
  $lab = $words | ? { $_.Text -match '(?i)(^pont|tos:?$)' } | select -First 1; if(-not $lab){ return -1 }
  $yc = $lab.BoundingRect.Y + $lab.BoundingRect.Height/2
  $n = $words | ? { $_.Text -match '^\d{1,7}$' -and $_.BoundingRect.X -gt $lab.BoundingRect.X -and [Math]::Abs(($_.BoundingRect.Y + $_.BoundingRect.Height/2) - $yc) -lt ($lab.BoundingRect.Height + 4) } | sort { $_.BoundingRect.X } | select -First 1
  if($n){ [int]$n.Text } else { -1 }
}
function Status-Open($words){ [bool]($words | ? { $_.Text -match '(?i)^(pont|energia|vitalidade|agilidade|for)' }) }
function Parse-Attrs($words){   # das words do OCR global: acha cada rotulo (For/Agi/Vit/Ene) e pega o numero a direita na mesma linha. Robusto a deslocamento da janela (mudanca de resolucao)
  $vals = @{}
  $pat = @{ For='(?i)^(for|str)'; Agi='(?i)^agi'; Vit='(?i)^v(?!elo).*dade'; Ene='(?i)^ene' }   # Vitalidade: OCR le "vwidade"; casa V...dade mas exclui "Velocidade" (linha de detalhe) e "Vida"
  foreach($k in $pat.Keys){
    $w = $words | ? { $_.Text -match $pat[$k] } | select -First 1; if(-not $w){ continue }
    $yc = $w.BoundingRect.Y + $w.BoundingRect.Height/2
    $n = $words | ? { $_.Text -match '^\d{1,6}$' -and $_.BoundingRect.X -gt $w.BoundingRect.X -and [Math]::Abs(($_.BoundingRect.Y + $_.BoundingRect.Height/2) - $yc) -lt ($w.BoundingRect.Height + 6) } | sort { $_.BoundingRect.X } | select -First 1   # primeiro numero a direita, mesma linha
    if($n){ $vals[$k] = [int]$n.Text }
  }
  $vals
}
# Aqui existia um "recorte aprendido" pra evitar o OCR da tela inteira. REMOVIDO por medicao:
# OCR global 88ms contra ~30ms no recorte, UMA vez a cada 15s = 0.4% de um core. Nao pagava a complexidade,
# aprendia caixa errada (chegou a 1378x775, 72% da tela) e, quando envelhecia, custava um OCR A MAIS.
function Ocr-Status($img){
  # O OCR do Windows NAO le o painel de status na resolucao nativa: a fonte e pequena e o fundo cinza-escuro.
  # Medido no print de 13:49 - na tela inteira ele devolveu UMA palavra ('Satan'); recortando o painel e
  # ampliando 2x devolveu tudo (For=19880 Agi=20000 Vit=15000 Ene=27000 Pontos=1192). Era essa a causa dos
  # 100 "nao consegui ler o status" e dos "nao li Vit"/"Pts=-1" do log, nao a tecla C.
  # Ampliar 3x volta a falhar (imagem grande demais), entao 2x nao e chute: e o unico que funciona.
  $r = @()
  $pw = [int]($img.Width * $StatPanelFrac.W); $ph = [int]($img.Height * $StatPanelFrac.H)
  if($pw -gt 0 -and $ph -gt 0){
    $c = Crop-Bitmap $img 0 0 $pw $ph $StatPanelScale
    $r = @((Ocr-Bitmap $c).Lines | % { $_.Words }); $c.Dispose()
  }
  # Fallback pra tela inteira: se o painel abrir noutro lugar (as janelas deste cliente nao tem posicao fixa -
  # o inventario ja abriu em (1317,408) e em (607,333)), pelo menos nao ficamos cegos.
  if(-not (Status-Open $r)){ $r = @((Ocr-Bitmap $img).Lines | % { $_.Words }) }
  $r
}
function Read-Status {   # abre a janela de status (C), le os 4 atributos + pontos, fecha. @{For;Agi;Vit;Ene;Pts} ou $null
  $prev = Focus-Game; if(-not $script:gameFg){ Restore-Focus $prev; return $null }
  Close-Chat; $out = $null; $fechou = $false
  for($try = 0; $try -lt 6; $try++){
    # C ALTERNA: tentativa par aperta, impar le sem apertar (senao uma leitura ruim FECHA a janela e ele alterna pra sempre).
    # 900ms e o tempo que a janela precisa pra aparecer - cortei pra 350 quando otimizei o tickrate e o "nao consegui ler o status" virou constante.
    if($try % 2 -eq 0){
      $null = Focus-Game   # reafirma o foco ANTES de cada tecla: so checar no inicio nao basta - se a sua janela volta, o C vai pra ELA e o status nunca abre (era a causa das falhas)
      if(-not $script:gameFg){ Log "status: jogo perdeu o foco, nao vou apertar C"; Wait 1; continue }
      Press-Vk $StatusKey $HotkeyHoldMs
      # Era Start-Sleep 900 fixo. Agora espera SO ate a janela aparecer: captura a cada 150ms e segue assim que
      # a leitura reconhece o painel. Com o recorte do OCR ela costuma aparecer em ~300ms, entao sobram ~600ms
      # por leitura - e sao centenas de leituras por hora, todas com o foco preso no jogo.
      $viu = $false
      for($w = 0; $w -lt 8 -and -not $viu; $w++){
        Start-Sleep -Milliseconds 150
        $t = Capture-Raw
        if($script:capOk -and (Status-Open (Ocr-Status $t))){ $viu = $true }
        $t.Dispose()
      }
    }
    $img = Capture-Raw
    if(-not $script:capOk){ $img.Dispose(); Log "status: a captura pegou outra janela, nao vou ler"; Wait 1; continue }   # nunca le (nem salva print) da tela de outro programa
    $words = Ocr-Status $img
    if(Status-Open $words){
      $v = Parse-Attrs $words; $v['Pts'] = Get-Points $words
      for($k = 0; $k -lt 2 -and @('For','Agi','Vit','Ene' | ? { -not $v.ContainsKey($_) }).Count; $k++){   # faltou atributo: rele com a janela aberta e combina
        $img.Dispose(); Start-Sleep -Milliseconds 400; $img = Capture-Raw; $words = Ocr-Status $img
        $v2 = Parse-Attrs $words; foreach($kk in $v2.Keys){ if(-not $v.ContainsKey($kk)){ $v[$kk] = $v2[$kk] } }; if($v2.ContainsKey('Pts')){ $v['Pts'] = $v2['Pts'] } else { $v['Pts'] = Get-Points $words }
      }
      $miss = @('For','Agi','Vit','Ene') | ? { -not $v.ContainsKey($_) }
      # O print so serve quando a leitura FALHA. Antes ia pro disco em TODA leitura: ~3500 por sessao, 3.8MB
      # cada, numa pasta dentro do OneDrive - uns 13GB de re-upload por noite pra reescrever sempre o mesmo nome.
      if($miss){ $null = Salvar-Print $img 'status_ultimo.png' }
      # CALIBRA A CAIXA DO LEVEL enquanto o painel esta aberto: aqui o level e VERDADE (tem rotulo do lado) e a
      # HUD esta visivel na mesma foto. E o unico momento em que da pra saber qual dos numeros da tela e o level.
      # So quando nao ha caixa: custa um OCR de tela cheia, entao nao se paga isso a cada leitura de status.
      if(-not $script:lvlBox){
        $lp = Get-Level-Painel $words
        if($lp){ $null = Calibrar-LevelBox $img $lp }
      }
      $img.Dispose()
      Press-Vk $StatusKey $HotkeyHoldMs; Start-Sleep -Milliseconds 300; $fechou = $true   # fecha
      foreach($k in @('For','Agi','Vit','Ene')){ if($miss -notcontains $k){ $script:stCarry[$k] = [int]$v[$k] } }   # o que FOI lido vira memoria
      # Uma leitura 3-de-4 nao pode valer zero. Neste cliente o OCR do Windows simplesmente NAO enxerga a linha
      # da Vitalidade - confirmado no print salvo, em pt-BR e en-US, escalas 1x a 4x, cru e binarizado: devolve
      # so o "(+0)" da linha. Foram 429 leituras perdidas assim e o char empilhou 423 MIL pontos sem gastar um.
      # Um atributo so muda quando o proprio bot manda /f /a /v /e, entao "ultimo lido + o que mandei desde
      # entao" (mantido em $stCarry) e valor EXATO, nao chute.
      $script:stParcial = @()
      foreach($k in $miss){ if($null -ne $script:stCarry[$k]){ $v[$k] = $script:stCarry[$k]; $script:stParcial += $k } }
      $semFonte = @('For','Agi','Vit','Ene') | ? { -not $v.ContainsKey($_) }
      if($semFonte){ Log ("status: nao li " + ($semFonte -join ',') + " e nao tenho valor guardado (li " + (($v.GetEnumerator() | % { "$($_.Key)=$($_.Value)" }) -join ',') + "). Print em captcha\status_ultimo.png") }
      else {
        if($script:stParcial.Count){ Log ("status: OCR nao leu " + ($script:stParcial -join ',') + "; usando o valor que o bot ja sabia (" + (($script:stParcial | % { "$_=$($v[$_])" }) -join ' ') + "). Print em captcha\status_ultimo.png") }
        $out = $v
      }
      break
    }
    if($try -eq 5){   # desistiu: salva a tela pra dar pra ver se a janela ESTAVA aberta (OCR falhou) ou nao abriu mesmo (tecla C engolida)
      if(Salvar-Print $img 'status_falhou.png'){ Log "status: nao abriu em 6 tentativas. Print em captcha\status_falhou.png" }
      else { Log "status: nao abriu em 6 tentativas (sem print: a tela nao era a do jogo)" }
    }
    $img.Dispose(); Wait 1   # nao abriu (tecla ignorada logo apos reset): tenta de novo
  }
  # A alternancia deixa a janela ABERTA quando desiste (aperta C nas tentativas 0,2,4 = 3 vezes = aberta), e o
  # bot segue achando que esta fechada. O proximo /resetar e digitado com o painel de status por cima - e no log
  # 83 dos 179 /resetar simplesmente sumiram, quase sempre logo depois de uma leitura de status. Fecha na saida.
  if(-not $fechou){   # nao aperta C no escuro: se a leitura falhou porque o C nem chegou, apertar aqui ABRIRIA
    $img = Capture-Raw
    if($script:capOk -and (Status-Open (Ocr-Status $img))){ Press-Vk $StatusKey $HotkeyHoldMs; Start-Sleep -Milliseconds 300; Log "status: janela ficou aberta apos falhar, fechei" }
    $img.Dispose()
  }
  Restore-Focus $prev; $out
}
function Login-Btn($img){   # onde clicar pra voltar pro jogo, ou $null. DOIS sinais: botao play irreconhecivel (fora do jogo) + texto conhecido
  if(-not $img -or (Get-HelperState $img) -ne 'unknown'){ return $null }   # play verde/vermelho = dentro do jogo; nem gasta OCR
  $linhas = @((Ocr-Bitmap $img).Lines)
  $perigo = [bool]($linhas | ? { $_.Text -match $LoginDangerWords })   # "CRIAR NOVA CONTA"/"Sair": nunca clicar por perto
  $alvo = $null
  foreach($l in $linhas){
    if($LoginServerWords -and $l.Text -match $LoginServerWords){ $alvo = $l; break }   # tela de escolha de servidor
  }
  if(-not $alvo){ $alvo = $linhas | ? { $_.Text -match "^($LoginWords)$" } | select -First 1 }   # tela de personagem
  if($alvo){
    $r = @($alvo.Words)[0].BoundingRect
    $x2 = (@($alvo.Words) | % { $_.BoundingRect.X + $_.BoundingRect.Width } | measure -Maximum).Maximum
    return @{ X = [int](($r.X + $x2)/2); Y = [int]($r.Y + $r.Height/2); Perigo = $perigo }
  }
  if($perigo){ return @{ X = -1; Y = -1; Perigo = $true } }   # reconheci a tela mas NAO sei onde clicar: melhor avisar que chutar
  $null
}
$script:viuLogin = $false
function Enter-Game([string]$motivo){   # clica pra entrar com o personagem ate o botao play aparecer. $true se voltou pro jogo
  Log "tela de login detectada ($motivo): tentando entrar de novo"
  $script:viuLogin = $false   # o Master-Reset usa isto pra saber se o personagem REALMENTE saiu do jogo
  for($i = 0; $i -lt 12 -and -not $script:stop; $i++){
    $img = Capture-Game
    if($img -and (Get-HelperState $img) -ne 'unknown'){ $img.Dispose(); Log "de volta no jogo"; return $true }
    $btn = if($img){ Login-Btn $img } else { $null }
    $alturaCli = if($img){ $img.Height } else { $ClientEsperado.H }   # pro fallback cego seguir a altura REAL da janela
    if($img){ $img.Dispose() }
    if($btn){ $script:viuLogin = $true }   # confirmou que estava FORA do jogo (nao so que o play sumiu por um loading)
    if($btn -and $btn.X -lt 0){   # reconheci a tela (tem "CRIAR NOVA CONTA"/"Sair") mas nao sei em que botao clicar: JAMAIS chutar coordenada aqui
      Notify "MudinhoX" "Estou na tela de servidor/login e nao sei qual botao clicar. Entra manualmente (ou ajuste `$LoginServerWords)."
      Wait 30; continue
    }
    if(-not $btn){   # nao reconheci nada: pode ser so tela de loading. So usa a coordenada de config apos insistir
      if($i -lt 3){ Log "tela de login: nao achei o botao ainda, esperando"; Wait 5; continue }
      $btn = @{ X = [int](($(if($img){$img.Width}else{$ClientEsperado.W})) * $LoginBtnFrac.X); Y = $alturaCli - [int]($alturaCli * $LoginBtnFrac.YFromBottom) }
    }
    Log "tela de login: clicando ($($btn.X),$($btn.Y))"; $null = Click-Client $btn.X $btn.Y; Wait 8
  }
  Notify "MudinhoX" "Nao consegui entrar de novo na tela de login ($motivo). Da uma olhada."; $false
}
function Master-Reset {   # atributos cheios: /darmr -> tela de selecao -> clica pra entrar com o personagem -> volta pro loop
  # CONFIRMA com uma 2a leitura antes de mandar: um erro de OCR nos 4 atributos dispara /darmr a toa, e como
  # a leitura seguinte repete o erro isso vira LOOP de /darmr recusado (ja aconteceu neste projeto).
  $conf = Read-Status
  if(-not $conf){ Log "/darmr: nao consegui reler o status pra confirmar, deixo pro proximo tick"; return }
  if((Points-Needed $conf) -gt 0){ Log "/darmr CANCELADO: a releitura mostra F=$($conf.For) A=$($conf.Agi) V=$($conf.Vit) E=$($conf.Ene) (a 1a leitura estava errada)"; return }
  # Nao BLOQUEIA: se um atributo veio da memoria e ela estiver errada, o proprio servidor recusa o /darmr e o
  # bloco abaixo ja trata isso ("/darmr NAO APLICOU"). Mas registra, porque e a decisao mais cara do ciclo.
  if($script:stParcial.Count){ Log "/darmr indo com $($script:stParcial -join ',') vindo da memoria (OCR nao leu a linha) - se o servidor recusar, e aqui que se olha" }
  if(-not (Send-Chat "/darmr")){ return }
  Notify "MudinhoX" "Atributos no maximo: mandei /darmr. Tentando entrar de novo com o personagem."
  Wait 10
  if(Enter-Game '/darmr'){
    # Enter-Game devolve $true assim que ve o botao play - e isso tambem e verdade quando o /darmr foi RECUSADO
    # e o personagem nunca saiu do jogo. Sem esta checagem o bot contava MR falso, zerava as metricas e ia pro warmup.
    Wait 5
    $depois = Read-Status
    if($depois -and (Points-Needed $depois) -le 0){
      Log "== /darmr NAO APLICOU: atributos continuam cheios (F=$($depois.For) A=$($depois.Agi) V=$($depois.Vit) E=$($depois.Ene)) =="
      Notify "MudinhoX" "O /darmr nao aplicou (atributos continuam no maximo). Da uma olhada."
      $null = Save-Shot 'darmr_recusado.png'
      return   # nao conta MR, nao zera metrica, nao vai pro warmup
    }
    if(-not $depois -and -not $script:viuLogin){   # nao deu pra ler E nunca vi tela de login: provavelmente nao aplicou
      Log "/darmr: nao vi tela de login nem consegui ler o status - NAO vou contar como master reset"
      return
    }
    $script:mrs++; $script:mrsSessao++   # mrs = da vida do char (vem do estado.txt); mrsSessao = so deste processo, e o que a janelinha mostra
    Cota-Rolar   # antes de contar: se o MR caiu depois da meia-noite, ele e do dia NOVO
    $script:mrsDia++
    $dur = [Math]::Round(((Get-Date) - $script:mrStart).TotalHours, 2); $script:mrStart = Get-Date
    Log "== MASTER RESET #$($script:mrs) FEITO (levou ${dur}h, $($script:resets) resets) | $($script:mrsDia) de $(if($MrsPorDia -gt 0){ $MrsPorDia } else { 'infinito' }) hoje =="   # o marco que interessa
    Notify "MudinhoX" "Master reset #$($script:mrs) feito em ${dur}h."
    $script:resets = 0; $script:ptsSent = 0; $script:runStart = Get-Date; $script:ativoSeg = 0; $script:stallPts = -1   # zera pra medir o proximo MR limpo (o stallPts acompanha: a base dele e $ptsSent, que acabou de zerar)
    # Bateu a cota do dia: para de resetar e vai mixar joias ate virar o dia. O modo joias ja e exatamente isso
    # (farma no spot da fase, mixa, repete, sem /resetar e sem /darmr), entao o descanso nao precisou de modo novo.
    # O Warp-To-Spot dele respeita a fase, entao o char recem-saido do /darmr vai pro $WarmupCmd, nao pro $WarpCmd.
    if($MrsPorDia -gt 0 -and $script:mrsDia -ge $MrsPorDia -and -not $script:cotaJoias){
      $script:cotaJoias = $true; $script:modo = 'joias'; Sync-BotoesModo
      Log "== COTA DIARIA: $($script:mrsDia) master resets hoje (limite $MrsPorDia). Parando de resetar; vou mixar joias ate virar o dia. =="
      Notify "MudinhoX" "Cota do dia: $($script:mrsDia) master resets. Parei de resetar, vou mixar joias ate amanha."
    }
    # Antes ia direto pro warmup. Agora TESTA o spot normal: se o char aguentar, economiza os 37-56 min que o
    # warmup custava por MR. Se nao aguentar, Tick-WarmupTeste percebe e cai pro Lost Tower sem perder a noite.
    if($WarmupTeste){
      $script:phase = 'normal'; $script:warmupCount = 0
      $script:spotTeste = $true; $script:spotTesteIni = Get-Date
      Log "pos-MR: testando o spot normal ($WarpCmd) por ate $WarmupTesteSec s antes de decidir pelo warmup"
    } else {
      $script:phase = 'warmup'; $script:warmupCount = 0; Log "modo warmup ($WarmupCmd ate $WarmupResets resets)"
    }
    Save-Estado; $script:restartCycle = $true
  }
}
function Walk-Forward {   # ~4 passos numa direcao aleatoria. SO usado pra desbugar o miss infinito (o passeio pos-warp foi removido a pedido do usuario)
  $h = Get-Game; $c = New-Object W+RECT; [W]::GetClientRect($h,[ref]$c) | Out-Null
  $ang = Get-Random -Minimum 0.0 -Maximum 6.2832; $dx = [int]($WalkDist * [Math]::Cos($ang)); $dy = [int]($WalkDist * 0.75 * [Math]::Sin($ang))   # isometrico: vertical mais curto
  Log "andando 4 passos ($dx,$dy)"; $null = Click-Client ([int]($c.R/2)+$dx) ([int]($c.B/2)+$dy); Wait 2.5
}
function Wait-Map([string]$want,[double]$maxSec,[string]$diff = ''){   # espera ATE o mapa mudar, em vez de dormir o tempo cravado.
  $fim = (Get-Date).AddSeconds($maxSec)               # 18s dos 88s do ciclo eram Start-Sleep fixo: ~12s por ciclo recuperaveis (13 min por MR)
  do {
    Wait 1
    $m = Read-Map $null
    if($want){ if(Same-Map $m $want){ return $m } }
    elseif($diff){ if($m -and -not (Same-Map $m $diff)){ return $m } }   # sem nome esperado: espera SAIR de $diff (usado pra aprender o mapa de um spot novo)
    elseif($m){ return $m }
  } while((Get-Date) -lt $fim -and -not $script:stop)
  Read-Map $null
}
function Warp-To-Spot {   # teleporta pro spot da fase atual (warmup=, normal=) e confirma pelo mapa. Sucesso = ja num mapa de farm ou chegou num. $false = desistiu
  $cmd = if($script:phase -eq 'warmup'){ $WarmupCmd } else { $WarpCmd }
  $want = Spot-Map
  $before = Read-Map $null
  if(Same-Map $before $want){ $script:farmMap = $before; Log "ja no spot (mapa: $before, fase: $($script:phase))"; return $true }   # ja no spot CORRETO da fase
  $cego = 0; $travado = $false
  for($t = 1; $t -le $WarpTries; $t++){
    if(-not (Send-Chat $cmd)){ Wait 10; continue }
    $now = Wait-Map $want $WarpWaitSec $(if($want){ '' } else { $before })   # chega e segue; nao dorme os 9s inteiros
    # $WarpMap vazio = APRENDE aqui. Nao da pra saber de fora que nome o minimapa mostra num spot novo (/k37 e
    # companhia), e chutar errado e pior que nao saber: o bot acharia que nunca chegou e re-teleportaria a noite toda.
    # A regra e so "acabei de mandar o warp e estou num mapa que NAO e cidade". Exigir que o mapa tenha MUDADO era
    # errado e travou de verdade em 12:01: o char ja estava em Kanturu, o mapa nao mudou, nada foi aprendido e o
    # bot queimou os 4 warps ("antes 'kanturu'", "esperado ''"). Ja estar no destino e o caso de SUCESSO mais comum.
    if(-not $want -and (Is-FarmMap $now)){
      $script:WarpMap = $now.Substring(0, [Math]::Min(4, $now.Length)); $want = $script:WarpMap
      Log "aprendi o mapa de ${cmd}: '$now' -> gravando '$want' no estado.txt (pra reaprender, apague a linha warpMap= de la)"
      Save-Estado
    }
    if(Same-Map $now $want){ $script:farmMap = $now; Log "no spot (mapa: $now, fase: $($script:phase))"; return $true }   # chegou no spot certo
    if($now){
      Tag-Ciclo 'warp'; Log "nao teleportou pro spot certo (mapa: '$now', esperado '$want', antes '$before'), tentativa $t/$WarpTries ($cmd)"
      if($t -eq 1){   # le a resposta do servidor e fotografa na PRIMEIRA falha (a mensagem some rapido)
        $msg = Log-GameMsg $null "apos $cmd"; $null = Save-Shot 'warp_falhou.png'
        # O servidor esta DIZENDO qual e o problema e o bot ignorava: "nao pode se mover" = ha janela de NPC (ou
        # modal) aberta, e nenhuma quantidade de /k37 resolve isso. Foram 54 min mandando o mesmo comando em
        # 12/09, depois de o mix desistir com o dialogo de confirmar na tela. Fechar e o que destrava.
        if($msg -match $MsgTravadoWords -and $msg -match '(?i)moment'){
          Log "warp: o jogo diz que o char NAO PODE SE MOVER - tem janela aberta na tela. Fechando antes de tentar de novo."
          $travado = $true
          Unstick-Tudo
        }
      }
    }
    else { $cego++; Tag-Ciclo 'warp'; Log "NAO CONSEGUI LER o nome do mapa (minimapa recolhido ou tapado?), tentativa $t/$WarpTries ($cmd)" }
  }
  if($cego -ge $WarpTries){   # nunca deu pra ler: o problema e a LEITURA, nao o teleporte. Reenviar /s18 nao resolve nada.
    $f = Save-Shot 'mapa_ilegivel.png'
    Notify "MudinhoX" "Nao consigo LER o nome do mapa no minimapa. Abra o painel do minimapa (setinha no canto). Print: $f"
    return $false
  }
  # O aviso tem que dizer O QUE FAZER. Em 12/09 sairam 55 notificacoes iguais de "da uma olhada" enquanto a causa
  # (janela de NPC aberta, deixada pelo mix que desistiu) estava escrita na tela o tempo todo. Se o ESC nao
  # resolveu, quem resolve e voce - mas so se o aviso disser isso.
  if($travado){
    $f = Save-Shot 'warp_travado.png'
    Notify "MudinhoX" "O jogo diz que o char NAO PODE SE MOVER e o ESC nao resolveu: deve ter janela de NPC aberta. Fecha na mao. Print: $f"
    return $false
  }
  Notify "MudinhoX" "Nao consegui teleportar com $cmd ($WarpTries tentativas). Da uma olhada."; $false
}
function Start-Helper {   # liga o helper e CONFIRMA. Para de clicar apos PlayTries (nao insiste cego). $true se confirmou running
  for($i = 0; $i -lt $PlayTries; $i++){
    $st = Get-HelperState
    if($st -eq 'running'){ if($i){ Log "helper rodando" }; return $true }
    if($st -eq 'stopped'){
      $pb = Play-XY; if(-not $pb){ Log "play: nao achei o botao no canto superior esquerdo"; break }
      Log "clicando play ($($i+1)/$PlayTries) em ($($pb.X),$($pb.Y))"; $null = Click-Client $pb.X $pb.Y
      # Espera ATIVA dentro da mesma janela de 2.5s: o helper costuma ligar na hora, e dormir os 2.5s inteiros
      # custava ~2s por ciclo (~42s por master reset). O piso ANTES do 2o clique continua igual - o play e um
      # ALTERNADOR, e clicar de novo cedo demais DESLIGA o helper. Era so pra isso que o sleep cheio existia.
      $ate = (Get-Date).AddSeconds(2.5)
      while((Get-Date) -lt $ate){ if((Get-HelperState) -eq 'running'){ Log "helper rodando"; return $true }; Wait 0.4 }
      continue
    }
    Wait 2   # botao nao reconhecido (tela ainda carregando): espera sem clicar
  }
  if((Get-HelperState) -eq 'running'){ Log "helper rodando"; return $true }
  # FOTOGRAFA A FALHA. Medido em 15/09: o helper liga em 20 de 24 vezes (83%) e falha nas outras 4, e as tres
  # explicacoes obvias ja cairam - a caixa (78,30) esta em cima do botao, o classificador acerta com folga ali
  # (124 pixels vermelhos contra os >10 que ele exige) e nao ha relacao com o tempo desde o teleporte (sucesso e
  # falha acontecem ambos 0-1s depois de chegar ao spot). Sem ver o botao no instante da falha, qualquer
  # correcao aqui seria chute - e chute em limiar de cor ja produziu falso positivo neste projeto.
  # O print passa pelo Salvar-Print, entao NAO grava nada se a tela nao for a do jogo.
  $f = Save-Shot 'helper_nao_ligou.png'
  Log "helper nao ligou apos $PlayTries cliques, parei de tentar$(if($f){ ' - print em captcha\helper_nao_ligou.png' })"
  $false
}
# ---------- inventario / mix de joias ----------
function Screen-Words($img){ @((Ocr-Bitmap $img).Lines | % { $_.Words }) }
function Word-Center($w){ @{ X = [int]($w.BoundingRect.X + $w.BoundingRect.Width/2); Y = [int]($w.BoundingRect.Y + $w.BoundingRect.Height/2) } }
function Word-Color($img,$w){   # cor do BOTAO atras da palavra: 'green' (disponivel), 'red' (indisponivel) ou 'other'
  # Os botoes do modal sao verde/vermelho ESCUROS (~(45,85,45) e ~(90,40,40)). O limiar antigo exigia canal > 110
  # e classificava os dois como 'other' - nenhuma joia era vista como verde. Agora e comparacao RELATIVA entre canais.
  $r = $w.BoundingRect; $g = 0; $rd = 0
  $x1 = [Math]::Max(0,[int]$r.X); $y1 = [Math]::Max(0,[int]$r.Y)
  $x2 = [Math]::Min($img.Width-1, [int]($r.X + $r.Width)); $y2 = [Math]::Min($img.Height-1, [int]($r.Y + $r.Height))
  for($y = $y1; $y -le $y2; $y++){ for($x = $x1; $x -le $x2; $x++){
    $p = $img.GetPixel($x,$y)
    if($p.R + $p.G + $p.B -lt 60){ continue }   # quase preto: nao decide nada
    if($p.G -gt $p.R + 18 -and $p.G -gt $p.B + 18){ $g++ }
    elseif($p.R -gt $p.G + 18 -and $p.R -gt $p.B + 18){ $rd++ }
  } }
  if($g -gt $rd -and $g -gt 20){ 'green' } elseif($rd -gt $g -and $rd -gt 20){ 'red' } else { 'other' }
}
function Inv-Occupancy($img,$grid){   # matriz de celulas ocupadas ($true = tem item). $null se a grade nao foi localizada
  if(-not $grid){ $grid = Achar-InvGrid $img }
  if(-not $grid){ return $null }
  $c = [double]$grid.Cell   # celula tem tamanho fracionario (34.4): arredondar acumula 3px de erro na 8a coluna
  @(for($r = 0; $r -lt $grid.Rows; $r++){
    ,@(for($k = 0; $k -lt $grid.Cols; $k++){
      $lit = 0
      for($y = 5; $y -lt $c-5; $y += 2){ for($x = 5; $x -lt $c-5; $x += 2){
        $px = [int]($grid.X + $k*$c + $x); $py = [int]($grid.Y + $r*$c + $y)
        if($px -lt $img.Width -and $py -lt $img.Height){ $p = $img.GetPixel($px,$py); if(($p.R + $p.G + $p.B) -gt $InvCellLit){ $lit++ } }
      } }
      ($lit -gt $InvCellMin)
    })
  })
}
function Achar-InvGrid($img){   # acha a grade ANCORADA NO TITULO da janela. Coordenada fixa nao serve: o painel abriu
  # em (1317,408) na calibracao e em (607,333) depois - ele NAO tem posicao fixa. O titulo "Inventario" e a ancora,
  # e achar o titulo tambem prova que a janela esta aberta (bem melhor que caçar a palavra "Zen", pequena e vermelha).
  $t = Screen-Words $img | ? { $_.Text -match $InvTituloWords } | select -First 1
  if(-not $t){ return $null }
  $r = $t.BoundingRect
  $cx = [int]($r.X + $r.Width/2)
  # ATENCAO: a caixa do OCR no titulo OSCILA (visto ao vivo: (652,314) e (689,300) com 8s de diferenca = 37px,
  # mais que uma celula de 34.4px). Medido no fixture: o MESMO inventario cheio le 0 livres alinhado e 26 livres
  # 20px fora. Ou seja, a CONTAGEM POR CELULA nao e confiavel com esta ancora.
  # Tentei refinar escolhendo o deslocamento que deixa as celulas mais "decisivas" - NAO FUNCIONA: num inventario
  # cheio toda celula tem item, entao grade torta pontua igual. Por isso a contagem virou informativa e o gatilho
  # de "cheio" passou a ser a MENSAGEM do jogo + o teto de tempo, que nao dependem de alinhamento.
  @{ X = $cx + $InvGridDx; Y = [int]$r.Y + $InvGridDy; Cell = $InvCellPx; Cols = 8; Rows = 8; Titulo = "$($t.Text)" }
}
function Inv-Open($img){ [bool](Achar-InvGrid $img) }   # titulo visivel = painel aberto
function Abrir-Inv-PeloMenu {   # caminho alternativo: a tecla configurada nao abre o inventario neste cliente, mas o
  # menu do jogo (botao de 3 barras no topo direito) tem um item "Inventario". Mesmo padrao do NPC do mix:
  # clica, CONFIRMA por OCR que o menu abriu, so entao clica no item. Nunca clica no escuro.
  Log "inventario: tentando pelo menu do jogo (a tecla nao abriu)"
  # posicao do botao de menu em fracao do CANVAS (o topo do canvas vem do rotulo do minimapa, ver Topo-Do-Canvas)
  $ic = Capture-Raw; $iy0 = Topo-Do-Canvas $ic
  $mx = [int]($ic.Width * $InvMenuFrac.X); $my = $iy0 + [int](($ic.Height - $iy0) * $InvMenuFrac.Y); $ic.Dispose()
  $null = Click-Client $mx $my -KeepFocus
  # Achar o proprio item "Inventario" ja prova que o menu abriu - e procurar ate achar cobre o tempo variavel de desenho
  $item = Achar-Ate $InvMenuWords $MixConfirmTentativas
  if(-not $item){
    Log "inventario: o menu nao abriu (ou nao achei o item). Fechando com ESC."
    Close-Popup; return $false
  }
  $c = Word-Center $item
  # No menu cada item e um ICONE com o rotulo EMBAIXO. O OCR acha o texto, mas o clicavel e o icone ACIMA dele:
  # clicar no rotulo abriu o menu e nao aconteceu nada (visto no print de 10:35:50, tela continuou no Stadium).
  $cy = [Math]::Max(0, $c.Y + $InvMenuClickDy)
  Log "inventario: clicando no icone de '$($item.Text)' ($($c.X),$cy)"
  $null = Click-Client $c.X $cy -KeepFocus
  Wait 2.5
  $true
}
function Inv-Free {   # abre o inventario (V), conta celulas livres, fecha. -1 se nao calibrado, nao abriu ou nao deu pra ler
  if($script:invDesligado){ return -1 }
  $prev = Focus-Game; if(-not $script:gameFg){ Restore-Focus $prev; return -1 }
  Close-Chat
  $map = $null
  for($try = 0; $try -lt 4 -and -not $map; $try++){   # V ALTERNA igual o C: tentativa par aperta, impar le sem apertar (senao uma leitura ruim FECHA a janela e ele alterna pra sempre)
    if($try % 2 -eq 0){
      $null = Focus-Game   # reafirma o foco antes da tecla (mesmo motivo do Read-Status: sem isso o V vai pra janela do usuario)
      if(-not $script:gameFg){ Log "inventario: jogo perdeu o foco, nao vou apertar V"; Wait 1; continue }
      Press-Vk $InvKey $HotkeyHoldMs; Start-Sleep -Milliseconds 900
    } else { Start-Sleep -Milliseconds 300 }
    $img = Capture-Raw
    if($script:capOk){ $g = Achar-InvGrid $img; if($g){ $map = Inv-Occupancy $img $g; Log "inventario: grade em ($($g.X),$($g.Y)) pelo titulo '$($g.Titulo)'" } }
    $img.Dispose()
  }
  if(-not $map -and $InvUsarMenu){   # a tecla nao abriu: tenta pelo menu do jogo antes de desistir
    if(Abrir-Inv-PeloMenu){
      $img = Capture-Raw
      if($script:capOk){ $g = Achar-InvGrid $img; if($g){ $map = Inv-Occupancy $img $g; Log "inventario: abriu pelo menu, grade em ($($g.X),$($g.Y))" } }
      $img.Dispose()
    }
  }
  if($map){ Press-Vk $InvKey $HotkeyHoldMs; Start-Sleep -Milliseconds 200 }   # fecha
  Restore-Focus $prev
  if(-not $map){
    # Falha recorrente em todo start. O print + o que o OCR leu na faixa do Zen dizem QUAL dos dois casos e:
    # janela nao abriu (faixa com cenario/vazio) ou abriu noutro lugar (faixa com outro texto do jogo).
    $script:invFalhas++
    Log "inventario: nao consegui abrir/confirmar a janela (tecla $('{0:X2}' -f $InvKey))"
    Unblock-Areas   # pode ser a propria janela do bot cobrindo a grade
    $null = Save-Shot 'inventario_falhou.png'
    if($script:invFalhas -ge $InvMaxFalhas){
      # Insistir custa caro: aperta uma tecla que talvez nem seja a do inventario, varias vezes, a cada ciclo.
      # Se nao e o atalho certo, sabe-se la o que ela dispara no personagem. Desiste e avisa UMA vez.
      $script:invDesligado = $true
      Log "inventario: desisti apos $($script:invFalhas) falhas - a tecla configurada nao abre o inventario neste cliente. Ajuste \$InvKey. O botao MIXAR JOIAS continua funcionando."
      Notify "MudinhoX" "A tecla do inventario esta errada (\$InvKey). Desliguei a checagem automatica; o mix pelo botao continua."
    }
    return -1
  }
  $script:invFalhas = 0
  @($map | % { $_ } | ? { -not $_ }).Count
}
$script:npcPos = $null   # onde o Lahap foi confirmado da ultima vez (por OCR). Vale mais que qualquer chute
function Hover-Npc {   # passa o mouse ate o nome do NPC aparecer. Devolve o ponto confirmado ou $null. Chamar com o jogo na frente
  # SEM coordenada cravada. Tres fontes, nesta ordem:
  #  1. onde ele foi CONFIRMADO por OCR da ultima vez (o mapa do /mixer nao muda, entao isso acerta sempre depois da 1a vez)
  #  2. fracao do CANVAS (nao da area cliente: na web a barra do navegador empurra tudo pra baixo)
  #  3. a varredura em volta, que ja existia
  # O nome do NPC so aparece com o mouse EM CIMA dele, entao nao da pra procurar por texto antes de chegar la -
  # por isso aqui e varredura, e nao OCR direto. Mas nada disso clica: quem autoriza o clique e o OCR do nome.
  $o = Client-Origin
  $img0 = Capture-Raw; $y0 = Topo-Do-Canvas $img0; $cw = $img0.Width; $ch = $img0.Height - $y0; $img0.Dispose()
  $base = if($script:npcPos){ $script:npcPos } else { @{ X = [int]($cw * $MixNpcFrac.X); Y = $y0 + [int]($ch * $MixNpcFrac.Y) } }
  foreach($dy in $MixNpcSweep){ foreach($dx in $MixNpcSweep){
    $x = $base.X + $dx; $y = $base.Y + $dy
    if($x -lt 0 -or $y -lt $y0 -or $x -ge $cw -or $y -ge ($y0 + $ch)){ continue }
    [W]::SetCursorPos($o.X + $x, $o.Y + $y) | Out-Null; Start-Sleep -Milliseconds 350
    $img = Capture-Raw
    $c = Crop-Bitmap $img ([Math]::Max(0,$x-150)) ([Math]::Max(0,$y+$MixNpcNameDy-25)) 300 60 2   # o nome so aparece com o mouse em cima: le so a faixa acima do cursor
    $txt = (Ocr-Bitmap $c).Text; $c.Dispose(); $img.Dispose()
    if($txt -match $MixNpcWords){
      $script:npcPos = @{ X = $x; Y = $y }   # confirmado por OCR: da proxima vez comeca daqui e acerta de primeira
      Log "mix: NPC confirmado em ($x,$y) - OCR leu '$($txt.Trim())'"
      return $script:npcPos
    }
  } }
  $script:npcPos = $null   # nao achou: nao insiste no ponto velho na proxima
  $null
}
function Tirar-Cursor {   # o ponteiro do mouse APARECE na captura e apaga a palavra debaixo dele no OCR.
  # No 1o mix real ele ficou parado em cima de 'Jewel of Chaos' e o bot nao viu que aquela opcao estava verde.
  try { $o = Client-Origin; [W]::SetCursorPos(($o.X + $CursorParkX), ($o.Y + $CursorParkY)) | Out-Null; Start-Sleep -Milliseconds 120 } catch {}
}
function Achar-Ate([string]$pat,[int]$tentativas,[switch]$MaisAbaixo){   # procura uma palavra na tela ate achar.
  # UI de jogo demora um tempo VARIAVEL pra desenhar: o dialogo de confirmacao do mix apareceu DEPOIS da leitura
  # unica do bot (o print de diagnostico, 1s mais tarde, mostrava ele na tela). Olhar uma vez perde a janela.
  for($t = 0; $t -lt $tentativas; $t++){
    Wait 1
    Tirar-Cursor   # o ponteiro apaga a palavra debaixo dele no OCR
    $img = Capture-Raw
    $ws = @(Screen-Words $img | ? { $_.Text -match $pat })
    $img.Dispose()
    if($ws.Count){
      if($MaisAbaixo){ return ($ws | sort { $_.BoundingRect.Y } | select -Last 1) }   # ex: o BOTAO "Mixar Joias", nao o titulo
      return $ws[0]
    }
  }
  $null
}
function Lista-Mix-Aberta($words){   # a lista de joias esta na tela? (o modal fecha a cada mix confirmado)
  [bool]($words | ? { $_.Text -match $MixListaWords })
}
function Abrir-Modal-Mix([int]$volta){   # NPC -> botao "Mixar Joias". $true se abriu
  $npc = Hover-Npc
  if(-not $npc){
    # A mensagem separa as duas causas, que pedem coisas opostas: NPC ausente no lugar CERTO e varredura pra
    # ajustar ($MixNpcFrac / $MixNpcSweep); warp que nao pegou e outro problema, e varrer nao resolve.
    if($volta -eq 0){
      $null = Save-Shot 'mix_sem_npc.png'
      Notify "MudinhoX" $(if($script:mixChegou){ "Cheguei no $MixCmd mas o NPC nao apareceu na varredura." }
                         else { "O $MixCmd nao me levou pro mixer (o mapa nao mudou) - por isso nao achei o NPC." })
    }
    else { Log "mix: nao achei o NPC pra reabrir o modal, encerrando" }
    return $false
  }
  Log "mix: clicando no NPC ($($npc.X),$($npc.Y))"
  $null = Click-Client $npc.X $npc.Y -KeepFocus
  # -MaisAbaixo: o "Mixar" de cima e o TITULO da janela; o botao e o de baixo
  $menu = Achar-Ate $MixMenuWords $MixConfirmTentativas -MaisAbaixo
  if(-not $menu){
    if($volta -eq 0){ Notify "MudinhoX" "Cliquei no NPC mas nao abriu o modal 'Mixar Joias'." }
    else { Log "mix: o modal nao reabriu, encerrando" }
    return $false
  }
  $c = Word-Center $menu; Log "mix: clicando '$($menu.Text)' em ($($c.X),$($c.Y))"
  $null = Click-Client $c.X $c.Y -KeepFocus; Wait 2
  $true
}
function Mix-Jewels {   # /mixer -> NPC -> "Mixar Joias" -> mixa TODAS as opcoes verdes (reabrindo o modal a cada uma) ate sobrar so vermelho
  Tag-Ciclo 'mix'; Log "mix: indo pro $MixCmd"
  # O return mudo daqui escondia a falha: o gatilho por tempo disparava, o comando morria e o log nao dizia nada.
  if(-not (Send-Chat $MixCmd)){ Log "mix: nao consegui mandar $MixCmd (captcha na tela? jogo sem foco?) - tento de novo no proximo tick"; return $false }
  # Relogio do mix por tempo: zerado depois que o $MixCmd SAIU, e AQUI porque e o unico ponto por onde os dois
  # modos passam (Tick-Inventory e Ciclo-Joias). Zerar antes do Send-Chat gastaria a janela de $MixEveryMin
  # inteira num comando que o jogo engoliu, sem o personagem ter saido do spot. Depois daqui ele ja saiu: se o
  # NPC nao aparecer, nao adianta voltar la em 1 min.
  $script:mixLast = Get-Date
  # Era `Wait $WarpWaitSec` cravado (9s). Medido em 164 mixes do log: do /mixer ate achar o NPC davam 12.4s, e a
  # maior fatia era esse sleep esperando um teleporte que cai em 2-3s. Agora espera pelo RESULTADO - o nome do
  # mapa mudar - com o mesmo teto de antes. Estourou o teto, segue mesmo assim: o Hover-Npc logo abaixo confere
  # o nome do NPC por OCR antes de clicar, entao chegar cedo demais nao clica em lugar nenhum.
  $mapaAntes = Read-Map $null
  $ate = (Get-Date).AddSeconds($WarpWaitSec)
  do { Wait 1; $mapaAgora = Read-Map $null } until (($mapaAgora -and $mapaAgora -ne $mapaAntes) -or (Get-Date) -ge $ate)
  # REGISTRA se chegou mesmo. Sem isto o bot dizia "Cheguei no /mixer mas o NPC nao apareceu" sem ter conferido
  # que chegou - e as duas causas pedem coisas opostas: NPC ausente no lugar certo e um problema de varredura,
  # ja o warp que nao pegou e um problema de warp, e varrer 34s atras de um NPC noutro mapa nao resolve nenhum
  # dos dois. Em 15/09 a unica falha do log ficou ambigua exatamente por isso.
  $script:mixChegou = [bool]($mapaAgora -and $mapaAgora -ne $mapaAntes)
  if($script:mixChegou){ Log "mix: cheguei (mapa '$mapaAntes' -> '$mapaAgora')" }
  else {
    Log "mix: o mapa NAO mudou em ${WarpWaitSec}s (li '$mapaAgora', antes '$mapaAntes') - reenviando $MixCmd"
    if(Send-Chat $MixCmd){
      $ate = (Get-Date).AddSeconds($WarpWaitSec)
      do { Wait 1; $mapaAgora = Read-Map $null } until (($mapaAgora -and $mapaAgora -ne $mapaAntes) -or (Get-Date) -ge $ate)
      $script:mixChegou = [bool]($mapaAgora -and $mapaAgora -ne $mapaAntes)
      Log $(if($script:mixChegou){ "mix: cheguei na 2a tentativa (mapa '$mapaAgora')" } else { "mix: o mapa continua '$mapaAgora' - sigo assim mesmo, o NPC confirma ou nao" })
    }
  }
  $prev = Focus-Game; if(-not $script:gameFg){ Restore-Focus $prev; return $false }
  try {
    $mixados = 0; $anterior = $null   # $anterior = joia clicada na volta passada, ainda sem veredito
    for($round = 0; $round -lt $MixRounds; $round++){
      Tirar-Cursor   # depois de clicar, o cursor fica EM CIMA da lista e some com a palavra debaixo dele no OCR
      $img = Capture-Raw; $words = Screen-Words $img
      # Confirmar um mix FECHA o modal. Sem reabrir, a volta seguinte varre uma tela sem lista, nao acha verde
      # e o bot conclui "acabou" tendo mixado so a primeira - foi o que aconteceu no 1o mix real (4 estavam verdes).
      if(-not (Lista-Mix-Aberta $words)){
        $img.Dispose()
        if(-not (Abrir-Modal-Mix $round)){ break }
        $img = Capture-Raw; $words = Screen-Words $img
      }
      $verde = $null
      foreach($j in $MixJewels){
        $w = $words | ? { $_.Text -match $j.Pat } | select -First 1
        if(-not $w){ continue }
        if((Word-Color $img $w) -eq 'green'){ $verde = @{ J = $j; W = $w }; break }
      }
      $img.Dispose()
      # VEREDITO DA VOLTA ANTERIOR, e nao a mensagem do chat: a joia clicada saiu do verde = mixou de verdade.
      # Se o clique nao tivesse mixado, ela continuaria verde e seria escolhida DE NOVO nesta volta. O "Sucesso!
      # voce mixou N" e leitura fraca - falhou em 5 dos 6 mixes que comprovadamente aconteceram (01/09 e 04/09),
      # e o log fechava com "terminado (0 mix)" logo depois de mixar Soul, Life e Creation. Com o mix rodando
      # sozinho a cada $MixEveryMin, um contador que sempre diz 0 esconde a falha de verdade quando ela vier.
      if($anterior){
        if(-not $verde -or $verde.J.Name -ne $anterior){ $mixados++; $script:joiasMix++; Log "mix: $anterior mixado (saiu do verde)" }
        else { Log "mix: $anterior continua verde - o clique nao mixou" }
      }
      $anterior = $(if($verde){ $verde.J.Name } else { $null })
      if(-not $verde){ Log "mix: nenhuma opcao verde sobrou ($mixados mixados)"; break }
      $c = Word-Center $verde.W
      # print ANTES de clicar, igual ao captcha: fica o registro de qual opcao estava verde e onde o bot clicou
      New-Item -ItemType Directory -Force $CaptchaShotDir | Out-Null
      $shot = Join-Path $CaptchaShotDir ("mix_{0}_{1}.png" -f (Get-Date -Format 'yyyyMMdd_HHmmss'), $verde.J.Name)
      $imgS = Capture-Raw; try { $imgS.Save($shot) } catch {}; $imgS.Dispose()
      Log "mix: $($verde.J.Name) verde em ($($c.X),$($c.Y)), clicando. Print: $(Split-Path $shot -Leaf)"
      $null = Click-Client $c.X $c.Y -KeepFocus
      # Clicar na joia abre um SEGUNDO dialogo ("Mixar 12 Jewel of Soul / Deseja continuar?" com CONFIRMAR e CANCELAR).
      # Ele demora um tempo VARIAVEL pra aparecer: com uma leitura unica apos 1.5s o bot ja perdeu o dialogo que o
      # print de diagnostico (tirado 1s depois) mostrava na tela. Entao PROCURA ate achar, em vez de olhar uma vez.
      $conf = Achar-Ate $MixConfirmWords $MixConfirmTentativas
      if(-not $conf){
        Log "mix: cliquei em $($verde.J.Name) mas nao achei o botao CONFIRMAR"
        $null = Save-Shot 'mix_sem_confirmar.png'
        # CANCELAR DE VERDADE, nao so desistir. Sair daqui com o dialogo na tela custou 54 min em 12/09 e 81 min
        # em 13/09, as duas unicas vezes que isto aconteceu: com janela de NPC aberta o servidor recusa TODO
        # warp ("Voce nao pode se mover neste momento"), e o bot fica reenviando /k37 contra uma parede. O ESC do
        # Close-Popup NAO fecha esse dialogo - foi tentado nas duas vezes e nas duas falhou. So o botao fecha.
        $canc = Achar-Ate $MixCancelWords $MixConfirmTentativas
        if($canc){
          $cx = Word-Center $canc
          Log "mix: clicando CANCELAR em ($($cx.X),$($cx.Y)) - dialogo aberto travaria todo warp daqui pra frente"
          $null = Click-Client $cx.X $cx.Y -KeepFocus
          Wait 1
        } else {
          # Sem CONFIRMAR e sem CANCELAR na tela, o bot nao sabe o que esta aberto. Ai sim e caso de chamar voce -
          # e o Close-Popup no fim do laco ainda tenta o ESC, que as vezes resolve dialogo de outro tipo.
          Log "mix: nao achei nem CONFIRMAR nem CANCELAR - nao sei o que esta aberto, chamando voce"
          Notify "MudinhoX" "O mix abriu um dialogo que eu nao reconheci e nao achei o CANCELAR. Fecha na mao e clique RETOMAR."
        }
        break
      }
      $cc = Word-Center $conf
      Log "mix: confirmando em ($($cc.X),$($cc.Y))"
      $null = Click-Client $cc.X $cc.Y -KeepFocus
      # "Sucesso! voce mixou N Soul Points" no chat e BONUS, nao veredito: a faixa vive cheia de anuncio de jogador
      # e a leitura falha na maioria das vezes. Quem conta e a volta seguinte (a joia saiu do verde).
      # Era um laco de $MixConfirmTentativas x (Wait 1 + OCR) esperando essa mensagem que quase nunca vem: com o
      # $MixWaitSec somado deu 11.5s por joia em 197 medicoes. Agora e UMA leitura, e ela nem decide nada.
      Wait 1
      if((Read-Msgs $null) -match $MixSucessoWords){ Log "mix: $($verde.J.Name) confirmado pelo jogo" }
      Wait $MixWaitSec
    }
    Close-Popup
    Log "mix: terminado ($mixados mix), voltando pro farm"
    $mixados -gt 0
  } finally { Restore-Focus $prev }
}
$script:mixNow = $false; $script:semPlay = 0; $script:invFalhas = 0; $script:invDesligado = $false
$script:mixLast = Get-Date   # quando o bot foi mixar pela ultima vez (gatilho por tempo do ciclo normal)
$script:mixChegou = $false   # o ultimo $MixCmd levou mesmo o char pro mixer? (separa "NPC sumido" de "warp nao pegou")
function Tick-Inventory {   # aviso do jogo, teto de tempo (ou botao MIXAR AGORA) -> vai mixar e reinicia o ciclo (volta pro spot)
  # A contagem periodica de celulas saiu daqui: abria e fechava o inventario a cada 2 min (dois cliques, foco
  # roubado) pra produzir um numero que oscila com o alinhamento da grade - o MESMO inventario cheio leu 0 e 26
  # livres com 20px de diferenca na ancora. Sobrou o gatilho confiavel: a mensagem do proprio jogo. Inv-Free
  # continua existindo pro -Preflight e pro -TestInv, onde o numero e so informativo.
  # ...so que a mensagem NUNCA chegou: 0 ocorrencias de "inventario cheio" em 42 mil linhas de rpa.log, e no
  # mesmo periodo 68 pausas manuais suas pra mixar na mao. A faixa de mensagens e dominada por chat de jogador
  # (anuncio de troca), e o aviso de inventario cheio nao cai la. O modo joias ja tinha o teto de tempo
  # ($JoiasFarmMax) justamente por isso; o ciclo normal ficou sem gatilho nenhum. Agora tem o mesmo teto.
  if($MixEveryMin -gt 0 -and -not $script:mixNow -and ((Get-Date) - $script:mixLast).TotalMinutes -ge $MixEveryMin){
    $script:mixNow = $true; Log "inventario: $MixEveryMin min desde o ultimo mix -> indo mixar (o jogo nao avisa 'cheio' nesta faixa)"
  }
  if(-not $script:mixNow){ return }
  $script:mixNow = $false
  $null = Mix-Jewels
  $script:ptsLastGain = Get-Date   # mixar tambem nao distribui pontos: nao deixa o watchdog de progresso contar esse tempo
  $script:restartCycle = $true   # volta pro spot pelo caminho normal (warp + andar + play)
}
# ATENCAO: nomes de variavel no PowerShell sao case-INSENSITIVE. $script:warmupTeste e o MESMO que $WarmupTeste
# do CONFIG - a variavel de estado zerava a config no start e o teste do spot nunca rodava (visto ao vivo no
# MR #5: caiu direto no "modo warmup"). Por isso o estado se chama $script:spotTeste, e nao warmupTeste.
$script:spotTeste = $false; $script:spotTesteIni = Get-Date
function Tick-WarmupTeste {   # o teste do spot normal pos-MR estourou o tempo? cai pro warmup em vez de insistir
  if(-not $script:spotTeste){ return }
  if(((Get-Date) - $script:spotTesteIni).TotalSeconds -lt $WarmupTesteSec){ return }
  $script:spotTeste = $false
  $script:phase = 'warmup'; $script:warmupCount = 0; $script:restartCycle = $true; Save-Estado
  Log "pos-MR: o spot normal nao fechou um reset em $WarmupTesteSec s - char fraco demais, indo pro warmup ($WarmupCmd)"
}
function Jit([double]$sec){ $sec * (1 + (Get-Random -Minimum (-$JitterPct) -Maximum $JitterPct)) }   # varia o RITMO (nunca os valores dos stats, que precisam ser exatos)
$script:runStart = Get-Date; $script:resets = 0; $script:ptsSent = 0; $script:ptsNeeded = -1
$script:mrs = 0; $script:mrStart = Get-Date; $script:resumo = ''; $script:ciclos = @(); $script:ultimoReset = $null
$script:tagsCiclo = @()
function Tag-Ciclo([string]$t){ if($script:tagsCiclo -notcontains $t){ $script:tagsCiclo += $t } }   # o que atrapalhou o ciclo atual
function CicloSeg($c){ [int](("$c" -split ':')[0]) }        # ciclo e "segundos" ou "segundos:tag+tag"
function CicloTags($c){ $p = "$c" -split ':'; if($p.Count -gt 1){ $p[1] } else { '' } }
function Mediana($a){ if(-not $a -or $a.Count -eq 0){ return 0 }; $s = @(@($a | % { CicloSeg $_ }) | sort); [int]$s[[int]($s.Count/2)] }
# ---------- quantos resets ainda faltam pro /darmr ----------
# O $porReset de antes era $ptsSent / $resets: media do MR INTEIRO, e ela mistura coisas que nao se parecem.
# Os $WarmupResets do Lost Tower fecham com o char fraco e rendem MUITO menos que um reset no spot normal, e no
# comeco do MR os atributos ainda estao baixos. Media com essas duas caudas nao serve pra projetar o que vem.
# Aqui a medida e POR RESET (quanto o ganho acumulado andou entre um reset e o proximo), so da fase normal, e o
# resumo e a MEDIANA - a mesma escolha que ja se fez pro ciclo, e pelo mesmo motivo: um reset travado ou um
# captcha no meio nao pode mover a projecao.
$script:ganhoPorReset = @()   # ultimos ganhos medidos, fase normal
$script:ganhoMarco = -1       # ganho acumulado no reset anterior (-1 = ainda nao ha marco)
$CapGanhos = 12               # ~metade de um MR: acompanha o char ficando mais forte sem virar media da vida toda
$script:resetsDesdeTeste = 0
function Ajustar-Alvo-Do-Proximo-Ciclo {   # re-testa o alvo do CONFIG de tempos em tempos (ver $ResetRetestResets)
  if($script:TargetLevel -le $TargetLevelConfig){ $script:resetsDesdeTeste = 0; return }   # ja esta no alvo pedido: nada a testar
  $script:resetsDesdeTeste++
  if($script:resetsDesdeTeste -lt $ResetRetestResets){ return }
  $script:resetsDesdeTeste = 0
  Log "testando de novo o alvo do CONFIG (lvl $TargetLevelConfig) contra o piso aprendido ($($script:LevelMinReset)): se o servidor aceitar, o piso cai sozinho"
  $script:TargetLevel = $TargetLevelConfig   # o teste E resetar no alvo pedido; recusando, o aprendizado sobe o piso de novo
}
function Marcar-Ganho-Do-Reset {   # chamar UMA vez por reset, logo apos ele fechar
  $ganho = $script:ptsSent + $script:ptsLeft   # ptsSent nao conta o que ainda nao foi distribuido; a soma conta
  if($script:ganhoMarco -ge 0 -and $script:phase -eq 'normal'){
    $d = $ganho - $script:ganhoMarco
    # Descarta o reset que atravessou o /darmr (o $ptsSent zera la, entao $d sai negativo) e o warmup->normal,
    # onde o marco anterior e de um reset de Lost Tower e a diferenca nao mede reset nenhum.
    if($d -gt 0){ $script:ganhoPorReset = @(@($script:ganhoPorReset) + $d | select -Last $CapGanhos) }
  }
  $script:ganhoMarco = $ganho
}
function Pontos-Por-Reset {   # mediana dos ganhos medidos; $null enquanto nao ha medida propria
  if(@($script:ganhoPorReset).Count -lt 2){ return $null }   # 1 medida nao tem mediana que preste
  $o = @($script:ganhoPorReset | sort); $o[[int]($o.Count / 2)]
}
function Resets-Faltando {   # projecao: quantos resets ainda faltam pro /darmr. $null = ainda nao da pra dizer
  if($script:ptsNeeded -lt 0){ return $null }     # status nunca lido
  if($script:ptsNeeded -eq 0){ return 0 }
  $pr = Pontos-Por-Reset
  # Sem medida propria ainda, cai na media do MR - pior, mas melhor que nao dizer nada nos primeiros resets.
  if(-not $pr -and $script:resets -gt 0){ $pr = [int]($script:ptsSent / $script:resets) }
  if(-not $pr -or $pr -le 0){ return $null }
  [Math]::Ceiling($script:ptsNeeded / $pr)
}
function Log-Plano {   # o que o bot VAI fazer, em duas linhas, logo no start
  # O plano estava espalhado por quatro variaveis de CONFIG ($WarmupResets, $WarmupCmd, $WarpCmd, $TargetLevel)
  # e por duas de estado (fase, warmupCount). Pra saber o que o bot ia fazer era preciso juntar tudo de cabeca -
  # e quando ele fazia outra coisa (spot errado, fase errada retomada do estado.txt) isso so aparecia dali a
  # varios minutos, no meio do log. Declarado aqui, uma linha desmente a outra na hora.
  $ciclo = if($WarmupTeste){ "TESTA $WarpCmd primeiro; se nao fechar um reset em ${WarmupTesteSec}s, cai pro warmup" }
           else { "$WarmupResets resets em $WarmupCmd (warmup: apos o /darmr o char volta fraco)" }
  Log "plano: $ciclo -> depois $WarpCmd ate os 4 atributos no cap -> /darmr"
  $agora = if($script:modo -eq 'joias'){ "MODO JOIAS - farma em $WarpCmd, mixa no $MixCmd, NAO reseta" }
           elseif($script:phase -eq 'warmup'){ "warmup $($script:warmupCount)/$WarmupResets -> vai pra $WarmupCmd" }
           else { "fase normal -> vai pra $WarpCmd" }
  Log ("  agora: {0} | reseta no level {1} (piso {2}) | {3} resets e {4} pontos neste MR" -f `
       $agora, $script:TargetLevel, $script:LevelMinReset, $script:resets, $script:ptsSent)
}
function Metrics {   # o objetivo e o /darmr, nao o reset: o numero que importa e PONTOS/HORA e o ETA do MR. Reset e so o meio.
  $h = $script:ativoSeg / 3600.0   # TEMPO ATIVO, nao relogio de parede: downtime nao pode afundar a taxa
  if($h -le 0.01){ return }
  $ph = [int]($script:ptsSent / $h)
  $eta = if($ph -gt 0 -and $script:ptsNeeded -gt 0){ [Math]::Round($script:ptsNeeded / $ph, 1) } else { -1 }
  # MEDIDO por reset (mediana da fase normal) em vez da media do MR: e o que vale pra projetar o que ainda vem.
  $medido = Pontos-Por-Reset
  $porReset = if($medido){ $medido } elseif($script:resets -gt 0){ [int]($script:ptsSent / $script:resets) } else { 0 }
  $faltamR = Resets-Faltando
  $rh = if($h -gt 0){ [Math]::Round($script:resets / $h, 1) } else { 0 }
  $script:resumo = if($eta -ge 0){ "ETA MR ${eta}h | $ph pts/h" } else { "$ph pts/h" }   # vai pro titulo da janelinha
  Log ("== MR: faltam {0} pontos ({1} resets) | {2} pontos/h | ETA ~{3} | {4} resets/h a {5} pts/reset{6} (alvo lvl {7}, piso {8}, warmup {9}) | MRs: {10} ==" -f `
       $script:ptsNeeded, $(if($null -ne $faltamR){ "~$faltamR" }else{'?'}), $ph, $(if($eta -ge 0){"${eta}h"}else{'?'}), $rh, $porReset,
       $(if($medido){ " (medido em $(@($script:ganhoPorReset).Count))" }else{ ' (media do MR)' }), $TargetLevel, $script:LevelMinReset, $WarmupResets, $script:mrs)
  # MEDIANA, nao media: numa noite a media do ciclo deu 756s e a mediana 88s - a media mentiu por 8x por causa de poucos ciclos travados.
  # O que decide o ETA do MR nao e o ciclo bom, e quanto tempo vaza nos ruins (69% do tempo numa noite medida).
  if($script:ciclos.Count -ge 4){
    $med = Mediana $script:ciclos
    $lentos = @($script:ciclos | ? { (CicloSeg $_) -gt ($med * 1.5) })
    $total = (@($script:ciclos | % { CicloSeg $_ }) | measure -Sum).Sum
    $perdido = if($lentos.Count){ (@($lentos | % { (CicloSeg $_) - $med }) | measure -Sum).Sum } else { 0 }
    $pctT = if($total -gt 0){ [int]($perdido * 100 / $total) } else { 0 }
    # POR QUE vazou: sem isto a metrica diz que se perde tempo, mas nao onde atacar
    $porCausa = @{}
    foreach($c in $lentos){
      $extra = (CicloSeg $c) - $med
      $tags = @((CicloTags $c) -split '\+' | ? { $_ })
      if(-not $tags.Count){ $tags = @('?') }
      foreach($t in $tags){ $porCausa[$t] = [int]$porCausa[$t] + [int]($extra / $tags.Count) }   # divide o excesso entre as causas do ciclo
    }
    $culpa = (@($porCausa.GetEnumerator() | sort Value -Descending | % { "{0} {1}%" -f $_.Key, [int]($_.Value * 100 / [Math]::Max(1,$total)) }) -join ', ')
    Log ("   ciclo mediano {0}s | {1}/{2} lentos (>{3}s) | {4}% do tempo perdido neles{5} | fase {6}" -f `
         $med, $lentos.Count, $script:ciclos.Count, [int]($med*1.5), $pctT, $(if($culpa){ " -> $culpa" }else{''}), $script:phase)
  }
  if($script:ui -and -not $script:ui.IsDisposed){ $script:ui.Text = "MudinhoX RPA - $($script:resumo)" }
}
function Read-Msgs($img){   # texto da faixa de mensagens do jogo (o servidor responde tudo por ali e o bot ignorava)
  # FRACAO da area cliente, nao pixel. As mensagens nao tem ancora pra procurar por texto (sao texto solto, e o
  # que se quer e justamente descobrir o que esta escrito), entao o jeito de nao cravar coordenada e descrever
  # ONDE ELAS FICAM em proporcao: faixa central-baixa, acima da barra inferior.
  # Medido nos dois layouts: desktop x 0.40-0.60 / y 0.13-0.25 da base; web x 0.32-0.68 / y 0.19-0.30.
  # A faixa abaixo e a uniao dos dois com folga. Ler texto a mais nao atrapalha - todo chamador casa por regex,
  # e a faixa ja vivia cheia de anuncio de jogador mesmo na versao estreita.
  $own = -not $img; if($own){ $img = Capture-Game }; if(-not $img){ return '' }
  $t = ''
  try {
    $x = [int]($img.Width  * $MsgFaixa.X1)
    $w = [int]($img.Width  * ($MsgFaixa.X2 - $MsgFaixa.X1))
    $y = [int]($img.Height * (1 - $MsgFaixa.Y1FromBottom))
    $h = [int]($img.Height * ($MsgFaixa.Y1FromBottom - $MsgFaixa.Y2FromBottom))
    if($w -gt 0 -and $h -gt 0 -and ($x + $w) -le $img.Width -and ($y + $h) -le $img.Height){
      $c = Crop-Bitmap $img $x $y $w $h 2
      $t = (Ocr-Bitmap $c).Text; $c.Dispose()
    }
  } catch { $t = '' }
  if($own){ $img.Dispose() }
  ($t -replace '\s+',' ').Trim()
}
function Log-GameMsg($img,[string]$quando){   # loga o que o servidor respondeu (antes so sobrava tirar print e adivinhar)
  $m = Read-Msgs $img
  if($m){ Log "jogo diz ($quando): $m" }
  $m
}
$script:msgDue = (Get-Date).AddSeconds(10)
function Tick-Msgs($img){   # le as mensagens do jogo de vez em quando (aviso de inventario cheio)
  if((Get-Date) -lt $script:msgDue){ return }
  $script:msgDue = (Get-Date).AddSeconds((Jit $MsgCheckSec))
  $m = Read-Msgs $img
  if(-not $m){ return }
  if($m -match $MsgInvWords){ Log "jogo avisou inventario cheio -> vou mixar"; $script:mixNow = $true }
}
$script:joiasMix = 0; $script:joiasCiclos = 0
$script:tuneOn = $AutoTune; $script:tuneArm = 0; $script:tuneResets = 0; $script:tunePts = 0; $script:tuneAtivo0 = 0.0; $script:tuneRes = @()
if($script:tuneOn){ $script:TargetLevel = [Math]::Max($AutoTuneAlvos[0], $LevelMinReset) }   # comeca pelo primeiro alvo da lista (Load-Estado sobrepoe se o A/B ja terminou antes)
function Tick-AutoTune {   # $TargetLevel sempre foi chute. Em vez de pedir experimento manual, o bot roda o A/B sozinho.
  # Compara PONTOS/H (nao resets/h): resetar mais cedo da mais resets, mas pode dar menos pontos por reset.
  if(-not $script:tuneOn){ return }
  $script:tuneResets++
  if($script:tuneResets -lt $AutoTuneResets){ return }
  $h = ($script:ativoSeg - $script:tuneAtivo0) / 3600.0   # tempo ATIVO do braco: travar no meio nao pode penalizar o alvo injustamente
  $ph = if($h -gt 0){ [int](($script:ptsSent - $script:tunePts) / $h) } else { 0 }
  $script:tuneRes += ,@($TargetLevel, $ph)
  Log "autotune: alvo $TargetLevel rendeu $ph pontos/h em $($script:tuneResets) resets"
  $script:tuneArm++
  if($script:tuneArm -lt $AutoTuneAlvos.Count){
    $script:TargetLevel = [Math]::Max($AutoTuneAlvos[$script:tuneArm], $script:LevelMinReset)   # nunca abaixo do minimo que o servidor exige
    $script:tuneResets = 0; $script:tunePts = $script:ptsSent; $script:tuneAtivo0 = $script:ativoSeg
    Log "autotune: testando agora alvo $($script:TargetLevel) por $AutoTuneResets resets"
    Save-Estado   # grava o braco fechado NA HORA: se o bot cair antes do proximo reset, o resultado nao se perde
  } else {
    $melhor = @($script:tuneRes | sort { $_[1] } -Descending)[0]
    $script:TargetLevel = $melhor[0]; $script:tuneOn = $false
    Log ("autotune: FIM. " + (@($script:tuneRes | % { "$($_[0])=$($_[1])pts/h" }) -join ' vs ') + " -> ficando com alvo $($melhor[0])")
    Notify "MudinhoX" "Auto-tune: melhor alvo de level e $($melhor[0]) ($($melhor[1]) pontos/h)."
    Save-Estado
  }
}
$script:ptsLastGain = Get-Date; $script:semProgresso = 0
function Unstick-Tudo {   # forca um estado conhecido. Em 01/09 uma caixa de chat aberta (nao detectada) travou tudo:
  # o C do status virava letra, o /resetar virava hotkey. ESC + fechar o chat cobre essa classe inteira.
  $prev = Focus-Game; if(-not $script:gameFg){ Restore-Focus $prev; return }
  Close-Popup                                   # ESC: fecha janela/modal do jogo
  Start-Sleep -Milliseconds 300
  if(Chat-Open){ Clear-ChatLine; Press-Vk 0x0D; Log "destravei: a caixa de chat estava aberta" }
  Restore-Focus $prev
}
function Tick-Progresso {   # rede de seguranca GERAL: o travamento de 2h passou porque nada vigiava o RESULTADO.
  # $ResetStuckMin cobre so o loop de reset; isto cobre qualquer modo de falha em que o bot "roda" sem produzir nada.
  if(((Get-Date) - $script:ptsLastGain).TotalMinutes -lt $SemProgressoMin){ return }
  $script:ptsLastGain = Get-Date
  $script:semProgresso++
  Log "SEM PROGRESSO ha $SemProgressoMin min ($($script:semProgresso)x): destravando e reiniciando o ciclo"
  Unstick-Tudo   # forca estado conhecido: fecha popup e caixa de chat (foi um chat aberto que travou o bot em 01/09)
  if($script:semProgresso -ge $SemProgressoMax){
    Save-Estado
    # Este e o UNICO lugar que ainda cria processo sozinho, e so com o bot rodando: fechar a janela ja marca
    # parada antes de chegar aqui. Quem nao quiser nem isso, $AutoRestart = $false no CONFIG e ele so para.
    if(-not $AutoRestart){
      Log "sem progresso $($script:semProgresso)x seguidas e AutoRestart desligado: parando"
      Notify "MudinhoX" "Sem progresso $($script:semProgresso)x seguidas. Parando (AutoRestart desligado)."
      $script:stopReason = 'sem progresso'; $script:stop = $true; return
    }
    # Reiniciar o PROPRIO processo resolve o que reiniciar o ciclo nao resolve (estado interno ruim) e ainda
    # recarrega o script - se houver correcao nova no disco, ela entra. O processo ja e elevado, entao o filho
    # nasce elevado SEM pedir UAC de novo.
    Log "sem progresso $($script:semProgresso)x seguidas: REINICIANDO O PROPRIO BOT"
    Notify "MudinhoX" "Sem progresso $($script:semProgresso)x seguidas. Reiniciando o bot sozinho."
    try { Start-Process powershell -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-WindowStyle","Hidden","-File","`"$PSCommandPath`"" | Out-Null } catch { Log "nao consegui relancar: $_" }
    Remove-Item $HeartbeatFile -ErrorAction SilentlyContinue   # libera pro novo processo assumir
    $script:stopReason = 'reinicio proprio'
    $script:stop = $true; return
  }
  Notify "MudinhoX" "Sem ganhar pontos ha $SemProgressoMin min. Reiniciando o ciclo - da uma olhada se repetir."
  $script:restartCycle = $true
}
function Ciclo-Joias {   # MODO JOIAS: farma no spot ate encher o inventario, vai mixar, volta a farmar. Nao reseta nem da MR.
  $script:restartCycle = $false
  Hold-Focus
  try { $ok = Warp-To-Spot; if($ok){ Start-Helper; $script:lvlChangedAt = Get-Date; $script:lvlSame = 0 } } finally { Release-Focus }
  if(-not $ok){ Wait 15; return }
  $fim = (Get-Date).AddMinutes($JoiasFarmMax)
  $cheio = $false
  # O spot e o da FASE (Warp-To-Spot escolhe): recem-saido de um /darmr o char e fraco e vai pro $WarmupCmd.
  # A linha dizia "$WarpCmd" sempre, e no descanso da cota - que comeca logo depois de um MR - isso era mentira.
  Log "joias: farmando em $(if($script:phase -eq 'warmup'){ $WarmupCmd } else { $WarpCmd }) ate encher (ou $JoiasFarmMax min)$(if($script:cotaJoias){ ' [descanso da cota diaria]' })"
  do {
    Wait (Poll-Interval); Bater-Heartbeat
    Hold-Focus
    try {
      $img = Capture-Game
      if($img){
        if(-not (Handle-Captcha $img)){
          $lvl = Read-Level $img
          # No modo joias nao ha reset, entao no level MAXIMO o level nunca muda e o detector de miss infinito
          # dispararia a cada $StallReads leituras pausando o farm a toa (visto no log: 2 disparos em 40s, level 400 fixo).
          # Leitura que FALHOU (lvl nulo) nao mexe em nada: zerar o contador ali deixaria um travamento invisivel
          # sempre que o OCR falhasse no meio dele. So o teto de level zera.
          if($null -ne $lvl){
            if($lvl -lt $LevelMaximo){ if(-not (Check-Progress $lvl $img)){ $img.Dispose(); continue } }
            else { $script:lvlPrev = $lvl; $script:lvlChangedAt = Get-Date; $script:lvlSame = 0 }
          }
          # Nada de Tick-Stats aqui: voce pediu um ciclo que "nao envolve checkar inventario, checar atributos,
          # resetar nem darmr". O log mostrava o custo - 84 leituras de status logando "0 a distribuir",
          # cada uma roubando o foco por 2-3s pra nada (no modo joias os pontos nao servem pra nada, o /darmr
          # esta bloqueado). Os pontos que sobrarem sao distribuidos assim que voltar pro modo normal.
          Tick-Msgs $img        # "inventario cheio" no chat liga $script:mixNow
          Tick-Human
          # A contagem periodica de celulas foi REMOVIDA: ela abria e fechava o inventario a cada 2 min (dois
          # cliques, foco roubado) pra produzir um numero que oscila (17 e 13 livres em 8s no mesmo inventario,
          # porque a ancora varia ate 37px) e que a gente ja tinha decidido nao usar pra adiar o mix.
          # Sobraram os dois gatilhos que nao dependem de alinhamento: aviso do jogo e teto de tempo.
          if($script:mixNow){ $script:mixNow = $false; $cheio = $true; Log "joias: hora de mixar (aviso do jogo ou botao)" }
        }
        $img.Dispose()
      }
    } finally { Release-Focus }
  } until ($cheio -or (Get-Date) -ge $fim -or $script:stop -or $script:restartCycle -or $script:modo -ne 'joias')
  if($script:stop -or $script:modo -ne 'joias'){ return }
  if(-not $cheio){ Log "joias: $JoiasFarmMax min de farm, indo mixar mesmo assim (sem deteccao de inventario cheio)" }
  Hold-Focus; try { $null = Mix-Jewels } finally { Release-Focus }
  $script:ptsLastGain = Get-Date   # mixar nao distribui pontos: nao deixa o watchdog de progresso contar esse tempo
  # As metricas do bot eram todas do master reset (pontos/h, ETA do MR) e nao valem nada aqui, que nao reseta.
  # O numero do modo joias e JOIAS/HORA - e e ele que diz se $JoiasFarmMax (chute) esta bom.
  $script:joiasCiclos++
  $h = $script:ativoSeg / 3600.0
  if($h -gt 0.02){
    Log ("== JOIAS: {0} mixadas em {1} ciclos | {2} joias/h | farm de {3} min por ciclo ==" -f `
         $script:joiasMix, $script:joiasCiclos, [Math]::Round($script:joiasMix / $h, 1), $JoiasFarmMax)
    if($script:ui -and -not $script:ui.IsDisposed){ $script:ui.Text = "MudinhoX RPA - $($script:joiasMix) joias ($([Math]::Round($script:joiasMix / $h,1))/h)" }
  }
  Save-Estado
}
function Poll-Interval {   # perto do alvo le rapido: o level sobe ~150 entre leituras e o reset saia com 400 em vez de 350
  if($null -ne $script:lvlPrev -and $script:lvlPrev -ge ($TargetLevel * $PollNearFrom)){ return $PollNearSec }
  if($NoFocusRead -or $script:gameWasFg){ $PollSec } else { $PollBgSec }
}

# ---------- calibracao do inventario / mix (nao clica em nada) ----------
if($TestInv){   # abra o inventario NO JOGO antes de rodar
  $img = Capture-Game; if(-not $img){ Log "jogo nao ficou na frente, nada lido"; exit }
  New-Item -ItemType Directory -Force $CaptchaShotDir | Out-Null
  $f = Join-Path $CaptchaShotDir 'inventario.png'; $img.Save($f); Log "print do inventario salvo: $f  (me passe o X,Y do canto sup-esq da primeira celula e o tamanho da celula em pixels)"
  if(-not (Inv-Open $img)){ Log "AVISO: nao achei o titulo do inventario -> a janela NAO esta aberta. O mapa abaixo e do chao do mapa, ignore." }
  $map = Inv-Occupancy $img
  if($map){ Log "ocupacao ($((@($map | % { $_ } | ? { -not $_ }).Count)) livres):"; foreach($r in $map){ Log ("  " + (($r | % { if($_){'X'}else{'.'} }) -join '')) } }
  else { Log "InvGrid ainda nao calibrado (veja o bloco CONFIG)" }
  $img.Dispose(); exit
}
if($TestNpc){   # de /mixer no jogo e deixe o mouse EM CIMA do Lahap: mostra a coordenada e confirma que o OCR le o nome
  $h = Get-Game
  Log "TestNpc: clique no JOGO agora e deixe o mouse parado em cima do Lahap. Comeco em 5s, leio por 20s."
  Start-Sleep 5
  for($i = 0; $i -lt 20; $i++){
    if([W]::GetForegroundWindow() -ne $h){ Log "  jogo nao esta na frente (clique nele)"; Start-Sleep 1; continue }
    $o = Client-Origin; $c = New-Object W+RECT; [W]::GetClientRect($h,[ref]$c) | Out-Null
    $p = New-Object W+POINT; [W]::GetCursorPos([ref]$p) | Out-Null
    $x = $p.X - $o.X; $y = $p.Y - $o.Y
    if($x -lt 0 -or $y -lt 0 -or $x -ge $c.R -or $y -ge $c.B){ Log "  mouse fora da area do jogo"; Start-Sleep 1; continue }
    $img = Capture-Raw
    $crop = Crop-Bitmap $img ([Math]::Max(0,$x-150)) ([Math]::Max(0,$y+$MixNpcNameDy-25)) 300 60 2
    $txt = ((Ocr-Bitmap $crop).Text).Trim(); $crop.Dispose(); $img.Dispose()
    $ok = if($txt -match $MixNpcWords){ 'CONFERE' } else { '-' }
    Log ("  cursor ({0},{1})  OCR acima do cursor: '{2}'  {3}" -f $x,$y,$txt,$ok)
    Start-Sleep 1
  }
  Log "TestNpc: o bot NAO usa mais coordenada fixa aqui - ele estima por fracao do canvas, varre em volta e confirma pelo OCR do nome. Este teste serve pra ver se o nome aparece no hover."
  exit
}
function Run-Preflight([bool]$comSpot){   # valida os subsistemas de leitura no jogo de verdade. Devolve quantas falhas.
  # Diferente do -Check: este APERTA teclas (C e V), que e a parte que mais falha. Rodado no start (sem checar spot,
  # porque o bot ainda vai warpar) e sob demanda com -Preflight (checando spot).
  $script:falhas = 0
  # Duas contas, nao uma. Ha verificacoes que SO fazem sentido com o char no spot de farm - o botao play e o
  # nome do mapa. No start o char costuma estar na cidade (acabou de logar, ou de mixar), e o bot vai warpar
  # daqui a 2 segundos: cobrar isso ali e falha inventada. Elas seguem no LOG, porque ajudam a ler o que estava
  # acontecendo, mas nao entram no aviso. Notificacao a toa ensina a ignorar notificacao - e esta disparava em
  # TODO start feito da cidade, que hoje foram varios.
  # Com -Preflight (comSpot) e outra historia: ali voce mandou conferir com o char no lugar, entao contam.
  $script:falhasReais = 0
  function Ok([string]$nome,$cond,[string]$detalhe,[switch]$PrecisaDoSpot){
    if($cond){ Log "  OK   $nome"; return }
    $script:falhas++
    if(-not ($PrecisaDoSpot -and -not $comSpot)){ $script:falhasReais++ }
    Log "  FALHOU $nome -> $detalhe$(if($PrecisaDoSpot -and -not $comSpot){ ' (esperado fora do spot: o bot ainda vai warpar)' })"
  }
  if((Game-IsAdmin) -and -not (Is-Admin)){ Log "  FALHOU privilegios -> o jogo roda elevado e este processo nao; o Windows vai ignorar teclado/mouse"; $script:falhas++ }
  else { Log "  OK   privilegios" }

  $h0 = Get-Game; $c0 = New-Object W+RECT; [W]::GetClientRect($h0,[ref]$c0) | Out-Null
  Ok 'resolucao bate com a calibracao' ($c0.R -eq $ClientEsperado.W -and $c0.B -eq $ClientEsperado.H) "$($c0.R)x$($c0.B), esperado $($ClientEsperado.W)x$($ClientEsperado.H)"

  Hold-Focus
  try {
    $img = Capture-Game
    Ok 'consegue capturar a tela do jogo' ($img -and $script:capOk) 'capturou outra janela ou o jogo nao veio pra frente'
    if($img){
      Ok 'reconhece o botao play' ((Get-HelperState $img) -ne 'unknown') 'botao play irreconhecivel (fora do jogo? tela de login?)' -PrecisaDoSpot
      $mapa = Read-Map $img
      Ok 'le o nome do mapa' ([bool]$mapa) 'minimapa recolhido ou tapado pela janela do bot?' -PrecisaDoSpot
      # Com o $WarpMap ainda vazio nao ha nome pra comparar: cobrar isso seria uma falha inventada (o bot
      # aprende o nome no primeiro teleporte). Reporta e segue.
      if($comSpot){ $sp = Spot-Map; if($sp){ Ok 'esta no spot da fase atual' (Same-Map $mapa $sp) "mapa '$mapa', esperado '$sp'" } else { Log "       mapa do spot ainda nao aprendido: vou adotar o do primeiro $WarpCmd (li '$mapa' agora)" } }
      Ok 'nenhum captcha na tela' (-not (Find-Captcha $img)) 'tem captcha aberto agora'
      $img.Dispose()
    }
    $st = Read-Status
    Ok 'le os 4 atributos' ($null -ne $st) 'Read-Status falhou (janela C nao abriu ou OCR nao leu)'
    # O level vem DEPOIS do Read-Status de proposito: a caixa do level na HUD se auto-calibra pelo painel de
    # status (o painel diz "Level: 400" com rotulo, e so sabendo o numero certo da pra achar o outro na tela).
    # Conferido antes, com a caixa ainda vazia, ele falhava sempre no primeiro start e disparava um NOTIFY de
    # "1 verificacao falhou" - alarme falso, o proprio log mostrava a calibracao dando certo 2s depois.
    Ok 'le o level' ($null -ne (Read-Level $null)) 'Read-Level devolveu nada mesmo apos a calibracao pelo painel'
    # Pts era conferido junto e passava com -1: sem os pontos o bot nao distribui nada, entao e falha propria
    # NAO e falha: sem pontos a distribuir o jogo omite a linha. So reporta o valor.
    if($st){ Log "       pontos disponiveis: $(if([int]$st.Pts -ge 0){$st.Pts}else{"0 (linha ausente)"})" }
    if($st){ Log "       F=$($st.For) A=$($st.Agi) V=$($st.Vit) E=$($st.Ene) Pts=$($st.Pts) | faltam $(Points-Needed $st) pro cap" }
    $free = Inv-Free
    Ok 'le o inventario' ($free -ge 0) 'Inv-Free devolveu -1 (tecla errada e o menu tambem nao abriu)'
    if($free -ge 0){ Log "       $free celulas livres (referencia: menos de $InvFreeMin ja e inventario cheio)" }
    $m = Read-Msgs $null
    Log $(if($m){ "  OK   le a faixa de mensagens: '$m'" } else { "  (faixa de mensagens vazia agora - normal se o chat esta quieto)" })
  } finally { Release-Focus }
  $script:falhas
}
if($Preflight){
  Log "Preflight: o personagem precisa estar NO SPOT de farm, logado e sem janela aberta"
  $f = Run-Preflight $true
  Log $(if($f){ "Preflight: $f FALHA(S) - resolva antes de deixar rodando sozinho" } else { 'Preflight: tudo OK, pode deixar rodando' })
  exit $(if($f){ 1 } else { 0 })
}
if($TestStatMin){   # o servidor aceita stat ABAIXO de 1000? Disso depende fechar o cap em 32767 - e sem fechar, o /darmr nunca sai.
  # Em 2187 linhas de log nunca saiu um comando <1000, entao esse caminho critico nunca rodou. Aqui ele roda de verdade.
  $val = 300   # valor pequeno, seguro: so em /f (o /a com valor pequeno teleporta pra AIDA)
  Log "TestStatMin: vou mandar '/f $val' e conferir se a Forca sobe. Precisa de pontos disponiveis."
  Hold-Focus
  try {
    $a = Read-Status
    if(-not $a){ Log "TestStatMin: nao consegui ler o status antes. Abortando."; exit 1 }
    Log "  antes:  For=$($a.For)  Pts=$($a.Pts)"
    if([int]$a.Pts -lt $val){ Log "TestStatMin: so tem $($a.Pts) pontos disponiveis, precisa de pelo menos $val. Farme um pouco e rode de novo."; exit 1 }
    if([int]$a.For + $val -gt $StatMaxValue){ Log "TestStatMin: Forca ja esta perto do cap, o teste passaria dele. Abortando."; exit 1 }
    $null = Send-Chat "/f $val"
    Wait 3
    $b = Read-Status
    if(-not $b){ Log "TestStatMin: nao consegui ler o status depois. Inconclusivo."; exit 1 }
    Log "  depois: For=$($b.For)  Pts=$($b.Pts)"
    $ganho = [int]$b.For - [int]$a.For
    if($ganho -eq $val){
      Log "TestStatMin: ACEITOU (+$ganho de Forca). Da pra baixar o piso de /f /v /e e fechar o cap exato."
    } elseif($ganho -eq 0){
      Log "TestStatMin: RECUSOU (Forca nao mudou). O piso de 1000 tem que ficar - e ATENCAO: assim o cap 32767 pode ser inalcancavel e o /darmr nunca sai."
      Notify "MudinhoX" "O servidor recusou /f $val. Fechar o cap exato pode ser impossivel - o /darmr depende disso."
    } else {
      Log "TestStatMin: resultado estranho, Forca subiu $ganho em vez de $val. Conferir manualmente."
    }
  } finally { Release-Focus }
  exit 0
}
if($TestVisao){   # regressao das funcoes de LEITURA DE TELA contra prints guardados em fixtures\ (nao precisa do jogo aberto)
  $falhas = 0
  function Ok([string]$nome,$cond,[string]$detalhe){ if($cond){ Log "  OK   $nome" } else { $script:falhas++; Log "  FALHOU $nome -> $detalhe" } }
  function Fx([string]$n){ $p = Join-Path $FixtureDir $n; if(Test-Path $p){ [System.Drawing.Bitmap]::FromFile($p) } else { Log "  (sem fixture $n)"; $null } }
  Log "TestVisao: rodando contra $FixtureDir"

  $i = Fx 'lorencia_modal_mix.png'
  if($i){
    Ok 'Read-Map le lorencia' ((Read-Map $i) -match '^lorencia') "leu '$(Read-Map $i)'"
    $ws = Screen-Words $i
    $menu = $ws | ? { $_.Text -match $MixMenuWords } | sort { $_.BoundingRect.Y } | select -Last 1
    # regressao: '^mixar' casava com o TITULO da janela (y~378) antes do BOTAO (y~535) e o bot clicaria no titulo
    Ok 'menu do mix pega o BOTAO, nao o titulo' ($menu -and $menu.BoundingRect.Y -gt 450) "y=$(if($menu){$menu.BoundingRect.Y}else{'nao achou'})"
    foreach($j in $MixJewels){ Ok "rotulo $($j.Name) reconhecido" ([bool]($ws | ? { $_.Text -match $j.Pat })) 'nenhuma palavra casou' }
    $i.Dispose()
  }
  # REGRESSAO da causa raiz do "nao consegui ler o status": neste print a caixa de chat esta ABERTA, mas as bordas
  # vermelhas estao em 117/92 a partir da base - as duas linhas fixas antigas (111/87) davam ZERO e o bot achava
  # que estava fechada, entao o C do status virava letra dentro do chat.
  # Print real do 1o mix: Soul/Life/Creation/Chaos VERDES, Fragment/Stone/Jewel of God VERMELHOS.
  # O bot mixou so a Soul e concluiu "acabou", porque o modal fecha a cada confirmacao e ele nao reabria.
  # Dialogo "Mixar 12 Jewel of Soul / Deseja continuar?". O bot deu por perdido lendo a tela UMA vez 1.5s apos o
  # clique; este print, tirado 1s depois, mostra o dialogo na tela. Tem que achar o CONFIRMAR e NUNCA o CANCELAR.
  $i = Fx 'mix_dialogo_confirmar.png'
  if($i){
    $ws = Screen-Words $i
    $conf = $ws | ? { $_.Text -match $MixConfirmWords } | select -First 1
    Ok 'acha o botao CONFIRMAR no dialogo' ([bool]$conf) 'nao achou CONFIRMAR na tela que o tem'
    Ok 'nao confunde CANCELAR com CONFIRMAR' (-not ($ws | ? { $_.Text -match '(?i)^cancelar$' -and $_.Text -match $MixConfirmWords })) 'o padrao casou com CANCELAR'
    Ok 'a lista NAO e considerada aberta no dialogo' (-not (Lista-Mix-Aberta $ws)) 'acharia a lista aberta e nao reabriria o modal'
    $i.Dispose()
  }
  $i = Fx 'mix_lista_4verdes.png'
  if($i){
    $ws = Screen-Words $i
    Ok 'reconhece que a lista de mix esta aberta' (Lista-Mix-Aberta $ws) 'nao detectou a lista (entao nao reabriria o modal)'
    $verdes = @(); $outras = @()
    foreach($j in $MixJewels){
      $w = $ws | ? { $_.Text -match $j.Pat } | select -First 1
      if($w){ if((Word-Color $i $w) -eq 'green'){ $verdes += $j.Name } else { $outras += $j.Name } }
    }
    # Neste print o CURSOR esta em cima de 'Jewel of Chaos' e o OCR nao le a palavra - por isso 3 e nao 4.
    # E justamente esse achado que motivou o Tirar-Cursor antes de cada leitura da lista.
    Ok 'acha as joias verdes visiveis' ($verdes.Count -ge 3) "verdes: $($verdes -join ',') | nao-verdes: $($outras -join ',')"
    $fd = $ws | ? { $_.Text -match '(?i)^fragment' } | select -First 1
    Ok 'Fragment of Death nao e verde' ($fd -and (Word-Color $i $fd) -ne 'green') 'classificou opcao vermelha como verde'
    $i.Dispose()
  }
  # chat_ABERTO_sem_borda.png e o caso que quebrou em 15/09: caixa aberta na tela ("Whisper" e "Digite sua
  # mensagem" visiveis) e a faixa inteira com 4px de corrida vermelha contra os 115 exigidos. O detector de
  # borda dizia FECHADO, a tecla C virava letra e o painel de status "nao abria em 6 tentativas". Quem resolve
  # este e a segunda prova, por texto - entao ele e o unico fixture que exercita esse caminho.
  foreach($fx in 'chat_ABERTO.png','chat_ABERTO_2.png','chat_ABERTO_sem_borda.png'){   # duas amostras independentes; nas duas as bordas ficaram em 117-118 e 92-93
    $i = Fx $fx
    if($i){ Ok "Chat-Open detecta a caixa aberta ($fx)" (Chat-Open $i) 'disse fechada com a caixa aberta (o C viraria letra no chat)'; $i.Dispose() }
  }
  # FALSO POSITIVO e o erro caro aqui: se Chat-Open mente "aberta", o Close-Chat manda Enter e ABRE um chat que
  # nao estava aberto - e dai as teclas viram letra, que foi o que cegou o bot por uma sessao inteira.
  # As capturas web sao o teste novo: o orbe de vida vermelho continua la, so que agora noutro tamanho e posicao.
  foreach($fx in 'tela_servidor.png','web_hud.png','web_status_ABERTO.png','lorencia_modal_mix.png','status_ABERTO.png'){
    $i = Fx $fx
    if($i){ Ok "Chat-Open nao inventa caixa ($fx)" (-not (Chat-Open $i)) 'disse aberta com o chat fechado - o Enter do Close-Chat abriria um de verdade'; $i.Dispose() }
  }
  # BOTAO PLAY sem coordenada: nao e texto (triangulo verde / barras vermelhas), entao a busca e pela maior
  # concentracao de verde-ou-vermelho no canto superior esquerdo, em fracao da area cliente. Precisa achar nos
  # dois layouts - na web a barra do navegador empurra o botao de y=33 pra ~116.
  # O topo do canvas e ancorado no rotulo do minimapa, entao Read-Map roda ANTES - e o que acontece em producao
  # (o bot le o mapa a cada warp e no Check-Progress). status_ABERTO tem o painel TAPANDO o botao: ali o certo e
  # devolver 'unknown', nao um palpite - clicar no lugar errado e pior que nao achar.
  foreach($pl in @(@{ F='lorencia_modal_mix.png'; E='achou' },
                   @{ F='web_hud.png';            E='achou' },
                   @{ F='status_ABERTO.png';      E='unknown' })){
    $i = Fx $pl.F
    if(-not $i){ continue }
    $script:playBox = $null; $script:mapaBox = $null
    $null = Read-Map $i                     # ancora o topo do canvas
    $st = Get-HelperState $i
    if($pl.E -eq 'achou'){ Ok "play: acha o botao e le o estado ($($pl.F))" ($st -in 'running','stopped') "devolveu '$st'" }
    else { Ok "play: nao chuta com o botao tapado ($($pl.F))" ($st -eq 'unknown') "devolveu '$st' com o painel por cima do botao" }
    $script:playBox = $null; $script:mapaBox = $null
    $i.Dispose()
  }
  $i = Fx 'tela_servidor.png'
  if($i){
    $b = Login-Btn $i
    Ok 'Login-Btn reconhece a tela de servidor' ([bool]$b) 'nao detectou (o bot ficaria mandando /s18 no vazio)'
    # regressao critica: "CRIAR NOVA CONTA" fica em y=959 e o fallback cego $LoginBtn e (960,940) - clicaria em criar conta
    Ok 'nao clica sem saber o botao' ($b -and ($b.X -ge 0 -or $b.Perigo)) 'devolveu coordenada chutada numa tela com CRIAR NOVA CONTA'
    if($LoginServerWords){ Ok 'acha o servidor configurado' ($b -and $b.X -ge 0 -and $b.Y -gt 250 -and $b.Y -lt 500) "y=$(if($b){$b.Y}else{'-'})" }
    $i.Dispose()
  }

  # Painel ABERTO, mas em (607,333) - longe dos (1317,408) da calibracao original. Prova que a posicao nao e fixa
  # e que ancorar no titulo funciona nos dois lugares.
  $i = Fx 'inventario_ABERTO_esquerda.png'
  if($i){
    $g = Achar-InvGrid $i
    Ok 'acha a grade pelo titulo, mesmo fora do lugar antigo' ([bool]$g) 'nao localizou o painel aberto'
    if($g){
      # Com a grade NA POSICAO MEDIDA a contagem e certa. Fora dela nao e - por isso a contagem e so informativa
      # e o gatilho de "cheio" nao depende dela (mensagem do jogo + teto de tempo).
      $m = Inv-Occupancy $i @{ X=607; Y=333; Cell=$InvCellPx; Cols=8; Rows=8 }
      $livres = @($m | % { $_ } | ? { -not $_ }).Count
      Ok 'na posicao medida, ve o inventario cheio como cheio' ($livres -le 4) "$livres celulas livres"
    }
    $i.Dispose()
  }

  # Regressao mais cara do dia: o OCR NAO le o painel de status na resolucao nativa (na tela inteira deste
  # print ele devolveu UMA palavra). So recortando o painel e ampliando 2x ele le os 4 atributos + os pontos.
  # Era a causa dos 100 "nao consegui ler o status" e dos "nao li Vit"/"Pts=-1" do log.
  $i = Fx 'status_ABERTO.png'
  if($i){
    $w = Ocr-Status $i
    Ok 'reconhece a janela de status aberta' (Status-Open $w) 'Status-Open disse fechada'
    $v = Parse-Attrs $w
    foreach($k in 'For','Agi','Vit','Ene'){ Ok "le $k no painel" ($v.ContainsKey($k) -and $v[$k] -gt 0) 'atributo nao foi lido' }
    Ok 'le os pontos disponiveis' ((Get-Points $w) -ge 0) 'rotulo "Pontos" nao casou com o numero'
    $i.Dispose()
  }
  # O caso que PROVA a mudanca: print de 12:48, quando o log disse "status: nao abriu em 6 tentativas".
  # Lendo a tela inteira o OCR devolve zero palavra do painel (Status-Open = False, e o bot conclui que a
  # janela nem abriu). Recortando o painel, le os 4 atributos. Sem "Pontos" no OCR porque o personagem
  # estava com 0 - o jogo esconde a linha - entao aqui a checagem e so dos atributos.
  $i = Fx 'status_ABERTO_dificil.png'
  if($i){
    $w = Ocr-Status $i
    Ok 'painel que a tela inteira nao lia agora e lido' (Status-Open $w) 'Status-Open disse fechada'
    $v = Parse-Attrs $w
    Ok 'le os 4 atributos no print que falhava' (@('For','Agi','Vit','Ene' | ? { -not $v.ContainsKey($_) }).Count -eq 0) "faltou: $(@('For','Agi','Vit','Ene' | ? { -not $v.ContainsKey($_) }) -join ',')"
    $i.Dispose()
  }
  # VERSAO WEB (game.mudinhox.com.br numa aba do Chrome, 1024x720). Dois pontos que so aparecem aqui:
  #  - o HUD da web NAO encolhe com a janela, ao contrario do cliente desktop: e por isso que o OCR le num
  #    tamanho onde o desktop reprovou (em 958x484 ele nem detectava o painel aberto).
  #  - os pontos sao um BOTAO "Pontos: 244", e o OCR devolveu '%' + 'ritos:' + '244'. Com o padrao antigo
  #    (`^pont`) o bot lia "sem pontos" com 244 na tela - e ponto nao lido nunca e distribuido.
  $i = Fx 'web_status_ABERTO.png'
  if($i){
    $w = Ocr-Status $i
    Ok 'web: reconhece o painel de status' (Status-Open $w) 'Status-Open disse fechada'
    $v = Parse-Attrs $w
    Ok 'web: le os 4 atributos' (@('For','Agi','Vit','Ene' | ? { -not $v.ContainsKey($_) }).Count -eq 0) "faltou: $(@('For','Agi','Vit','Ene' | ? { -not $v.ContainsKey($_) }) -join ',')"
    Ok 'web: le os PONTOS do botao mastigado' ((Get-Points $w) -eq 244) "Get-Points devolveu $(Get-Points $w), esperado 244"
    # O MESMO Read-Map que le o desktop em 1920x1009 tem que ler a aba do Chrome em 1024x720, sem coordenada
    # cravada: ele acha o rotulo pela coordenada do minimapa ("132,125") e pega o nome a esquerda.
    # E importante que este teste rode DEPOIS do fixture desktop: a caixa cacheada la nao serve aqui, entao
    # este caso tambem exercita o auto-conserto (cache invalido -> procura de novo).
    Ok 'web: Read-Map acha o mapa noutro layout' ((Read-Map $i) -match '^lorencia') "leu '$(Read-Map $i)'"
    # LEVEL auto-calibrado. O painel diz "Level: 400" (verdade, tem rotulo); a HUD mostra o mesmo 400 solto.
    # A calibracao tem que pegar a ocorrencia da HUD e DESCARTAR a do painel - se pegar a do painel, o bot le o
    # level so enquanto a janela C estiver aberta, que e quase nunca.
    Ok 'web: le o level pelo rotulo do painel' ((Get-Level-Painel $w) -eq 400) "Get-Level-Painel devolveu '$(Get-Level-Painel $w)', esperado 400"
    $i.Dispose()
  }
  # LEVEL AUTO-CALIBRADO. O painel diz "Level: 400" (verdade, tem rotulo do lado); a HUD mostra o mesmo 400
  # solto, sem rotulo nenhum - e em posicao que nem por fracao transfere entre desktop (0.56 da largura) e web
  # (0.62). Entao a calibracao usa o numero do painel pra achar o da HUD e guarda so o recorte.
  # Este fixture e a HUD da web SEM painel aberto: e o que prova que o OCR enxerga o numero solto la.
  # Os dois layouts tem que calibrar e ler. O DESKTOP e o caso de regressao: o $LevelBox cravado foi removido,
  # entao a leitura de level dele passou a depender inteiramente deste caminho.
  foreach($cal in @(@{ F='web_hud.png';          L=400; Q='web'     },
                    @{ F='status_ABERTO.png';    L=329; Q='desktop' },
                    @{ F='lorencia_modal_mix.png'; L=0;  Q='desktop sem painel' })){
    $i = Fx $cal.F
    if(-not $i){ continue }
    $script:lvlBox = $null
    if($cal.L -gt 0){
      Ok "$($cal.Q): acha o level na HUD" (Calibrar-LevelBox $i $cal.L) "nao achou o $($cal.L) na faixa inferior"
      if($script:lvlBox){ Ok "$($cal.Q): o recorte calibrado devolve $($cal.L)" ((Read-Level $i) -eq $cal.L) "Read-Level devolveu '$(Read-Level $i)'" }
    } else {
      # sem level conhecido pra este print: o que importa e que SEM caixa calibrada o Read-Level devolve $null
      # em vez de inventar numero. Level errado manda o bot resetar na hora errada.
      Ok "$($cal.Q): sem calibracao, Read-Level nao inventa" ($null -eq (Read-Level $i)) "devolveu '$(Read-Level $i)' sem caixa calibrada"
    }
    $script:lvlBox = $null
    $i.Dispose()
  }
  # FAIXA DE MENSAGENS em fracao, nao em pixel. Sem ancora possivel (o que se quer e justamente descobrir o que
  # esta escrito), entao o jeito de nao cravar coordenada e descrever ONDE ELAS FICAM em proporcao. Os dois
  # layouts tem que cair dentro da mesma faixa - e o que estes casos provam.
  # Padrao TOLERANTE de proposito: o OCR mastiga a fonte pequena do desktop ('Rosta ainda 5 Goldon Dra') e sai
  # limpo na web ('Resta ainda 6 Golden Dragon vivo(s) em Devias!'). Casar os dois prova que a faixa em fracao
  # pega a mensagem de verdade nos dois layouts - que e o ponto. Os chamadores ja casam por regex tolerante.
  foreach($msg in @(@{ F='web_hud.png';            P='(?i)r[eo]sta ainda'; Q='web'     },
                    @{ F='lorencia_modal_mix.png'; P='(?i)r[eo]sta ainda'; Q='desktop' })){
    $i = Fx $msg.F
    if(-not $i){ continue }
    $t = Read-Msgs $i
    Ok "$($msg.Q): le a faixa de mensagens" ($t -match $msg.P) "leu '$($t.Substring(0,[Math]::Min(70,$t.Length)))'"
    $i.Dispose()
  }
  $i = Fx 'inventario_FECHADO.png'
  # regressao real: com o inventario FECHADO a grade cai no chao do mapa e leu "8 livres" - o bot acharia que esta cheio e mixaria pra sempre
  if($i){ Ok 'Inv-Open recusa inventario fechado' (-not (Inv-Open $i)) 'achou o Zen onde nao tem inventario'; $i.Dispose() }

  # Word-Color com os tons ESCUROS dos botoes do modal de mix. O limiar antigo (canal > 110) dava 'other' nos dois
  # e nenhuma joia era vista como verde - o mix nunca clicava em nada.
  $bm = New-Object System.Drawing.Bitmap(120,60); $gg = [System.Drawing.Graphics]::FromImage($bm)
  $gg.FillRectangle((New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(45,85,45))), 0, 0, 120, 30)   # botao verde escuro
  $gg.FillRectangle((New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(90,40,40))), 0, 30, 120, 30)  # botao vermelho escuro
  $gg.Dispose()
  function FakeWord($x,$y,$w,$h){ [pscustomobject]@{ BoundingRect = [pscustomobject]@{ X=$x; Y=$y; Width=$w; Height=$h } } }
  Ok 'Word-Color acha verde escuro'    ((Word-Color $bm (FakeWord 10 5 100 20))  -eq 'green') "deu '$(Word-Color $bm (FakeWord 10 5 100 20))'"
  Ok 'Word-Color acha vermelho escuro' ((Word-Color $bm (FakeWord 10 35 100 20)) -eq 'red')   "deu '$(Word-Color $bm (FakeWord 10 35 100 20))'"
  $bm.Dispose()

  $i = Fx 'captcha.png'
  if($i){
    $a = Find-Captcha $i
    Ok 'Find-Captcha acha a ancora' ([bool]$a) 'nao achou a frase "Selecione a mesma imagem"'
    if($a){ Ok 'Solve-Captcha tem certeza' ((Solve-Captcha $i $a -NoClick) -eq $true) 'ficou ambiguo' }
    $i.Dispose()
  }
  # NEGATIVO, e e o que faltava: o dialogo do mix diz "Selecione o metodo de combinacao". Com a ancora casando
  # so a palavra "Selecione", o bot interrompia a MIXAGEM pra resolver um captcha inexistente, comparava pedacos
  # quaisquer da tela (razoes de 0.99 - empate entre coisas que nao sao opcao de captcha) e chamava o usuario.
  # 3 dos 4 "captchas" do log de 15/09 eram isto.
  $i = Fx 'mix_dialogo_metodo.png'
  if($i){
    Ok 'nao confunde o dialogo do mix com captcha' (-not (Find-Captcha $i)) 'achou captcha onde so ha o painel de combinacao'
    $i.Dispose()
  }
  Log $(if($script:falhas){ "TestVisao: $($script:falhas) FALHA(S)" } else { 'TestVisao: tudo OK' })
  exit $(if($script:falhas){ 1 } else { 0 })
}
if($TestStatus -ne ''){   # -TestStatus [print.png]  (sem arquivo: captura a tela agora, com a janela C aberta no jogo)
  # Existe porque "status: nao li Vit" e "Pts=-1" sao os erros mais comuns do log e ate agora so davam pra
  # diagnosticar no olho, abrindo o print. Aqui da pra ver EXATAMENTE o que o OCR devolveu.
  if($TestStatus -eq 'live'){ $img = Capture-Game; if(-not $img){ Log "jogo nao ficou na frente, nada lido"; exit } }
  else { Add-Type -AssemblyName System.Drawing; $img = [System.Drawing.Bitmap]::FromFile((Resolve-Path $TestStatus)) }
  $words = Ocr-Status $img
  Log "TestStatus: janela aberta? $(Status-Open $words)"
  foreach($w in ($words | sort { $_.BoundingRect.Y })){
    if($w.BoundingRect.X -gt 500){ continue }   # o painel fica na esquerda; o resto e dano/chat e so polui
    Log ("  {0,4},{1,4}  '{2}'" -f [int]$w.BoundingRect.X, [int]$w.BoundingRect.Y, $w.Text)
  }
  $v = Parse-Attrs $words
  Log ("TestStatus: Parse-Attrs -> " + ((@('For','Agi','Vit','Ene') | % { "$_=$(if($v.ContainsKey($_)){$v[$_]}else{'FALTOU'})" }) -join ' '))
  Log "TestStatus: Get-Points -> $(Get-Points $words)"
  $img.Dispose(); exit
}
if($TestMix){   # abra o modal de mix NO JOGO antes de rodar
  $img = Capture-Game; if(-not $img){ Log "jogo nao ficou na frente, nada lido"; exit }
  New-Item -ItemType Directory -Force $CaptchaShotDir | Out-Null
  $f = Join-Path $CaptchaShotDir 'mixer.png'; $img.Save($f); Log "print salvo: $f"
  foreach($w in (Screen-Words $img)){
    if($w.Text.Length -lt 3){ continue }
    $col = Word-Color $img $w; $c = Word-Center $w
    $hit = @(); if($w.Text -match $MixNpcWords){ $hit += 'NPC' }; if($w.Text -match $MixMenuWords){ $hit += 'MENU' }
    foreach($j in $MixJewels){ if($w.Text -match $j.Pat){ $hit += $j.Name } }
    if($hit.Count -or $col -ne 'other'){ Log ("  '{0}' ({1},{2}) cor={3} {4}" -f $w.Text,$c.X,$c.Y,$col,($hit -join '/')) }
  }
  $img.Dispose(); exit
}

Show-Ui
if(Heartbeat-Fresco){   # ja tem bot vivo: dois no mesmo jogo brigam pelo teclado e estragam tudo
  Log 'ja existe um bot rodando (heartbeat fresco). Saindo pra nao duplicar.'
  if($script:ui){ $script:ui.Dispose() }; exit
}
Remove-Item $StopFile -ErrorAction SilentlyContinue
Bater-Heartbeat
Log 'iniciando'
try {   # preflight no start: 10s conferindo tudo evita a noite inteira perdida por algo obvio. Nao BLOQUEIA (o spot nem e checado, o bot ainda vai warpar)
  # JANELA MENOR QUE A CALIBRACAO = para na hora, com instrucao. Nao e frescura de preflight: TODA coordenada do
  # bot ainda depende do $ClientEsperado (a grade do inventario, a do captcha). Numa janela menor o
  # Read-Level vai ler em x=1080 de uma tela de 958 e o GetPixel estoura - foi o que matou os 4 slots em 08/09,
  # quando os clientes foram reduzidos pra 958x484 pra caberem os quatro no monitor. O erro que aparecia era
  # "O parametro deve ser positivo e < Width", que nao diz nada sobre o tamanho da janela.
  # Maior que a calibracao nao para: as coordenadas ainda caem dentro, e o $ChatBox ja mede a partir
  # da BASE da area cliente, entao altura extra e tolerada (ja rodou assim em 1920x1061).
  # MINIMIZADA NAO E "JANELA PEQUENA". Janela minimizada devolve area cliente 0x0, e o bot dizia "esta 0x0,
  # menor que a calibracao - ponha em 1920x1009", que e a instrucao errada: nao ha o que redimensionar, e so
  # restaurar. Pior, ele MORRIA por isso - sendo que minimizado e um estado passageiro. Agora espera.
  $h0 = Get-Game
  if([W]::IsIconic($h0)){
    Log "o jogo esta MINIMIZADO (area cliente 0x0). Restaure a janela - eu espero, nao vou fechar."
    Notify "MudinhoX" "O jogo esta minimizado. Restaure a janela que o bot continua sozinho."
    # Bate o heartbeat DIRETO no arquivo, nao via Bater-Heartbeat: aquele acumula TEMPO ATIVO, e esperar voce
    # restaurar a janela nao e o bot trabalhando - entraria no divisor do pontos/h e afundaria a taxa. Mesma
    # razao do Pause-Gate. O heartbeat em si tem que continuar, senao outra instancia acha que este morreu.
    while(-not $script:stop -and [W]::IsIconic((Get-Game))){
      try { (Get-Date).Ticks | Set-Content -Path $HeartbeatFile -Encoding ASCII } catch {}
      Check-Stop; Wait 5
    }
    if(-not $script:stop){ Log "jogo restaurado, seguindo"; Wait 2 }
  }
  $cli = New-Object W+RECT; [W]::GetClientRect((Get-Game),[ref]$cli) | Out-Null
  if(-not $script:stop -and ($cli.R -lt $ClientEsperado.W -or $cli.B -lt $ClientEsperado.H)){
    Log "PARANDO: a area cliente do jogo esta $($cli.R)x$($cli.B), menor que a calibracao $($ClientEsperado.W)x$($ClientEsperado.H)."
    Log "  Todas as coordenadas do bot sao fixas nesse tamanho - numa janela menor ele le fora da tela e quebra."
    Log "  Ponha a janela do jogo em $($ClientEsperado.W)x$($ClientEsperado.H) e suba de novo."
    Notify "MudinhoX" "Janela do jogo em $($cli.R)x$($cli.B); precisa ser $($ClientEsperado.W)x$($ClientEsperado.H). Bot parado."
    # APAGA O HEARTBEAT ANTES DE SAIR. Sem isto o bot bloqueava a si mesmo: ele bate o heartbeat no start, morre
    # aqui sem limpar, e as tentativas seguintes batiam em "ja existe um bot rodando (heartbeat fresco)" pelos
    # $HeartbeatVivoSec (180s) seguintes. Foi o que aconteceu em 14/09: duas tentativas de reabrir recusadas
    # em sequencia depois de uma parada por janela minimizada. Quem para, para limpo - a regra ja valia pro
    # Check-Stop, e este caminho de saida tinha escapado dela.
    Remove-Item $HeartbeatFile -ErrorAction SilentlyContinue
    if($script:logW){ $script:logW.Dispose() }; if($script:ui){ $script:ui.Dispose() }
    exit
  }
  Log "preflight de inicializacao:"
  $pf = Run-Preflight $false
  # So avisa pelas falhas que NAO sao "o char ainda nao esta no spot" - essas o proprio warp resolve em 2s.
  if($script:falhasReais){ Notify "MudinhoX" "$($script:falhasReais) verificacao(oes) falharam no start - veja o log. O bot vai tentar rodar mesmo assim." }
  elseif($pf){ Log "preflight: as $pf falhas sao so de estar fora do spot (o bot vai warpar) - nao te avisei por isso" }
} catch { Log "preflight falhou: $_" }
try { Limpar-Watchdog } catch { Log "watchdog: $_" }   # apaga a Tarefa Agendada da versao antiga: nada pode sobreviver ao fechamento da janela
Load-Estado   # retoma fase/warmup/modo de onde parou (o warmup.flag abaixo ainda tem prioridade)
# Se o $WarmupResets do CONFIG baixou (10 -> 3) e o estado.txt guardou uma contagem maior, o char ja cumpriu a
# cota: sai do warmup na hora, em vez de gastar mais um ciclo de ~220s no Lost Tower so pra descobrir isso.
if($script:phase -eq 'warmup' -and $script:warmupCount -ge $WarmupResets){
  $script:phase = 'normal'; Save-Estado
  Log "warmup ja cumprido ($($script:warmupCount)/$WarmupResets pelo estado.txt) -> indo direto pro spot normal ($WarpCmd)"
}
if($script:modo -eq 'joias'){ Log "retomando em MODO JOIAS: farma em $WarpCmd ate encher, mixa no $MixCmd, repete" }
if(Test-Path $WarmupFile){ Remove-Item $WarmupFile -ErrorAction SilentlyContinue; $script:phase = 'warmup'; $script:warmupCount = 0; Save-Estado; Log "iniciando em modo warmup (pos-MR manual): $WarmupCmd ate $WarmupResets resets" }
Log-Plano   # DEPOIS do Load-Estado e dos ajustes de fase acima: o plano tem que refletir o que o bot vai fazer de verdade, nao o CONFIG cru
while(-not $script:stop){   # envelope: se o cliente cair, o catch espera ele voltar e o ciclo recomeca aqui (antes o script terminava)
try {
while($true){
  Pause-Gate
  Cota-Rolar   # meia-noite: zera a cota do dia e tira o bot do descanso. Aqui em cima porque no descanso quem roda e o Ciclo-Joias, que da `continue`
  if($script:modo -eq 'joias'){ Ciclo-Joias; continue }       # farma ate encher, mixa, repete. Sem reset/darmr.
  if($script:mixNow){ Hold-Focus; try { Tick-Inventory } finally { Release-Focus } }   # botao MIXAR JOIAS: atende ANTES do warp (senao so era visto la dentro do loop de farm, e o bot parecia ignorar o botao)

  $script:restartCycle = $false   # comecando um ciclo novo (botoes de fase ja aplicaram phase/forceMR)
  Hold-Focus; try { $warpOk = Warp-To-Spot; if($warpOk){ Start-Helper; $script:lvlChangedAt = Get-Date; $script:lvlSame = 0; if($script:forceMR){ $script:forceMR = $false; $script:statDue = Get-Date; Log "forcando distribuicao + MR" } } } finally { Release-Focus }
  # Tick-Progresso TAMBEM aqui, e nao so dentro do laco de farm. Era o buraco da rede de seguranca: com o warp
  # falhando o bot nunca ENTRA no laco de farm, entao nada vigiava o resultado - em 12/09 ele reenviou /k37 por
  # 54 min sem que o vigia de "sem progresso" tickasse uma vez. O destravamento especifico ja esta no
  # Warp-To-Spot; isto cobre a classe inteira, inclusive o que ainda nao aconteceu.
  if(-not $warpOk){ Hold-Focus; try { Tick-Progresso } finally { Release-Focus }; Wait 15; continue }

  # upando: le level, checa captcha, manda stats (traz o jogo 1x por iteracao, devolve o foco pra sua janela no fim)
  do {
    Wait (Poll-Interval); $lvl = $null; Bater-Heartbeat
    Hold-Focus
    try {
      $img = Capture-Game
      if($img){
        if(-not (Handle-Captcha $img)){
          # caiu pra tela de login no meio do farm: sem isso o bot mandava /s18 e /resetar no vazio pra sempre.
          # So investiga apos 3 leituras seguidas sem o botao play - loading normal some em 1-2, e assim nao paga OCR da tela toda a toa.
          if((Get-HelperState $img) -eq 'unknown'){ $script:semPlay++ } else { $script:semPlay = 0 }
          if($script:semPlay -ge 3 -and (Login-Btn $img)){
            $img.Dispose(); $script:semPlay = 0
            if(Enter-Game 'caiu durante o farm'){ $script:restartCycle = $true }
            continue
          }
          $lvl = Read-Level $img
          if($null -ne $lvl){
            # No teto do servidor ($LevelMaximo) o level NAO SOBE MAIS, entao o detector de miss infinito
            # dispararia a cada $StallReads leituras pra sempre - ESC + pausa + anda + religa helper de 40 em 40s, com o
            # char farmando normalmente. Foram 16 das 113 ocorrencias do log. O Ciclo-Joias ja tinha a guarda;
            # o loop normal nao (o char chega no teto quando o /resetar demora a pegar).
            if($lvl -ge $LevelMaximo){ $script:lvlPrev = $lvl; $script:lvlChangedAt = Get-Date; $script:lvlSame = 0 }
            elseif(-not (Check-Progress $lvl $img)){ $img.Dispose(); continue }
            # perto do alvo o poll e de 2s: logar todo tick enche o arquivo e atrapalha achar problema. So loga salto real ou queda (reset)
            if($null -eq $script:lvlLogged -or $lvl -lt $script:lvlLogged -or ($lvl - $script:lvlLogged) -ge $LogLevelDelta){ Log "level: $lvl"; $script:lvlLogged = $lvl }
          }
          # CHEGOU NO ALVO = sai JA, sem pagar a rodada de Ticks. O `until` la embaixo so e avaliado depois que
          # tudo isto roda, entao o reset ficava esperando um Read-Status (~3s), um comando de distribuicao
          # (~2.5s) e ate um disfarce do Tick-Human - medido no log: 10s entre o level passar do alvo e o
          # /resetar sair, em TODO reset. Nada do que essas Ticks fazem muda o que vem a seguir, que e resetar:
          # os pontos nao somem, e quem os gasta e a subida do proximo ciclo.
          if($null -eq $lvl -or $lvl -lt $TargetLevel){
            Tick-Stats; Tick-Inventory; Tick-Msgs $img; Tick-Progresso; Tick-Human; Tick-WarmupTeste
          }
        }
        $img.Dispose()
      }
    } finally { Release-Focus }
  } until (($null -ne $lvl -and $lvl -ge $TargetLevel) -or $script:restartCycle)
  # CHEGOU NO ALVO: reseta JA. Distribuir aqui custava 11.1s por reset (medido em 82 resets: `level alvo ->
  # /resetar`), ~3.7 min por master reset, e nao era necessario - os pontos nao somem, so esperam. Quem gasta
  # e o Tick-Stats durante a SUBIDA do proximo ciclo, que e quando o char esta upando e as leituras ja acontecem
  # de qualquer forma. Pedido seu em 11/09: distribuir do level 1 ao alvo, e no alvo so resetar.
  # A guarda de pontos parados FICA: se a ultima leitura ja mostrava mais que $StatMaxLeftover sobrando, aqui e
  # o lugar de gastar antes de gerar mais uns 2000 com o reset. Foi assim que um char empilhou 1.66 MILHAO de
  # pontos em 08/09 - sem esse freio a pilha cresce sem ninguem ver. $script:ptsLeft vem da ultima leitura de
  # status do farm, entao a decisao nao custa uma leitura nova.
  if($script:ptsLeft -gt $StatMaxLeftover){
    Log "stats: $($script:ptsLeft) pontos sobrando (limite $StatMaxLeftover) - gastando antes de resetar"
    for($d = 0; $d -lt 3 -and -not $script:restartCycle; $d++){
      Hold-Focus; try { Distribute-Points } finally { Release-Focus }
      if($script:ptsLeft -le $StatMaxLeftover){ break }
      Log "stats: ainda sobram $($script:ptsLeft) pontos (limite $StatMaxLeftover), segurando o reset e tentando de novo ($($d+1)/3)"
      Wait 3
    }
  }
  # O Close-Popup aqui esta FORA de qualquer bloco de foco (o Release-Focus acima ja devolveu): sem o Hold-Focus,
  # o ESC ia parar na janela de quem estivesse na frente. Agora ele pega o jogo, manda o ESC e devolve.
  if($script:restartCycle){ $script:restartCycle = $false; $pf = Focus-Game; Close-Popup; Restore-Focus $pf; Log "recomecando ciclo (pos-/darmr ou pos-mix, fase $($script:phase))"; continue }   # /darmr acabou de re-logar na cidade: nao reseta, vai direto pro warp da fase

  # reset: espera captcha (resolve) ou level cair
  $lvlEnvio = $lvl   # em que level este /resetar saiu. Se ele for aceito de primeira, o servidor PROVOU que aceita aqui.
  Hold-Focus; try { while(-not (Send-Chat "/resetar")){ Release-Focus; Wait 10; Hold-Focus } } finally { Release-Focus }
  $sent = Get-Date; $resends = 0; $warned = $null; $inicio = Get-Date
  $resetOk = $false
  # 1a conferida em 1s, depois no ritmo de 4s. Medido no MR #15: `/resetar -> reset feito` deu mediana 5s e
  # MINIMO 5s em 19 resets - piso artificial, ninguem estava esperando o servidor, era o Wait 4 mais a leitura.
  # Sao 139s por master reset so pra PERCEBER um reset que ja tinha acontecido. Conferir cedo nao arrisca nada:
  # se o frame ainda estiver velho, cai na volta seguinte exatamente como antes.
  $espera = 1
  do {
    Wait $espera; $espera = 4; $lvl = $null
    Hold-Focus
    try {
      $img = Capture-Game
      if($img){
        if(Handle-Captcha $img){ $sent = Get-Date }
        else {
          $lvl = Read-Level $img
          $mapa = Read-Map $img
          if($mapa -match $CityWords){ $resetOk = $true }   # char foi pra uma cidade = reset aconteceu (confirma na hora, sem depender de ler o level, que demora em Lorencia)
          if($null -ne $lvl -and $lvl -lt $TargetLevel){ $resetOk = $true }
          if(-not $resetOk -and ((Get-Date) - $sent).TotalSeconds -ge $ResetWaitSec){
            $resends++
            Tag-Ciclo "reset"; Log "reset nao aconteceu (level: $(if($null -ne $lvl){$lvl}else{'ilegivel'}), mapa: '$mapa'), reenviando ($resends)"   # loga O QUE ELE VE: sem isso nao da pra saber se e o /resetar ou a LEITURA que falhou
            if($resends -eq 1){
              $msg = Log-GameMsg $img "apos /resetar"; $null = Save-Shot 'reset_travado.png'
              # O servidor diz o motivo em texto: "Voce precisa de estar no level 350 para resetar!".
              # Em vez de deixar o alvo num valor impossivel (e reenviar /resetar ate o char passar de 350 sozinho),
              # aprende o piso da propria mensagem e corrige o alvo - inclusive cancelando um braco invalido do auto-tune.
              if($msg -match $MsgMinResetWords){
                $min = [int]$Matches[1]
                # Teto de sanidade: um OCR ruim que devolvesse 3500 deixaria o alvo num valor que o char nunca
                # alcanca, e ai o bot farmaria pra sempre sem nunca resetar - pior que o problema original.
                if($TargetLevel -lt $min -and $min -le $LevelMaximo){
                  Log "servidor exige level $min pra resetar (alvo estava $TargetLevel): subindo o alvo"
                  $script:TargetLevel = $min; $script:LevelMinReset = $min; Save-Estado
                  if($script:tuneOn){ Log "autotune: alvo abaixo do minimo do servidor, descartando este braco"; $script:tuneResets = $AutoTuneResets - 1 }
                }
              }
            }
            if($resends -eq ($ResetRetries + 1)){ Notify "MudinhoX" "Reset nao aconteceu 3x (level: $(if($null -ne $lvl){$lvl}else{'ilegivel'}), mapa: '$mapa'). Print em captcha\reset_travado.png"; $warned = Get-Date }
            elseif($resends -gt $ResetRetries -and (-not $warned -or ((Get-Date) - $warned).TotalSeconds -ge $RenotifySec)){ Notify "MudinhoX" "Reset ainda nao aconteceu (level: $(if($null -ne $lvl){$lvl}else{'ilegivel'}), mapa: '$mapa')."; $warned = Get-Date }
            if(Send-Chat "/resetar"){ $sent = Get-Date }   # NUNCA para de tentar: antes desistia apos 2 reenvios e so re-avisava, ficando preso por horas
          }
        }
        $img.Dispose()
      }
    } finally { Release-Focus }
    if(((Get-Date) - $inicio).TotalMinutes -ge $ResetStuckMin){   # travado ha muito tempo: reinicia o ciclo (re-warp desbuga morte/teleporte/mapa errado)
      Log "reset travado ha $ResetStuckMin min: reiniciando o ciclo (re-warp) pra tentar desbugar"
      $script:restartCycle = $true
    }
  } until ($resetOk -or $script:restartCycle)
  if($script:restartCycle){ continue }   # botao mudou a fase no meio do reset: recomeca o ciclo (nao conta este reset)
  $script:resets++; $script:resetsSessao++   # resets = do MR atual (zera no /darmr); resetsSessao = so deste processo
  $agora = Get-Date
  if($script:ultimoReset){ $seg = [Math]::Max(0, [int](($agora - $script:ultimoReset).TotalSeconds - $script:pausaSeg)); $tg = ($script:tagsCiclo -join "+"); $script:ciclos = @(@($script:ciclos) + $(if($tg){"${seg}:$tg"}else{"$seg"}) | select -Last $CapCiclosMax) }
  $script:pausaSeg = 0.0   # ciclo novo: zera o cronometro de pausa
  $script:tagsCiclo = @()   # ciclo novo comeca sem etiqueta
  $script:ultimoReset = $agora
  Log "reset feito, recomecando"
  # ACEITO DE PRIMEIRA abaixo do piso que estava gravado = o piso estava errado. Sem isto o aprendizado so sabia
  # SUBIR, e uma recusa unica prendia o char naquele level pra sempre - mesmo depois de a exigencia cair.
  # $resends -eq 0 e a prova: com reenvio o char subiu de level no meio e nao da pra dizer em qual tentativa o
  # servidor cedeu, entao gravar o piso ali seria gravar um numero que ele nunca aceitou.
  if($resends -eq 0 -and $null -ne $lvlEnvio -and $lvlEnvio -lt $script:LevelMinReset){
    Log "servidor ACEITOU reset no level $lvlEnvio (piso gravado era $($script:LevelMinReset)): baixando o piso"
    $script:LevelMinReset = $lvlEnvio
    if($script:TargetLevel -gt $TargetLevelConfig){ $script:TargetLevel = [Math]::Max($TargetLevelConfig, $lvlEnvio) }   # volta pro alvo pedido, que o aprendizado tinha empurrado pra cima
    Save-Estado
  }
  Ajustar-Alvo-Do-Proximo-Ciclo
  Marcar-Ganho-Do-Reset
  Tick-AutoTune
  Save-Estado   # metricas do MR sobrevivem a reinicio do bot (medir um MR leva horas)
  if(($script:resets % $MetricsEvery) -eq 0){ Metrics }
  $null = Wait-Map '' 8   # espera o mapa RENDERIZAR (o jogo ignora teclas durante o teleporte); segue assim que ler, em vez de dormir 8s
  if($script:spotTeste){   # fechou um reset no spot normal dentro do prazo: o warmup era desperdicio
    $seg = [int]((Get-Date) - $script:spotTesteIni).TotalSeconds
    $script:spotTeste = $false
    Log "pos-MR: o spot normal fechou um reset em ${seg}s - PULANDO o warmup (medido: o warmup custa ~14 min, 33% do MR)"
    Save-Estado
  }
  if($script:phase -eq 'warmup'){
    $script:warmupCount++; Log "warmup: reset $($script:warmupCount)/$WarmupResets (Lost Tower)"
    if($script:warmupCount -ge $WarmupResets){ $script:phase = 'normal'; Log "warmup completo ($WarmupResets resets) -> voltando ao spot normal ($WarpCmd)" }
    Save-Estado
  }
  $script:statDue = Get-Date   # distribui os pontos do reset ja no proximo tick (Distribute-Points valida os 4 atributos e cuida do /darmr)
}
} catch {
  if("$_" -match 'nao esta rodando'){   # o cliente caiu: antes o bot MORRIA junto e a noite acabava ali. Agora espera ele voltar
    # MINIMIZADO ou FECHADO sao coisas diferentes, e a mensagem precisa saber qual. Este mesmo erro cobre os
    # dois: "nao achei o processo" e "a janela devolveu area cliente 0x0". Em 15/09 o bot disse "O jogo fechou.
    # Abra o MudinhoX" com o mudx.exe rodando (PID 56812) e so minimizado - instrucao errada pra quem le.
    $minim = $(try { $h = Get-Game; $h -ne [IntPtr]::Zero -and [W]::IsIconic($h) } catch { $false })
    Log "ERRO: $_"
    if($minim){ Notify "MudinhoX" "O jogo esta minimizado. Restaure a janela que o bot continua sozinho." }
    else      { Notify "MudinhoX" "O jogo fechou. Abra o MudinhoX que o bot continua sozinho." }
    $avisou = Get-Date
    while(-not $script:stop){
      Wait 10
      $script:gameH = [IntPtr]::Zero   # forca re-resolver o handle (o processo antigo morreu)
      # "o jogo voltou?" = existe uma janela que o Get-Game aceitaria E ELA DA PRA LER. Janela minimizada
      # devolve handle normalmente, entao so perguntar pelo handle faria o bot "retomar" e estourar no
      # Capture-Raw na volta seguinte, em loop. O que prova que da pra trabalhar e a area cliente.
      # Nao pode ser `Get-Process mudx` cravado: na versao web quem responde isso e o titulo da janela.
      $pronto = $(try {
        $h = Get-Game
        if($h -eq [IntPtr]::Zero -or [W]::IsIconic($h)){ $false }
        else { $c = New-Object W+RECT; [W]::GetClientRect($h,[ref]$c) | Out-Null; $c.R -gt 0 -and $c.B -gt 0 }
      } catch { $false })
      if($pronto){
        Log "jogo voltou: esperando a tela carregar e retomando"; Wait 15
        Hold-Focus; try { $null = Enter-Game 'jogo reaberto' } finally { Release-Focus }   # pode ter voltado na tela de login
        break
      }
      if(((Get-Date) - $avisou).TotalSeconds -ge $RenotifySec){
        Notify "MudinhoX" $(if($(try { $h = Get-Game; $h -ne [IntPtr]::Zero -and [W]::IsIconic($h) } catch { $false })){ "Ainda esperando voce restaurar a janela do jogo." } else { "Ainda esperando o jogo abrir." })
        $avisou = Get-Date
      }
    }
  } else { Log "ERRO: $_"; Notify "MudinhoX RPA parou" "$_"; Wait 30; $script:stopReason = "erro: $_"; $script:stop = $true }   # erro que nao seja o jogo fechado: sai sem stop.flag - quem decide se volta e o watchdog (que agora conta relancamento em vao e desiste)
}
}
Check-Stop
