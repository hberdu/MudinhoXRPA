# Self-check do estado persistido (nao toca no jogo): .\test_estado.ps1
# Metricas do MR levam horas pra juntar; se o estado.txt nao sobreviver a um restart, a medicao inteira se perde.
$EstadoFile = Join-Path $env:TEMP 'estado_rt_test.txt'
$WarmupResets = 10
function Log($m){ }

$src = Get-Content "$PSScriptRoot\mudinhox_rpa.ps1" -Raw
if($src -notmatch '(?s)(function Save-Estado.*?)\r?\nfunction Same-Map'){ throw "nao achei Save-Estado..Load-Estado no mudinhox_rpa.ps1" }
. ([scriptblock]::Create($Matches[1]))

$script:erros = 0
function Chk($n,$got,$exp){ if("$got" -ne "$exp"){ "FALHOU $n : '$got' != '$exp'"; $script:erros++ } }

# 1. round-trip completo
$script:phase='warmup'; $script:warmupCount=7; $script:resets=42; $script:ptsSent=91234
$script:mrs=3; $script:runStart=(Get-Date).AddHours(-2.5); $script:mrStart=(Get-Date).AddHours(-1.25)
$script:ciclos=@(88,91,102,301,77)
$rs=$script:runStart.Ticks; $ms=$script:mrStart.Ticks
Save-Estado
$script:phase='normal'; $script:warmupCount=0; $script:resets=0; $script:ptsSent=0; $script:mrs=0
$script:ciclos=@(); $script:runStart=Get-Date; $script:mrStart=Get-Date
Load-Estado
Chk 'fase' $script:phase 'warmup'
Chk 'warmup' $script:warmupCount 7
Chk 'resets' $script:resets 42
Chk 'ptsSent' $script:ptsSent 91234
Chk 'mrs' $script:mrs 3
Chk 'runStart' $script:runStart.Ticks $rs
Chk 'mrStart' $script:mrStart.Ticks $ms
Chk 'ciclos' ($script:ciclos -join ',') '88,91,102,301,77'

# 2. formato antigo ("fase warmup") tem que continuar sendo lido
'normal 4' | Set-Content $EstadoFile -Encoding ASCII
$script:phase='warmup'; $script:warmupCount=0
Load-Estado
Chk 'formato antigo: fase' $script:phase 'normal'
Chk 'formato antigo: warmup' $script:warmupCount 4

# 3. arquivo corrompido nao pode derrubar o bot nem zerar o que ja estava em memoria
'lixo{{{ sem igual' | Set-Content $EstadoFile -Encoding ASCII
$script:resets = 99
Load-Estado
Chk 'corrompido nao zera resets' $script:resets 99

Remove-Item $EstadoFile -ErrorAction SilentlyContinue
if($script:erros -eq 0){ "OK: estado sobrevive ao round-trip, ao formato antigo e a arquivo corrompido" }
else { "$($script:erros) FALHA(S)"; exit 1 }
