param(
    [string]$OutputDirectory,
    [switch]$IncludeWindows,
    [switch]$BuildWindows
)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $projectRoot 'releases' }
$outputRoot = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($OutputDirectory))
$releaseName = 'FlowDay-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
$staging = Join-Path $outputRoot ('.flowday-package-' + [Guid]::NewGuid().ToString('N'))
$archive = Join-Path $outputRoot ($releaseName + '-server.tar.gz')
$windowsArchive = Join-Path $outputRoot ($releaseName + '-windows.zip')

function Assert-CommandExit([string]$Operation) {
    if ($LASTEXITCODE -ne 0) { throw "$Operation failed (exit $LASTEXITCODE)." }
}
function Write-ArchiveHash([string]$Path) {
    $hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    $line = $hash + '  ' + [IO.Path]::GetFileName($Path)
    [IO.File]::WriteAllText($Path + '.sha256', $line + "`n", [Text.UTF8Encoding]::new($false))
}

foreach ($line in Get-Content -LiteralPath (Join-Path $projectRoot 'server/.env.example')) {
    if ($line -match '^\s*([A-Z0-9_]*(?:KEY|SECRET|TOKEN|PASSWORD|WEBHOOK)[A-Z0-9_]*)=(.*)$' -and $Matches[2].Trim()) {
        throw ('.env.example must not contain a populated credential field: ' + $Matches[1])
    }
}

if ($BuildWindows) {
    & (Join-Path $PSScriptRoot 'flutter.ps1') analyze --no-pub
    Assert-CommandExit 'Flutter analysis'
    & (Join-Path $PSScriptRoot 'flutter.ps1') build windows --release --no-pub
    Assert-CommandExit 'Windows release build'
    $IncludeWindows = $true
}

$tarCommand = (Get-Command tar -ErrorAction Stop).Source
if (Test-Path -LiteralPath $archive) { throw 'The release archive already exists. Run again with a new timestamp.' }
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
New-Item -ItemType Directory -Path $staging | Out-Null
try {
    $serverTarget = Join-Path $staging 'server'
    $docsTarget = Join-Path $staging 'docs'
    $scriptsTarget = Join-Path $staging 'scripts'
    New-Item -ItemType Directory -Path $serverTarget, $docsTarget, $scriptsTarget | Out-Null
    # Explicit allowlist excludes .env, SQLite, user files, logs and node_modules.
    foreach ($name in @('Dockerfile', 'compose.yaml', 'package.json', 'package-lock.json', '.dockerignore', '.env.example', 'README.md')) {
        Copy-Item -LiteralPath (Join-Path $projectRoot "server/$name") -Destination $serverTarget
    }
    $sourceRoot = Join-Path $projectRoot 'server/src'
    foreach ($source in Get-ChildItem -LiteralPath $sourceRoot -Recurse -File -Filter '*.js') {
        $relative = [IO.Path]::GetRelativePath($sourceRoot, $source.FullName)
        $destination = Join-Path $serverTarget "src/$relative"
        New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
        Copy-Item -LiteralPath $source.FullName -Destination $destination
    }
    foreach ($name in @('deployment.md', 'deployment-production.md', 'backend-api.md')) {
        Copy-Item -LiteralPath (Join-Path $projectRoot "docs/$name") -Destination $docsTarget
    }
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'deploy-preflight.sh') -Destination $scriptsTarget
    & $tarCommand -czf $archive -C $staging server docs scripts
    Assert-CommandExit 'Server archive creation'
    Write-ArchiveHash $archive

    if ($IncludeWindows) {
        $built = Join-Path $projectRoot 'build/windows/x64/runner/Release'
        foreach ($required in @('flowday.exe', 'flutter_windows.dll', 'flutter_secure_storage_windows_plugin.dll', 'data')) {
            if (-not (Test-Path -LiteralPath (Join-Path $built $required))) { throw "Windows release missing $required. Use -BuildWindows." }
        }
        if (Test-Path -LiteralPath $windowsArchive) { throw 'The Windows archive already exists.' }
        $windowsTarget = Join-Path $staging 'FlowDay'
        New-Item -ItemType Directory -Path $windowsTarget | Out-Null
        Copy-Item -LiteralPath (Join-Path $built 'flowday.exe') -Destination $windowsTarget
        Get-ChildItem -LiteralPath $built -File -Filter '*.dll' | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $windowsTarget }
        Copy-Item -LiteralPath (Join-Path $built 'data') -Destination $windowsTarget -Recurse
        $nativeAssets = Join-Path $built 'native_assets.json'
        if (Test-Path -LiteralPath $nativeAssets) { Copy-Item -LiteralPath $nativeAssets -Destination $windowsTarget }
        Compress-Archive -LiteralPath $windowsTarget -DestinationPath $windowsArchive
        Write-ArchiveHash $windowsArchive
        Write-Output $windowsArchive
    }
    Write-Output $archive
} finally {
    # Only remove the fresh staging directory created by this invocation.
    $resolvedStaging = [IO.Path]::GetFullPath($staging)
    $resolvedParent = [IO.Path]::GetDirectoryName($resolvedStaging)
    if ($resolvedParent -ne $outputRoot -or -not [IO.Path]::GetFileName($resolvedStaging).StartsWith('.flowday-package-')) {
        throw 'Staging cleanup path escaped the output directory.'
    }
    if (Test-Path -LiteralPath $resolvedStaging) { Remove-Item -LiteralPath $resolvedStaging -Recurse -Force }
}
