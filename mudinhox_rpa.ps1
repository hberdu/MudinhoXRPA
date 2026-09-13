<#
  MudinhoX RPA - loop: /s18 -> play (MU Helper) -> espera level 350 -> /resetar -> repete.
  Stats: /f, /a, /e em ciclo, valor escala com os levels ganhos (nunca repete). Atributos cheios -> /darmr e entra de novo.
  Level parado (miss infinito) -> religa o helper. De vez em quando faz algo "humano". Captcha: resolve sozinho (compara imagens);
  se nao tiver certeza, toast + beep e espera voce.

  Uso:   duplo clique em "MudinhoX RPA.cmd"  (abre janelinha com log e botao PARAR; pede admin porque o jogo roda como admin)
         parar por fora: crie o arquivo stop.flag na pasta. Log completo em rpa.log.
         powershell -ExecutionPolicy Bypass -File .\mudinhox_rpa.ps1 -Check              (le level/botao/captcha, nao clica)
         powershell -ExecutionPolicy Bypass -File .\mudinhox_rpa.ps1 -TestImage x.png    (testa solver num print salvo)
  Requisito: o jogo precisa estar visivel na hora da leitura. Se outra janela estiver na frente, o bot traz o jogo
  por ~1s, le, e devolve o foco pra janela que voce estava usando (nesse caso le a cada 60s em vez de 10s).
#>
param([switch]$Check, [string]$TestImage)

