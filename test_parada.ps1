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

# --- "Voce nao pode se mover": janela de NPC aberta trava TODO warp -------------------------------
# 12/09: o mix desistiu com o dialogo de confirmar na tela; o servidor passou a recusar todo /k37 com essa
# mensagem e o bot reenviou o comando por 54 MINUTOS, lendo a resposta e ignorando. Custou mais que qualquer
# outro travamento do log. O teste usa as leituras REAIS do rpa.log - o OCR destroi a frase de formas diferentes
# a cada vez, entao casar so com o texto correto nao serviria de nada.
if($src -notmatch "(?m)^\`$MsgTravadoWords\s*=\s*'([^']+)'"){ throw "nao achei o `$MsgTravadoWords no CONFIG" }
$travado = $Matches[1]
$reais = @(
  'Rosetado com sucosso, você possui 2585 rosots! Resta ainda 1 Golden Dragon vivo(s) em Devias! Vocó não podo se mover nosto momento',
  'voco nao poao so mover nosto momento Resta ainda 6 Golden Dragon vivo(s) em Lorencia!',
  'Jewel of Soul Mudinho Drop começou! K Lorencia X:125 Y:125 Você não pode se mover neste momento'
)
$i = 0
foreach($m in $reais){ $i++; Chk "leitura real $i do OCR e reconhecida" (($m -match $travado) -and ($m -match '(?i)moment')) $true }
# ...e a faixa de mensagens NORMAL nao pode disparar o destravamento: fechar janela a toa no meio do farm
# atrapalha (o ESC as cegas ja abriu o menu do jogo e cegou o bot por 65 min em 04/09).
$normais = @(
  'Resta ainda 7 Golden Dragon vivo(s) em Lorencia! ViotNam88 acabou do matar um Goldon Dragon!',
  'Você adicionou 512 pontos, permanecendo 304 pontos a serem distribuídos',
  'Vocó precisa do estar no Iovol 350 para rosetar!'
)
$i = 0
foreach($m in $normais){ $i++; Chk "mensagem comum $i nao dispara" (($m -match $travado) -and ($m -match '(?i)moment')) $false }
# E o codigo tem que AGIR: ler a mensagem e nao fazer nada foi exatamente o bug.
Chk 'o warp destrava ao ver a mensagem' ($src -match '(?s)if\(\$msg -match \$MsgTravadoWords.*?Unstick-Tudo') 'True'
# A rede de seguranca geral tambem tickava so DENTRO do laco de farm - com o warp falhando o bot nunca entra la,
# e nada vigiava nada. Por isso os 54 min passaram sem um unico "SEM PROGRESSO".
Chk 'vigia de progresso roda com warp falho' ($src -match 'if\(-not \$warpOk\)\{ Hold-Focus; try \{ Tick-Progresso \}') 'True'

# --- aprender o level minimo de reset pela mensagem do servidor -----------------------------------
# O mecanismo existia e estava MORTO: o regex pedia "level" e "resetar" literais, e o OCR le "Iovol 350 para
# rosetar". Seis avisos do servidor no rpa.log, zero aprendizados, alvo parado em 305 contra os 350 exigidos -
# um reenvio de /resetar sobrando a cada reset. Estas sao as leituras REAIS, com os erros de OCR que aconteceram.
if($src -notmatch "(?m)^\`$MsgMinResetWords\s*=\s*'([^']+)'"){ throw "nao achei o `$MsgMinResetWords no CONFIG" }
$minRe = $Matches[1]
$reaisMin = @(
  'Rosta ainda 3 Goldon Tantalo vivo(s) om Tarkant Vocó precisa do estar no Iovol 350 para rosetar!',
  'pontos, permanecendo 48 pontos a serem distribuídos Você precisa de estar no levei 350 para resetad ViotNam88 aca',
  'Obtido Jowol of Creation Você precisa de estar no leve! 350 para resetar!',
  'pontos, permanecendo 128 pontos a serem distribuídos Você precisa do estar no lovol 350 para rosetar! Ml Post'
)
$i = 0
foreach($m in $reaisMin){
  $i++
  $casou = $m -match $minRe
  Chk "exigencia do servidor $i e lida"  $casou               $true
  if($casou){ Chk "e o piso lido e 350"  ([int]$Matches[1])   350 }
}
# O numero tem que vir de "N para resetar", nao de qualquer numero da faixa: a mesma leitura tem "48 pontos",
# "128 pontos", "3 Goldon Tantalo". Pegar o numero errado poria o alvo num valor absurdo.
Chk 'nao pega numero solto da faixa' ('Você adicionou 512 pontos, permanecendo 304 pontos a serem distribuídos' -match $minRe) 'False'
# E o teto de sanidade: OCR ruim devolvendo 3500 faria o char farmar pra sempre sem nunca resetar.
Chk 'aprendizado tem teto'           ($src -match '\$min -le \$LevelMaximo') 'True'

if($script:erros -eq 0){ "OK: parada limpa o disco e registra o motivo, painel congelado pego em $StatCongeladoN leituras, e warp travado destrava" }
else { "$($script:erros) FALHA(S)"; exit 1 }
