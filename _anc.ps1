Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Runtime.WindowsRuntime
[void][Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType=WindowsRuntime]
[void][Windows.Graphics.Imaging.BitmapDecoder, Windows.Foundation, ContentType=WindowsRuntime]
[void][Windows.Storage.Streams.InMemoryRandomAccessStream, Windows.Foundation, ContentType=WindowsRuntime]
[void][Windows.Storage.Streams.DataWriter, Windows.Foundation, ContentType=WindowsRuntime]
[void][Windows.Globalization.Language, Windows.Foundation, ContentType=WindowsRuntime]
$asTask=[System.WindowsRuntimeSystemExtensions].GetMethods()|Where-Object {$_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'}|Select-Object -First 1
function Await($op,$t){$x=$asTask.MakeGenericMethod($t).Invoke($null,@($op));$x.Wait();$x.Result}
$ocr=[Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage((New-Object Windows.Globalization.Language('pt-BR')))
$b=[System.Drawing.Bitmap]::FromFile("$PSScriptRoot\captcha\inventario_falhou.png")
$ms=New-Object System.IO.MemoryStream;$b.Save($ms,[System.Drawing.Imaging.ImageFormat]::Bmp)
$ras=New-Object Windows.Storage.Streams.InMemoryRandomAccessStream
$dw=New-Object Windows.Storage.Streams.DataWriter($ras.GetOutputStreamAt(0));$dw.WriteBytes($ms.ToArray())
$null=Await ($dw.StoreAsync()) ([uint32]);$null=Await ($dw.FlushAsync()) ([bool])
$d=Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($ras)) ([Windows.Graphics.Imaging.BitmapDecoder])
$sb=Await ($d.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
$r=Await ($ocr.RecognizeAsync($sb)) ([Windows.Media.Ocr.OcrResult])
"ancoras do painel de inventario:"
foreach($l in $r.Lines){
  foreach($w in $l.Words){
    if($w.Text -match '(?i)^(invent|zen)'){
      $br=$w.BoundingRect
      "  '{0}'  x={1} y={2} w={3} h={4}" -f $w.Text,[int]$br.X,[int]$br.Y,[int]$br.Width,[int]$br.Height
    }
  }
}
$b.Dispose()
