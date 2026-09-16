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

# --- mixagem temporariamente desativada -----------------------------------------------------------
Chk "acabou de mixar: nao vai de novo"      (Rodar (Get-Date) $false) 0
Chk "faltando 1 min pro teto: ainda nao"    (Rodar (Get-Date).AddMinutes(1-$MixEveryMin) $false) 0
Chk "estourou o teto: mix desativado"       (Rodar (Get-Date).AddMinutes(-$MixEveryMin) $false) 0
Chk "bem depois do teto: mix desativado"    (Rodar (Get-Date).AddHours(-3) $false) 0
# botao MIXAR AGORA / aviso do jogo tambem ficam desativados por enquanto
Chk "botao MIXAR AGORA nao mistura"         (Rodar (Get-Date) $true) 0

# --- sem mix nao reinicia o ciclo nem mexe no relogio ----------------------------------------------
$null = Rodar (Get-Date).AddHours(-3) $false
Chk "nao mixou -> nao reinicia o ciclo"     $script:restartCycle 'False'
Chk "mixou -> relogio zerado, nao repete"   (Rodar $script:mixLast $false) 0

# --- desligar tem que desligar --------------------------------------------------------------------
$teto = $MixEveryMin; $MixEveryMin = 0
Chk "MixEveryMin=0 desliga o teto"          (Rodar (Get-Date).AddHours(-3) $false) 0

# --- desistir do mix NAO pode deixar dialogo aberto ------------------------------------------------
# O caso mais caro do log inteiro, duas vezes: o bot clica na joia, nao acha o CONFIRMAR e sai. O dialogo do NPC
# fica na tela, e com ele aberto o servidor recusa TODO warp ("Voce nao pode se mover neste momento") - o bot
# reenvia /k37 contra uma parede. Custou 54 min em 12/09 e 81 min em 13/09. O ESC do Close-Popup foi tentado nas
# duas e nas duas falhou: esse dialogo so fecha pelo botao.
$src = Get-Content "$PSScriptRoot\mudinhox_rpa.ps1" -Raw
Chk "existe o padrao do CANCELAR"        ($src -match "(?m)^\`$MixCancelWords\s*=") 'True'
Chk "sem CONFIRMAR, procura o CANCELAR"  ($src -match '(?s)nao achei o botao CONFIRMAR.*?Achar-Ate \$MixCancelWords') 'True'
Chk "e CLICA nele"                       ($src -match '(?s)nao achei o botao CONFIRMAR.*?Word-Center \$canc.*?Click-Client') 'True'
# CANCELAR e CONFIRMAR moram no mesmo dialogo: casar um com o outro clicaria em confirmar achando que cancela
# (ou pior, o contrario - mixando joia que voce nao mandou mixar).
if($src -notmatch "(?m)^\`$MixCancelWords\s*=\s*'([^']+)'"){ throw "nao achei o `$MixCancelWords" }
$canc = $Matches[1]
if($src -notmatch "(?m)^\`$MixConfirmWords\s*=\s*'([^']+)'"){ throw "nao achei o `$MixConfirmWords" }
$conf = $Matches[1]
Chk "CANCELAR casa com 'Cancelar'"       ('Cancelar' -match $canc) 'True'
Chk "  (e nao com 'Confirmar')"          ('Confirmar' -match $canc) 'False'
Chk "CONFIRMAR nao casa com 'Cancelar'"  ('Cancelar' -match $conf) 'False'
# So chama o usuario quando NAO ha saida: achando o CANCELAR o bot se resolve sozinho, e notificacao a toa
# ensina a ignorar notificacao.
Chk "so notifica se nem CANCELAR achou"  ($src -match '(?s)nem CONFIRMAR nem CANCELAR.*?Notify') 'True'

# --- o dialogo do mix NAO pode ser lido como captcha ----------------------------------------------
# 15/09: o bot chamou o usuario duas vezes pra "resolver um captcha" e nao havia captcha nenhum na tela - era o
# painel de combinacao aberto. O Find-Captcha ancorava em qualquer linha com a palavra "Selecione", e o dialogo
# do mix diz "Selecione o metodo de combinacao". No meio da mixagem o bot comparava pedacos quaisquer da tela,
# empatava (0.83, 0.991, 0.992) e pedia socorro. 3 dos 4 "captchas" daquele log eram isso.
# As duas strings abaixo sao o que o OCR do Windows LEU de verdade nas imagens - inclusive o erro dele em
# "combinaqäo". O -TestVisao cobre isso com as imagens, mas fixtures/ e gitignored: noutra maquina aquele teste
# PULA em silencio. Este aqui roda em qualquer lugar, porque so precisa do regex.
Chk "existe a ancora do captcha"     ($src -match "(?m)^\`$CapAncoraWords\s*=") 'True'
if($src -notmatch "(?m)^\`$CapAncoraWords = '([^']+)'"){ throw "nao achei o `$CapAncoraWords no CONFIG" }
$anc = $Matches[1]
Chk "acha o captcha de verdade"      ('Selecione a mesma imagem abaixo:' -match $anc) 'True'
Chk "NAO acha no dialogo do mix"     ('Selecione o método de combinaqäo' -match $anc) 'False'
# E a ancora nao pode voltar a ser so a palavra solta - foi exatamente esse o bug.
Chk "nao casa 'Selecione' sozinho"   ('Selecione' -match $anc) 'False'
# O Find-Captcha tem que USAR a constante, senao o padrao volta cravado no corpo da funcao e este teste mente.
Chk "Find-Captcha usa a ancora"      ($src -match '(?s)function Find-Captcha.*?-match \$CapAncoraWords') 'True'

if($script:erros){ "`n$($script:erros) FALHA(S)"; exit 1 }
"OK: gatilho do mix por tempo ($teto min no CONFIG), botao, desligamento, e desistir CANCELA o dialogo"
