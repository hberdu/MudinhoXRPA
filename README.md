# RPA do MudinhoX

Loop automático: `/k37` -> play (MU Helper) -> espera level 350 -> `/resetar` -> repete.

- Piso por comando: **1000** no geral e **500 na reta final** (`$StatMinPerto`, quando os 4 atributos passam de `$StatPertoDoMax` = 30000). O `/a` nunca vai abaixo de **100** (`$StatMinAgi`) — abaixo disso ele teleporta o char pra AIDA. `/f`, `/v`, `/e` podem mandar qualquer valor quando é pra **fechar exatamente** o 32767.
- **O piso de `/f` `/v` `/e` agora é perguntado ao servidor, não chutado** (`$StatMinAprende`). Era o maior desperdício medido do projeto: **2109 das 3551** leituras de status de uma sessão não renderam *um* comando — os pontos chegam em blocos de ~600–900 e o piso de 1000 recusava todos. Cada leitura dessas abre a janela `C`, rouba o foco e gasta ~3s. E o piso nunca tinha sido testado: só o `/a` tem perigo real (AIDA). Na primeira vez que sobrarem pelo menos `$StatMinTeste` (100) pontos sem plano, o bot manda um `/f` com eles, relê o status e vê se a Força subiu o valor exato — aceitou, o piso cai pra 100; recusou, fica em 1000. O veredito vai pro `estado.txt` (`statMinOk=`) e a pergunta **nunca se repete**. Não testa com menos de 100 de propósito: mandar `/f 16` e concluir "o servidor recusa" seria mentira. `$StatMinAprende = $false` desliga e volta pro piso fixo; o `-TestStatMin` continua servindo pra conferir na mão.
- **Nunca deixa um vão pequeno demais pra fechar depois.** Era o travamento: agilidade em 32729, faltando 38, e nenhum `/a` legal fecha 38 — com os outros 3 já no cap, 33 mil pontos ficavam parados e o `/darmr` não saía. Agora o plano ou fecha o cap de uma vez, ou manda menos e deixa uma sobra que o próximo comando consegue mandar.
- **Painel de status congelado é detectado em ~2 leituras** (`$StatCongeladoN`). Os 4 atributos *e* os pontos idênticos à leitura anterior, mas o **level andou** no meio: se o char está upando, ponto tem que entrar — leitura igual quer dizer frame velho na tela (o `C` não reabriu, ou o OCR pegou o painel que ficou aberto). Em 01/09 foram 12 min lendo `752 pontos` parados e o único que pegou foi o `$SemProgressoMin`, 12 minutos depois. Agora ele roda o `Unstick-Tudo` (ESC + fecha chat) na hora e etiqueta o ciclo com `congelado`.
- **Pausa sua não entra na duração do ciclo.** Os 3 piores ciclos da sessão medida (1058s, 996s, 977s = 8% do tempo) eram você pausado no NPC: entravam sem etiqueta na mediana e a métrica culpava um `?` que não existia. O tempo pausado já ficava fora de `pontos/h`; agora fica fora do ciclo também.
- **Perto do máximo lê o status a cada 5s** (`$StatEveryNearSec`) e ignora o "só relê se o level mudou" — no cap o level pode nem subir mais, e são os últimos pontos que liberam o `/darmr`.
- Stats de **5k em 5k** (`$StatStep`): 5000, 10000, ... 30000 e por fim **32767** (o cap que o `/darmr` exige — abaixo disso o jogo recusa). Dentro de cada etapa enche **um atributo por vez, nesta ordem: energia, agilidade, força, vitalidade**. Se faltar menos de 1000 pra fechar a etapa num atributo, passa um pouco da meta em vez de travar (senão a etapa inteira empaca e os pontos empilham).
- A cada 15s (e logo após cada reset) abre a janela de status (C), lê os 4 atributos + os **pontos disponíveis** e manda os valores exatos. Uma leitura de status rende o plano inteiro (até 28 comandos), não uma etapa por leitura.
- Nunca deixa mais de **10k de pontos sobrando** (`$StatMaxLeftover`): distribui **antes de cada `/resetar`** e, se ainda sobrar mais que isso, segura o reset e tenta de novo (até 3x) em vez de gerar mais 2000 pontos. Se não conseguir gastar nada, avisa.
- **Modo Jóias** (botão **MODO JOIAS**): interrompe o ciclo de reset/master reset e roda um ciclo próprio — farma em `/k37` até encher o inventário, vai no `/mixer`, mixa tudo que estiver verde (salvando um print antes de cada clique, pra você validar) e volta a farmar. Sem `/resetar` e sem `/darmr`. Aperte de novo (ou "Normal /k37") pra voltar ao ciclo normal. A cada volta loga **jóias/h** (`== JOIAS: 12 mixadas em 3 ciclos | 4,1 joias/h ==`) — é o número que diz se o `$JoiasFarmMax` está bom; as métricas de `pontos/h` e ETA do MR não valem nada aqui, que não reseta. Se o inventário cheio não for detectado, vai mixar mesmo assim após `$JoiasFarmMax` (25 min).
- **Quando o bot decide mixar**: pela **mensagem do próprio jogo** ("inventário cheio") ou pelo botão **MIXAR JOIAS** — e, no modo jóias, pelo teto de tempo. A contagem periódica de células foi removida: abria e fechava o inventário a cada 2 min pra produzir um número que oscila com o alinhamento da grade (o *mesmo* inventário cheio leu 0 e 26 livres com 20px de diferença na âncora). `Inv-Free` continua no `-Preflight`/`-TestInv`, onde o número é só informativo.
- **Mix de jóias** (mecânica): vai no `/mixer`, passa o mouse no **Lahap** (o nome só aparece no hover — o bot confirma o nome por OCR antes de clicar), abre **Mixar Jóias** e clica em cada tipo que estiver **verde** (Soul, Life, Creation, Chaos), 5s entre cada um, até sobrar só vermelho — depois volta pro spot onde estava. Botão **MIXAR JOIAS** força na hora.
- **Modo Dragões** (botão **MODO DRAGOES**): ciclo próprio, igual ao de jóias — vai pro `/lorencia` e **só caça**. Não checa inventário, não checa atributos, não reseta e não dá `/darmr`. Varre a tela atrás dos **Golden Dragon** e clica em cima pra atacar; sem nada dourado, anda e procura de novo. Roda até você desligar. Se os guardas detectarem que está batendo em cenário, sai do modo sozinho e avisa. Lorencia é cidade, então o MU Helper fica desligado (`$GoldHelper`): clicar no play lá abre "precisa estar fora da cidade". ⚠️ **`$GoldPix` ainda não foi calibrado** — rode `-TestGold` com um Golden Dragon na tela; até lá o bot detecta cenário, avisa e volta.
- **`/darmr` por validação**: só quando os 4 atributos = **32767** manda `/darmr`, vai à tela de login e re-entra. Depois o personagem volta em Lorencia: entra em **modo warmup** — usa `/losttower7` e farma lá até **3 resets** (`$WarmupResets`, distribuindo os pontos), depois volta ao `/k37` normal. Eram 10: medido, cada reset em Lost Tower custa ~220s contra 70-110s no Stadium pelos mesmos ~6200 pontos, então os 10 eram 73-78% do tempo do MR inteiro.
- **Alvo de reset: 350** (`$TargetLevel`), fixado por decisão sua. O A/B automático está **desligado** (`$AutoTune = $false`) e, com ele desligado, o `alvo` gravado no `estado.txt` é ignorado — quem manda é o CONFIG, senão um alvo antigo do experimento sobrescreveria sua escolha pra sempre.
- **Teste do spot pós-`/darmr`** (`$WarmupTeste`, hoje **desligado**): se ligado, o bot vai pro spot normal depois do MR e dá `$WarmupTesteSec` (300s) pra fechar um reset lá; fechou, pula o warmup inteiro; estourou, cai pro Lost Tower. Está off porque você prefere os 3 resets garantidos de warmup.
- **Spot: `/k37` → Kanturu** (`$WarpMap = 'kant'`, confirmado no log das 12:01). Se `$WarpMap` estiver **vazio**, o bot **aprende**: adota o mapa onde estiver depois de mandar o warp, desde que não seja cidade, e grava no `estado.txt` junto com o comando (`warpCmd=`/`warpMap=`). Trocar o `$WarpCmd` invalida o nome antigo e ele reaprende. CONFIG preenchido sempre manda.
  A regra de aprendizado é só *"mandei o warp e estou num mapa que não é cidade"* — exigir que o mapa **mudasse** estava errado e travou de verdade: o personagem já estava em Kanturu, o mapa não mudou, nada foi aprendido, e o bot queimou os 4 warps em sequência (`nao teleportou pro spot certo (mapa: 'kanturu', esperado '', antes 'kanturu')`). Já estar no destino é o caso de sucesso mais comum, não uma falha.
