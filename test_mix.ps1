# Self-check do GATILHO do mix de joias (nao toca no jogo): .\test_mix.ps1
# Nasceu do rpa.log de 04/09: o mix funciona (o /mixer, o Lahap, o clique no verde e o CONFIRMAR ja foram
# provados ao vivo em 01/09), mas no ciclo NORMAL ele nunca era chamado - 0 ocorrencias de "inventario cheio"
# em 42 mil linhas de log, contra 68 pausas manuais do usuario pra mixar na mao. O teto de tempo era so do
# modo joias. Este teste garante que o gatilho por tempo do ciclo normal existe e dispara.
$src = Get-Content "$PSScriptRoot\mudinhox_rpa.ps1" -Raw
$script:erros = 0
function Chk($n,$got,$exp){ if("$got" -ne "$exp"){ "FALHOU $n : '$got' != '$exp'"; $script:erros++ } }

if($src -notmatch '(?m)^\$MixEveryMin\s*=\s*(\d+)'){ throw "nao achei o `$MixEveryMin no CONFIG" }
$MixEveryMin = [int]$Matches[1]
if($src -notmatch '(?s)(function Tick-Inventory \{.*?\r?\n\})'){ throw "nao achei a Tick-Inventory" }
# Mix-Jewels vai no jogo: aqui ela so registra a chamada e faz o que a de verdade faz (zerar o relogio).
. ([scriptblock]::Create($Matches[1]))
function Log($m){ $script:ultimoLog = $m }
function Mix-Jewels { $script:mixou++; $script:mixLast = Get-Date }

function Rodar([datetime]$ultimo,[bool]$avisado){
  $script:mixLast = $ultimo; $script:mixNow = $avisado; $script:mixou = 0
  $script:restartCycle = $false; $script:ptsLastGain = $null
  Tick-Inventory
  $script:mixou
}

# --- gatilho por tempo: e o unico que sobrou no ciclo normal ---------------------------------------
Chk "acabou de mixar: nao vai de novo"      (Rodar (Get-Date) $false) 0
Chk "faltando 1 min pro teto: ainda nao"    (Rodar (Get-Date).AddMinutes(1-$MixEveryMin) $false) 0
Chk "estourou o teto: MIXA"                 (Rodar (Get-Date).AddMinutes(-$MixEveryMin) $false) 1
Chk "bem depois do teto: MIXA"              (Rodar (Get-Date).AddHours(-3) $false) 1
# botao MIXAR AGORA / aviso do jogo continuam valendo antes do teto
Chk "botao MIXAR AGORA fura o teto"         (Rodar (Get-Date) $true) 1

# --- o relogio zera, senao o bot volta pro /mixer a cada volta do loop -----------------------------
$null = Rodar (Get-Date).AddHours(-3) $false
Chk "mixou -> volta pro spot pelo warp"     $script:restartCycle 'True'
Chk "mixou -> relogio zerado, nao repete"   (Rodar $script:mixLast $false) 0

# --- desligar tem que desligar --------------------------------------------------------------------
$teto = $MixEveryMin; $MixEveryMin = 0
Chk "MixEveryMin=0 desliga o teto"          (Rodar (Get-Date).AddHours(-3) $false) 0

if($script:erros){ "`n$($script:erros) FALHA(S)"; exit 1 }
"OK: gatilho do mix por tempo ($teto min no CONFIG), botao e desligamento"
