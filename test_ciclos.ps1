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

if($script:erros -eq 0){ "OK: mediana ignora etiquetas, culpa dividida certo, formato antigo aceito" }
else { "$($script:erros) FALHA(S)"; exit 1 }
