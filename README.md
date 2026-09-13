# RPA do MudinhoX

Loop automático: `/s18` -> play (MU Helper) -> espera level 350 -> `/resetar` -> repete.

- Nunca envia stat < 1000 (`/a` pequeno teleporta pra AIDA; atributo que precisa <1000 fica pro próximo tick com mais pontos).
- Stats `/f`, `/a`, `/v`, `/e`: a cada ~90s (e logo após cada reset) abre a janela de status (C), lê os 4 atributos (Força/Agilidade/Vitalidade/Energia) e os **pontos disponíveis**, e distribui de verdade — só nos atributos abaixo do máximo, dividindo os pontos entre eles; valores variam, nunca repete.
- **`/darmr` por validação**: só quando os 4 atributos = **32767** manda `/darmr`, vai à tela de login e re-entra. Depois o personagem volta em Lorencia: entra em **modo warmup** — usa `/losttower7` e farma lá até **10 resets** (distribuindo os pontos), depois volta ao `/s18` normal.
- Confirma o resultado das ações: após `/s18` lê o nome do mapa (minimapa) e só segue quando está no spot de farm (confirma por mudança de mapa) (reenvia até 4x, senão avisa). Liga o play e confirma o helper rodando; não fica clicando à toa (máx 3). Se o level fica parado fora do spot, re-teleporta; parado no spot, religa o helper (miss infinito).
- Passos após `/s18` vão numa direção aleatória a cada chegada.
- Level parado 75s (miss infinito) -> pausa + anda + despausa (desbuga). Botão PAUSE/RETOMAR na janela pra mixar joias no NPC.
- De vez em quando (2–7 min, aleatório) faz algo "humano": anda um pouco e volta, abre/fecha status ou chat, mexe o mouse.
- Após `/s18` anda ~4 passos pra frente antes de ligar o play.
- Captcha de imagem: resolve sozinho (seleciona, confere a borda vermelha, confirma). Se não tiver certeza, avisa (toast + beep) e espera você. **Errou 2 vezes -> fecha o jogo (mudx.exe) e para** (não arrisca a 3ª).

## Uso

Duplo clique em **`MudinhoX RPA.cmd`** com o jogo aberto. Pede permissão de administrador (o jogo roda como admin; sem isso o Windows ignora o teclado/mouse do bot). Abre uma janelinha com log e botão **PARAR** (ou feche a janela). Também para se criar um arquivo `stop.flag` na pasta.

Log completo em `rpa.log`. Prints de captcha e da última janela de status em `captcha\`.

Modos de teste (não clicam em nada):

```powershell
powershell -ExecutionPolicy Bypass -File .\mudinhox_rpa.ps1 -Check                        # lê level, botão play, captcha, chat aberto
powershell -ExecutionPolicy Bypass -File .\mudinhox_rpa.ps1 -TestImage .\captcha\exemplo.png  # testa o solver num print
```

## Ajustes (bloco CONFIG no .ps1)

- Coordenadas relativas à área cliente do jogo em 1920x1009.
- `$PointsPerLevel` / `$PointsPerReset`: pontos de atributo por level e por reset (base do valor dos stats). Chute inicial 4 / 2000.
- `$LoginBtn`: botão pra entrar com o personagem após `/darmr` (centro embaixo). O bot procura o texto "Entrar/Conectar/..." por OCR antes de usar essa coordenada.
- O jogo precisa estar visível na leitura. Se outra janela estiver na frente, o bot traz o jogo por ~1s, lê e devolve o foco (aí lê a cada 60s em vez de 10s). Se o Windows negar o foco, ele pula em vez de digitar no lugar errado.

## Versão Python

`rpa_mudinhox.py`, `calibrar.py`, `config*.json`, `requirements.txt`: versão em Python (pyautogui + Tesseract, hotkeys F8/F9). Independente do `.ps1`; o `.cmd` não usa nada disso.
