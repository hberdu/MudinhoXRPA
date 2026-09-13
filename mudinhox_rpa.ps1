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
         powershell -ExecutionPolicy Bypass -File .\mudinhox_rpa.ps1 -TestGold         (com um Golden Tantalos na tela: marca o que o detector achou)
         powershell -ExecutionPolicy Bypass -File .\mudinhox_rpa.ps1 -TestVisao        (regressao das funcoes de leitura contra os prints de fixtures\)
         powershell -ExecutionPolicy Bypass -File .\mudinhox_rpa.ps1 -Preflight        (NO SPOT, em PowerShell ADMIN: valida level/mapa/status/inventario de uma vez)
  Requisito: o jogo precisa estar visivel na hora da leitura. Se outra janela estiver na frente, o bot traz o jogo
  por ~1s, le, e devolve o foco pra janela que voce estava usando (nesse caso le a cada 60s em vez de 10s).
#>
param([switch]$Check, [string]$TestImage, [string]$TestStatus = "", [switch]$TestInv, [switch]$TestMix, [switch]$TestNpc, [switch]$TestGold, [switch]$TestVisao, [switch]$Preflight, [switch]$TestStatMin,
      # MULTIBOX: -Slot 1..N liga o modo N-clientes. 0 (padrao) = um cliente so, tudo exatamente como antes.
      # Um PROCESSO por cliente, nao um processo controlando N janelas: todo o estado do bot (fase, warmupCount,
      # resets, lvlPrev, stCarry, mixLast...) vive em variaveis $script:, e transformar isso em estado-por-janela
      # seria reescrever o arquivo inteiro. Com um processo por slot a logica de um cliente fica intocada.
      [int]$Slot = 0,
      # Qual janela do mudx este slot controla. Vazio = pega a N-esima ordenada por PID (estavel enquanto ninguem
      # fecha cliente). Passe o PID explicito se quiser amarrar slot a personagem.
      [int]$GamePid = 0)

# ---------- CONFIG (coordenadas relativas a area cliente do jogo, 1920x1009) ----------
$TargetLevel   = 305     # level pra resetar. Nunca abaixo de $LevelMinReset (o servidor recusa).
                         # 305 desde 11/09: esta conta tem FENRIR, que baixa a exigencia de reset em 45 levels (350 -> 305).
                         # Era 350 por decisao sua; o A/B de antes tinha apontado 380 (272925 vs 175938 pontos/h), mas os
                         # dois bracos rodaram em sequencia e nao intercalados, entao a comparacao nao era controlada.
                         # O que aquele A/B sugere e que alvo MENOR rende mais - o ciclo encurta mais do que os pontos
                         # por reset caem -, entao 305 deve render acima de 350. Da pra conferir no `pontos/h` do log.
$PlayBtn       = @{ X = 77;   Y = 33 }                     # centro do botao play/pause (canto sup. esquerdo)
$LevelBox      = @{ X = 1080; W = 140; H = 40; YFromBottom = 82 }    # numero do level na barra inferior; Y medido a partir da BASE da area cliente (aguenta resolucao/altura diferente)
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
$GameTitle     = ''       # VERSAO WEB (game.mudinhox.com.br): regex do TITULO da janela, ex '(?i)mudinhox'.
                          # Preenchido = procura por titulo em QUALQUER processo (o jogo vira uma aba do Chrome,
                          # entao o processo e 'chrome' e o nome do processo nao identifica mais nada).
                          # Vazio = comportamento de sempre, por nome de processo.
                          # Rodando na VM, o bot tem que rodar DENTRO dela: do host a VM e uma janela opaca so -
                          # daria pra capturar os pixels, mas nao pra mirar a janela do navegador la dentro,
                          # nem pra fazer multibox, nem pra conferir foco.
$WarpCmd       = '/k37'   # comando de teleporte pro spot de farm normal (troque aqui se mudar de spot). Era /s18 (Stadium)
                          # MULTIBOX: os quatro slots usam ESTE mesmo spot. Houve um $SlotSpots que dava um spot
                          # por slot (/k37, /k36, ...) pra eles nao dividirem mapa; saiu a pedido do usuario, que
                          # sobe os quatro em PARTY - e party quer os chars JUNTOS, no mesmo lugar.
$WarmupCmd     = '/losttower7'   # apos /darmr o personagem volta fraco em Lorencia: farma AQUI (Lost Tower 7) ate juntar os primeiros resets
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
$WarmupMap     = 'lost'      # nome esperado do mapa do /losttower7 (Lost Tower). Evita aceitar mapa errado (ex AIDA) como spot
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
$StatMaxSec    = 90      # teto: mesmo com o level parado (ou ilegivel), rele o status a cada N seg
$StatCongeladoN = 2      # N leituras de status IDENTICAS (4 atributos + pontos) com o level andando entre elas = painel velho na tela -> destrava. Em 01/09 ficou 12 min com "752 pontos" congelados e so o $SemProgressoMin pegou
$StatRoundSec  = 0.25    # espera entre uma rodada de distribuicao e a releitura do status (era 0.5; a releitura ja custa ~1s de captura+OCR, nao precisa de folga por cima)
# Velocidade do teclado/chat. 40/40 e o valor testado que NAO embaralha - nao baixe (ja fez /s18 sair invalido e queimar 4 warps).
$KeyHoldMs     = 40      # tempo segurando cada tecla ao digitar
$KeyGapMs      = 40      # pausa entre uma tecla e a proxima
$KeyClearMs    = 12      # backspaces pra limpar o chat (sao 30 seguidos, e so apagar: aguenta ser rapido)
$ChatOpenMs    = 130     # espera a caixa de chat abrir antes de digitar
$ChatSendMs    = 70      # espera em volta do Enter que envia
$StatPanel     = @{ X = 0; Y = 0; W = 500; H = 760 }   # regiao do painel de status (C), que abre encostado na esquerda. Recortada e AMPLIADA antes do OCR
$StatPanelScale = 2      # 2x: na resolucao nativa o OCR nao le o painel; em 3x tambem falha (imagem grande demais). Medido, nao chutado
$StatMaxValue  = 32767   # atributo cheio (cap real do servidor). /darmr SO funciona com Forca, Agilidade, Vitalidade E Energia TODOS = 32767; abaixo disso o jogo recusa ("precisa 32767 em todos status")
$StatStages    = @(1..([Math]::Floor(($StatMaxValue - 1) / $StatStep)) | % { $_ * $StatStep }) + $StatMaxValue   # 5000,10000,...,30000,32767
$StatusKey     = 0x43    # C = janela de status
$HotkeyHoldMs  = 150     # hotkey (C) segurada mais tempo que tecla de texto
$LoginBtn      = @{ X = 960; YFromBottom = 69 }    # botao pra entrar com o personagem apos /darmr (centro embaixo). Antes disso procura o texto abaixo por OCR.
                                          # Y medido a partir da BASE da area cliente (era Y=940 cravado, calibrado numa altura de 1009). Numa janela de outra altura o
                                          # clique cego escorregava - e logo ali embaixo mora o "CRIAR NOVA CONTA". Todo o resto do layout ja e ancorado no topo ou na base.
$LoginWords    = 'Entrar|Conectar|Iniciar|Jogar|Selecionar|Enter|Start|Login'   # tela de selecao de PERSONAGEM
$LoginServerWords = '(?i)server vip gold'   # tela de selecao de SERVIDOR: regex do botao a clicar (ex 'Server Principal'). Vazio = nao clica, avisa
$LoginDangerWords = '(?i)(criar nova conta|create account|^sair$|delete)'   # se isso esta na tela, NUNCA clicar em coordenada chutada
$ChatBox       = @{ X1 = 870; X2 = 1130; YFromBottomMin = 80; YFromBottomMax = 130 }   # bordas vermelhas da caixa de chat aberta. FAIXA, nao linha fixa: a caixa desloca alguns px conforme o layout
# Miss infinito. A METRICA DO PROPRIO BOT aponta 'stall' como 23-27% de TODO o tempo (113 disparos numa sessao),
# e a maior parte disso e latencia de DETECCAO, nao a recuperacao. Por isso duas condicoes em vez de um relogio so:
$StallReads    = 3       # N LEITURAS seguidas com o level identico. E o sinal forte, e imune a OCR: uma leitura que falhou nao entra na conta (antes ela empurrava o relogio como se o level estivesse parado)
$StallMinSec   = 15      # ...e pelo menos N seg. Piso de seguranca pra logo apos o reset, quando o char esta fraco e demora mesmo pra subir um level. Era 40 fixo (antes 75): 40s x 113 disparos = ~75 min so esperando pra perceber
$CityWords     = 'lorencia|noria|devias|elbeland|lorenmarket|karutan|elveland'   # mapas-cidade onde NAO se farma (personagem cai aqui apos reset). Qualquer outro mapa = spot de farm (ex Stadium do /s18)
# teleporte confirmado quando o mapa e um spot de farm (nao-cidade). $farmMap guarda o ultimo spot.
$MapLabel      = @{ X = 1690; Y = 68; W = 230; H = 30 }   # rotulo do minimapa
$WarpTries     = 4       # reenvia o comando de warp ate N vezes se o mapa nao mudar, depois avisa e segue
$PlayTries     = 3       # clica no play ate N vezes; se nao ligar, para de clicar (nao insiste cego)
$HumanMinSec   = 120; $HumanMaxSec = 420   # a cada X seg (aleatorio) faz algo "humano": anda um pouco, abre/fecha janela, mexe o mouse
# Modos de teste escrevem em OUTRO arquivo. Analisar o rpa.log e como todo bug serio deste projeto foi achado,
# e cada -TestVisao despejava ~30 linhas de "OK ..." no meio do log do bot, quebrando as contagens.
# MULTIBOX: com -Slot N cada instancia tem os SEUS arquivos (rpa2.log, estado2.txt, ...). Sem sufixo os quatro
# processos escreveriam o mesmo log e, pior, o mesmo estado.txt - um sobrescrevendo a fase/warmup do outro.
# Slot 0 (padrao) fica com os nomes de sempre, entao um cliente so nao muda nada.
$Sfx           = if($Slot -gt 0){ "$Slot" } else { '' }
$LogFile       = Join-Path $PSScriptRoot $(if($Check -or $TestImage -or $TestStatus -or $TestInv -or $TestMix -or $TestNpc -or $TestGold -or $TestVisao -or $TestStatMin){ 'testes.log' } else { "rpa$Sfx.log" })
$StopFile      = Join-Path $PSScriptRoot "stop$Sfx.flag"
$StopAllFile   = Join-Path $PSScriptRoot 'stop.flag'   # stop.flag sem numero para TODOS os slots de uma vez
$HeartbeatFile = Join-Path $PSScriptRoot "heartbeat$Sfx.txt"   # o bot bate aqui a cada volta; serve pra nao subir dois bots no mesmo cliente
$AtivoGapMax   = 120     # buraco maior que N seg entre voltas = o bot esteve PARADO; nao conta como tempo ativo nas metricas
$HeartbeatVivoSec = 180  # heartbeat mais novo que isso = tem bot vivo (impede duas instancias no mesmo jogo)
$SemProgressoMax = 3     # apos N ciclos seguidos sem progresso, o bot REINICIA A SI MESMO (ja elevado: nao pede UAC de novo)
$AutoRestart   = $true   # $false = nunca relanca a si mesmo; sem progresso $SemProgressoMax vezes ele so PARA. Unico caminho que ainda cria processo sozinho - e so com o bot rodando (fechar a janela ja o desliga antes)
$WatchdogTask  = 'MudinhoX RPA Watchdog'   # Tarefa Agendada do watchdog ANTIGO. Ele foi removido (nao queremos nada rodando depois que voce fecha); isto so serve pra APAGAR a tarefa que ficou instalada em quem ja rodou a versao velha
$EstadoFile    = Join-Path $PSScriptRoot "estado$Sfx.txt"   # fase + contagem de warmup, pra sobreviver a reinicio do bot
$LogMaxMB      = 5       # rpa.log maior que isso no start vira .bak (a pasta sincroniza no OneDrive)
$LogKeepBaks   = 5       # quantos .bak manter
$WarmupFile    = Join-Path $PSScriptRoot "warmup$Sfx.flag"   # se existir no start, o bot comeca em modo warmup (/losttower7) — use apos dar MR manualmente
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
$CapConfidence = 0.65                         # melhor precisa ser < N% do segundo, senao nao chuta. Era 0.5, e ESSE era o gargalo do MR:
                                              # captcha nao resolvido TRAVA o jogo (o char nao farma, o /resetar nao pega), e o bot ficava
                                              # relendo a mesma imagem estatica a cada 5s pra sempre. No MR #30 foram 12 captchas distintos,
                                              # 192 linhas de "ambiguo" e 4 travados - o MR levou 4.59h contra os 0.71h do MR #15.
                                              # Razoes medidas (melhor/segundo): 0.132 0.199 0.218 0.431 0.487 0.493 passavam;
                                              # 0.503 0.504 0.514 0.515 eram RECUSADOS - e o de 0.515 foi aberto na mao: a resposta estava CERTA.
                                              # Lixo de verdade (cursor tapando a opcao certa, 04/09) deu 0.98, bem longe daqui.
                                              # Errar nao e barato mas e limitado: o bot confere a borda vermelha depois de clicar e PAUSA
                                              # apos $CapMaxTries erros. Nao clicar custou ~1h por captcha travado.
