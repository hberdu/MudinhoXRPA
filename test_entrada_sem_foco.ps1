# TESTE: da pra mandar tecla pro cliente do MU SEM trazer a janela pra frente?
# Rode em PowerShell COMO ADMINISTRADOR, com pelo menos 2 clientes abertos.
# Isso decide se o bot consegue rodar sem roubar a sua tela. Nao altera nada do bot; so manda um 'C'
# (abre/fecha o painel de status) num cliente que NAO esta em primeiro plano e mede se a tela dele mudou.
# RESULTADO MEDIDO em 08/09/2026, com PowerShell ELEVADO e o alvo fora de primeiro plano:
#   controle (sem tecla): 897, 921, 893 -> media 904
#   AttachThreadInput+SetFocus   817 px -> nao fez nada   (attach=True, ou seja, nao foi privilegio)
#   PostMessage WM_KEYDOWN       891 px -> nao fez nada
# Os dois FICARAM ABAIXO da variacao natural do jogo. Conclusao: este cliente so aceita entrada real do
# sistema, na janela em primeiro plano. Nao existe caminho de "mandar comando sem roubar a tela".
# Guardado aqui pra ninguem (eu inclusive) tentar de novo achando que foi falta de privilegio.
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;using System.Runtime.InteropServices;
public class SF {
 [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a,uint b,bool f);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr p);
 [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
 [DllImport("user32.dll")] public static extern IntPtr SetFocus(IntPtr h);
 [DllImport("user32.dll")] public static extern IntPtr GetFocus();
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte sc, uint fl, UIntPtr ex);
 [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
 [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint c, uint t);
 [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RC r);
 [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref PT p);
 public struct RC { public int Left,Top,Right,Bottom; } public struct PT { public int X,Y; } }
"@ -ErrorAction SilentlyContinue

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if(-not $admin){ Write-Host "RODE COMO ADMINISTRADOR. Sem isso o teste falha por privilegio, nao por limite da API." -Foreground Red; exit 1 }

function Shot($h){
  $c = New-Object SF+RC; [SF]::GetClientRect($h,[ref]$c) | Out-Null
  $o = New-Object SF+PT; [SF]::ClientToScreen($h,[ref]$o) | Out-Null
  $b = New-Object System.Drawing.Bitmap($c.Right,$c.Bottom)
  $g = [System.Drawing.Graphics]::FromImage($b); $g.CopyFromScreen($o.X,$o.Y,0,0,$b.Size); $g.Dispose(); $b
}
function Dif($a,$b){ $d=0; for($y=20;$y -lt $a.Height-20;$y+=13){ for($x=20;$x -lt $a.Width-20;$x+=13){ if($a.GetPixel($x,$y).ToArgb() -ne $b.GetPixel($x,$y).ToArgb()){ $d++ } } }; $d }

$cls = @(Get-Process mudx -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Sort-Object Id)
if($cls.Count -lt 2){ Write-Host "Abra pelo menos 2 clientes do MU (achei $($cls.Count))." -Foreground Red; exit 1 }
$alvo = $cls[1].MainWindowHandle
if([SF]::GetForegroundWindow() -eq $alvo){ Write-Host "Clique noutra janela: o alvo NAO pode estar em primeiro plano." -Foreground Red; exit 1 }

# CONTROLE: quanto a tela do jogo muda sozinha (ele e animado). Sem isto qualquer numero engana.
$ctrl = @(); foreach($i in 1..3){ $a = Shot $alvo; Start-Sleep -Milliseconds 1300; $b = Shot $alvo; $ctrl += (Dif $a $b); $a.Dispose(); $b.Dispose() }
$base = ($ctrl | Measure-Object -Average).Average
$pico = ($ctrl | Measure-Object -Maximum).Maximum
Write-Host ("controle (sem tecla): {0} -> media {1:0}, maximo {2}" -f ($ctrl -join ', '), $base, $pico)
# Abrir o painel de status muda MUITA area de uma vez. Exijo o dobro do pior controle pra chamar de sucesso.
$limite = [Math]::Max($pico * 2, $base + 400)
Write-Host "limite pra considerar que a tecla funcionou: $([int]$limite) pixels"

$sc = [SF]::MapVirtualKey(0x43,0)   # 'C' = painel de status
foreach($metodo in 'AttachThreadInput+SetFocus','PostMessage WM_KEYDOWN'){
  $antes = Shot $alvo
  if($metodo -like 'Attach*'){
    $meu = [SF]::GetCurrentThreadId(); $dele = [SF]::GetWindowThreadProcessId($alvo,[IntPtr]::Zero)
    $att = [SF]::AttachThreadInput($meu,$dele,$true)
    $ant = [SF]::SetFocus($alvo)
    [SF]::keybd_event(0x43,[byte]$sc,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 60
    [SF]::keybd_event(0x43,[byte]$sc,2,[UIntPtr]::Zero)
    Start-Sleep -Milliseconds 1400
    $extra = "attach=$att focoAntes=$ant focoAgora=$([SF]::GetFocus())"
    [SF]::AttachThreadInput($meu,$dele,$false) | Out-Null
  } else {
    [SF]::PostMessage($alvo,0x0100,[IntPtr]0x43,[IntPtr](1 -bor ($sc -shl 16))) | Out-Null; Start-Sleep -Milliseconds 60
    [SF]::PostMessage($alvo,0x0101,[IntPtr]0x43,[IntPtr](1 -bor ($sc -shl 16) -bor 0xC0000000)) | Out-Null
    Start-Sleep -Milliseconds 1400; $extra = ''
  }
  $depois = Shot $alvo; $d = Dif $antes $depois
  $ok = $d -gt $limite
  Write-Host ("  {0,-28} mudou {1,5} px  ->  {2}   {3}" -f $metodo, $d, $(if($ok){'FUNCIONOU'}else{'nao fez nada'}), $extra) -Foreground $(if($ok){'Green'}else{'Yellow'})
  # devolve o painel ao estado anterior se por acaso abriu
  if($ok -and $metodo -like 'Attach*'){
    $meu = [SF]::GetCurrentThreadId(); $dele = [SF]::GetWindowThreadProcessId($alvo,[IntPtr]::Zero)
    [SF]::AttachThreadInput($meu,$dele,$true) | Out-Null; [SF]::SetFocus($alvo) | Out-Null
    [SF]::keybd_event(0x43,[byte]$sc,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 60; [SF]::keybd_event(0x43,[byte]$sc,2,[UIntPtr]::Zero)
    [SF]::AttachThreadInput($meu,$dele,$false) | Out-Null
  }
  $antes.Dispose(); $depois.Dispose()
}
Write-Host ""
Write-Host "Se algum disser FUNCIONOU, o bot consegue rodar sem roubar a sua tela." -Foreground Cyan
Write-Host "Se os dois disserem 'nao fez nada', entrada exige primeiro plano e a saida e outra (sessao separada)." -Foreground Cyan
