# Watchdog do MudinhoX RPA. Roda pela Tarefa Agendada (ver instalar-watchdog.cmd) a cada poucos minutos.
# Motivo: se o processo do bot morre, ou o UAC nao e aceito, NADA o traz de volta - foi o que aconteceu em 01/09.
# A tarefa roda com privilegio elevado, entao relanca o bot SEM prompt de UAC.
$dir  = $PSScriptRoot
$bot  = Join-Path $dir 'mudinhox_rpa.ps1'
$hb   = Join-Path $dir 'heartbeat.txt'
$stop = Join-Path $dir 'stop.flag'
$log  = Join-Path $dir 'watchdog.log'
$vivoSec = 180   # heartbeat mais velho que isso = bot morto ou travado

function Diz($m){
  $l = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m
  try { Add-Content -Path $log -Value $l -Encoding UTF8 } catch {}
  Write-Host $l
}

# Voce parou de proposito? O watchdog respeita e nao ressuscita.
if(Test-Path $stop){ Diz "stop.flag presente: nao vou relancar (parada intencional)"; exit 0 }

# Sem o jogo aberto o bot nao tem o que fazer - e ele proprio ja sabe esperar o cliente voltar.
if(-not (Get-Process mudx -ErrorAction SilentlyContinue)){ Diz "mudx.exe nao esta rodando: nada a fazer"; exit 0 }

$vivo = $false
if(Test-Path $hb){
  try {
    $t = [datetime]::new([long](Get-Content $hb -Raw).Trim())
    $idade = [int]((Get-Date) - $t).TotalSeconds
    if($idade -lt $vivoSec){ $vivo = $true } else { Diz "heartbeat parado ha ${idade}s (limite ${vivoSec}s)" }
  } catch { Diz "heartbeat ilegivel: $_" }
} else { Diz "sem heartbeat.txt" }

if($vivo){ exit 0 }

# Bot morto/travado: mata sobra e sobe de novo. O proprio bot recusa subir se achar heartbeat fresco,
# entao nao ha risco de dois rodando.
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.CommandLine -like '*mudinhox_rpa.ps1*' } |
  ForEach-Object { Diz "matando instancia travada (pid $($_.ProcessId))"; Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Remove-Item $hb -ErrorAction SilentlyContinue

Diz "relancando o bot"
Start-Process powershell -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',"`"$bot`"" -WorkingDirectory $dir
