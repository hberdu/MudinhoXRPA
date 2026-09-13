# Self-check do estado persistido (nao toca no jogo): .\test_estado.ps1
# Metricas do MR levam horas pra juntar; se o estado.txt nao sobreviver a um restart, a medicao inteira se perde.
$EstadoFile = Join-Path $env:TEMP 'estado_rt_test.txt'
$WarmupResets = 10
$AutoTune = $true
$TargetLevel = 350
$WarpCmd = '/k37'
$WarpMap = ''
$StatMinAprende = $true
$StatMinTeste = 100
$StatMinOutros = 1000
$script:statMinOk = 0
$script:stCarry = @{}
function Log($m){ }

$src = Get-Content "$PSScriptRoot\mudinhox_rpa.ps1" -Raw
if($src -notmatch '(?s)(function Save-Estado.*?)\r?\nfunction Same-Map'){ throw "nao achei Save-Estado..Load-Estado no mudinhox_rpa.ps1" }
. ([scriptblock]::Create($Matches[1]))

$script:erros = 0
function Chk($n,$got,$exp){ if("$got" -ne "$exp"){ "FALHOU $n : '$got' != '$exp'"; $script:erros++ } }

# 1. round-trip completo
$script:phase='warmup'; $script:warmupCount=7; $script:resets=42; $script:ptsSent=91234
$script:mrs=3; $script:runStart=(Get-Date).AddHours(-2.5); $script:mrStart=(Get-Date).AddHours(-1.25)
$script:ciclos=@(88,91,102,301,77); $script:ativoSeg=4200; $script:joiasMix=37; $script:joiasCiclos=9
$rs=$script:runStart.Ticks; $ms=$script:mrStart.Ticks
Save-Estado
$script:phase='normal'; $script:warmupCount=0; $script:resets=0; $script:ptsSent=0; $script:mrs=0
$script:ciclos=@(); $script:ativoSeg=0; $script:joiasMix=0; $script:joiasCiclos=0; $script:runStart=Get-Date; $script:mrStart=Get-Date
Load-Estado
Chk 'fase' $script:phase 'warmup'
Chk 'warmup' $script:warmupCount 7
Chk 'resets' $script:resets 42
Chk 'ptsSent' $script:ptsSent 91234
Chk 'mrs' $script:mrs 3
Chk 'runStart' $script:runStart.Ticks $rs
Chk 'mrStart' $script:mrStart.Ticks $ms
Chk 'ciclos' ($script:ciclos -join ',') '88,91,102,301,77'
Chk 'tempo ativo' $script:ativoSeg 4200
Chk 'joias mixadas' $script:joiasMix 37
Chk 'ciclos de joias' $script:joiasCiclos 9

# 1d. o teste do spot normal pos-MR sobrevive a restart (senao uma queda no meio dele mandaria o char
#     de volta pro warmup, que e justamente o que ele existe pra evitar)
$script:spotTeste = $true; $script:spotTesteIni = (Get-Date).AddSeconds(-200)
$ini = $script:spotTesteIni.Ticks
Save-Estado
$script:spotTeste = $false; $script:spotTesteIni = Get-Date
Load-Estado
Chk 'teste do spot normal sobrevive' $script:spotTeste $true
Chk 'relogio do teste sobrevive' $script:spotTesteIni.Ticks $ini
$script:spotTeste = $false; Save-Estado; $script:spotTeste = $true; Load-Estado
Chk 'teste desligado sobrevive' $script:spotTeste $false

# 1d-bis. REGRESSAO da colisao de nomes: no PowerShell $script:xxx e $Xxx sao a MESMA variavel (case-insensitive).
# A variavel de estado chamava-se warmupTeste e zerava a config $WarmupTeste no start - o teste do spot nunca
# rodava (visto ao vivo no MR #5). Aqui: mexer no estado NAO pode apagar a config.
$WarmupTeste = $true
$script:spotTeste = $false
Chk 'estado do teste nao pisa na config' $WarmupTeste $true
# 1e. com o A/B desligado, o alvo do estado.txt NAO pode sobrescrever a escolha do usuario no CONFIG
$AutoTune = $false; $script:TargetLevel = 380; Save-Estado; $script:TargetLevel = 350; Load-Estado
Chk 'A/B desligado: CONFIG manda no alvo' $script:TargetLevel 350
$AutoTune = $true; $script:TargetLevel = 380; Save-Estado; $script:TargetLevel = 350; Load-Estado
Chk 'A/B ligado: estado.txt manda no alvo' $script:TargetLevel 380
$AutoTune = $true   # os testes seguintes assumem o A/B ligado

