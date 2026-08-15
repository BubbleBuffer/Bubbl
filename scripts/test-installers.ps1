param(
    [Parameter(Mandatory = $true)][string]$Archive,
    [ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+$')][string]$Version = '1.0.0',
    [ValidatePattern('^[0-9a-fA-F]{40}$')][string]$ExpectedCommit = '0123456789abcdef0123456789abcdef01234567'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
$Archive = (Resolve-Path -LiteralPath $Archive).Path
$commit = $ExpectedCommit.ToLowerInvariant()
$archiveName = "bubbl-$Version-x86_64-pc-windows-msvc.zip"
$temp = Join-Path ([System.IO.Path]::GetTempPath()) ('bubbl-installer-tests-' + [guid]::NewGuid().ToString('N'))
$oldPath = $env:PATH
$oldLocalAppData = $env:LOCALAPPDATA

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Invoke-Installer([string]$InstallRoot) {
    & pwsh -NoProfile -NonInteractive -File (Join-Path $repo 'install.ps1') -Version $Version -InstallRoot $InstallRoot 2>&1 | Out-Host
    return $LASTEXITCODE
}
function Set-FixtureArchive([string]$Source) {
    Copy-Item -Force -LiteralPath $Source -Destination (Join-Path $temp "release/$archiveName")
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $temp "release/$archiveName")).Hash.ToLowerInvariant()
    Set-Content -LiteralPath (Join-Path $temp 'release/SHA256SUMS.txt') -Value "$hash  $archiveName" -Encoding utf8NoBOM
}

