# Self-check da metrica de ciclos (nao toca no jogo): .\test_ciclos.ps1
# A metrica do tail so serve se a MEDIANA ignorar as etiquetas e a culpa for atribuida certo.
$src = Get-Content "$PSScriptRoot\mudinhox_rpa.ps1" -Raw
if($src -notmatch '(?s)(\$script:tagsCiclo = @\(\).*?)\r?\nfunction Metrics'){ throw "nao achei o bloco Tag-Ciclo..Mediana" }
. ([scriptblock]::Create($Matches[1]))

$script:erros = 0
function Chk($n,$got,$exp){ if("$got" -ne "$exp"){ "FALHOU $n : '$got' != '$exp'"; $script:erros++ } }

# CicloSeg/CicloTags aceitam os dois formatos (o estado.txt antigo so tinha numeros)
Chk 'CicloSeg sem tag' (CicloSeg '88') 88
Chk 'CicloSeg com tag' (CicloSeg '191:captcha+warp') 191
Chk 'CicloTags sem tag' (CicloTags '88') ''
Chk 'CicloTags com tag' (CicloTags '191:captcha+warp') 'captcha+warp'

# mediana tem que ignorar as etiquetas e nao se deixar puxar pelos outliers
Chk 'mediana mista' (Mediana @('88','91','102:stall','3193:reset','77')) 91
Chk 'mediana vazia' (Mediana @()) 0

# atribuicao de culpa: excesso sobre a mediana, dividido entre as causas do ciclo
$ciclos = @('90','90','90','90','290:captcha','290:warp+stall')
$med = Mediana $ciclos
Chk 'mediana da amostra' $med 90
$lentos = @($ciclos | Where-Object { (CicloSeg $_) -gt ($med * 1.5) })
Chk 'quantos lentos' $lentos.Count 2
$porCausa = @{}
foreach($c in $lentos){
  $extra = (CicloSeg $c) - $med
  $tags = @((CicloTags $c) -split '\+' | Where-Object { $_ })
  if(-not $tags.Count){ $tags = @('?') }
  foreach($t in $tags){ $porCausa[$t] = [int]$porCausa[$t] + [int]($extra / $tags.Count) }
}
Chk 'captcha leva o excesso inteiro'   $porCausa['captcha'] 200
Chk 'warp leva metade do ciclo dele'   $porCausa['warp']    100
Chk 'stall leva a outra metade'        $porCausa['stall']   100
Chk 'nao inventa causa'                $porCausa.Keys.Count 3

# ciclo lento SEM etiqueta vira '?' em vez de sumir da conta
$porCausa2 = @{}
$c = '290'; $extra = (CicloSeg $c) - 90
$tags = @((CicloTags $c) -split '\+' | Where-Object { $_ }); if(-not $tags.Count){ $tags = @('?') }
foreach($t in $tags){ $porCausa2[$t] = [int]$porCausa2[$t] + [int]($extra / $tags.Count) }
Chk 'lento sem etiqueta vira ?' $porCausa2['?'] 200

# Tag-Ciclo nao duplica
$script:tagsCiclo = @(); Tag-Ciclo 'warp'; Tag-Ciclo 'warp'; Tag-Ciclo 'stall'
Chk 'Tag-Ciclo sem duplicata' ($script:tagsCiclo -join '+') 'warp+stall'


# --- Tick-Stats so rele o status quando ha motivo -------------------------------------------------
# 84 leituras do log logaram "0 a distribuir": o level estava parado, entao nao havia ponto novo pra
# gastar. Cada uma custa foco + 2-3s. A regra: rele se o level MUDOU, ou se estourou o teto de tempo.
$StatEverySec = 15; $StatMaxSec = 90; $JitterPct = 0
function Jit([double]$sec){ $sec }
$script:chamadas = 0
function Distribute-Points { $script:chamadas++ }
$src2 = Get-Content "$PSScriptRoot\mudinhox_rpa.ps1" -Raw
if($src2 -notmatch '(?s)(\$script:statLvlLast = -1.*?\r?\n\})'){ throw "nao achei o Tick-Stats" }
. ([scriptblock]::Create($Matches[1]))

