param([Parameter(ValueFromRemainingArguments = $true)][string[]]$FlutterArgs)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$sdk = Join-Path $projectRoot '.tools\flutter\bin\flutter.bat'
if (-not (Test-Path -LiteralPath $sdk)) {
    $sdk = (Get-Command flutter -ErrorAction Stop).Source
}
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
$env:CI = 'true'
Push-Location $projectRoot
try {
    # Junctions allow Windows plugin builds without changing system Developer Mode.
    if ([Environment]::OSVersion.Platform -eq 'Win32NT' -and (Test-Path '.flutter-plugins-dependencies')) {
        $metadata = Get-Content '.flutter-plugins-dependencies' -Raw | ConvertFrom-Json
        foreach ($platform in @('windows', 'linux')) {
            foreach ($plugin in $metadata.plugins.$platform) {
                $link = Join-Path $projectRoot "$platform\flutter\ephemeral\.plugin_symlinks\$($plugin.name)"
                if (-not (Test-Path -LiteralPath $link)) {
                    New-Item -ItemType Junction -Path $link -Target $plugin.path -Force | Out-Null
                }
            }
        }
    }
    & $sdk @FlutterArgs
    exit $LASTEXITCODE
} finally { Pop-Location }
