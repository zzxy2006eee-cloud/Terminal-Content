$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$modulePath = Join-Path $repoRoot 'shell\term-context.psm1'

$parseTargets = @(
    $modulePath,
    (Join-Path $repoRoot 'installers\install.ps1'),
    (Join-Path $repoRoot 'installers\uninstall.ps1'),
    (Join-Path $repoRoot 'scripts\dev.ps1'),
    (Join-Path $repoRoot 'skills\terminal-context\scripts\verify.ps1')
)

foreach ($target in $parseTargets) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($target, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count -gt 0) {
        throw "PowerShell parse errors in ${target}: $($errors -join '; ')"
    }
}

Import-Module $modulePath -Force

$expectedCommands = @(
    'Start-TermContext',
    'Update-TermContext',
    'Set-TermContextName',
    'Set-TermContextDescription',
    'Stop-TermContext',
    'Invoke-TermContextCommand',
    'Open-TermContextDashboard'
)

foreach ($name in $expectedCommands) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        throw "Missing exported PowerShell function: $name"
    }
}

Write-Host 'PowerShell module export checks passed.'
