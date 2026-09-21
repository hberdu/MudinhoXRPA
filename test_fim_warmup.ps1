# Self-check da saida do warmup por atributos (nao toca no jogo): .\test_fim_warmup.ps1
# 21/09 (pedido do usuario): losttower7 ate os 4 atributos passarem de $WarmupPts, dai vai pra k37/s21. Chamada
# depois de CADA reset feito em warmup (Checa-Fim-Warmup), nao mais por contagem de resets ($WarmupResets virou
# so display). Mesma regra do Valida-FaseBoot (boot), testado em test_fase_boot.ps1.
$StatOrder = 'Ene','Agi','For','Vit'
$WarmupPts = 8000
$WarpCmd = '/k37'

$src = Get-Content "$PSScriptRoot\mudinhox_rpa.ps1" -Raw
if($src -notmatch '(?s)(function Checa-Fim-Warmup \{.*?\r?\n\})'){ throw "nao achei a Checa-Fim-Warmup" }
. ([scriptblock]::Create($Matches[1]))

$script:erros = 0
function Chk($n,$got,$exp){ if("$got" -ne "$exp"){ "FALHOU $n : '$got' != '$exp'"; $script:erros++ } }

function St($f,$a,$v,$e){ @{ For=$f; Agi=$a; Vit=$v; Ene=$e } }
$script:logs = @(); function Log($m){ $script:logs += $m }
$script:saves = 0; function Save-Estado { $script:saves++ }

# 1. os 4 atributos JA passaram de $WarmupPts neste reset: sai pro spot normal
$script:saves = 0
function Read-Status { St 9744 9176 8304 10000 }
$script:phase = 'warmup'; $script:warmupCount = 3
Checa-Fim-Warmup
Chk 'os 4 altos -> normal'          $script:phase 'normal'
Chk 'conta o reset mesmo saindo'    $script:warmupCount 4
Chk 'sempre grava'                  $script:saves 1
Chk 'log diz que completou'         ([bool]($script:logs -match 'warmup completo')) 'True'

# 2. so 1 atributo passou (os outros 3 nao): continua no warmup, diz QUAIS faltam e com QUE valor
$script:saves = 0; $script:logs = @()
function Read-Status { St 9744 1500 1500 4200 }
$script:phase = 'warmup'; $script:warmupCount = 0
Checa-Fim-Warmup
Chk 'so 1 alto -> continua warmup'     $script:phase 'warmup'
Chk 'conta o reset'                     $script:warmupCount 1
Chk 'sempre grava'                      $script:saves 1
Chk 'diz o que falta: Vit'   ([bool]($script:logs -match 'Vit=1500')) 'True'
Chk 'diz o que falta: Ene'   ([bool]($script:logs -match 'Ene=4200')) 'True'
Chk 'NAO lista o que ja passou (For)' ([bool]($script:logs -match 'For=')) 'False'

# 3. nao consegue ler o status neste reset: conta o reset mesmo assim (senao trava contando pra sempre igual),
#    fica no warmup (nao pode assumir sucesso sem prova), e diz que nao leu em vez de inventar numero
$script:saves = 0; $script:logs = @()
function Read-Status { $null }
$script:phase = 'warmup'; $script:warmupCount = 5
Checa-Fim-Warmup
Chk 'sem leitura: continua warmup'    $script:phase 'warmup'
Chk 'sem leitura: ainda conta o reset' $script:warmupCount 6
Chk 'sem leitura: grava mesmo assim'   $script:saves 1
Chk 'sem leitura: avisa no log' ([bool]($script:logs -match 'nao consegui ler o status')) 'True'

if($script:erros -eq 0){ "OK: Checa-Fim-Warmup so libera o spot normal quando os 4 atributos passam de `$WarmupPts, nunca inventa sucesso sem leitura" }
else { "$($script:erros) FALHA(S)"; exit 1 }
