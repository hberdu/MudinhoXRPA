# RPA do MudinhoX

Loop automático: `/k37` -> play (MU Helper) -> espera level 350 -> `/resetar` -> repete.

- Piso por comando: **1000** no geral e **500 na reta final** (`$StatMinPerto`, quando os 4 atributos passam de `$StatPertoDoMax` = 30000). O `/a` nunca vai abaixo de **100** (`$StatMinAgi`) — abaixo disso ele teleporta o char pra AIDA. `/f`, `/v`, `/e` podem mandar qualquer valor quando é pra **fechar exatamente** o 32767.
- **A reta final nunca tem piso maior que o trecho normal.** O `$StatMinPerto` (500) existe pra *baixar* o piso de 1000 — mas depois que o servidor aceitou abaixo do piso (ver abaixo) o `$StatMinOutros` virou **100**, e pegar o 500 direto **subia** o piso justo onde fechar o cap é tudo que importa. Travou de verdade em 04/09: `F=30000 A=32767 V=30000 E=32767` com **418 pontos** em mãos, 418 < 500, nenhum comando saiu — 31 min parados, `/darmr` sem sair e auto-restart por "sem progresso". Agora o piso da reta final é o **menor** dos dois; sem o piso aprendido, continua 500, como era a intenção. A mensagem de recusa também mostrava o piso errado (`418 pontos; minimo 100`, quando o aplicado tinha sido 500).
- **O piso de `/f` `/v` `/e` agora é perguntado ao servidor, não chutado** (`$StatMinAprende`). Era o maior desperdício medido do projeto: **2109 das 3551** leituras de status de uma sessão não renderam *um* comando — os pontos chegam em blocos de ~600–900 e o piso de 1000 recusava todos. Cada leitura dessas abre a janela `C`, rouba o foco e gasta ~3s. E o piso nunca tinha sido testado: só o `/a` tem perigo real (AIDA). Na primeira vez que sobrarem pelo menos `$StatMinTeste` (100) pontos sem plano, o bot manda um `/f` com eles, relê o status e vê se a Força subiu o valor exato — aceitou, o piso cai pra 100; recusou, fica em 1000. O veredito vai pro `estado.txt` (`statMinOk=`) e a pergunta **nunca se repete**. Não testa com menos de 100 de propósito: mandar `/f 16` e concluir "o servidor recusa" seria mentira. `$StatMinAprende = $false` desliga e volta pro piso fixo; o `-TestStatMin` continua servindo pra conferir na mão.
- **Nunca deixa um vão pequeno demais pra fechar depois.** Era o travamento: agilidade em 32729, faltando 38, e nenhum `/a` legal fecha 38 — com os outros 3 já no cap, 33 mil pontos ficavam parados e o `/darmr` não saía. Agora o plano ou fecha o cap de uma vez, ou manda menos e deixa uma sobra que o próximo comando consegue mandar.
- **Painel de status congelado é detectado em ~2 leituras** (`$StatCongeladoN`). Os 4 atributos *e* os pontos idênticos à leitura anterior, mas o **level andou** no meio: se o char está upando, ponto tem que entrar — leitura igual quer dizer frame velho na tela (o `C` não reabriu, ou o OCR pegou o painel que ficou aberto). Em 01/09 foram 12 min lendo `752 pontos` parados e o único que pegou foi o `$SemProgressoMin`, 12 minutos depois. Agora ele roda o `Unstick-Tudo` (ESC + fecha chat) na hora e etiqueta o ciclo com `congelado`.
- **Pausa sua não entra na duração do ciclo.** Os 3 piores ciclos da sessão medida (1058s, 996s, 977s = 8% do tempo) eram você pausado no NPC: entravam sem etiqueta na mediana e a métrica culpava um `?` que não existia. O tempo pausado já ficava fora de `pontos/h`; agora fica fora do ciclo também.
- **Perto do máximo lê o status a cada 5s** (`$StatEveryNearSec`) e ignora o "só relê se o level mudou" — no cap o level pode nem subir mais, e são os últimos pontos que liberam o `/darmr`.
- Stats de **5k em 5k** (`$StatStep`): 5000, 10000, ... 30000 e por fim **32767** (o cap que o `/darmr` exige — abaixo disso o jogo recusa). Dentro de cada etapa enche **um atributo por vez, nesta ordem: energia, agilidade, força, vitalidade**. Se faltar menos de 1000 pra fechar a etapa num atributo, passa um pouco da meta em vez de travar (senão a etapa inteira empaca e os pontos empilham).
- A cada 15s (e logo após cada reset) abre a janela de status (C), lê os 4 atributos + os **pontos disponíveis** e manda os valores exatos. Uma leitura de status rende o plano inteiro (até 28 comandos), não uma etapa por leitura.
- **Chegou no alvo, reseta. Não para pra distribuir.** Distribuir ali custava **11,1s por reset** (medido em 82 resets, `level alvo → /resetar`) — ~3,7 min por master reset, o segundo maior custo de bot do ciclo. Os pontos não somem: quem gasta é o `Tick-Stats` na **subida** do ciclo seguinte, que é quando o char está upando e as leituras acontecem de qualquer jeito. Distribuir é coisa do level 1 até o alvo; no alvo, resetar.
- Nunca deixa mais de **10k de pontos sobrando** (`$StatMaxLeftover`): se a última leitura já mostrava mais que isso, aí sim gasta antes do `/resetar` (e tenta de novo até 3x) em vez de gerar mais 2000 pontos com o reset. Se não conseguir gastar nada, avisa. **Essa guarda é o que separa isso de um desastre**: foi sem ela que um char empilhou **1,66 milhão** de pontos em 08/09 — a pilha cresce sem ninguém ver. A decisão usa o `$script:ptsLeft` da última leitura do farm, então não custa uma leitura nova.
- **Modo Jóias** (botão **MODO JOIAS**): interrompe o ciclo de reset/master reset e roda um ciclo próprio — farma em `/k37` até encher o inventário, vai no `/mixer`, mixa tudo que estiver verde (salvando um print antes de cada clique, pra você validar) e volta a farmar. Sem `/resetar` e sem `/darmr`. **Pra sair, "Normal /k37"** — o botão de modo só *liga*, não alterna. Alternar custou caro em 04/09: o bot estava preso reenviando `/resetar`, o primeiro clique não pareceu fazer nada (a janelinha só anda no `DoEvents` do `Log`), você clicou de novo e o modo desligou 6s depois de ligar — `03:14:54 MODO JOIAS` / `03:15:00 modo JOIAS desligado` — e o bot emendou um `/darmr` em vez de ir mixar. Vale igual pro MODO DRAGOES. A cada volta loga **jóias/h** (`== JOIAS: 12 mixadas em 3 ciclos | 4,1 joias/h ==`) — é o número que diz se o `$JoiasFarmMax` está bom; as métricas de `pontos/h` e ETA do MR não valem nada aqui, que não reseta. Se o inventário cheio não for detectado, vai mixar mesmo assim após `$JoiasFarmMax` (25 min).
- **Quando o bot decide mixar**: pelo **teto de tempo** (`$MixEveryMin`, 25 min), pela **mensagem do próprio jogo** ("inventário cheio") ou pelo botão **MIXAR AGORA**. A contagem periódica de células foi removida: abria e fechava o inventário a cada 2 min pra produzir um número que oscila com o alinhamento da grade (o *mesmo* inventário cheio leu 0 e 26 livres com 20px de diferença na âncora). `Inv-Free` continua no `-Preflight`/`-TestInv`, onde o número é só informativo.
- **O ciclo normal mixa sem parar de resetar** (`$MixEveryMin`). Antes o único gatilho fora do modo jóias era a mensagem do jogo — e ela **nunca chegou**: 0 ocorrências de "inventário cheio" em 42 mil linhas de `rpa.log`, contra **68** pausas manuais suas pra mixar na mão. A faixa do `$MsgBox` vive tomada por anúncio de troca de jogador, e o aviso não cai lá. O modo jóias já tinha o teto de tempo (`$JoiasFarmMax`) exatamente por isso; o ciclo de reset ficou anos sem gatilho nenhum. Um mix custa 30–70s (ida pro `/mixer`, mix, warp de volta, play). `$MixEveryMin = 0` desliga e volta pro gatilho antigo.
- **O contador do mix é a volta seguinte, não o "Sucesso!" do chat.** A joia que estava verde sair do verde é a prova de que mixou — se o clique não tivesse funcionado, ela continuaria verde e seria escolhida de novo. A leitura do `Sucesso! você mixou N` falhou em **5 dos 6** mixes que comprovadamente aconteceram (01/09 e 04/09), e o log fechava com `terminado (0 mix)` logo depois de mixar Soul, Life e Creation. Com o mix rodando sozinho a cada `$MixEveryMin`, um contador que sempre diz 0 esconderia a falha de verdade quando ela viesse.
- **`Close-Popup` aperta ESC e confere, em vez de dois às cegas.** Com nada aberto, o ESC **abre** o menu principal do jogo (Shop / Inventário / Personagem / … / Sair) — e esse painel tapa o **minimapa**, que é de onde sai o nome do mapa. Em 04/09 o mix terminou com a lista aberta, o 1º ESC fechou a lista e o 2º abriu o menu: o bot passou **65 minutos** cego, 251 `NAO CONSEGUI LER o nome do mapa`, reenviando `/losttower7` pra um minimapa tapado, sem farmar nada. Os dois ESC continuam (fecham popup empilhado no meio da tela, que o sensor não enxerga); depois deles, se o rótulo do minimapa estiver ilegível, mais um ESC fecha o menu. O sensor é o próprio `Read-Map` — sem lista de palavras nova pra calibrar.
- **O mix espera por resultado, não por relógio.** Medido em 164 mixes: `/mixer` → achar o NPC dava **12,4s** e `CONFIRMAR` → próxima volta dava **11,5s**, enquanto os passos que dependem de OCR já estavam em 1,6–2,5s. O tempo todo estava em dois sleeps cegos. Agora: depois do `/mixer` ele espera o **nome do mapa mudar** (mesmo teto do `$WarpWaitSec`; estourou, segue assim mesmo, porque o `Hover-Npc` confere o nome do NPC por OCR antes de clicar); e a espera pelo `Sucesso! você mixou N` virou **uma** leitura em vez de um laço de 5 — essa mensagem quase nunca chega e não decide nada, quem conta é a joia ter saído do verde na volta seguinte. `$MixWaitSec` caiu de 5 pra 2: quem tolera UI lenta é o `Achar-Ate`, que procura o menu até `$MixConfirmTentativas` vezes em vez de olhar uma vez.
- **Mix de jóias** (mecânica): vai no `/mixer`, passa o mouse no **Lahap** (o nome só aparece no hover — o bot confirma o nome por OCR antes de clicar), abre **Mixar Jóias** e clica em cada tipo que estiver **verde** (Soul, Life, Creation, Chaos), 5s entre cada um, até sobrar só vermelho — depois volta pro spot onde estava. Botão **MIXAR JOIAS** força na hora.
- **Modo Dragões** (botão **MODO DRAGOES**): ciclo próprio, igual ao de jóias — vai pro `/lorencia` e **só caça**. Não checa inventário, não checa atributos, não reseta e não dá `/darmr`. Varre a tela atrás dos **Golden Dragon** e clica em cima pra atacar; sem nada dourado, anda e procura de novo. Roda até você desligar. Se os guardas detectarem que está batendo em cenário, sai do modo sozinho e avisa. Lorencia é cidade, então o MU Helper fica desligado (`$GoldHelper`): clicar no play lá abre "precisa estar fora da cidade". ⚠️ **`$GoldPix` ainda não foi calibrado** — rode `-TestGold` com um Golden Dragon na tela; até lá o bot detecta cenário, avisa e volta.
- **`/darmr` por validação**: só quando os 4 atributos = **32767** manda `/darmr`, vai à tela de login e re-entra. Depois o personagem volta em Lorencia.
- **O warmup era o maior ponto isolado de demora do MR.** Contabilidade de 9 master resets com o código corrigido, num MR médio de 41,8 min: **warmup 13,9 min (33%)**, farm no Kanturu ~18,7 min (45%), distribuir pontos antes do reset 3,7 min (9%), confirmar reset 1,9 min (5%), warp+play 1,3 min (3%). Um reset de warmup custa **255s** contra **74s** no `$WarpCmd` — 9 min do MR são só o Lost Tower ser mais lento. Por isso, desde 08/09:
  - `$WarmupResets` caiu de 3 pra **2**. O 3º era o mais barato dos três (214s) e o char já chegava nele com ~18000 de atributo — é o que menos faz falta.
  - `$WarmupTeste` está **ligado**. Depois do `/darmr` o bot vai direto pro spot normal e tem `$WarmupTesteSec` (300s) pra fechar um reset lá; fechou, pula o warmup inteiro; estourou, o `Tick-WarmupTeste` percebe e cai pro Lost Tower pros 2 resets de sempre. Ficou desligado até 07/09 porque você preferia os resets garantidos — a conta mudou quando o warmup virou 33% do MR. Se auto-corrige a cada MR: não aguentou hoje, amanhã custa só o próprio teste.
  - O warmup **não é gordura pura**: ele leva o char de 6000 pra ~24500 de atributo (4,1x). É por isso que a saída é um teste com fallback, e não simplesmente apagar o warmup.
