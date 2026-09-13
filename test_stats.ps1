# Self-check da distribuicao em etapas (nao toca no jogo): .\test_stats.ps1
$StatCmds  = @( @{Cmd='/f';Key='For'}, @{Cmd='/a';Key='Agi'}, @{Cmd='/v';Key='Vit'}, @{Cmd='/e';Key='Ene'} )
$StatOrder = 'Ene','Agi','For','Vit'
$StatStep = 5000
$StatMinCmd = 1000
$StatMinOutros = 1000
$StatPertoDoMax = 30000
$StatMinPerto = 500
$StatMinAgi = 100
$StatMaxValue = 32767
$StatStages = @(1..([Math]::Floor(($StatMaxValue - 1) / $StatStep)) | % { $_ * $StatStep }) + $StatMaxValue
# pega as 3 funcoes puras direto do .ps1 (sem carregar o bot inteiro)
$src = Get-Content "$PSScriptRoot\mudinhox_rpa.ps1" -Raw
if($src -notmatch '(?s)(function Points-Needed.*?)\r?\nfunction Distribute-Points'){ throw "nao achei o bloco Points-Needed..Plan-Stats no mudinhox_rpa.ps1" }
. ([scriptblock]::Create($Matches[1]))

function St($f,$a,$v,$e){ @{ For=$f; Agi=$a; Vit=$v; Ene=$e } }
function Run($st,$p){   # simula rodadas ate os pontos acabarem; devolve os comandos e o estado final
  $cmds = @()
  for($i=0; $i -lt 60; $i++){
    $plano = Plan-Stats $st $p
    if($plano.Count -eq 0){ break }
    foreach($c in $plano){ $n = $c -split ' '; $k = ($StatCmds | ? { $_.Cmd -eq $n[0] }).Key; $st[$k] += [int]$n[1]; $p -= [int]$n[1]; $cmds += $c }
  }
  @{ Cmds = $cmds; St = $st; Pts = $p }
}

