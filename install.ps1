[CmdletBinding()]
param(
    [ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+$')][string]$Version,
    [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'Bubbl\marketplace'),
    [switch]$Strict,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$Repository = 'BubbleBuffer/Bubbl'
$Marketplace = 'bubbl-release'
$SignerWorkflow = 'github.com/BubbleBuffer/Bubbl/.github/workflows/release.yml'
$Target = 'x86_64-pc-windows-msvc'
$ApiRoot = "https://api.github.com/repos/$Repository"

if ($Help) {
    Write-Output 'Usage: .\install.ps1 [-Version X.Y.Z] [-InstallRoot PATH] [-Strict]'
    Write-Output 'Default: install an immutable release with GitHub asset-digest, SHA-256, and package checks. This does not require GitHub CLI or a GitHub account.'
    Write-Output 'Strict: add GitHub release and artifact-attestation verification; requires an authenticated GitHub CLI.'
    return
}

function Invoke-Checked([string]$File, [string[]]$Arguments) {
    & $File @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$File failed with exit code $LASTEXITCODE" }
}

function Find-Codex {
    $desktopBin = Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\bin'
    if (Test-Path -LiteralPath $desktopBin) {
        $desktop = Get-ChildItem -LiteralPath $desktopBin -Filter codex.exe -File -Recurse |
            Sort-Object FullName -Descending | Select-Object -First 1
        if ($desktop) { return $desktop.FullName }
    }
    $command = Get-Command codex -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }
    throw 'Codex CLI not found. Install or update the Codex app first.'
}

function Get-ReleaseAsset($Release, [string]$Name) {
    $asset = $Release.assets | Where-Object { $_.name -eq $Name } | Select-Object -First 1
    if (-not $asset) { throw "Release asset is missing: $Name" }
    return $asset
}

function Save-ReleaseAsset($Asset, [string]$Destination) {
    $oldProgress = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        Invoke-WebRequest -UseBasicParsing -Headers @{ 'User-Agent' = 'Bubbl-Installer' } -Uri $Asset.browser_download_url -OutFile $Destination
    } finally { $ProgressPreference = $oldProgress }
    if ($Asset.digest -notmatch '^sha256:([0-9a-fA-F]{64})$') { throw "Release asset has no SHA-256 digest: $($Asset.name)" }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $Destination).Hash.ToLowerInvariant()
    if ($actual -ne $Matches[1].ToLowerInvariant()) { throw "Release asset digest mismatch: $($Asset.name)" }
}

$codex = Find-Codex
Invoke-Checked $codex @('plugin', '--help')

if ($Strict) {
    $ghCommand = Get-Command gh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $ghCommand) { throw 'Strict verification requires GitHub CLI (gh).' }
    $gh = $ghCommand.Source
    Invoke-Checked $gh @('auth', 'status')
    Invoke-Checked $gh @('attestation', 'verify', '--help')
    Invoke-Checked $gh @('release', 'verify', '--help')
    if ($Version) {
        $tag = "v$Version"
    } else {
        $tag = (& $gh release list -R $Repository --exclude-drafts --exclude-pre-releases --limit 1 --json tagName --jq '.[0].tagName').Trim()
        if ($LASTEXITCODE -ne 0 -or $tag -notmatch '^v([0-9]+\.[0-9]+\.[0-9]+)$') { throw 'No stable Bubbl release found.' }
        $Version = $Matches[1]
    }
    $sourceCommit = (& $gh api "repos/$Repository/commits/$tag" --jq .sha).Trim().ToLowerInvariant()
    if ($LASTEXITCODE -ne 0 -or $sourceCommit -notmatch '^[0-9a-f]{40}$') { throw 'Could not resolve the release commit.' }
} else {
    $headers = @{ 'User-Agent' = 'Bubbl-Installer'; 'Accept' = 'application/vnd.github+json' }
    $releaseUri = if ($Version) { "$ApiRoot/releases/tags/v$Version" } else { "$ApiRoot/releases/latest" }
    $release = Invoke-RestMethod -Headers $headers -Uri $releaseUri
    if ($release.draft -or $release.prerelease -or -not $release.immutable -or $release.tag_name -notmatch '^v([0-9]+\.[0-9]+\.[0-9]+)$') {
        throw 'Bubbl release is not stable and immutable.'
    }
    $tag = $release.tag_name
    $Version = $Matches[1]
    $commitInfo = Invoke-RestMethod -Headers $headers -Uri "$ApiRoot/commits/$tag"
    $sourceCommit = ([string]$commitInfo.sha).ToLowerInvariant()
    if ($sourceCommit -notmatch '^[0-9a-f]{40}$') { throw 'Could not resolve the release commit.' }
}
$archiveName = "bubbl-$Version-$Target.zip"
$sourceRef = "refs/tags/$tag"