- **Não relê o status quando a sobra já não dá comando.** Depois de mandar o plano, o bot sabe quanto sobrou (pontos − soma do plano). Se essa sobra já está abaixo do piso por comando, a volta seguinte do laço só abriria o `C` de novo (~3s, roubando foco) pra concluir "nada a distribuir agora". Medido: `level 350 → /resetar` levava **11,1s** por reset e essa releitura era a maior fatia. Continua relendo quando a sobra ainda renderia comando ou quando passou do `$StatMaxLeftover`.
- **Cota diária: DESLIGADA** (`$MrsPorDia = 0`, sem limite). Ela foi criada quando o bot fazia 6 MR/dia e o teto de 10 nunca encostava; depois que o captcha e a cauda lenta foram corrigidos o MR caiu pra ~0,61h (~39/dia) e a cota passava a morder antes do meio-dia. O mecanismo continua inteiro — é só pôr um número maior que 0 de volta. Com valor > 0: batendo a cota o bot **para de resetar** e cai no **modo jóias** — farma no spot da fase, mixa, repete, sem `/resetar` e sem `/darmr` — até virar o dia. À meia-noite ele zera a contagem e **volta a resetar sozinho**. `$MrsPorDia = 0` desliga o limite.
  A contagem é por **dia do calendário** e mora no `estado.txt` (`mrsDia=` / `mrsDiaData=` / `cotaJoias=`): reiniciar o bot **não fura a cota**, e a máquina desligada a noite toda também não atrapalha — o que vale é a data, não um relógio que só anda com o bot aberto. O `cotaJoias=` existe pra separar "modo jóias que a cota ligou" de "modo jóias que **você** ligou": virar o dia só tira o bot do primeiro.
  **Não encerra o processo.** O watchdog foi removido deste projeto, então bot fechado não volta sozinho no dia seguinte — o descanso é dentro do mesmo processo, com a janelinha aberta.
  O botão **Normal /k37** fura a cota de propósito, mas só por **um** MR: com o `mrsDia` já no limite, o master reset seguinte re-arma o descanso sozinho.