if(($StatStages -join ',') -ne '5000,10000,15000,20000,25000,30000,32767'){ throw "etapas erradas: $($StatStages -join ',')" }
# 1. do zero com pontos de sobra: 5k em cada, na ordem energia/agilidade/forca/vitalidade
$r = Run (St 0 0 0 0) 200000
if(($r.Cmds | select -First 4) -join '|' -ne '/e 5000|/a 5000|/f 5000|/v 5000'){ throw "etapa 1 fora de ordem: $($r.Cmds[0..3] -join '|')" }
# 2. termina exatamente no cap nos 4, sem passar
if(($r.Cmds | select -Last 4) -join '|' -ne '/e 2767|/a 2767|/f 2767|/v 2767'){ throw "etapa final errada: $($r.Cmds[-4..-1] -join '|')" }
foreach($k in $StatOrder){ if($r.St[$k] -ne 32767){ throw "$k terminou em $($r.St[$k]), esperado 32767" } }
if($r.Cmds.Count -ne 28){ throw "esperava 28 comandos (7 etapas x 4 atributos), veio $($r.Cmds.Count)" }
# 2b. as 7 etapas saem de UMA leitura de status so
$umPlano = Plan-Stats (St 0 0 0 0) 200000
if(($umPlano -join '|') -ne ($r.Cmds -join '|')){ throw "plano unico difere do incremental" }
# 3. poucos pontos: enche energia primeiro, nao espalha
$r2 = Run (St 0 0 0 0) 4000
if($r2.Cmds -join '|' -ne '/e 4000'){ throw "com 4000 pontos deveria mandar so /e 4000, veio: $($r2.Cmds -join '|')" }
# 4. piso do /a: 1000 no geral, 500 na reta final (os 4 acima de $StatPertoDoMax), NUNCA abaixo de 100 (AIDA)
$r3 = Run (St 20000 19600 20000 20000) 500      # longe do maximo: piso do /a segue 1000
if($r3.Cmds.Count -ne 0){ throw "/a com 500 fora da reta final nao pode sair: $($r3.Cmds -join '|')" }
$r3b = Plan-Stats (St 32767 31000 32767 32767) 600   # reta final: 600 fecharia deixando 767 - cabe num /a depois
if(($r3b -join '|') -ne '/a 600'){ throw "na reta final o /a deveria aceitar 600: $($r3b -join '|')" }
# 4b. REGRESSAO do travamento de 14:54: A=32729, faltando 38. Nenhum /a legal fecha 38 (piso 100 por causa da
#     AIDA), e os outros 3 ja estao no cap. A saida e NAO CRIAR o vao: o plano nunca pode deixar a agilidade
#     a menos de $StatMinPerto do cap sem fechar.
$r3c = Plan-Stats (St 32767 32000 32767 32767) 500    # 500 deixaria 267 de vao: impossivel de fechar depois
if($r3c.Count -ne 0){ throw "nao pode criar vao de 267 no /a: $($r3c -join '|')" }
$r3d = Plan-Stats (St 32767 32000 32767 32767) 767    # com 767 da pra FECHAR: tem que fechar
if(($r3d -join '|') -ne '/a 767'){ throw "com 767 o /a deveria fechar o cap: $($r3d -join '|')" }
# 4c. simulacao longa a partir do estado real do log: nunca pode parar com a agilidade encalhada
$r3e = Run (St 30000 30000 30000 30000) 11068
foreach($k in $StatOrder){
  $falta = 32767 - $r3e.St[$k]
  if($falta -gt 0 -and $falta -lt $StatMinAgi){ throw "$k parou a $falta do cap - vao impossivel de fechar" }
}
$r4 = Run (St 32000 32767 32767 32767) 767
if($r4.Cmds -join '|' -ne '/f 767'){ throw "/f fechando o cap com 767 deveria sair: $($r4.Cmds -join '|')" }
# 5. REGRESSAO: faltando <1000 pra fechar a etapa nao pode TRAVAR a distribuicao inteira
$r5 = Run (St 5000 5000 5000 4500) 50000   # Vit precisa de 500 pra fechar a etapa 5000
if($r5.Cmds.Count -eq 0){ throw "travou: faltando 500 no Vit nao distribuiu nada" }
if($r5.Pts -gt 10000){ throw "sobraram $($r5.Pts) pontos (>10k) com 50000 disponiveis - etapa travou" }
foreach($k in $StatOrder){ if($r5.St[$k] -gt 32767){ throw "$k passou do cap: $($r5.St[$k])" } }
# 6. nunca sobra mais de 10k enquanto houver espaco nos atributos
foreach($ini in (St 0 0 0 0), (St 12000 9800 3000 20500), (St 32767 32767 30000 32767)){
  $rr = Run $ini 90000
  $espaco = ($StatOrder | % { 32767 - $rr.St[$_] } | measure -Sum).Sum
  if($rr.Pts -gt 10000 -and $espaco -gt 10000){ throw "sobraram $($rr.Pts) pontos com $espaco de espaco livre" }
}
# 7. Points-Needed / Stat-Stage
# 6b. piso separado: baixando so o de /f /v /e, o /a CONTINUA protegido (valor pequeno nele teleporta pra AIDA)
$StatMinOutros = 1
$r6 = Run (St 32767 32000 32767 32767) 500      # so o Agi falta, e /a nao pode receber 500
if($r6.Cmds.Count -ne 0){ throw "/a recebeu valor pequeno mesmo com o piso proprio: $($r6.Cmds -join '|')" }
$r7 = Run (St 32000 32767 32767 32767) 500      # so a For falta: com piso baixo, pode receber
if($r7.Cmds -join '|' -ne '/f 500'){ throw "com StatMinOutros=1 o /f deveria aceitar 500: $($r7.Cmds -join '|')" }
$StatMinOutros = 1000
$StatPertoDoMax = 30000
$StatMinPerto = 500
$StatMinAgi = 100
# 6b. o piso aprendido e o ponto do exercicio: com 1000, um bloco tipico de pontos do log (~700) nao rende
#     comando nenhum - foram 2109 leituras assim numa sessao. Com o piso baixado ele vira comando.
$StatMinOutros = 1000
if((Plan-Stats (St 5000 5000 5000 5000) 700).Count -ne 0){ throw "com piso 1000, 700 pontos nao deviam render comando" }
$StatMinOutros = 100
$pl = Plan-Stats (St 5000 5000 5000 5000) 700
if($pl.Count -eq 0){ throw "com piso 100, 700 pontos TEM que render comando (e o ganho todo da mudanca)" }
if($pl[0] -notmatch '^/e 700$'){ throw "esperava '/e 700' (energia e a primeira da ordem), veio '$($pl[0])'" }
# o /a nunca entra nessa: o piso dele e $StatMinCmd, por causa do teleporte pra AIDA
if(($pl | Where-Object { $_ -match '^/a (\d+)$' -and [int]$Matches[1] -lt $StatMinCmd })){ throw "/a nao pode ir abaixo de $StatMinCmd" }
$StatMinOutros = 1000