$script:statDue = Get-Date; $script:lvlPrev = 100
Tick-Stats                                  # primeira leitura sempre acontece
Chk 'primeira leitura' $script:chamadas 1
$script:statDue = Get-Date; Tick-Stats      # level parado, dentro do teto: pula
Chk 'level parado nao rele' $script:chamadas 1
$script:statDue = Get-Date; $script:lvlPrev = 101; Tick-Stats
Chk 'level subiu, rele' $script:chamadas 2
$script:statDue = Get-Date; $script:statMax = (Get-Date).AddSeconds(-1); Tick-Stats
Chk 'teto de tempo forca a releitura' $script:chamadas 3
# level ilegivel (OCR falhou): nao pode congelar a distribuicao pra sempre
$script:statDue = Get-Date; $script:lvlPrev = $null; Tick-Stats
Chk 'level ilegivel rele mesmo assim' $script:chamadas 4
# e o intervalo normal continua valendo: sem $statDue vencido, nao le nada
$script:statDue = (Get-Date).AddSeconds(30); $script:lvlPrev = 999; Tick-Stats
Chk 'respeita o intervalo' $script:chamadas 4
# perto do maximo o portao do level NAO vale: sao os ultimos pontos que liberam o /darmr
$StatEveryNearSec = 5
$script:pertoDoMax = $true; $script:statDue = Get-Date; $script:lvlPrev = 999; $script:statLvlLast = 999
Tick-Stats
Chk 'perto do maximo le mesmo com o level parado' $script:chamadas 5
$script:statDue = Get-Date; Tick-Stats
Chk 'e continua lendo' $script:chamadas 6
$script:pertoDoMax = $false; $script:statDue = Get-Date; Tick-Stats
Chk 'longe do maximo volta a respeitar o level' $script:chamadas 6
# recuo progressivo: leitura que nao rende comando espaca a proxima (56% das leituras do log eram assim)
$StatMaxSec = 90
$script:pertoDoMax = $false; $script:statVazias = 0; $script:lvlPrev = 500; $script:statLvlLast = -1
$script:statDue = Get-Date; Tick-Stats
Chk 'sem leituras vazias, intervalo base' ([int]($script:statDue - (Get-Date)).TotalSeconds) 15
$script:statVazias = 3; $script:statDue = Get-Date; $script:lvlPrev = 501; Tick-Stats
Chk '3 vazias seguidas: 15s vira 120s, cortado no teto de 90s' ([int]($script:statDue - (Get-Date)).TotalSeconds) 90
$script:statVazias = 1; $script:statDue = Get-Date; $script:lvlPrev = 502; Tick-Stats
Chk '1 vazia: dobra pra 30s' ([int]($script:statDue - (Get-Date)).TotalSeconds) 30
# perto do maximo o recuo e curto: la os ultimos pontos e que liberam o /darmr
$script:pertoDoMax = $true; $script:statVazias = 5; $script:statDue = Get-Date; Tick-Stats
Chk 'perto do maximo o recuo para em 4x o intervalo curto' ([int]($script:statDue - (Get-Date)).TotalSeconds) 20

# --- chegou no alvo: nao paga a rodada de Ticks antes de resetar ----------------------------------
# O `until` do laco de farm so e avaliado DEPOIS de Tick-Stats/Inventory/Msgs/Progresso/Human rodarem. Medido no
# log: 10s entre o level passar do alvo e o /resetar sair, em todo reset - um Read-Status (~3s), um comando de
# distribuicao (~2.5s) e as vezes um disfarce do Tick-Human. Nada disso muda o que vem a seguir, que e resetar.
Chk 'no alvo, pula as Ticks'    ($src -match '(?s)if\(\$null -eq \$lvl -or \$lvl -lt \$TargetLevel\)\{\s*\r?\n\s*Tick-Stats') 'True'
# E o intervalo de status NAO pode voltar a inflar: o recuo do Tick-Stats multiplica esta base, entao cada
# segundo aqui vira o dobro (ou mais) de tempo cego. Medido: 35 nao rendeu nada (99s/reset contra 100s) e dobrou
# todo intervalo cego - um ciclo ficou 77s sem olhar atributo nem level com o char ja passando do alvo.
if($src -notmatch '(?m)^\$StatEverySec\s*=\s*(\d+)'){ throw "nao achei o `$StatEverySec" }
Chk 'intervalo de status curto' ([int]$Matches[1] -le 20) 'True'

