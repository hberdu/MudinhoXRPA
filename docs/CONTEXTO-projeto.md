---
name: proj-rpa-mudinhox
description: "MudinhoX (MU Online) RPA bot in PowerShell at OneDrive\\Área de Trabalho\\proj_RPA — state, decisions, gotchas"
metadata: 
  node_type: memory
  type: project
  originSessionId: 91c75d33-d4ea-46cd-b767-bfa23cfc1b67
  modified: 2026-08-28T13:09:59.169Z
---

Project: `c:\Users\henri\OneDrive\Área de Trabalho\proj_RPA\mudinhox_rpa.ps1` + launcher `MudinhoX RPA.cmd`.
Bot loop for game MudinhoX (process `mudx.exe`): warp (`$WarpCmd`, currently `/s18`) -> 4 steps random dir -> click play (MU Helper) -> wait level 350 -> `/resetar` -> repeat. Stats `/f`,`/a`,`/v`,`/e`: each tick opens status window (C), OCRs "Pontos: N" and distributes real available points — splits avail across the attributes still below max (share = avail/remaining), capped by what each attr needs, unique values; drains fast (re-schedules 4s while points remain). `/darmr` (master reset) ONLY when all 4 attrs (For/Agi/Vit/Ene) >= 32767 — user premise. Level stalled 120s -> Check-Progress (re-warp if not on farm map, else re-toggle helper); random "human" actions; captcha auto-solve, wrong twice -> kill game and stop.
Warp target changed from `/icarus` to `/s18` (2026-08-28). Teleport is confirmed by the minimap MAP NAME CHANGING (not by a hardcoded name) — `$WarpCmd` can be swapped to any `/sN` and `In-Farm`/`Warp-To-Spot` still work; `$script:farmMap` records the farm map (compared by first 4 chars).
Pure PowerShell 5.1 + Windows OCR (WinRT) + WinForms window with PARAR button; also stops on `stop.flag`; logs to `rpa.log`. Folder also has a Python/pyautogui/Tesseract version (`rpa_mudinhox.py`, created 2026-08-28 02:11, not by Claude — provenance unknown).

