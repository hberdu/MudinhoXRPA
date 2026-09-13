<#
  MudinhoX RPA - loop: /s18 -> play (MU Helper) -> espera level 350 -> /resetar -> repete.
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
param([switch]$Check, [string]$TestImage, [switch]$TestInv, [switch]$TestMix, [switch]$TestNpc, [switch]$TestGold, [switch]$TestVisao, [switch]$Preflight, [switch]$TestStatMin)

# ---------- CONFIG (coordenadas relativas a area cliente do jogo, 1920x1009) ----------
$TargetLevel   = 350     # level pra resetar. Nunca abaixo de $LevelMinReset (o servidor recusa)
$PlayBtn       = @{ X = 77;   Y = 33 }                     # centro do botao play/pause (canto sup. esquerdo)
$LevelBox      = @{ X = 1080; W = 140; H = 40; YFromBottom = 82 }    # numero do level na barra inferior; Y medido a partir da BASE da area cliente (aguenta resolucao/altura diferente)
$PollSec       = 6       # intervalo de leitura do level com o jogo na frente
$PollNearSec   = 2       # perto do level alvo le a cada N seg: o level sobe ~150 entre leituras e o reset saia com 400 em vez de 350 (farm jogado fora)
$PollNearFrom  = 0.82    # "perto" = a partir de N% do $TargetLevel
$NoFocusRead   = $false  # $true: LE sem trazer o jogo pra frente (so pra jogo sempre visivel, ex 2o monitor). Comandos continuam exigindo foco
$PollBgSec     = 60      # intervalo quando outra janela esta na frente (cada leitura rouba o foco por ~1s)
$WarpCmd       = '/s18'   # comando de teleporte pro spot de farm normal (troque aqui se mudar de spot)
$WarmupCmd     = '/losttower7'   # apos /darmr o personagem volta fraco em Lorencia: farma AQUI (Lost Tower 7) ate juntar os primeiros resets
$WarmupResets  = 10          # quantos resets fazer no modo warmup (pos-darmr) antes de voltar ao spot normal ($WarpCmd)
$WarpMap       = 'stad'      # nome esperado do mapa do /s18 (Stadium), 4 primeiras letras. So conta "no spot" se o mapa bater com este
$WarmupMap     = 'lost'      # nome esperado do mapa do /losttower7 (Lost Tower). Evita aceitar mapa errado (ex AIDA) como spot
$WarpWaitSec   = 9       # espera apos o teleporte (dar tempo do mapa trocar)
$ResetWaitSec  = 15      # sem captcha e level ainda alto apos N seg -> reenvia /resetar
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
$StatMinOutros = 1000    # piso de /f /v /e. Era so precaucao (nunca testado). Baixe pra ~1 depois que -TestStatMin confirmar que o servidor aceita
$StatEverySec  = 15      # distribui os pontos a cada N seg enquanto upa (alem de logo apos cada reset e antes de cada /resetar)
$StatRoundSec  = 0.5     # espera entre uma rodada de distribuicao e a releitura do status
# Velocidade do teclado/chat. 40/40 e o valor testado que NAO embaralha - nao baixe (ja fez /s18 sair invalido e queimar 4 warps).
$KeyHoldMs     = 40      # tempo segurando cada tecla ao digitar
$KeyGapMs      = 40      # pausa entre uma tecla e a proxima
$KeyClearMs    = 12      # backspaces pra limpar o chat (sao 30 seguidos, e so apagar: aguenta ser rapido)
$ChatOpenMs    = 130     # espera a caixa de chat abrir antes de digitar
$ChatSendMs    = 70      # espera em volta do Enter que envia
$StatCol       = @{ X = 1155; Y = 108; W = 195; H = 380 }   # coluna da janela de status (rotulos+valores); OCR isolado dessa faixa le os 4 atributos + pontos
$StatMaxValue  = 32767   # atributo cheio (cap real do servidor). /darmr SO funciona com Forca, Agilidade, Vitalidade E Energia TODOS = 32767; abaixo disso o jogo recusa ("precisa 32767 em todos status")
$StatStages    = @(1..([Math]::Floor(($StatMaxValue - 1) / $StatStep)) | % { $_ * $StatStep }) + $StatMaxValue   # 5000,10000,...,30000,32767
$StatusKey     = 0x43    # C = janela de status
$HotkeyHoldMs  = 150     # hotkey (C) segurada mais tempo que tecla de texto
$LoginBtn      = @{ X = 960; Y = 940 }    # botao pra entrar com o personagem apos /darmr (centro embaixo). Antes disso procura o texto abaixo por OCR
$LoginWords    = 'Entrar|Conectar|Iniciar|Jogar|Selecionar|Enter|Start|Login'   # tela de selecao de PERSONAGEM
$LoginServerWords = '(?i)server vip gold'   # tela de selecao de SERVIDOR: regex do botao a clicar (ex 'Server Principal'). Vazio = nao clica, avisa
$LoginDangerWords = '(?i)(criar nova conta|create account|^sair$|delete)'   # se isso esta na tela, NUNCA clicar em coordenada chutada
$ChatBox       = @{ X1 = 870; X2 = 1130; YFromBottomMin = 80; YFromBottomMax = 130 }   # bordas vermelhas da caixa de chat aberta. FAIXA, nao linha fixa: a caixa desloca alguns px conforme o layout
$StallSec      = 40      # no spot com level parado N seg (miss infinito) -> pausa e religa o helper. 75 gastava tempo demais so PRA DETECTAR (disparou 5x numa noite)
$CityWords     = 'lorencia|noria|devias|elbeland|lorenmarket|karutan|elveland'   # mapas-cidade onde NAO se farma (personagem cai aqui apos reset). Qualquer outro mapa = spot de farm (ex Stadium do /s18)
# teleporte confirmado quando o mapa e um spot de farm (nao-cidade). $farmMap guarda o ultimo spot.
$MapLabel      = @{ X = 1690; Y = 68; W = 230; H = 30 }   # rotulo do minimapa
$WarpTries     = 4       # reenvia o comando de warp ate N vezes se o mapa nao mudar, depois avisa e segue
$PlayTries     = 3       # clica no play ate N vezes; se nao ligar, para de clicar (nao insiste cego)
$HumanMinSec   = 120; $HumanMaxSec = 420   # a cada X seg (aleatorio) faz algo "humano": anda um pouco, abre/fecha janela, mexe o mouse
$LogFile       = Join-Path $PSScriptRoot 'rpa.log'
$StopFile      = Join-Path $PSScriptRoot 'stop.flag'
$HeartbeatFile = Join-Path $PSScriptRoot 'heartbeat.txt'   # o bot bate aqui a cada volta; o watchdog externo relanca se ficar velho
$AtivoGapMax   = 120     # buraco maior que N seg entre voltas = o bot esteve PARADO; nao conta como tempo ativo nas metricas
$HeartbeatVivoSec = 180  # heartbeat mais novo que isso = tem bot vivo (impede duas instancias no mesmo jogo)
$SemProgressoMax = 3     # apos N ciclos seguidos sem progresso, o bot REINICIA A SI MESMO (ja elevado: nao pede UAC de novo)
$EstadoFile    = Join-Path $PSScriptRoot 'estado.txt'   # fase + contagem de warmup, pra sobreviver a reinicio do bot
$LogMaxMB      = 5       # rpa.log maior que isso no start vira .bak (a pasta sincroniza no OneDrive)
$LogKeepBaks   = 5       # quantos .bak manter
$WarmupFile    = Join-Path $PSScriptRoot 'warmup.flag'   # se existir no start, o bot comeca em modo warmup (/losttower7) — use apos dar MR manualmente
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
$CapConfidence = 0.5                          # melhor precisa ser < 50% do segundo, senao nao chuta
$CaptchaShotDir = Join-Path $PSScriptRoot 'captcha'   # print salvo aqui a cada captcha
$FixtureDir    = Join-Path $PSScriptRoot 'fixtures'   # prints guardados pro -TestVisao (regressao das funcoes de leitura de tela)
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
$AutoTune      = $true   # o bot roda um A/B do alvo de level sozinho e fica com o melhor (compara PONTOS/H, nao resets/h)
$AutoTuneAlvos = 350, 380   # alvos a testar. NAO usar abaixo de $LevelMinReset: o servidor recusa e o /resetar so vira reenvio ate o char passar do minimo sozinho
$LevelMaximo   = 400     # teto de level do servidor ("voce esta no nivel maximo"). No modo joias o char fica parado nele, entao o detector de miss infinito nao pode usar o level la
$LevelMinReset = 350     # level minimo pra resetar. CONFIRMADO pela mensagem do servidor: "Voce precisa de estar no level 350 para resetar!". O bot re-aprende isso sozinho se mudar
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
$MixConfirmWords = '(?i)^confirmar$'   # 2o dialogo do mix: "Deseja continuar?" com CONFIRMAR/CANCELAR. NUNCA casar com CANCELAR
$CursorParkX   = 40      # canto pra onde o mouse e levado antes de ler a tela (o ponteiro aparece na captura e some com o texto debaixo)
$CursorParkY   = 400
$MixListaWords = '(?i)^(soul|life|creation|chaos|fragment|stone|jewel)'   # alguma dessas na tela = a LISTA de joias esta aberta
$MixWaitSec    = 5        # espera entre o mix de um tipo e o proximo
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
$InvFreeMin    = 4        # menos que N celulas livres = inventario cheio -> vai mixar
$JoiasFarmMax  = 8       # modo JOIAS: vai mixar a cada N min. E o gatilho PRINCIPAL: a contagem de celulas depende de alinhamento e a ancora oscila, entao nao da pra confiar nela pra adiar o mix
$InvUsarMenu   = $true   # se a tecla nao abrir o inventario, tenta pelo MENU do jogo (botao de 3 barras no topo direito)
$InvMenuBtn    = @{ X = 1888; Y = 23 }   # botao de 3 barras (menu) no canto superior direito, area cliente
$InvMenuAncora = '(?i)^(shop|personagem|guild|mercado|invent)'   # se nenhuma dessas palavras aparece, o menu NAO abriu: nao clica
$InvMenuClickDy = -45    # no menu, o item e um ICONE com o rotulo EMBAIXO: o OCR acha o texto, mas o clicavel esta ACIMA dele
$InvMenuWords  = '(?i)^invent'   # item do menu que abre o inventario
$InvMaxFalhas  = 3       # apos N falhas seguidas de abrir o inventario, desiste (nao fica apertando tecla desconhecida no personagem)
$InvCheckSec   = 300      # checa o inventario a cada N seg enquanto farma
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
function Log($m){
  $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m; Write-Host $line
  if($script:logW){ try { $script:logW.WriteLine($line) } catch {} } else { try { Add-Content -Path $LogFile -Value $line -Encoding UTF8 } catch {} }
  if($script:ui -and -not $script:ui.IsDisposed){
    $script:status.Text = $m
    # o TextBox crescia sem limite: rodando dias seguidos a janela fica pesada. Corta pela metade quando passa do teto.
    if($script:logBox.TextLength -gt $UiLogMaxChars){ $script:logBox.Text = $script:logBox.Text.Substring($script:logBox.TextLength - [int]($UiLogMaxChars/2)) }
    $script:logBox.AppendText("$line`r`n"); [System.Windows.Forms.Application]::DoEvents()
  }
}
$script:ativoSeg = 0.0; $script:tickLast = $null
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
function Check-Stop { if(-not $script:stop -and (Test-Path $StopFile)){ $script:stop = $true; Remove-Item $StopFile -ErrorAction SilentlyContinue }; if($script:stop){ Log "parado pelo usuario"; Remove-Item $HeartbeatFile -ErrorAction SilentlyContinue; if($script:logW){ $script:logW.Dispose() }; if($script:ui){ $script:ui.Dispose() }; exit } }
function Pause-Gate {   # congela o bot enquanto PAUSADO e LIBERA o foco pra voce mixar joias no NPC; re-adquire ao retomar
  if(-not $script:paused){ return }
  $wasHeld = $script:focusHeld; if($wasHeld){ Release-Focus }   # solta o jogo pra voce interagir
  while($script:paused -and -not $script:stop){ if($script:ui){ [System.Windows.Forms.Application]::DoEvents() }; Check-Stop; Start-Sleep -Milliseconds 200 }
  $script:ptsLastGain = Get-Date   # tempo pausado nao conta como "sem progresso" (senao o watchdog dispara na hora que voce retoma)
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
function Show-Ui {
  $f = New-Object System.Windows.Forms.Form
  $f.Text = 'MudinhoX RPA'; $f.Width = 400; $f.Height = 300; $f.TopMost = $true; $f.FormBorderStyle = 'FixedToolWindow'
  $f.StartPosition = 'Manual'; $f.Location = New-Object System.Drawing.Point(10, ([System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea.Height - 310))   # canto INFERIOR ESQUERDO: nao cobre play(topo-esq), minimapa(topo-dir), inventario(dir) nem chat/level(centro-baixo)
  $script:status = New-Object System.Windows.Forms.Label; $script:status.SetBounds(10,12,160,22); $script:status.Text = 'iniciando...'
  $script:btnPause = New-Object System.Windows.Forms.Button; $script:btnPause.SetBounds(175,6,100,28); $script:btnPause.Text = 'PAUSAR'; $script:btnPause.BackColor = 'Goldenrod'
  $btn = New-Object System.Windows.Forms.Button; $btn.SetBounds(280,6,100,28); $btn.Text = 'PARAR'; $btn.BackColor = 'IndianRed'
  # linha 2: comando manual de fase
  $script:btnWarmup = New-Object System.Windows.Forms.Button; $script:btnWarmup.SetBounds(10,40,122,32);  $script:btnWarmup.Text = "Warmup LT7`n(10 resets)"; $script:btnWarmup.BackColor = 'SteelBlue'
  $script:btnNormal = New-Object System.Windows.Forms.Button; $script:btnNormal.SetBounds(137,40,122,32); $script:btnNormal.Text = "Normal /s18`n(ate MT)"; $script:btnNormal.BackColor = 'MediumSeaGreen'
  $script:btnMR     = New-Object System.Windows.Forms.Button; $script:btnMR.SetBounds(264,40,120,32);     $script:btnMR.Text = "Atribuir tudo`n+ MR"; $script:btnMR.BackColor = 'MediumPurple'
  $script:btnMix    = New-Object System.Windows.Forms.Button; $script:btnMix.SetBounds(10,76,122,26);    $script:btnMix.Text = 'MODO JOIAS'; $script:btnMix.BackColor = 'DarkCyan'
  $script:btnGold   = New-Object System.Windows.Forms.Button; $script:btnGold.SetBounds(137,76,247,26); $script:btnGold.Text = "MODO DRAGOES ($GoldCmd)"; $script:btnGold.BackColor = 'Teal'   # NAO usar tom dourado: o -TestGold roda em processo separado (nao mascara a UI) e detectava o proprio botao como dragao
  $script:logBox = New-Object System.Windows.Forms.TextBox; $script:logBox.SetBounds(10,108,375,150); $script:logBox.Multiline = $true; $script:logBox.ReadOnly = $true; $script:logBox.ScrollBars = 'Vertical'
  $script:btnPause.Add_Click({ $script:paused = -not $script:paused; $script:btnPause.Text = $(if($script:paused){ 'RETOMAR' } else { 'PAUSAR' }); $script:btnPause.BackColor = $(if($script:paused){ 'ForestGreen' } else { 'Goldenrod' }); Log $(if($script:paused){ 'PAUSADO pelo usuario (mixe as joias; clique RETOMAR pra voltar)' } else { 'retomado pelo usuario' }) })
  $btn.Add_Click({ $script:stop = $true })
  $script:btnWarmup.Add_Click({ $script:phase = 'warmup'; $script:warmupCount = 0; $script:forceMR = $false; $script:restartCycle = $true; $script:paused = $false; $script:btnPause.Text = 'PAUSAR'; $script:btnPause.BackColor = 'Goldenrod'; Save-Estado; Log "[BOTAO] modo WARMUP: /losttower7 ate $WarmupResets resets" })
  $script:btnNormal.Add_Click({ $script:modo = 'reset'; $script:btnMix.Text = 'MODO JOIAS'; $script:btnMix.BackColor = 'DarkCyan'; $script:btnGold.Text = "MODO DRAGOES ($GoldCmd)"; $script:btnGold.BackColor = 'Teal'; $script:phase = 'normal'; $script:forceMR = $false; $script:restartCycle = $true; $script:paused = $false; $script:btnPause.Text = 'PAUSAR'; $script:btnPause.BackColor = 'Goldenrod'; Save-Estado; Log "[BOTAO] modo NORMAL: /s18 ate os atributos encherem" })
  $script:btnMR.Add_Click({ $script:forceMR = $true; $script:restartCycle = $true; $script:paused = $false; $script:btnPause.Text = 'PAUSAR'; $script:btnPause.BackColor = 'Goldenrod'; Log "[BOTAO] ATRIBUIR TUDO + MR" })
  $script:btnMix.Add_Click({
    $script:modo = if($script:modo -eq 'joias'){ 'reset' } else { 'joias' }
    $script:restartCycle = $true; $script:paused = $false; $script:btnPause.Text = 'PAUSAR'; $script:btnPause.BackColor = 'Goldenrod'
    $script:btnMix.Text = if($script:modo -eq 'joias'){ 'MODO JOIAS (ligado)' } else { 'MODO JOIAS' }
    $script:btnGold.Text = "MODO DRAGOES ($GoldCmd)"; $script:btnGold.BackColor = 'Teal'
    $script:btnMix.BackColor = if($script:modo -eq 'joias'){ 'ForestGreen' } else { 'DarkCyan' }
    Save-Estado
    Log $(if($script:modo -eq 'joias'){ "[BOTAO] MODO JOIAS: farma em $WarpCmd ate encher, mixa no $MixCmd, repete. Sem reset e sem /darmr." } else { '[BOTAO] modo JOIAS desligado: volta ao ciclo de reset/master reset' })
  })
  $script:btnGold.Add_Click({
    $script:modo = if($script:modo -eq 'dragoes'){ 'reset' } else { 'dragoes' }
    $script:restartCycle = $true; $script:paused = $false; $script:btnPause.Text = 'PAUSAR'; $script:btnPause.BackColor = 'Goldenrod'
    $script:btnGold.Text = if($script:modo -eq 'dragoes'){ 'MODO DRAGOES (ligado)' } else { "MODO DRAGOES ($GoldCmd)" }
    $script:btnGold.BackColor = if($script:modo -eq 'dragoes'){ 'ForestGreen' } else { 'Teal' }
    $script:btnMix.Text = 'MODO JOIAS'; $script:btnMix.BackColor = 'DarkCyan'
    Save-Estado
    Log $(if($script:modo -eq 'dragoes'){ "[BOTAO] MODO DRAGOES: so caca em $GoldCmd, sem reset/darmr/inventario" } else { '[BOTAO] modo DRAGOES desligado: volta ao ciclo de reset/master reset' })
  })
  $f.Add_FormClosing({ $script:stop = $true })
  $f.Controls.AddRange(@($script:status,$script:btnPause,$btn,$script:btnWarmup,$script:btnNormal,$script:btnMR,$script:btnMix,$script:btnGold,$script:logBox)); $f.Show(); $script:ui = $f
}

# ---------- janela do jogo / foco ----------
function Is-Admin { ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) }
function Game-IsAdmin { -not (Get-Process mudx -ErrorAction SilentlyContinue | select -First 1).Path }   # processo elevado nao expoe o Path pra processo comum
$script:gameH = [IntPtr]::Zero
function Get-Game {   # handle da janela do jogo, EM CACHE: Get-Process enumera todos os processos do Windows e isto e chamado ~6x por comando
  if($script:gameH -ne [IntPtr]::Zero -and [W]::IsWindow($script:gameH)){ return $script:gameH }
  $p = Get-Process mudx -ErrorAction SilentlyContinue | ? { $_.MainWindowHandle -ne 0 } | select -First 1
  if(-not $p){ throw "MudinhoX (mudx.exe) nao esta rodando" }
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
function Focus-Game {
  $h = Get-Game
  if($script:focusHeld){   # dentro de um bloco: nao mexe no prev nem devolve; so garante o jogo na frente
    $script:gameFg = ([W]::GetForegroundWindow() -eq $h); if(-not $script:gameFg){ Set-Foreground $h; $script:gameFg = ([W]::GetForegroundWindow() -eq $h) }; return $script:focusPrev
  }
  $prev = [W]::GetForegroundWindow(); $script:gameWasFg = ($prev -eq $h) -or (Is-OwnUi $prev); Set-Foreground $h; $script:gameFg = ([W]::GetForegroundWindow() -eq $h); $prev
}
function Restore-Focus($prev){ if($script:focusHeld){ return }; if($prev -and $prev -ne (Get-Game) -and -not (Is-OwnUi $prev)){ Set-Foreground $prev } }   # dentro de bloco nao devolve; senao devolve pra janela anterior (nao a do bot)
function Hold-Focus {   # inicia bloco: guarda a janela do usuario, traz o jogo 1x
  if($script:focusHeld){ return }
  $script:focusPrev = [W]::GetForegroundWindow(); $script:gameWasFg = ($script:focusPrev -eq (Get-Game)) -or (Is-OwnUi $script:focusPrev)
  $script:focusHeld = $true; $null = Focus-Game
}
function Release-Focus {   # fim do bloco: devolve o foco pra janela do usuario (1x)
  if(-not $script:focusHeld){ return }
  $script:focusHeld = $false; Restore-Focus $script:focusPrev
}
function Client-Origin { $h = Get-Game; $pt = New-Object W+POINT; [W]::ClientToScreen($h,[ref]$pt) | Out-Null; $pt }
$script:capOk = $true   # a ultima captura foi mesmo do jogo? (Read-Status/Inv-Free usam pra nao ler nem salvar print de outra janela)
function Capture-Raw {   # bitmap da area cliente, sem mexer no foco (so chamar com o jogo na frente). Janelinha do bot fica preta (nao suja OCR/pixels)
  $h = Get-Game; $b = $null
  for($i = 0; $i -lt 2; $i++){
    $c = New-Object W+RECT; [W]::GetClientRect($h,[ref]$c) | Out-Null; $o = Client-Origin
    $b = New-Object System.Drawing.Bitmap($c.R,$c.B); $g = [System.Drawing.Graphics]::FromImage($b)
    $g.CopyFromScreen($o.X,$o.Y,0,0,$b.Size)
    if($script:ui -and -not $script:ui.IsDisposed){ $r = $script:ui.Bounds; $g.FillRectangle([System.Drawing.Brushes]::Black, $r.X-$o.X, $r.Y-$o.Y, $r.Width, $r.Height) }
    $g.Dispose()
    # confere DEPOIS da foto: so checar antes nao basta, outra janela sobe no meio e o bot acaba lendo (e salvando print d)a tela do usuario
    $script:capOk = $NoFocusRead -or ([W]::GetForegroundWindow() -eq $h)   # com $NoFocusRead voce garante o jogo visivel (2o monitor) e o bot nao rouba foco pra ler
    if($script:capOk){ return $b }
    $b.Dispose(); $b = $null
    if($i -eq 0){ Set-Foreground $h; Start-Sleep -Milliseconds 250 }   # uma re-tentativa; se o Windows negar, devolve a foto marcada como suspeita
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
function Press-Vk([int]$vk,[int]$hold=$KeyHoldMs,[int]$gap=$KeyGapMs){ $sc = [W]::MapVirtualKey($vk,0); [W]::keybd_event($vk,$sc,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds $hold; [W]::keybd_event($vk,$sc,2,[UIntPtr]::Zero); Start-Sleep -Milliseconds $gap }
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
  $o = Client-Origin; [W]::SetCursorPos($o.X+$x,$o.Y+$y) | Out-Null; Start-Sleep -Milliseconds 80
  [W]::mouse_event(2,0,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 50; [W]::mouse_event(4,0,0,0,[UIntPtr]::Zero)
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
    $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $script:ui.Location = New-Object System.Drawing.Point(10, ($wa.Height - $script:ui.Height - 10))
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
function Save-Estado {   # fase/warmup E as metricas do MR. Medir um MR leva horas e reiniciar o bot zerava tudo.
  try {
    @(
      "fase=$($script:phase)"
      "modo=$($script:modo)"
      "warmup=$($script:warmupCount)"
      "resets=$($script:resets)"
      "ptsSent=$($script:ptsSent)"
      "runStart=$($script:runStart.Ticks)"
      "ativoSeg=$([int]$script:ativoSeg)"
      "mrs=$($script:mrs)"
      "mrStart=$($script:mrStart.Ticks)"
      "ciclos=$(@($script:ciclos) -join ",")"
      "alvo=$TargetLevel"
      "tuneOn=$(if($script:tuneOn){1}else{0})"
      "minReset=$($script:LevelMinReset)"
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
      if($kv.resets){ $script:resets = [int]$kv.resets }
      if($kv.ptsSent){ $script:ptsSent = [int]$kv.ptsSent }
      if($kv.mrs){ $script:mrs = [int]$kv.mrs }
      if($kv.runStart){ $script:runStart = [datetime]::new([long]$kv.runStart) }
      if($kv.ativoSeg){ $script:ativoSeg = [double]$kv.ativoSeg }
      if($kv.mrStart){ $script:mrStart = [datetime]::new([long]$kv.mrStart) }
      if($kv.ciclos){ $script:ciclos = @($kv.ciclos -split "," | ? { $_ }) }
      if($kv.alvo){ $script:TargetLevel = [int]$kv.alvo }
      if($kv.tuneOn -eq "0"){ $script:tuneOn = $false; Log "autotune ja concluido antes: alvo $($script:TargetLevel)" }
      if($kv.minReset){ $script:LevelMinReset = [int]$kv.minReset }
    }
    Log "estado retomado: fase $($script:phase), warmup $($script:warmupCount)/$WarmupResets, $($script:resets) resets e $($script:ptsSent) pontos acumulados neste MR"
  } catch { Log "estado.txt ilegivel, comecando do zero: $_" }
}
function Same-Map($a,$b){ $a -and $b -and $a.Substring(0,[Math]::Min(4,$a.Length)) -eq $b.Substring(0,[Math]::Min(4,$b.Length)) }   # mesmo mapa pelos 4 primeiros caracteres (tolera ruido do OCR nas coords/fim)
function Close-Popup { Press-Vk 0x1B; Start-Sleep -Milliseconds 300; Press-Vk 0x1B }   # ESC fecha popups do jogo (ex "precisa estar fora da cidade" apos /darmr)
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
function Solve-Captcha($img,$a,[switch]$NoClick){   # $true se clicou (ou, com -NoClick, se teria certeza)
  $ref = Crop-Bitmap $img ($a.X-40) ($a.Y+$CapRefDy-40) 80 80
  $cands = foreach($dy in $CapRowDy){ foreach($dx in $CapColDx){
    $o = Crop-Bitmap $img ($a.X+$dx-48) ($a.Y+$dy-48) 96 96; $s = [Img]::MinSad($ref,$o); $o.Dispose()
    [pscustomobject]@{ X = $a.X+$dx; Y = $a.Y+$dy; S = $s }
  } }
  $ref.Dispose(); $c = $cands | sort S
  Log ("captcha: melhor ({0},{1}) score={2} | segundo score={3}" -f $c[0].X,$c[0].Y,$c[0].S,$c[1].S)
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
      Log "captcha: errei $CapMaxTries vezes -> fechando o jogo (mudx.exe) e parando"
      Notify "MudinhoX: CAPTCHA" "Errei o captcha $CapMaxTries vezes. Fechei o jogo e parei o bot."
      Get-Process mudx -ErrorAction SilentlyContinue | Stop-Process -Force; if($script:ui){ $script:ui.Dispose() }; exit
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
  Log "level lido: $(Read-Level $img) | helper: $(Get-HelperState $img) | captcha: $(if($a){"sim ($($a.X),$($a.Y))"}else{'nao'}) | jogo na frente: $($script:gameWasFg) | chat aberto: $(Chat-Open $img)"
  if($a){ $null = Solve-Captcha $img $a -NoClick }
  if((Game-IsAdmin) -and -not (Is-Admin)){ Log "AVISO: o jogo roda como administrador e eu nao -> Windows ignora meu teclado/mouse. O loop principal se eleva sozinho (aceite o UAC)." }
  exit
}

# ---------- admin ----------
# O jogo roda como administrador: o Windows descarta teclado/mouse sintetico vindo de processo comum (UIPI). Entao roda elevado.
if(-not (Is-Admin) -and -not ($TestInv -or $TestMix -or $TestNpc -or $TestGold -or $TestVisao -or $Preflight)){   # -TestInv/-TestMix so LEEM a tela: nao precisam de admin (e elevar abriria janela oculta, sem saida no terminal)
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
function Plan-Stats($st,[int]$p){   # TODOS os comandos que os $p pontos dao conta, ja atravessando as etapas (simula o efeito de cada comando).
  $sim = @{}; foreach($k in $StatOrder){ $sim[$k] = [int]$st[$k] }   # assim uma leitura de status rende ate 16 comandos, em vez de 1 leitura por etapa
  $out = @()
  for($etapa = 0; $etapa -le $StatStages.Count; $etapa++){
    $stage = Stat-Stage $sim; $mandou = $false
    foreach($k in $StatOrder){   # enche um atributo ate a meta da etapa antes de passar pro proximo (energia, agilidade, forca, vitalidade)
      if($p -le 0){ break }   # nao corta aqui pelo minimo de 1000: um atributo pode precisar de menos pra FECHAR o cap
      $faltaEtapa = $stage - $sim[$k]
      if($faltaEtapa -le 0){ continue }
      $faltaCap = $StatMaxValue - $sim[$k]
      $sc = $StatCmds | ? { $_.Key -eq $k } | select -First 1
      # /a tem perigo REAL documentado (valor pequeno teleporta pra AIDA). Pros outros o piso era so precaucao:
      # baixe $StatMinOutros depois de confirmar com -TestStatMin que o servidor aceita valor pequeno em /f /v /e.
      $minCmd = if($sc.Cmd -eq '/a'){ $StatMinCmd } else { $StatMinOutros }
      $amt = [Math]::Min($p, $faltaEtapa)
      # se o que falta pra fechar a etapa e menor que o minimo por comando, passa um pouco da meta (limitado pelo cap):
      # senao a etapa inteira TRAVA por causa de um atributo faltando <1000, e os pontos ficam empilhando pra sempre
      if($amt -lt $minCmd){ $amt = [Math]::Min($p, [Math]::Min($minCmd, $faltaCap)) }
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
    $script:ptsNeeded = Points-Needed $st
    if($script:ptsNeeded -le 0){ if($script:modo -eq 'joias'){ Log "stats: atributos no maximo, mas o modo JOIAS nao da /darmr"; return }; if($script:phase -eq 'warmup'){ Log "stats: atributos no maximo durante o warmup, seguindo sem /darmr"; return }; Log "stats: F=$($st.For) A=$($st.Agi) V=$($st.Vit) E=$($st.Ene) -> TODOS no maximo, /darmr"; Master-Reset; return }
    $p = [int]$st['Pts']; $script:ptsLeft = $p
    # O jogo SO mostra a linha "Pontos" quando ha pontos a distribuir (o print do painel confirma: Forca/Agilidade/
    # Vitalidade/Energia aparecem, "Pontos" nao). Entao Pts=-1 quase sempre significa ZERO, nao erro de leitura.
    if($p -lt 0){ Log "stats: F=$($st.For) A=$($st.Agi) V=$($st.Vit) E=$($st.Ene) - sem linha de Pontos (0 a distribuir)"; return }
    if($p -lt $StatMinAvail){ return }   # nada relevante a distribuir agora
    if($p -eq $prevP){ $stuck++ } else { $stuck = 0 }; $prevP = $p
    if($stuck -ge 2){ Log "stats: $p pontos nao baixam (faltam $($script:ptsNeeded) pontos pro cap). Parei pra nao repetir a toa."; return }
    $stage = Stat-Stage $st
    Log "stats: $p pontos | etapa $stage | F=$($st.For) A=$($st.Agi) V=$($st.Vit) E=$($st.Ene) | faltam $($script:ptsNeeded) pro cap"
    $plano = Plan-Stats $st $p
    if($plano.Count -eq 0){
      if($p -gt $StatMaxLeftover){ Log "stats: ALERTA - $p pontos sobrando (limite $StatMaxLeftover) e nao consigo gastar nenhum. F=$($st.For) A=$($st.Agi) V=$($st.Vit) E=$($st.Ene)"; Notify "MudinhoX" "$p pontos parados e nao consigo distribuir. Da uma olhada." }
      else { Log "stats: nada a distribuir agora ($p pontos; minimo $StatMinCmd por comando)" }
      return
    }
    Log "stats: plano ($($plano.Count) comandos): $($plano -join ' | ')"
    foreach($cmd in $plano){   # acumula pra metrica de pontos/h e marca que houve progresso
      if($script:stop -or -not (Send-Chat $cmd)){ break }
      $script:ptsSent += [int](($cmd -split " ")[1]); $script:ptsLastGain = Get-Date; $script:semProgresso = 0
    }
    Wait $StatRoundSec
  }
}
function Tick-Stats {   # so roda enquanto upa (nunca durante captcha)
  if((Get-Date) -lt $script:statDue){ return }
  Distribute-Points
  $script:statDue = (Get-Date).AddSeconds((Jit $StatEverySec))
}
$script:lvlPrev = $null; $script:lvlChangedAt = Get-Date; $script:lvlLogged = $null
function Check-Progress([int]$lvl, $img){   # level parado: se saiu do spot, re-teleporta (retorna $false p/ reiniciar o ciclo); se esta no spot parado, religa helper (miss infinito). $true = segue normal
  if($lvl -ne $script:lvlPrev){ $script:lvlPrev = $lvl; $script:lvlChangedAt = Get-Date; return $true }
  if(((Get-Date) - $script:lvlChangedAt).TotalSeconds -lt $StallSec){ return $true }
  $script:lvlChangedAt = Get-Date
  if(-not (In-Farm $img)){ Log "level parado e fora do spot: re-teleportando"; if(Warp-To-Spot){ Start-Helper }; return $false }
  Log "level parado ha $StallSec s no spot (miss infinito): ESC + pausa + anda + despausa"
  Tag-Ciclo 'stall'
  Close-Popup   # se o que travou foi uma janela/modal aberta por acidente, andar nao resolve - ESC resolve
  $null = Click-Client $PlayBtn.X $PlayBtn.Y; Wait 2   # pausa o helper
  Walk-Forward                                          # anda um pouco (desbuga o miss infinito)
  Start-Helper; $true                                   # religa o ataque
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
    2 { Log "humano: mexe o mouse"; $o = Client-Origin; 1..(Get-Random -Minimum 3 -Maximum 8) | % { [W]::SetCursorPos($o.X + (Get-Random -Maximum $c.R), $o.Y + (Get-Random -Maximum $c.B)) | Out-Null; Start-Sleep -Milliseconds (Get-Random -Minimum 150 -Maximum 600) } }
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
function Ocr-Status($img){ @((Ocr-Bitmap $img).Lines | % { $_.Words }) }
function Read-Status {   # abre a janela de status (C), le os 4 atributos + pontos, fecha. @{For;Agi;Vit;Ene;Pts} ou $null
  $prev = Focus-Game; if(-not $script:gameFg){ Restore-Focus $prev; return $null }
  Close-Chat; $out = $null
  for($try = 0; $try -lt 6; $try++){
    # C ALTERNA: tentativa par aperta, impar le sem apertar (senao uma leitura ruim FECHA a janela e ele alterna pra sempre).
    # 900ms e o tempo que a janela precisa pra aparecer - cortei pra 350 quando otimizei o tickrate e o "nao consegui ler o status" virou constante.
    if($try % 2 -eq 0){
      $null = Focus-Game   # reafirma o foco ANTES de cada tecla: so checar no inicio nao basta - se a sua janela volta, o C vai pra ELA e o status nunca abre (era a causa das falhas)
      if(-not $script:gameFg){ Log "status: jogo perdeu o foco, nao vou apertar C"; Wait 1; continue }
      Press-Vk $StatusKey $HotkeyHoldMs; Start-Sleep -Milliseconds 900
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
      New-Item -ItemType Directory -Force $CaptchaShotDir | Out-Null; $img.Save((Join-Path $CaptchaShotDir 'status_ultimo.png')) | Out-Null; $img.Dispose()
      Press-Vk $StatusKey $HotkeyHoldMs; Start-Sleep -Milliseconds 300   # fecha
      $miss = @('For','Agi','Vit','Ene') | ? { -not $v.ContainsKey($_) }
      if($miss){ Log ("status: nao li " + ($miss -join ',') + " (li " + (($v.GetEnumerator() | % { "$($_.Key)=$($_.Value)" }) -join ',') + "). Print em captcha\status_ultimo.png") } else { $out = $v }
      break
    }
    if($try -eq 5){   # desistiu: salva a tela pra dar pra ver se a janela ESTAVA aberta (OCR falhou) ou nao abriu mesmo (tecla C engolida)
      New-Item -ItemType Directory -Force $CaptchaShotDir | Out-Null
      $img.Save((Join-Path $CaptchaShotDir 'status_falhou.png')); Log "status: nao abriu em 6 tentativas. Print em captcha\status_falhou.png"
    }
    $img.Dispose(); Wait 1   # nao abriu (tecla ignorada logo apos reset): tenta de novo
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
    if($img){ $img.Dispose() }
    if($btn){ $script:viuLogin = $true }   # confirmou que estava FORA do jogo (nao so que o play sumiu por um loading)
    if($btn -and $btn.X -lt 0){   # reconheci a tela (tem "CRIAR NOVA CONTA"/"Sair") mas nao sei em que botao clicar: JAMAIS chutar coordenada aqui
      Notify "MudinhoX" "Estou na tela de servidor/login e nao sei qual botao clicar. Entra manualmente (ou ajuste `$LoginServerWords)."
      Wait 30; continue
    }
    if(-not $btn){   # nao reconheci nada: pode ser so tela de loading. So usa a coordenada de config apos insistir
      if($i -lt 3){ Log "tela de login: nao achei o botao ainda, esperando"; Wait 5; continue }
      $btn = $LoginBtn
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
    $script:mrs++
    $dur = [Math]::Round(((Get-Date) - $script:mrStart).TotalHours, 2); $script:mrStart = Get-Date
    Log "== MASTER RESET #$($script:mrs) FEITO (levou ${dur}h, $($script:resets) resets) =="   # o marco que interessa
    Notify "MudinhoX" "Master reset #$($script:mrs) feito em ${dur}h."
    $script:resets = 0; $script:ptsSent = 0; $script:runStart = Get-Date; $script:ativoSeg = 0   # zera pra medir o proximo MR limpo
    $script:phase = 'warmup'; $script:warmupCount = 0; Save-Estado; $script:restartCycle = $true; Log "modo warmup ($WarmupCmd ate $WarmupResets resets)"
  }
}
function Walk-Forward {   # ~4 passos numa direcao aleatoria. SO usado pra desbugar o miss infinito (o passeio pos-warp foi removido a pedido do usuario)
  $h = Get-Game; $c = New-Object W+RECT; [W]::GetClientRect($h,[ref]$c) | Out-Null
  $ang = Get-Random -Minimum 0.0 -Maximum 6.2832; $dx = [int]($WalkDist * [Math]::Cos($ang)); $dy = [int]($WalkDist * 0.75 * [Math]::Sin($ang))   # isometrico: vertical mais curto
  Log "andando 4 passos ($dx,$dy)"; $null = Click-Client ([int]($c.R/2)+$dx) ([int]($c.B/2)+$dy); Wait 2.5
}
function Wait-Map([string]$want,[double]$maxSec){   # espera ATE o mapa mudar, em vez de dormir o tempo cravado.
  $fim = (Get-Date).AddSeconds($maxSec)               # 18s dos 88s do ciclo eram Start-Sleep fixo: ~12s por ciclo recuperaveis (13 min por MR)
  do {
    Wait 1
    $m = Read-Map $null
    if($want){ if(Same-Map $m $want){ return $m } } elseif($m){ return $m }
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
    $now = Wait-Map $want $WarpWaitSec   # chega e segue; nao dorme os 9s inteiros
    if(Same-Map $now $want){ $script:farmMap = $now; Log "no spot (mapa: $now, fase: $($script:phase))"; return $true }   # chegou no spot certo
    if($now){
      Tag-Ciclo 'warp'; Log "nao teleportou pro spot certo (mapa: '$now', esperado '$want', antes '$before'), tentativa $t/$WarpTries ($cmd)"
X   # le a resposta do servidor e fotografa na PRIMEIRA falha (a mensagem some rapido)
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
    if($st -eq 'stopped'){ Log "clicando play ($($i+1)/$PlayTries)"; $null = Click-Client $PlayBtn.X $PlayBtn.Y; Wait 2.5; continue }
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
  Wait 1.5
  $img = Capture-Raw
  $ws = Screen-Words $img
  $ok = [bool]($ws | ? { $_.Text -match $InvMenuAncora })   # o menu tem varios itens conhecidos; se nenhum aparece, nao e o menu
  $item = $ws | ? { $_.Text -match $InvMenuWords } | select -First 1
  $img.Dispose()
  if(-not $ok -or -not $item){
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
  $null = Click-Client $npc.X $npc.Y -KeepFocus; Wait 2
  $img = Capture-Raw
  $menu = Screen-Words $img | ? { $_.Text -match $MixMenuWords } | sort { $_.BoundingRect.Y } | select -Last 1   # o de cima e o TITULO da janela; o botao e o de baixo
  $img.Dispose()
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
  if(-not (Send-Chat $MixCmd)){ return $false }
  Wait $WarpWaitSec
  $prev = Focus-Game; if(-not $script:gameFg){ Restore-Focus $prev; return $false }
  try {
    $mixados = 0
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
      if(-not $verde){ Log "mix: nenhuma opcao verde sobrou ($mixados mixados)"; break }
      $c = Word-Center $verde.W
      # print ANTES de clicar, igual ao captcha: fica o registro de qual opcao estava verde e onde o bot clicou
      New-Item -ItemType Directory -Force $CaptchaShotDir | Out-Null
      $shot = Join-Path $CaptchaShotDir ("mix_{0}_{1}.png" -f (Get-Date -Format 'yyyyMMdd_HHmmss'), $verde.J.Name)
      $imgS = Capture-Raw; try { $imgS.Save($shot) } catch {}; $imgS.Dispose()
      Log "mix: $($verde.J.Name) verde em ($($c.X),$($c.Y)), clicando. Print: $(Split-Path $shot -Leaf)"
      $null = Click-Client $c.X $c.Y -KeepFocus
      Wait 1.5
      # Clicar na joia abre um SEGUNDO dialogo ("Mixar 16 Jewel of Life / Deseja continuar?" com CONFIRMAR e CANCELAR).
      # O bot nao clicava em CONFIRMAR e ficava travado nele - era o travamento que o usuario reportou.
      $img2 = Capture-Raw
      $conf = Screen-Words $img2 | ? { $_.Text -match $MixConfirmWords } | select -First 1
      $img2.Dispose()
      if(-not $conf){
        Log "mix: cliquei em $($verde.J.Name) mas nao achei o botao CONFIRMAR - parando pra nao travar"
        Notify "MudinhoX" "O mix abriu um dialogo que eu nao reconheci. Confirma na mao e clique RETOMAR."
        $null = Save-Shot 'mix_sem_confirmar.png'
        break
      }
      $cc = Word-Center $conf
      Log "mix: confirmando em ($($cc.X),$($cc.Y))"
      $null = Click-Client $cc.X $cc.Y -KeepFocus; $mixados++
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
$script:invDue = (Get-Date).AddSeconds($InvCheckSec); $script:mixNow = $false; $script:semPlay = 0; $script:invFalhas = 0; $script:invDesligado = $false
function Tick-Inventory {   # de tempos em tempos checa o inventario; cheio (ou botao MIXAR) -> vai mixar e reinicia o ciclo (volta pro spot)
  if(-not $script:mixNow){
    if((Get-Date) -lt $script:invDue){ return }
    $script:invDue = (Get-Date).AddSeconds((Jit $InvCheckSec))
    $free = Inv-Free
    if($free -lt 0){ return }
    Log "inventario: $free celulas livres"
    if($free -ge $InvFreeMin){ return }
  }
  $script:mixNow = $false; $script:invDue = (Get-Date).AddSeconds((Jit $InvCheckSec))
  $null = Mix-Jewels
  $script:ptsLastGain = Get-Date   # mixar tambem nao distribui pontos: nao deixa o watchdog de progresso contar esse tempo
  $script:restartCycle = $true   # volta pro spot pelo caminho normal (warp + andar + play)
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
  if($m -match $MsgGoldWords){ Log "evento dos dragoes no chat (use o botao DRAGOES DOURADOS se quiser ir)" }
  elseif($m -match $MsgInvWords){ Log "jogo avisou inventario cheio -> vou mixar"; $script:mixNow = $true }
}
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
    # Reiniciar o PROPRIO processo resolve o que reiniciar o ciclo nao resolve (estado interno ruim) e ainda
    # recarrega o script - se houver correcao nova no disco, ela entra. O processo ja e elevado, entao o filho
    # nasce elevado SEM pedir UAC de novo.
    Log "sem progresso $($script:semProgresso)x seguidas: REINICIANDO O PROPRIO BOT"
    Notify "MudinhoX" "Sem progresso $($script:semProgresso)x seguidas. Reiniciando o bot sozinho."
    Save-Estado
    try { Start-Process powershell -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-WindowStyle","Hidden","-File","`"$PSCommandPath`"" | Out-Null } catch { Log "nao consegui relancar: $_" }
    Remove-Item $HeartbeatFile -ErrorAction SilentlyContinue   # libera pro novo processo assumir
    $script:stop = $true; return
  }
  Notify "MudinhoX" "Sem ganhar pontos ha $SemProgressoMin min. Reiniciando o ciclo - da uma olhada se repetir."
  $script:restartCycle = $true
}
function Ciclo-Joias {   # MODO JOIAS: farma no spot ate encher o inventario, vai mixar, volta a farmar. Nao reseta nem da MR.
  $script:restartCycle = $false
  Hold-Focus
  try { $ok = Warp-To-Spot; if($ok){ Start-Helper; $script:lvlChangedAt = Get-Date } } finally { Release-Focus }
  if(-not $ok){ Wait 15; return }
  $fim = (Get-Date).AddMinutes($JoiasFarmMax)
  $cheio = $false
  $script:invDue = Get-Date   # checa o inventario JA na primeira leitura: se ja esta cheio, nao faz sentido farmar 5 min antes de olhar
  Log "joias: farmando em $WarpCmd ate encher (ou $JoiasFarmMax min)"
  do {
    Wait (Poll-Interval); Bater-Heartbeat
    Hold-Focus
    try {
      $img = Capture-Game
      if($img){
        if(-not (Handle-Captcha $img)){
          $lvl = Read-Level $img
          # No modo joias nao ha reset, entao no level MAXIMO o level nunca muda e o detector de miss infinito
          # dispararia a cada $StallSec pausando o farm a toa (visto no log: 2 disparos em 40s, level 400 fixo).
          if($null -ne $lvl -and $lvl -lt $LevelMaximo){ if(-not (Check-Progress $lvl $img)){ $img.Dispose(); continue } }
          else { $script:lvlChangedAt = Get-Date }
          Tick-Stats            # continua distribuindo pontos (o /darmr fica bloqueado neste modo)
          Tick-Msgs $img        # "inventario cheio" no chat liga $script:mixNow
          Tick-Human
          if($script:mixNow){ $script:mixNow = $false; $cheio = $true; Log "joias: inventario cheio (aviso do jogo)" }
          elseif(-not $script:invDesligado -and (Get-Date) -ge $script:invDue){   # NAO a cada leitura: abrir/fechar o inventario a cada poll seria absurdo
            $script:invDue = (Get-Date).AddSeconds((Jit $InvCheckSec))
            $free = Inv-Free
            # A contagem so e confiavel com a grade bem alinhada, e a ancora (titulo) oscila ate 37px. Entao ela
            # so CONFIRMA cheio (poucas livres); nunca serve pra dizer "ainda tem espaco" e adiar o mix.
            if($free -ge 0){ Log "joias: $free celulas livres (contagem aproximada)"; if($free -lt $InvFreeMin){ $cheio = $true } }
          }
        }
        $img.Dispose()
      }
    } finally { Release-Focus }
  } until ($cheio -or (Get-Date) -ge $fim -or $script:stop -or $script:restartCycle -or $script:modo -ne 'joias')
  if($script:stop -or $script:modo -ne 'joias'){ return }
  if(-not $cheio){ Log "joias: $JoiasFarmMax min de farm, indo mixar mesmo assim (sem deteccao de inventario cheio)" }
  Hold-Focus; try { $null = Mix-Jewels } finally { Release-Focus }
  $script:ptsLastGain = Get-Date   # mixar nao distribui pontos: nao deixa o watchdog de progresso contar esse tempo
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
      if($comSpot){ Ok 'esta no spot da fase atual' (Same-Map $mapa (Spot-Map)) "mapa '$mapa', esperado '$(Spot-Map)'" }
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
    if($free -ge 0){ Log "       $free celulas livres (mixa abaixo de $InvFreeMin)" }
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
  Log "ja existe um bot rodando (heartbeat fresco). Saindo pra nao duplicar."
  if($script:ui){ $script:ui.Dispose() }; exit
}
Remove-Item $StopFile -ErrorAction SilentlyContinue; Bater-Heartbeat; Log "iniciando"
try {   # preflight no start: 10s conferindo tudo evita a noite inteira perdida por algo obvio. Nao BLOQUEIA (o spot nem e checado, o bot ainda vai warpar)
  Log "preflight de inicializacao:"
  $pf = Run-Preflight $false
  if($pf){ Notify "MudinhoX" "$pf verificacao(oes) falharam no start - veja o log. O bot vai tentar rodar mesmo assim." }
} catch { Log "preflight falhou: $_" }
Load-Estado   # retoma fase/warmup/modo de onde parou (o warmup.flag abaixo ainda tem prioridade)
if($script:ui){   # botoes tem que refletir o modo retomado do estado.txt
  if($script:modo -eq 'joias'){
    $script:btnMix.Text = 'MODO JOIAS (ligado)'; $script:btnMix.BackColor = 'ForestGreen'
    Log "retomando em MODO JOIAS: farma em $WarpCmd ate encher, mixa no $MixCmd, repete"
  } elseif($script:modo -eq 'dragoes'){
    $script:btnGold.Text = 'MODO DRAGOES (ligado)'; $script:btnGold.BackColor = 'ForestGreen'
    Log "retomando em MODO DRAGOES: so caca em $GoldCmd"
  }
}
if(Test-Path $WarmupFile){ Remove-Item $WarmupFile -ErrorAction SilentlyContinue; $script:phase = 'warmup'; $script:warmupCount = 0; Save-Estado; Log "iniciando em modo warmup (pos-MR manual): $WarmupCmd ate $WarmupResets resets" }
while(-not $script:stop){   # envelope: se o cliente cair, o catch espera ele voltar e o ciclo recomeca aqui (antes o script terminava)
try {
while($true){
  Pause-Gate
  if($script:modo -eq 'joias'){ Ciclo-Joias; continue }       # farma ate encher, mixa, repete. Sem reset/darmr.
  if($script:modo -eq 'dragoes'){ Ciclo-Dragoes; continue }   # so caca. Sem inventario, sem atributos, sem reset/darmr.
  if($script:mixNow){ Hold-Focus; try { Tick-Inventory } finally { Release-Focus } }   # botao MIXAR JOIAS: atende ANTES do warp (senao so era visto la dentro do loop de farm, e o bot parecia ignorar o botao)

  $script:restartCycle = $false   # comecando um ciclo novo (botoes de fase ja aplicaram phase/forceMR)
  Hold-Focus; try { $warpOk = Warp-To-Spot; if($warpOk){ Start-Helper; $script:lvlChangedAt = Get-Date; if($script:forceMR){ $script:forceMR = $false; $script:statDue = Get-Date; Log "forcando distribuicao + MR" } } } finally { Release-Focus }
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
            if(-not (Check-Progress $lvl $img)){ $img.Dispose(); continue }
            # perto do alvo o poll e de 2s: logar todo tick enche o arquivo e atrapalha achar problema. So loga salto real ou queda (reset)
            if($null -eq $script:lvlLogged -or $lvl -lt $script:lvlLogged -or ($lvl - $script:lvlLogged) -ge $LogLevelDelta){ Log "level: $lvl"; $script:lvlLogged = $lvl }
          }
          Tick-Stats; Tick-Inventory; Tick-Msgs $img; Tick-Progresso; Tick-Human
        }
        $img.Dispose()
      }
    } finally { Release-Focus }
  } until (($null -ne $lvl -and $lvl -ge $TargetLevel) -or $script:restartCycle)
  # gasta os pontos ANTES de resetar: assim nunca sobra mais que o ganho de um reset (~2000) alem do necessario, e o /darmr sai assim que fecha o cap
  # se ainda sobrar mais de $StatMaxLeftover, tenta de novo (leitura ruim do OCR costuma resolver na releitura) antes de gerar mais 2000 pontos com o reset
  for($d = 0; $d -lt 3 -and -not $script:restartCycle; $d++){
    Hold-Focus; try { Distribute-Points } finally { Release-Focus }
    if($script:ptsLeft -le $StatMaxLeftover){ break }
    Log "stats: ainda sobram $($script:ptsLeft) pontos (limite $StatMaxLeftover), segurando o reset e tentando de novo ($($d+1)/3)"
    Wait 3
  }
  if($script:restartCycle){ $script:restartCycle = $false; Close-Popup; Log "recomecando ciclo (pos-/darmr ou pos-mix, fase $($script:phase))"; continue }   # /darmr acabou de re-logar na cidade: nao reseta, vai direto pro warp da fase

  # reset: espera captcha (resolve) ou level cair
  Hold-Focus; try { while(-not (Send-Chat "/resetar")){ Release-Focus; Wait 10; Hold-Focus } } finally { Release-Focus }
  $sent = Get-Date; $resends = 0; $warned = $null; $inicio = Get-Date
  $resetOk = $false
  do {
    Wait 4; $lvl = $null
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
  $script:resets++
  $agora = Get-Date
  if($script:ultimoReset){ $seg = [int]($agora - $script:ultimoReset).TotalSeconds; $tg = ($script:tagsCiclo -join "+"); $script:ciclos = @(@($script:ciclos) + $(if($tg){"${seg}:$tg"}else{"$seg"}) | select -Last $CapCiclosMax) }
  $script:tagsCiclo = @()   # ciclo novo comeca sem etiqueta
  $script:ultimoReset = $agora
  Log "reset feito, recomecando"
  Tick-AutoTune
  Save-Estado   # metricas do MR sobrevivem a reinicio do bot (medir um MR leva horas)
  if(($script:resets % $MetricsEvery) -eq 0){ Metrics }
  $null = Wait-Map '' 8   # espera o mapa RENDERIZAR (o jogo ignora teclas durante o teleporte); segue assim que ler, em vez de dormir 8s
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
      if(Get-Process mudx -ErrorAction SilentlyContinue | ? { $_.MainWindowHandle -ne 0 }){
        Log "jogo voltou: esperando a tela carregar e retomando"; Wait 15
        Hold-Focus; try { $null = Enter-Game 'jogo reaberto' } finally { Release-Focus }   # pode ter voltado na tela de login
        break
      }
      if(((Get-Date) - $avisou).TotalSeconds -ge $RenotifySec){ Notify "MudinhoX" "Ainda esperando o jogo abrir."; $avisou = Get-Date }
    }
  } else { Log "ERRO: $_"; Notify "MudinhoX RPA parou" "$_"; Wait 30; $script:stop = $true }   # erro que nao seja o jogo fechado: para de verdade (nao entra em loop de erro)
}
}
Check-Stop