# --- miss infinito: detectar sem esperar 40s e sem acusar por leitura que falhou ------------------
# A metrica do proprio bot aponta 'stall' como 23-27% de TODO o tempo, e a maior parte e latencia de
# deteccao: 113 disparos x 40s = ~75 min so pra perceber. Agora sao DUAS condicoes - N leituras iguais
# seguidas (sinal forte, e leitura que falhou nao chega aqui) E um piso de segundos (char fraco pos-reset).
$StallReads = 3; $StallMinSec = 15
$script:reteleportou = 0; $script:destravouStall = 0
function Log($m){ }
function In-Farm($img){ $script:noSpot }
function Warp-To-Spot { $script:reteleportou++; $true }
function Start-Helper { $true }
function Close-Popup { }
function Focus-Game { $true }
# A guarda dos pontos rele o status quando o valor em cache nao cresceu: com $StatEverySec em 35s, decidir
# "travado" com numero velho seria o mesmo falso positivo que ela existe pra evitar. $script:frescoPts = $null
# simula "a leitura falhou" (tem que cair de volta no cache, nao travar).
$script:frescoPts = $null; $script:lidoFresco = 0
function Read-Status { $script:lidoFresco++; if($null -eq $script:frescoPts){ $null } else { @{ For=0; Agi=0; Vit=0; Ene=0; Pts=$script:frescoPts } } }
function Click-Client($x,$y){ $script:destravouStall++; $true }
function Walk-Forward { }
function Wait([double]$s){ }
# O botao play nao tem mais coordenada fixa: o Play-XY procura o icone no canto do canvas e devolve onde achou.
# Aqui devolve um ponto qualquer - o que este teste mede e o DETECTOR de miss infinito, nao onde se clica.
function Play-XY { @{ X = 77; Y = 33 } }
if($src -notmatch '(?s)(function Check-Progress.*?\r?\n\})'){ throw "nao achei a Check-Progress" }
. ([scriptblock]::Create($Matches[1]))

function ZeraStall($segAtras){ $script:lvlPrev = 100; $script:lvlSame = 0; $script:lvlChangedAt = (Get-Date).AddSeconds(-$segAtras); $script:noSpot = $true; $script:destravouStall = 0; $script:reteleportou = 0; $script:ptsLeft = 0; $script:ptsSent = 0; $script:stallPts = 0 }   # base = ganho atual (0+0); -1 aqui faria a 1a avaliacao parecer progresso

# level parado ha bastante tempo, mas ainda nao houve $StallReads leituras: nao dispara
ZeraStall 60
Chk 'antes de 3 leituras iguais nao dispara' (Check-Progress 100 $null) $true   # 1a
$null = Check-Progress 100 $null                                                # 2a
Chk '  (nada de desbugar ainda)'             $script:destravouStall     0
$null = Check-Progress 100 $null                                                # 3a
Chk 'na 3a leitura igual dispara'            $script:destravouStall     1

# 3 leituras iguais mas cedo demais no relogio: e o char fraco logo apos o reset, nao um travamento
ZeraStall 5
1..4 | ForEach-Object { $null = Check-Progress 100 $null }
Chk 'sem o piso de segundos nao dispara'     $script:destravouStall     0

# o level mudou: zera tudo (e o caminho normal)
ZeraStall 60
$null = Check-Progress 100 $null; $null = Check-Progress 101 $null
Chk 'level novo zera o contador'             $script:lvlSame            0
$null = Check-Progress 101 $null
Chk 'e recomeca a contagem do zero'          $script:destravouStall     0

