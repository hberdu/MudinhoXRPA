# Self-check do modo MULTIBOX (nao toca no jogo): .\test_multibox.ps1
# Quatro bots, um por cliente do MU. O que pode dar muito errado, e o que este teste protege:
#  1. dois slots escrevendo o MESMO estado.txt - um sobrescreve a fase/warmup do outro e os chars se perdem
#  2. dois slots no MESMO spot, brigando por mob
#  3. dois slots mandando tecla ao mesmo tempo - keybd_event e GLOBAL, o /resetar de um cai no cliente do outro
#  4. slot 0 (um cliente so) mudar de comportamento - o modo de sempre nao pode regredir
$src = Get-Content "$PSScriptRoot\mudinhox_rpa.ps1" -Raw
$script:erros = 0
function Chk($n,$got,$exp){ if("$got" -ne "$exp"){ "FALHOU $n : '$got' != '$exp'"; $script:erros++ } }

# --- 1. arquivos por slot: nada de dois bots no mesmo estado.txt -----------------------------------
# O $Sfx e o sufixo. Slot 0 tem que dar string vazia (nomes de sempre), slot N tem que dar "N".
foreach($caso in @(@{S=0;Sfx=''}, @{S=1;Sfx='1'}, @{S=4;Sfx='4'})){
  $Slot = $caso.S
  $Sfx = if($Slot -gt 0){ "$Slot" } else { '' }
  Chk "slot $($caso.S): sufixo dos arquivos" $Sfx $caso.Sfx
}
foreach($campo in 'rpa\$Sfx\.log', 'stop\$Sfx\.flag', 'heartbeat\$Sfx\.txt', 'estado\$Sfx\.txt', 'captcha\$Sfx', 'warmup\$Sfx\.flag'){
  Chk "arquivo por slot: $($campo -replace '\\','')" ($src -match $campo) 'True'
}
# o flag geral de parada NAO pode ter sufixo, senao nao derruba todo mundo
Chk "stop.flag geral sem sufixo" ($src -match "StopAllFile\s*=\s*Join-Path \`$PSScriptRoot 'stop\.flag'") 'True'

# --- 2. spot: os quatro no MESMO lugar --------------------------------------------------------------
# Os chars sobem em PARTY, entao party quer eles juntos. Existiu um $SlotSpots dando um spot por slot; foi
# removido. Este teste garante que nao volta por acidente e que nenhum slot sobrescreve o $WarpCmd.
Chk "nao ha spot por slot"        ($src -match '(?m)^\$SlotSpots\s*=') 'False'   # o comentario que conta a historia pode ficar; a CONFIG e que nao volta
Chk "o slot nao mexe no WarpCmd"  ($src -match '(?s)if\(\$Slot -gt 0\)\{.*?\$WarpCmd\s*=') 'False'

# --- 3. trava de entrada ----------------------------------------------------------------------------
# Mutex do SISTEMA (Global\), senao nao serve: os slots sao processos separados, um lock em processo nao veria.
Chk "mutex e global"        ($src.Contains("New-Object System.Threading.Mutex(`$false, 'Global\MudinhoX-Input')")) 'True'
Chk "so existe com -Slot"   ($src -match "if\(\`$Slot -gt 0\)\{ \`$script:mtx = New-Object System\.Threading\.Mutex") 'True'
Chk "Focus-Game pega a vez" ($src -match "(?s)function Focus-Game \{\s*\r?\n\s*Input-Lock") 'True'
Chk "Restore-Focus devolve" ($src -match "(?s)function Restore-Focus.*?Input-Unlock") 'True'
Chk "Check-Stop devolve"    ($src -match "(?s)function Check-Stop.*?Input-Unlock") 'True'
# A IDEMPOTENCIA e o ponto critico: o Focus-Game e chamado solto varias vezes sem Restore-Focus casado, e um
# mutex conta reentradas. Pegar 2x e soltar 1x vazaria a trava e travaria os outros tres bots pra sempre.
Chk "Input-Lock sai se ja tem"   ($src -match "function Input-Lock \{(?s).*?if\(-not \`$script:mtx -or \`$script:lockHeld\)\{ return \}") 'True'
Chk "Input-Unlock sai se nao tem" ($src -match "function Input-Unlock \{(?s).*?if\(-not \`$script:lockHeld\)\{ return \}") 'True'
# Bot morto com a trava na mao nao pode parar a fila pra sempre
Chk "espera tem teto"            ($src -match "WaitOne\(120000\)") 'True'
Chk "trata mutex abandonado"     ($src -match "AbandonedMutexException") 'True'

