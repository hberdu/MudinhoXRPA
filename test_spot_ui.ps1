# Self-check dos campos WARMUP/NORMAL da janelinha (nao toca no jogo): .\test_spot_ui.ps1
# 20/09: comando do spot virou editavel na interface (antes so dava pra mudar editando o .ps1). Aplica-SpotUi e
# quem valida o texto digitado, atualiza a variavel de CONFIG em memoria e grava warpCmdUi=/warmupCmdUi= no
# estado.txt pra sobreviver a um restart. Formato invalido nao pode virar comando - o char mandaria lixo pro chat.
$src = Get-Content "$PSScriptRoot\mudinhox_rpa.ps1" -Raw
if($src -notmatch '(?s)(function Aplica-SpotUi.*?)\r?\nfunction Set-Barra'){ throw "nao achei a Aplica-SpotUi" }
. ([scriptblock]::Create($Matches[1]))

$script:erros = 0
function Chk($n,$got,$exp){ if("$got" -ne "$exp"){ "FALHOU $n : '$got' != '$exp'"; $script:erros++ } }

function Tb([string]$texto){ [pscustomobject]@{ Text = $texto; BackColor = 'inicial' } }
$script:logs = @(); function Log($m){ $script:logs += $m }
$script:saves = 0; function Save-Estado { $script:saves++ }
$HudPoco = 'poco'; $HudSangueCl = 'vermelho'   # cores de verdade sao System.Drawing.Color; aqui so precisam ser distintas

# --- campo NORMAL (WarpCmd): comando novo valido -------------------------------------------------
$WarpCmd = '/k37'; $script:warpCmdUi = ''; $script:WarpMap = 'kant'; $script:mapaBox = @{X=1;Y=2}
$script:saves = 0
$tb = Tb '/s21'
Aplica-SpotUi $tb 'WarpCmd' 'normal'
Chk 'aplica o comando novo'          $WarpCmd '/s21'
Chk 'grava pra sobreviver a restart' $script:warpCmdUi '/s21'
Chk 'invalida o mapa aprendido'      $script:WarpMap ''
Chk 'invalida a caixa do rotulo'     ($null -eq $script:mapaBox) 'True'
Chk 'gravou o estado'                $script:saves 1
Chk 'aplicou com sucesso: cor normal' $tb.BackColor $HudPoco

# --- mesmo valor: nao gasta Save-Estado a toa, nao mexe no mapa aprendido, e limpa vermelho de uma
#     rejeicao anterior mesmo sem mudar nada (senao ficaria tingido pra sempre) ---------------------
$WarpCmd = '/s21'; $script:warpCmdUi = '/s21'; $script:WarpMap = 'sela'; $script:saves = 0
$tb = Tb '/s21'; $tb.BackColor = $HudSangueCl   # simula campo ainda vermelho de uma tentativa invalida anterior
Aplica-SpotUi $tb 'WarpCmd' 'normal'
Chk 'sem mudanca, nao salva'         $script:saves 0
Chk 'sem mudanca, mapa intacto'      $script:WarpMap 'sela'
Chk 'sem mudanca, limpa vermelho'    $tb.BackColor $HudPoco

# --- formato invalido: reverte o campo, NAO aplica, e AVISA (tinge vermelho) - antes so revertia o
#     texto em silencio: sem estar olhando a janelinha na hora, nada dizia que a digitacao foi rejeitada -----
$WarpCmd = '/k37'; $script:warpCmdUi = ''; $script:saves = 0
foreach($ruim in 'k37', '', '   ', '/tem espaco'){
  $tb = Tb $ruim
  Aplica-SpotUi $tb 'WarpCmd' 'normal'
  Chk "rejeita '$ruim': mantem o CONFIG"      $WarpCmd '/k37'
  Chk "rejeita '$ruim': reverte o campo"      $tb.Text '/k37'
  Chk "rejeita '$ruim': nao salva"            $script:saves 0
  Chk "rejeita '$ruim': tinge de vermelho"    $tb.BackColor $HudSangueCl
}

# --- campo WARMUP (WarmupCmd): mesma validacao, mas NAO mexe no WarpMap/mapaBox (mapa generico 'lost', nao
#     depende do comando - qualquer /losttowerN mostra 'Lost Tower' no minimapa) --------------------
$WarmupCmd = '/losttower7'; $script:warmupCmdUi = ''; $script:WarpMap = 'kant'; $script:mapaBox = @{X=1;Y=2}
$script:saves = 0
$tb = Tb '/losttower3'
Aplica-SpotUi $tb 'WarmupCmd' 'warmup'
Chk 'warmup: aplica o comando novo'      $WarmupCmd '/losttower3'
Chk 'warmup: grava pra sobreviver'       $script:warmupCmdUi '/losttower3'
Chk 'warmup: NAO mexe no mapa do normal' $script:WarpMap 'kant'
Chk 'warmup: NAO mexe na caixa do rotulo' ($null -eq $script:mapaBox) 'False'

if($script:erros -eq 0){ "OK: campos WARMUP/NORMAL validam o formato, aplicam so quando muda, e invalidam o mapa aprendido so quando e o comando NORMAL que trocou" }
else { "$($script:erros) FALHA(S)"; exit 1 }
