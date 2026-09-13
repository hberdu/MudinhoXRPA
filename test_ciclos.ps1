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
if($script:erros -eq 0){ "OK: mediana ignora etiquetas, culpa dividida certo, Tick-Stats so rele quando precisa" }
else { "$($script:erros) FALHA(S)"; exit 1 }
