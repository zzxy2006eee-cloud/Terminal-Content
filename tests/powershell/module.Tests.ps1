$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$modulePath = Join-Path $repoRoot 'shell\term-context.psm1'

$parseTargets = @(
    $modulePath,
    (Join-Path $repoRoot 'installers\install.ps1'),
    (Join-Path $repoRoot 'installers\uninstall.ps1'),
    (Join-Path $repoRoot 'scripts\dev.ps1'),
    (Join-Path $repoRoot 'skills\terminal-context\scripts\verify.ps1'),
    (Join-Path $repoRoot 'tests\powershell\execution-policy.Tests.ps1'),
    (Join-Path $repoRoot 'tests\powershell\title-encoding.Tests.ps1')
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

$dataRoot = if ($env:TERM_CONTEXT_DEV_DATA) {
    $env:TERM_CONTEXT_DEV_DATA
} else {
    Join-Path (Split-Path -Parent $repoRoot) 'data'
}
$binaryCandidates = @(
    (Join-Path $repoRoot 'target\debug\tc.exe'),
    (Join-Path $dataRoot 'target\debug\tc.exe'),
    (Join-Path $dataRoot 'target\release\tc.exe')
)
$binaryPath = $binaryCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
if (-not $binaryPath) {
    throw "A built tc.exe is required for installer tests. Checked: $($binaryCandidates -join ', ')"
}

$sandboxParent = Join-Path $dataRoot 'test-sandboxes'
$sandbox = Join-Path $sandboxParent ("powershell-" + [guid]::NewGuid().ToString('N'))
$installRoot = Join-Path $sandbox 'install'
$profilePath = Join-Path $sandbox 'profile.ps1'
$skillRoot = Join-Path $sandbox '.agents\skills'
$previousDataDir = $env:TERM_CONTEXT_DATA_DIR
$previousBinary = $env:TERM_CONTEXT_BIN

try {
    New-Item -ItemType Directory -Force -Path $sandbox | Out-Null
    $env:TERM_CONTEXT_DATA_DIR = Join-Path $sandbox 'session-data'

    $installArguments = @{
        BinaryPath       = $binaryPath
        InstallCodexSkill = $true
        Force            = $true
        NoAutoPrompt     = $true
        InstallRoot      = $installRoot
        ProfilePath      = $profilePath
        SkillRoot        = $skillRoot
        SkipPathUpdate   = $true
    }
    & (Join-Path $repoRoot 'installers\install.ps1') @installArguments

    $installedBinary = Join-Path $installRoot 'bin\tc.exe'
    $installedModule = Join-Path $installRoot 'shell\term-context.psm1'
    $installedSkill = Join-Path $skillRoot 'terminal-context\SKILL.md'
    foreach ($path in $installedBinary, $installedModule, $installedSkill) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Installer did not create expected file: $path"
        }
    }

    Set-Content -LiteralPath $installedModule -Value '# stale module' -Encoding ascii
    $binaryLock = [IO.File]::Open(
        $installedBinary,
        [IO.FileMode]::Open,
        [IO.FileAccess]::Read,
        [IO.FileShare]::Read
    )
    try {
        & (Join-Path $repoRoot 'installers\install.ps1') @installArguments
    } finally {
        $binaryLock.Dispose()
    }
    if ((Get-FileHash -LiteralPath $installedModule).Hash -ne (Get-FileHash -LiteralPath $modulePath).Hash) {
        throw 'Installer did not refresh the module while an identical installed tc.exe was in use.'
    }

    & $installedBinary --version | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Installed binary version check failed.' }
    if (-not (Get-Command tc-start -ErrorAction SilentlyContinue)) {
        throw 'Installed PowerShell module did not expose tc-start.'
    }
    Remove-Item Env:TERMCTX_ID -ErrorAction SilentlyContinue
    Initialize-TermContext -AutoPrompt
    if ($env:TERMCTX_ID) {
        throw 'Auto prompt ran during a PowerShell -Command or -File automation launch.'
    }
    $sessionId = tc-start -Name 'Installer test' -Description 'PowerShell round-trip'
    if (-not $sessionId) { throw 'tc-start did not create a session.' }
    tc-done | Out-Null

    $profileContent = Get-Content -Raw -LiteralPath $profilePath
    $profileMarkerCount = [regex]::Matches(
        $profileContent,
        [regex]::Escape('# >>> terminal-context >>>')
    ).Count
    if ($profileMarkerCount -ne 1) {
        throw 'PowerShell profile integration is not idempotent.'
    }
    if ($profileContent -notmatch 'TERM_CONTEXT_BIN') {
        throw 'PowerShell profile does not preserve the installed binary path.'
    }

    & (Join-Path $repoRoot 'installers\uninstall.ps1') `
        -RemoveCodexSkill -Force -InstallRoot $installRoot -ProfilePath $profilePath `
        -SkillRoot $skillRoot -SkipPathUpdate

    if (Test-Path -LiteralPath $installRoot) {
        throw "Uninstaller did not remove $installRoot"
    }
    if (Test-Path -LiteralPath (Join-Path $skillRoot 'terminal-context')) {
        throw 'Uninstaller did not remove the Codex Skill.'
    }
    if ((Get-Content -Raw -LiteralPath $profilePath) -match 'terminal-context') {
        throw 'Uninstaller did not remove the PowerShell profile block.'
    }
    Write-Host 'PowerShell installer round-trip checks passed.'
} finally {
    Remove-Module term-context -Force -ErrorAction SilentlyContinue
    if ($null -eq $previousDataDir) {
        Remove-Item Env:TERM_CONTEXT_DATA_DIR -ErrorAction SilentlyContinue
    } else {
        $env:TERM_CONTEXT_DATA_DIR = $previousDataDir
    }
    if ($null -eq $previousBinary) {
        Remove-Item Env:TERM_CONTEXT_BIN -ErrorAction SilentlyContinue
    } else {
        $env:TERM_CONTEXT_BIN = $previousBinary
    }
    $resolvedParent = [IO.Path]::GetFullPath($sandboxParent).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $resolvedSandbox = [IO.Path]::GetFullPath($sandbox)
    if ($resolvedSandbox.StartsWith($resolvedParent, [StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $resolvedSandbox)) {
        Remove-Item -LiteralPath $resolvedSandbox -Recurse -Force
    }
}