# PONTOS SUBINDO = char matando, mesmo com o level parado. O level anda em degraus (level alto, mob fraco, teto),
# e os pontos disponiveis sao a prova direta de que ele nao esta travado. Medido no MR #15, o melhor do log: 3
# dos 19 ciclos tiveram miss infinito e somaram 646s de excesso sobre o p25 - um com 10 disparos seguidos e o
# char ganhando ponto o tempo todo (16, 32, 64...). Maior causa isolada da cauda lenta, acima do captcha.
ZeraStall 60
$script:ptsLeft = 64   # subiu de 0 pra 64 entre as leituras
$null = Check-Progress 100 $null; $null = Check-Progress 100 $null; $null = Check-Progress 100 $null
Chk 'pontos subindo NAO dispara'             $script:destravouStall     0
Chk '  (e o contador de leituras zera)'      $script:lvlSame            0
# ...mas pontos PARADOS com o level parado continua sendo travamento de verdade
ZeraStall 60
$null = Check-Progress 100 $null; $null = Check-Progress 100 $null; $null = Check-Progress 100 $null
Chk 'pontos parados ainda dispara'           $script:destravouStall     1
# DISTRIBUIR NAO PODE PARECER TRAVAMENTO. Era o bug que mais custava tempo no bot: a guarda comparava o SALDO
# ($ptsLeft), e o /f /a /v /e zera o saldo - entao ~20s depois de toda distribuicao ela via "0 pontos, nao subiu"
# e deixava passar um falso positivo. Medido no rpa.log: 36 dos 105 disparos (34%) cairam ate 30s depois de um
# comando de distribuicao, com o char matando normal. Os ciclos marcados 'stall' somavam 51% de TODO o tempo do
# bot. A conta certa e o GANHO ACUMULADO ($ptsSent + $ptsLeft), que a distribuicao nao muda - ela so move valor
# de um lado pro outro. Este teste antes esperava o disparo, ou seja: ele guardava o bug.
ZeraStall 60
$script:ptsLeft = 900; $null = Check-Progress 100 $null; $null = Check-Progress 100 $null; $null = Check-Progress 100 $null
$script:ptsSent = 900; $script:ptsLeft = 16    # gastou os 900 num /f e ja matou mais 16
$script:lvlChangedAt = (Get-Date).AddSeconds(-60)
1..3 | ForEach-Object { $null = Check-Progress 100 $null }
Chk 'distribuir NAO dispara'                 $script:destravouStall     0
# ...e o char parando DE VERDADE depois de distribuir continua sendo pego: o ganho para de crescer.
$script:lvlChangedAt = (Get-Date).AddSeconds(-60)
1..3 | ForEach-Object { $null = Check-Progress 100 $null }
Chk 'parar apos distribuir ainda dispara'    $script:destravouStall     1

# LEITURA FRESCA antes de gastar os ~17s de destravamento. O $ptsLeft em cache pode ter ate $StatEverySec (35s)
# de idade, e com o cache velho a guarda cai no mesmo falso positivo que ela existe pra evitar. Uma leitura
# custa ~2.5s e so acontece aqui, quando as outras duas condicoes ja apontaram travamento.
ZeraStall 60
$script:frescoPts = 900; $script:lidoFresco = 0      # cache diz 0, mas o char ganhou 900 desde a ultima leitura
1..3 | ForEach-Object { $null = Check-Progress 100 $null }
Chk 'rele o status antes de destravar'       $script:lidoFresco         1
Chk 'ponto fresco cancela o falso positivo'  $script:destravouStall     0
# ...e com o status confirmando zero, destrava mesmo
ZeraStall 60
$script:frescoPts = 0
1..3 | ForEach-Object { $null = Check-Progress 100 $null }
Chk 'status fresco confirma: destrava'       $script:destravouStall     1
# leitura que FALHA nao pode travar nem virar "progresso": cai de volta no cache e decide com ele
ZeraStall 60
$script:frescoPts = $null
1..3 | ForEach-Object { $null = Check-Progress 100 $null }
Chk 'leitura falha cai no cache'             $script:destravouStall     1
# e quando o cache JA mostra ganho, nao gasta leitura nenhuma
ZeraStall 60
$script:ptsLeft = 700; $script:frescoPts = 0; $script:lidoFresco = 0
1..3 | ForEach-Object { $null = Check-Progress 100 $null }
Chk 'cache com ganho nao rele'               $script:lidoFresco         0
Chk '  (e nao destrava)'                     $script:destravouStall     0

