@echo off
REM Instala a Tarefa Agendada que vigia o bot. RODE UMA VEZ, COMO ADMINISTRADOR.
REM Depois de instalada ela roda com privilegio elevado SEM pedir UAC - que e o ponto:
REM se o bot morrer (ou o UAC do launcher nao for aceito), ela traz de volta sozinha.
setlocal
set TAREFA=MudinhoX RPA Watchdog
set PASTA=%~dp0
set PS=%PASTA%watchdog.ps1

net session >nul 2>&1
if errorlevel 1 (
  echo Precisa rodar como ADMINISTRADOR: botao direito neste arquivo, "Executar como administrador".
  pause
  exit /b 1
)

schtasks /query /tn "%TAREFA%" >nul 2>&1
if not errorlevel 1 (
  echo Tarefa ja existe, recriando...
  schtasks /delete /tn "%TAREFA%" /f >nul
)

schtasks /create /tn "%TAREFA%" /tr "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"%PS%\"" /sc minute /mo 3 /rl HIGHEST /f
if errorlevel 1 (
  echo Falhou ao criar a tarefa.
  pause
  exit /b 1
)

echo.
echo Pronto. O watchdog roda a cada 3 minutos e relanca o bot se ele morrer ou travar.
echo   - respeita o stop.flag (parada intencional nao e desfeita)
echo   - nao faz nada se o mudx.exe estiver fechado
echo   - log em watchdog.log
echo.
echo Para desinstalar:  schtasks /delete /tn "%TAREFA%" /f
pause
