# Self-check do estado persistido (nao toca no jogo): .\test_estado.ps1
# Metricas do MR levam horas pra juntar; se o estado.txt nao sobreviver a um restart, a medicao inteira se perde.
$EstadoFile = Join-Path $env:TEMP 'estado_rt_test.txt'
$WarmupResets = 10
$TargetLevel = 350
function Log($m){ }

$src = Get-Content "$PSScriptRoot\mudinhox_rpa.ps1" -Raw
if($src -notmatch '(?s)(function Save-Estado.*?)\r?\nfunction Same-Map'){ throw "nao achei Save-Estado..Load-Estado no mudinhox_rpa.ps1" }
. ([scriptblock]::Create($Matches[1]))

$script:erros = 0
function Chk($n,$got,$exp){ if("$got" -ne "$exp"){ "FALHOU $n : '$got' != '$exp'"; $script:erros++ } }

# 1. round-trip completo
$script:phase='warmup'; $script:warmupCount=7; $script:resets=42; $script:ptsSent=91234
$script:mrs=3; $script:runStart=(Get-Date).AddHours(-2.5); $script:mrStart=(Get-Date).AddHours(-1.25)
$script:ciclos=@(88,91,102,301,77); $script:ativoSeg=4200; $script:joiasMix=37; $script:joiasCiclos=9
$rs=$script:runStart.Ticks; $ms=$script:mrStart.Ticks
Save-Estado
$script:phase='normal'; $script:warmupCount=0; $script:resets=0; $script:ptsSent=0; $script:mrs=0
$script:ciclos=@(); $script:ativoSeg=0; $script:joiasMix=0; $script:joiasCiclos=0; $script:runStart=Get-Date; $script:mrStart=Get-Date
Load-Estado
Chk 'fase' $script:phase 'warmup'
Chk 'warmup' $script:warmupCount 7
Chk 'resets' $script:resets 42
Chk 'ptsSent' $script:ptsSent 91234
Chk 'mrs' $script:mrs 3
Chk 'runStart' $script:runStart.Ticks $rs
Chk 'mrStart' $script:mrStart.Ticks $ms
Chk 'ciclos' ($script:ciclos -join ',') '88,91,102,301,77'
Chk 'tempo ativo' $script:ativoSeg 4200
Chk 'joias mixadas' $script:joiasMix 37
Chk 'ciclos de joias' $script:joiasCiclos 9

# 1b. o alvo de level e o estado do auto-tune sobrevivem (o estado.txt agora manda no $TargetLevel:
#     um bug aqui mudaria silenciosamente o alvo do bot)
$script:TargetLevel = 320; $script:tuneOn = $false
Save-Estado
$script:TargetLevel = 350; $script:tuneOn = $true
Load-Estado
Chk 'alvo de level' $script:TargetLevel 320
# o modo decide QUAL ciclo o bot roda (reset/master reset vs farmar-e-mixar): errar aqui muda tudo
$script:modo = 'joias'; Save-Estado; $script:modo = 'reset'; Load-Estado
Chk 'modo joias sobrevive' $script:modo 'joias'
$script:modo = 'reset'; Save-Estado; $script:modo = 'joias'; Load-Estado
Chk 'modo reset sobrevive' $script:modo 'reset'
$script:modo = 'dragoes'; Save-Estado; $script:modo = 'reset'; Load-Estado
Chk 'modo dragoes sobrevive' $script:modo 'dragoes'
'fase=normal' | Set-Content $EstadoFile -Encoding ASCII   # arquivo sem 'modo' nao pode virar lixo
$script:modo = 'joias'; Load-Estado
Chk 'sem modo no arquivo, mantem o da memoria' $script:modo 'joias'
Chk 'autotune concluido nao refaz' $script:tuneOn $false
# com o A/B ainda rodando, o alvo e salvo mas o tune continua ligado
$script:tuneOn = $true; Save-Estado; $script:tuneOn = $false; Load-Estado
Chk 'autotune em andamento continua' $script:tuneOn $false   # so DESLIGA quando o arquivo diz 0; nunca religa sozinho

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