- **Alvo de reset: 305** (`$TargetLevel`). Esta conta tem **Fenrir**, que baixa a exigência de reset em 45 levels — de 350 pra 305. O `$LevelMinReset` acompanhou.
  O `minReset=` do `estado.txt` é restaurado **sempre** no load (diferente do `alvo=`, que só entra com `$AutoTune`), então trocar o CONFIG sem apagar aquela linha não adianta — o valor velho volta por cima. Foram limpos dos 5 arquivos de estado em 11/09 (backups `.bak-fenrir`).
  O bot re-aprende o mínimo pela mensagem do servidor, mas só **pra cima**: um valor baixo demais se corrige sozinho, um alto demais não.
  O A/B antigo (350 vs 380, `272925` contra `175938` pontos/h) sugere que alvo **menor** rende mais — o ciclo encurta mais do que os pontos por reset caem. Então 305 deve ficar acima de 350; o `pontos/h` do log confirma.
- Alvo anterior: **350**, fixado por decisão sua. O A/B automático está **desligado** (`$AutoTune = $false`) e, com ele desligado, o `alvo` gravado no `estado.txt` é ignorado — quem manda é o CONFIG, senão um alvo antigo do experimento sobrescreveria sua escolha pra sempre.
- **Teste do spot pós-`/darmr`** (`$WarmupTeste`, hoje **desligado**): se ligado, o bot vai pro spot normal depois do MR e dá `$WarmupTesteSec` (300s) pra fechar um reset lá; fechou, pula o warmup inteiro; estourou, cai pro Lost Tower. Está off porque você prefere os 3 resets garantidos de warmup.
- **Spot: `/k37` → Kanturu** (`$WarpMap = 'kant'`, confirmado no log das 12:01). Se `$WarpMap` estiver **vazio**, o bot **aprende**: adota o mapa onde estiver depois de mandar o warp, desde que não seja cidade, e grava no `estado.txt` junto com o comando (`warpCmd=`/`warpMap=`). Trocar o `$WarpCmd` invalida o nome antigo e ele reaprende. CONFIG preenchido sempre manda.
  A regra de aprendizado é só *"mandei o warp e estou num mapa que não é cidade"* — exigir que o mapa **mudasse** estava errado e travou de verdade: o personagem já estava em Kanturu, o mapa não mudou, nada foi aprendido, e o bot queimou os 4 warps em sequência (`nao teleportou pro spot certo (mapa: 'kanturu', esperado '', antes 'kanturu')`). Já estar no destino é o caso de sucesso mais comum, não uma falha.
