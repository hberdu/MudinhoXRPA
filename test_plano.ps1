# Self-check do PLANO declarado no start (nao toca no jogo): .\test_plano.ps1
# O ciclo do bot e "N resets no spot de warmup, depois o spot normal ate fechar o cap, entao /darmr", mas isso
# vivia espalhado por quatro variaveis de CONFIG e duas de estado. Pra saber o que ele ia fazer era preciso
# juntar tudo de cabeca - e quando ele fazia OUTRA coisa (fase errada retomada do estado.txt, spot trocado),
# so dava pra perceber varios minutos depois, no meio do log. Declarado no start, uma linha desmente a outra.
$src = Get-Content "$PSScriptRoot\mudinhox_rpa.ps1" -Raw
$script:erros = 0
function Chk($n,$got,$exp){ if("$got" -ne "$exp"){ "FALHOU $n : '$got' != '$exp'"; $script:erros++ } }
function Tem($n,$hay,$needle){ if("$hay" -notlike "*$needle*"){ "FALHOU $n : nao achei '$needle' em '$hay'"; $script:erros++ } }

$script:linhas = @()
function Log($m){ $script:linhas += $m }
if($src -notmatch '(?s)(function Log-Plano \{.*?\r?\n\})'){ throw "nao achei a Log-Plano" }
. ([scriptblock]::Create($Matches[1]))

# CONFIG de verdade, lido do arquivo: o teste tem que falhar se alguem trocar o spot e esquecer do resto.
foreach($v in 'WarmupResets','WarmupTesteSec'){
  if($src -notmatch "(?m)^\`$$v\s*=\s*(\d+)"){ throw "nao achei o `$$v no CONFIG" }
  Set-Variable $v ([int]$Matches[1])
}
foreach($v in 'WarmupCmd','WarpCmd','MixCmd'){
  if($src -notmatch "(?m)^\`$$v\s*=\s*'([^']+)'"){ throw "nao achei o `$$v no CONFIG" }
  Set-Variable $v $Matches[1]
}
$WarmupTeste = $false

# --- 1. o plano confere com o CONFIG --------------------------------------------------------------
$script:linhas = @(); $script:modo = 'reset'; $script:phase = 'warmup'; $script:warmupCount = 0
$script:TargetLevel = 315; $script:LevelMinReset = 315; $script:resets = 0; $script:ptsSent = 0
Log-Plano
Chk 'sao duas linhas'                $script:linhas.Count 2
Tem 'diz quantos resets de warmup'   $script:linhas[0] "$WarmupResets resets em $WarmupCmd"
Tem 'diz o spot normal depois'       $script:linhas[0] "depois $WarpCmd"
Tem 'e onde isso termina'            $script:linhas[0] '/darmr'
Tem 'diz a fase atual'               $script:linhas[1] "warmup 0/$WarmupResets"
Tem 'e o proximo passo concreto'     $script:linhas[1] "vai pra $WarmupCmd"
Tem 'diz o level de reset'           $script:linhas[1] 'reseta no level 315'

# --- 2. warmup ja cumprido: o proximo passo muda ---------------------------------------------------
# Retomar do estado.txt na fase normal e o caso em que o plano MAIS importa: o bot nao vai pro Lost Tower, e
# sem esta linha isso so apareceria quando o /k37 fosse embora no log.
$script:linhas = @(); $script:phase = 'normal'; $script:warmupCount = $WarmupResets
Log-Plano
Tem 'fase normal vai pro spot normal' $script:linhas[1] "fase normal -> vai pra $WarpCmd"
if($script:linhas[1] -like "*$WarmupCmd*"){ "FALHOU 'na fase normal nao promete warmup'"; $script:erros++ }

# --- 3. modo joias nao reseta ----------------------------------------------------------------------
$script:linhas = @(); $script:modo = 'joias'
Log-Plano
Tem 'modo joias aparece'             $script:linhas[1] 'MODO JOIAS'
Tem 'e avisa que nao reseta'         $script:linhas[1] 'NAO reseta'

# --- 4. o $WarmupTeste muda o ciclo, e o plano tem que dizer ---------------------------------------
# Ligado, o bot TESTA o spot normal antes e pode pular o warmup inteiro. Um plano que continuasse prometendo
# "3 resets em losttower7" estaria mentindo - e mentira no log e pior que silencio.
$script:linhas = @(); $script:modo = 'reset'; $script:phase = 'warmup'; $WarmupTeste = $true
Log-Plano
Tem 'com WarmupTeste o plano muda'   $script:linhas[0] "TESTA $WarpCmd primeiro"
if($script:linhas[0] -like "*$WarmupResets resets em*"){ "FALHOU 'com WarmupTeste nao promete os N resets'"; $script:erros++ }

# --- 5. e o plano e logado DEPOIS de o estado ser retomado -----------------------------------------
# Antes do Load-Estado ele imprimiria o CONFIG cru e diria "warmup 0/3" mesmo com 2 resets ja feitos.
Chk 'Log-Plano vem depois do Load-Estado' ($src -match '(?s)Load-Estado.*?Log-Plano\s*#.*?\r?\nwhile\(-not \$script:stop\)') 'True'

if($script:erros){ "`n$script:erros FALHA(S)"; exit 1 }
"OK: o plano declarado no start bate com o CONFIG e com a fase retomada ($WarmupResets x $WarmupCmd -> $WarpCmd -> /darmr)"
