# Self-check da validacao de fase no boot (nao toca no jogo): .\test_fase_boot.ps1
# 20/09: o estado.txt podia estar errado, ausente ou velho (voce apagou o arquivo, ou deu /darmr na mao fora do
# bot) e nada conferia isso contra o PERSONAGEM antes de decidir losttower7 (warmup) ou k37/s21 (normal). Agora
# Valida-FaseBoot le os 4 atributos e corrige quando eles discordam do que foi retomado.
# 21/09 (pedido do usuario): a regra virou "fica no warmup ate os 4 atributos passarem de $WarmupPts" - TODOS,
# nao qualquer um. Um char com 1 atributo alto e os outros 3 baixos AINDA precisa do warmup.
$StatOrder = 'Ene','Agi','For','Vit'
$WarmupPts = 8000

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

# 2. SO UM atributo acima de $WarmupPts, os outros 3 ainda baixos: continua/corrige pra warmup. E a regra nova -
#    "todos os 4", nao "qualquer um". Testa os dois sentidos: estado.txt dizia 'normal' (corrige) e 'warmup' (fica).
$script:saves = 0
function Read-Status { St 9744 1500 1500 1500 }
$script:phase = 'normal'; $script:warmupCount = 0
Valida-FaseBoot
Chk 'so 1 atributo alto -> AINDA e warmup (faltam os outros 3)' $script:phase 'warmup'
Chk 'grava a correcao'                                           $script:saves 1

$script:saves = 0; $script:phase = 'warmup'; $script:warmupCount = 1
Valida-FaseBoot
Chk 'so 1 atributo alto, warmup concordando: fica' $script:phase 'warmup'
Chk 'concordando: nao salva a toa'                  $script:saves 0

# 3. os 4 atributos passaram de $WarmupPts: estado.txt dizia 'warmup' por engano - corrige pra normal.
$script:saves = 0
function Read-Status { St 9744 9176 8304 10000 }
$script:phase = 'warmup'; $script:warmupCount = 4
Valida-FaseBoot
Chk 'os 4 atributos altos -> corrige pra normal' $script:phase 'normal'
Chk 'grava a correcao'                            $script:saves 1

# 4. atributos CONCORDAM com a fase retomada: nao mexe em nada, nao gasta Save-Estado a toa
$script:saves = 0
function Read-Status { St 9744 9176 8304 10000 }
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

# 5. nao consegue ler o status (jogo travado, tela de loading etc): nao inventa, mantem o que o estado.txt disse.
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

# 6. REGRESSAO (24/09): jogo FECHADO no boot. Read-Status LANCA ("MudinhoX (mudx.exe) nao esta rodando") em vez de
#    devolver $null, e Valida-FaseBoot roda fora do try do laco principal - a excecao derrubava o script inteiro
#    logo depois de abrir. Tem que engolir, logar, manter a fase e NAO propagar.
$script:saves = 0; $script:logs = @()
function Read-Status { throw "MudinhoX (mudx.exe) nao esta rodando" }
$script:phase = 'warmup'; $script:warmupCount = 1
$propagou = $false
try { Valida-FaseBoot } catch { $propagou = $true }
Chk 'jogo fechado: NAO propaga a excecao' $propagou $false
Chk 'jogo fechado: mantem a fase'         $script:phase 'warmup'
Chk 'jogo fechado: nao grava'             $script:saves 0
Chk 'jogo fechado: loga o motivo'         ([bool]($script:logs -match 'nao esta rodando')) 'True'

if($script:erros -eq 0){ "OK: Valida-FaseBoot corrige losttower7/k37 pelos atributos reais (os 4 tem que passar de `$WarmupPts), so quando discorda do estado.txt" }
else { "$($script:erros) FALHA(S)"; exit 1 }
