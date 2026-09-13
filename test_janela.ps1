# Self-check de QUAL JANELA E O JOGO (nao toca no jogo): .\test_janela.ps1
# Tres bugs reais moram aqui, todos com o mesmo sintoma - "nao achei a janela" com o jogo aberto na tela:
#   1. Get-Process nao acha a aba do Chrome (multi-processo: MainWindowTitle expoe UMA janela por processo).
#   2. O array de resultado desenrolava na saida do `if` e $todas.Count virava $null com UMA janela casando.
#   3. Titulo de janela de navegador e o da ABA ATIVA - jogo em aba de fundo nao aparece pra ninguem.
$src = Get-Content "$PSScriptRoot\mudinhox_rpa.ps1" -Raw
$script:erros = 0
function Chk($n,$got,$exp){ if("$got" -ne "$exp"){ "FALHOU $n : '$got' != '$exp'"; $script:erros++ } }

# --- 1. achar a janela: EnumWindows, nunca Get-Process -----------------------------------------------
# Com o jogo aberto numa aba, a unica janela de chrome que o Get-Process enxergava era a barra
# "... is sharing a window." - a do jogo nao. Falso negativo silencioso.
Chk "acha janela por EnumWindows"  ($src -match "(?s)if\(\`$GameTitle\)\{.*?\[W\]::JanelasVisiveis") 'True'
Chk "nao volta pro Get-Process"    ($src -match "MainWindowTitle -match \`$GameTitle") 'False'
# $GameTitle e CONFIG (vazio = cliente desktop), entao o teste nao trava o valor - so a regra: se estiver
# preenchido, tem que estar ancorado em "[GAME]". Ha outra aba "MudinhoX - Servidor de Mu Online" e casar com ela
# faria o bot mirar a janela errada (ler a HUD de um site e clicar nele).
if($src -notmatch "(?m)^\`$GameTitle\s*=\s*'([^']*)'"){ throw "nao achei o `$GameTitle no CONFIG" }
$tituloConfig = $Matches[1]
if($tituloConfig){ Chk "regex do titulo ancorado no [GAME]" ($tituloConfig -match '\\\[GAME\\\]') 'True' }

# --- 2. o @( ) externo do $todas -------------------------------------------------------------------
# ESTE e o bug do dia 12/09, e ele e invisivel numa leitura casual do codigo. Sem o @( ) EXTERNO o valor sai do
# bloco `if` pela pipeline, que DESENROLA o array: com exatamente UMA janela casando, $todas vira um
# PSCustomObject solto - e $obj.Count num PSCustomObject devolve $null, nao 1. O `if(-not $todas.Count)` entao
# dispara "nao achei janela" com o jogo aberto. So acontecia com 1 cliente (2+ mantinham o array) e so na web
# (Get-Process devolve Process, que tem Count=1 de verdade), ou seja: exatamente o caso normal de uso.
Chk "todas e array de verdade"     ($src -match '(?s)\$todas = @\(if\(\$GameTitle\)') 'True'
# E a razao pela qual isso importa, medida aqui e agora - se o PowerShell um dia passar a dar Count=1 em
# PSCustomObject, este teste avisa que o @( ) virou opcional (nao que deva sair).
$umObjeto = [pscustomobject]@{ H = 1; T = 'x' }
Chk "PSCustomObject.Count e null"  ($null -eq $umObjeto.Count) 'True'
# E a prova de que o wrapper resolve: mesma forma do codigo, um resultado so.
$comWrapper = @(if($true){ [pscustomobject]@{ H = 1; T = 'x' } })
Chk "com @( ) o Count e 1"         $comWrapper.Count 1
$semWrapper = if($true){ @([pscustomobject]@{ H = 1; T = 'x' }) }
Chk "sem @( ) o Count e null"      ($null -eq $semWrapper.Count) 'True'

# --- 3. aba de fundo: o erro tem que apontar a ABA ---------------------------------------------------
# Aba de fundo nao renderiza, entao nem adiantaria achar a janela - a captura sairia velha. Sem esta mensagem o
# erro vira "o jogo web esta aberto?", que e a pergunta errada: o jogo ESTA aberto, na aba errada.
Chk "erro aponta a aba, nao a janela" ($src -match 'nao esta na aba ATIVA') 'True'

# --- 4. o multibox saiu ------------------------------------------------------------------------------
# Um cliente so, a pedido (12/09). O que ficou do multibox foi o caminho de leitura sem foco.
foreach($morto in '\$Slot','\$GamePid','\$Sfx','Input-Lock','Outras-Janelinhas'){
  Chk "sumiu: $morto" ($src -match $morto) 'False'
}
# Mas Ver-Janela e Janela-Na-Frente FICAM, e agora sem guarda de slot: sao o que impede o bot de roubar sua tela
# pra ler (Z-order com SWP_NOACTIVATE) e o que impede ele de ler a tela de OUTRA janela como se fosse o jogo.
Chk "Ver-Janela sempre ativo"      ($src -match '(?s)function Ver-Janela \{(?!.*\$Slot).*?SetWindowPos') 'True'
Chk "capOk pergunta quem esta nos pixels" ($src -match '\$script:capOk = Janela-Na-Frente') 'True'

if($script:erros){ "`n$script:erros FALHA(S)"; exit 1 }
"OK: janela achada por EnumWindows, `$todas e array com 1 resultado, erro de aba de fundo, multibox removido"
