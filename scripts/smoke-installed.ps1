param(
    [Parameter(Mandatory = $true)][string]$InstallRoot,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+$')][string]$Version,
    [Parameter(Mandatory = $true)][string]$ExpectedTarget
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$installFull = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $InstallRoot).Path)
$binaryName = if ($IsWindows) { 'bubl.exe' } else { 'bubl' }
$binary = Join-Path $installFull "plugins/bubbl/bin/$binaryName"
$buildInfoPath = Join-Path $installFull 'BUILD-INFO.json'
if (-not (Test-Path -LiteralPath $binary -PathType Leaf)) { throw "installed binary missing: $binary" }
if (-not (Test-Path -LiteralPath $buildInfoPath -PathType Leaf)) { throw 'installed BUILD-INFO.json missing' }

$buildInfo = Get-Content -Raw -LiteralPath $buildInfoPath | ConvertFrom-Json
if ($buildInfo.version -ne $Version -or $buildInfo.target -ne $ExpectedTarget) {
    throw 'installed release metadata does not match the requested version and target'
}

$reportedVersion = (& $binary --version).Trim()
if ($LASTEXITCODE -ne 0 -or $reportedVersion -ne "bubl $Version") {
    throw "installed binary reported an unexpected version: $reportedVersion"
}

$marketplaces = & codex plugin marketplace list --json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw 'could not list Codex marketplaces' }
$marketplace = $marketplaces.marketplaces | Where-Object { $_.name -eq 'bubbl-release' } | Select-Object -First 1
if (-not $marketplace) { throw 'bubbl-release marketplace is not registered' }
$marketRoot = [System.IO.Path]::GetFullPath([string]$marketplace.root).TrimEnd([System.IO.Path]::DirectorySeparatorChar)
if ($marketRoot -ne $installFull.TrimEnd([System.IO.Path]::DirectorySeparatorChar)) {
    throw "bubbl-release marketplace points to an unexpected root: $marketRoot"
}

$plugins = & codex plugin list --marketplace bubbl-release --json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw 'could not inspect installed Bubbl plugin' }
$plugin = $plugins.installed | Where-Object { $_.pluginId -eq 'bubbl@bubbl-release' } | Select-Object -First 1
if (-not $plugin -or -not $plugin.installed -or -not $plugin.enabled -or $plugin.version -ne $Version) {
    throw 'Bubbl is not installed and enabled at the expected version'
}

function New-HookToken([string]$Canary) {
    $hookInput = @{
        hook_event_name = 'UserPromptSubmit'
        prompt = "deliver [@bubl $Canary]"
    } | ConvertTo-Json -Compress
    $hookLines = $hookInput | & $binary codex-hook
    if ($LASTEXITCODE -ne 0) { throw 'installed hook command failed' }
    $hookOutput = [string]::Join([Environment]::NewLine, @($hookLines))
    if ($hookOutput.Contains($Canary)) { throw 'installed hook disclosed the disposable canary' }
    $hook = $hookOutput | ConvertFrom-Json
    if ($hook.decision -ne 'block') { throw 'installed hook did not block the marked prompt' }
    $match = [regex]::Match([string]$hook.hookSpecificOutput.additionalContext, '\[@bubl-ref (b1_[A-Za-z0-9_-]+)\]')
    if (-not $match.Success) { throw 'installed hook did not emit a Bubbl reference' }
    return $match.Groups[1].Value
}

$canary = "bubbl-ci-$($env:GITHUB_RUN_ID)-$($env:GITHUB_RUN_ATTEMPT)-$ExpectedTarget"
$env:BUBL_SMOKE_EXPECTED = $canary
$stdinToken = New-HookToken $canary
$stdinChild = '$value = [Console]::In.ReadToEnd(); if ($value -cne $env:BUBL_SMOKE_EXPECTED) { exit 7 }'
& $binary run $stdinToken --stdin -- pwsh -NoProfile -NonInteractive -Command $stdinChild
if ($LASTEXITCODE -ne 0) { throw 'installed stdin delivery failed' }

$reuseOutput = & $binary run $stdinToken --stdin -- pwsh -NoProfile -NonInteractive -Command $stdinChild 2>&1
$reuseCode = $LASTEXITCODE
if ($reuseCode -eq 0) { throw 'bubble reuse unexpectedly succeeded' }
if ([string]::Join([Environment]::NewLine, @($reuseOutput)) -notmatch 'bubble unavailable') {
    throw 'bubble reuse failed without the expected public error'
}

$envCanary = "env-$canary"
$env:BUBL_SMOKE_EXPECTED_ENV = $envCanary
$envToken = New-HookToken $envCanary
$envChild = 'if ($env:BUBL_SMOKE_DELIVERED -cne $env:BUBL_SMOKE_EXPECTED_ENV) { exit 8 }'
& $binary run $envToken --env BUBL_SMOKE_DELIVERED -- pwsh -NoProfile -NonInteractive -Command $envChild
if ($LASTEXITCODE -ne 0) { throw 'installed environment delivery failed' }

Write-Output "installed Bubbl $Version smoke test passed for $ExpectedTarget"
