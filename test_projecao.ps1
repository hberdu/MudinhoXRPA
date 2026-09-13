# Self-check da PROJECAO DE RESETS e do piso de reset (nao toca no jogo): .\test_projecao.ps1
# Duas coisas que so se pode saber MEDINDO, nunca supondo:
#   1. quanto um reset rende - depende do level do alvo e de quao forte o char esta;
#   2. se o servidor aceita resetar no level pedido - a mensagem dele e a unica fonte de verdade.
# O erro que este arquivo guarda: o aprendizado do piso so sabia SUBIR. Uma recusa unica prendia o char naquele
# level pra sempre, mesmo depois de a exigencia cair - e o alvo do CONFIG nunca mais era tentado, porque o
# proprio $TargetLevel tinha sido sobrescrito.
$src = Get-Content "$PSScriptRoot\mudinhox_rpa.ps1" -Raw
$script:erros = 0
function Chk($n,$got,$exp){ if("$got" -ne "$exp"){ "FALHOU $n : '$got' != '$exp'"; $script:erros++ } }

function Log($m){ $script:ultimoLog = $m }
$CapGanhos = 12
foreach($fn in 'function Marcar-Ganho-Do-Reset','function Pontos-Por-Reset','function Resets-Faltando'){
  if($src -notmatch "(?s)($fn \{.*?\r?\n\})"){ throw "nao achei a $fn" }
  . ([scriptblock]::Create($Matches[1]))
}

# --- 1. ganho POR RESET, nao media do MR ----------------------------------------------------------
# A media do MR mistura os resets de warmup (Lost Tower, char fraco, rende pouco) com os do spot normal. Pra
# projetar o que VEM, o que vale sao os do spot normal - e a mediana deles, nao a media: um reset travado ou um
# captcha no meio nao pode mover a projecao.
function Reset($ptsSent, $ptsLeft, $fase = 'normal'){ $script:ptsSent = $ptsSent; $script:ptsLeft = $ptsLeft; $script:phase = $fase; Marcar-Ganho-Do-Reset }
$script:ganhoPorReset = @(); $script:ganhoMarco = -1
Reset 0 0                      # 1o reset: so cria o marco, nao ha diferenca pra medir
Chk 'primeiro reset nao mede'  (@($script:ganhoPorReset).Count) 0
Reset 5000 0                   # ganhou 5000
Reset 9000 1000                # ganhou mais 5000 (4000 distribuidos + 1000 em maos)
Chk 'mede dois ganhos'         (@($script:ganhoPorReset) -join ',') '5000,5000'
Chk 'pontos por reset'         (Pontos-Por-Reset) 5000
# O que ainda esta EM MAOS conta: $ptsSent so registra o que ja virou comando, e ha ate $StatEverySec de atraso
# entre o char ganhar o ponto e o bot gastar. Sem somar o $ptsLeft, a projecao oscilaria com o ritmo da distribuicao.
$script:ganhoPorReset = @(); $script:ganhoMarco = -1
Reset 1000 0
Reset 1000 4000                # nao distribuiu nada, mas ganhou 4000
Chk 'ganho em maos conta'      (@($script:ganhoPorReset) -join ',') '4000'

# --- 2. o que NAO pode entrar na conta ------------------------------------------------------------
# Reset de warmup: char fraco em Lost Tower, rende muito menos. Entra na media e estraga a projecao.
$script:ganhoPorReset = @(); $script:ganhoMarco = -1
Reset 0 0
Reset 900 0 'warmup'
Chk 'warmup nao entra'         (@($script:ganhoPorReset).Count) 0
# O reset que atravessa o /darmr: la o $ptsSent ZERA, entao a diferenca sai negativa e nao mede reset nenhum.
$script:ganhoPorReset = @(); $script:ganhoMarco = -1
Reset 60000 0
Reset 0 0                      # /darmr zerou o acumulado
Chk 'reset pos-/darmr nao entra' (@($script:ganhoPorReset).Count) 0
Chk '  (e o marco acompanha)'  $script:ganhoMarco 0