- Confirma o resultado das ações: após `/k37` lê o nome do mapa (minimapa) e só segue quando está no spot de farm (confirma por mudança de mapa) (reenvia até 4x, senão avisa). Liga o play e confirma o helper rodando; não fica clicando à toa (máx 3). Se o level fica parado fora do spot, re-teleporta; parado no spot, religa o helper (miss infinito).
- **Confere o reset em 1s, não em 4.** Medido no MR #15: `/resetar` → `reset feito` deu mediana 5s e **mínimo 5s** em 19 resets. Mínimo igual à mediana é piso artificial — ninguém estava esperando o servidor, era o `Wait 4` mais a leitura. São **139s por master reset** só pra *perceber* um reset que já tinha acontecido. A primeira conferida agora sai em 1s e o ritmo volta pra 4s; o relógio do reenvio (`$ResetWaitSec`) é absoluto desde o envio, então conferir cedo não reenvia nada antes da hora.
- **`Start-Helper` espera acordado.** Depois de clicar no play ele lia o botão a cada 0,4s dentro da mesma janela de 2,5s, em vez de dormir os 2,5s inteiros — ~2s por ciclo, ~42s por master reset. O piso **antes do segundo clique** continua idêntico, e é o que importa: o play é um **alternador**, e clicar de novo cedo demais *desliga* o helper. Era só pra isso que o sleep cheio existia.
- **Anatomia de um ciclo rápido (~66s), medida:** 6s do reset até o helper rodando, **41s de farm** (lado do jogo, não dá pra apressar), 19s do level 300 até o próximo reset. Os 25s fora do farm são o que o bot controla — é lá que os cortes acima mordem.
- **Pontos subindo desliga o miss infinito.** Terceira condição, além das duas abaixo: se os **pontos disponíveis** subiram desde a última avaliação, o char está matando — o level é que anda em degraus. Medido no MR #15, o melhor do log: dos 19 ciclos, os 3 com miss infinito somaram **646s de excesso** sobre o p25 (61s), e um deles disparou **10 vezes seguidas** com o char ganhando ponto o tempo todo (16, 32, 64...). Era a maior causa isolada da cauda lenta, acima do captcha. A base de comparação é atualizada em toda avaliação: distribuir os pontos zera o disponível, e sem isso a guarda ficaria desligada pelo resto do ciclo.
- **Miss infinito: `$StallReads` (3) leituras seguidas com o level idêntico *e* pelo menos `$StallMinSec` (15) segundos** -> ESC + pausa + anda + despausa (desbuga). Era 40s cravado (antes 75). A métrica do próprio bot aponta `stall` como **23-27% de todo o tempo**, e a maior parte disso é latência de *detecção*, não de recuperação: 113 disparos × 40s ≈ 75 min de uma sessão só esperando pra perceber. As duas condições juntas cortam isso pela metade sem falso positivo — as leituras iguais são o sinal forte (e uma leitura que o OCR **não** conseguiu não entra na conta; antes ela empurrava o relógio como se o level estivesse parado), e os segundos são o piso pro char fraco logo depois do reset. Botão PAUSE/RETOMAR na janela pra mixar joias no NPC.
- **`Check-Progress` devolvia dois valores** e por isso o ciclo nunca reiniciava depois de re-teleportar: `Start-Helper` retorna `$true`/`$false`, e sem descartar isso a função saía com `@($true,$false)`. Um array de 2 itens é sempre verdadeiro em PowerShell, então o `if(-not (Check-Progress ...))` do chamador nunca entrava e o `return $false` era engolido. Achado pelo self-check novo do `test_ciclos.ps1`, não em produção.
- De vez em quando (2–7 min, aleatório) faz algo "humano": anda um pouco e volta, abre/fecha status ou chat, mexe o mouse. Os intervalos de tudo variam ±25% (`$JitterPct`) — só o **ritmo**, nunca os valores dos stats.
- Captcha de imagem: resolve sozinho (seleciona, confere a borda vermelha, confirma). Se não tiver certeza, avisa (toast + beep) e espera você. **Errou 2 vezes -> PAUSA e espera você** (`$CapKillGame = $true` volta a regra antiga de fechar o jogo).
- **`$CapConfidence` é 0,65, não 0,5 — e esse era o gargalo do MR.** Captcha não resolvido **trava o jogo**: o char não farma, o `/resetar` não pega, e o bot fica relendo a mesma imagem estática a cada 5s pra sempre. No MR #30 foram 12 captchas distintos, **192** linhas de `ambiguo` e 4 travados; o MR levou **4,59h** contra 0,71h do MR #15 (20 `/resetar` → 20 resets, 0 reenvios, contra 39 → 22 com 11 reenvios e 6 `reset travado`). As razões medidas (melhor/segundo): `0,132 0,199 0,218 0,431 0,487 0,493` passavam; `0,503 0,504 0,514 0,515` eram recusadas — e a de 0,515 foi aberta na mão, com a **resposta certa**. Lixo de verdade (o cursor tapando a opção certa) deu **0,98**, bem longe do novo limite. Errar não é grátis, mas é limitado: o bot confere a borda vermelha depois de clicar e **pausa após `$CapMaxTries`**; não clicar custava ~1h por captcha.
- **Deu ambíguo? tira outra foto com o ponteiro fora do caminho antes de desistir.** O cursor aparece na captura e a seta cobre um pedaço do quadradinho embaixo dele — o mesmo problema que o `Tirar-Cursor` já resolvia no mix, e que o caminho do captcha nunca chamou. Em 04/09 o ponteiro parou em cima da opção **certa** e o bot ficou preso das 06:09 às 06:41, se reiniciando sozinho no meio: `score=320229` contra `327168` no segundo (0,98). Um acerto de verdade fica em **23–68 mil**, 0,07–0,18 do segundo — o `$CapConfidence` (0,5) estava certo em recusar, quem estava errado era a foto. O ponteiro volta pra onde você deixou. O `-NoClick` (`-TestImage`/`-Preflight`) não entra nisso: roda sobre PNG salvo, sem jogo aberto.
- Se cair pra tela de login/servidor no meio do farm, ele detecta e volta sozinho. **Nunca clica em coordenada chutada** numa tela que tenha "CRIAR NOVA CONTA" ou "Sair" — avisa e espera.
- Se o jogo fechar, o bot não morre junto: espera o cliente voltar, re-entra e retoma. Janela com **área cliente 0x0** (minimizando, ou o cliente reiniciando) entra nesse mesmo caminho — antes `New-Object Bitmap(0,0)` estourava com "Parâmetro inválido" e o `catch` do loop tratava como erro fatal.