- Confirma o resultado das ações: após `/k37` lê o nome do mapa (minimapa) e só segue quando está no spot de farm (confirma por mudança de mapa) (reenvia até 4x, senão avisa). Liga o play e confirma o helper rodando; não fica clicando à toa (máx 3). Se o level fica parado fora do spot, re-teleporta; parado no spot, religa o helper (miss infinito).
- **Miss infinito: `$StallReads` (3) leituras seguidas com o level idêntico *e* pelo menos `$StallMinSec` (15) segundos** -> ESC + pausa + anda + despausa (desbuga). Era 40s cravado (antes 75). A métrica do próprio bot aponta `stall` como **23-27% de todo o tempo**, e a maior parte disso é latência de *detecção*, não de recuperação: 113 disparos × 40s ≈ 75 min de uma sessão só esperando pra perceber. As duas condições juntas cortam isso pela metade sem falso positivo — as leituras iguais são o sinal forte (e uma leitura que o OCR **não** conseguiu não entra na conta; antes ela empurrava o relógio como se o level estivesse parado), e os segundos são o piso pro char fraco logo depois do reset. Botão PAUSE/RETOMAR na janela pra mixar joias no NPC.
- **`Check-Progress` devolvia dois valores** e por isso o ciclo nunca reiniciava depois de re-teleportar: `Start-Helper` retorna `$true`/`$false`, e sem descartar isso a função saía com `@($true,$false)`. Um array de 2 itens é sempre verdadeiro em PowerShell, então o `if(-not (Check-Progress ...))` do chamador nunca entrava e o `return $false` era engolido. Achado pelo self-check novo do `test_ciclos.ps1`, não em produção.
- De vez em quando (2–7 min, aleatório) faz algo "humano": anda um pouco e volta, abre/fecha status ou chat, mexe o mouse. Os intervalos de tudo variam ±25% (`$JitterPct`) — só o **ritmo**, nunca os valores dos stats.
- Captcha de imagem: resolve sozinho (seleciona, confere a borda vermelha, confirma). Se não tiver certeza, avisa (toast + beep) e espera você. **Errou 2 vezes -> PAUSA e espera você** (`$CapKillGame = $true` volta a regra antiga de fechar o jogo).
- Se cair pra tela de login/servidor no meio do farm, ele detecta e volta sozinho. **Nunca clica em coordenada chutada** numa tela que tenha "CRIAR NOVA CONTA" ou "Sair" — avisa e espera.
- Se o jogo fechar, o bot não morre junto: espera o cliente voltar, re-entra e retoma.