New-Item -ItemType Directory -Force -Path (Join-Path $temp 'bin'), (Join-Path $temp 'release'), (Join-Path $temp 'local') | Out-Null
try {
    Set-Content -LiteralPath (Join-Path $temp 'bin/gh.cmd') -Encoding ascii -Value '@pwsh -NoProfile -NonInteractive -File "%~dp0gh.ps1" %*'
    Set-Content -LiteralPath (Join-Path $temp 'bin/codex.cmd') -Encoding ascii -Value '@pwsh -NoProfile -NonInteractive -File "%~dp0codex.ps1" %*'
    Set-Content -LiteralPath (Join-Path $temp 'bin/gh.ps1') -Encoding utf8NoBOM -Value @'
$all = [string]::Join(' ', $args)
if ($env:BUBBL_TEST_FAIL_ATTESTATION -eq '1' -and $all -like 'attestation verify*') { exit 1 }
if ($args[0] -eq 'api') { Write-Output $env:BUBBL_TEST_COMMIT; exit 0 }
if ($args[0] -eq 'release' -and $args[1] -eq 'list') { Write-Output ('v' + $env:BUBBL_TEST_VERSION); exit 0 }
if ($args[0] -eq 'release' -and $args[1] -eq 'download') {
    $destination = $args[[Array]::IndexOf($args, '-D') + 1]
    New-Item -ItemType Directory -Force -Path $destination | Out-Null
    Copy-Item -Force -LiteralPath (Join-Path $env:BUBBL_TEST_RELEASE $env:BUBBL_TEST_ARCHIVE_NAME) -Destination $destination
    Copy-Item -Force -LiteralPath (Join-Path $env:BUBBL_TEST_RELEASE 'SHA256SUMS.txt') -Destination $destination
}
exit 0
'@
    Set-Content -LiteralPath (Join-Path $temp 'bin/codex.ps1') -Encoding utf8NoBOM -Value @'
if ($args[0] -eq 'plugin' -and $args[1] -eq 'marketplace' -and $args[2] -eq 'list') {
    $items = @()
    if (Test-Path -LiteralPath $env:BUBBL_TEST_MARKET_FILE) {
        $items += @{ name = 'bubbl-release'; root = (Get-Content -Raw -LiteralPath $env:BUBBL_TEST_MARKET_FILE).Trim() }
    }
    @{ marketplaces = $items } | ConvertTo-Json -Depth 4
    exit 0
}
if ($args[0] -eq 'plugin' -and $args[1] -eq 'marketplace' -and $args[2] -eq 'add') {
    Set-Content -LiteralPath $env:BUBBL_TEST_MARKET_FILE -Value $args[3] -NoNewline
    exit 0
}
if ($args[0] -eq 'plugin' -and $args[1] -eq 'marketplace' -and $args[2] -eq 'remove') {
    Remove-Item -Force -ErrorAction SilentlyContinue -LiteralPath $env:BUBBL_TEST_MARKET_FILE
    exit 0
}
if ($args[0] -eq 'plugin' -and $args[1] -eq 'add' -and $env:BUBBL_TEST_FAIL_ADD -eq '1') { exit 9 }
exit 0
'@
    $env:PATH = (Join-Path $temp 'bin') + [IO.Path]::PathSeparator + $oldPath
    $env:LOCALAPPDATA = Join-Path $temp 'local'
    $env:BUBBL_TEST_RELEASE = Join-Path $temp 'release'
    $env:BUBBL_TEST_COMMIT = $commit
    $env:BUBBL_TEST_VERSION = $Version
    $env:BUBBL_TEST_ARCHIVE_NAME = $archiveName
    $env:BUBBL_TEST_MARKET_FILE = Join-Path $temp 'market.txt'
    Set-FixtureArchive $Archive

    $install = Join-Path $temp 'installed/marketplace'
    Assert-True ((Invoke-Installer $install) -eq 0) 'first install failed'
    Assert-True (Test-Path -LiteralPath (Join-Path $install 'plugins/bubbl/bin/bubl.exe')) 'installed binary missing'
    Set-Content -LiteralPath (Join-Path $install 'upgrade-sentinel') -Value old
    Assert-True ((Invoke-Installer $install) -eq 0) 'upgrade failed'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $install 'upgrade-sentinel'))) 'upgrade did not replace old marketplace'

    Set-Content -LiteralPath (Join-Path $install 'attestation-sentinel') -Value keep
    $env:BUBBL_TEST_FAIL_ATTESTATION = '1'
    Assert-True ((Invoke-Installer $install) -ne 0) 'missing attestation was accepted'
    Assert-True (Test-Path -LiteralPath (Join-Path $install 'attestation-sentinel')) 'attestation failure mutated installation'
    $env:BUBBL_TEST_FAIL_ATTESTATION = '0'

    Set-Content -LiteralPath (Join-Path $temp 'release/SHA256SUMS.txt') -Value "$('0' * 64)  $archiveName" -Encoding utf8NoBOM
    Assert-True ((Invoke-Installer $install) -ne 0) 'bad checksum was accepted'
    Assert-True (Test-Path -LiteralPath (Join-Path $install 'attestation-sentinel')) 'checksum failure mutated installation'
    Set-FixtureArchive $Archive

    Set-Content -LiteralPath $env:BUBBL_TEST_MARKET_FILE -Value (Join-Path $temp 'other-market') -NoNewline
    Assert-True ((Invoke-Installer $install) -ne 0) 'marketplace collision was accepted'
    Assert-True (Test-Path -LiteralPath (Join-Path $install 'attestation-sentinel')) 'collision mutated installation'
    Set-Content -LiteralPath $env:BUBBL_TEST_MARKET_FILE -Value $install -NoNewline

    $env:BUBBL_TEST_FAIL_ADD = '1'
    Assert-True ((Invoke-Installer $install) -ne 0) 'Codex add failure was accepted'
    Assert-True (Test-Path -LiteralPath (Join-Path $install 'attestation-sentinel')) 'Codex add failure did not restore previous marketplace'
    $env:BUBBL_TEST_FAIL_ADD = '0'

    $badZip = Join-Path $temp 'bad.zip'
    Add-Type -AssemblyName System.IO.Compression
    $stream = [IO.File]::Open($badZip, [IO.FileMode]::Create)
    $zip = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create)
    [void]$zip.CreateEntry('../escape')
    $zip.Dispose(); $stream.Dispose()
    Set-FixtureArchive $badZip
    Assert-True ((Invoke-Installer $install) -ne 0) 'unsafe archive was accepted'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $temp 'escape'))) 'unsafe archive escaped extraction root'

    foreach ($file in @('install.ps1', 'install.sh')) {
        $text = Get-Content -Raw -LiteralPath (Join-Path $repo $file)
        Assert-True (-not ($text -match 'raw\.githubusercontent|git clone|cargo build|\bPATH-install\b|--archive')) "$file contains a forbidden installation route"
        Assert-True ($text.Contains('BubbleBuffer/Bubbl')) "$file does not pin the official repository"
        Assert-True ($text.Contains('--signer-workflow')) "$file does not pin the signer workflow"
        Assert-True ($text.Contains('--source-ref')) "$file does not pin the source ref"
        Assert-True ($text.Contains('--source-digest')) "$file does not pin the source commit"
        Assert-True ($text.Contains('--deny-self-hosted-runners')) "$file permits self-hosted provenance"
    }
    $shell = Get-Content -Raw -LiteralPath (Join-Path $repo 'install.sh')
    foreach ($target in @('x86_64-unknown-linux-musl', 'x86_64-apple-darwin', 'aarch64-apple-darwin')) {
        Assert-True ($shell.Contains($target)) "install.sh lacks platform mapping for $target"
    }
    Write-Output 'installer tests passed'
} finally {
    $env:PATH = $oldPath
    $env:LOCALAPPDATA = $oldLocalAppData
    Remove-Item Env:BUBBL_TEST_RELEASE, Env:BUBBL_TEST_COMMIT, Env:BUBBL_TEST_VERSION, Env:BUBBL_TEST_ARCHIVE_NAME, Env:BUBBL_TEST_MARKET_FILE, Env:BUBBL_TEST_FAIL_ATTESTATION, Env:BUBBL_TEST_FAIL_ADD -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $temp) { Remove-Item -Recurse -Force -LiteralPath $temp }
}