$CaptchaShotDir = Join-Path $PSScriptRoot "captcha$Sfx"   # print salvo aqui a cada captcha
$FixtureDir    = Join-Path $PSScriptRoot 'fixtures'   # prints guardados pro -TestVisao (regressao das funcoes de leitura de tela)
# ---------- MULTIBOX: o que o -Slot muda no CONFIG ----------
if($Slot -gt 0){
  # O spot e o $WarpCmd, igual pros quatro: eles sobem em PARTY, entao tem que ficar no mesmo lugar.
  # $NoFocusRead = $true: LER nao pede foco. Chegou a ficar $false aqui (assumindo janelas empilhadas), e MEDIDO
  # em 08/09 isso nao cabia: com toda leitura passando pelo primeiro plano, um bot sozinho precisava de 40-60%
  # do foco do sistema - dois ja saturavam, e os quatro se atropelaram (slot 1 passou 81s sem uma leitura e
  # disparou miss infinito achando que estava travado).
  # O que faltava era separar "preciso VER" de "preciso DIGITAR". Ver e Z-order: o Ver-Janela sobe a janela do
  # slot com SWP_NOACTIVATE, custa ms e nao tira o teclado de onde voce esta. Digitar e que exige primeiro plano
  # de verdade (medido: PostMessage e AttachThreadInput+SetFocus nao funcionam neste cliente, ver
  # test_entrada_sem_foco.ps1). Com isso a fatia de foco por bot cai pra 10-15% e os quatro cabem.
  $NoFocusRead = $true
  # O $PollBgSec (60s) e pro caso "sua janela na frente, leio devagar pra nao te atrapalhar". Aqui a leitura nao
  # depende mais de foco, entao esse freio nao faz sentido - e 60s deixariam o level passar de 350 pra 400.
  $PollBgSec = $PollSec
}
# Mensagens do jogo (faixa acima da caixa de chat). O servidor responde tudo por texto e o bot ignorava:
# "Voce adicionou N pontos", "Bem-vindo(a) a Lorencia", "Resta ainda N Golden Tantalo vivo(s)".
$MsgBox        = @{ X = 760; W = 400; Y1FromBottom = 250; Y2FromBottom = 135 }
$MsgCheckSec   = 20      # le as mensagens a cada N seg (recorte pequeno, usa a captura que ja existe)
$MsgGoldWords  = '(?i)(golden tantalo|drago.?es dourados|invas.o de drag)'   # evento -> vai cacar sozinho
$MsgInvWords   = '(?i)(invent.rio.{0,12}cheio|espa.o insuficiente|inventory full)'   # inventario cheio -> vai mixar
$ClientEsperado = @{ W = 1920; H = 1009 }   # resolucao pra qual as coordenadas fixas foram calibradas; muda isso se recalibrar noutra
$SemProgressoMin = 12    # sem ganhar UM ponto por N min = travou em algo que a gente ainda nao previu -> avisa e reinicia o ciclo
$LogLevelDelta = 40      # so loga o level quando ele salta N (ou cai = reset). Com poll de 2s, logar todo tick so enche o arquivo
$UiLogMaxChars = 60000   # teto do log da janelinha (o TextBox crescia sem limite rodando dias seguidos)
$AutoTune      = $false  # A/B do alvo DESLIGADO: o alvo agora e escolha sua ($TargetLevel), nao do experimento
$AutoTuneAlvos = 350, 380   # alvos a testar. NAO usar abaixo de $LevelMinReset: o servidor recusa e o /resetar so vira reenvio ate o char passar do minimo sozinho
$LevelMaximo   = 400     # teto de level do servidor ("voce esta no nivel maximo"). No modo joias o char fica parado nele, entao o detector de miss infinito nao pode usar o level la
$LevelMinReset = 305     # level minimo pra resetar. Era 350, confirmado pela mensagem do servidor ("Voce precisa de estar
                         # no level 350 para resetar!"); com FENRIR a conta reseta 45 levels antes, entao 305.
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
$MixNpcPos     = @{ X = 805; Y = 285 }   # onde o Lahap fica (area cliente), medido nos prints do usuario. Hover-Npc confirma pelo nome antes de clicar; se errar, ajuste com -TestNpc
$MixNpcSweep   = 0, -45, 45, -90, 90   # se o nome nao aparecer na posicao exata, tenta esses deslocamentos (X e Y) em volta
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
$InvMenuBtn    = @{ X = 1888; Y = 23 }   # botao de 3 barras (menu) no canto superior direito, area cliente
$InvMenuClickDy = -45    # no menu, o item e um ICONE com o rotulo EMBAIXO: o OCR acha o texto, mas o clicavel esta ACIMA dele
$InvMenuWords  = '(?i)^invent'   # item do menu que abre o inventario
$InvMaxFalhas  = 3       # apos N falhas seguidas de abrir o inventario, desiste (nao fica apertando tecla desconhecida no personagem)
# Evento dos Dragoes Dourados: botao -> /lorencia -> procura os Golden Dragon (mobs DOURADOS) pela tela, anda ate eles e mata.
# O chat anuncia dois bichos diferentes: "Golden Dragon vivo(s) em Lorencia" e "Golden Tantalo vivo(s) em Tarkan". O alvo aqui e o DRAGAO, em Lorencia.
$GoldCmd       = '/lorencia'
$GoldMap       = 'lore'   # nome esperado do mapa (4 letras). Lorencia e CIDADE: ver $GoldHelper abaixo
$GoldArea      = @{ X1 = 70; Y1 = 100; X2FromRight = 70; Y2FromBottom = 150 }   # area util da tela (fora do HUD, minimapa e chat)
# Calibrado pelo print do Golden Derkon em Lorencia (01/09). O bicho e laranja-ouro MUITO saturado: R alto, G medio, B quase zero.
# O filtro antigo (GMin=140, RmG=75) rejeitava justo as partes mais saturadas do dragao e aceitava areia clara - dai casar com o chao de Tarkan.
# BMax baixo e o que separa dourado de areia/pedra/grama: areia de Tarkan e pedra cinza tem azul alto, o dragao nao.
$GoldPix       = @{ RMin = 200; GMin = 90; BMax = 90; RmB = 110; RmG = 145 }   # RMin 200: o dragao e ouro BRILHANTE. Com 180 passava ouro fosco - inclusive DarkGoldenrod(184,134,11), a cor de um botao da propria UI
$GoldCell      = 26       # agrega os pixels dourados em blocos de N px (o mob e um borrao, nao um pixel)
$GoldBlobMin   = 250     # de 676 px do bloco (26x26), quantos precisam ser dourados. 30 era 4% do bloco - permissivo demais. O dragao e enorme e enche o bloco; brilho solto do personagem nao
$GoldSelfR     = 300     # raio ignorado em volta do centro. As ASAS FLAMEJANTES do personagem (255,131,15) e o icone VIP dourado sao tao laranja quanto o dragao - cor nao separa, so distancia. O dragao tem ~700px, entao sobra blob de sobra fora do raio
$GoldHelper    = $false  # ligar o MU Helper na caca? Em CIDADE (Lorencia) nao da: clicar no play abre "precisa estar fora da cidade". Sem helper, o clique no mob e o ataque
$GoldStepSec   = 2.0      # espera depois de mandar o personagem pro bloco dourado
$GoldRepetMax  = 4       # mesma coordenada N vezes na caca = cenario, nao mob: para e avisa (no log de 31/08 foram 21 de 26 deteccoes no mesmo x)
$GoldMaxSeguidas = 10    # alvo achado em N varreduras SEGUIDAS = cenario dourado, nao mob. Mob e raro e some entre varreduras
$GoldRoamSec   = 4.0      # sem nada dourado na tela: anda pra um lado e procura de novo
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
using System; using System.Runtime.InteropServices;
public class W {
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);   // multibox: apagar a janelinha DOS OUTROS slots da captura
  // multibox: SUBIR a janela na pilha SEM roubar o teclado (SWP_NOACTIVATE). E o que separa "preciso ver" de
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
  public static int[] BestGold(Bitmap b, int x1, int y1, int x2, int y2, int cell,
                               int rMin, int gMin, int bMax, int rmB, int rmG,
                               int cx, int cy, int selfR, int minCount){
    var bd = b.LockBits(new Rectangle(0,0,b.Width,b.Height), ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
    int stride = bd.Stride;
    byte[] d = new byte[stride*b.Height]; Marshal.Copy(bd.Scan0, d, 0, d.Length); b.UnlockBits(bd);
    int cols = (x2-x1)/cell + 1, rows = (y2-y1)/cell + 1;
    int[] acc = new int[cols*rows];
    int r2 = selfR*selfR;
    for (int y = y1; y < y2; y++) for (int x = x1; x < x2; x++) {
      int i = y*stride + x*3;
      int bb = d[i], gg = d[i+1], rr = d[i+2];
      if (rr < rMin || gg < gMin || bb > bMax) continue;   // dourado = R e G altos, B baixo
      if (rr-bb < rmB || rr-gg > rmG) continue;            // R-B grande (chao marrom nao passa) e R-G pequeno (fogo/laranja nao passa)
      int dx = x-cx, dy = y-cy; if (dx*dx + dy*dy < r2) continue;
      acc[((y-y1)/cell)*cols + (x-x1)/cell]++;
    }
    int best = -1, bi = 0;
    for (int i = 0; i < acc.Length; i++) if (acc[i] > best) { best = acc[i]; bi = i; }
    if (best < minCount) return new int[]{0,0,best};
    return new int[]{ x1 + (bi%cols)*cell + cell/2, y1 + (bi/cols)*cell + cell/2, best };
  }
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
    $script:barra.Value = [int]($pct * $script:barra.Maximum)
    # Texto encurtado junto com a janela: a versao longa nao cabia nos 284px e truncava justo no numero do fim.
    $script:contador.Text = ("{0} resets | {1} MR  -  MR {2:0.0}% (faltam {3})" -f `
      $script:resetsSessao, $script:mrsSessao, ($pct * 100), $(if($script:ptsNeeded -ge 0){ $script:ptsNeeded } else { '?' }))
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
  # MULTIBOX: um stop.flag SEM numero derruba os quatro de uma vez. Com quatro janelinhas espalhadas, fechar uma
  # por uma no meio de um /darmr e como o estado do char ficou inconsistente em 08/09.
  if(-not $script:stop -and $Slot -gt 0 -and (Test-Path $StopAllFile)){ $script:stop = $true; $script:stopReason = 'stop.flag geral' }
  if(-not $script:stop){ return }
  Log "parado ($script:stopReason)"
  Input-Unlock   # morrer com a trava na mao faria os outros slots esperarem os 120s do teto
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
  # MULTIBOX: as janelinhas em CASCATA, todas dentro do canto inferior esquerdo. Nao lado a lado: a 3a e a 4a
  # cairiam em cima do $MsgBox (x 760+), do $ChatBox (x 870+) e do $LevelBox (x 1080+). Mascarar a janela dos
  # outros slots (ver Outras-Janelinhas) impede LER LIXO, mas ler PRETO tambem nao serve - o Read-Level ia
  # falhar do mesmo jeito. Entao elas ficam onde nao ha nada pra ler.
  # Passo de 28px: da pra ver as 4 barras de titulo (e saber qual e qual) sem sair da area segura. A 4a termina
  # em x=396 e sobe ate 572px da base - longe do captcha (que comeca em x~600) e do play (topo esquerdo).
  $off = ($Slot - 1) * 28
  New-Object System.Drawing.Point(($wa.X + 10 + $off), ($wa.Y + $wa.Height - $alturaJanela - 10 - $off))
}
function Show-Ui {
  $f = New-Object System.Windows.Forms.Form
  # Janelinha COMPACTA (302x239, era 400x380 - 53% menos area). Nao e so estetica: o Capture-Raw pinta a area
  # dela de PRETO em toda captura pra ela nao sujar o OCR, entao janela menor = menos tela do jogo cega, e o
  # Fugir-Da-Area precisa move-la com menos frequencia.
  # Grade de 3 colunas de 92px (6 + 92+4 + 92+4 + 92 + 6 = 296 de area cliente), botoes de 22-24px, fonte 7.5.
  # Com quatro janelinhas iguais na tela nao daria pra saber qual e qual: o titulo carrega slot e spot.
  $f.Text = $(if($Slot -gt 0){ "MudinhoX RPA - slot $Slot ($WarpCmd)" } else { 'MudinhoX RPA' })
  $f.Width = 302; $f.Height = 239; $f.TopMost = $true; $f.FormBorderStyle = 'FixedToolWindow'
  # AutoScaleMode 'None' ANTES da fonte: o padrao e 'Font', que reescala os controles filhos a partir da fonte do
  # formulario. Como TODA a grade abaixo esta em pixel fixo (e o resto do bot tambem trabalha em pixel: $PlayBtn,
  # $LevelBox, $MixNpcPos...), escala automatica so teria como estragar. 'None' deixa o layout deterministico.
  $f.AutoScaleMode = 'None'
  $f.Font = New-Object System.Drawing.Font('Segoe UI', 7.5)
  $f.StartPosition = 'Manual'; $f.Location = Canto-Da-Tela-Do-Jogo $f.Height
  # O rotulo de status saiu: ele mostrava a ULTIMA linha de log, que a caixa de log logo abaixo ja mostra
  # inteira - duas coisas dizendo o mesmo, e a versao dele truncava no meio da frase.
  $script:btnPause = New-Object System.Windows.Forms.Button; $script:btnPause.SetBounds(6,4,92,24);   $script:btnPause.Text = 'PAUSAR'; $script:btnPause.BackColor = 'Goldenrod'
  $btn = New-Object System.Windows.Forms.Button;             $btn.SetBounds(102,4,92,24);             $btn.Text = 'PARAR'; $btn.BackColor = 'IndianRed'
  $script:btnMR     = New-Object System.Windows.Forms.Button; $script:btnMR.SetBounds(198,4,92,24);    $script:btnMR.Text = 'TUDO + MR'; $script:btnMR.BackColor = 'MediumPurple'
  $script:btnWarmup = New-Object System.Windows.Forms.Button; $script:btnWarmup.SetBounds(6,32,92,22);   $script:btnWarmup.Text = "Warmup ($WarmupResets)"; $script:btnWarmup.BackColor = 'SteelBlue'
  $script:btnNormal = New-Object System.Windows.Forms.Button; $script:btnNormal.SetBounds(102,32,92,22); $script:btnNormal.Text = "Normal $WarpCmd"; $script:btnNormal.BackColor = 'MediumSeaGreen'
  $script:btnMixJa  = New-Object System.Windows.Forms.Button; $script:btnMixJa.SetBounds(198,32,92,22);  $script:btnMixJa.Text = 'MIXAR JA'; $script:btnMixJa.BackColor = 'SteelBlue'
  # Os dois de MODO ficam mais largos: sao os unicos que mudam de texto e de cor sozinhos (ver Sync-BotoesModo)
  $script:btnMix  = New-Object System.Windows.Forms.Button; $script:btnMix.SetBounds(6,58,140,22);    $script:btnMix.BackColor = 'DarkCyan'
  $script:btnGold = New-Object System.Windows.Forms.Button; $script:btnGold.SetBounds(150,58,140,22); $script:btnGold.BackColor = 'Teal'   # NAO usar tom dourado: o -TestGold roda em processo separado (nao mascara a UI) e detectava o proprio botao como dragao
  # Barra = caminho ate o proximo /darmr (os 4 atributos do zero ao cap), NAO "quantos resets faltam": reset e so
  # o meio de juntar pontos, e quantos cabem num MR muda com o alvo, com o spot e com a fase. Pontos e o que conta.
  $script:barra = New-Object System.Windows.Forms.ProgressBar
  $script:barra.SetBounds(6,84,284,12); $script:barra.Minimum = 0; $script:barra.Maximum = 1000   # milesimos: com 100 passos pra 131068 pontos a barra parecia travada
  $script:contador = New-Object System.Windows.Forms.Label; $script:contador.SetBounds(6,99,284,14); $script:contador.Text = 'sessao: 0 resets | 0 MR'
  $script:logBox = New-Object System.Windows.Forms.TextBox; $script:logBox.SetBounds(6,116,284,86); $script:logBox.Multiline = $true; $script:logBox.ReadOnly = $true; $script:logBox.ScrollBars = 'Vertical'
  $script:btnPause.Add_Click({ $script:paused = -not $script:paused; $script:btnPause.Text = $(if($script:paused){ 'RETOMAR' } else { 'PAUSAR' }); $script:btnPause.BackColor = $(if($script:paused){ 'ForestGreen' } else { 'Goldenrod' }); Log $(if($script:paused){ 'PAUSADO pelo usuario (mixe as joias; clique RETOMAR pra voltar)' } else { 'retomado pelo usuario' }) })
  $btn.Add_Click({ $script:stopReason = 'usuario'; $script:stop = $true })
  $script:btnWarmup.Add_Click({ $script:phase = 'warmup'; $script:warmupCount = 0; $script:forceMR = $false; $script:restartCycle = $true; $script:paused = $false; $script:btnPause.Text = 'PAUSAR'; $script:btnPause.BackColor = 'Goldenrod'; Save-Estado; Log "[BOTAO] modo WARMUP: /losttower7 ate $WarmupResets resets" })
  # "Normal" durante o descanso da cota fura a cota DE PROPOSITO, mas so por um MR: com o $mrsDia ja no limite,
  # o proximo master reset re-arma o descanso sozinho. Override explicito seu, que se desfaz sozinho.
  $script:btnNormal.Add_Click({ $script:modo = 'reset'; $script:cotaJoias = $false; Sync-BotoesModo; $script:phase = 'normal'; $script:forceMR = $false; $script:restartCycle = $true; $script:paused = $false; $script:btnPause.Text = 'PAUSAR'; $script:btnPause.BackColor = 'Goldenrod'; Save-Estado; Log "[BOTAO] modo NORMAL: $WarpCmd ate os atributos encherem" })
  $script:btnMR.Add_Click({ $script:forceMR = $true; $script:restartCycle = $true; $script:paused = $false; $script:btnPause.Text = 'PAUSAR'; $script:btnPause.BackColor = 'Goldenrod'; Log "[BOTAO] ATRIBUIR TUDO + MR" })
  # Os botoes de MODO LIGAM o modo, nao alternam. Alternar custou caro em 04/09: dois cliques (o bot estava
  # ocupado num /resetar e o primeiro clique nao pareceu fazer nada, porque a UI so anda no DoEvents do Log)
  # ligaram e desligaram o modo joias em 6 segundos - 03:14:54 "MODO JOIAS", 03:15:00 "modo JOIAS desligado" -
  # e o bot emendou um /darmr (MASTER RESET #13) em vez de ir mixar. Quem sai do modo e o botao "Normal $WarpCmd".
  $script:btnMix.Add_Click({
    $script:modo = 'joias'; $script:cotaJoias = $false   # ligado por VOCE, nao pela cota: virar o dia nao pode te tirar dele
    $script:restartCycle = $true; $script:paused = $false; $script:btnPause.Text = 'PAUSAR'; $script:btnPause.BackColor = 'Goldenrod'
    Sync-BotoesModo
    Save-Estado
    Log "[BOTAO] MODO JOIAS: farma em $WarpCmd ate encher, mixa no $MixCmd, repete. Sem reset e sem /darmr. (pra sair: Normal $WarpCmd)"
  })
  $script:btnGold.Add_Click({
    $script:modo = 'dragoes'; $script:cotaJoias = $false   # botao seu manda mais que a cota; ela re-arma no proximo master reset
    $script:restartCycle = $true; $script:paused = $false; $script:btnPause.Text = 'PAUSAR'; $script:btnPause.BackColor = 'Goldenrod'
    Sync-BotoesModo
    Save-Estado
    Log "[BOTAO] MODO DRAGOES: so caca em $GoldCmd, sem reset/darmr/inventario. (pra sair: Normal $WarpCmd)"
  })
  # Quando o botao de mix virou alternador de MODO, ficou sem jeito de mandar mixar AGORA. Este devolve isso:
  # com o inventario cheio na sua frente, nao faz sentido esperar o teto de tempo.
  $script:btnMixJa.Add_Click({
    $script:mixNow = $true; $script:paused = $false; $script:btnPause.Text = 'PAUSAR'; $script:btnPause.BackColor = 'Goldenrod'
    if($script:modo -ne 'joias'){ $script:restartCycle = $true }   # fora do modo joias, corta o ciclo atual pra ir mixar
    Log "[BOTAO] MIXAR AGORA: indo pro $MixCmd no proximo tick"
  })
  $f.Add_FormClosing({ $script:stopReason = 'janela fechada'; $script:stop = $true })
  $f.Controls.AddRange(@($script:btnPause,$btn,$script:btnWarmup,$script:btnNormal,$script:btnMR,$script:btnMix,$script:btnGold,$script:btnMixJa,$script:barra,$script:contador,$script:logBox)); $f.Show(); $script:ui = $f
  Sync-BotoesModo   # texto/cor iniciais dos dois botoes de modo saem daqui tambem - nao ha copia deles no SetBounds
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
function Get-Game {   # handle da janela do jogo, EM CACHE: Get-Process enumera todos os processos do Windows e isto e chamado ~6x por comando
  if($script:gameH -ne [IntPtr]::Zero -and [W]::IsWindow($script:gameH)){ return $script:gameH }
  # MULTIBOX: cada slot manda numa janela. Ordena por Id porque a ordem do Get-Process nao e estavel entre
  # chamadas - sem ordenar, o slot 2 poderia trocar de cliente no meio da noite e misturar dois personagens.
  # VERSAO WEB: o jogo roda numa aba do navegador, entao o processo e 'chrome'/'msedge' e quem identifica e o
  # TITULO da janela. Com $GameTitle preenchido a busca passa a ser por titulo, em qualquer processo.
  $todas = if($GameTitle){
      @(Get-Process -ErrorAction SilentlyContinue | ? { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -match $GameTitle } | sort Id)
    } else {
      @(Get-Process $GameProc -ErrorAction SilentlyContinue | ? { $_.MainWindowHandle -ne 0 } | sort Id)
    }
  if(-not $todas.Count){ throw $(if($GameTitle){ "nenhuma janela com titulo casando '$GameTitle' (o jogo web esta aberto?)" } else { "MudinhoX ($GameProc.exe) nao esta rodando" }) }
  $p = if($GamePid -gt 0){ $todas | ? { $_.Id -eq $GamePid } | select -First 1 }
       elseif($Slot -gt 0){ $todas | select -Skip ($Slot - 1) -First 1 }
       else{ $todas | select -First 1 }
  if(-not $p){ throw $(if($GamePid -gt 0){ "MudinhoX com PID $GamePid nao esta rodando" } else { "slot $Slot pediu a ${Slot}a janela do mudx, mas so ha $($todas.Count)" }) }
  $script:gameH = $p.MainWindowHandle; $script:gameH
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
# ---------- MULTIBOX: trava global de ENTRADA ----------
# keybd_event e mouse_event sao GLOBAIS: vao pra janela que estiver em primeiro plano, seja qual for. Com quatro
# bots rodando, dois trazendo janelas pra frente ao mesmo tempo significa o /resetar de um caindo no cliente do
# outro. Esta trava faz o revezamento: quem vai mexer no jogo pega o mutex, faz o que tem que fazer, solta.
# E um mutex do SISTEMA (Global\), nao um lock em processo - os slots sao processos separados.
$script:mtx = $null
if($Slot -gt 0){ $script:mtx = New-Object System.Threading.Mutex($false, 'Global\MudinhoX-Input') }
$script:lockHeld = $false
function Input-Lock {
  # IDEMPOTENTE de proposito. O Focus-Game e chamado solto em varios lugares (Read-Status reafirma o foco a cada
  # tecla, por exemplo) sem um Restore-Focus casado. Um mutex conta reentradas, entao "pegar" duas vezes e soltar
  # uma vazaria a trava e travaria os outros tres bots pra sempre. Com a flag, N chamadas = uma aquisicao so.
  if(-not $script:mtx -or $script:lockHeld){ return }
  try { $null = $script:mtx.WaitOne(120000) }   # teto: bot morto com a trava na mao nao pode parar a fila pra sempre
  catch [System.Threading.AbandonedMutexException] { }   # dono anterior morreu sem soltar; o mutex e nosso agora
  $script:lockHeld = $true
}
function Input-Unlock {
  if(-not $script:lockHeld){ return }
  $script:lockHeld = $false
  try { $script:mtx.ReleaseMutex() } catch {}
}
function Focus-Game {
  Input-Lock   # so mexe no primeiro plano com a vez na mao
  $h = Get-Game
  if($script:focusHeld){   # dentro de um bloco: nao mexe no prev nem devolve; so garante o jogo na frente
    $script:gameFg = ([W]::GetForegroundWindow() -eq $h); if(-not $script:gameFg){ Set-Foreground $h; $script:gameFg = ([W]::GetForegroundWindow() -eq $h) }; return $script:focusPrev
  }
  $prev = [W]::GetForegroundWindow(); $script:gameWasFg = ($prev -eq $h) -or (Is-OwnUi $prev); Set-Foreground $h; $script:gameFg = ([W]::GetForegroundWindow() -eq $h); $prev
}
function Restore-Focus($prev){   # dentro de bloco nao devolve; senao devolve pra janela anterior (nao a do bot)
  if($script:focusHeld){ return }
  if($prev -and $prev -ne (Get-Game) -and -not (Is-OwnUi $prev)){ Set-Foreground $prev }
  Input-Unlock   # fora de bloco, quem chamou Focus-Game solto devolve a vez aqui
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
# ---------- MULTIBOX: ver a janela sem roubar o teclado ----------
function Ver-Janela {   # sobe a janela do slot na pilha, SEM ativar. Barato (ms) e nao tira o foco de onde voce esta.
  # Com 2 clientes empilhados por monitor, so o de cima aparece - e a leitura sai de CopyFromScreen, que pega o
  # que esta NA TELA. Trazer pra ver com SetForegroundWindow custaria o foco do sistema inteiro e ~2s; aqui e so
  # Z-order. E a diferenca entre "cada bot precisa de 40-60% do primeiro plano" (nao cabe) e "10-15%" (cabe).
  if($Slot -le 0){ return }
  # HWND_TOP=0, SWP_NOSIZE=1 | SWP_NOMOVE=2 | SWP_NOACTIVATE=0x10 = 0x13
  [W]::SetWindowPos((Get-Game), [IntPtr]::Zero, 0,0,0,0, 0x13) | Out-Null
  Start-Sleep -Milliseconds 60   # o compositor precisa de um frame pra desenhar por cima do irmao do par
}
function Janela-Na-Frente {   # os pixels da area cliente sao MESMO desta janela?
  # Sem isto, dois slots empilhados no MESMO ponto da tela leriam um o jogo do outro - e nada no log denunciaria:
  # o mapa e o mesmo, o level e parecido, e o bot distribuiria os pontos do char errado.
  if($Slot -le 0){ return $true }
  try {
    $h = Get-Game; $c = New-Object W+RECT; [W]::GetClientRect($h,[ref]$c) | Out-Null
    $o = Client-Origin; $p = New-Object W+POINT
    $p.X = $o.X + [int]($c.R/2); $p.Y = $o.Y + [int]($c.B/2)
    $w = [W]::WindowFromPoint($p)
    if($w -eq [IntPtr]::Zero){ return $false }
    ($w -eq $h) -or ([W]::GetAncestor($w, 2) -eq $h)   # GA_ROOT=2: o ponto pode cair num controle filho do jogo
  } catch { $false }
}
$script:outrasUi = @(); $script:outrasUiAt = [datetime]::MinValue
function Outras-Janelinhas {   # retangulos das janelinhas DOS OUTROS slots (vazio fora do modo multibox)
  # EM CACHE: o Capture-Raw roda a cada leitura e o Get-Process enumera todos os processos do Windows - o mesmo
  # motivo pelo qual o Get-Game ja e cacheado. As janelinhas so mudam de lugar quando um bot sobe, cai, ou o
  # Fugir-Da-Area move alguma, entao 30s de validade sobra.
  if($Slot -le 0){ return @() }
  if(((Get-Date) - $script:outrasUiAt).TotalSeconds -lt 30){ return $script:outrasUi }
  $script:outrasUiAt = Get-Date
  $meu = if($script:ui -and -not $script:ui.IsDisposed){ $script:ui.Handle } else { [IntPtr]::Zero }
  $out = @()
  try {
    foreach($p in (Get-Process powershell -ErrorAction SilentlyContinue)){
      $h = $p.MainWindowHandle
      if($h -eq 0 -or $h -eq $meu -or $p.MainWindowTitle -notlike 'MudinhoX RPA*'){ continue }
      $r = New-Object W+RECT
      if([W]::GetWindowRect($h,[ref]$r)){ $out += New-Object System.Drawing.Rectangle($r.L, $r.T, ($r.R-$r.L), ($r.B-$r.T)) }
    }
  } catch {}
  $script:outrasUi = $out; $out
}
$script:capOk = $true   # a ultima captura foi mesmo do jogo? (Read-Status/Inv-Free usam pra nao ler nem salvar print de outra janela)
function Capture-Raw {   # bitmap da area cliente, sem mexer no foco (so chamar com o jogo na frente). Janelinha do bot fica preta (nao suja OCR/pixels)
  $h = Get-Game; $b = $null
  # Janela fechando/minimizando devolve area cliente 0x0, e New-Object Bitmap(0,0) estoura com "Parametro
  # invalido" - erro que o catch do loop principal trata como fatal e PARA o bot. Visto ao vivo, num restart do
  # mudx. Com a mensagem 'nao esta rodando' ele cai no caminho que ja existe: espera o cliente voltar e retoma.
  $c0 = New-Object W+RECT; [W]::GetClientRect($h,[ref]$c0) | Out-Null
  if($c0.R -le 0 -or $c0.B -le 0){ $script:gameH = [IntPtr]::Zero; throw "MudinhoX (mudx.exe) nao esta rodando: janela sem area cliente (minimizada ou fechando)" }
  Ver-Janela   # multibox: sobe a janela deste slot (sem roubar teclado) antes de fotografar
  for($i = 0; $i -lt 2; $i++){
    $c = New-Object W+RECT; [W]::GetClientRect($h,[ref]$c) | Out-Null; $o = Client-Origin
    $b = New-Object System.Drawing.Bitmap($c.R,$c.B); $g = [System.Drawing.Graphics]::FromImage($b)
    $g.CopyFromScreen($o.X,$o.Y,0,0,$b.Size)
    if($script:ui -and -not $script:ui.IsDisposed){ $r = $script:ui.Bounds; $g.FillRectangle([System.Drawing.Brushes]::Black, $r.X-$o.X, $r.Y-$o.Y, $r.Width, $r.Height) }
    # MULTIBOX: apaga tambem a janelinha DOS OUTROS slots. Cada bot so conhecia a propria ($script:ui), e com
    # quatro na tela a do slot 2 em cima do $LevelBox do cliente 1 viraria leitura de lixo - o tipo de bug que
    # este projeto ja caçou por horas. Mascarar sai mais barato e mais seguro que tentar posicionar as quatro
    # fora de tudo que o bot le (o inventario e o modal do mix nem tem posicao fixa).
    foreach($r in (Outras-Janelinhas)){ $g.FillRectangle([System.Drawing.Brushes]::Black, $r.X-$o.X, $r.Y-$o.Y, $r.Width, $r.Height) }
    $g.Dispose()
    # confere DEPOIS da foto: so checar antes nao basta, outra janela sobe no meio e o bot acaba lendo (e salvando print d)a tela do usuario
    # No MULTIBOX o teste nao pode ser "estou em primeiro plano" (a leitura nem pede foco) nem um "confio e sigo":
    # dois slots empilhados no MESMO ponto da tela leriam um o jogo do outro, e NADA no log denunciaria - mesmo
    # mapa, level parecido, e o bot distribuindo os pontos do char errado. Pergunta-se ao Windows quem esta nos
    # pixels: WindowFromPoint no centro da area cliente.
    $script:capOk = if($Slot -gt 0){ Janela-Na-Frente } else { $NoFocusRead -or ([W]::GetForegroundWindow() -eq $h) }
    if($script:capOk){ return $b }
    $b.Dispose(); $b = $null
    if($i -eq 0){   # uma re-tentativa; se ainda nao for a nossa janela nos pixels, devolve a foto marcada como suspeita
      if($Slot -gt 0){ Ver-Janela; Start-Sleep -Milliseconds 150 } else { Set-Foreground $h; Start-Sleep -Milliseconds 250 }
    }
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
  $own = -not $img; if($own){ $img = Capture-Raw }
  $largura = $ChatBox.X2 - $ChatBox.X1; $linhas = 0
  for($yb = $ChatBox.YFromBottomMax; $yb -ge $ChatBox.YFromBottomMin; $yb--){
    $y = $img.Height - $yb
    if($y -lt 0 -or $y -ge $img.Height){ continue }
    $red = 0
    for($x = $ChatBox.X1; $x -le $ChatBox.X2; $x += 4){   # passo 4: a borda e linha continua, nao precisa de todo pixel
      $p = $img.GetPixel($x,$y); if($p.R -gt 150 -and $p.G -lt 100 -and $p.B -lt 100){ $red += 4 }
    }
    if($red -gt $largura/2){ $linhas++ }
  }
  if($own){ $img.Dispose() }
  $linhas -ge 2   # borda de cima + borda de baixo
}
function Close-Chat { if(Chat-Open){ Clear-ChatLine; Press-Vk 0x0D; Start-Sleep -Milliseconds 200 } }   # apaga residuo e fecha (Enter vazio fecha); chamar com o jogo na frente
function Send-Chat([string]$text){   # $false se o jogo nao ficou na frente (nao digita em outra janela)
  $prev = Focus-Game
  if(-not $script:gameFg){ Log "jogo nao esta na frente, nao enviei '$text'"; return $false }
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
function Read-Map($img){   # nome do mapa (rotulo do minimapa) em minusculo, ou '' se nao leu. Com $img=$null captura sozinho
  $own = -not $img; if($own){ $img = Capture-Game }; if(-not $img){ return '' }
  $out = ''
  foreach($v in @( @{ X=$MapLabel.X; Y=$MapLabel.Y; W=$MapLabel.W; H=$MapLabel.H; S=4 },                              # faixa exata do rotulo
                   @{ X=$MapLabel.X-110; Y=[Math]::Max(0,$MapLabel.Y-25); W=$MapLabel.W+110; H=$MapLabel.H+50; S=3 } )){  # faixa larga: salva quando o painel desloca um pouco
    $c = Crop-Bitmap $img $v.X $v.Y $v.W $v.H $v.S
    $out = ((Ocr-Bitmap $c).Text -replace '[^A-Za-z]','').ToLower(); $c.Dispose()
    if($out){ break }
  }
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
  $null = Fugir-Da-Area $MapLabel.X $MapLabel.Y $MapLabel.W $MapLabel.H 'rotulo do minimapa'
  # A grade do inventario nao tem posicao fixa, entao aqui vale a metade direita da tela, que e onde ela ja apareceu.
  $null = Fugir-Da-Area 560 300 1060 420 'area onde o inventario costuma abrir'
}
function Unblock-MapLabel { Unblock-Areas }   # nome antigo, mantido pelos chamadores
function Save-Shot([string]$nome){   # print pra diagnostico (chamar com o jogo na frente)
  $img = Capture-Game; if(-not $img){ return '' }
  New-Item -ItemType Directory -Force $CaptchaShotDir | Out-Null
  $f = Join-Path $CaptchaShotDir $nome; $img.Save($f); $img.Dispose(); $f
}
$script:modo = 'reset'   # 'reset' = ciclo normal (farm/reset/darmr). 'joias' = farma ate encher, mixa, repete
$script:farmMap = ''; $script:phase = 'normal'; $script:warmupCount = 0; $script:restartCycle = $false; $script:forceMR = $false
# Cota diaria de master resets. mrsDia conta os de HOJE (mrs, do estado, e da vida inteira do char). cotaJoias
# lembra que foi a COTA que ligou o modo joias - sem isso, virar o dia arrancaria voce de um modo joias que
# VOCE escolheu. Os tres vao pro estado.txt: reiniciar o bot nao pode ser jeito de furar a cota.
$script:mrsDia = 0; $script:mrsDiaData = ''; $script:cotaJoias = $false
function Hoje { (Get-Date).ToString('yyyy-MM-dd') }
function Sync-BotoesModo {   # deixa os botoes coerentes com o $script:modo - tambem quando quem trocou de modo foi o BOT, nao voce
  if(-not $script:ui -or $script:ui.IsDisposed){ return }
  $script:btnMix.Text       = if($script:modo -eq 'joias'){ 'JOIAS: LIGADO' } else { 'modo JOIAS' }
  $script:btnMix.BackColor  = if($script:modo -eq 'joias'){ 'ForestGreen' } else { 'DarkCyan' }
  $script:btnGold.Text      = if($script:modo -eq 'dragoes'){ 'DRAGOES: LIGADO' } else { 'modo DRAGOES' }
  $script:btnGold.BackColor = if($script:modo -eq 'dragoes'){ 'ForestGreen' } else { 'Teal' }
}
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
      if($kv.modo -in 'reset','joias','dragoes'){ $script:modo = $kv.modo }
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
function Read-Level($img){
  $own = -not $img; if($own){ $img = Capture-Game }; if(-not $img){ return $null }
  $reads = @()
  $ly = $img.Height - $LevelBox.YFromBottom   # topo do numero, relativo a base da area cliente
  foreach($v in $LevelOcrVariants){
    $c = Crop-Bitmap $img $LevelBox.X $ly $LevelBox.W $LevelBox.H $v.S $v.Pad; if($v.Inv){ [Img]::Invert($c) }
    $txt = (Ocr-Bitmap $c).Text; $c.Dispose()
    if($txt -match '\d+'){ $reads += [int]$Matches[0] }
  }
  if($own){ $img.Dispose() }
  if($reads.Count -eq 0){ return $null }
  [int]($reads | Group-Object | Sort-Object Count -Descending | Select-Object -First 1).Name   # Sort-Object e estavel: empate mantem prioridade
}
function Get-HelperState($img){   # pausa = barras vermelhas; play = triangulo verde. Conta pixels num quadrado em volta do botao
  $own = -not $img; if($own){ $img = Capture-Game }; if(-not $img){ return 'unknown' }; $red = 0; $green = 0
  for($x = $PlayBtn.X-11; $x -le $PlayBtn.X+11; $x++){ for($y = $PlayBtn.Y-13; $y -le $PlayBtn.Y+13; $y++){
    $p = $img.GetPixel($x,$y)
    if($p.R -gt 120 -and $p.G -lt 100 -and $p.B -lt 100){ $red++ } elseif($p.G -gt 140 -and $p.R -lt 140 -and $p.B -lt 140){ $green++ }
  } }
  if($own){ $img.Dispose() }
  if($red -gt 10){ 'running' } elseif($green -gt 10){ 'stopped' } else { 'unknown' }
}

# ---------- captcha ----------
function Find-Captcha($img){   # centro do texto "Selecione a mesma imagem abaixo:" ou $null
  $line = (Ocr-Bitmap $img).Lines | ? { $_.Text -match 'Selecione' } | select -First 1
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
if(-not (Is-Admin) -and -not ($TestInv -or $TestMix -or $TestNpc -or $TestGold -or $TestVisao -or $Preflight -or $TestStatus -ne "")){   # -TestInv/-TestMix so LEEM a tela: nao precisam de admin (e elevar abriria janela oculta, sem saida no terminal)
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
        # Mostrar o piso REAL: na reta final ele nao e o $StatMinOutros, e a mensagem "418 pontos; minimo 100"
        # fez a recusa parecer um absurdo quando o piso aplicado tinha sido 500.
        $pisoReal = if($script:pertoDoMax){ [Math]::Min($StatMinPerto, $StatMinOutros) } else { $StatMinOutros }
        Log "stats: nada a distribuir agora ($p pontos; minimo $pisoReal por comando)"
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
  if(-not $script:pertoDoMax){
    $mesmoLevel = ($null -ne $script:lvlPrev -and $script:lvlPrev -eq $script:statLvlLast)
    if($mesmoLevel -and (Get-Date) -lt $script:statMax){ $script:statDue = (Get-Date).AddSeconds((Jit $intervalo)); return }
  }
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
  $subiu = ($script:ptsLeft -gt $script:stallPts); $script:stallPts = $script:ptsLeft
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
  $null = Click-Client $PlayBtn.X $PlayBtn.Y; Wait 2   # pausa o helper
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
  $lab = $words | ? { $_.Text -match '(?i)^pont' } | select -First 1; if(-not $lab){ return -1 }
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
  if($img.Width -ge $StatPanel.W -and $img.Height -ge $StatPanel.H){
    $c = Crop-Bitmap $img $StatPanel.X $StatPanel.Y $StatPanel.W $StatPanel.H $StatPanelScale
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
      if($miss){ New-Item -ItemType Directory -Force $CaptchaShotDir | Out-Null; $img.Save((Join-Path $CaptchaShotDir 'status_ultimo.png')) | Out-Null }
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
      New-Item -ItemType Directory -Force $CaptchaShotDir | Out-Null
      $img.Save((Join-Path $CaptchaShotDir 'status_falhou.png')); Log "status: nao abriu em 6 tentativas. Print em captcha\status_falhou.png"
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
      $btn = @{ X = $LoginBtn.X; Y = $alturaCli - $LoginBtn.YFromBottom }
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
    $script:resets = 0; $script:ptsSent = 0; $script:runStart = Get-Date; $script:ativoSeg = 0   # zera pra medir o proximo MR limpo
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
function Warp-To-Spot {   # teleporta pro spot da fase atual (warmup=/losttower7, normal=/s18) e confirma pelo mapa. Sucesso = ja num mapa de farm ou chegou num. $false = desistiu
  $cmd = if($script:phase -eq 'warmup'){ $WarmupCmd } else { $WarpCmd }
  $want = Spot-Map
  $before = Read-Map $null
  if(Same-Map $before $want){ $script:farmMap = $before; Log "ja no spot (mapa: $before, fase: $($script:phase))"; return $true }   # ja no spot CORRETO da fase
  $cego = 0
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
      if($t -eq 1){ $null = Log-GameMsg $null "apos $cmd"; $null = Save-Shot 'warp_falhou.png' }   # le a resposta do servidor e fotografa na PRIMEIRA falha (a mensagem some rapido)
    }
    else { $cego++; Tag-Ciclo 'warp'; Log "NAO CONSEGUI LER o nome do mapa (minimapa recolhido ou tapado?), tentativa $t/$WarpTries ($cmd)" }
  }
  if($cego -ge $WarpTries){   # nunca deu pra ler: o problema e a LEITURA, nao o teleporte. Reenviar /s18 nao resolve nada.
    $f = Save-Shot 'mapa_ilegivel.png'
    Notify "MudinhoX" "Nao consigo LER o nome do mapa no minimapa. Abra o painel do minimapa (setinha no canto). Print: $f"
    return $false
  }
  Notify "MudinhoX" "Nao consegui teleportar com $cmd ($WarpTries tentativas). Da uma olhada."; $false
}
function Start-Helper {   # liga o helper e CONFIRMA. Para de clicar apos PlayTries (nao insiste cego). $true se confirmou running
  for($i = 0; $i -lt $PlayTries; $i++){
    $st = Get-HelperState
    if($st -eq 'running'){ if($i){ Log "helper rodando" }; return $true }
    if($st -eq 'stopped'){
      Log "clicando play ($($i+1)/$PlayTries)"; $null = Click-Client $PlayBtn.X $PlayBtn.Y
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
  Log "helper nao ligou apos $PlayTries cliques, parei de tentar"; $false
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
  $null = Click-Client $InvMenuBtn.X $InvMenuBtn.Y -KeepFocus
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
function Hover-Npc {   # passa o mouse por $MixNpcPos (e uns vizinhos) ate o nome do NPC aparecer. Devolve o ponto confirmado ou $null. Chamar com o jogo na frente
  if(-not $MixNpcPos){ return $null }
  $o = Client-Origin
  foreach($dy in $MixNpcSweep){ foreach($dx in $MixNpcSweep){
    $x = $MixNpcPos.X + $dx; $y = $MixNpcPos.Y + $dy
    [W]::SetCursorPos($o.X + $x, $o.Y + $y) | Out-Null; Start-Sleep -Milliseconds 350
    $img = Capture-Raw
    $c = Crop-Bitmap $img ([Math]::Max(0,$x-150)) ([Math]::Max(0,$y+$MixNpcNameDy-25)) 300 60 2   # o nome so aparece com o mouse em cima: le so a faixa acima do cursor
    $txt = (Ocr-Bitmap $c).Text; $c.Dispose(); $img.Dispose()
    if($txt -match $MixNpcWords){ Log "mix: NPC confirmado em ($x,$y) - OCR leu '$($txt.Trim())'"; return @{ X = $x; Y = $y } }
  } }
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
    if($volta -eq 0){ Notify "MudinhoX" "Cheguei no $MixCmd mas o NPC nao apareceu em volta de ($($MixNpcPos.X),$($MixNpcPos.Y))." }
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
  if(-not $MixNpcPos){ Notify "MudinhoX" "Nao sei onde o NPC do mix fica: rode -TestNpc e preencha `$MixNpcPos."; return $false }
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
        Log "mix: cliquei em $($verde.J.Name) mas nao achei o botao CONFIRMAR - parando pra nao travar"
        Notify "MudinhoX" "O mix abriu um dialogo que eu nao reconheci. Confirma na mao e clique RETOMAR."
        $null = Save-Shot 'mix_sem_confirmar.png'
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
# ---------- evento dos dragoes dourados ----------
function Find-Gold($img){   # centro do bloco mais dourado da tela (Golden Tantalos), ou $null
  $x2 = $img.Width - $GoldArea.X2FromRight; $y2 = $img.Height - $GoldArea.Y2FromBottom
  $r = [Img]::BestGold($img, $GoldArea.X1, $GoldArea.Y1, $x2, $y2, $GoldCell,
        $GoldPix.RMin, $GoldPix.GMin, $GoldPix.BMax, $GoldPix.RmB, $GoldPix.RmG,
        [int]($img.Width/2), [int]($img.Height/2), $GoldSelfR, $GoldBlobMin)
  if($r[0] -eq 0 -and $r[1] -eq 0){ return $null }
  @{ X = $r[0]; Y = $r[1]; N = $r[2] }
}
function Ciclo-Dragoes {   # MODO DRAGOES: so caca. Nao checa inventario, nao checa atributos, nao reseta, nao da /darmr.
  $script:restartCycle = $false
  Hold-Focus
  try {
    Log "dragoes: indo pro $GoldCmd"
    if(-not (Send-Chat $GoldCmd)){ Wait 10; return }
    Wait $WarpWaitSec
    for($t = 1; $t -lt $WarpTries -and -not (Same-Map (Read-Map $null) $GoldMap); $t++){
      Log "dragoes: nao cheguei em '$GoldMap', reenviando ($t/$WarpTries)"; $null = Send-Chat $GoldCmd; Wait $WarpWaitSec
    }
    if(-not (Same-Map (Read-Map $null) $GoldMap)){
      Notify "MudinhoX" "Nao consegui chegar em '$GoldMap' com $GoldCmd. Saindo do modo dragoes."
      $script:modo = 'reset'; Save-Estado; return
    }
    # Lorencia e CIDADE: clicar no play la abre o popup "precisa estar fora da cidade" (gotcha ja documentado).
    # Sem helper, quem ataca e o proprio clique no mob - o loop abaixo reclica a cada varredura.
    if($GoldHelper){ Start-Helper } else { Log "dragoes: mapa e cidade, nao ligo o helper (clico no mob direto)"; Close-Popup }
  } finally { Release-Focus }

  $achados = 0; $vazios = 0; $vistos = @{}; $seguidas = 0
  while($script:modo -eq 'dragoes' -and -not $script:stop -and -not $script:restartCycle){
    Bater-Heartbeat
    $script:ptsLastGain = Get-Date   # cacar nao distribui pontos: sem isto o watchdog de progresso dispararia sozinho
    Pause-Gate
    Hold-Focus
    try {
    $img = Capture-Game
    if(-not $img){ Wait 2; continue }
    if(Handle-Captcha $img){ $img.Dispose(); continue }
    $alvo = Find-Gold $img; $img.Dispose()
    if($alvo){
      $vazios = 0; $achados++
      # Mob se move e morre. Mesma coordenada varias vezes = CENARIO, nao mob. No log de 31/08 foram 21 de 26
      # deteccoes na coluna x=655, e a caca passou o tempo batendo em nada. Vale mesmo com o filtro de cor errado.
      # Segunda guarda, pra falso positivo ESPALHADO: em Tarkan o CHAO e dourado e o detector achou "mob" em 20
      # varreduras seguidas, cada uma num lugar diferente. Um Golden Tantalos e raro ("restam 9 no mapa inteiro"):
      # achar um em toda varredura, sem intervalo, e impossivel. A guarda de coordenada repetida nao pega isso.
      $seguidas++
      if($seguidas -ge $GoldMaxSeguidas){
        Log "dragoes: achei alvo em $seguidas varreduras SEGUIDAS, cada uma num lugar - isso e o cenario dourado, nao mob. Parando."
        Notify "MudinhoX" "A caca esta casando com o cenario, nao com o mob. Calibre a cor com -TestGold. Parei."
        $null = Save-Shot 'gold_falso_positivo.png'
        $script:modo = 'reset'; Save-Estado; break   # detector provado errado: sair do modo, senao volta a cacar cenario no proximo ciclo
      }
      $chave = "$($alvo.X),$($alvo.Y)"
      $vistos[$chave] = [int]$vistos[$chave] + 1
      if($vistos[$chave] -ge $GoldRepetMax){
        Log "dragoes: achei '$chave' $($vistos[$chave]) vezes - isso e cenario, nao mob. Parando (calibre `$GoldPix com -TestGold)."
        Notify "MudinhoX" "A caca esta batendo sempre no mesmo ponto ($chave): o filtro de cor precisa de calibracao. Parei."
        $null = Save-Shot 'gold_falso_positivo.png'
        $script:modo = 'reset'; Save-Estado; break
      }
      Log "dragoes: dourado em $chave [$($alvo.N) px dourados], indo bater"
      $null = Click-Client $alvo.X $alvo.Y   # 1o clique leva o personagem ate o mob
      Wait $GoldStepSec
      if($GoldHelper){ Start-Helper } else { $null = Click-Client $alvo.X $alvo.Y; Wait $GoldStepSec }   # sem helper, o 2o clique e o ataque
    } else {
      $vazios++; $seguidas = 0   # varredura limpa quebra a sequencia: mob de verdade some da tela entre um e outro
      if($vazios % 10 -eq 0){ Log "dragoes: nada dourado na tela ha $vazios varreduras, continuo procurando" }
      Walk-Forward   # mapa grande e spawn variavel: anda pra um lado e procura de novo
      Wait $GoldRoamSec
    }
    } finally { Release-Focus }
  }
  Log "dragoes: saindo do modo ($achados alvos nesta rodada)"
  $script:ptsLastGain = Get-Date
}
$script:mixNow = $false; $script:semPlay = 0; $script:invFalhas = 0; $script:invDesligado = $false
$script:mixLast = Get-Date   # quando o bot foi mixar pela ultima vez (gatilho por tempo do ciclo normal)
function Tick-Inventory {   # aviso do jogo, teto de tempo (ou botao MIXAR AGORA) -> vai mixar e reinicia o ciclo (volta pro spot)
  # A contagem periodica de celulas saiu daqui: abria e fechava o inventario a cada 2 min (dois cliques, foco
  # roubado) pra produzir um numero que oscila com o alinhamento da grade - o MESMO inventario cheio leu 0 e 26
  # livres com 20px de diferenca na ancora. Sobrou o gatilho confiavel: a mensagem do proprio jogo. Inv-Free
  # continua existindo pro -Preflight e pro -TestInv, onde o numero e so informativo.
  # ...so que a mensagem NUNCA chegou: 0 ocorrencias de "inventario cheio" em 42 mil linhas de rpa.log, e no
  # mesmo periodo 68 pausas manuais suas pra mixar na mao. A faixa do $MsgBox e dominada por chat de jogador
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
function Metrics {   # o objetivo e o /darmr, nao o reset: o numero que importa e PONTOS/HORA e o ETA do MR. Reset e so o meio.
  $h = $script:ativoSeg / 3600.0   # TEMPO ATIVO, nao relogio de parede: downtime nao pode afundar a taxa
  if($h -le 0.01){ return }
  $ph = [int]($script:ptsSent / $h)
  $eta = if($ph -gt 0 -and $script:ptsNeeded -gt 0){ [Math]::Round($script:ptsNeeded / $ph, 1) } else { -1 }
  $porReset = if($script:resets -gt 0){ [int]($script:ptsSent / $script:resets) } else { 0 }
  $rh = if($h -gt 0){ [Math]::Round($script:resets / $h, 1) } else { 0 }
  $script:resumo = if($eta -ge 0){ "ETA MR ${eta}h | $ph pts/h" } else { "$ph pts/h" }   # vai pro titulo da janelinha
  Log ("== MR: faltam {0} pontos | {1} pontos/h | ETA ~{2} | {3} resets/h a {4} pts/reset (alvo lvl {5}, warmup {6}) | MRs: {7} ==" -f `
       $script:ptsNeeded, $ph, $(if($eta -ge 0){"${eta}h"}else{'?'}), $rh, $porReset, $TargetLevel, $WarmupResets, $script:mrs)
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
  $own = -not $img; if($own){ $img = Capture-Game }; if(-not $img){ return '' }
  $y = $img.Height - $MsgBox.Y1FromBottom; $h = $MsgBox.Y1FromBottom - $MsgBox.Y2FromBottom
  $t = ''
  if($y -ge 0 -and $h -gt 0 -and ($MsgBox.X + $MsgBox.W) -le $img.Width){
    $c = Crop-Bitmap $img $MsgBox.X $y $MsgBox.W $h 2
    $t = (Ocr-Bitmap $c).Text; $c.Dispose()
  }
  if($own){ $img.Dispose() }
  ($t -replace '\s+',' ').Trim()
}
function Log-GameMsg($img,[string]$quando){   # loga o que o servidor respondeu (antes so sobrava tirar print e adivinhar)
  $m = Read-Msgs $img
  if($m){ Log "jogo diz ($quando): $m" }
  $m
}
$script:msgDue = (Get-Date).AddSeconds(10)
function Tick-Msgs($img){   # le as mensagens do jogo de vez em quando. A caca aos dragoes NAO dispara sozinha (so pelo botao) - pedido do usuario
  if((Get-Date) -lt $script:msgDue){ return }
  $script:msgDue = (Get-Date).AddSeconds((Jit $MsgCheckSec))
  $m = Read-Msgs $img
  if(-not $m){ return }
  # O servidor repete o aviso do evento; no log foram 27 linhas iguais em ~1h. Loga uma vez por $RenotifySec.
  if($m -match $MsgGoldWords){
    if(-not $script:goldAviso -or ((Get-Date) - $script:goldAviso).TotalSeconds -ge $RenotifySec){
      $script:goldAviso = Get-Date; Log "evento dos dragoes no chat (use o botao DRAGOES DOURADOS se quiser ir)"
    }
  }
  elseif($m -match $MsgInvWords){ Log "jogo avisou inventario cheio -> vou mixar"; $script:mixNow = $true }
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
  Log "TestNpc: use a coordenada que apareceu com CONFERE em `$MixNpcPos = @{ X=..; Y=.. }"
  exit
}
function Run-Preflight([bool]$comSpot){   # valida os subsistemas de leitura no jogo de verdade. Devolve quantas falhas.
  # Diferente do -Check: este APERTA teclas (C e V), que e a parte que mais falha. Rodado no start (sem checar spot,
  # porque o bot ainda vai warpar) e sob demanda com -Preflight (checando spot).
  $script:falhas = 0
  function Ok([string]$nome,$cond,[string]$detalhe){ if($cond){ Log "  OK   $nome" } else { $script:falhas++; Log "  FALHOU $nome -> $detalhe" } }
  if((Game-IsAdmin) -and -not (Is-Admin)){ Log "  FALHOU privilegios -> o jogo roda elevado e este processo nao; o Windows vai ignorar teclado/mouse"; $script:falhas++ }
  else { Log "  OK   privilegios" }

  $h0 = Get-Game; $c0 = New-Object W+RECT; [W]::GetClientRect($h0,[ref]$c0) | Out-Null
  Ok 'resolucao bate com a calibracao' ($c0.R -eq $ClientEsperado.W -and $c0.B -eq $ClientEsperado.H) "$($c0.R)x$($c0.B), esperado $($ClientEsperado.W)x$($ClientEsperado.H)"

  Hold-Focus
  try {
    $img = Capture-Game
    Ok 'consegue capturar a tela do jogo' ($img -and $script:capOk) 'capturou outra janela ou o jogo nao veio pra frente'
    if($img){
      Ok 'le o level' ($null -ne (Read-Level $img)) 'Read-Level devolveu nada'
      Ok 'reconhece o botao play' ((Get-HelperState $img) -ne 'unknown') 'botao play irreconhecivel (fora do jogo? tela de login?)'
      $mapa = Read-Map $img
      Ok 'le o nome do mapa' ([bool]$mapa) 'minimapa recolhido ou tapado pela janela do bot?'
      # Com o $WarpMap ainda vazio nao ha nome pra comparar: cobrar isso seria uma falha inventada (o bot
      # aprende o nome no primeiro teleporte). Reporta e segue.
      if($comSpot){ $sp = Spot-Map; if($sp){ Ok 'esta no spot da fase atual' (Same-Map $mapa $sp) "mapa '$mapa', esperado '$sp'" } else { Log "       mapa do spot ainda nao aprendido: vou adotar o do primeiro $WarpCmd (li '$mapa' agora)" } }
      Ok 'nenhum captcha na tela' (-not (Find-Captcha $img)) 'tem captcha aberto agora'
      $img.Dispose()
    }
    $st = Read-Status
    Ok 'le os 4 atributos' ($null -ne $st) 'Read-Status falhou (janela C nao abriu ou OCR nao leu)'
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
  foreach($fx in 'chat_ABERTO.png','chat_ABERTO_2.png'){   # duas amostras independentes; nas duas as bordas ficaram em 117-118 e 92-93
    $i = Fx $fx
    if($i){ Ok "Chat-Open detecta a caixa aberta ($fx)" (Chat-Open $i) 'disse fechada com a caixa aberta (o C viraria letra no chat)'; $i.Dispose() }
  }
  $i = Fx 'tela_servidor.png'
  if($i){ Ok 'Chat-Open nao inventa caixa onde nao tem' (-not (Chat-Open $i)) 'achou chat aberto na tela de servidor'; $i.Dispose() }
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
    Ok 'Find-Captcha acha a ancora' ([bool]$a) 'nao achou o texto "Selecione"'
    if($a){ Ok 'Solve-Captcha tem certeza' ((Solve-Captcha $i $a -NoClick) -eq $true) 'ficou ambiguo' }
    $i.Dispose()
  }
  Log $(if($script:falhas){ "TestVisao: $($script:falhas) FALHA(S)" } else { 'TestVisao: tudo OK' })
  exit $(if($script:falhas){ 1 } else { 0 })
}
if($TestGold){   # com um Golden Tantalos NA TELA: mostra onde o detector acha dourado e salva o print marcado
  $img = Capture-Game; if(-not $img){ Log "jogo nao ficou na frente, nada lido"; exit }
  New-Item -ItemType Directory -Force $CaptchaShotDir | Out-Null
  $alvo = Find-Gold $img
  if($alvo){
    Log "dourado achado em ($($alvo.X),$($alvo.Y)) com $($alvo.N) pixels no bloco"
    $g = [System.Drawing.Graphics]::FromImage($img)
    $g.DrawRectangle((New-Object System.Drawing.Pen([System.Drawing.Color]::Lime,4)), $alvo.X-40, $alvo.Y-40, 80, 80); $g.Dispose()
  } else { Log "nenhum bloco dourado passou de $GoldBlobMin pixels (maior bloco teve menos que isso). Se o mob esta na tela, baixe `$GoldBlobMin ou afrouxe `$GoldPix" }
  $f = Join-Path $CaptchaShotDir 'gold.png'; $img.Save($f); Log "print salvo (com o quadrado verde no que ele achou): $f"
  $img.Dispose(); exit
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
  Log $(if($Slot -gt 0){ "ja existe um bot no slot $Slot (heartbeat$Sfx.txt fresco). Saindo pra nao duplicar." } else { 'ja existe um bot rodando (heartbeat fresco). Saindo pra nao duplicar.' })
  if($script:ui){ $script:ui.Dispose() }; exit
}
Remove-Item $StopFile -ErrorAction SilentlyContinue
if($Slot -gt 0){ Remove-Item $StopAllFile -ErrorAction SilentlyContinue }   # flag geral esquecida no disco derrubaria o start
Bater-Heartbeat
Log $(if($Slot -gt 0){ "iniciando (slot $Slot, spot $WarpCmd, arquivos rpa$Sfx.log / estado$Sfx.txt)" } else { 'iniciando' })
try {   # preflight no start: 10s conferindo tudo evita a noite inteira perdida por algo obvio. Nao BLOQUEIA (o spot nem e checado, o bot ainda vai warpar)
  # JANELA MENOR QUE A CALIBRACAO = para na hora, com instrucao. Nao e frescura de preflight: TODA coordenada do
  # bot e fixa em $ClientEsperado ($PlayBtn, $LevelBox, $MixNpcPos, a grade do captcha...). Numa janela menor o
  # Read-Level vai ler em x=1080 de uma tela de 958 e o GetPixel estoura - foi o que matou os 4 slots em 08/09,
  # quando os clientes foram reduzidos pra 958x484 pra caberem os quatro no monitor. O erro que aparecia era
  # "O parametro deve ser positivo e < Width", que nao diz nada sobre o tamanho da janela.
  # Maior que a calibracao nao para: as coordenadas ainda caem dentro, e o $LevelBox/$ChatBox ja medem a partir
  # da BASE da area cliente, entao altura extra e tolerada (ja rodou assim em 1920x1061).
  $cli = New-Object W+RECT; [W]::GetClientRect((Get-Game),[ref]$cli) | Out-Null
  if($cli.R -lt $ClientEsperado.W -or $cli.B -lt $ClientEsperado.H){
    Log "PARANDO: a area cliente do jogo esta $($cli.R)x$($cli.B), menor que a calibracao $($ClientEsperado.W)x$($ClientEsperado.H)."
    Log "  Todas as coordenadas do bot sao fixas nesse tamanho - numa janela menor ele le fora da tela e quebra."
    Log "  Ponha a janela do jogo em $($ClientEsperado.W)x$($ClientEsperado.H) e suba de novo."
    if($Slot -gt 0){ Log "  No multibox as janelas FICAM EMPILHADAS mesmo, uma por cima da outra - o bot traz pra frente a que ele precisa, uma de cada vez." }
    Notify "MudinhoX" "Janela do jogo em $($cli.R)x$($cli.B); precisa ser $($ClientEsperado.W)x$($ClientEsperado.H). Bot parado."
    if($script:logW){ $script:logW.Dispose() }; if($script:ui){ $script:ui.Dispose() }
    exit
  }
  Log "preflight de inicializacao:"
  $pf = Run-Preflight $false
  if($pf){ Notify "MudinhoX" "$pf verificacao(oes) falharam no start - veja o log. O bot vai tentar rodar mesmo assim." }
} catch { Log "preflight falhou: $_" }
try { Limpar-Watchdog } catch { Log "watchdog: $_" }   # apaga a Tarefa Agendada da versao antiga: nada pode sobreviver ao fechamento da janela
Load-Estado   # retoma fase/warmup/modo de onde parou (o warmup.flag abaixo ainda tem prioridade)
# Se o $WarmupResets do CONFIG baixou (10 -> 3) e o estado.txt guardou uma contagem maior, o char ja cumpriu a
# cota: sai do warmup na hora, em vez de gastar mais um ciclo de ~220s no Lost Tower so pra descobrir isso.
if($script:phase -eq 'warmup' -and $script:warmupCount -ge $WarmupResets){
  $script:phase = 'normal'; Save-Estado
  Log "warmup ja cumprido ($($script:warmupCount)/$WarmupResets pelo estado.txt) -> indo direto pro spot normal ($WarpCmd)"
}
if($script:ui){   # botoes tem que refletir o modo retomado do estado.txt
  Sync-BotoesModo   # UM lugar decide texto e cor dos botoes de modo; antes eram seis, e cada layout novo tinha que caçar todos
  if($script:modo -eq 'joias'){
    Log "retomando em MODO JOIAS: farma em $WarpCmd ate encher, mixa no $MixCmd, repete"
  } elseif($script:modo -eq 'dragoes'){
    Log "retomando em MODO DRAGOES: so caca em $GoldCmd"
  }
}
if(Test-Path $WarmupFile){ Remove-Item $WarmupFile -ErrorAction SilentlyContinue; $script:phase = 'warmup'; $script:warmupCount = 0; Save-Estado; Log "iniciando em modo warmup (pos-MR manual): $WarmupCmd ate $WarmupResets resets" }
while(-not $script:stop){   # envelope: se o cliente cair, o catch espera ele voltar e o ciclo recomeca aqui (antes o script terminava)
try {
while($true){
  Pause-Gate
  Cota-Rolar   # meia-noite: zera a cota do dia e tira o bot do descanso. Aqui em cima porque no descanso quem roda e o Ciclo-Joias, que da `continue`
  if($script:modo -eq 'joias'){ Ciclo-Joias; continue }       # farma ate encher, mixa, repete. Sem reset/darmr.
  if($script:modo -eq 'dragoes'){ Ciclo-Dragoes; continue }   # so caca. Sem inventario, sem atributos, sem reset/darmr.
  if($script:mixNow){ Hold-Focus; try { Tick-Inventory } finally { Release-Focus } }   # botao MIXAR JOIAS: atende ANTES do warp (senao so era visto la dentro do loop de farm, e o bot parecia ignorar o botao)

  $script:restartCycle = $false   # comecando um ciclo novo (botoes de fase ja aplicaram phase/forceMR)
  Hold-Focus; try { $warpOk = Warp-To-Spot; if($warpOk){ Start-Helper; $script:lvlChangedAt = Get-Date; $script:lvlSame = 0; if($script:forceMR){ $script:forceMR = $false; $script:statDue = Get-Date; Log "forcando distribuicao + MR" } } } finally { Release-Focus }
  if(-not $warpOk){ Wait 15; continue }

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
          Tick-Stats; Tick-Inventory; Tick-Msgs $img; Tick-Progresso; Tick-Human; Tick-WarmupTeste
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
              if($msg -match '(?i)level\s*(\d{2,4})\s*para\s*resetar'){
                $min = [int]$Matches[1]
                if($TargetLevel -lt $min){
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
    Log "ERRO: $_"; Notify "MudinhoX" "O jogo fechou. Abra o MudinhoX que o bot continua sozinho."
    $avisou = Get-Date
    while(-not $script:stop){
      Wait 10
      $script:gameH = [IntPtr]::Zero   # forca re-resolver o handle (o processo antigo morreu)
      # "o jogo voltou?" = existe de novo uma janela que o Get-Game aceitaria. Nao pode ser `Get-Process mudx`
      # cravado: na versao web quem responde isso e o titulo da janela, nao o nome do processo.
      if($(try { (Get-Game) -ne [IntPtr]::Zero } catch { $false })){
        Log "jogo voltou: esperando a tela carregar e retomando"; Wait 15
        Hold-Focus; try { $null = Enter-Game 'jogo reaberto' } finally { Release-Focus }   # pode ter voltado na tela de login
        break
      }
      if(((Get-Date) - $avisou).TotalSeconds -ge $RenotifySec){ Notify "MudinhoX" "Ainda esperando o jogo abrir."; $avisou = Get-Date }
    }
  } else { Log "ERRO: $_"; Notify "MudinhoX RPA parou" "$_"; Wait 30; $script:stopReason = "erro: $_"; $script:stop = $true }   # erro que nao seja o jogo fechado: sai sem stop.flag - quem decide se volta e o watchdog (que agora conta relancamento em vao e desiste)
}
}
Check-Stop
