param(
    [string]$Tag,
    [string]$Dist
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$cargo = Get-Content -Raw -LiteralPath (Join-Path $repo 'Cargo.toml')
$versionMatch = [regex]::Match($cargo, '(?m)^version = "([^"]+)"$')
if (-not $versionMatch.Success) { throw 'Cargo package version is missing' }
$version = $versionMatch.Groups[1].Value
$plugin = Get-Content -Raw -LiteralPath (Join-Path $repo 'plugins/bubbl/.codex-plugin/plugin.json') | ConvertFrom-Json
if ($plugin.version -ne $version) {
    throw "plugin version $($plugin.version) does not match Cargo version $version"
}

$expectedTag = "v$version"
if ($Tag -and $Tag -ne $expectedTag) {
    throw "release tag $Tag does not match $expectedTag"
}
$changelog = Get-Content -Raw -LiteralPath (Join-Path $repo 'CHANGELOG.md')
if ($changelog -notmatch [regex]::Escape("## [$version]")) {
    throw "CHANGELOG.md has no entry for $version"
}

if ($Dist) {
    $expectedArchives = @(
        "bubbl-$version-x86_64-pc-windows-msvc.zip",
        "bubbl-$version-x86_64-unknown-linux-musl.tar.gz",
        "bubbl-$version-x86_64-apple-darwin.tar.gz",
        "bubbl-$version-aarch64-apple-darwin.tar.gz"
    )
    foreach ($archive in $expectedArchives) {
        if (-not (Test-Path -LiteralPath (Join-Path $Dist $archive))) {
            throw "release archive is missing: $archive"
        }
    }
    foreach ($installer in @('install.ps1', 'install.sh')) {
        if (-not (Test-Path -LiteralPath (Join-Path $Dist $installer))) {
            throw "release installer is missing: $installer"
        }
    }
}

$powerShellInstaller = Get-Content -Raw -LiteralPath (Join-Path $repo 'install.ps1')
$shellInstaller = Get-Content -Raw -LiteralPath (Join-Path $repo 'install.sh')
foreach ($content in @($powerShellInstaller, $shellInstaller)) {
    foreach ($required in @('BubbleBuffer/Bubbl', '--signer-workflow', '--source-ref', '--source-digest', '--deny-self-hosted-runners')) {
        if (-not $content.Contains($required)) { throw "installer is missing release verification: $required" }
    }
    foreach ($forbidden in @('raw.githubusercontent', 'git clone', 'cargo build')) {
        if ($content.Contains($forbidden)) { throw "installer contains forbidden install route: $forbidden" }
    }
}

Write-Output "release metadata validated for $expectedTag"
