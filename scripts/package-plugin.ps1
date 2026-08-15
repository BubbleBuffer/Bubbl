param(
    [Parameter(Mandatory = $true)][string]$Target,
    [Parameter(Mandatory = $true)][string]$Binary,
    [Parameter(Mandatory = $true)][ValidateSet('zip', 'tar.gz')][string]$Format,
    [string]$SourceRepository = 'BubbleBuffer/Bubbl',
    [string]$SourceCommit,
    [string]$SourceRef = 'local'
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
$version = (Select-String -LiteralPath (Join-Path $repo 'Cargo.toml') -Pattern '^version = "([^"]+)"$').Matches[0].Groups[1].Value
if (-not $SourceCommit) {
    $SourceCommit = (& git -C $repo rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'could not determine source commit' }
}
if ($SourceCommit -notmatch '^[0-9a-fA-F]{40}$') { throw 'SourceCommit must be a full Git commit SHA' }

$packageName = "bubbl-$version-$Target"
$packageRoot = Join-Path $repo "target/package/$packageName"
$pluginRoot = Join-Path $packageRoot 'plugins/bubbl'
$dist = Join-Path $repo 'dist'

if (Test-Path -LiteralPath $packageRoot) { Remove-Item -Recurse -Force -LiteralPath $packageRoot }
New-Item -ItemType Directory -Force -Path (Join-Path $pluginRoot 'bin') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $packageRoot '.agents/plugins') | Out-Null

foreach ($directory in @('.codex-plugin', 'hooks', 'skills')) {
    Copy-Item -Recurse -Force -LiteralPath (Join-Path $repo "plugins/bubbl/$directory") -Destination $pluginRoot
}
Copy-Item -Recurse -Force -LiteralPath (Join-Path $repo 'docs') -Destination $pluginRoot
foreach ($file in @('README.md', 'CHANGELOG.md', 'SECURITY.md', 'RELEASING.md', 'LICENSE')) {
    Copy-Item -Force -LiteralPath (Join-Path $repo $file) -Destination $pluginRoot
}
Copy-Item -Force -LiteralPath (Join-Path $repo 'packaging/marketplace.json') -Destination (Join-Path $packageRoot '.agents/plugins/marketplace.json')

$binaryName = if ($Target -like '*windows*') { 'bubl.exe' } else { 'bubl' }
Copy-Item -Force -LiteralPath $Binary -Destination (Join-Path $pluginRoot "bin/$binaryName")
if ($Target -notlike '*windows*') { chmod 755 (Join-Path $pluginRoot "bin/$binaryName") }

[ordered]@{
    repository = $SourceRepository
    version = $version
    target = $Target
    tag = if ($SourceRef -like 'refs/tags/*') { $SourceRef.Substring(10) } else { $null }
    commit = $SourceCommit.ToLowerInvariant()
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $packageRoot 'BUILD-INFO.json') -Encoding utf8NoBOM

New-Item -ItemType Directory -Force -Path $dist | Out-Null
$archive = Join-Path $dist "$packageName.$Format"
if (Test-Path -LiteralPath $archive) { Remove-Item -Force -LiteralPath $archive }
if ($Format -eq 'zip') {
    Compress-Archive -Path $packageRoot -DestinationPath $archive
} else {
    tar -czf $archive -C (Split-Path -Parent $packageRoot) $packageName
    if ($LASTEXITCODE -ne 0) { throw 'tar archive creation failed' }
}

Write-Output $archive