# ---------- CONFIG (coordenadas relativas a area cliente do jogo, 1920x1009) ----------
$TargetLevel   = 350
$PlayBtn       = @{ X = 77;   Y = 33 }                     # centro do botao play/pause (canto sup. esquerdo)
$LevelBox      = @{ X = 1080; W = 140; H = 40; YFromBottom = 82 }    # numero do level na barra inferior; Y medido a partir da BASE da area cliente (aguenta resolucao/altura diferente)
$PollSec       = 10      # intervalo de leitura do level com o jogo na frente
$PollBgSec     = 60      # intervalo quando outra janela esta na frente (cada leitura rouba o foco por ~1s)
$WarpCmd       = '/s18'   # comando de teleporte pro spot de farm normal (troque aqui se mudar de spot)
$WarmupCmd     = '/losttower7'   # apos /darmr o personagem volta fraco em Lorencia: farma AQUI (Lost Tower 7) ate juntar os primeiros resets
$WarmupResets  = 10          # quantos resets fazer no modo warmup (pos-darmr) antes de voltar ao spot normal ($WarpCmd)
$WarpMap       = 'stad'      # nome esperado do mapa do /s18 (Stadium), 4 primeiras letras. So conta "no spot" se o mapa bater com este
$WarmupMap     = 'lost'      # nome esperado do mapa do /losttower7 (Lost Tower). Evita aceitar mapa errado (ex AIDA) como spot
$WarpWaitSec   = 9       # espera apos o teleporte (dar tempo do mapa trocar)
$ResetWaitSec  = 15      # sem captcha e level ainda alto apos N seg -> reenvia /resetar
$ResetRetries  = 2       # quantas vezes reenvia /resetar antes de avisar
$RenotifySec   = 120     # re-avisa a cada N segundos enquanto espera humano
$StatCmds      = @(      # ciclo: /f apos 3min, /a apos +2min, /v apos +2min, /e apos +3min, repete. Atributo ja cheio e pulado.
  @{ Cmd = '/f'; AfterSec = 180; Key = 'For' },   # /darmr exige TODOS os atributos no maximo, entao vitalidade tambem entra no ciclo
  @{ Cmd = '/a'; AfterSec = 120; Key = 'Agi' },
  @{ Cmd = '/v'; AfterSec = 120; Key = 'Vit' },
  @{ Cmd = '/e'; AfterSec = 180; Key = 'Ene' }
)
$StatMin = 500; $StatMax = 3000   # StatMax = teto por comando; StatMin so vale quando nao consegue ler os pontos (estimativa)
$StatMinAvail  = 50      # menos que isso de pontos disponiveis: nao distribui
$StatMinCmd    = 1000    # valor MINIMO por comando de stat. /a com valor pequeno (<100) teleporta pra AIDA; abaixo de 1000 o atributo nem recebe (fica pro proximo, com mais pontos)
$StatEverySec  = 90      # distribui os pontos a cada N seg enquanto upa (alem de logo apos cada reset)
$StatCol       = @{ X = 1155; Y = 108; W = 195; H = 380 }   # coluna da janela de status (rotulos+valores); OCR isolado dessa faixa le os 4 atributos + pontos
$PointsPerLevel = 4      # pontos de atributo por level  (calibrar pro servidor: "adicionou 2000, restam 48" no level 12 -> ~4/level)
$PointsPerReset = 2000   # pontos ganhos por reset       (idem). Valor do comando = pontos ganhos desde o ultimo comando * 0.55..1.0, nunca repete
$StatMaxValue  = 32767   # atributo cheio (cap real do servidor). /darmr SO funciona com Forca, Agilidade, Vitalidade E Energia TODOS = 32767; abaixo disso o jogo recusa ("precisa 32767 em todos status")
$StatusKey     = 0x43    # C = janela de status
$HotkeyHoldMs  = 150     # hotkey (C) segurada mais tempo que tecla de texto
$LoginBtn      = @{ X = 960; Y = 940 }    # botao pra entrar com o personagem apos /darmr (centro embaixo). Antes disso procura o texto abaixo por OCR
$LoginWords    = 'Entrar|Conectar|Iniciar|Jogar|Selecionar|Enter|Start|Login'
$ChatBox       = @{ X1 = 870; X2 = 1130; Y1FromBottom = 111; Y2FromBottom = 87 }   # bordas vermelhas da caixa de chat aberta; Y medido a partir da BASE da area cliente
$StallSec      = 75      # no spot com level parado N seg (miss infinito) -> pausa e religa o helper
$CityWords     = 'lorencia|noria|devias|elbeland|lorenmarket|karutan|elveland'   # mapas-cidade onde NAO se farma (personagem cai aqui apos reset). Qualquer outro mapa = spot de farm (ex Stadium do /s18)
# teleporte confirmado quando o mapa e um spot de farm (nao-cidade). $farmMap guarda o ultimo spot.
$MapLabel      = @{ X = 1690; Y = 68; W = 230; H = 30 }   # rotulo do minimapa
$WarpTries     = 4       # reenvia o comando de warp ate N vezes se o mapa nao mudar, depois avisa e segue
$PlayTries     = 3       # clica no play ate N vezes; se nao ligar, para de clicar (nao insiste cego)
$HumanMinSec   = 120; $HumanMaxSec = 420   # a cada X seg (aleatorio) faz algo "humano": anda um pouco, abre/fecha janela, mexe o mouse
$LogFile       = Join-Path $PSScriptRoot 'rpa.log'
$StopFile      = Join-Path $PSScriptRoot 'stop.flag'
$WarmupFile    = Join-Path $PSScriptRoot 'warmup.flag'   # se existir no start, o bot comeca em modo warmup (/losttower7) — use apos dar MR manualmente
# Captcha: offsets a partir do centro do texto "Selecione a mesma imagem abaixo:" (achado por OCR)
$CapRefDy      = -80                          # imagem de referencia (acima do texto)
$CapRowDy      = 80, 210                      # 2 linhas de opcoes
$CapColDx      = -260, -130, 0, 130, 260      # 5 colunas
$CapConfirmDy  = 355                          # botao Confirmar
$CapMaxTries   = 2                            # errou N vezes -> fecha o jogo (mudx.exe) e para; nao arrisca a proxima
$CapSelHalf    = 61                           # distancia do centro ate a borda vermelha (3px) da opcao selecionada; varre +-5px
$WalkDist      = 140                          # apos /icarus anda ~4 passos (pixels a partir do centro) numa direcao aleatoria a cada chegada, antes do play
$CapConfidence = 0.5                          # melhor precisa ser < 50% do segundo, senao nao chuta
$CaptchaShotDir = Join-Path $PSScriptRoot 'captcha'   # print salvo aqui a cada captcha
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
try { $script:logW = New-Object System.IO.StreamWriter([System.IO.FileStream]::new($LogFile, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)); $script:logW.AutoFlush = $true } catch {}
function Log($m){
  $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m; Write-Host $line
  if($script:logW){ try { $script:logW.WriteLine($line) } catch {} } else { try { Add-Content -Path $LogFile -Value $line -Encoding UTF8 } catch {} }
  if($script:ui -and -not $script:ui.IsDisposed){ $script:status.Text = $m; $script:logBox.AppendText("$line`r`n"); [System.Windows.Forms.Application]::DoEvents() }
}
function Check-Stop { if(-not $script:stop -and (Test-Path $StopFile)){ $script:stop = $true; Remove-Item $StopFile -ErrorAction SilentlyContinue }; if($script:stop){ Log "parado pelo usuario"; if($script:logW){ $script:logW.Dispose() }; if($script:ui){ $script:ui.Dispose() }; exit } }
function Pause-Gate {   # congela o bot enquanto PAUSADO e LIBERA o foco pra voce mixar joias no NPC; re-adquire ao retomar
  if(-not $script:paused){ return }
  $wasHeld = $script:focusHeld; if($wasHeld){ Release-Focus }   # solta o jogo pra voce interagir
  while($script:paused -and -not $script:stop){ if($script:ui){ [System.Windows.Forms.Application]::DoEvents() }; Check-Stop; Start-Sleep -Milliseconds 200 }
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
  $f.StartPosition = 'Manual'; $f.Location = New-Object System.Drawing.Point(([System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea.Width - 410), 300)
  $script:status = New-Object System.Windows.Forms.Label; $script:status.SetBounds(10,12,160,22); $script:status.Text = 'iniciando...'
  $script:btnPause = New-Object System.Windows.Forms.Button; $script:btnPause.SetBounds(175,6,100,28); $script:btnPause.Text = 'PAUSAR'; $script:btnPause.BackColor = 'Goldenrod'
  $btn = New-Object System.Windows.Forms.Button; $btn.SetBounds(280,6,100,28); $btn.Text = 'PARAR'; $btn.BackColor = 'IndianRed'
  # linha 2: comando manual de fase
  $script:btnWarmup = New-Object System.Windows.Forms.Button; $script:btnWarmup.SetBounds(10,40,122,32);  $script:btnWarmup.Text = "Warmup LT7`n(10 resets)"; $script:btnWarmup.BackColor = 'SteelBlue'
  $script:btnNormal = New-Object System.Windows.Forms.Button; $script:btnNormal.SetBounds(137,40,122,32); $script:btnNormal.Text = "Normal /s18`n(ate MT)"; $script:btnNormal.BackColor = 'MediumSeaGreen'
  $script:btnMR     = New-Object System.Windows.Forms.Button; $script:btnMR.SetBounds(264,40,120,32);     $script:btnMR.Text = "Atribuir tudo`n+ MR"; $script:btnMR.BackColor = 'MediumPurple'
  $script:logBox = New-Object System.Windows.Forms.TextBox; $script:logBox.SetBounds(10,78,375,180); $script:logBox.Multiline = $true; $script:logBox.ReadOnly = $true; $script:logBox.ScrollBars = 'Vertical'
  $script:btnPause.Add_Click({ $script:paused = -not $script:paused; $script:btnPause.Text = $(if($script:paused){ 'RETOMAR' } else { 'PAUSAR' }); $script:btnPause.BackColor = $(if($script:paused){ 'ForestGreen' } else { 'Goldenrod' }); Log $(if($script:paused){ 'PAUSADO pelo usuario (mixe as joias; clique RETOMAR pra voltar)' } else { 'retomado pelo usuario' }) })
  $btn.Add_Click({ $script:stop = $true })
  $script:btnWarmup.Add_Click({ $script:phase = 'warmup'; $script:warmupCount = 0; $script:forceMR = $false; $script:restartCycle = $true; $script:paused = $false; $script:btnPause.Text = 'PAUSAR'; $script:btnPause.BackColor = 'Goldenrod'; Log "[BOTAO] modo WARMUP: /losttower7 ate $WarmupResets resets" })
  $script:btnNormal.Add_Click({ $script:phase = 'normal'; $script:forceMR = $false; $script:restartCycle = $true; $script:paused = $false; $script:btnPause.Text = 'PAUSAR'; $script:btnPause.BackColor = 'Goldenrod'; Log "[BOTAO] modo NORMAL: /s18 ate os atributos encherem" })
  $script:btnMR.Add_Click({ $script:forceMR = $true; $script:restartCycle = $true; $script:paused = $false; $script:btnPause.Text = 'PAUSAR'; $script:btnPause.BackColor = 'Goldenrod'; Log "[BOTAO] ATRIBUIR TUDO + MR" })
  $f.Add_FormClosing({ $script:stop = $true })
  $f.Controls.AddRange(@($script:status,$script:btnPause,$btn,$script:btnWarmup,$script:btnNormal,$script:btnMR,$script:logBox)); $f.Show(); $script:ui = $f
}

# ---------- janela do jogo / foco ----------
function Is-Admin { ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) }
function Game-IsAdmin { -not (Get-Process mudx -ErrorAction SilentlyContinue | select -First 1).Path }   # processo elevado nao expoe o Path pra processo comum
function Get-Game { $p = Get-Process mudx -ErrorAction SilentlyContinue | ? { $_.MainWindowHandle -ne 0 } | select -First 1; if(-not $p){ throw "MudinhoX (mudx.exe) nao esta rodando" }; $p.MainWindowHandle }
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
function Capture-Raw {   # bitmap da area cliente, sem mexer no foco (so chamar com o jogo na frente). Janelinha do bot fica preta (nao suja OCR/pixels)
  $h = Get-Game; $c = New-Object W+RECT; [W]::GetClientRect($h,[ref]$c) | Out-Null; $o = Client-Origin
  $b = New-Object System.Drawing.Bitmap($c.R,$c.B); $g = [System.Drawing.Graphics]::FromImage($b)
  $g.CopyFromScreen($o.X,$o.Y,0,0,$b.Size)
  if($script:ui -and -not $script:ui.IsDisposed){ $r = $script:ui.Bounds; $g.FillRectangle([System.Drawing.Brushes]::Black, $r.X-$o.X, $r.Y-$o.Y, $r.Width, $r.Height) }
  $g.Dispose(); $b
}
function Capture-Game {   # bitmap da area cliente, ou $null se o jogo nao ficou na frente (nunca le/clica em outra janela)
  $prev = Focus-Game
  if(-not $script:gameFg){ Restore-Focus $prev; Log "jogo nao esta na frente (outra janela ativa), pulando leitura"; return $null }
  $b = Capture-Raw; Restore-Focus $prev; $b
}

