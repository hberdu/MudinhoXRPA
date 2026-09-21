# Self-check do destravamento por ESC no Distribute-Points (nao toca no jogo): .\test_travado.ps1
# 19/09: painel de status aberto o jogo inteiro. /f e /v "enviados" (Send-Chat devolvia $true) 2972x cada,
# mas o servidor nunca aplicava - 7h28 com os MESMOS 464 pontos na tela. O bot ja detectava isso ("pontos
# nao baixam"), so que so desistia (return) e esperava o proximo tick repetir o mesmo comando contra a mesma
# trava. Agora, ao detectar, da ESC (Unstick-Tudo) e tenta de novo DENTRO da mesma chamada - sem exceder o
# teto de 8 voltas do guard (nao pode virar loop infinito se o ESC tambem nao resolver).
$StatMinAvail = 1
$StatCongeladoN = 2   # so pra existir: o detector de painel CONGELADO (sibling, guard==0) nao pode disparar primeiro
$StatTravadoAviso = 3
$src = Get-Content "$PSScriptRoot\mudinhox_rpa.ps1" -Raw
if($src -notmatch '(?s)(function Distribute-Points \{.*?)\r?\nfunction Tick-Stats'){ throw "nao achei a Distribute-Points" }
. ([scriptblock]::Create($Matches[1]))

$script:erros = 0
function Chk($n,$got,$exp){ if("$got" -ne "$exp"){ "FALHOU $n : '$got' != '$exp'"; $script:erros++ } }

$StatCmds = @( @{Cmd='/f';Key='For'}, @{Cmd='/a';Key='Agi'}, @{Cmd='/v';Key='Vit'}, @{Cmd='/e';Key='Ene'} )
function Capture-Game { $null }                       # sem level pra ler: pula o bloco de level, vai direto pro status
function Log($m){ $script:logs += $m }
function Wait($s){}
function Tag-Ciclo($t){ $script:tags += $t }
function Save-Estado {}
function Master-Reset { $script:masterResets++ }
function Points-Needed($st){ 99999 }                   # nunca "no maximo": nao entra no /darmr
function Perto-Do-Max($st){ $false }
function Stat-Stage($st){ 5000 }
$script:travadoN = 0   # script-scoped de verdade no bot: sobrevive entre chamadas de Distribute-Points

# --- cenario real: pontos NUNCA mudam (servidor engoliu os comandos) ------------------------------
$script:logs = @(); $script:tags = @(); $script:masterResets = 0
$script:readStatusN = 0; $script:sendChatN = 0; $script:unstickN = 0; $script:notifyN = 0; $script:shots = @()
$script:stFp = ''; $script:stFpLvl = $null; $script:stFpN = 0; $script:lvlPrev = $null   # fingerprint do detector CONGELADO, zerado (ver StatCongeladoN acima)
function Read-Status { $script:readStatusN++; @{ For=100; Agi=100; Vit=100; Ene=100; Pts=500 } }
function Plan-Stats($st,$p){ ,@('/f 50') }
function Send-Chat($cmd,[switch]$KeepFocus){ $script:sendChatN++; $true }   # "digita" com sucesso, mas o servidor ignora (Pts acima nunca cai)
function Unstick-Tudo { $script:unstickN++ }
function Save-Shot($nome){ $script:shots += $nome; "captcha\$nome" }
function Notify-Once($k,$t,$m){ $script:notifyN++ }

$script:stop = $false
Distribute-Points