# --- 4. VER e DIGITAR sao coisas diferentes ---------------------------------------------------------
# Foi o erro que quebrou os 4 slots em 08/09: leitura passando pelo primeiro plano custava 40-60% do foco do
# sistema por bot; dois ja saturavam. Ver e Z-order (SWP_NOACTIVATE, custa ms); so digitar exige foco.
Chk "leitura NAO pede foco"      ($src -match "(?s)if\(\`$Slot -gt 0\)\{.*?\`$NoFocusRead = \`$true") 'True'
Chk "poll de fundo acompanha"    ($src -match "(?s)if\(\`$Slot -gt 0\)\{.*?\`$PollBgSec = \`$PollSec") 'True'
Chk "sobe a janela sem ativar"   ($src -match 'SetWindowPos\(\(Get-Game\), \[IntPtr\]::Zero, 0,0,0,0, 0x13\)') 'True'
Chk "Capture-Raw sobe antes"     ($src -match "(?s)function Capture-Raw.*?Ver-Janela") 'True'
# A verificacao mais importante do multibox: dois slots empilhados no MESMO ponto da tela leriam um o jogo do
# outro, e nada no log denunciaria (mesmo mapa, level parecido, pontos do char errado).
Chk "confere de quem sao os pixels" ($src -match 'WindowFromPoint') 'True'
Chk "e usa isso no capOk"        ($src -match "capOk = if\(\`$Slot -gt 0\)\{ Janela-Na-Frente \}") 'True'
Chk "aceita controle filho"      ($src -match 'GetAncestor\(\$w, 2\)') 'True'

# --- 5. slot 0 nao pode regredir --------------------------------------------------------------------
# Tudo que e novo esta atras de `if($Slot -gt 0)`. Um cliente so tem que rodar exatamente como antes.
Chk "Slot tem default 0"    ($src -match '\[int\]\$Slot = 0') 'True'
Chk "GamePid tem default 0" ($src -match '\[int\]\$GamePid = 0') 'True'

# --- 6. as janelinhas dos OUTROS slots saem da captura ----------------------------------------------
# Cada bot ja apagava a propria janelinha do Capture-Raw pra nao sujar o OCR. Com quatro na tela isso nao basta:
# a do slot 2 em cima do $LevelBox (x 1080..1220) do cliente 1 vira leitura de lixo. Posicionar as quatro fora
# de tudo que o bot le nao da - o inventario e o modal do mix nem tem posicao fixa. Entao mascara todas.
Chk "Capture-Raw apaga as outras"  ($src -match "(?s)function Capture-Raw.*?foreach\(\`$r in \(Outras-Janelinhas\)\)") 'True'
Chk "acha pelo titulo da janela"   ($src -match "MainWindowTitle -notlike 'MudinhoX RPA\*'") 'True'
Chk "nao apaga a propria duas vezes" ($src -match '\$h -eq \$meu') 'True'
Chk "fora do multibox nao custa nada" ($src -match "(?s)function Outras-Janelinhas.*?if\(\`$Slot -le 0\)\{ return @\(\) \}") 'True'
# Get-Process enumera TODOS os processos e o Capture-Raw roda a cada leitura: sem cache seria caro igual ao
# problema que o Get-Game ja resolveu cacheando.
Chk "a lista fica em cache"        ($src -match 'outrasUiAt\)\.TotalSeconds -lt 30') 'True'
# O titulo e o que identifica: se o Show-Ui parar de escrever "MudinhoX RPA" nele, a mascara silenciosamente
# para de achar as outras janelas e o bug volta sem aviso.
Chk "o titulo casa com a busca"    ($src -match '"MudinhoX RPA - slot \$Slot \(\$WarpCmd\)"') 'True'

if($script:erros){ "`n$($script:erros) FALHA(S)"; exit 1 }
"OK: arquivos por slot, mesmo spot (party), trava so pra digitar, leitura por Z-order sem roubar foco, slot 0 intacto"