# 1c. progresso do A/B sobrevive (sem isto o experimento NUNCA fecha: 15 resets por braco, e cada
#     restart zerava o contador - no log de 11h so o 1o braco chegou ao fim)
$script:tuneOn = $true; $script:tuneArm = 1; $script:tuneResets = 9; $script:tunePts = 45000
$script:tuneAtivo0 = 1234.0; $script:tuneRes = @(,@(350,160794))
Save-Estado
$script:tuneArm = 0; $script:tuneResets = 0; $script:tunePts = 0; $script:tuneAtivo0 = 0.0; $script:tuneRes = @()
Load-Estado
Chk 'braco do A/B' $script:tuneArm 1
Chk 'resets do braco' $script:tuneResets 9
Chk 'pontos do braco' $script:tunePts 45000
Chk 'tempo ativo do braco' $script:tuneAtivo0 1234
Chk 'resultado do braco 1' "$($script:tuneRes[0][0])=$($script:tuneRes[0][1])" '350=160794'
# dois bracos ja medidos
$script:tuneRes = @(@(350,160794),@(380,171000)); Save-Estado; $script:tuneRes = @(); Load-Estado
Chk 'dois resultados' (@($script:tuneRes | % { "$($_[0]):$($_[1])" }) -join '|') '350:160794|380:171000'
# nenhum braco medido ainda: a chave sai vazia e o loader MANTEM o que esta em memoria (mesma regra do 'modo'),
# que no start e @() - o que importa e nao quebrar nem inventar resultado
$script:tuneRes = @(); Save-Estado; $script:tuneRes = @(); Load-Estado
Chk 'sem braco medido nao inventa resultado' $script:tuneRes.Count 0
Chk 'lista vazia continua vazia' $script:tuneRes.Count 0

# 1b. o alvo de level e o estado do auto-tune sobrevivem (o estado.txt agora manda no $TargetLevel:
#     um bug aqui mudaria silenciosamente o alvo do bot)
$script:TargetLevel = 320; $script:tuneOn = $false
Save-Estado
$script:TargetLevel = 350; $script:tuneOn = $true
Load-Estado
Chk 'alvo de level' $script:TargetLevel 320
# o modo decide QUAL ciclo o bot roda (reset/master reset vs farmar-e-mixar): errar aqui muda tudo
$script:modo = 'joias'; Save-Estado; $script:modo = 'reset'; Load-Estado
Chk 'modo joias sobrevive' $script:modo 'joias'
$script:modo = 'reset'; Save-Estado; $script:modo = 'joias'; Load-Estado
Chk 'modo reset sobrevive' $script:modo 'reset'
$script:modo = 'dragoes'; Save-Estado; $script:modo = 'reset'; Load-Estado
Chk 'modo dragoes sobrevive' $script:modo 'dragoes'
'fase=normal' | Set-Content $EstadoFile -Encoding ASCII   # arquivo sem 'modo' nao pode virar lixo
$script:modo = 'joias'; Load-Estado
Chk 'sem modo no arquivo, mantem o da memoria' $script:modo 'joias'
Chk 'autotune concluido nao refaz' $script:tuneOn $false
# com o A/B ainda rodando, o alvo e salvo mas o tune continua ligado
$script:tuneOn = $true; Save-Estado; $script:tuneOn = $false; Load-Estado
Chk 'autotune em andamento continua' $script:tuneOn $false   # so DESLIGA quando o arquivo diz 0; nunca religa sozinho

# 2. formato antigo ("fase warmup") tem que continuar sendo lido
'normal 4' | Set-Content $EstadoFile -Encoding ASCII
$script:phase='warmup'; $script:warmupCount=0
Load-Estado
Chk 'formato antigo: fase' $script:phase 'normal'
Chk 'formato antigo: warmup' $script:warmupCount 4

