@echo off
REM Sobe UM bot por cliente do MU. Cada slot pega uma janela do mudx (ordenadas por PID).
REM Os quatro vao pro MESMO spot (o $WarpCmd do CONFIG): eles sobem em PARTY, entao ficam juntos.
REM Precisa de admin igual ao de sempre: o jogo roda elevado e sem isso o Windows ignora teclado/mouse do bot.
REM Pra parar TODOS de uma vez, crie um arquivo stop.flag nesta pasta (sem numero).
cd /d "%~dp0"
net session >nul 2>&1 || (
  powershell -NoProfile -Command "Start-Process -Verb RunAs -FilePath '%comspec%' -ArgumentList '/c','\"%~f0\"'"
  exit /b
)
set CLIENTES=4
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$n=(Get-Process mudx -EA SilentlyContinue ^| Where-Object { $_.MainWindowHandle -ne 0 }).Count;" ^
  "if($n -lt %CLIENTES%){ Write-Host \"So achei $n janela(s) do mudx, e o lancador quer %CLIENTES%. Abra os clientes que faltam e rode de novo.\" -Foreground Yellow; exit 1 }" ^
  "Write-Host \"$n clientes encontrados.\" -Foreground Green"
if errorlevel 1 ( pause & exit /b )
del /q stop.flag 2>nul
for /l %%s in (1,1,%CLIENTES%) do (
  echo Subindo slot %%s...
  start "" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0mudinhox_rpa.ps1" -Slot %%s
  REM 3s entre um e outro: os quatro disputam o mesmo mutex de entrada logo no preflight, e subir juntos
  REM so faz tres deles esperarem na fila enquanto o primeiro le a tela.
  timeout /t 3 /nobreak >nul
)
echo.
echo %CLIENTES% bots no ar. Cada um tem a sua janelinha (o titulo diz o slot e o spot).
echo Log de cada um: rpa1.log, rpa2.log, ...   Estado: estado1.txt, estado2.txt, ...
echo Pra parar todos: crie um arquivo stop.flag nesta pasta.
timeout /t 6 /nobreak >nul
