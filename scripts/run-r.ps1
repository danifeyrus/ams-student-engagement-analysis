param(
  [Parameter(Mandatory = $true, Position = 0)]
  [string]$Script,
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$ScriptArguments
)

$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$pathCommand = Get-Command Rscript -ErrorAction SilentlyContinue
$localExecutable = Join-Path $projectRoot "tmp\R-4.6.2\bin\Rscript.exe"

if ($pathCommand) {
  $rscript = $pathCommand.Source
} elseif (Test-Path -LiteralPath $localExecutable) {
  $rscript = $localExecutable
} else {
  $installed = @(
    Get-ChildItem -LiteralPath "C:\Program Files\R" -Filter "Rscript.exe" -Recurse -ErrorAction SilentlyContinue
  ) | Sort-Object FullName -Descending | Select-Object -First 1
  if (-not $installed) {
    throw "Rscript was not found. Install R and add its bin directory to PATH."
  }
  $rscript = $installed.FullName
}

Set-Location -LiteralPath $projectRoot
& $rscript $Script @ScriptArguments
exit $LASTEXITCODE