Chk 'esgota as 8 voltas do guard (nao desiste na primeira trava)'  $script:readStatusN 8
Chk 'ESC exatamente 2x (guard 2 e 5, com 500 sempre igual)'        $script:unstickN 2
# REGRESSAO (20/09): o ESC reseta $prevP pra -1 pra exigir 2 leituras frescas antes de destravar de novo - uma
# variavel SEPARADA ($prevPReal) tem que guardar a ultima leitura de verdade, senao a 1a leitura apos CADA ESC
# comparava contra o -1 sentinela, achava "mudou" e zerava $travadoN sozinho - o aviso nunca disparava de verdade.
Chk '$travadoN NAO reseta sozinho a cada ESC (pontos continuam nos MESMOS 500)' $script:travadoN 2
Chk 'etiqueta o ciclo como travado'                                 (@($script:tags | Select-Object -Unique) -join ',') 'travado'
Chk 'continua tentando /f entre os ESCs (nao trava mudo)'          ($script:sendChatN -ge 4) $true
Chk 'nao confunde travado com "no maximo"'                          $script:masterResets 0
# so 2 ESCs nesta chamada (guard de 8 nao alcanca o 3o) - o aviso ($StatTravadoAviso=3) e pra so disparar
# numa chamada FUTURA, quando o $travadoN persistido cruzar o teto. Nao pode disparar cedo demais.
Chk 'ainda nao cruzou o aviso: sem Notify' $script:notifyN 0
Chk 'ainda nao cruzou o aviso: sem print'  $script:shots.Count 0

# --- chamada seguinte, MESMA trava (persistindo $travadoN=2 de antes): cada chamada roda os 8 guards inteiros
#     e da 2 ESCs (igual a primeira, o cenario continua travado do inicio ao fim) - entao esta cruza o aviso
#     (3) no meio dela e termina em 4. $travadoN e $script:, sobrevive entre chamadas igual no bot de verdade.
$script:unstickN = 0; $script:readStatusN = 0
Distribute-Points
Chk 'trava persistente: acumula entre chamadas' $script:travadoN 4
Chk 'cruzou o aviso: Notify disparou'            ($script:notifyN -ge 1) $true
Chk 'cruzou o aviso so 1x: salva UM print so'    $script:shots.Count 1
Chk 'o print e o certo'                          $script:shots[0] 'stat_travado.png'

# --- cenario saudavel: pontos CAEM a cada rodada - Unstick-Tudo nunca deveria entrar aqui ----------
$script:logs = @(); $script:tags = @(); $script:masterResets = 0
$script:readStatusN = 0; $script:sendChatN = 0; $script:unstickN = 0; $script:travadoN = 0
$script:ptsAtual = 300
function Read-Status { $script:readStatusN++; @{ For=100; Agi=100; Vit=100; Ene=100; Pts=$script:ptsAtual } }
function Plan-Stats($st,$p){ if($p -lt 100){ ,@() } else { $script:ptsAtual -= 100; ,@('/f 100') } }   # simula o servidor aceitando de verdade
function Send-Chat($cmd,[switch]$KeepFocus){ $script:sendChatN++; $true }

$script:stop = $false
Distribute-Points

Chk 'saudavel: nunca chama ESC'               $script:unstickN 0
Chk 'saudavel: gastou os pontos (Plan-Stats zerou)' $script:sendChatN 3
Chk 'saudavel: travadoN fica em 0'                   $script:travadoN 0

# --- recupera sozinho: trava, UM ESC, dai os pontos voltam a cair - travadoN tem que voltar a 0 -----
$script:logs = @(); $script:tags = @(); $script:unstickN = 0; $script:travadoN = 0; $script:readStatusN = 0
function Read-Status {
  $script:readStatusN++
  if($script:readStatusN -le 3){ @{ For=100; Agi=100; Vit=100; Ene=100; Pts=500 } }   # trava 3 leituras (1 ESC)
  else { @{ For=100; Agi=100; Vit=100; Ene=100; Pts=(500 - ($script:readStatusN - 3) * 50) } }   # dai desce de verdade
}
function Plan-Stats($st,$p){ ,@('/f 50') }
$script:stop = $false
Distribute-Points
Chk 'recupera: deu pelo menos 1 ESC'      ($script:unstickN -ge 1) $true
Chk 'recupera: travadoN volta a 0 sozinho' $script:travadoN 0

if($script:erros -eq 0){ "OK: pontos travados (comando digitado mas o servidor ignora) levam a ESC + retentativa, com teto de 8 voltas; o aviso/print so disparam ao cruzar `$StatTravadoAviso de verdade, sem reset falso a cada ESC; caminho saudavel nao aciona o ESC" }
else { "$($script:erros) FALHA(S)"; exit 1 }
