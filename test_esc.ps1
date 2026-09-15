# Self-check do Close-Popup (nao toca no jogo): .\test_esc.ps1
# ESC neste jogo e um ALTERNADOR: com algo aberto ele FECHA, com nada aberto ele ABRE o menu principal - e esse
# menu tapa o minimapa, que e de onde o bot le o nome do mapa. Sem o mapa ele nao confirma warp e fica cego,
# reenviando /k37 pra sempre.
# Custou caro duas vezes: 4+ min em 04/09 e, em 15/09, um travamento que so ia sair no reinicio automatico - com
# o sensor tendo DETECTADO o problema ("minimapa continua ilegivel") e desistido assim mesmo.
# A licao que este teste guarda: num alternador, CONTAR PRENSAS NAO SERVE. Nao da pra saber quantas o estado
# atual exige, e uma a mais desfaz a anterior. Quem decide e o sensor.
$src = Get-Content "$PSScriptRoot\mudinhox_rpa.ps1" -Raw
$script:erros = 0
function Chk($n,$got,$exp){ if("$got" -ne "$exp"){ "FALHOU $n : '$got' != '$exp'"; $script:erros++ } }

if($src -notmatch '(?m)^\$EscMax\s*=\s*(\d+)'){ throw "nao achei o `$EscMax no CONFIG" }
$EscMax = [int]$Matches[1]
if($src -notmatch '(?s)(function Close-Popup \{.*?\r?\n\})'){ throw "nao achei a Close-Popup" }
. ([scriptblock]::Create($Matches[1]))

# MUNDO SIMULADO: uma pilha de coisas abertas. ESC tira a de cima; com a pilha vazia, ESC PoE o menu nela.
# O minimapa so e legivel quando o 'menu' nao esta aberto (popup no meio da tela nao tapa o minimapa).
$script:pilha = @()
$script:prensas = 0
function Press-Vk($vk, $hold, $gap){
  $script:prensas++
  if(@($script:pilha).Count){ $script:pilha = @($script:pilha | select -SkipLast 1) }
  else { $script:pilha = @('menu') }
}
function Read-Map($img){ if(@($script:pilha) -contains 'menu'){ '' } else { 'kant' } }
function Log($m){ $script:ultimoLog = $m }
function Start-Sleep { param($Milliseconds) }

function Cenario($nome, $inicial){
  $script:pilha = @($inicial); $script:prensas = 0; $script:ultimoLog = ''
  Close-Popup
  [pscustomobject]@{ Nome = $nome; Sobrou = (@($script:pilha) -join ','); Prensas = $script:prensas; Menu = (@($script:pilha) -contains 'menu') }
}

# --- 1. o caso de 15/09: o mix termina com o modal aberto ------------------------------------------
# 1a prensa fecha o modal -> pilha vazia -> minimapa legivel -> PARA. Se prensasse de novo as cegas, abriria o
# menu e o bot ficaria cego, que foi exatamente o que aconteceu.
$r = Cenario 'modal do mix aberto' @('modal_mix')
Chk 'fecha o modal'                    $r.Sobrou ''
Chk '  (e NAO abre o menu depois)'     $r.Menu   $false
Chk '  (gasta so a prensa cega)'       $r.Prensas 1

# --- 2. nada aberto: a prensa cega ABRE o menu, e o sensor tem que desfazer -------------------------
# E o caso que mais machuca, porque o bot chama Close-Popup "por garantia" em varios lugares.
$r = Cenario 'nada aberto' @()
Chk 'nao deixa o menu aberto'          $r.Menu   $false
Chk '  (a cega abriu, a conferida fechou)' $r.Prensas 2

# --- 3. duas coisas empilhadas: precisa de mais prensas, e o sensor permite ------------------------
# O contrato e "deixar o minimapa legivel", nao "fechar tudo": popup no MEIO da tela nao tapa o minimapa, entao
# o sensor nao o enxerga e a funcao para. Quem cobre esse resto e o tratamento de "voce nao pode se mover" do
# Warp-To-Spot. Escrevi este teste esperando pilha vazia e ele me corrigiu - a expectativa e que estava errada.
$r = Cenario 'popup por cima do modal' @('modal_mix','popup')
Chk 'minimapa fica legivel'            (Read-Map $null) 'kant'
Chk '  (e sem menu aberto)'            $r.Menu   $false

# --- 4. menu ja aberto quando entra (o estado de 15/09 03:28) --------------------------------------
$r = Cenario 'menu ja aberto'          @('menu')
Chk 'fecha o menu'                     $r.Menu   $false
Chk '  (uma prensa basta)'             $r.Prensas 1

# --- 5. ESC IGNORADO: para no teto, nao entra em laco ----------------------------------------------
# O jogo engole tecla em transicao (teleporte, loading). Se isso durar, o sensor nunca fica satisfeito - e sem
# teto a funcao prensaria pra sempre. Aqui o ESC nao faz nada e o minimapa nunca volta a ler.
$script:prensas = 0; $script:ultimoLog = ''
function Press-Vk($vk, $hold, $gap){ $script:prensas++ }   # engolido pelo jogo
function Read-Map($img){ '' }                              # nunca volta a ler
Close-Popup
Chk 'respeita o teto'                  $script:prensas ($EscMax + 1)
Chk '  (e avisa que desistiu)'         ($script:ultimoLog -like '*continua ilegivel*') $true

# --- 6. a regra que nao pode voltar: prensa cega e UMA ---------------------------------------------
# Duas cegas e o bug original - a segunda abre o menu quando a primeira ja resolveu.
$antes = ($src -split '(?s)function Close-Popup \{')[1]
$corpo = ($antes -split '(?m)^\}')[0]
$cegas = ([regex]::Matches(($corpo -split 'for\(')[0], 'Press-Vk 0x1B')).Count
Chk 'so UMA prensa as cegas'           $cegas 1

if($script:erros){ "`n$script:erros FALHA(S)"; exit 1 }
"OK: Close-Popup para pelo sensor, nao pela contagem (teto $EscMax), e nunca termina com o menu aberto"
