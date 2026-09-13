# Self-check da PARADA e do detector de painel congelado (nao toca no jogo): .\test_parada.ps1
# Os dois nasceram do log de 01-02/09: o bot dizia "parado pelo usuario" ate quando tinha sido erro ou
# reinicio proprio; e ficou 12 min lendo "752 pontos" congelados sem ninguem perceber.
# Depois que o watchdog foi removido, o que importa aqui e: parou -> some tudo, e o log diz POR QUE.
$src = Get-Content "$PSScriptRoot\mudinhox_rpa.ps1" -Raw
$script:erros = 0
function Chk($n,$got,$exp){ if("$got" -ne "$exp"){ "FALHOU $n : '$got' != '$exp'"; $script:erros++ } }

$tmp = Join-Path $env:TEMP ("rpa_test_" + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $tmp | Out-Null
$StopFile      = Join-Path $tmp 'stop.flag'
$HeartbeatFile = Join-Path $tmp 'heartbeat.txt'
function Log($m){ $script:ultimoLog = $m }
$script:logW = $null; $script:ui = $null

# Check-Stop termina em `exit`, que mataria o teste: troca por `return` e o resto do corpo roda igual.
if($src -notmatch '(?s)(function Check-Stop \{.*?\r?\n\})'){ throw "nao achei a Check-Stop" }
. ([scriptblock]::Create(($Matches[1] -replace '(?m)^\s*exit\s*$', '  return')))

function Parar($motivo){
  Remove-Item $StopFile,$HeartbeatFile -ErrorAction SilentlyContinue
  '0' | Set-Content $HeartbeatFile
  $script:stop = $true; $script:stopReason = $motivo
  Check-Stop
}

# --- parou: nao pode sobrar NADA no disco --------------------------------------------------------
# Sem watchdog, ninguem le esses arquivos depois. Um stop.flag esquecido so atrapalharia a proxima
# abertura, e um heartbeat velho faria o proximo bot achar que ja tem outro rodando.
foreach($motivo in 'usuario','janela fechada','reinicio proprio','erro: alguma coisa explodiu','sem progresso'){
  Parar $motivo
  Chk "[$motivo] some o stop.flag"  (Test-Path $StopFile)      $false
  Chk "[$motivo] some o heartbeat"  (Test-Path $HeartbeatFile) $false
  Chk "[$motivo] o log diz o motivo" $script:ultimoLog         "parado ($motivo)"   # antes dizia sempre "parado pelo usuario", ate quando era crash
}

# --- stop.flag criado por voce, por fora: e detectado, registrado e consumido ---------------------
Remove-Item $StopFile,$HeartbeatFile -ErrorAction SilentlyContinue
'' | Set-Content $StopFile
$script:stop = $false; $script:stopReason = 'usuario'
Check-Stop
Chk 'stop.flag externo para o bot'       $script:stop               $true
Chk 'e o motivo fica registrado'         $script:stopReason         'stop.flag'
Chk 'e o arquivo e consumido'            (Test-Path $StopFile)      $false

Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue

# --- painel de status congelado -------------------------------------------------------------------
# Leitura identica (4 atributos + pontos) com o LEVEL andando no meio = frame velho na tela. Se o char
# esta upando, ponto TEM que entrar. Antes so o $SemProgressoMin pegava isso, 12 minutos depois.
$StatCongeladoN = 2
function Tag-Ciclo($t){}
$script:destravou = 0
function Unstick-Tudo { $script:destravou++ }
if($src -notmatch '(?s)(    # Painel congelado:.*?\r?\n    \})'){ throw "nao achei o detector de painel congelado" }
$detector = [scriptblock]::Create("param(`$st,`$guard)`n" + $Matches[1])
$script:stFp = ''; $script:stFpLvl = $null; $script:stFpN = 0

$st = @{ For = 5000; Agi = 10000; Vit = 5824; Ene = 10760; Pts = 752 }   # a leitura real que travou 12 min
$script:lvlPrev = 100; & $detector $st 0
Chk 'primeira leitura nao acusa nada'        $script:destravou 0
$script:lvlPrev = 180; & $detector $st 0     # mesma leitura, level andou
Chk 'segunda igual ainda nao acusa'          $script:destravou 0
$script:lvlPrev = 260; & $detector $st 0     # terceira: passou do $StatCongeladoN
Chk 'terceira igual destrava'                $script:destravou 1

# level PARADO com leitura igual nao e painel congelado - e o char sem upar, que o Check-Progress cobre
$script:stFp = ''; $script:stFpLvl = $null; $script:stFpN = 0; $script:destravou = 0
$script:lvlPrev = 300
1..5 | ForEach-Object { & $detector $st 0 }
Chk 'level parado nao dispara o detector'    $script:destravou 0

# leitura que MUDA zera a contagem (o caminho normal: pontos entrando)
$script:stFp = ''; $script:stFpLvl = $null; $script:stFpN = 0; $script:destravou = 0
$script:lvlPrev = 10; & $detector $st 0
$script:lvlPrev = 20; & $detector $st 0
$script:lvlPrev = 30; & $detector @{ For=5000; Agi=10000; Vit=5824; Ene=10760; Pts=3696 } 0
$script:lvlPrev = 40; & $detector @{ For=5000; Agi=10000; Vit=5824; Ene=10760; Pts=3696 } 0
Chk 'leitura nova zera a contagem'           $script:destravou 0

# so a 1a leitura da chamada conta: as de dentro do loop tem o mesmo level e nao podem zerar nada
$script:stFp = ''; $script:stFpLvl = $null; $script:stFpN = 0; $script:destravou = 0
$script:lvlPrev = 10; & $detector $st 0
$script:lvlPrev = 20; & $detector $st 0
& $detector $st 3                             # releitura dentro da mesma chamada: ignorada
$script:lvlPrev = 30; & $detector $st 0
Chk 'releitura interna nao atrapalha'        $script:destravou 1

if($script:erros -eq 0){ "OK: parada limpa o disco e registra o motivo, e o painel congelado e pego em $StatCongeladoN leituras" }
else { "$($script:erros) FALHA(S)"; exit 1 }