# 6c. RETA FINAL nao pode ter piso MAIOR que o do trecho normal. Estado real de 04/09: F=30000 V=30000 (os 4 ja
#     contam como reta final, o teste e >= 30000), 418 pontos em maos. Com o piso aprendido em 100, pegar o
#     $StatMinPerto (500) direto SUBIA o piso e nenhum comando saia: 418 pontos parados, /darmr travado, 31 min
#     perdidos e auto-restart por "sem progresso".
$StatMinOutros = 100
$pl = Plan-Stats (St 30000 32767 30000 32767) 418
if($pl.Count -eq 0){ throw "reta final com piso aprendido 100: 418 pontos TEM que render comando (travou o /darmr em 04/09)" }
if($pl[0] -notmatch '^/f 418$'){ throw "esperava '/f 418' (Ene e Agi ja no cap, Forca e a proxima da ordem), veio '$($pl[0])'" }
# com o piso NAO aprendido (1000) o menor dos dois ainda e o 500 da reta final: 418 continua recusado, de proposito
$StatMinOutros = 1000
if((Plan-Stats (St 30000 32767 30000 32767) 418).Count -ne 0){ throw "sem piso aprendido, a reta final ainda usa 500 e 418 nao passa" }
# e o /a segue protegido: na reta final o piso dele e 500, nunca os 100 da AIDA
$StatMinOutros = 100
if((Plan-Stats (St 32767 30000 32767 32767) 418).Count -ne 0){ throw "/a nao pode sair com 418 na reta final (piso 500)" }
$StatMinOutros = 1000

# 6d. O bot pula a releitura de status apos distribuir quando a SOBRA SIMULADA (pontos - soma do plano) ja esta
#     abaixo do piso. Isso so e seguro se o plano nunca gastar MAIS do que ha em maos: sobra negativa faria o bot
#     concluir "acabou" e seguir pro /resetar com pontos na mesa. Invariante checada em varios estados.
foreach($piso in 100, 1000){
  $StatMinOutros = $piso
  foreach($caso in @(@(0,0,0,0,200000), @(5000,5000,5000,5000,700), @(30000,32767,30000,32767,418),
                     @(32000,32000,32000,32000,3000), @(32767,32767,32767,30000,2767), @(1500,1500,1500,1500,6200))){
    $st = St $caso[0] $caso[1] $caso[2] $caso[3]; $p = $caso[4]
    $gasto = 0; foreach($c in (Plan-Stats $st $p)){ $gasto += [int](($c -split ' ')[1]) }
    if($gasto -gt $p){ throw "piso ${piso}: plano gastou $gasto com apenas $p pontos (F=$($caso[0]) A=$($caso[1]) V=$($caso[2]) E=$($caso[3]))" }
  }
}
$StatMinOutros = 1000

# 6e. No ALVO o bot reseta direto, sem parar pra distribuir (custava 11.1s por reset, ~3.7 min por master reset).
#     Os pontos nao somem: quem gasta e o Tick-Stats na subida do ciclo seguinte. MAS a guarda de pontos parados
#     tem que continuar - foi sem ela que um char empilhou 1.66 MILHAO de pontos em 08/09, e a pilha cresce sem
#     ninguem ver. Assercao no FONTE porque esse trecho vive no laco principal, fora de qualquer funcao.
$fonte = Get-Content "$PSScriptRoot\mudinhox_rpa.ps1" -Raw
if($fonte -notmatch 'if\(\$script:ptsLeft -gt \$StatMaxLeftover\)\{'){
  throw "a guarda de pontos parados antes do reset sumiu: sem ela a pilha de pontos cresce sem limite"
}
if($fonte -notmatch '(?s)if\(\$script:ptsLeft -gt \$StatMaxLeftover\)\{.*?Distribute-Points'){
  throw "a guarda existe mas nao chama Distribute-Points: ela so serve se GASTAR os pontos"
}
# e o caminho normal (sobra pequena) NAO pode distribuir: e justamente o tempo que estamos cortando
if($fonte -match '(?m)^  for\(\$d = 0; \$d -lt 3 -and -not \$script:restartCycle; \$d\+\+\)\{'){
  throw "o laco de distribuir antes do reset voltou a ser incondicional"
}

# 7. Points-Needed / Stat-Stage
if((Points-Needed (St 0 0 0 0)) -ne 131068){ throw "Points-Needed do zero errado" }
if((Stat-Stage (St 5000 5000 5000 4999)) -ne 5000){ throw "etapa deveria continuar em 5000 ate todos chegarem" }
if((Stat-Stage (St 5000 5000 5000 5000)) -ne 10000){ throw "etapa deveria virar 10000" }
"OK: $($r.Cmds.Count) comandos, $($StatStages.Count) etapas de $StatStep, cap 32767 fechado em todos"