## Uso

Duplo clique em **`MudinhoX RPA.cmd`** com o jogo aberto. Pede permissão de administrador (o jogo roda como admin; sem isso o Windows ignora o teclado/mouse do bot). Abre uma janelinha com log e botão **PARAR** (ou feche a janela). Também para se criar um arquivo `stop.flag` na pasta.

A janelinha mostra uma **barra de progresso até o próximo `/darmr`** e, embaixo dela, os contadores **da sessão**:

```
sessao: 47 resets | 2 MR    -    /darmr: 62,0%  (49806 pontos faltando)
```

A barra mede **pontos**, não resets: quantos resets cabem num master reset muda com o alvo, com o spot e com a fase, então contar reset daria uma barra que anda torto. O denominador é `4 × 32767 = 131068` — os quatro atributos do zero ao cap. Os contadores são **deste processo**: o `$script:resets` interno zera a cada `/darmr` (ele mede o MR atual) e o `mrs` do `estado.txt` é acumulado da vida inteira do personagem, então nenhum dos dois responde "quanto rendeu hoje". Reiniciar o bot zera a contagem da sessão — é uma sessão nova mesmo.

Log completo em `rpa.log`. Prints de captcha e da última janela de status em `captcha\`.
- **Fechou, acabou. Nada fica rodando.** O watchdog foi **removido** — era uma Tarefa Agendada que rodava de 3 em 3 minutos e relançava o bot, inclusive o que você tinha mandado parar: na madrugada de 01-02/09 ele reabriu o PowerShell sozinho a cada 3 min. Foram embora o `watchdog.ps1`, o `instalar-watchdog.cmd` e o `$AutoWatchdog`. Se a Tarefa Agendada antiga ainda existir na máquina, **o bot a apaga sozinho no próximo start** (ele já roda elevado); pra tirar na mão, num PowerShell **como administrador**:

  ```powershell
  schtasks /delete /tn "MudinhoX RPA Watchdog" /f
  ```

- **Parar diz por que parou.** O log dizia `parado pelo usuario` até quando tinha sido um crash — de madrugada não dava pra saber o que aconteceu. Agora: `parado (usuario)`, `parado (janela fechada)`, `parado (stop.flag)`, `parado (erro: ...)`, `parado (sem progresso)`. Ao sair ele consome o `stop.flag` e o `heartbeat.txt`: nada sobra pra atrapalhar a próxima abertura.
- **O único caminho que ainda cria processo sozinho** é o auto-restart depois de `$SemProgressoMax` (3) ciclos seguidos sem ganhar um ponto — e só com o bot **rodando**, porque fechar a janela já marca a parada antes disso. Pra desligar até isso: `$AutoRestart = $false` no CONFIG (aí ele só para e avisa).
- **O print do status só é salvo quando a leitura falha.** Antes ia pro disco em *toda* leitura: ~3500 por sessão, 3,8 MB cada, numa pasta dentro do OneDrive — uns 13 GB de re-upload por noite pra reescrever sempre o mesmo `status_ultimo.png`. Agora ele aparece exatamente quando há o que olhar (e é o arquivo que o `-TestStatus` usa).
- **O clique cego da tela de login segue a altura da janela.** `$LoginBtn` era `Y = 940` cravado, calibrado numa área cliente de 1009 — numa janela de outra altura o clique escorregava, e logo ali embaixo mora o "CRIAR NOVA CONTA". Virou `YFromBottom = 69`, o mesmo padrão que o `$LevelBox`, o `$ChatBox` e o `$MsgBox` já usavam. (Sobre a resolução: **não** era caso de recalibrar. O `1920x1061` do log foi um estado passageiro da janela entre 00:22 e 02:10; nas 27 outras verificações, e na mais recente, ela está em `1920x1009`. O preflight estava certo em reclamar.)
- **Miss infinito não dispara no teto de level.** No `$LevelMaximo` (400) o level não sobe mais, então o detector de level parado disparava a cada 40s pra sempre — ESC + pausa + anda + religa helper, com o char farmando normal. Foram **16 das 113** ocorrências do log. O modo jóias já tinha essa guarda; o ciclo normal não (o char chega no teto quando o `/resetar` demora a pegar).

Modos de teste (não clicam em nada):

```powershell
powershell -ExecutionPolicy Bypass -File .\mudinhox_rpa.ps1 -Check                        # lê level, botão play, captcha, chat aberto
powershell -ExecutionPolicy Bypass -File .\mudinhox_rpa.ps1 -TestImage .\captcha\exemplo.png  # testa o solver num print
powershell -ExecutionPolicy Bypass -File .\mudinhox_rpa.ps1 -TestInv                     # inventário ABERTO no jogo: salva print e mostra as células ocupadas
powershell -ExecutionPolicy Bypass -File .\mudinhox_rpa.ps1 -TestMix                     # modal de mix ABERTO: mostra o que o OCR lê e a cor de cada opção
powershell -ExecutionPolicy Bypass -File .\mudinhox_rpa.ps1 -TestStatus .\captcha\status_ultimo.png  # mostra o que o OCR leu no painel de status e o que virou For/Agi/Vit/Ene/Pontos
powershell -ExecutionPolicy Bypass -File .\mudinhox_rpa.ps1 -TestNpc                      # no /mixer, mouse em cima do Lahap: mostra a coordenada dele
powershell -ExecutionPolicy Bypass -File .\mudinhox_rpa.ps1 -TestGold                     # com um Golden Tantalos na tela: marca em verde o que o detector achou
powershell -ExecutionPolicy Bypass -File .\mudinhox_rpa.ps1 -TestVisao                    # regressão das funções de leitura de tela (usa os prints de fixtures\)
powershell -ExecutionPolicy Bypass -File .\test_stats.ps1                                # self-check da distribuição em etapas (não toca no jogo)
powershell -ExecutionPolicy Bypass -File .\test_estado.ps1                               # self-check do estado persistido (métricas sobrevivem a restart)
powershell -ExecutionPolicy Bypass -File .\test_lint.ps1                                 # caca comando inexistente na AST (o `X` solto que matou o bot 2x)
powershell -ExecutionPolicy Bypass -File .\test_ciclos.ps1                               # self-check da metrica de ciclos (mediana, atribuicao de culpa, recuo do Tick-Stats)
powershell -ExecutionPolicy Bypass -File .\test_parada.ps1                               # self-check da parada (stop.flag sobrevive) e do detector de painel congelado
```

**Antes de deixar rodando sozinho a noite toda** — com o personagem **no spot** e num PowerShell **como administrador** (sem admin o Windows descarta as teclas `C`/`V` e o teste falha por isso):

```powershell
powershell -ExecutionPolicy Bypass -File .\mudinhox_rpa.ps1 -Preflight
```

Valida numa tacada: privilégios, resolução, captura, level, botão play, mapa, spot correto, captcha, os 4 atributos, inventário e a faixa de mensagens. Sai com código 1 se algo falhar.

## Ainda por calibrar

- **Lista de jóias verde/vermelho**: falta o print da tela que abre *depois* de clicar em "Mixar Jóias". Rode `-TestMix` com ela aberta.
- **Golden Tantalos** (`$GoldPix`): o filtro de cor é um chute. Rode `-TestGold` com o mob na tela — salva `captcha\gold.png` com um quadrado verde no que ele achou.

O mix acha o resto por OCR. Se algum texto não bater com `$MixMenuWords` / `$MixJewels`, rode `-TestMix` e corrija os padrões. O bot **não clica no escuro**: se não achar, avisa e volta pro farm.

## Ajustes (bloco CONFIG no .ps1)

- Coordenadas relativas à área cliente do jogo em 1920x1009.
- `$StatStep` (5000) e `$StatMaxLeftover` (10000): tamanho da etapa e teto de pontos parados.
- A grade do inventário é localizada **dinamicamente** pelo título da janela (`$InvTituloWords` + `$InvGridDx/Dy`): o painel não tem posição fixa — abriu em (1317,408) e depois em (607,333). `$MixNpcPos` (posição do Lahap) continua fixo; refaça com `-TestNpc` se mudar de resolução.
- `$KeyHoldMs` / `$KeyGapMs` (40/40): velocidade da digitação. **Não baixe** — abaixo disso o comando embaralha e o `/k37` sai inválido.
- `$LoginServerWords` (`Server Vip Gold`): qual botão clicar na tela de escolha de servidor. `$LoginDangerWords` lista o que **nunca** pode ser clicado por coordenada chutada (`CRIAR NOVA CONTA`, `Sair`) — o fallback `$LoginBtn` (960,940) cai justo em cima do "criar conta", então numa tela dessas o bot avisa em vez de clicar.
- `$MetricsEvery` (5): a cada N resets loga `pontos/h`, ETA do MR e a **mediana** do ciclo + quanto do tempo vazou nos ciclos lentos.
- `$MsgBox`: faixa de mensagens do jogo que o bot lê (respostas do servidor, aviso de inventário cheio, evento dos dragões).
- `$ClientEsperado` (1920x1009): resolução da calibração. Se a janela do jogo mudar de tamanho, o bot avisa no start.
- `$SemProgressoMin` (12): sem distribuir um ponto sequer por N min, o bot assume que travou, avisa e reinicia o ciclo.
- O jogo precisa estar visível na leitura. Se outra janela estiver na frente, o bot traz o jogo por ~1s, lê e devolve o foco (aí lê a cada 60s em vez de 10s). Se o Windows negar o foco, ele pula em vez de digitar no lugar errado.

## Medindo o master reset

O objetivo é o `/darmr`, não o reset — reset é só o meio de juntar pontos. A cada 5 resets o bot loga:

```
== MR: faltam 57969 pontos | 24000 pontos/h | ETA ~2.4h | 38 resets/h a 630 pts/reset (alvo lvl 350) | MRs nesta sessao: 1 ==
```

O número que importa é **pontos/h**, não resets/h: resetar mais cedo dá mais resets, mas pode dar menos pontos por reset. Pra achar o `$TargetLevel` ótimo, rode ~30min em 350, ~30min noutro valor e compare **pontos/h** entre os dois. Os contadores zeram a cada `/darmr`, então cada MR é medido limpo. O resumo também aparece no título da janelinha.
