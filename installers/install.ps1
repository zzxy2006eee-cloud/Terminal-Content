[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$BinaryPath,
    [switch]$NoAutoPrompt,
    [switch]$InstallCodexSkill,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $BinaryPath) {
    $BinaryPath = Join-Path $repoRoot 'target\release\tc.exe'
}
$BinaryPath = (Resolve-Path -LiteralPath $BinaryPath).Path
$moduleSource = Join-Path $repoRoot 'shell\term-context.psm1'
$installRoot = Join-Path $env:LOCALAPPDATA 'TermContext'
$binDir = Join-Path $installRoot 'bin'
$moduleDir = Join-Path $installRoot 'shell'
$installedBinary = Join-Path $binDir 'tc.exe'
$installedModule = Join-Path $moduleDir 'term-context.psm1'

if (-not $Force) {
    $answer = Read-Host "Install Terminal Context to $installRoot and update your PowerShell profile? [y/N]"
    if ($answer -notmatch '^(y|yes)$') { return }
}

if ($PSCmdlet.ShouldProcess($installRoot, 'Install Terminal Context')) {
    New-Item -ItemType Directory -Force -Path $binDir, $moduleDir | Out-Null
    Copy-Item -LiteralPath $BinaryPath -Destination $installedBinary -Force
    Copy-Item -LiteralPath $moduleSource -Destination $installedModule -Force

    $profilePath = $PROFILE.CurrentUserAllHosts
    $profileDir = Split-Path -Parent $profilePath
    New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
    $existing = if (Test-Path -LiteralPath $profilePath) { Get-Content -Raw -LiteralPath $profilePath } else { '' }
    $start = '# >>> terminal-context >>>'
    $end = '# <<< terminal-context <<<'
    $escapedStart = [regex]::Escape($start)
    $escapedEnd = [regex]::Escape($end)
    $existing = [regex]::Replace($existing, "(?s)\r?\n?$escapedStart.*?$escapedEnd\r?\n?", "`r`n")
    $autoPrompt = if ($NoAutoPrompt) { '' } else { ' -AutoPrompt' }
    $moduleLiteral = $installedModule.Replace("'", "''")
    $block = @"
$start
Import-Module '$moduleLiteral'
Initialize-TermContext$autoPrompt
$end
"@
    Set-Content -LiteralPath $profilePath -Value ($existing.TrimEnd() + "`r`n" + $block) -Encoding utf8

    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $parts = @($userPath -split ';' | Where-Object { $_ })
    if ($parts -notcontains $binDir) {
        [Environment]::SetEnvironmentVariable('Path', (($parts + $binDir) -join ';'), 'User')
    }
    $env:Path = "$binDir;$env:Path"
    if ($InstallCodexSkill) {
        $skillSource = Join-Path $repoRoot 'skills\terminal-context'
        $codexRoot = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }
        $skillTarget = Join-Path $codexRoot 'skills\terminal-context'
        New-Item -ItemType Directory -Force -Path $skillTarget | Out-Null
        Copy-Item -Path (Join-Path $skillSource '*') -Destination $skillTarget -Recurse -Force
        Write-Host "Installed personal Codex skill to $skillTarget"
    }
    Write-Host "Installed. Open a new PowerShell terminal or run: Import-Module '$installedModule'"
}
