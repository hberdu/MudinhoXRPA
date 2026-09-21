# Self-check do rotulo do minimapa (nao toca no jogo): .\test_mapa.ps1
# 17/09: depois do /losttower7 o bot leu o mapa como 'satan' em 8 warps seguidos, com o char JA na Lost Tower.
# "Satan" e a barra do pet no canto superior esquerdo. Numero de dano tem a mesma forma da coordenada do rotulo
# ("186,968"), e o nome era aceito a QUALQUER distancia a esquerda dela - com o rotulo sumido por um frame (tela
# carregando), o dano na altura da barra do pet virava "Satan 186,968", e a caixa errada ia pro cache.
# As posicoes abaixo sao as que o OCR devolveu nos prints reais (captcha\status_falhou.png, warp_falhou.png, web_hud.png).
$src = Get-Content "$PSScriptRoot\mudinhox_rpa.ps1" -Raw
$script:erros = 0
function Chk($n,$got,$exp){ if("$got" -ne "$exp"){ "FALHOU $n : '$got' != '$exp'"; $script:erros++ } }

if($src -notmatch '(?s)(function Achar-Rotulo-Mapa\(\$img\)\{.*?\r?\n\})'){ throw "nao achei a Achar-Rotulo-Mapa" }
. ([scriptblock]::Create($Matches[1]))

function W($t,$x,$y,$w,$h){ [pscustomobject]@{ Text = $t; BoundingRect = [pscustomobject]@{ X = $x; Y = $y; Width = $w; Height = $h } } }
function Crop-Bitmap { [pscustomobject]@{} | Add-Member -MemberType ScriptMethod -Name Dispose -Value {} -PassThru }
function Ocr-Bitmap($b){ [pscustomobject]@{ Lines = @([pscustomobject]@{ Words = $script:palavras }) } }
$img = [pscustomobject]@{ Width = 1920; Height = 1009 }
function Nome { $r = Achar-Rotulo-Mapa $img; if($r){ $r.Nome } else { '(nada)' } }

$satan = W 'Satan' 46 114 28 8
$dano  = W '186,968' 641 119 45 10

# o bug: rotulo ausente, dano na altura da barra do pet
$script:palavras = @($satan, $dano)
Chk 'dano longe nao transforma o pet em mapa' (Nome) '(nada)'

# rotulo na tela: acha ele, com pet e dano em volta
$script:palavras = @($satan, $dano, (W 'Losttower' 1692 79 55 9), (W '8,86' 1752 79 22 10))
Chk 'acha o rotulo colado na coordenada'      (Nome) 'losttower'

# web (aba do Chrome 1024x720): o vao medido tambem e de 7px
$script:palavras = @((W 'Satan' 43 202 34 10), (W 'Lorencia' 796 165 52 11), (W '132,125' 855 166 41 11))
Chk 'web: acha o rotulo'                      (Nome) 'lorencia'

if($script:erros -eq 0){ "OK: rotulo do minimapa so aceita nome colado na coordenada (pet 'Satan' + numero de dano nao viram mapa)" }
else { "$($script:erros) FALHA(S)"; exit 1 }