# ---------- input ----------
function Press-Vk([int]$vk,[int]$hold=40){ $sc = [W]::MapVirtualKey($vk,0); [W]::keybd_event($vk,$sc,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds $hold; [W]::keybd_event($vk,$sc,2,[UIntPtr]::Zero); Start-Sleep -Milliseconds 40 }
function Type-Text([string]$s){   # ~40ms hold + ~40ms gap por tecla (rapido; sobe se comecar a embaralhar)
  foreach($ch in $s.ToCharArray()){
    $k = [W]::VkKeyScan($ch); $vk = $k -band 0xFF; $shift = ($k -shr 8) -band 1
    if($shift){ [W]::keybd_event(0x10,0x2A,0,[UIntPtr]::Zero) }
    Press-Vk $vk 40
    if($shift){ [W]::keybd_event(0x10,0x2A,2,[UIntPtr]::Zero) }
  }
}
function Chat-Open($img){   # caixa de chat aberta = bordas vermelhas no topo e na base (Enter alterna abre/fecha, entao precisa saber o estado)
  $own = -not $img; if($own){ $img = Capture-Raw }
  $ok = $true
  foreach($yFromB in $ChatBox.Y1FromBottom,$ChatBox.Y2FromBottom){
    $y = $img.Height - $yFromB   # relativo a base da area cliente
    $red = 0; for($x = $ChatBox.X1; $x -le $ChatBox.X2; $x++){ $p = $img.GetPixel($x,$y); if($p.R -gt 150 -and $p.G -lt 100 -and $p.B -lt 100){ $red++ } }
    if($red -lt ($ChatBox.X2-$ChatBox.X1)/2){ $ok = $false }
  }
  if($own){ $img.Dispose() }; $ok
}
function Close-Chat { if(Chat-Open){ 1..30 | % { Press-Vk 0x08 }; Press-Vk 0x0D; Start-Sleep -Milliseconds 300 } }   # apaga residuo e fecha (Enter vazio fecha); chamar com o jogo na frente
function Send-Chat([string]$text){   # $false se o jogo nao ficou na frente (nao digita em outra janela)
  $prev = Focus-Game
  if(-not $script:gameFg){ Log "jogo nao esta na frente, nao enviei '$text'"; return $false }
  if(Chat-Open){ 1..30 | % { Press-Vk 0x08 } } else { Press-Vk 0x0D; Start-Sleep -Milliseconds 200 }   # ja aberta (residuo seu?) -> so apaga; fechada -> Enter abre
  Log "chat: $text"; Type-Text $text; Start-Sleep -Milliseconds 130; Press-Vk 0x0D
  Start-Sleep -Milliseconds 150; if(Chat-Open){ Press-Vk 0x0D }   # se continuou aberta apos enviar, Enter vazio fecha (senao letras viram hotkey)
  Restore-Focus $prev; $true
}
function Click-Client([int]$x,[int]$y,[switch]$KeepFocus){   # $false se o jogo nao ficou na frente. -KeepFocus: jogo ja esta na frente, nao mexe no foco (varios cliques em sequencia)
  if(-not $KeepFocus){ $prev = Focus-Game; if(-not $script:gameFg){ Log "jogo nao esta na frente, nao cliquei"; return $false } }
  $o = Client-Origin; [W]::SetCursorPos($o.X+$x,$o.Y+$y) | Out-Null; Start-Sleep -Milliseconds 150
  [W]::mouse_event(2,0,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 80; [W]::mouse_event(4,0,0,0,[UIntPtr]::Zero)
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
  $c = Crop-Bitmap $img $MapLabel.X $MapLabel.Y $MapLabel.W $MapLabel.H 4
  $t = (Ocr-Bitmap $c).Text; $c.Dispose(); if($own){ $img.Dispose() }
  ($t -replace '[^A-Za-z]','').ToLower()
}
$script:farmMap = ''; $script:phase = 'normal'; $script:warmupCount = 0; $script:restartCycle = $false; $script:forceMR = $false
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
function Save-CaptchaShot($img){
  New-Item -ItemType Directory -Force $CaptchaShotDir | Out-Null
  $f = Join-Path $CaptchaShotDir ("captcha_{0}.png" -f (Get-Date -Format 'yyyyMMdd_HHmmss')); $img.Save($f); Log "print salvo: $f"
}
$script:capTries = 0; $script:capNotified = $null
function Handle-Captcha($img){   # $true se captcha esta na tela (tentou resolver ou avisou humano)
  if(-not $img){ return $false }
  $a = Find-Captcha $img
  if(-not $a){ $script:capTries = 0; $script:capNotified = $null; return $false }
  if($script:capTries -ge $CapMaxTries){   # ja errou N vezes e o captcha continua na tela: fecha o jogo e para (nao arrisca mais uma)
    Log "captcha: errei $CapMaxTries vezes -> fechando o jogo (mudx.exe) e parando"
    Notify "MudinhoX: CAPTCHA" "Errei o captcha $CapMaxTries vezes. Fechei o jogo e parei o bot."
    Get-Process mudx -ErrorAction SilentlyContinue | Stop-Process -Force; if($script:ui){ $script:ui.Dispose() }; exit
  }
  Save-CaptchaShot $img
  $r = Solve-Captcha $img $a
  if($r -eq 'enviado'){ $script:capTries++; Log "captcha: tentativa $($script:capTries) enviada"; Wait 5; return $true }
  if($r -eq 'ambiguo' -and (-not $script:capNotified -or ((Get-Date) - $script:capNotified).TotalSeconds -ge $RenotifySec)){
    Notify "MudinhoX: CAPTCHA" "Nao tenho certeza da imagem. Resolve ai que o bot continua sozinho."; $script:capNotified = Get-Date
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
if(-not (Is-Admin)){
  try { Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`"" }
  catch { [System.Windows.Forms.MessageBox]::Show("Precisa rodar como administrador: o jogo roda como admin e senao o Windows bloqueia o teclado/mouse do bot. Abra de novo e aceite o UAC.", 'MudinhoX RPA') | Out-Null }
  exit
}

# ---------- loop principal ----------
$script:statIdx = 0; $script:statDue = (Get-Date).AddSeconds($StatCmds[0].AfterSec)
$script:lvlLast = $null; $script:ptsGained = 0; $script:statHist = @(); $script:statVals = $null
function Note-Level([int]$lvl){   # acumula pontos ganhos desde o ultimo comando de stat (level subiu, ou caiu = reset)
  if($null -eq $script:lvlLast){ $script:lvlLast = $lvl; return }
  if($lvl -ge $script:lvlLast){ $script:ptsGained += ($lvl - $script:lvlLast) * $PointsPerLevel }
  else { $script:ptsGained += $PointsPerReset + ([Math]::Max(0, $TargetLevel - $script:lvlLast) + $lvl) * $PointsPerLevel }
  $script:lvlLast = $lvl
}
function Uniq-Amt([int]$v){   # varia levemente pra nao repetir o mesmo valor (parecer humano), sem descer abaixo de $StatMinCmd
  for($i = 0; $i -lt 12 -and ($script:statHist -contains $v); $i++){ $v = [Math]::Max($StatMinCmd, $v - (Get-Random -Minimum 1 -Maximum 25)) }
  $script:statHist = @($script:statHist + $v | select -Last 60); $v
}
function Distribute-Points {   # le os 4 atributos + pontos e distribui de verdade. VALIDA os valores: os 4 no maximo -> /darmr. Distribui so nos que ainda faltam.
  $prevP = -1; $stuck = 0
  for($guard = 0; $guard -lt 15 -and -not $script:stop; $guard++){
    $st = Read-Status
    if(-not $st){ Log "stats: nao consegui ler o status"; return }
    $falta = @('For','Agi','Vit','Ene') | ? { [int]$st[$_] -lt $StatMaxValue }
    if($falta.Count -eq 0){ if($script:phase -eq 'warmup'){ Log "stats: atributos no maximo durante o warmup, seguindo sem /darmr"; return }; Log "stats: F=$($st.For) A=$($st.Agi) V=$($st.Vit) E=$($st.Ene) -> TODOS no maximo, /darmr"; Master-Reset; return }
    $p = [int]$st['Pts']
    if($p -lt 0){ Log "stats: F=$($st.For) A=$($st.Agi) V=$($st.Vit) E=$($st.Ene) (pontos ilegiveis)"; return }
    if($p -lt $StatMinAvail){ return }   # nada relevante a distribuir agora
    if($p -eq $prevP){ $stuck++ } else { $stuck = 0 }; $prevP = $p
    if($stuck -ge 2){ Log "stats: $p pontos nao baixam (faltam: $($falta -join ',')). Parei pra nao repetir a toa."; return }
    Log "stats: $p pontos | F=$($st.For) A=$($st.Agi) V=$($st.Vit) E=$($st.Ene) | distribuindo em: $($falta -join ',')"
    $enviados = 0
    foreach($k in @('For','Agi','Vit','Ene')){   # uma volta: manda so nos atributos que faltam
      if($falta -notcontains $k -or $script:stop){ continue }
      $sc = $StatCmds | ? { $_.Key -eq $k } | select -First 1
      $faltaCap = $StatMaxValue - [int]$st[$k]   # quanto falta pra fechar 32767 neste atributo
      $amt = [Math]::Min([int]$p, [Math]::Min([int][Math]::Ceiling($p / $falta.Count), $faltaCap))
      $fechando = ($amt -eq $faltaCap)   # este valor fecha exatamente o cap do atributo
      $piso = if($sc.Cmd -ne '/a' -and $fechando){ 1 } else { $StatMinCmd }   # so manda <1000 quando e pra FECHAR o cap (e nunca no /a, que teleporta pra AIDA)
      if($amt -lt $piso){ continue }
      $val = if($fechando -and $amt -lt $StatMinCmd){ $amt } else { Uniq-Amt $amt }   # fechando o cap: valor exato (sem jitter); senao varia (>=1000)
      $null = Send-Chat ("{0} {1}" -f $sc.Cmd, $val); $enviados++
    }
    if($enviados -eq 0){ Log "stats: nada a distribuir agora (restam $p pontos; /a espera >= $StatMinCmd)"; return }
    Wait 2
  }
}
function Tick-Stats {   # so roda enquanto upa (nunca durante captcha)
  if((Get-Date) -lt $script:statDue){ return }
  Distribute-Points
  $script:statDue = (Get-Date).AddSeconds($StatEverySec)
}
$script:lvlPrev = $null; $script:lvlChangedAt = Get-Date
function Check-Progress([int]$lvl, $img){   # level parado: se saiu do spot, re-teleporta (retorna $false p/ reiniciar o ciclo); se esta no spot parado, religa helper (miss infinito). $true = segue normal
  if($lvl -ne $script:lvlPrev){ $script:lvlPrev = $lvl; $script:lvlChangedAt = Get-Date; return $true }
  if(((Get-Date) - $script:lvlChangedAt).TotalSeconds -lt $StallSec){ return $true }
  $script:lvlChangedAt = Get-Date
  if(-not (In-Farm $img)){ Log "level parado e fora do spot: re-teleportando"; if(Warp-To-Spot){ Walk-Forward; Start-Helper }; return $false }
  Log "level parado ha $StallSec s no spot (miss infinito): pausa + anda + despausa"
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
function Read-Status {   # abre a janela de status (C), le os 4 atributos + pontos, fecha. @{For;Agi;Vit;Ene;Pts} ou $null
  $prev = Focus-Game; if(-not $script:gameFg){ Restore-Focus $prev; return $null }
  Close-Chat; $out = $null
  for($try = 0; $try -lt 4; $try++){
    Press-Vk $StatusKey $HotkeyHoldMs; Start-Sleep -Milliseconds 900
    $img = Capture-Raw
    $words = @((Ocr-Bitmap $img).Lines | % { $_.Words })
    if(Status-Open $words){
      $v = Parse-Attrs $words; $v['Pts'] = Get-Points $words
      for($k = 0; $k -lt 2 -and @('For','Agi','Vit','Ene' | ? { -not $v.ContainsKey($_) }).Count; $k++){   # faltou atributo: rele com a janela aberta e combina
        $img.Dispose(); Start-Sleep -Milliseconds 400; $img = Capture-Raw; $words = @((Ocr-Bitmap $img).Lines | % { $_.Words })
        $v2 = Parse-Attrs $words; foreach($kk in $v2.Keys){ if(-not $v.ContainsKey($kk)){ $v[$kk] = $v2[$kk] } }; if($v2.ContainsKey('Pts')){ $v['Pts'] = $v2['Pts'] } else { $v['Pts'] = Get-Points $words }
      }
      New-Item -ItemType Directory -Force $CaptchaShotDir | Out-Null; $img.Save((Join-Path $CaptchaShotDir 'status_ultimo.png')) | Out-Null; $img.Dispose()
      Press-Vk $StatusKey $HotkeyHoldMs; Start-Sleep -Milliseconds 300   # fecha
      $miss = @('For','Agi','Vit','Ene') | ? { -not $v.ContainsKey($_) }
      if($miss){ Log ("status: nao li " + ($miss -join ',') + " (li " + (($v.GetEnumerator() | % { "$($_.Key)=$($_.Value)" }) -join ',') + "). Print em captcha\status_ultimo.png") } else { $out = $v }
      break
    }
    $img.Dispose(); Wait 2   # nao abriu (tecla ignorada logo apos reset): tenta de novo
  }
  Restore-Focus $prev; $out
}
function Master-Reset {   # atributos cheios: /darmr -> tela de selecao -> clica pra entrar com o personagem -> volta pro loop
  if(-not (Send-Chat "/darmr")){ return }
  Notify "MudinhoX" "Atributos no maximo: mandei /darmr. Tentando entrar de novo com o personagem."
  Wait 10
  for($i = 0; $i -lt 12; $i++){
    $img = Capture-Game
    if($img -and (Get-HelperState $img) -ne 'unknown'){ $img.Dispose(); $script:phase = 'warmup'; $script:warmupCount = 0; $script:restartCycle = $true; Log "de volta no jogo -> modo warmup ($WarmupCmd ate $WarmupResets resets)"; return }   # botao play visivel = dentro do jogo (na cidade); recomeca o ciclo em vez de clicar play aqui
    $btn = $null
    if($img){
      $w = (Ocr-Bitmap $img).Lines | % { $_.Words } | ? { $_.Text -match "^($LoginWords)$" } | select -First 1
      if($w){ $btn = @{ X = [int]($w.BoundingRect.X + $w.BoundingRect.Width/2); Y = [int]($w.BoundingRect.Y + $w.BoundingRect.Height/2) } }
      $img.Dispose()
    }
    if(-not $btn){ $btn = $LoginBtn }
    Log "tela de login: clicando ($($btn.X),$($btn.Y))"; $null = Click-Client $btn.X $btn.Y; Wait 8
  }
  Notify "MudinhoX" "Nao consegui entrar de novo apos /darmr. Da uma olhada."
}
function Walk-Forward {   # ~4 passos apos o /icarus numa direcao aleatoria (varia a cada chegada), antes de ligar o helper
  $h = Get-Game; $c = New-Object W+RECT; [W]::GetClientRect($h,[ref]$c) | Out-Null
  $ang = Get-Random -Minimum 0.0 -Maximum 6.2832; $dx = [int]($WalkDist * [Math]::Cos($ang)); $dy = [int]($WalkDist * 0.75 * [Math]::Sin($ang))   # isometrico: vertical mais curto
  Log "andando 4 passos ($dx,$dy)"; $null = Click-Client ([int]($c.R/2)+$dx) ([int]($c.B/2)+$dy); Wait 2.5
}
function Warp-To-Spot {   # teleporta pro spot da fase atual (warmup=/losttower7, normal=/s18) e confirma pelo mapa. Sucesso = ja num mapa de farm ou chegou num. $false = desistiu
  $cmd = if($script:phase -eq 'warmup'){ $WarmupCmd } else { $WarpCmd }
  $want = Spot-Map
  $before = Read-Map $null
  if(Same-Map $before $want){ $script:farmMap = $before; Log "ja no spot (mapa: $before, fase: $($script:phase))"; return $true }   # ja no spot CORRETO da fase
  for($t = 1; $t -le $WarpTries; $t++){
    if(-not (Send-Chat $cmd)){ Wait 10; continue }
    Wait $WarpWaitSec
    $now = Read-Map $null
    if(Same-Map $now $want){ $script:farmMap = $now; Log "no spot (mapa: $now, fase: $($script:phase))"; return $true }   # chegou no spot certo
    Log "nao teleportou pro spot certo (mapa: '$now', esperado '$want', antes '$before'), tentativa $t/$WarpTries ($cmd)"
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
function Poll-Interval { if($script:gameWasFg){ $PollSec } else { $PollBgSec } }

Show-Ui
Remove-Item $StopFile -ErrorAction SilentlyContinue; Log "iniciando"
if(Test-Path $WarmupFile){ Remove-Item $WarmupFile -ErrorAction SilentlyContinue; $script:phase = 'warmup'; $script:warmupCount = 0; Log "iniciando em modo warmup (pos-MR manual): $WarmupCmd ate $WarmupResets resets" }
try {
while($true){
  Pause-Gate
  $script:restartCycle = $false   # comecando um ciclo novo (botoes de fase ja aplicaram phase/forceMR)
  Hold-Focus; try { $warpOk = Warp-To-Spot; if($warpOk){ Walk-Forward; Start-Helper; $script:lvlChangedAt = Get-Date; if($script:forceMR){ $script:forceMR = $false; $script:statDue = Get-Date; Log "forcando distribuicao + MR" } } } finally { Release-Focus }
  if(-not $warpOk){ Wait 15; continue }

  # upando: le level, checa captcha, manda stats (traz o jogo 1x por iteracao, devolve o foco pra sua janela no fim)
  do {
    Wait (Poll-Interval); $lvl = $null
    Hold-Focus
    try {
      $img = Capture-Game
      if($img){
        if(-not (Handle-Captcha $img)){
          $lvl = Read-Level $img
          if($null -ne $lvl){ Note-Level $lvl; if(-not (Check-Progress $lvl $img)){ $img.Dispose(); continue }; Log "level: $lvl" }
          Tick-Stats; Tick-Human
        }
        $img.Dispose()
      }
    } finally { Release-Focus }
  } until (($null -ne $lvl -and $lvl -ge $TargetLevel) -or $script:restartCycle)
  if($script:restartCycle){ $script:restartCycle = $false; Close-Popup; Log "recomecando ciclo (pos-/darmr, fase $($script:phase))"; continue }   # /darmr acabou de re-logar na cidade: nao reseta, vai direto pro warp da fase

  # reset: espera captcha (resolve) ou level cair
  Hold-Focus; try { while(-not (Send-Chat "/resetar")){ Release-Focus; Wait 10; Hold-Focus } } finally { Release-Focus }
  $sent = Get-Date; $resends = 0; $warned = $null
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
          if($null -ne $lvl){ Note-Level $lvl }
          if((Read-Map $img) -match $CityWords){ $resetOk = $true }   # char foi pra uma cidade = reset aconteceu (confirma na hora, sem depender de ler o level, que demora em Lorencia)
          if($null -ne $lvl -and $lvl -lt $TargetLevel){ $resetOk = $true }
          if(-not $resetOk -and $null -ne $lvl -and $lvl -ge $TargetLevel -and ((Get-Date) - $sent).TotalSeconds -ge $ResetWaitSec){
            if($resends -lt $ResetRetries){ $resends++; Log "reset nao aconteceu, reenviando"; if(Send-Chat "/resetar"){ $sent = Get-Date } }
            elseif(-not $warned -or ((Get-Date) - $warned).TotalSeconds -ge $RenotifySec){ Notify "MudinhoX" "Reset nao aconteceu e nao vejo captcha. Da uma olhada."; $warned = Get-Date }
          }
        }
        $img.Dispose()
      }
    } finally { Release-Focus }
  } until ($resetOk -or $script:restartCycle)
  if($script:restartCycle){ continue }   # botao mudou a fase no meio do reset: recomeca o ciclo (nao conta este reset)
  Log "reset feito, recomecando"; Wait 8   # efeito do teleporte: jogo ignora teclas por uns segundos
  if($script:phase -eq 'warmup'){
    $script:warmupCount++; Log "warmup: reset $($script:warmupCount)/$WarmupResets (Lost Tower)"
    if($script:warmupCount -ge $WarmupResets){ $script:phase = 'normal'; Log "warmup completo ($WarmupResets resets) -> voltando ao spot normal ($WarpCmd)" }
  }
  $script:statDue = Get-Date   # distribui os pontos do reset ja no proximo tick (Distribute-Points valida os 4 atributos e cuida do /darmr)
}
} catch { Log "ERRO: $_"; Notify "MudinhoX RPA parou" "$_"; Wait 30 }
