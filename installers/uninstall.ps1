[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$RemoveCodexSkill,
    [switch]$Force,
    [string]$InstallRoot,
    [string]$ProfilePath,
    [string]$SkillRoot,
    [switch]$SkipPathUpdate
)

$ErrorActionPreference = 'Stop'
$userHome = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
if (-not $InstallRoot) {
    if (-not $env:LOCALAPPDATA) {
        throw 'LOCALAPPDATA is not set. Pass -InstallRoot explicitly.'
    }
    $InstallRoot = Join-Path $env:LOCALAPPDATA 'TermContext'
}
if (-not $ProfilePath) { $ProfilePath = $PROFILE.CurrentUserAllHosts }
if (-not $SkillRoot) { $SkillRoot = Join-Path $userHome '.agents\skills' }

$binDir = Join-Path $InstallRoot 'bin'
$skillTarget = Join-Path $SkillRoot 'terminal-context'
$legacySkillTargets = @((Join-Path $userHome '.codex\skills\terminal-context'))
if ($env:CODEX_HOME) {
    $legacySkillTargets += Join-Path $env:CODEX_HOME 'skills\terminal-context'
}

if (-not $Force) {
    $answer = Read-Host 'Remove Terminal Context and its PowerShell profile block? Session data and execution policy are kept. [y/N]'
    if ($answer -notmatch '^(y|yes)$') { return }
}

if ($PSCmdlet.ShouldProcess($InstallRoot, 'Uninstall Terminal Context')) {
    Remove-Module term-context -Force -ErrorAction SilentlyContinue

    if (Test-Path -LiteralPath $ProfilePath) {
        $content = Get-Content -Raw -LiteralPath $ProfilePath
        $start = [regex]::Escape('# >>> terminal-context >>>')
        $end = [regex]::Escape('# <<< terminal-context <<<')
        $content = [regex]::Replace($content, "(?s)\r?\n?$start.*?$end\r?\n?", "`r`n")
        Set-Content -LiteralPath $ProfilePath -Value $content.TrimEnd() -Encoding utf8
    }

    if (-not $SkipPathUpdate) {
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        $parts = @($userPath -split ';' | Where-Object { $_ -and $_ -ne $binDir })
        [Environment]::SetEnvironmentVariable('Path', ($parts -join ';'), 'User')
    }
    $env:Path = (@($env:Path -split ';' | Where-Object { $_ -and $_ -ne $binDir }) -join ';')

    if (Test-Path -LiteralPath $InstallRoot) {
        Remove-Item -LiteralPath $InstallRoot -Recurse -Force
    }
    if ($RemoveCodexSkill) {
        foreach ($path in @($skillTarget) + $legacySkillTargets | Select-Object -Unique) {
            if (Test-Path -LiteralPath $path) {
                Remove-Item -LiteralPath $path -Recurse -Force
                Write-Host "Removed Codex Skill from $path"
            }
        }
    }

    Write-Host 'Terminal Context removed. Session data and PowerShell execution policy were not changed.'
}
