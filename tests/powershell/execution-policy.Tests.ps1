$ErrorActionPreference = 'Stop'

if (-not $env:CI) {
    Write-Host 'Execution-policy first-install test is CI-only to avoid changing the local user policy.'
    return
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$binaryPath = Join-Path $repoRoot 'target\debug\tc.exe'
if (-not (Test-Path -LiteralPath $binaryPath -PathType Leaf)) {
    throw "A built tc.exe is required for the execution-policy test: $binaryPath"
}

$sandboxParent = Join-Path $repoRoot 'target\test-sandboxes'
$sandbox = Join-Path $sandboxParent ("execution-policy-" + [guid]::NewGuid().ToString('N'))
$installRoot = Join-Path $sandbox 'install'
$profilePath = Join-Path $sandbox 'profile.ps1'
$skillRoot = Join-Path $sandbox '.agents\skills'
$previousPolicy = Get-ExecutionPolicy -Scope CurrentUser
$previousDataDir = $env:TERM_CONTEXT_DATA_DIR

function Set-TestCurrentUserPolicy {
    param([Parameter(Mandatory)][string]$Policy)

    $setError = $null
    try {
        Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy $Policy -Force -ErrorAction Stop
    } catch {
        $setError = $_
    }
    $savedPolicy = Get-ExecutionPolicy -Scope CurrentUser
    if ($savedPolicy -ne $Policy) {
        if ($setError) { throw $setError }
        throw "Could not set the CI test CurrentUser policy to $Policy; found $savedPolicy."
    }
    if ($setError -and $setError.FullyQualifiedErrorId -notmatch '^ExecutionPolicyOverride') {
        throw $setError
    }
}

try {
    New-Item -ItemType Directory -Force -Path $sandbox | Out-Null
    $env:TERM_CONTEXT_DATA_DIR = Join-Path $sandbox 'session-data'
    Set-TestCurrentUserPolicy -Policy Undefined

    $windowsPowerShell = (Get-Command powershell.exe -ErrorAction Stop).Source
    $installer = Join-Path $repoRoot 'installers\install.ps1'
    $arguments = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $installer,
        '-BinaryPath', $binaryPath,
        '-InstallCodexSkill',
        '-ConfigureExecutionPolicy',
        '-Force',
        '-NoAutoPrompt',
        '-InstallRoot', $installRoot,
        '-ProfilePath', $profilePath,
        '-SkillRoot', $skillRoot,
        '-SkipPathUpdate'
    )
    & $windowsPowerShell @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "First-install subprocess failed with exit code $LASTEXITCODE."
    }

    $savedPolicy = Get-ExecutionPolicy -Scope CurrentUser
    if ($savedPolicy -ne 'RemoteSigned') {
        throw "Installer did not persist RemoteSigned for CurrentUser; found $savedPolicy."
    }
    if (-not (Test-Path -LiteralPath (Join-Path $installRoot 'bin\tc.exe') -PathType Leaf)) {
        throw 'Installer stopped after the Process-scope execution-policy override.'
    }
    Write-Host 'Process Bypass / CurrentUser RemoteSigned first-install check passed.'
} finally {
    Set-TestCurrentUserPolicy -Policy $previousPolicy
    if ($null -eq $previousDataDir) {
        Remove-Item Env:TERM_CONTEXT_DATA_DIR -ErrorAction SilentlyContinue
    } else {
        $env:TERM_CONTEXT_DATA_DIR = $previousDataDir
    }

    $resolvedParent = [IO.Path]::GetFullPath($sandboxParent).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $resolvedSandbox = [IO.Path]::GetFullPath($sandbox)
    if ($resolvedSandbox.StartsWith($resolvedParent, [StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $resolvedSandbox)) {
        Remove-Item -LiteralPath $resolvedSandbox -Recurse -Force
    }
}