$temp = Join-Path ([System.IO.Path]::GetTempPath()) ("bubbl-install-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
try {
    $archive = Join-Path $temp $archiveName
    $checksums = Join-Path $temp 'SHA256SUMS.txt'
    if ($Strict) {
        Invoke-Checked $gh @('release', 'verify', $tag, '-R', $Repository)
        if (-not $PSCommandPath) { throw 'Run install.ps1 from a downloaded file.' }
        Invoke-Checked $gh @('release', 'verify-asset', $tag, $PSCommandPath, '-R', $Repository)
        Invoke-Checked $gh @('attestation', 'verify', $PSCommandPath, '-R', $Repository, '--signer-workflow', $SignerWorkflow, '--source-ref', $sourceRef, '--source-digest', $sourceCommit, '--deny-self-hosted-runners')
        Invoke-Checked $gh @('release', 'download', $tag, '-R', $Repository, '-D', $temp, '-p', $archiveName, '-p', 'SHA256SUMS.txt')
        foreach ($asset in @($archive, $checksums)) {
            Invoke-Checked $gh @('release', 'verify-asset', $tag, $asset, '-R', $Repository)
            Invoke-Checked $gh @('attestation', 'verify', $asset, '-R', $Repository, '--signer-workflow', $SignerWorkflow, '--source-ref', $sourceRef, '--source-digest', $sourceCommit, '--deny-self-hosted-runners')
        }
    } else {
        Save-ReleaseAsset (Get-ReleaseAsset $release $archiveName) $archive
        Save-ReleaseAsset (Get-ReleaseAsset $release 'SHA256SUMS.txt') $checksums
    }
    $expectedLine = Get-Content -LiteralPath $checksums | Where-Object { $_ -match "^[0-9a-fA-F]{64}  $([regex]::Escape($archiveName))$" } | Select-Object -First 1
    if (-not $expectedLine) { throw "$archiveName is absent from SHA256SUMS.txt" }
    $expectedHash = ($expectedLine -split '  ', 2)[0].ToLowerInvariant()
    $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash.ToLowerInvariant()
    if ($actualHash -ne $expectedHash) { throw 'Archive checksum mismatch.' }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($archive)
    try {
        foreach ($entry in $zip.Entries) {
            $entryPath = $entry.FullName.Replace('\', '/')
            if ($entryPath.StartsWith('/') -or $entryPath -match '(^|/)\.\.(/|$)' -or $entryPath -match '^[A-Za-z]:') {
                throw "Unsafe archive entry: $entryPath"
            }
            $unixType = (($entry.ExternalAttributes -shr 16) -band 0xF000)
            $windowsAttributes = ($entry.ExternalAttributes -band 0xFFFF)
            if ($unixType -eq 0xA000 -or ($windowsAttributes -band [int][IO.FileAttributes]::ReparsePoint)) {
                throw "Archive links are not allowed: $entryPath"
            }
        }
    } finally { $zip.Dispose() }
    $expanded = Join-Path $temp 'expanded'
    Expand-Archive -LiteralPath $archive -DestinationPath $expanded
    $candidate = Get-ChildItem -LiteralPath $expanded -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'BUILD-INFO.json') } | Select-Object -First 1
    if (-not $candidate) { throw 'Archive does not contain a Bubbl marketplace root.' }
    $info = Get-Content -Raw -LiteralPath (Join-Path $candidate.FullName 'BUILD-INFO.json') | ConvertFrom-Json
    if ($info.repository -ne $Repository -or $info.version -ne $Version -or $info.target -ne $Target -or $info.tag -ne $tag -or $info.commit -ne $sourceCommit) {
        throw 'BUILD-INFO.json does not match the verified release.'
    }
    $manifest = Get-Content -Raw -LiteralPath (Join-Path $candidate.FullName 'plugins/bubbl/.codex-plugin/plugin.json') | ConvertFrom-Json
    $market = Get-Content -Raw -LiteralPath (Join-Path $candidate.FullName '.agents/plugins/marketplace.json') | ConvertFrom-Json
    if ($manifest.version -ne $Version -or $market.name -ne $Marketplace -or $market.plugins[0].source.path -ne './plugins/bubbl') {
        throw 'Packaged marketplace metadata is invalid.'
    }

    $installFull = [System.IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
    $listed = & $codex plugin marketplace list --json | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) { throw 'Could not inspect configured Codex marketplaces.' }
    $existing = $listed.marketplaces | Where-Object { $_.name -eq $Marketplace } | Select-Object -First 1
    if ($existing -and [System.IO.Path]::GetFullPath($existing.root).TrimEnd('\') -ne $installFull) {
        throw "Marketplace '$Marketplace' already points to a different location: $($existing.root)"
    }

    $parent = Split-Path -Parent $installFull
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $incoming = Join-Path $parent ('.bubbl-incoming-' + [guid]::NewGuid().ToString('N'))
    $previous = Join-Path $parent ('.bubbl-previous-' + [guid]::NewGuid().ToString('N'))
    Copy-Item -Recurse -LiteralPath $candidate.FullName -Destination $incoming
    $hadPrevious = Test-Path -LiteralPath $installFull
    try {
        if ($hadPrevious) { Move-Item -LiteralPath $installFull -Destination $previous }
        Move-Item -LiteralPath $incoming -Destination $installFull
        if (-not $existing) { Invoke-Checked $codex @('plugin', 'marketplace', 'add', $installFull) }
        Invoke-Checked $codex @('plugin', 'add', "bubbl@$Marketplace")
    } catch {
        if (Test-Path -LiteralPath $installFull) { Remove-Item -Recurse -Force -LiteralPath $installFull }
        if ($hadPrevious -and (Test-Path -LiteralPath $previous)) {
            Move-Item -LiteralPath $previous -Destination $installFull
            try { Invoke-Checked $codex @('plugin', 'add', "bubbl@$Marketplace") } catch {}
        } elseif (-not $existing) {
            try { Invoke-Checked $codex @('plugin', 'marketplace', 'remove', $Marketplace) } catch {}
        }
        throw
    }
    if (Test-Path -LiteralPath $previous) { Remove-Item -Recurse -Force -LiteralPath $previous }
    $verification = if ($Strict) { 'attestation-verified' } else { 'checksum-verified immutable' }
    Write-Output "Bubbl $Version installed from $verification release $tag ($sourceCommit)."
    Write-Output 'Open /hooks, inspect and trust the Bubbl UserPromptSubmit hook, then start a new task.'
} finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -Recurse -Force -LiteralPath $temp }
}