Decisions / gotchas (as of 2026-08-28):
- **Game runs elevated (High IL)**: keybd_event/mouse_event from a normal process are silently dropped (UIPI). Script self-elevates via `Start-Process -Verb RunAs` (UAC prompt each launch). Symptom was "focus works, typing does nothing".
- Focus: `ShowWindow(SW_SHOW)` then `AttachThreadInput` + `SetForegroundWindow`; never synthesize Alt (hijacked user's keyboard).
- Chat box: Enter toggles open/close; open box = red border rows y=898 and y=922, x 870–1130 (client 1920x1009). Send-Chat checks state first (Chat-Open) — if it assumes closed, letters become hotkeys.
- Hotkey C (status window) needs ~150ms key hold (40ms ignored). Typing commands at 40ms/60ms EMBARALHA (/s18 came out invalid, failed 4x); Type-Text now 90ms hold + ~130ms gap — verified /s18 types clean. Slower but every command (warp/reset/stats/darmr) lands.
- Client area size can change (user switched game from fullscreen 1920x1009 to windowed 1920x1061, +52px height). Coords anchored to the BOTTOM (level number, chat box) broke — Read-Level and Chat-Open now compute Y as img.Height - offset ($LevelBox.YFromBottom=82, $ChatBox.Y1/Y2FromBottom=111/87). Symptom: bot could not read the level -> never hit 350 -> never reset -> char stuck at 400. Play button (top, y33) and captcha (OCR-relative) and status (global OCR) were unaffected.
- **Reading attribute VALUES**: OCR of the whole screen or of isolated small crops is unreliable (truncated "1900"->"1", or empty). Parse-Attrs now reads from the GLOBAL OCR words (find each label For/Agi/Vit/Ene, take the number to its right on the same line) — robust to the status window shifting when the user changes game resolution (the old fixed StatCol crop broke: window moved left ~40px, crop cut the "F" of Força, no label matched). Read-Status re-reads up to 2x more with the window open, merging results. Verified 4/4 on a shifted window. GOTCHA: OCR often reads "Vitalidade" as "vwidade", so Vit pattern is `^v(?!elo).*dade` (matches vwidade/Vitalidade, excludes Velocidade detail line and Vida).
- CAP-CLOSE exception (2026-08-28): the flat <1000 floor left an attribute stuck a few hundred short of 32767 (e.g. Força 32347), so /darmr never fired and points piled up (47k). Fix: /a stays >=1000 (AIDA teleport), but /f /v /e MAY send <1000 when it exactly closes the cap (faltaCap), sent as the exact value (no jitter). So all 4 reach 32767 and /darmr fires; only /a can be left <1000 short (rare).
- Never send a stat command < 1000 (`$StatMinCmd`): `/a` with a small value (<100) teleports the char to AIDA. Server does NOT clamp (tested `/f 999999` -> rejected, For unchanged), so amt = min(pts, share, cap-current); if that is < 1000 the attr is skipped this tick (waits for more points). Consequence: attrs may stop <1000 short of 32767, so auto-/darmr may not fire — user does MR manually and relaunches with warmup.flag.
- `/darmr` by VALUE validation (user premise, 2026-08-28): Distribute-Points reads the 4 values; distributes points only into attrs < 32767 (share = pts/remaining); when all 4 = 32767 -> Master-Reset. Cap is **32767** (2^15-1), NOT 32670 — game rejects /darmr with "Você precisa estar com 32767 pontos em todos status!" below that (this caused a darmr loop when cap was 32670).
- Spot must MATCH the phase (2026-08-28): warmup expects Lost Tower (`$WarmupMap` "lost"), normal expects Stadium (`$WarpMap` "stad"), compared via Same-Map (first 4 chars). Fixed a bug where any non-city map (e.g. AIDA, where the char landed after a bad /a) counted as "already at spot". In-Farm/Warp-To-Spot now use Spot-Map, so Check-Progress re-warps if the char is on the wrong map.
- `/darmr` full flow (user, 2026-08-28): /darmr -> login screen -> click the enter-character button (center-bottom; Master-Reset finds it via OCR of $LoginWords ~1060,954, else $LoginBtn 960,940) -> char lands in Lorencia. Then **warmup mode**: `$WarmupCmd` `/losttower7`, farm there for `$WarmupResets`=10 resets (distributing points), THEN `$script:phase` back to 'normal' and resume `/s18`. Do NOT click play in the city (popup "precisa estar fora da cidade") — Master-Reset sets restartCycle so the loop goes straight to the warp. Distribute-Points does NOT trigger darmr while phase=warmup (loop guard in case master reset doesn't zero attrs). Close-Popup = ESC.
- Windows OCR on level digits: x8 no margin fails on "400"; Read-Level OCRs 4 variants (`$LevelOcrVariants`) and takes majority.
- Single monitor + user wants to work in another window ON TOP of the game (same desktop; virtual desktops do NOT work — DirectX capture of a hidden desktop is black, SetForegroundWindow switches desktop). Focus grouping: Hold-Focus/Release-Focus bring the game to front ONCE per block (poll iter, warp, reset, distribute) and return focus to the user window at the end (try/finally), instead of stealing focus per sub-action. Pause-Gate releases focus while PAUSED (mix jewels) and re-acquires on resume.
- UI has 3 manual mode buttons (user drives when the bot gets lost): "Warmup LT7" (phase=warmup, count=0), "Normal /s18" (phase=normal), "Atribuir tudo + MR" (forceMR: distributes + closes caps + /darmr). Each sets restartCycle so the loop restarts in the chosen mode; handled at up-until, reset-until and top of while. Plus PAUSAR/PARAR.
- Anti miss-infinito (user confirmed it IS the bug, not weakness): Check-Progress after StallSec (75s) does pause(play)+Walk-Forward+Start-Helper — WALKING unstucks it (just re-toggling helper was not enough). UI has a PAUSE/RETOMAR button (`$script:paused`, Pause-Gate in Wait + top of while) so user can pause the bot to mix jewels at the NPC without it stealing focus. Read-Status now re-reads up to 3x with the window open when Parse-Attrs misses an attribute (OCR drops one intermittently).
- Play button: green triangle = stopped, red bars = running.
- Captcha rule from user (2026-08-28): wrong twice -> kill mudx.exe and stop, never a 3rd try. Selected option shows 3px red border (255,0,0) ~61px from option center; bot verifies it before clicking Confirmar. Do all captcha clicks without changing focus in between (focus bounce made clicks land before selection registered).
- After `/icarus` walk ~4 steps in a RANDOM direction each arrival (isometric: vertical *0.75) before play. PrintWindow on the game returns black; screen capture only, bot masks its own window black in captures.
- Hotkey C right after a reset is ignored for a few seconds (teleport effect): wait ~8s and retry.
- **Confirm results, never repeat blindly (user premise, 2026-08-28)**: map name via OCR of minimap label (`$MapLabel` x1690,y68,230x30, scale4; Icarus label contains "caru"). Warp-To-Icarus resends /icarus only if map didn't change (≤4x). Start-Helper clicks play ≤3x and verifies helper running. Loop's Check-Progress: level stalled + not in Icarus -> re-warp; stalled in Icarus -> re-toggle helper (miss-infinito). Symptom that triggered this: /icarus silently failed, char stuck in Lorencia lvl 10, bot spammed stats forever.
- **Log resilience**: `Add-Content` per line stopped writing to rpa.log mid-run (froze at a line while the WinForms logBox kept updating) — concurrent-access flake. Fixed: one `StreamWriter` over `FileStream(...,Append,Write,FileShare.ReadWrite)`, AutoFlush, opened once. Reader (tail/Get-Content/monitor) must open with FileShare.ReadWrite too; monitor now reads via `cp rpa.log tmp` before grep.
- BOM gotcha: don't re-prepend a BOM to a heredoc file that already starts with one — double BOM makes PowerShell read `?$sp` and the var becomes empty (then FromFile fails, $img null, Read-Map falls back to live capture and reads the wrong map). Write the BOM exactly once.
- User plays manually in the same client while testing -> tests that type into the game get corrupted; ask them to stay off the game during runs.
- 2026-08-28: two Claude sessions edited this file concurrently, one clobbered the other's Read-Level; restored from backup. Check `.claude/projects/*proj-RPA*` transcript mtime before editing.
- Elevated test pattern: write .ps1 with UTF-8 BOM (path has "Área"), run via `Start-Process powershell -Verb RunAs -Wait`, log to a file in scratchpad (hidden window has no stdout).

**How to apply:** when user says "continue" from C:\Users\henri with no context, this project is the likely one; check its session transcript under `.claude/projects/c--Users-henri-OneDrive--rea-de-Trabalho-proj-RPA`.

Mudancas 2026-08-31 (pedido do usuario: "MR demora muito", distribuicao precisa, mix automatico):
- **Distribuicao em 4 etapas** (`$StatStages = 10000,20000,30000,32767`), ordem `$StatOrder = 'Ene','Agi','For','Vit'`. Dentro de uma etapa enche UM atributo por vez ate a meta (nao divide mais os pontos entre os 4). `Plan-Stats $st $p` e pura (so calcula os comandos) e tem self-check em `test_stats.ps1` (16 comandos do zero ao cap, ultima leva `2767` em cada — o usuario falou "2676", e 32767-30000=2767).
- Jitter/`Uniq-Amt` REMOVIDO: o usuario quer contagem exata, valor aleatorio quebrava as metas. Junto foram removidos `Note-Level`, `$ptsGained`, `$PointsPerLevel`, `$PointsPerReset`, `$StatMin`, `$StatMax` (estimativa morta; tudo vem do OCR do status agora).
- `Distribute-Points` roda tambem ANTES de cada `/resetar` (loop principal). Assim nunca sobra mais que ~2000 pontos alem do necessario ("nao gerar mais de 2k a mais").
- Velocidade: `$StatEverySec` 90->30, `$PollSec` 10->6, `Read-Status` sleep 900->500ms, `Wait 2`->`Wait 1.2` entre rodadas.
- `$StatMinAvail` 50->1 e o `break` do minimo por comando virou `if($p -le 0)`: senao o piso de 1000 impedia de FECHAR o cap com poucos pontos (bug CAP-CLOSE de novo).
- **Mix de joias**: `Mix-Jewels` = `/mixer` -> acha o NPC por OCR (`$MixNpcWords`) e clica `$MixNpcClickDy` px abaixo do nome -> acha "Mixar" (`$MixMenuWords`) e clica -> loop: acha Soul/Chaos/Creation/Life (`$MixJewels`) e usa `Word-Color` (pixels do proprio texto: verde vs vermelho) pra clicar so nos verdes, `Wait $MixWaitSec`(5s) entre cada, ate nao sobrar verde. Depois `$script:restartCycle = $true` -> loop volta pro spot pelo caminho normal. NAO clica no escuro: sem OCR -> Notify e volta.
- NPC do mix = **Lahap** (Lorencia). **O nome SO aparece com o mouse em cima** (usuario corrigiu isso 2026-08-31): nao da pra achar o NPC por OCR da tela. Solucao: `$MixNpcPos` fixo (o /mixer cai sempre no mesmo lugar) + `Hover-Npc` passa o mouse la, le a faixa ~70px acima do cursor (`$MixNpcNameDy`) e so clica se o OCR CONFIRMAR "Lahap"; se nao, varre os vizinhos (`$MixNpcSweep`). Calibrar com `-TestNpc` (mostra a coordenada do cursor + o que o OCR le).
- Inventario: grade de **8x8** (`Cols=8; Rows=8` ja e o default); acima dela fica a area de equipamento, que NAO entra na contagem. Cheio = 64 ocupadas.
- **Deteccao de inventario cheio NAO CALIBRADA**: `$InvGrid = $null` (usuario escolheu "abrir inventario e contar slots"). `Inv-Free` abre com V, conta celulas por brilho (`$InvCellLit`/`$InvCellMin`), cheio = menos de `$InvFreeMin` livres. Enquanto `$InvGrid` for `$null`, `Tick-Inventory` so age pelo botao MIXAR JOIAS da UI. Calibrar com `-TestInv` (inventario aberto, salva `captcha\inventario.png` + mapa X/.), e `-TestMix` (modal aberto, lista o que o OCR le + cor de cada palavra).
- **Tickrate (usuario pediu "comandos mais rapidos", 2026-08-31)**: tempos de teclado viraram config (`$KeyHoldMs` 25, `$KeyGapMs` 20, `$KeyClearMs` 12, `$ChatOpenMs` 130, `$ChatSendMs` 70) — antes era 40/40 fixo e 30 backspaces a 80ms cada (2.4s so pra limpar o chat). `$StatEverySec` 30->15, `$StatRoundSec` 0.5, `Read-Status` 500->350ms, `Click-Client` 150/80 -> 80/50ms.
- Digitacao rapida embaralha comando (gotcha antigo), entao `Send-Chat` agora **confere por OCR** (`Chat-Text`, crop da caixa de chat) o que digitou antes do Enter e redigita ate 3x. Se o OCR nao ler nada, segue mesmo assim (nao trava). E isso que torna 25/20ms seguro; se ver "saiu 'X' em vez de 'Y'" toda hora no log, sobe `$KeyHoldMs`.
- `Plan-Stats` agora simula o efeito de cada comando e planeja **as 4 etapas de uma leitura de status so** (16 comandos num plano), em vez de 1 leitura de OCR por etapa. Guard do `Distribute-Points` caiu de 24 pra 8 voltas.
- **Get-Game em cache (2026-08-31)**: era `Get-Process mudx` a CADA chamada, e Get-Game e chamado ~6x por comando (Focus-Game, Client-Origin, Capture-Raw, Chat-Open x2, Restore-Focus). Enumerar todos os processos do Windows entre um comando e outro era O gargalo do "intervalo entre comandos". Agora guarda o handle em `$script:gameH` e so re-resolve quando `IsWindow` falha (jogo fechou/reabriu).
- Digitacao voltou pra **40/40** (`$KeyHoldMs`/`$KeyGapMs`) por pedido do usuario: 25/20 nao era o problema, o problema era o overhead ENTRE comandos. Junto foi removida a conferencia por OCR do que foi digitado (`Chat-Text`/`Norm-Cmd`) — so existia pra segurar o teclado rapido. `Send-Chat` agora faz **1** captura de tela em vez de 2 (passa o `$img` pro `Chat-Open`).
- **Walk-Forward pos-warp REMOVIDO** (usuario: "pode remover as andadinhas apos chegar nos mapas"). A funcao continua, mas SO no desbug do miss infinito (`Check-Progress`).
- `$MixNpcPos = @{X=805;Y=285}` medido nos prints do usuario (Lahap em Lorencia, area cliente 1920x1009; nome em y~153, corpo em y~270-290).

Calibracao concluida 2026-08-31 (prints -TestMix / -TestInv):
- **Modal do NPC**: primeiro vem uma janela com TITULO "Mixar Joias" (y~378), a descricao "Aqui voce podera mixar/dissolver suas Soul's, Life's, Creation's, Chaos's" (y~459-475) e DOIS botoes: **"Mixar Joias" (y~535)** e "Dissolver Joias" (y~593). Bug pego na calibracao: `^mixar` casava com o TITULO primeiro (`select -First 1`) e o bot clicaria nele. Agora `$MixMenuWords = '^mixar$'` (exclui "mixar/dissolver") + `sort Y | select -Last 1` (o de baixo e o botao).
- Ordem real dos rotulos: **Soul, Life, Creation, Chaos** (nao Soul/Chaos/Creation/Life). Sao os nomes em INGLES, com apostrofe ("Soul's,"), dai `Pat = '(?i)^soul'` etc.
- FALTA ainda o print da SEGUNDA tela (a lista com verde/vermelho) — o -TestMix pegou so o primeiro modal.
- **`$InvGrid = @{X=1317;Y=408;Cell=34.4;Cols=8;Rows=8}`** com `$InvCellMin=10`: calibrado por busca em grade contra um mapa de ocupacao lido a olho do print, **64/64 celulas certas**. Cell e FRACIONARIO (34.4) — arredondar pra 34 acumula 3px de erro ate a 8a coluna e erra ~15 celulas; `Inv-Occupancy` usa `[double]` e converte so na hora do GetPixel.
- **Guarda obrigatoria `Inv-Open`**: com o inventario FECHADO a grade cai em cima do chao do mapa e le "8 livres" (aconteceu de verdade num -TestInv) — o bot acharia que esta cheio e mixaria pra sempre. Agora `Inv-Free` so confia no mapa se o OCR achar "Zen" na faixa logo abaixo da grade, e tenta abrir com V ate 3x.
- **Evento dos Dragoes Dourados** (pedido do usuario 2026-08-31): botao "DRAGOES DOURADOS" -> `/tarkan2` -> varre a tela procurando blocos DOURADOS (Golden Tantalos) e manda o personagem neles; sem nada dourado, anda e procura de novo; para em `$GoldMinutes` (20) e volta pro farm. Varredura em C# (`Img.BestGold`, LockBits) porque GetPixel em ~1M pixels no PowerShell levaria segundos. Ignora `$GoldSelfR` (150px) em volta do centro: o proprio personagem tem fogo/asas laranja e dava falso positivo. `$GoldPix` NAO calibrado com print real ainda — usar `-TestGold` com o mob na tela (salva `captcha\gold.png` com quadrado verde no que achou).
- **"/s18 nao saiu" (2026-08-31 17:00)**: o comando SAIA (log "chat: /s18"), o que falhava era `Read-Map` devolvendo `''` 8x seguidas -> `Warp-To-Spot` achava que nao teleportou e reenviava ate desistir. Diagnostico: o crop `(1690,68,230x30)` foi testado nos prints salvos e le "Tarkan 99,145"/"Lorencia 132,121" perfeitamente, e `Capture-Game` NAO logou falha -> a tela foi capturada e o rotulo nao estava la. Causa mais provavel: **a janelinha do bot em cima do minimapa** — `Capture-Raw` pinta `$script:ui.Bounds` de PRETO pra nao sujar o OCR, entao se o usuario arrasta a janela pro canto sup-direito o bot se cega sozinho (e o level, que fica embaixo, continua lendo normal — foi exatamente o sintoma). Correcoes: `Unblock-MapLabel` detecta a sobreposicao e DESCE a janela sozinha; `Read-Map` tenta uma faixa mais larga se a exata falhar; `Warp-To-Spot` separa "nao consegui LER o mapa" (cego, reenviar /s18 nao adianta) de "teleportou pro mapa errado", e salva `captcha\mapa_ilegivel.png` no primeiro caso.

Etapas de 5k + teto de sobra (2026-08-31, usuario: "bot esta ficando com muitos pontos acima do maximo"):
- **BUG RAIZ do acumulo**: `Plan-Stats` so mandava ate a meta da etapa. Se um atributo precisava de MENOS que `$StatMinCmd` (1000) pra fechar a etapa (ex Vit=4500, meta 5000, falta 500), nenhum comando saia pra ele, `$mandou` ficava $false e o planejador dava `break` — a etapa inteira TRAVAVA e os pontos empilhavam pra sempre. Correcao: quando o que falta pra etapa e < 1000, manda 1000 (limitado pelo cap), passando um pouco da meta em vez de travar. Regressao coberta no `test_stats.ps1` (teste 5).
- `$StatStep = 5000` -> `$StatStages` montado a partir do cap: 5000,10000,...,30000,32767 (7 etapas, 28 comandos do zero ao cap).
- **O usuario pediu cap 32567; NAO usar.** O `/darmr` exige exatamente 32767 ("Voce precisa estar com 32767 pontos em todos status!") — 32670 ja causou loop de darmr recusado. Mantido 32767 e explicado a ele.
- `$StatMaxLeftover = 10000`: antes do `/resetar` o loop distribui e, se `$script:ptsLeft` ainda passar de 10k, segura o reset e tenta de novo (ate 3x) em vez de gerar +2000. Se o plano sai vazio com >10k parados, loga ALERTA + Notify.
- Gotcha do teste: `@((St 0 0 0 0))` envolve o hashtable num ARRAY, ai `$st[$k]` indexa array com string e o PowerShell tenta `[int]'Ene'` (dezenas de erros, mas o teste ainda imprimia OK). Usar `(St ...), (St ...)` direto no foreach.

Travamento de 2h no reset (2026-08-31 18:57-20:58):
- **Bug de projeto no loop de reset**: apos `$ResetRetries` (2) reenvios ele PARAVA de mandar `/resetar` e so re-avisava a cada 2 min. Ficou 2 horas repetindo "Reset nao aconteceu e nao vejo captcha" sem tentar nada. Correcoes: (1) NUNCA para de reenviar `/resetar`; (2) o log agora mostra **o que ele ve** (`level: N / ilegivel, mapa: 'x'`) — sem isso nao da pra saber se falhou o comando ou a LEITURA; (3) salva `captcha\reset_travado.png` no 3o reenvio; (4) `$ResetStuckMin = 5` — preso 5 min, `$restartCycle = $true` e re-warpa (desbuga morte/teleporte/mapa errado).
- **C e V sao TOGGLE**: `Read-Status` apertava C a cada tentativa. Se a janela abria mas o OCR falhava, a tentativa seguinte FECHAVA a janela — alternando pra sempre ("stats: nao consegui ler o status" e "inventario: nao consegui abrir a janela (tecla V)" apareciam sem parar no log). Agora tentativa PAR aperta, IMPAR le sem apertar (cobre os dois estados sem pagar OCR extra). Mesma correcao no `Inv-Free`.

"stats: nao consegui ler o status" - causa raiz achada 2026-08-31 21:25 (~25% das leituras, desde sempre):
- Descartado por medicao, nao por palpite: (1) taxa de falha por hora no rpa.log e ~20-35% ANTES e DEPOIS das mudancas de velocidade (17h, com a espera ja cortada, teve a MELHOR taxa: 14%) — nao era regressao do tickrate; (2) OCR rodado 5x sobre um `status_ultimo.png` real deu 5/5 com os 4 rotulos, 93 palavras — **o OCR e deterministico e nao erra quando a janela esta na tela**; (3) so 8 de 50 falhas caem dentro de 30s de um reset/warp — nao e o gotcha do "C ignorado apos teleporte".
- **E o FOCO**: `Read-Status` conferia `$script:gameFg` uma vez no comeco e depois apertava C. Se a janela do usuario voltasse pra frente no meio, o C ia pra ELA e o status nunca abria. Mesma causa raiz da captura que fotografou o navegador do usuario. Por isso as falhas agrupam nos horarios em que ele esta usando o PC.
- Correcoes: `Capture-Raw` confere o foco DEPOIS da foto (`$script:capOk`) e refoca 1x; `Read-Status`/`Inv-Free` descartam captura suspeita (e nunca salvam print da tela de outro programa — o `captcha\status_ultimo.png` chegou a conter o checkout do Mercado Livre do usuario, e a pasta sincroniza no OneDrive); `Read-Status` reafirma `Focus-Game` antes de CADA tecla C. Tambem: 6 tentativas, espera de 900ms de volta, e print `status_falhou.png` quando desiste.

7 melhorias implementadas 2026-08-31 22:00 (usuario pediu "faca do 1 ao 7"):
1. **Tela de login no loop de farm**: `Login-Btn($img)` exige DOIS sinais (botao play 'unknown' + texto de `$LoginWords`) e so e consultado apos **3 leituras seguidas** sem o play (`$script:semPlay`) — loading normal some em 1-2, e assim nao paga OCR da tela toda a toa nem da falso positivo com chat. `Enter-Game` extraido do `Master-Reset` e reusado nos dois lugares; so cai pra coordenada `$LoginBtn` apos 3 tentativas sem achar o texto (nao clica a esmo dentro do jogo).
2. **`$NoFocusRead`** (default `$false`): quando `$true`, `Capture-Game` LE sem trazer o jogo pra frente e `$capOk` nao exige foreground. So pra jogo sempre visivel (2o monitor). Comandos/cliques continuam exigindo foco.
3. **`$PollNearSec`/`$PollNearFrom`**: a partir de 82% do `$TargetLevel` le a cada 2s. O level subia ~150 entre leituras e os resets saiam com 364/384/400 em vez de 350 — ate 50 levels de farm jogados fora por ciclo.
4. **Watchdog do cliente**: o `while($true)` virou `while(-not $stop){ try{...} catch{...} }`. Erro "nao esta rodando" nao mata mais o bot: zera `$script:gameH`, espera o mudx voltar, `Enter-Game` (pode voltar no login) e retoma. Qualquer OUTRO erro para de verdade (`$script:stop = $true`) pra nao virar loop de erro.
5. **`estado.txt`** (`Save-Estado`/`Load-Estado`): fase + warmupCount sobrevivem a reinicio. Salvo no MR, nos botoes de fase e a cada reset de warmup. O `warmup.flag` ainda tem prioridade no start. Adicionado ao .gitignore.
6. **`Ocr-Status`**: aprende o recorte do painel (caixa dos rotulos+numeros, com folga) na primeira leitura global e depois so faz OCR desse recorte; se o recorte parar de servir, volta pro OCR global e RE-APRENDE. Funciona porque `Parse-Attrs` so compara posicoes RELATIVAS rotulo-numero.
7. **Rotacao do rpa.log** no start: >`$LogMaxMB` (5) vira `rpa_<timestamp>.log.bak`, mantendo os `$LogKeepBaks` (5) mais novos.

Rodada 2 de melhorias, 2026-08-31 22:20 (usuario: "pode implementar do 1 ao 6"):
1. **Metricas** (`Metrics`, `$MetricsEvery`=5): a cada 5 resets loga `N resets em Xh | R resets/h (1 a cada Ns) | P pontos/h | faltam N pro cap | ETA do MR ~Xh`. Sem numero nao dava pra saber se as mudancas ajudavam - era a queixa original ("MR demora muito"). `$script:ptsSent` acumula o valor de cada comando enviado.
2. **`-TestVisao`**: regressao das funcoes de LEITURA DE TELA contra prints em `fixtures\` (fora do git, ~4MB cada). Rodado como modo do proprio .ps1 (nao extrai funcao por regex como o test_stats). Cobre: Read-Map, botao do mix vs titulo, os 4 rotulos de joia, Login-Btn na tela de servidor, Inv-Open recusando inventario fechado, Find-Captcha + Solve-Captcha.
   **O teste ja pagou na primeira execucao** (ver item abaixo).
3. **`Read-Msgs`/`Log-GameMsg`** (`$MsgBox`, faixa acima do chat): o servidor responde tudo por texto e o bot ignorava. Agora as falhas de `/resetar` e `/s18` logam o que o jogo respondeu, em vez de so tirar print e adivinhar.
4. **`Tick-Msgs` + `$GoldAuto`**: le as mensagens a cada ~20s (recorte pequeno, reusa a captura que ja existe) e vai pro `/tarkan2` sozinho quando ve `Golden Tantalo`/`Invasao de Dragoes`. `$GoldAutoMin`=25min de cooldown (o evento repete a mensagem).
5. Mesmo `Tick-Msgs` dispara o mix quando ve `inventario cheio` (2o gatilho, alem da contagem de celulas).
6. **`Jit()`**: varia +-25% os intervalos (stats, inventario, mensagens). **Valores de stat seguem EXATOS** - so o ritmo varia.

**PERIGO achado pelo -TestVisao (a fixture "kanturu" era na verdade a tela de SERVIDOR):**
- A tela de selecao de servidor deste jogo tem `Server Vip Gold` (y=296), `Server Spot` (y=356), `Server Principal` (y=416), `CRIAR NOVA CONTA` (y=959), `Sair` (y=966).
- **Nenhuma casa com `$LoginWords`**, e o fallback cego `$LoginBtn = (960,940)` cai EM CIMA de "CRIAR NOVA CONTA" (y=959, centrada em x~960). O `/darmr` ou uma queda fariam o bot clicar em criar conta.
- Correcao: `$LoginServerWords` (usuario escolheu **'server vip gold'**) escolhe o botao por OCR; `$LoginDangerWords` marca telas onde NUNCA se clica coordenada chutada — nesse caso `Login-Btn` devolve `X=-1` e o `Enter-Game` avisa e espera em vez de clicar. Coberto por teste em `-TestVisao`.

Rodada 3, 2026-08-31 22:30. **PREMISSA CORRIGIDA PELO USUARIO: o objetivo e o MR (`/darmr`), NAO o reset.** Reset e so o meio de juntar pontos.
- Metricas reescritas em torno do MR: a linha agora lidera com `faltam N pontos | P pontos/h | ETA ~Xh`, e resets/h + pts/reset viram secundarios. `Master-Reset` conta os MRs, loga quanto tempo levou e **zera** `$resets`/`$ptsSent`/`$runStart` pra medir o proximo MR limpo. Resumo tambem no titulo da janelinha.
- **Como achar o `$TargetLevel` otimo**: comparar **pontos/h** (nao resets/h) entre dois valores. Resetar mais cedo da mais resets mas pode dar menos pontos por reset - so o pts/h decide. Procedimento no README.
- **Guarda de resolucao no start** (`$ClientEsperado` 1920x1009): compara com o GetClientRect real e avisa. Coordenadas ancoradas na BASE se ajustam; as fixas (InvGrid, MixNpcPos, MapLabel) nao. Isso ja custou uma noite antes.
- **Captcha nao mata mais o jogo** (`$CapKillGame = $false`): apos `$CapMaxTries` PAUSA o bot e avisa. A regra antiga nasceu quando os cliques do captcha as vezes iam pra OUTRA JANELA (bug de foco corrigido hoje), entao parte dos erros nao era do solver. `$CapKillGame = $true` volta o comportamento antigo.
- **Removida a versao Python** (`rpa_mudinhox.py`, `calibrar.py`, `config.json`, `config.example.json`, `requirements.txt`) via `git rm` - nada executavel referenciava, so o proprio README, e estao no historico do git se precisar. Removido tambem `.rpa_mon.tmp` (672KB) e adicionado ao .gitignore.
- Medicao que DESCARTOU uma sugestao minha: OCR tela inteira 88ms, Read-Level (4 variantes) 31ms, Read-Map 5ms, Read-Msgs 11ms. ~135ms por ciclo - o poll de 2s tem folga, nao ha problema de performance.
- Usuario descartou a hipotese de durabilidade de equipamento como causa do miss infinito.

Rodada 4, 2026-08-31 22:40:
- **Caca aos dragoes NAO dispara mais sozinha** (pedido do usuario): `$GoldAuto`/`$GoldAutoMin` removidos. `Tick-Msgs` so LOGA quando ve o evento no chat; ir la e decisao do botao. O gatilho de inventario cheio por mensagem continua.
- **Metricas do TAIL** (a melhoria que vale mais): numa noite medida a MEDIA do ciclo deu 756s e a MEDIANA 88s — a media mentiu por 8x. E 38% dos ciclos passaram de 120s, levando **69% do tempo total**. Entao `Metrics` agora reporta mediana do ciclo, quantos ciclos foram lentos (>1.5x a mediana) e **quanto % do tempo vazou neles**. Media esconde exatamente o que decide o ETA do MR.
- **`Wait-Map`**: espera ATE o mapa mudar em vez de dormir cravado. O overhead medido de "reset feito" ate "no spot" era 18s dos 88s do ciclo (20%), quase tudo `Start-Sleep` fixo (`Wait 8` + `$WarpWaitSec` 9s). Recupera ~12s por ciclo = ~13 min por MR.
- `$StallSec` 75 -> 40: o miss infinito disparou 5x numa noite e 75s eram gastos so PRA DETECTAR.
- Medicoes desta rodada (55 ciclos): mediana 88s, p25 75s, p75 191s, overhead reset->spot 18s.

Rodada 5, 2026-08-31 23:30:
- **BUG SERIO CORRIGIDO no `/darmr`**: `Enter-Game` devolve `$true` assim que ve o botao play — e isso tambem e verdade quando o `/darmr` foi **RECUSADO** e o personagem nunca saiu do jogo. O bot contava MR falso, logava "MASTER RESET FEITO", **zerava as metricas** e ia pro warmup em Lost Tower com os atributos cheios. Agora: (a) confirma com uma **2a leitura de status ANTES** de mandar `/darmr` (um erro de OCR disparava o comando a toa, e como a releitura repetia o erro virava loop — ja aconteceu neste projeto); (b) **depois** de entrar, rele o status: se os atributos continuam cheios, NAO conta MR, nao zera metrica, nao vai pro warmup, e salva `captcha\darmr_recusado.png`; (c) `$script:viuLogin` marca se a tela de login foi realmente vista, usado quando o status nao da pra ler.
- **`Tick-Progresso`** (`$SemProgressoMin` = 12): rede de seguranca GERAL. O travamento de 2h passou porque nada vigiava o RESULTADO — `$ResetStuckMin` cobre so o loop de reset. Sem distribuir um ponto por 12 min, avisa e reinicia o ciclo. O relogio e zerado ao sair do PAUSE (senao dispararia na hora que o usuario retoma).
- **Metricas persistidas** no `estado.txt` (formato kv: fase/warmup/resets/ptsSent/runStart/mrs/mrStart/ciclos). Medir um MR leva horas e reiniciamos o bot ~6x numa noite. `Load-Estado` ainda le o formato antigo ("fase warmup") e nao zera o que esta em memoria se o arquivo estiver corrompido. Coberto por `test_estado.ps1` (round-trip + formato antigo + arquivo corrompido).
- `$GoldSelfR` 150 -> 90: o raio escondia o Golden Tantalos quando ele chegava perto do personagem. O filtro de cor ja rejeita o laranja do fogo/asas. AINDA precisa de `-TestGold` com o mob real.
- Gotcha reencontrado: script de teste escrito FORA do projeto le `C:\...\Área de Trabalho\...` como `�?rea` (heredoc bash gera UTF-8 sem BOM, PowerShell 5.1 le como ANSI). Testes tem que morar na pasta do projeto e usar `$PSScriptRoot`.

Rodada 6, 2026-08-31 23:45 (auditoria achou 3 defeitos, 2 deles introduzidos nas rodadas anteriores):
- **`captcha\` tinha 4.9GB / 2640 PNGs** acumulados desde 28/08, e a pasta esta DENTRO do OneDrive (sincronizando tudo pra nuvem). O .gitignore tirava do git, nao do OneDrive. `$CapKeepShots` = 40, podado a cada captcha novo.
- **Watchdog de progresso disparava a toa**: `$GoldMinutes` (20) > `$SemProgressoMin` (12), e cacar/mixar nao distribui pontos — ao voltar da caca o `Tick-Progresso` via 20 min "sem progresso" e reiniciava o ciclo sem motivo. `Hunt-Golden` e `Tick-Inventory` agora zeram `$ptsLastGain` na volta.
- **`$script:ciclos` crescia sem limite**: `+=` em array PowerShell realoca a cada item (O(n^2)) e a lista inteira ia pro estado.txt a cada reset. Capado em `$CapCiclosMax` = 200.
- **`-Preflight`**: valida TODOS os subsistemas no jogo real antes de deixar rodando sozinho (privilegios, resolucao, captura, level, play, mapa, spot, captcha, 4 atributos, inventario, mensagens). Diferente do `-Check`, ele APERTA C e V, que e a parte que mais falha. Exit code 1 se algo falhar. Na 1a execucao ja mostrou o encadeamento certo: sem admin -> UIPI descarta C/V -> status e inventario falham.
- `$LogLevelDelta` = 40: com poll de 2s perto do alvo, logar `level: N` a cada tick enchia o arquivo e atrapalhava diagnostico. So loga salto >= 40 ou queda (reset).

Rodada 7, 2026-08-31 23:50:
- **Etiqueta de causa por ciclo** (`Tag-Ciclo`): a metrica do tail dizia QUANTO tempo vazava, nao ONDE. Cada ciclo agora carrega o que deu errado nele e a linha vira `40% do tempo perdido -> captcha 22%, warp 12%, stall 6%`. O excesso sobre a mediana e dividido entre as causas daquele ciclo; ciclo lento sem etiqueta vira `?`. 7 pontos de etiqueta: captcha, status, stall, warp (2x), mix, dragoes. Formato do `$script:ciclos` virou "segundos" OU "segundos:tag+tag" — `CicloSeg`/`CicloTags` aceitam os dois (o estado.txt antigo so tinha numeros).
- **ESC antes de andar no miss infinito**: `Check-Progress` so pausava/andava/despausava. Se o que travou foi uma janela aberta por acidente, andar nao resolve — `Close-Popup` resolve. Uma linha.
- **`Podar-Shots` tambem no start**: a poda so rodava quando um captcha aparecia; sem captcha, os 4.9GB ficavam la. Agora tambem no boot, e loga quantos MB liberou.
- **Preflight no start do bot** (`Run-Preflight $false`, sem checar spot porque o bot ainda vai warpar): 10s conferindo tudo evita a noite perdida por algo obvio. NAO bloqueia, so avisa. O `-Preflight` manual continua checando o spot tambem.
- `test_ciclos.ps1`: mediana ignorando etiquetas, divisao da culpa, ciclo sem etiqueta virando '?', Tag-Ciclo sem duplicata, formato antigo.

Rodada 8, 2026-09-01 01:00 - achados da analise do log do dia (2187 linhas, 10:06->23:51):
- **O bot nao rodou desde 21:40 de 31/08.** Ultima atividade real de farm 21:38. Tudo depois sao testes. Ou seja: correcoes de foco, /darmr, watchdog, metricas, preflight e etiquetas de ciclo **nunca executaram contra o jogo**.
- **Detector de dragoes = falso positivo, provado**: das 26 deteccoes, **21 na mesma coluna x=655** ((655,503) 10x, (655,269) 8x, (655,243) 3x), 561-615px cada. Mob se move e morre; mesmo pixel 21 vezes e cenario. Correcao `$GoldRepetMax`=4: conta deteccoes por coordenada, para e avisa. Vale mesmo com `$GoldPix` errado (auto-validante).
- **Nunca saiu um comando de stat <1000 em 2187 linhas.** O caminho que FECHA o cap exato (`/f 767`) nunca rodou — e o /darmr inteiro depende dele. Criado `-TestStatMin`: le status, manda `/f 300`, rele e compara. NAO RODOU AINDA (UAC pendente).
- **Custo real do bug de deadlock, medido no log**: `77936 pontos | etapa 30000 | F=29856 A=30000 V=30000 E=30000 -> nada a distribuir`. Forca precisava de **144** pontos e isso congelou **77936**. Depois da correcao das etapas: ocorrencias de "nada a distribuir" cairam de 132 (mediana 576 parados) pra 6 (mediana 496).
- **`$StatMinCmd` dividido**: `$StatMinCmd` (1000) vale so pro `/a`, que tem perigo REAL documentado (teleporta pra AIDA). `$StatMinOutros` (1000, a baixar) vale pra /f /v /e, onde o piso era so precaucao nunca testada. Teste 6b no test_stats cobre: com `$StatMinOutros=1` o /f aceita 500 e o /a continua recusando.
- NAO usar a comparacao "18% de falha de status antes vs 74% depois": a janela pos-21h tem 19 minutos, rodando codigo ANTERIOR as correcoes, e justo enquanto o usuario usava o PC. Mede o problema, nao a solucao. Continua sem baseline limpa.

Rodada 9, 2026-09-01 02:15:
- **Auto-tune do `$TargetLevel`** (`$AutoTune`, `$AutoTuneAlvos` = 350,320, `$AutoTuneResets` = 15): o bot roda o A/B sozinho, compara **pontos/h** (nao resets/h) e fica com o melhor. Resultado persiste no estado.txt (`alvo`, `tuneOn`), entao nao refaz o experimento a cada restart. Se o servidor exigir level minimo pra resetar, o alvo baixo rende pouco e perde sozinho.
- `$UiLogMaxChars` = 60000: o TextBox da janelinha crescia sem limite.
- **Auditoria de vazamento de recurso: NEGATIVA.** `Ocr-Bitmap` nao descarta MemoryStream/InMemoryRandomAccessStream/DataWriter/SoftwareBitmap, mas medido: apos 50 OCRs + GC retem **2MB e 1 handle**. A versao "corrigida" com Dispose ficou PIOR (pico 735MB contra 175MB) por causa do copy de buffer. Nao mexer.
- **Dois defeitos meus achados pelo preflight rodando de verdade (02:10)**: (a) `Ocr-Status` aprendia recorte de **1378x775** (72% da tela) porque incluia "qualquer numero" na caixa — pegava numeros do HUD/chat. Agora so os ROTULOS definem a caixa, +300px a direita pro numero, e recusa candidato > 45% da largura; (b) o preflight dizia OK com `Pts=-1` — agora pontos e uma verificacao separada.
- **CORRECAO DE UMA AFIRMACAO MINHA**: eu disse que sem comandos <1000 o cap 32767 poderia ser inalcancavel e o /darmr nunca sairia. **Errado** — os logs mostram `TODOS no maximo, /darmr` **4 vezes**. O cap e alcancavel porque o valor enviado e exatamente `faltaCap` sempre que ele e >= 1000, e as etapas terminam batendo em 32767 (30000 + 2767). O caso <1000 so aparece se o atributo ficar entre 31768 e 32766 por estado anterior. `-TestStatMin` continua util, mas NAO e critico.
- Monitor do log: quando o bot rotaciona o rpa.log o contador de linhas do monitor via `m < n` e reprisava o arquivo inteiro. Corrigido pra `n = m`.
- **A guarda de coordenada repetida NAO bastava** (visto ao vivo 02:13-02:14 com o usuario rodando a caca): em Tarkan o CHAO e dourado, e o detector achou "mob" em 20 varreduras SEGUIDAS, **cada uma num lugar diferente** (603,269 / 447,607 / 1825,815 / 1461,373 ...), 439-664px cada. `$GoldRepetMax` so pega falso positivo ESTATICO. Adicionado `$GoldMaxSeguidas` = 10: alvo em N varreduras seguidas = cenario, porque Golden Tantalos e raro ("restam 9 no mapa inteiro") e some da tela entre varreduras. Varredura limpa zera o contador.
- **A caca aos dragoes NAO FUNCIONA ate `$GoldPix` ser calibrado com `-TestGold` num mob real.** As duas guardas so evitam desperdicio; nao substituem a calibracao.
- **Alvo da caca mudou pra LORENCIA (usuario, 2026-09-01)**: sao dois bichos diferentes e o chat do jogo anuncia os dois — `Golden Dragon vivo(s) em Lorencia` e `Golden Tantalo vivo(s) em Tarkan`. O alvo e o **Golden Dragon, em Lorencia**. `$GoldCmd` = `/lorencia`, `$GoldMap` = `lore`.
- Consequencia: **Lorencia e CIDADE**, e clicar no play la abre "precisa estar fora da cidade" (gotcha ja documentado). `$GoldHelper` = `$false`: sem MU Helper, quem ataca e o proprio clique no mob (1o clique leva ate ele, 2o ataca, e o loop reclica a cada varredura).

Rodada 10, 2026-09-01 02:25 - prints do usuario destravaram mix e caca:
- **MIX TRAVAVA porque falta(va) um PASSO**: clicar na joia verde abre um SEGUNDO dialogo (`Mixar 16 Jewel of Life` / `Deseja continuar?` com **CONFIRMAR** e CANCELAR). O bot clicava na joia e ficava parado nesse dialogo. Agora acha `$MixConfirmWords` (`^confirmar$`, nunca CANCELAR) por OCR e clica; se nao achar, salva `mix_sem_confirmar.png`, avisa e para.
- **A lista tem 7 opcoes**, nao 4: Jewel of Soul, Life, Creation, Chaos, Fragment of Death, Stone of God, Jewel of God (x~960, y de 416 a 698 na area cliente, passo ~47px). Verde = disponivel, vermelho = nao.
- **`Word-Color` nunca via verde**: os botoes sao verde/vermelho ESCUROS (~(45,85,45) e ~(90,40,40)) e o limiar exigia canal > 110 -> os dois davam 'other' e nenhuma joia era considerada disponivel. Trocado por comparacao RELATIVA entre canais (G > R+18 etc), com piso so pra ignorar quase-preto. Coberto por teste sintetico no `-TestVisao` (nao precisa de fixture do jogo).
- **Caca calibrada pelo print do Golden Derkon** (Lorencia): `$GoldPix = @{RMin=200; GMin=90; BMax=90; RmB=110; RmG=145}`. O filtro antigo (GMin=140, RmG=75) rejeitava as partes mais saturadas do dragao e aceitava areia clara. `BMax` baixo e o que separa dourado de areia/pedra/grama.
- **`$GoldBlobMin` 30 -> 250**: 30 era 4% do bloco de 26x26 (676px), permissivo demais.
- **`$GoldSelfR` -> 300**: as ASAS FLAMEJANTES do personagem sao (255,131,15) e o icone VIP e dourado - tao saturados quanto o dragao. **Cor nao separa, so distancia.** Verificado empiricamente: com 220 ainda detectava a asa (915,269); com 300 a tela sem dragao nao acusa nada.
- O botao "DRAGOES DOURADOS" era DarkGoldenrod (184,134,11) e **o proprio `-TestGold` detectava o botao como dragao** (o modo de teste roda em processo separado e nao mascara a UI). Botao virou Teal, e `RMin` subiu pra 200 pra rejeitar ouro fosco.
- Bug de escape: `"\$Var"` NAO escapa em PowerShell (sai `\` + valor). O certo e crase: `` "`$Var" ``. Corrigido em 5 mensagens.
- **Um `sed` meu injetou um `X` literal no script e derrubou o bot as 02:18** (`O termo "X" nao e reconhecido...`). Cuidado com `s|...|X|` como no-op em sed.
- **`Ocr-Status` com "recorte aprendido" REMOVIDO** (2026-09-01 02:32), por medicao e nao por gosto: OCR da tela inteira custa 88ms, o recorte ~30ms, e isso roda UMA vez a cada 15s = 0.4% de um core. Nao pagava a complexidade; aprendia caixa errada (1378x775, 72% da tela, na 1a versao) e, quando o recorte envelhecia, custava um OCR A MAIS (recorte falho + global). Em 214 leituras, aprendeu 2x e falhou 1x. Fui eu que construi isso na "rodada de 6 melhorias" ja classificando como "ganho de velocidade, nao de correcao" — com o numero na mao, a decisao certa foi apagar.

**CAUSA RAIZ do "stats: nao consegui ler o status" (2026-09-01 02:35) - achada pelo print que o proprio bot salvou:**
- `Chat-Open` checava DUAS LINHAS EXATAS (`Y1FromBottom=111`, `Y2FromBottom=87`). Medido no `captcha\status_falhou.png`: nessas duas linhas havia **0 pixels vermelhos**; as bordas reais estavam em **117-118 e 92-93**. A caixa desceu ~6px (layout com o campo "Whisper").
- Cadeia: `Chat-Open` sempre dizia "fechada" -> `Close-Chat` nunca fechava -> o `C` do `Read-Status` era digitado como **LETRA dentro do chat** -> a janela de status nunca abria. Explica a falha de ~25% que perseguiu a sessao inteira, e as 6 tentativas seguidas falhando.
- Correcao: `Chat-Open` varre a FAIXA `YFromBottomMin=80..YFromBottomMax=130` (passo 4 em x, a borda e linha continua) e exige **2 linhas vermelhas** (topo e base). Tolera o deslocamento.
- Fixture `chat_ABERTO.png` + 2 testes no `-TestVisao`: detecta a caixa aberta, e nao inventa caixa na tela de servidor.
- **Licao**: coordenada de UI fixa neste jogo quebra. Ja aconteceu com o level/chat (mudanca de resolucao), com o painel de status (janela deslocada) e agora com a caixa de chat. Onde der, usar FAIXA + confirmacao, nao pixel exato.

**LEVEL MINIMO PRA RESETAR = 350, confirmado pela MENSAGEM DO SERVIDOR (2026-09-01 03:04):**
- O `Log-GameMsg` (lido na faixa `$MsgBox`) capturou em texto: **"Você precisa de estar no level 350 para resetar!"**. Isso encerra a duvida sobre `$TargetLevel`, que era chute desde o inicio do projeto — nao e mais inferencia por contagem de reenvios, e o proprio jogo dizendo.
- Consequencia: o braco de 320 do auto-tune testava valor IMPOSSIVEL. O `/resetar` era recusado e so virava reenvio ate o char passar de 350 sozinho. E o `204560 pontos/h` que eu citei como "320 esta ganhando" era o numero CUMULATIVO da sessao, nao o do braco - leitura minha errada.
- Correcoes: `$LevelMinReset` (350) e piso, `$AutoTuneAlvos` virou `350, 380` (testar pra CIMA, nao pra baixo), e o alvo do auto-tune e sempre `Max(alvo, $LevelMinReset)`.
- **O bot APRENDE o piso sozinho**: se a mensagem casar com `level (\d+) para resetar`, ele sobe `$TargetLevel`, grava `minReset` no estado.txt e descarta o braco invalido do auto-tune. Se o servidor mudar a regra, o bot se ajusta sem ninguem editar config.
- Outra mensagem capturada: "voce esta no nivel maximo" (level 400 = teto do servidor).
- Validacao do `Chat-Open` em 2a amostra independente (print de 03:06:04): logica velha 0 vermelhos nas linhas 111/87 -> diz FECHADA; logica nova acha bordas em 118,117,93,92 -> diz ABERTA. Fixture `chat_ABERTO_2.png` no `-TestVisao`.

Rodada 11, 2026-09-01 09:10 — "garantir que o bot nao fique parado":
- **CAUSA DA PARADA DE 6 HORAS (03:27 -> 09:09, zero linha de log)**: quando o UAC e recusado, `Start-Process -Verb RunAs` lanca e o `catch` abria um **MessageBox**. Como o processo roda com `-WindowStyle Hidden`, o dialogo fica invisivel e o processo **trava nele pra sempre** — parecendo VIVO pra quem so olha a lista de processos. Agora loga + toast (nao bloqueia) e SAI. Nunca usar MessageBox em processo oculto.
- **Heartbeat** (`heartbeat.txt`, batido a cada volta do poll) + guarda de instancia unica: o bot recusa subir se achar heartbeat fresco (`$HeartbeatVivoSec`=180), entao watchdog e launcher nao criam dois bots brigando pelo teclado.
- **`watchdog.ps1` + `instalar-watchdog.cmd`**: Tarefa Agendada a cada 3 min com `/RL HIGHEST`. Rodando elevada, ela relanca o bot **SEM PROMPT DE UAC** — que e o unico jeito de resolver "UAC nao aceito" sem alguem na frente do PC. Respeita `stop.flag` (parada intencional) e nao faz nada se o `mudx.exe` estiver fechado. Testado nos 3 cenarios: stop.flag presente (nao mexe), heartbeat fresco (nao mexe), heartbeat velho (mata a instancia travada e relanca; validado: 1 instancia, estado retomado).
- **Auto-reinicio interno** (`$SemProgressoMax`=3): apos 3 disparos seguidos do `Tick-Progresso`, o bot reinicia O PROPRIO PROCESSO. Como ele ja e elevado, o filho nasce elevado sem UAC — e ainda recarrega o script do disco, entao correcao nova entra sozinha. `Unstick-Tudo` (ESC + fechar chat) roda antes, cobrindo a classe do chat aberto que travou tudo em 01/09.
- **A janelinha do bot cobria a GRADE DO INVENTARIO** (visto como retangulo preto no `inventario_falhou.png`): `Capture-Raw` mascara a UI de preto, entao ela cegava a leitura. Mesma classe do bug do minimapa. `Fugir-Da-Area`/`Unblock-Areas` generaliza a fuga, e a posicao padrao da janela foi pro **canto inferior esquerdo** — unico canto que nao cobre play(topo-esq), minimapa(topo-dir), inventario(dir) nem chat/level(centro-baixo).
- **Metricas contavam DOWNTIME como tempo produtivo**: `$runStart` e persistido, entao apos a parada de 6h o `pontos/h` caiu pra 19527 (contra 147116 reais) e o ETA do MR inflou pra 5.2h. Corrigido com `$script:ativoSeg`: o `Bater-Heartbeat` (1x por volta do poll) acumula o delta entre voltas e IGNORA buracos maiores que `$AtivoGapMax` (120s) — buraco grande = bot estava parado. `Metrics` e o auto-tune passam a dividir por tempo ATIVO. O auto-tune tinha o mesmo defeito: travar no meio de um braco penalizava aquele alvo injustamente e podia decidir o A/B errado. `ativoSeg` persiste no estado.txt e zera no MR. Coberto no `test_estado.ps1`.
- **MASTER RESET #1 saiu**: `== MASTER RESET #1 FEITO (levou 0.33h, 4 resets) ==` as 02:30:04, ja com a validacao nova (rele o status depois de entrar e confirma que os atributos zeraram, pra nao contar MR falso).
- **A tecla V NAO abre o inventario neste cliente.** Com a janela do bot ja fora do caminho (retangulo preto sumiu do print), a area continua mostrando o mapa. O cliente do MudinhoX tem menu proprio (Shop/Inventario/Personagem/Guild...), entao o atalho e outro. `$InvKey` esta esperando o valor certo — NAO sair testando teclas, hotkey errada dispara habilidade.
- **Gotcha de analise**: o `rpa.log` nao tem data, so hora, e mistura dias. Um `grep '^\[09:2'` pega ontem E hoje. Usar `tail` ou os `.bak` datados.

Rodada 12, 2026-09-01 09:45 — **MODO JOIAS** (pedido do usuario):
- `$script:modo` = `'reset'` (ciclo normal) ou `'joias'`. O botao MIXAR JOIAS virou ALTERNADOR de modo (texto/cor mudam), e o botao "Normal /s18" tambem sai do modo joias. Persiste no estado.txt.
- `Ciclo-Joias`: warp `$WarpCmd` -> helper -> farma ate encher -> `Mix-Jewels` -> repete. **Sem `/resetar` e sem `/darmr`** (o `Distribute-Points` bloqueia o darmr quando modo=joias, mas SEGUE distribuindo pontos, que continuam vindo do level).
- Deteccao de "cheio": (1) mensagem do jogo (`$MsgInvWords` liga `$mixNow`), (2) contagem de celulas — **so a cada `$InvCheckSec`**, nao a cada leitura (abrir/fechar o inventario a cada poll de 6s seria absurdo; corrigi isso antes de commitar), (3) fallback por tempo `$JoiasFarmMax` (25 min), necessario porque a tecla do inventario ainda esta errada.
- **Print antes de cada mix** (`captcha\mix_<timestamp>_<Joia>.png`), igual ao captcha: fica o registro de qual opcao estava verde e onde o bot clicou. Pedido explicito do usuario pra poder validar.
- `test_estado.ps1` cobre o modo: round-trip nos dois valores e arquivo sem o campo (mantem o da memoria, nao vira lixo).
- **MODO DRAGOES** (mesmo desenho do modo joias, pedido do usuario): `$script:modo = 'dragoes'`. `Hunt-Golden` virou `Ciclo-Dragoes` — roda ate o usuario desligar, **sem inventario, sem atributos, sem reset e sem /darmr**. `$GoldMinutes` e `$script:goldNow` removidos (o modo nao tem mais prazo). O botao virou alternador; "Normal /s18" tambem sai. Os dois guardas de falso positivo agora **saem do modo** (`modo='reset'` + Save-Estado) em vez de so dar `break`: com o detector provado errado, voltar a cacar cenario no ciclo seguinte seria burrice.
- `$ptsLastGain` e atualizado a cada volta dos dois modos novos: cacar/mixar nao distribui pontos, e sem isso o `Tick-Progresso` (12 min) dispararia sozinho e reiniciaria o bot no meio do ciclo.
- Removida a guarda de resolucao que rodava no "iniciando": ela media a janela ANTES do jogo estar pronto e leu `0x0`, disparando AVISO + toast falso — e um segundo depois o preflight media certo. Era duplicata do check que o `Run-Preflight` ja faz. `$ClientEsperado` continua vivo, so no preflight.
- **Inventario pelo MENU** (alternativa a tecla, que neste cliente nao abre): o print do usuario mostrou que o menu do jogo (botao de 3 barras, topo direito ~1888,23 na area cliente) tem um item **"Inventario"** junto de Shop/Personagem/Guild/Mercado. `Abrir-Inv-PeloMenu` clica no menu, **CONFIRMA por OCR** que ele abriu (`$InvMenuAncora` casa com alguma das palavras conhecidas) e so entao clica no item (`$InvMenuWords`). Se nao confirmar, da ESC e desiste — nunca clica no escuro. Roda como fallback dentro do `Inv-Free`, depois das 4 tentativas de tecla. Isso destrava o gatilho de "inventario cheio" sem depender do usuario descobrir a tecla.

Rodada 13, 2026-09-01 10:25 — 1o MIX REAL funcionou, e revelou 2 bugs:
- **Sequencia completa validada no log**: `/mixer` -> `NPC confirmado (805,240) OCR leu 'Lahap'` -> `clicando 'Mixar' em (942,535)` (o BOTAO, nao o titulo) -> `Soul verde` -> `confirmando em (900,510)` -> volta pro farm. Todas as correcoes da sessao aparecem nessa sequencia.
- **BUG 1: mixava so a PRIMEIRA opcao.** Confirmar um mix **FECHA o modal**; a volta seguinte varria uma tela sem lista, nao achava verde e o bot concluia "acabou". No print de validacao havia **4 verdes** (Soul, Life, Creation, Chaos) e ele mixou 1. Correcao: `Lista-Mix-Aberta` detecta se a lista esta na tela e `Abrir-Modal-Mix` reabre (NPC -> botao) a cada volta. `$MixRounds` 8 -> 12.
- **BUG 2 (achado pelo teste de regressao, nao pelo log): o CURSOR do mouse aparece na captura e apaga a palavra debaixo dele.** No print, o ponteiro estava sobre 'Jewel of Chaos' e o OCR nao leu a palavra — o bot nunca saberia que aquela opcao estava verde. E sistematico: depois de clicar, o cursor fica sempre sobre a lista. `Tirar-Cursor` leva o mouse pra `$CursorParkX/Y` antes de cada leitura da lista.
- Fixture `mix_lista_4verdes.png` + 3 testes no `-TestVisao` (lista detectada, verdes reconhecidas, Fragment of Death nao confundido com verde). O teste espera >=3 verdes E DOCUMENTA por que: neste print especifico o cursor esconde a quarta.
- **Menu do inventario: o clicavel e o ICONE, nao o rotulo.** A rota pelo menu abriu certo (achou e clicou em 'Inventário' em 1616,204 — a coordenada `$InvMenuBtn` 1888,23 estava certa), mas o inventario nao abriu: no print de 10:35:50 a tela seguia no Stadium. Cada item do menu e um icone com o rotulo EMBAIXO — mesmo padrao do Lahap, invertido. `$InvMenuClickDy = -45` clica acima do texto, e a espera subiu pra 2.5s.
- **"pontos ilegiveis" NAO era erro de OCR: o jogo OMITE a linha quando nao ha pontos.** Dump completo do OCR do `status_ultimo.png` mostra o painel (na ESQUERDA, x 55-210) com `Forca : 19880`, `Agilidade: 15000`, `Vitalidade: 10552`, `Energia: 27000` — e **nenhuma linha "Pontos"**. Todas as leituras bem-sucedidas tinham Pts > 0 (4544, 2048, 1712); as "falhas" davam -1. Logo `Pts=-1` significa **zero a distribuir**. Mensagem trocada pra "sem linha de Pontos (0 a distribuir)" e o preflight parou de contar isso como FALHA (so reporta o valor). O comportamento ja estava certo (nao distribui quando nao ha o que distribuir) — o que estava errado era o diagnostico.
- De passagem: o painel de status fica na ESQUERDA, o que confirma que o "recorte aprendido (51,63 490x373)" estava certo. A remocao daquela feature seguiu justificada por custo/beneficio, nao por estar errada.

**O INVENTARIO NAO TEM POSICAO FIXA (2026-09-01 10:50) — descoberta que invalidou a calibracao antiga:**
- O print de falha mostrou o painel **ABERTO**, mas na ESQUERDA da tela. A grade estava em **(607,333)**, nao nos **(1317,408)** que eu calibrei com 64/64 acerto. A celula de **34.4px** bate nos dois. Ou seja: o painel abre em lugares diferentes, e QUALQUER coordenada fixa pra ele esta errada metade do tempo.
- Correcao: `Achar-InvGrid` localiza a grade **ancorada no TITULO da janela** ("Inventário", achado por OCR) com `$InvGridDx = -133` (do centro do titulo ate a borda esquerda da 1a celula) e `$InvGridDy = 296`. `$InvGrid` fixo foi REMOVIDO.
- Bonus: achar o titulo tambem prova que o painel esta aberto — `Inv-Open` virou uma linha e nao depende mais de cacar a palavra "Zen" (pequena, vermelha, que o OCR quase nunca lia; era a causa do `OCR leu: ''`).
- Fixture `inventario_ABERTO_esquerda.png` + 3 testes: acha a grade fora do lugar antigo, cai em (607,333) e ve o inventario cheio como cheio.
- A rota pelo menu tambem foi confirmada funcionando ate o fim (o print e DELA): `$InvMenuBtn` (1888,23) certo, item achado por OCR, e `$InvMenuClickDy = -45` pra clicar no icone e nao no rotulo.
- **A CONTAGEM DE CELULAS DO INVENTARIO NAO E CONFIAVEL** (2026-09-01 11:22): a ancora (titulo, por OCR) OSCILA — vista ao vivo em (652,314) e (689,300) com 8s de diferenca, **37px**, mais que uma celula de 34.4px. Medido no fixture: o MESMO inventario cheio le **0 livres** alinhado e **26 livres** 20px fora. Era isso que fazia o bot dizer "17 celulas livres" com o inventario cheio.
- **Tentativa de refino que NAO funcionou** (registrada pra ninguem repetir): escolher o deslocamento que deixa as celulas mais "decisivas" (bem cheias ou bem vazias). Num inventario CHEIO toda celula tem item, entao grade torta pontua igual — o teste mostrou a heuristica escolhendo (625,351) e lendo 44 livres num inventario cheio. Revertido.
- Decisao: a contagem virou **informativa** e so CONFIRMA cheio; nunca serve pra dizer "ainda tem espaco" e adiar o mix. O gatilho principal passou a ser o **teto de tempo** (`$JoiasFarmMax` 25 -> 8 min) mais a mensagem do jogo — nenhum dos dois depende de alinhamento.
- **Modo joias no level MAXIMO**: sem reset, o level fica cravado em 400 e o detector de miss infinito disparava a cada 40s pausando o farm a toa. `$LevelMaximo` desliga o stall-por-level la em cima.
- **Dialogo de confirmacao demora um tempo VARIAVEL pra aparecer** (2026-09-01 12:56): o bot leu a tela UMA vez 1.5s apos clicar na joia, nao achou CONFIRMAR e desistiu — mas o print de diagnostico, tirado 1s depois, mostrava o dialogo na tela. Trocado por busca repetida (`$MixConfirmTentativas` = 5, 1s cada). Licao: em UI de jogo, procurar ate achar, nunca olhar uma vez.
- Fixture `mix_dialogo_confirmar.png` + 3 testes: acha CONFIRMAR, nao confunde com CANCELAR, e a lista nao e dada como aberta nessa tela (senao nao reabriria o modal).

## 2026-09-01 - contagem de celulas DELETADA do loop; metrica do modo joias

- **`Tick-Inventory` nao conta mais celulas.** Consequencia direta do achado de 11:22 (a ancora oscila 37px, e o
  MESMO inventario cheio le 0 ou 26 livres): a contagem abria e fechava o inventario a cada 2 min (dois cliques,
  foco roubado do usuario) pra produzir um numero que a gente **ja tinha decidido nao usar** pra adiar o mix.
  Sobraram os gatilhos que nao dependem de alinhamento:
  1. mensagem do proprio jogo (`$MsgInvWords` liga `$script:mixNow`) — vale nos dois modos;
  2. botao **MIXAR JOIAS**;
  3. teto de tempo `$JoiasFarmMax` (25 min) — **so no modo joias**.
  No ciclo de reset/MR nao ha teto de tempo, e de proposito: inventario cheio nao impede resetar, e o objetivo
  la e o `/darmr`. `Inv-Free` e `Achar-InvGrid` continuam existindo pro `-Preflight` e `-TestInv`, onde o numero
  e informativo e um humano esta olhando. `$InvCheckSec` foi removido do CONFIG (nao tinha mais leitor).
- **Metrica do modo joias: `joias/h`.** As metricas antigas (`pontos/h`, ETA do MR) sao todas do master reset e
  nao dizem nada num modo que nao reseta. Ao fim de cada ciclo o bot loga
  `== JOIAS: 12 mixadas em 3 ciclos | 4,1 joias/h | farm de 25 min por ciclo ==` e poe o mesmo resumo no titulo
  da janelinha. E o numero que responde a unica pergunta aberta do modo: **`$JoiasFarmMax` (25 min) esta bom?**
  Se joias/h cair ao aumentar o farm, o inventario ja estava cheio antes do teto.
  `$joiasMix`/`$joiasCiclos` entram no `estado.txt` (com regressao no `test_estado.ps1`), senao um restart do
  watchdog zeraria a medicao — foi exatamente o que aconteceu com as metricas do MR antes.
- **Contagem so conta se o jogo confirmar.** Cada mix so incrementa `$joiasMix` depois que a mensagem do jogo
  bate em `$MixSucessoWords`; clicar em CONFIRMAR e o jogo recusar (sem jóias suficientes, por exemplo) agora
  aparece no log como "cliquei em CONFIRMAR mas o jogo nao avisou sucesso" em vez de virar mix contabilizado.
- **`Achar-Ate` generico.** Tres lugares repetiam o mesmo laco "tira o cursor, captura, procura o texto, tenta de
  novo": menu do mix, icone do inventario e o botao CONFIRMAR. Viraram um helper so. O padrao ja tinha custado
  bug antes (uma leitura unica falha porque o dialogo aparece com atraso variavel) — agora e um lugar so.

## 2026-09-01 13:25 - o `X` solto matou o bot DE NOVO (agora tem lint)

- Crash: `ERRO: O termo 'X' nao e reconhecido como nome de cmdlet...`, logo depois de
  `nao teleportou pro spot certo (mapa: 'lorencia', esperado 'stad'), tentativa 1/4`.
- Causa: a linha 985 do `Warp-To-Spot` estava assim — so o `X` e o comentario orfao:
  ```
  X   # le a resposta do servidor e fotografa na PRIMEIRA falha (a mensagem some rapido)
  ```
  O codigo real (`if($t -eq 1){ $null = Log-GameMsg $null "apos $cmd"; $null = Save-Shot 'warp_falhou.png' }`)
  tinha sido destruido por um `sed` meu; restaurei do commit `a004d75`.
- **Por que passou por todos os testes:** o PowerShell so descobre que um comando nao existe **quando executa
  aquela linha**. O parser aceita `X` (e um nome de comando valido, so nao existe). E a linha so roda no ramo
  raro "teleportou pro mapa errado". `-TestVisao`, `test_stats`, `test_estado`, `test_ciclos` e a checagem de
  sintaxe passaram todos com o bug dentro. Foi a **segunda** vez (a primeira as 02:18 do mesmo dia).
- **Correcao do bug CLASSE, nao do sintoma:** `test_lint.ps1` percorre a AST de `mudinhox_rpa.ps1` e
  `watchdog.ps1` e cobra que todo nome de comando literal exista (funcao do proprio arquivo, cmdlet, alias ou
  executavel). Roda em ~1s. Verifiquei que ele PEGA o bug: injetei `X` de volta, o lint acusou
  `COMANDO INEXISTENTE ... linha 986: 'X'`, restaurei e voltou a passar. Rodar sempre antes de deixar a noite.
- Licao ja conhecida, agora com ferramenta: **`sed` com regex frouxa em cima deste arquivo e perigoso.** Se o
  padrao nao casar exatamente, ele apaga o que nao devia e o estrago fica num ramo que so roda de madrugada.
- **Bot PAUSADO parecia morto pro watchdog** (achado no mesmo log): `Pause-Gate` nao batia o heartbeat, entao
  depois de 180s pausado o watchdog mataria o processo e relancaria — **desfazendo a pausa que voce pediu** pra
  mixar no NPC. Agora o laco de pausa escreve o `heartbeat.txt` a cada ~5s. Escreve DIRETO no arquivo em vez de
  chamar `Bater-Heartbeat`, porque aquela funcao tambem acumula TEMPO ATIVO e tempo parado no NPC nao pode
  entrar no `pontos/h`; ao retomar, `$tickLast` e zerado pelo mesmo motivo. (Como o watchdog ainda nao esta
  instalado, isso nunca chegou a acontecer de verdade — mas aconteceria na primeira pausa depois de instalar.)

## 2026-09-01 - o que o log de 4883 linhas disse (numeros, nao palpites)

Contagens sobre a sessao inteira do `rpa.log`:

| sintoma | ocorrencias | o que era |
|---|---|---|
| `stats: nao consegui ler o status` | 100 de 1064 leituras (9,4%) | ver abaixo — deixava a janela ABERTA |
| `sem linha de Pontos (0 a distribuir)` | 84 | leitura de status sem motivo (level parado) |
| `reset nao aconteceu ... reenviando` | 83 de 179 `/resetar` | o 1o comando some; o REENVIO funciona quase sempre |
| `nao teleportou pro spot certo` | 27 (16 saindo de `lorencia`) | sempre logo depois de um mix |
| `ERRO: O termo 'X' nao e reconhecido` | 4 (02:18, 11:57, 13:05, 13:25) | a linha destruida do `Warp-To-Spot` |

- **O `X` matou o bot 4 vezes, nao 2** — e sempre no mesmo ponto: o retorno do mixer pro `/s18`, porque o warp
  saindo de Lorencia falha na 1a tentativa e e exatamente esse o ramo que continha o `X`. Corrigido + `test_lint.ps1`.
- **`Read-Status` deixava a janela de status ABERTA ao desistir.** A alternancia aperta C nas tentativas 0, 2 e 4
  — tres vezes, numero impar, janela aberta — e o bot seguia achando que estava fechada. E o `/resetar` seguinte
  era digitado com o painel por cima. Bate com os 83 `/resetar` perdidos, quase sempre logo apos uma leitura de
  status. Agora, ao falhar, ele CONFERE (captura + `Status-Open`) e so aperta C se estiver mesmo aberta — apertar
  no escuro seria pior, porque se o C nunca chegou o aperto ABRIRIA a janela.
- **`$ResetWaitSec` 15 -> 8.** Como o reenvio quase sempre resolve na hora, esperar 15s por 83 vezes jogou uns
  20 min fora. Nao ha risco em reenviar cedo: um `/resetar` a mais e recusado pelo proprio jogo.
- **`Tick-Stats` so rele o status quando ha MOTIVO.** Ponto so vem de subir de level; com o level parado a
  releitura so custa foco. Regra: rele se o level mudou desde a ultima leitura, ou se estourou `$StatMaxSec`
  (90s — o teto existe porque o level as vezes sai ilegivel do OCR e nao da pra confiar so nele). Regressao no
  `test_ciclos.ps1`, verificada quebrando a condicao de proposito (5 falhas).
- **`Tick-Stats` saiu do modo joias.** Era o que voce tinha pedido ("nao envolve checkar inventario, checar
  atributos, resetar nem darmr") e o log mostrava o custo: leituras a cada 15s logando "0 a distribuir" enquanto
  o `/darmr` esta bloqueado nesse modo. Os pontos acumulados sao gastos assim que voltar pro modo normal.
- **Ainda sem explicacao: o warp saindo de Lorencia falha na 1a tentativa.** A linha que lia a resposta do
  servidor era justamente a que o `X` tinha destruido — por isso nunca houve diagnostico. Restaurada; o proximo
  `nao teleportou` ja loga o `jogo diz (apos /s18): ...`.

## 2026-09-01 - o auto-tune nunca terminou (e por que)

- No log: `[02:53:42] autotune: alvo 350 rendeu 160794 pontos/h em 15 resets` seguido de
  `autotune: testando agora alvo 320 por 15 resets` — e **nunca** um `autotune: FIM`. Onze horas depois o
  `estado.txt` estava em `alvo=350 tuneOn=1`, ou seja, de volta ao **primeiro** braco.
- Causa: `$tuneArm/$tuneResets/$tunePts/$tuneAtivo0/$tuneRes` nao iam pro `estado.txt`. Cada restart zerava o
  contador do braco. Com 15 resets por braco e o bot caindo de tempos em tempos (4 quedas pelo `X` + 6h de
  outage no mesmo dia), **o A/B era matematicamente incapaz de fechar**. O resultado pratico: o `$TargetLevel`
  ficava parado no braco em teste, sem nunca comparar nada.
- Corrigido: os cinco campos entram no `estado.txt` (`tuneRes` serializado como `350:160794|380:171000`), e o
  bot grava NA HORA que um braco fecha, em vez de so no fim do experimento. Regressao no `test_estado.ps1`.
- **Bug de tabela achado ao escrever o teste:** `$null | % { $_[0] }` roda o bloco UMA vez com `$_` nulo e
  `$null[0]` lanca "Cannot index into a null array". Como o `Save-Estado` inteiro e um `try{}catch{}`, isso
  fazia o **estado.txt nao ser escrito** — silenciosamente. Ficou `@(@($x) | ? { $_ } | % { ... })`.
- **O bot agora instala o watchdog sozinho** (`Garantir-Watchdog`, `$AutoWatchdog`). Ele ja roda elevado, entao
  `schtasks /create ... /rl HIGHEST` funciona sem UAC extra. O `instalar-watchdog.cmd` dependia de voce lembrar
  de rodar como admin — nao foi rodado (`schtasks /query` confirma: tarefa inexistente), e o preco foi 6h de
  silencio no log e quatro quedas sem ninguem pra levantar. Desliga com `$AutoWatchdog = $false` ou
  `schtasks /delete /tn "MudinhoX RPA Watchdog" /f`.

## 2026-09-01 - a leitura de status falhava porque o OCR nao le a tela INTEIRA

O erro mais comum do log (100 de 1064 leituras, 9,4%) tinha uma causa que nao era a tecla C.

- `Ocr-Status` mandava a captura de **1920x1009 inteira** pro OCR do Windows. Nesse tamanho ele simplesmente
  **nao devolve as palavras do painel de status** — fonte pequena, fundo cinza-escuro e a tela cheia de numeros
  de dano competindo. Recortando so o painel (`$StatPanel`, 500x760 encostado na esquerda) ele le tudo.
- **Provado, nao deduzido**, no `captcha/status_falhou.png` de 12:48 — o print que o proprio bot salvou quando
  logou `status: nao abriu em 6 tentativas`:
  - tela inteira: `Status-Open = False`, `Parse-Attrs -> For=FALTOU Agi=FALTOU Vit=FALTOU Ene=FALTOU`
  - com recorte: `Status-Open = True`, `For=19880 Agi=15000 Vit=10552 Ene=27000`
  O print virou `fixtures/status_ABERTO_dificil.png` e e regressao no `-TestVisao`; desligando o recorte, as
  duas checagens falham.
- Ou seja: **a janela ESTAVA aberta nas 6 tentativas.** O bot apertava C seis vezes achando que ela nao abria,
  e saia deixando o painel aberto (o bug de paridade corrigido antes). Explica tambem os "nao li Vit" e os
  "Pts=-1" com a linha de Pontos visivel na tela.
- Ha fallback pra tela inteira se o recorte nao achar nada: as janelas deste cliente nao tem posicao fixa
  (o inventario ja abriu em dois lugares), entao nao da pra apostar tudo no recorte.
- `$StatPanelScale = 2`. Medi 1x, 2x e 3x: 3x **piora** (imagem grande demais pro OCR). Nao e chute.
- `$StatCol` (1155,108) foi apagado: era a "coluna do painel" da calibracao original e ha muito tempo apontava
  pro cenario — o painel abre na ESQUERDA. Nao tinha mais nenhum leitor no codigo.
- **`-TestStatus [print.png]`** novo: mostra palavra por palavra o que o OCR leu no painel e o que virou
  For/Agi/Vit/Ene/Pontos. Sem ele esse diagnostico era olhar o print e adivinhar.

## 2026-09-01 14:54 - o travamento na reta final do /darmr

Do log, o estado exato:

```
stats: 32922 pontos | etapa 32767 | F=32767 A=32729 V=32767 E=32767 | faltam 38 pro cap
stats: ALERTA - 32922 pontos sobrando (limite 10000) e nao consigo gastar nenhum
```

- **Faltavam 38 na agilidade.** O piso do `/a` era 1000, entao nenhum comando legal fechava o vao; os outros tres
  ja estavam no cap, entao nao havia onde gastar. Resultado: 33 mil pontos parados, tres rodadas de alerta e o
  `/darmr` so saindo depois que voce clicou no `+` na mao.
- O piso do `/a` **nao e frescura**: abaixo de 100 ele teleporta o char pra AIDA (perigo medido, ja documentado).
  Mas o piso estava em 1000 - dez vezes acima do perigo real.
- Tres mudancas, nesta ordem de importancia:
  1. **Nao criar o vao** (a causa). No plano, se mandar `$amt` deixaria uma sobra entre 1 e o piso, ou fecha o
     cap de uma vez (quando os pontos dao), ou manda menos de proposito, deixando uma sobra que o proximo
     comando ainda consegue mandar. Sem isso, qualquer piso - 1000, 500 ou 100 - so muda o TAMANHO do vao
     impossivel, nao resolve.
  2. **Piso menor na reta final** (o pedido): com os 4 atributos acima de `$StatPertoDoMax` (30000), o piso cai
     de 1000 pra `$StatMinPerto` (500). No `/a` fica `max(500, $StatMinAgi=100)` = 500, bem acima da AIDA.
  3. **Leitura rapida perto do cap**: `$StatEveryNearSec` (5s) e o portao "so rele se o level mudou" e ignorado.
     No cap o level pode nem subir mais, e sao justamente os ultimos pontos que liberam o `/darmr`.
- **Se mesmo assim encalhar** (char que ja chegou nesse estado, ou um `/a` manual), o aviso agora diz o que
  fazer: "Agi falta 38 - vao menor que 100, nenhum comando de chat fecha isso. Abra o status (C) e clique no
  '+' desse atributo." Antes era so "nao consigo distribuir".
- Regressoes novas no `test_stats.ps1`: o `/a` recusa 500 longe do maximo e aceita na reta final; o plano
  **nunca** deixa a agilidade a menos de 100 do cap sem fechar; com 767 disponiveis ele fecha em vez de deixar
  vao. E no `test_ciclos.ps1`: perto do maximo o Tick-Stats le mesmo com o level parado.
- **O lint pagou o proprio custo aqui**: `Jit (if($x){ $a } else { $b })` parseia mas explode em runtime (o
  PowerShell trata `if` dentro de parenteses como nome de comando). O `test_lint.ps1` pegou antes de rodar:
  `COMANDO INEXISTENTE linha 889: 'if'`.

## 2026-09-01 15:00 - o que sobrou depois dos consertos (sessao 13:49-15:01)

A culpa dos ciclos lentos mudou de dono. Antes: `reset 14%, status 14%, ? 9%`. Depois:
`? 14%, status 5%, captcha 2-3%` e a perda total caiu de 38% pra 22%. Ou seja: **o `?` virou o maior custo**.

Rastreei os ciclos sem etiqueta (236s, 219s, 216s, 216s contra mediana de 89-111s) ate os warmups em Lost Tower.
Dentro deles, o desperdicio real:

- **149 das 264 leituras de status (56%) nao renderam UM comando.** Mediana de 556 pontos disponiveis - abaixo
  do piso. Cada leitura abre a janela C, rouba o foco e gasta ~3s pra descobrir que nao da pra gastar nada.
  O portao "so rele se o level mudou" nao pega esse caso: no warmup o level sobe o tempo todo, so que rende
  poucos pontos por level.
- Correcao: **recuo progressivo**. Leitura que nao rende comando dobra o intervalo (15s, 30s, 60s, teto de
  `$StatMaxSec`); a primeira leitura util zera o recuo. Perto do cap o teto e curto (`$StatEveryNearSec * 4`),
  porque la a pressa vale mais que o foco. Regressao no `test_ciclos.ps1` com os quatro casos.
- **23 toasts iguais em 5,5 minutos** (o travamento das 14:49-14:55, mesmo alerta repetido). Toast repetido
  treina o usuario a ignorar toast. `Notify-Once <chave>` re-avisa no maximo a cada `$RenotifySec` por assunto;
  o `Log` continua saindo toda vez, que e o que serve pra diagnostico depois.
- **27 linhas iguais de "evento dos dragoes no chat"** em ~1h (o servidor repete o aviso). Mesma logica.
- **Modos de teste agora escrevem em `testes.log`, nao no `rpa.log`.** Cada `-TestVisao` despejava ~30 linhas de
  "OK ..." no meio do log do bot. Como TODO bug serio deste projeto foi achado contando linhas do `rpa.log`,
  poluir o arquivo com as proprias verificacoes atrapalha o unico instrumento de diagnostico que existe aqui.

Confirmado no mesmo log, sobre as correcoes anteriores: **MR #1 saiu limpo** (`/darmr` -> tela de login ->
re-entrada -> warmup em Lost Tower, sem falha de warp), `reset nao aconteceu` caiu pra **1 em 198 comandos**, e
o auto-tune fechou (`350=175938 vs 380=272925 -> alvo 380`), com o `estado.txt` retomando `alvo 380` no restart
das 15:04.

## 2026-09-01 19:00 - onde o tempo do MR realmente vai: o WARMUP

Pedido: "master reset mais agil, comandos disparados mais rapido". Medi antes de mexer, e a resposta nao estava
nos comandos.

| MR | warmup (Lost Tower) | resto (Stadium) | total |
|---|---|---|---|
| #3 | **56 min** (10 resets) | 16 min (20 resets) | 72 min |
| #4 | **37 min** (10 resets) | 14 min (20 resets) | 51 min |

- **O warmup e 73-78% do master reset.** 220s por reset em Lost Tower contra 70-110s no Stadium, por
  praticamente os MESMOS pontos por reset (6121-6261 contra 5942-6577). E os ciclos de warmup **nao aceleram**
  ao longo dos 10 - medidos um a um no MR #4: 230, 226, 222, 228, 219, 217, 283, 219, 238, 216s. Ou seja, o char
  nao esta "esquentando"; Lost Tower e so um spot mais lento.
- Correcao: **testar em vez de assumir.** Apos o `/darmr` o bot vai pro spot normal e tem `$WarmupTesteSec`
  (300s) pra fechar um reset la. Fechou -> pula o warmup inteiro. Estourou (ou nem fechou) -> `Tick-WarmupTeste`
  percebe e cai pro Lost Tower como antes. 300s e folgado de proposito: ciclo saudavel no Stadium e 70-110s e
  ate o Lost Tower fecha em ~220s, entao so estoura se o char realmente nao aguentar. O teste sobrevive a
  restart (vai pro `estado.txt`), senao uma queda no meio dele mandaria o char pro warmup - justo o que ele
  existe pra evitar.
- **Sobre "comandos mais rapidos": o gargalo nao e o teclado.** Medido no log, o ciclo de um comando e:
  ler status (~3s) -> mandar 1 comando (<1s) -> esperar ~15s -> repetir. Os 15s sao `$StatEverySec`, e sao
  gastos ESPERANDO O CHAR SUBIR DE LEVEL pra ter pontos novos - encurtar isso nao faz ponto aparecer mais cedo,
  so gasta foco. O que dava pra cortar sem risco foi cortado:
  - `Read-Status` nao dorme mais 900ms fixos apos apertar C: captura a cada 150ms e segue assim que reconhece o
    painel (~300ms com o recorte do OCR). ~600ms por leitura, centenas de leituras por hora.
  - `$StatRoundSec` 0.5 -> 0.25.
  - `$KeyHoldMs`/`$KeyGapMs` continuam 40/40: abaixo disso o comando embaralha e ja fez `/s18` sair invalido.
- **Alvo fixado em 350 por decisao do usuario**, com o A/B desligado. O experimento tinha apontado 380
  (272925 contra 175938 pontos/h), mas os dois bracos rodaram em SEQUENCIA e nao intercalados - a taxa do 380
  subiu durante a propria janela dele (126941 -> 241948 -> 272925), sinal de que algo mudou junto. Com
  `$AutoTune = $false` o `alvo` do `estado.txt` passa a ser ignorado: quem manda e o CONFIG, senao um alvo
  gravado pelo experimento sobrescreveria a escolha do usuario pra sempre. Regressao no `test_estado.ps1`.
- **Bug do mesmo dia, pego ao vivo no MR #5:** o teste do spot nao rodou - o log mostrou `modo warmup` direto.
  Causa: **nomes de variavel no PowerShell sao case-INSENSITIVE**, entao `$script:warmupTeste` (estado) e
  `$WarmupTeste` (config) eram **a mesma variavel**. A linha de inicializacao do estado, no topo do script,
  zerava a config antes do loop rodar. Estado renomeado pra `$script:spotTeste`. Regressao no `test_estado.ps1`
  cobre a colisao (mexer no estado nao pode apagar a config), verificada renomeando de volta.
  Vale como regra pro projeto: **nunca usar o mesmo nome pra config e pra estado**, nem trocando a caixa.
