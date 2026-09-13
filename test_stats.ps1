# Self-check da distribuicao em etapas (nao toca no jogo): .\test_stats.ps1
$StatCmds  = @( @{Cmd='/f';Key='For'}, @{Cmd='/a';Key='Agi'}, @{Cmd='/v';Key='Vit'}, @{Cmd='/e';Key='Ene'} )
$StatOrder = 'Ene','Agi','For','Vit'
$StatStep = 5000
$StatMinCmd = 1000
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
# 4. /a nunca recebe menos de 1000; /f /v /e podem, mas so pra FECHAR o cap
$r3 = Run (St 32767 32000 32767 32767) 500
if($r3.Cmds.Count -ne 0){ throw "/a com 500 (<1000) nao pode ser enviado: $($r3.Cmds -join '|')" }
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
if((Points-Needed (St 0 0 0 0)) -ne 131068){ throw "Points-Needed do zero errado" }
if((Stat-Stage (St 5000 5000 5000 4999)) -ne 5000){ throw "etapa deveria continuar em 5000 ate todos chegarem" }
if((Stat-Stage (St 5000 5000 5000 5000)) -ne 10000){ throw "etapa deveria virar 10000" }
"OK: $($r.Cmds.Count) comandos, $($StatStages.Count) etapas de $StatStep, cap 32767 fechado em todos"