# --- 3. a projecao -------------------------------------------------------------------------------
$script:ganhoPorReset = @(5000,5000,5000); $script:ganhoMarco = 0
$script:ptsNeeded = 22000; $script:resets = 4; $script:ptsSent = 20000
Chk 'resets faltando arredonda pra cima' (Resets-Faltando) 5    # 22000/5000 = 4.4 -> 5
$script:ptsNeeded = 0
Chk 'sem pontos faltando, zero resets'   (Resets-Faltando) 0
$script:ptsNeeded = -1
Chk 'status nao lido: nao chuta'         (Resets-Faltando) ''
# Nos primeiros resets ainda nao ha medida propria: cai na media do MR em vez de nao dizer nada
$script:ganhoPorReset = @(); $script:ptsNeeded = 20000; $script:resets = 2; $script:ptsSent = 8000
Chk 'sem medida usa a media do MR'       (Resets-Faltando) 5    # 8000/2 = 4000; 20000/4000 = 5
Chk '  (e Pontos-Por-Reset nao inventa)' (Pontos-Por-Reset) ''
# Uma medida so nao tem mediana que preste
$script:ganhoPorReset = @(5000)
Chk 'uma medida nao basta'               (Pontos-Por-Reset) ''
# E o char sem nenhum reset ainda nao permite projetar nada
$script:ganhoPorReset = @(); $script:resets = 0; $script:ptsSent = 0; $script:ptsNeeded = 20000
Chk 'sem resets, sem projecao'           (Resets-Faltando) ''

# --- 4. o piso do reset tem que saber DESCER ------------------------------------------------------
# Era so-sobe: a mensagem do servidor ("precisa estar no level 350") empurrava o piso pra cima e ele ficava la,
# gravado no estado.txt. A exigencia do servidor pode CAIR (evento, mudanca de regra, item que desconta level),
# e ai uma unica recusa antiga prendia o char num alvo alto pra sempre.
Chk 'existe o alvo do CONFIG preservado' ($src -match '(?m)^\$TargetLevelConfig = \$TargetLevel') 'True'
Chk 'aceite abaixo do piso baixa o piso' ($src -match '\$lvlEnvio -lt \$script:LevelMinReset') 'True'
# A prova tem que ser um reset aceito DE PRIMEIRA: com reenvio o char subiu de level no meio e nao da pra dizer
# em qual tentativa o servidor cedeu - baixar o piso ali gravaria um numero que o servidor nunca aceitou.
Chk 'so conta sem reenvio'               ($src -match '\$resends -eq 0 -and \$null -ne \$lvlEnvio') 'True'
# E o alvo pedido volta a ser tentado de tempos em tempos, senao o piso aprendido nunca teria chance de cair.
Chk 're-testa o alvo do CONFIG'          ($src -match '(?s)function Ajustar-Alvo-Do-Proximo-Ciclo.*?\$script:TargetLevel = \$TargetLevelConfig') 'True'
Chk 'e o re-teste e chamado por reset'   ($src -match '(?m)^\s*Ajustar-Alvo-Do-Proximo-Ciclo\s*$') 'True'
Chk 'e o ganho e marcado por reset'      ($src -match '(?m)^\s*Marcar-Ganho-Do-Reset\s*$') 'True'

# o re-teste em si: so conta resets enquanto o alvo estiver acima do pedido, e dispara no N-esimo
if($src -notmatch '(?s)(function Ajustar-Alvo-Do-Proximo-Ciclo \{.*?\r?\n\})'){ throw "nao achei a Ajustar-Alvo-Do-Proximo-Ciclo" }
. ([scriptblock]::Create($Matches[1]))
$TargetLevelConfig = 320; $ResetRetestResets = 20
$script:TargetLevel = 350; $script:LevelMinReset = 350; $script:resetsDesdeTeste = 0
1..19 | ForEach-Object { Ajustar-Alvo-Do-Proximo-Ciclo }
Chk 'antes do N-esimo nao testa'         $script:TargetLevel 350
Ajustar-Alvo-Do-Proximo-Ciclo
Chk 'no N-esimo volta pro alvo pedido'   $script:TargetLevel 320
Chk '  (e o contador zera)'              $script:resetsDesdeTeste 0
# ja no alvo pedido: nao ha o que testar, e o contador nao pode ficar correndo
$script:TargetLevel = 320; $script:resetsDesdeTeste = 7
Ajustar-Alvo-Do-Proximo-Ciclo
Chk 'no alvo pedido nao conta nada'      $script:resetsDesdeTeste 0

if($script:erros){ "`n$script:erros FALHA(S)"; exit 1 }
"OK: ganho medido por reset (sem warmup nem /darmr), projecao de resets, e o piso de reset sobe E desce"
