param(
    [Parameter(Mandatory = $true)][string]$PackageRoot,
    [string]$ExpectedTarget,
    [string]$ExpectedCommit,
    [switch]$SkipBinarySmokeTest
)

$ErrorActionPreference = 'Stop'
$PackageRoot = (Resolve-Path -LiteralPath $PackageRoot).Path
$pluginRoot = Join-Path $PackageRoot 'plugins/bubbl'
$marketplacePath = Join-Path $PackageRoot '.agents/plugins/marketplace.json'
$buildInfoPath = Join-Path $PackageRoot 'BUILD-INFO.json'
$required = @(
    (Join-Path $pluginRoot '.codex-plugin/plugin.json'),
    (Join-Path $pluginRoot 'hooks/hooks.json'),
    (Join-Path $pluginRoot 'skills/bubl-ref/SKILL.md'),
    (Join-Path $pluginRoot 'README.md'),
    (Join-Path $pluginRoot 'CHANGELOG.md'),
    (Join-Path $pluginRoot 'SECURITY.md'),
    (Join-Path $pluginRoot 'RELEASING.md'),
    (Join-Path $pluginRoot 'LICENSE'),
    (Join-Path $pluginRoot 'docs/assets/raw-token-policy-refusal.png'),
    (Join-Path $pluginRoot 'docs/assets/bubbl-success.png'),
    (Join-Path $pluginRoot 'docs/demo/AGENTS.md'),
    $marketplacePath,
    $buildInfoPath
)
foreach ($path in $required) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "missing package file: $path" }
}
foreach ($forbidden in @('.mcp.json', '.app.json')) {
    if (Test-Path -LiteralPath (Join-Path $pluginRoot $forbidden)) { throw "unexpected plugin file: $forbidden" }
}

$manifest = Get-Content -Raw -LiteralPath (Join-Path $pluginRoot '.codex-plugin/plugin.json') | ConvertFrom-Json
$marketplace = Get-Content -Raw -LiteralPath $marketplacePath | ConvertFrom-Json
$buildInfo = Get-Content -Raw -LiteralPath $buildInfoPath | ConvertFrom-Json
if ($marketplace.name -ne 'bubbl-release') { throw 'marketplace name must be bubbl-release' }
if ($marketplace.plugins.Count -ne 1 -or $marketplace.plugins[0].name -ne 'bubbl') { throw 'marketplace must contain only bubbl' }
if ($marketplace.plugins[0].source.path -ne './plugins/bubbl') { throw 'marketplace plugin source must be relative' }
if ($buildInfo.repository -ne 'BubbleBuffer/Bubbl') { throw 'BUILD-INFO repository is not official' }
if ($buildInfo.version -ne $manifest.version) { throw 'BUILD-INFO and plugin versions differ' }
if ($ExpectedTarget -and $buildInfo.target -ne $ExpectedTarget) { throw 'BUILD-INFO target differs from expected target' }
if ($ExpectedCommit -and $buildInfo.commit -ne $ExpectedCommit.ToLowerInvariant()) { throw 'BUILD-INFO commit differs from expected commit' }
if ($buildInfo.commit -notmatch '^[0-9a-f]{40}$') { throw 'BUILD-INFO commit is not a full SHA' }

$windowsTarget = $buildInfo.target -like '*windows*'
$binary = Join-Path $pluginRoot $(if ($windowsTarget) { 'bin/bubl.exe' } else { 'bin/bubl' })
$wrongBinary = Join-Path $pluginRoot $(if ($windowsTarget) { 'bin/bubl' } else { 'bin/bubl.exe' })
if (-not (Test-Path -LiteralPath $binary -PathType Leaf)) { throw "missing target executable: $binary" }
if (Test-Path -LiteralPath $wrongBinary) { throw "unexpected target executable: $wrongBinary" }

$hooks = Get-Content -Raw -LiteralPath (Join-Path $pluginRoot 'hooks/hooks.json') | ConvertFrom-Json
$handler = $hooks.hooks.UserPromptSubmit[0].hooks[0]
if ($handler.command -ne '"${PLUGIN_ROOT}/bin/bubl" codex-hook') { throw 'POSIX hook command is not the literal bundled path' }
if ($handler.commandWindows -ne '& "${PLUGIN_ROOT}\bin\bubl.exe" codex-hook') { throw 'Windows hook command is not the literal bundled path' }

if (-not $SkipBinarySmokeTest) {
    & $binary --version
    if ($LASTEXITCODE -ne 0) { throw 'packaged binary smoke test failed' }
    if ($windowsTarget) {
        $hookInput = @{ prompt = 'ordinary packaged hook smoke test'; hook_event_name = 'UserPromptSubmit' } | ConvertTo-Json -Compress
        $powershell = (Get-Process -Id $PID).Path
        $hookOutput = $hookInput | & $powershell -NoProfile -NonInteractive -Command $handler.commandWindows.Replace('${PLUGIN_ROOT}', $pluginRoot) 2>&1
        if ($LASTEXITCODE -ne 0) { throw 'packaged Windows hook command smoke test failed' }
        if ($hookOutput) { throw 'ordinary prompt unexpectedly produced hook output' }
    }
}

Write-Output "package validated: $PackageRoot"
