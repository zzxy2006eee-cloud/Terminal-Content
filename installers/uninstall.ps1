[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$RemoveCodexSkill,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$installRoot = Join-Path $env:LOCALAPPDATA 'TermContext'
$binDir = Join-Path $installRoot 'bin'
$profilePath = $PROFILE.CurrentUserAllHosts

if (-not $Force) {
    $answer = Read-Host "Remove Terminal Context and its PowerShell profile block? Session data is kept. [y/N]"
    if ($answer -notmatch '^(y|yes)$') { return }
}

if ($PSCmdlet.ShouldProcess($installRoot, 'Uninstall Terminal Context')) {
    if (Test-Path -LiteralPath $profilePath) {
        $content = Get-Content -Raw -LiteralPath $profilePath
        $start = [regex]::Escape('# >>> terminal-context >>>')
        $end = [regex]::Escape('# <<< terminal-context <<<')
        $content = [regex]::Replace($content, "(?s)\r?\n?$start.*?$end\r?\n?", "`r`n")
        Set-Content -LiteralPath $profilePath -Value $content.TrimEnd() -Encoding utf8
    }
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $parts = @($userPath -split ';' | Where-Object { $_ -and $_ -ne $binDir })
    [Environment]::SetEnvironmentVariable('Path', ($parts -join ';'), 'User')
    if (Test-Path -LiteralPath $installRoot) {
        Remove-Item -LiteralPath $installRoot -Recurse -Force
    }
    if ($RemoveCodexSkill) {
        $codexRoot = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }
        $skillTarget = Join-Path $codexRoot 'skills\terminal-context'
        if (Test-Path -LiteralPath $skillTarget) {
            Remove-Item -LiteralPath $skillTarget -Recurse -Force
        }
    }
    Write-Host 'Terminal Context removed. Session data was not deleted.'
}