# 3. arquivo corrompido nao pode derrubar o bot nem zerar o que ja estava em memoria
'lixo{{{ sem igual' | Set-Content $EstadoFile -Encoding ASCII
$script:resets = 99
Load-Estado
Chk 'corrompido nao zera resets' $script:resets 99

# 4. mapa do spot aprendido. O bot descobre no primeiro teleporte que nome o minimapa mostra pro $WarpCmd
#    (nao da pra saber de fora), grava, e retoma no restart. Mas so quando ele mesmo aprendeu.
$script:phase='normal'; $script:warmupCount=0
$script:WarpMap = 'kant'; Save-Estado                        # aprendeu 'kant' rodando /k37
$script:WarpMap = ''; Load-Estado
Chk 'mapa aprendido volta no restart'   $script:WarpMap 'kant'

$script:WarpMap = 'kant'; Save-Estado
$script:WarpMap = 'stad'; Load-Estado                        # nome fixo no CONFIG: e ele que manda
Chk 'CONFIG preenchido ignora o aprendido' $script:WarpMap 'stad'

$script:WarpMap = 'kant'; Save-Estado
$script:WarpCmd = '/s18'; $script:WarpMap = ''; Load-Estado  # trocou de spot: o nome antigo nao serve mais
Chk 'trocar de comando manda reaprender'   $script:WarpMap ''
$script:WarpCmd = '/k37'

# 5. veredito do piso de /f /v /e. E uma pergunta feita ao servidor UMA vez na vida: se nao sobreviver ao
#    restart, todo start gasta um /f e uma leitura de status pra reaprender o que ja se sabia.
$script:statMinOk = 1; $script:StatMinOutros = $StatMinTeste; Save-Estado
$script:statMinOk = 0; $script:StatMinOutros = 1000; Load-Estado
Chk 'veredito "aceita" volta no restart' $script:statMinOk 1
Chk 'e o piso ja vem baixado'            $script:StatMinOutros $StatMinTeste

$script:statMinOk = -1; Save-Estado
$script:statMinOk = 0; $script:StatMinOutros = 1000; Load-Estado
Chk 'veredito "recusa" tambem persiste' $script:statMinOk -1
Chk 'e o piso continua alto'            $script:StatMinOutros 1000   # senao ele reperguntaria a cada start

$script:statMinOk = 1; $script:StatMinOutros = $StatMinTeste; Save-Estado
$StatMinAprende = $false; $script:statMinOk = 0; $script:StatMinOutros = 1000; Load-Estado
Chk 'AutoAprender off ignora o aprendido' $script:StatMinOutros 1000
$StatMinAprende = $true

# 6. memoria dos atributos. Neste cliente o OCR nao enxerga a linha da Vitalidade; o unico valor que o bot
#    tem dela e o que ele guardou. Se isso nao sobreviver ao restart, a distribuicao inteira volta a travar.
$script:stCarry = @{ For = 15000; Agi = 13780; Vit = 11112; Ene = 15048 }
Save-Estado
$script:stCarry = @{}
Load-Estado
Chk 'memoria do atributo volta'   $script:stCarry['Vit'] 11112
Chk 'e os outros tambem'          "$($script:stCarry['For'])/$($script:stCarry['Agi'])/$($script:stCarry['Ene'])" '15000/13780/15048'

# atributo sem valor guardado nao pode virar 0 (0 no Plan-Stats mandaria o char pro cap errado)
$script:stCarry = @{ Vit = 11112 }
Save-Estado
$script:stCarry = @{}
Load-Estado
Chk 'so grava o que conhece'      $script:stCarry.Count 1
Chk 'e nao inventa For'           ($null -eq $script:stCarry['For']) $true

Remove-Item $EstadoFile -ErrorAction SilentlyContinue
if($script:erros -eq 0){ "OK: estado sobrevive ao round-trip, ao formato antigo e a arquivo corrompido" }
else { "$($script:erros) FALHA(S)"; exit 1 }
