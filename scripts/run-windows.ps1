$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$app = Join-Path $projectRoot 'build\windows\x64\runner\Release\flowday.exe'
if (-not (Test-Path -LiteralPath $app)) {
    throw '请先运行 .\scripts\flutter.ps1 build windows --release --no-pub'
}
Start-Process -FilePath $app -WorkingDirectory (Split-Path $app -Parent)
