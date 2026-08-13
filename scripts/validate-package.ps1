param([Parameter(Mandatory = $true)][string]$PluginRoot)

$ErrorActionPreference = 'Stop'
$manifest = Join-Path $PluginRoot '.codex-plugin/plugin.json'
$hooks = Join-Path $PluginRoot 'hooks/hooks.json'
$skill = Join-Path $PluginRoot 'skills/bubl-ref/SKILL.md'
$binary = @(
    (Join-Path $PluginRoot 'bin/bubl.exe'),
    (Join-Path $PluginRoot 'bin/bubl')
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

foreach ($path in @($manifest, $hooks, $skill)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "missing package file: $path" }
}
if (-not $binary) { throw 'missing packaged bubl executable' }
if (Test-Path -LiteralPath (Join-Path $PluginRoot '.mcp.json')) { throw 'unexpected MCP configuration' }
if (Test-Path -LiteralPath (Join-Path $PluginRoot '.app.json')) { throw 'unexpected app configuration' }

& $binary --version
if ($LASTEXITCODE -ne 0) { throw 'packaged binary smoke test failed' }
