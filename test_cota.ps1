# Self-check da COTA DIARIA de master resets (nao toca no jogo): .\test_cota.ps1
# Regra pedida: no maximo $MrsPorDia master resets por dia; batendo a cota o bot PARA DE RESETAR e cai no modo
# joias (farma, mixa, repete) ate virar o dia, e volta a resetar sozinho no dia seguinte.
# O que este teste protege: (1) a cota nao pode ser furada reiniciando o bot - por isso ela mora no estado.txt
# com a DATA junto; (2) virar o dia tem que tirar o bot do descanso; (3) virar o dia NAO pode arrancar voce de
# um modo joias que VOCE ligou.
$src = Get-Content "$PSScriptRoot\mudinhox_rpa.ps1" -Raw
$script:erros = 0
function Chk($n,$got,$exp){ if("$got" -ne "$exp"){ "FALHOU $n : '$got' != '$exp'"; $script:erros++ } }

if($src -notmatch '(?m)^\$MrsPorDia\s*=\s*(\d+)'){ throw "nao achei o `$MrsPorDia no CONFIG" }
$CotaConfig = [int]$Matches[1]   # o que esta no CONFIG hoje (pode ser 0 = sem limite)
# O MECANISMO e testado com um valor fixo, nao com o do CONFIG: senao trocar a config quebra o teste da logica.
# O valor configurado e conferido a parte, no fim.
$MrsPorDia = 10
foreach($fn in 'function Hoje','function Cota-Rolar'){
  if($src -notmatch "(?s)($fn \{.*?\r?\n\})"){ throw "nao achei a $fn" }
  . ([scriptblock]::Create($Matches[1]))
}
function Log($m){ $script:ultimoLog = $m }
function Notify($t,$m){}
function Save-Estado { $script:salvou++ }
function Sync-BotoesModo {}
$script:ui = $null

# --- a cota trava e destrava no lugar certo -------------------------------------------------------
# (mesma condicao do Master-Reset; aqui como funcao pra poder rodar sem o jogo)
function Bateu([int]$dia,[bool]$jaDescansando){ $MrsPorDia -gt 0 -and $dia -ge $MrsPorDia -and -not $jaDescansando }
Chk "MR $($MrsPorDia - 1): ainda reseta"      (Bateu ($MrsPorDia - 1) $false) 'False'
Chk "MR $MrsPorDia : bate a cota"             (Bateu $MrsPorDia $false)       'True'
Chk "ja descansando: nao re-dispara"          (Bateu $MrsPorDia $true)        'False'
Chk "acima da cota (override seu): re-arma"   (Bateu ($MrsPorDia + 1) $false) 'True'

# --- virar o dia -----------------------------------------------------------------------------------
function Estado([string]$data,[int]$dia,[bool]$cota,[string]$modo){
  $script:mrsDiaData = $data; $script:mrsDia = $dia; $script:cotaJoias = $cota
  $script:modo = $modo; $script:restartCycle = $false; $script:salvou = 0
  Cota-Rolar
}
Estado (Hoje) 13 $true 'joias'
Chk "mesmo dia: cota continua de pe"          "$($script:mrsDia)/$($script:modo)" "13/joias"
Chk "mesmo dia: nem salva a toa"              $script:salvou 0

Estado '2020-01-01' 13 $true 'joias'
Chk "virou o dia: zera a contagem"            $script:mrsDia 0
Chk "virou o dia: sai do descanso"            $script:modo 'reset'
Chk "virou o dia: refaz o ciclo"              $script:restartCycle 'True'
Chk "virou o dia: grava o estado"             ($script:salvou -ge 1) 'True'
Chk "virou o dia: carimba hoje"               $script:mrsDiaData (Hoje)

# modo joias ligado por VOCE (cotaJoias = false): virar o dia nao pode te tirar dele
Estado '2020-01-01' 4 $false 'joias'
Chk "joias seu sobrevive a virada"            $script:modo 'joias'
Chk "mas a contagem do dia zera"              $script:mrsDia 0

# descanso da cota + voce trocou pra dragoes na mao: a virada nao te joga pra reset
Estado '2020-01-01' 13 $true 'dragoes'
Chk "dragoes seu sobrevive a virada"          $script:modo 'dragoes'

# 1o start da vida (estado sem data): carimba hoje, sem log de virada
Estado '' 0 $false 'reset'
Chk "estado novo: carimba hoje"               $script:mrsDiaData (Hoje)
Chk "estado novo: nao anuncia virada"         ($script:ultimoLog -notmatch 'virou o dia') 'True'

# --- a cota mora no estado.txt (reiniciar nao fura) -------------------------------------------------
foreach($campo in 'mrsDia=','mrsDiaData=','cotaJoias='){
  Chk "Save-Estado grava $campo"              ($src -match [regex]::Escape("`"$campo")) 'True'
}
Chk "o loader confere a DATA antes de aceitar" ($src -match 'kv\.mrsDiaData -eq \(Hoje\)') 'True'

# --- 0 no CONFIG desliga a cota (sem limite), e a mesma condicao do Master-Reset -------------------
$MrsPorDia = 0
Chk "MrsPorDia=0 nunca bate a cota"          (Bateu 999 $false) 'False'
# ...e a virada de dia continua zerando a contagem, pro log ficar honesto
$MrsPorDia = 10
Estado '2020-01-01' 7 $false 'reset'
Chk "sem cota, a virada ainda zera o dia"    $script:mrsDia 0

if($script:erros){ "`n$($script:erros) FALHA(S)"; exit 1 }
"OK: mecanismo da cota (testado com 10), desligamento com 0, virada de dia e persistencia. CONFIG hoje: $(if($CotaConfig -gt 0){ "$CotaConfig MR/dia" } else { 'SEM LIMITE' })"
