param(
    [Parameter(Mandatory = $true)][string]$Target,
    [Parameter(Mandatory = $true)][string]$Binary,
    [Parameter(Mandatory = $true)][ValidateSet('zip', 'tar.gz')][string]$Format
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$version = (Select-String -LiteralPath (Join-Path $repo 'Cargo.toml') -Pattern '^version = "([^"]+)"$').Matches[0].Groups[1].Value
$stage = Join-Path $repo "target/package/bubbl-$version-$Target/bubbl"
$dist = Join-Path $repo 'dist'

if (Test-Path -LiteralPath $stage) { Remove-Item -Recurse -Force -LiteralPath $stage }
New-Item -ItemType Directory -Force -Path (Join-Path $stage 'bin') | Out-Null
Copy-Item -Recurse -Force -LiteralPath (Join-Path $repo 'plugins/bubbl/.codex-plugin') -Destination $stage
Copy-Item -Recurse -Force -LiteralPath (Join-Path $repo 'plugins/bubbl/hooks') -Destination $stage
Copy-Item -Recurse -Force -LiteralPath (Join-Path $repo 'plugins/bubbl/skills') -Destination $stage
$binaryName = if ($Target -like '*windows*') { 'bubl.exe' } else { 'bubl' }
Copy-Item -Force -LiteralPath $Binary -Destination (Join-Path $stage "bin/$binaryName")
if ($Target -notlike '*windows*') {
    chmod 755 (Join-Path $stage "bin/$binaryName")
}
New-Item -ItemType Directory -Force -Path $dist | Out-Null
$base = Join-Path $dist "bubbl-$version-$Target"

if ($Format -eq 'zip') {
    if (Test-Path -LiteralPath "$base.zip") { Remove-Item -Force -LiteralPath "$base.zip" }
    Compress-Archive -Path $stage -DestinationPath "$base.zip"
} else {
    tar -czf "$base.tar.gz" -C (Split-Path -Parent $stage) 'bubbl'
}