# fora do spot o remedio e outro: re-teleporta em vez de dancar no lugar
ZeraStall 60; $script:noSpot = $false
$null = Check-Progress 100 $null; $null = Check-Progress 100 $null; $r = Check-Progress 100 $null
Chk 'fora do spot re-teleporta'              $script:reteleportou       1
# UM valor, nao dois. Start-Helper devolve $true/$false e sem descartar isso a Check-Progress saia com
# @($true,$false) - array de 2 itens e sempre verdadeiro, o `if(-not (...))` do chamador nunca entrava e o
# ciclo nao reiniciava depois de re-teleportar.
Chk 'devolve UM valor so'                    (@($r).Count)              1
Chk 'e manda reiniciar o ciclo'              $r                         $false
Chk '  (sem dancar no lugar)'                $script:destravouStall     0


# --- barra de progresso do MR ---------------------------------------------------------------------
# A barra mede PONTOS ate o cap, nao resets: quantos resets cabem num MR muda com o alvo, com o spot e
# com a fase, entao contar reset daria uma barra que anda torto. $ptsNeeded = -1 e "ainda nao li o status".
$StatMaxValue = 32767
if($src -notmatch '(?s)(function Progresso-MR \{.*?\r?\n\})'){ throw "nao achei a Progresso-MR" }
. ([scriptblock]::Create($Matches[1]))
$script:ptsTotal = 4 * $StatMaxValue

$script:ptsNeeded = -1
Chk 'sem leitura de status, barra em 0'  (Progresso-MR) 0
$script:ptsNeeded = $script:ptsTotal
Chk 'char zerado (pos-MR), barra em 0'   (Progresso-MR) 0
$script:ptsNeeded = 0
Chk 'cap fechado, barra cheia'           (Progresso-MR) 1
$script:ptsNeeded = [int]($script:ptsTotal / 2)
Chk 'metade do caminho'                  ([Math]::Round((Progresso-MR),2)) 0.5
# leitura ruim nao pode estourar a barra (Value fora do Minimum..Maximum lanca excecao no WinForms)
$script:ptsNeeded = $script:ptsTotal * 3
Chk 'ptsNeeded absurdo nao vai abaixo de 0' (Progresso-MR) 0
$script:ptsNeeded = -50
Chk 'ptsNeeded negativo tambem cai em 0'    (Progresso-MR) 0

# --- a barra desenhada (dois paineis, nao ProgressBar) --------------------------------------------
# O ProgressBar do WinForms ignora BackColor/ForeColor com visual styles e sai sempre verde - a unica cor que a
# HUD do jogo nao tem. Virou trilho + preenchimento, e ai a largura passa a ser conta nossa: sem o clamp, uma
# fracao fora de 0..1 daria Width negativo (excecao) ou um painel maior que o trilho.
if($src -notmatch '(?s)(function Set-Barra(.*?){.*?\r?\n\})'){ throw "nao achei a Set-Barra" }
. ([scriptblock]::Create($Matches[1]))
$script:pintou = 0
$script:barraBox = [pscustomobject]@{ IsDisposed = $false }
$script:barraBox | Add-Member ScriptMethod Invalidate { $script:pintou++ }
Set-Barra 0.5;  Chk 'guarda a fracao'            $script:barraPct  0.5
Chk '  (e manda repintar)'                       $script:pintou    1
Set-Barra 1.0;  Chk 'cheia e 1'                  $script:barraPct  1
Set-Barra 3.0;  Chk 'fracao absurda e cortada'   $script:barraPct  1
Set-Barra -1.0; Chk 'fracao negativa vira 0'     $script:barraPct  0
# Chamada ANTES do Show-Ui nao pode explodir: o Log roda desde a primeira linha do script e ja chama Set-Barra,
# muito antes de existir janela.
$script:barraBox = $null
Set-Barra 0.5
Chk 'sem UI ainda, nao quebra'                   $script:barraPct  0.5

if($script:erros -eq 0){ "OK: mediana ignora etiquetas, culpa dividida certo, Tick-Stats so rele quando precisa, miss infinito por leituras+tempo, barra do MR nao estoura" }
else { "$($script:erros) FALHA(S)"; exit 1 }
