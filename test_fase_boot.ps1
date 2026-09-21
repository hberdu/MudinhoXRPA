# Self-check da validacao de fase no boot (nao toca no jogo): .\test_fase_boot.ps1
# 20/09: o estado.txt podia estar errado, ausente ou velho (voce apagou o arquivo, ou deu /darmr na mao fora do
# bot) e nada conferia isso contra o PERSONAGEM antes de decidir losttower7 (warmup) ou k37/s21 (normal). Agora
# Valida-FaseBoot le os 4 atributos e corrige quando eles discordam do que foi retomado.
$StatOrder = 'Ene','Agi','For','Vit'
$StatStep = 5000
$StatMaxValue = 32767
$StatStages = @(1..([Math]::Floor(($StatMaxValue - 1) / $StatStep)) | % { $_ * $StatStep }) + $StatMaxValue   # 5000,10000,...,32767 - mesma conta do CONFIG real

$src = Get-Content "$PSScriptRoot\mudinhox_rpa.ps1" -Raw
if($src -notmatch '(?s)(function Valida-FaseBoot \{.*?\r?\n\})'){ throw "nao achei a Valida-FaseBoot" }
. ([scriptblock]::Create($Matches[1]))

$script:erros = 0
function Chk($n,$got,$exp){ if("$got" -ne "$exp"){ "FALHOU $n : '$got' != '$exp'"; $script:erros++ } }

function St($f,$a,$v,$e){ @{ For=$f; Agi=$a; Vit=$v; Ene=$e } }
$script:logs = @(); function Log($m){ $script:logs += $m }
$script:saves = 0; function Save-Estado { $script:saves++ }

# 1. char recem-saido de /darmr (os 4 atributos voltam pra 1500 - medido no log real, MR #155): estado.txt dizia
#    'normal' por engano (arquivo velho/editado na mao) - tem que corrigir pra warmup.
function Read-Status { St 1500 1500 1500 1500 }
$script:phase = 'normal'; $script:warmupCount = 5
Valida-FaseBoot
Chk 'atributos baixos -> corrige pra warmup' $script:phase 'warmup'
Chk 'contador de warmup zera na correcao'    $script:warmupCount 0
Chk 'grava a correcao'                       $script:saves 1

# 2. char com progresso de verdade (qualquer atributo acima da 1a etapa): estado.txt dizia 'warmup' por engano -
#    tem que corrigir pra normal. Nao precisa dos 4 acima, UM ja prova que nao acabou de resetar.
$script:saves = 0
function Read-Status { St 9744 1500 1500 1500 }
$script:phase = 'warmup'; $script:warmupCount = 1
Valida-FaseBoot
Chk 'um atributo alto -> corrige pra normal' $script:phase 'normal'
Chk 'grava a correcao'                       $script:saves 1

# 3. atributos CONCORDAM com a fase retomada: nao mexe em nada, nao gasta Save-Estado a toa
$script:saves = 0
function Read-Status { St 9744 9176 5304 10000 }
$script:phase = 'normal'; $script:warmupCount = 0
Valida-FaseBoot
Chk 'concordando, fase intacta'      $script:phase 'normal'
Chk 'concordando, nao salva a toa'   $script:saves 0

$script:saves = 0
function Read-Status { St 1500 1500 1500 1500 }
$script:phase = 'warmup'; $script:warmupCount = 1
Valida-FaseBoot
Chk 'warmup concordando com baixo, fase intacta' $script:phase 'warmup'
Chk 'warmup concordando, nao salva a toa'         $script:warmupCount 1

# 4. nao consegue ler o status (jogo travado, tela de loading etc): nao inventa, mantem o que o estado.txt disse.
#    E diz O MOTIVO (captcha vs outra coisa) - antes so dizia "falhou", igual todo outro "Read-Status falhou" do
#    log, sem dar pra saber DE LONGE se era a mesma classe do incidente de 19/09 (painel tapado) ou um captcha.
$script:saves = 0
function Read-Status { $null }
function Capture-Game { 'img-fake' }   # so precisa ser truthy - Find-Captcha decide o resto
function Find-Captcha($img){ $true }   # captcha na tela
$script:phase = 'warmup'; $script:warmupCount = 2
Valida-FaseBoot
Chk 'sem leitura, mantem a fase do estado.txt' $script:phase 'warmup'
Chk 'sem leitura, nao gasta Save-Estado'        $script:saves 0
Chk 'diz que e captcha' ([bool]($script:logs -match 'tem captcha na tela')) 'True'

$script:saves = 0; $script:logs = @()
function Find-Captcha($img){ $false }   # jogo capturavel, mas sem captcha - motivo genuinamente desconhecido
Valida-FaseBoot
Chk 'sem captcha, nao inventa captcha' ([bool]($script:logs -match 'tem captcha na tela')) 'False'
Chk 'sem captcha, avisa motivo desconhecido' ([bool]($script:logs -match 'motivo desconhecido')) 'True'

$script:saves = 0; $script:logs = @()
function Capture-Game { $null }   # nem a captura funciona (jogo minimizado, fechando...)
Valida-FaseBoot
Chk 'sem captura nenhuma, nao quebra' $script:phase 'warmup'
Chk 'sem captura nenhuma, avisa no log' ([bool]($script:logs -match 'nao consegui ler')) 'True'

if($script:erros -eq 0){ "OK: Valida-FaseBoot corrige losttower7/k37 pelos atributos reais, so quando discorda do estado.txt" }
else { "$($script:erros) FALHA(S)"; exit 1 }