## Jogo num monitor, você no outro

`$NoFocusRead = $true` (ligado). Modo **"não brigo por foco nem pelo seu mouse"**, pra deixar o jogo rodando num monitor enquanto você trabalha no outro:

- **Lê sem foco.** Level, mapa, status, captcha, inventário — a maior parte do que o bot faz — sai da captura direta da área cliente, sem trazer o jogo pra frente.
- **`Hold-Focus` não puxa mais o jogo a cada volta do loop.** Era isso que fazia o bot brigar com você mesmo quando só ia ler o level: uma vez *por iteração*, sempre. Agora só quem manda comando (`Send-Chat`, `Click-Client`, `Read-Status`) pede foco, e devolve no fim do bloco.
- **O ponteiro volta pra onde você deixou** depois de cada clique — guardado antes e restaurado depois do `mouse_up` (antes disso o jogo não registra o clique).
- **O "humano: mexe o mouse" é pulado**: arrastaria o *seu* ponteiro por até ~5s. Os outros disfarces (andar, abrir/fechar status e chat) continuam.
- **A janelinha do bot nasce no monitor do jogo**, canto inferior esquerdo. Usava `PrimaryScreen`, e aqui o monitor 2 fica em **X negativo** (`-1920..0`) — a conta antiga jogava a janela pro monitor errado. Vale também pro `Fugir-Da-Area`, que a move quando ela tapa algo que o bot precisa ler.
- **Rede de segurança no `Press-Vk`**: `keybd_event` é global, vai pra janela que estiver na frente. A guarda fica no primitivo, não em cada chamador, então nenhum caminho novo pode esquecer dela — sem o jogo em foco, a tecla **não é enviada** (e o log avisa, no máximo 1× por minuto). Sem isso um `ESC`/`Enter`/`C` perdido cairia no que você está fazendo no outro monitor.

