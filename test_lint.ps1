# Caca comando inexistente no script (nao toca no jogo): .\test_lint.ps1
# Motivo: o PowerShell so descobre que um comando nao existe QUANDO EXECUTA aquela linha. Um `X` solto
# sobrou no meio do Warp-To-Spot e ficou invisivel ate o bot errar um teleporte - dai morreu com
# "O termo 'X' nao e reconhecido". Aconteceu DUAS vezes (02:18 e 13:25 de 01/09), sempre num ramo raro.
# Este teste percorre a AST e cobra que todo comando chamado exista: funcao do proprio arquivo, cmdlet,
# alias ou executavel. Roda em ~1s e pega o erro antes do bot rodar a noite toda.
$erros = 0
foreach($arq in @('mudinhox_rpa.ps1','watchdog.ps1')){
  $caminho = Join-Path $PSScriptRoot $arq
  $err = $null
  $ast = [System.Management.Automation.Language.Parser]::ParseFile($caminho, [ref]$null, [ref]$err)
  if($err){ $err | % { "SINTAXE $arq linha $($_.Extent.StartLineNumber): $($_.Message)"; $erros++ }; continue }

  $definidas = @{}
  $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) |
    % { $definidas[$_.Name] = $true }

  $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true) | % {
    $el = $_.CommandElements[0]
    # so da pra checar nome literal; `& $var` e chamada dinamica ficam de fora
    if($el -isnot [System.Management.Automation.Language.StringConstantExpressionAst]){ return }
    $nome = $el.Value
    if($definidas.ContainsKey($nome)){ return }
    if($nome -match '^[.\/]' -or $nome -match '^\$'){ return }   # caminho ou variavel
    if(-not (Get-Command $nome -ErrorAction SilentlyContinue)){
      "COMANDO INEXISTENTE em $arq linha $($_.Extent.StartLineNumber): '$nome'  ->  $($_.Extent.Text)"
      $script:erros++
    }
  }
}
if($erros -eq 0){ "OK: nenhum comando fantasma (todo nome chamado existe)" } else { "$erros PROBLEMA(S)"; exit 1 }
