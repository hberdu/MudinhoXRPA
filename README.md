# RPA do MudinhoX

Loop automático: `/s18` -> play (MU Helper) -> espera level 350 -> `/resetar` -> repete.

- Nunca envia stat < 1000 (`/a` pequeno teleporta pra AIDA; atributo que precisa <1000 fica pro próximo tick com mais pontos). Exceção: `/f`, `/v`, `/e` podem mandar menos quando é pra **fechar exatamente** o 32767.
- Stats de **5k em 5k** (`$StatStep`): 5000, 10000, ... 30000 e por fim **32767** (o cap que o `/darmr` exige — abaixo disso o jogo recusa). Dentro de cada etapa enche **um atributo por vez, nesta ordem: energia, agilidade, força, vitalidade**. Se faltar menos de 1000 pra fechar a etapa num atributo, passa um pouco da meta em vez de travar (senão a etapa inteira empaca e os pontos empilham).
- A cada 15s (e logo após cada reset) abre a janela de status (C), lê os 4 atributos + os **pontos disponíveis** e manda os valores exatos. Uma leitura de status rende o plano inteiro (até 28 comandos), não uma etapa por leitura.
- Nunca deixa mais de **10k de pontos sobrando** (`$StatMaxLeftover`): distribui **antes de cada `/resetar`** e, se ainda sobrar mais que isso, segura o reset e tenta de novo (até 3x) em vez de gerar mais 2000 pontos. Se não conseguir gastar nada, avisa.
- **Mix de jóias**: quando o inventário enche, vai no `/mixer`, passa o mouse no **Lahap** (o nome só aparece no hover — o bot confirma o nome por OCR antes de clicar), abre **Mixar Jóias** e clica em cada tipo que estiver **verde** (Soul, Life, Creation, Chaos), 5s entre cada um, até sobrar só vermelho — depois volta pro spot onde estava. Botão **MIXAR JOIAS** força na hora.
- **Dragões Dourados**: **só pelo botão** DRAGOES DOURADOS (nunca automático) — vai pro `/lorencia` e varre a tela atrás dos **Golden Dragon**, clica em cima pra atacar; sem nada dourado, anda e procura de novo. Para sozinho em 20min e volta pro farm. Lorencia é cidade, então o MU Helper fica desligado (`$GoldHelper`): clicar no play lá abre "precisa estar fora da cidade". ⚠️ **`$GoldPix` ainda não foi calibrado** — rode `-TestGold` com um Golden Dragon na tela; até lá o bot detecta cenário, avisa e volta.
- **`/darmr` por validação**: só quando os 4 atributos = **32767** manda `/darmr`, vai à tela de login e re-entra. Depois o personagem volta em Lorencia: entra em **modo warmup** — usa `/losttower7` e farma lá até **10 resets** (distribuindo os pontos), depois volta ao `/s18` normal.
- Confirma o resultado das ações: após `/s18` lê o nome do mapa (minimapa) e só segue quando está no spot de farm (confirma por mudança de mapa) (reenvia até 4x, senão avisa). Liga o play e confirma o helper rodando; não fica clicando à toa (máx 3). Se o level fica parado fora do spot, re-teleporta; parado no spot, religa o helper (miss infinito).
- Level parado 40s (miss infinito) -> pausa + anda + despausa (desbuga). Botão PAUSE/RETOMAR na janela pra mixar joias no NPC.
- De vez em quando (2–7 min, aleatório) faz algo "humano": anda um pouco e volta, abre/fecha status ou chat, mexe o mouse. Os intervalos de tudo variam ±25% (`$JitterPct`) — só o **ritmo**, nunca os valores dos stats.
- Captcha de imagem: resolve sozinho (seleciona, confere a borda vermelha, confirma). Se não tiver certeza, avisa (toast + beep) e espera você. **Errou 2 vezes -> PAUSA e espera você** (`$CapKillGame = $true` volta a regra antiga de fechar o jogo).
- Se cair pra tela de login/servidor no meio do farm, ele detecta e volta sozinho. **Nunca clica em coordenada chutada** numa tela que tenha "CRIAR NOVA CONTA" ou "Sair" — avisa e espera.
- Se o jogo fechar, o bot não morre junto: espera o cliente voltar, re-entra e retoma.

## Uso

Duplo clique em **`MudinhoX RPA.cmd`** com o jogo aberto. Pede permissão de administrador (o jogo roda como admin; sem isso o Windows ignora o teclado/mouse do bot). Abre uma janelinha com log e botão **PARAR** (ou feche a janela). Também para se criar um arquivo `stop.flag` na pasta.

Log completo em `rpa.log`. Prints de captcha e da última janela de status em `captcha\`.

Modos de teste (não clicam em nada):

```powershell
powershell -ExecutionPolicy Bypass -File .\mudinhox_rpa.ps1 -Check                        # lê level, botão play, captcha, chat aberto
powershell -ExecutionPolicy Bypass -File .\mudinhox_rpa.ps1 -TestImage .\captcha\exemplo.png  # testa o solver num print
powershell -ExecutionPolicy Bypass -File .\mudinhox_rpa.ps1 -TestInv                     # inventário ABERTO no jogo: salva print e mostra as células ocupadas
powershell -ExecutionPolicy Bypass -File .\mudinhox_rpa.ps1 -TestMix                     # modal de mix ABERTO: mostra o que o OCR lê e a cor de cada opção
powershell -ExecutionPolicy Bypass -File .\mudinhox_rpa.ps1 -TestNpc                      # no /mixer, mouse em cima do Lahap: mostra a coordenada dele
powershell -ExecutionPolicy Bypass -File .\mudinhox_rpa.ps1 -TestGold                     # com um Golden Tantalos na tela: marca em verde o que o detector achou
powershell -ExecutionPolicy Bypass -File .\mudinhox_rpa.ps1 -TestVisao                    # regressão das funções de leitura de tela (usa os prints de fixtures\)
powershell -ExecutionPolicy Bypass -File .\test_stats.ps1                                # self-check da distribuição em etapas (não toca no jogo)
powershell -ExecutionPolicy Bypass -File .\test_estado.ps1                               # self-check do estado persistido (métricas sobrevivem a restart)
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
- `$InvGrid` (grade do inventário) e `$MixNpcPos` (posição do Lahap): já calibrados nesta resolução; refaça com `-TestInv` / `-TestNpc` se mudar de resolução.
- `$KeyHoldMs` / `$KeyGapMs` (40/40): velocidade da digitação. **Não baixe** — abaixo disso o comando embaralha e o `/s18` sai inválido.
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