Em troca, **a janela do jogo precisa ficar visível e destapada**: sem foco pra conferir, uma janela por cima dela vira leitura de lixo. `$NoFocusRead = $false` volta ao comportamento antigo (um monitor só).

Verificado ao vivo com `-Check`: leu `level 400 | helper running`, e o foco (`HX Chat`) e o mouse `(173,907)` ficaram exatamente onde estavam.

## Multibox: 4 clientes de uma vez

Duplo clique em **`MudinhoX RPA - 4 clientes.cmd`**. Ele confere que há 4 janelas do `mudx` abertas e sobe **um bot por cliente**:

| slot | arquivos |
|---|---|
| 1 | `rpa1.log`, `estado1.txt`, `captcha1\` |
| 2 | `rpa2.log`, `estado2.txt`, `captcha2\` |
| 3 | `rpa3.log`, `estado3.txt`, `captcha3\` |
| 4 | `rpa4.log`, `estado4.txt`, `captcha4\` |

**Todos vão pro mesmo spot** (o `$WarpCmd`, hoje `/k37`): os chars sobem em **party**, e party quer eles juntos. Houve um `$SlotSpots` que dava um spot por slot (`/k37`, `/k36`, …) pra não dividirem mapa — saiu quando a decisão virou party.

O título de cada janelinha diz o slot. **Pra parar todos de uma vez**, crie um `stop.flag` (sem número) na pasta — fechar uma por uma no meio de um `/darmr` foi o que deixou o estado do char inconsistente em 08/09.

- **Um processo por cliente, não um processo com N janelas.** Todo o estado do bot (`fase`, `warmupCount`, `resets`, `lvlPrev`, `stCarry`, `mixLast`…) vive em variáveis `$script:`; virar estado-por-janela seria reescrever o arquivo inteiro. Com um processo por slot, a lógica de um cliente fica intocada — e `-Slot 0` (o padrão) roda exatamente como sempre.
- **Revezamento, não paralelo.** `keybd_event` e `mouse_event` são globais: vão pra janela que estiver em primeiro plano. Um mutex de sistema (`Global\MudinhoX-Input`) garante que só um bot mexe no jogo por vez — sem ele, o `/resetar` de um cai no cliente do outro. Quem pega a vez é o `Focus-Game`; quem devolve é o `Restore-Focus`/`Release-Focus`, que já eram o par "vou mexer no jogo".
  A trava é **idempotente de propósito**: o `Focus-Game` é chamado solto em vários lugares sem um `Restore-Focus` casado, e mutex conta reentradas — pegar 2x e soltar 1x travaria os outros três pra sempre. Tem teto de 120s e trata `AbandonedMutexException`, pra um bot morto com a trava na mão não parar a fila.
- **Não cabe paralelo mesmo.** O cliente é 1920x1009 e o monitor 1920x1080: cabe **um** por monitor. Quatro se tapam por completo, e a leitura sai de `CopyFromScreen` na área da janela — janela tapada é leitura de lixo. Por isso o `-Slot` força `$NoFocusRead = $false` (cada um traz a sua janela pra frente antes de ler) e iguala o `$PollBgSec` ao `$PollSec` (no revezamento "não estava na frente" é o caso normal, e 60s deixariam o level passar de 350 pra 400). Reduzir as janelas não é alternativa: todas as coordenadas são calibradas em 1920x1009.
- **Cada bot apaga da captura a janelinha dos outros**, não só a sua (`Outras-Janelinhas`, achadas pelo título e em cache de 30s). Com quatro na tela, a do slot 2 em cima do `$LevelBox` do cliente 1 viraria leitura de lixo. Mascarar é mais barato e mais seguro que posicionar as quatro fora de tudo que o bot lê — o inventário e o modal do mix nem têm posição fixa.
- **Custo:** a tela alterna entre os clientes o tempo todo, e `SetForegroundWindow` rouba o foco do sistema inteiro. A máquina fica ruim de usar enquanto roda. O modo "jogo num monitor, você no outro" (`$NoFocusRead = $true`) só existe pro caso de **um** cliente.

## Nenhuma coordenada cravada

O bot está migrando de coordenadas fixas para **auto-localização**: cada coisa se acha sozinha, por texto onde há texto. Foi o que tornou possível rodar o mesmo código no cliente desktop em `1920x1009` e na aba do navegador em `1024x720`.

| | como se localiza |
|---|---|
| atributos, pontos | pelo **rótulo** (`Força`, `Pontos`) — pega o número à direita, na mesma linha |
| nome do mapa | pela **coordenada do char** no minimapa (`132,125`) — nada mais na tela tem a forma `número,número`; o nome é a palavra à esquerda |
| level | **auto-calibrado**: o painel mostra `Level: 400` *com rótulo*, e isso é verdade; com o número certo na mão, procura ele na faixa inferior e guarda o recorte |
| captcha | acha a âncora `Selecione a mesma imagem` por OCR |
| inventário | acha a grade pelo título da janela |
| modal do mix | acha `Mixar` e os nomes das joias por OCR |

**Por que o level precisou de auto-calibração:** ele é um número **solto** na HUD, sem rótulo do lado, e a posição não transfere nem por fração — fica em 0,56 da largura no desktop e 0,62 na web. E o OCR do Windows **não enxerga** ele numa varredura de tela cheia (mesma limitação que já obrigava o painel a ser ampliado 2x), então a busca é na faixa inferior (`$LevelFaixaBase`, fração da altura) com ampliação.

Validação: o desktop calibrou sozinho em `(1121,932)`. O `$LevelBox` cravado que existia antes era `X=1080, y=927` — a auto-calibração achou o mesmo lugar que a calibração manual.

Se o recorte parar de dar número plausível (janela redimensionada, layout trocado), a caixa é descartada e ele recalibra na próxima leitura de status. E sem calibração o `Read-Level` devolve `$null` em vez de inventar — level errado manda o bot resetar na hora errada.

Os que **não são texto** não podiam ser OCR, mas também deixaram de ser pixel cravado:

| | como se localiza |
|---|---|
| chat aberto | a borda é uma **linha vermelha contínua e longa**; o orbe de vida também é vermelho, mas redondo, então a corrida por linha é curta. O que separa é o **comprimento da corrida em fração da largura**, não a posição |
| botão play/pause | maior concentração de verde-ou-vermelho no canto superior esquerdo **do canvas**. Achou desktop em `(78,30)` (o cravado era `77,33`) e web em `(78,115)` |
| NPC do mix | fração do canvas como **ponto de partida**, varredura em volta, e quem autoriza o clique continua sendo o OCR do nome no hover. O ponto confirmado fica guardado pra próxima |
| painel de status, login, menu do jogo | fração da área cliente / do canvas |

**Topo do canvas:** na aba do navegador, abas e barra de endereço ocupam ~85px no topo, e sem descontar isso a busca do play achava **favicon de aba**. Separar por brilho não funciona — a barra de abas do Chrome no tema escuro é tão escura quanto o jogo. O que funciona é ancorar no rótulo do minimapa, que o `Read-Map` já localiza: ele fica ~68px abaixo do topo do canvas no desktop e ~85px na web.

**Onde o bot se recusa a chutar:** com o painel de status por cima do botão play, `Get-HelperState` devolve `unknown` em vez de um palpite — clicar no lugar errado é pior que não achar, e o `Start-Helper` já trata `unknown` esperando sem clicar.

**Sobrou em pixel:** só o `$ClientEsperado`, que é a referência de calibração, não uma coordenada de leitura.

## Uso

Duplo clique em **`MudinhoX RPA.cmd`** com o jogo aberto. Pede permissão de administrador (o jogo roda como admin; sem isso o Windows ignora o teclado/mouse do bot). Abre uma janelinha com log e botão **PARAR** (ou feche a janela). Também para se criar um arquivo `stop.flag` na pasta.

A janelinha é **compacta: 302x239** (era 400x380, 53% menos área). Não é só estética — o `Capture-Raw` pinta a área dela de **preto** em toda captura pra ela não sujar o OCR, então janela menor significa menos tela do jogo cega, e o `Fugir-Da-Area` precisa movê-la com menos frequência. Oito botões numa grade de 3 colunas, fonte 7,5 e `AutoScaleMode = 'None'` (o layout é todo em pixel fixo, como o resto do bot).

O rótulo de status saiu: ele mostrava a **última linha de log**, que a caixa de log logo abaixo já mostra inteira — duas coisas dizendo o mesmo, e a versão dele truncava no meio da frase.

Texto e cor dos dois botões de MODO saem de **um lugar só** (`Sync-BotoesModo`). Eram seis cópias espalhadas — nos três handlers de clique, no `Show-Ui`, na retomada do `estado.txt` e no gatilho da cota — e cada mudança de layout obrigava a caçar todas.

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
powershell -ExecutionPolicy Bypass -File .\test_mix.ps1                                  # self-check do gatilho do mix por tempo (teto, botao e desligamento)
powershell -ExecutionPolicy Bypass -File .\test_cota.ps1                                 # self-check da cota diaria de MRs (descanso no modo joias, virada de dia, persistencia)
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
- `$MixEveryMin` (25): no ciclo normal, vai mixar a cada N min sem parar de resetar. `0` desliga (aí só a mensagem do jogo e o botão). Não confunda com o `$JoiasFarmMax` (8), que é o teto do **modo jóias**.
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
