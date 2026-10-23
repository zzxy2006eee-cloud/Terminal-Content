Set-StrictMode -Version Latest

$script:TermContextExecutable = if ($env:TERM_CONTEXT_BIN) {
    $env:TERM_CONTEXT_BIN
} else {
    $installed = Join-Path $env:LOCALAPPDATA 'TermContext\bin\tc.exe'
    if (Test-Path -LiteralPath $installed) { $installed } else { 'tc' }
}

function Get-TermContextExecutable {
    $command = Get-Command $script:TermContextExecutable -ErrorAction SilentlyContinue
    if (-not $command) {
        throw "Terminal Context executable was not found. Set TERM_CONTEXT_BIN or run the installer."
    }
    return $command.Source
}

function Invoke-TermContextUtf8Text {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Executable,
        [Parameter(Mandatory)][string[]]$Arguments
    )

    $originalOutputEncoding = [Console]::OutputEncoding
    $result = $null
    $exitCode = 1
    try {
        # Rust writes UTF-8 when stdout is captured. Windows PowerShell 5.1
        # otherwise decodes those bytes with the active legacy console code page.
        [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
        $result = & $Executable @Arguments 2>$null
        $exitCode = $LASTEXITCODE
    } finally {
        [Console]::OutputEncoding = $originalOutputEncoding
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Text = ($result -join [Environment]::NewLine)
    }
}

function Set-TermContextTitle {
    if (-not $env:TERMCTX_ID) { return }
    $executable = Get-TermContextExecutable
    $result = Invoke-TermContextUtf8Text -Executable $executable -Arguments @(
        'title', '--id', $env:TERMCTX_ID, '--max-length', '64'
    )
    if ($result.ExitCode -eq 0 -and $result.Text) {
        try { $Host.UI.RawUI.WindowTitle = $result.Text.Trim() } catch { }
    }
}

function Start-TermContext {
    [CmdletBinding()]
    param(
        [string]$Name,
        [string]$Description,
        [string]$Directory = (Get-Location).Path
    )

    $executable = Get-TermContextExecutable
    $arguments = @(
        'start', '--print-id', '--pid', $PID,
        '--shell', 'powershell', '--cwd', $Directory
    )
    if ($Name) { $arguments += @('--name', $Name) }
    if ($PSBoundParameters.ContainsKey('Description')) {
        $arguments += @('--description', $Description)
    }

    $sessionId = & $executable @arguments
    if ($LASTEXITCODE -ne 0 -or -not $sessionId) {
        throw 'Terminal Context could not create the session.'
    }
    $env:TERMCTX_ID = $sessionId.Trim()
    Set-TermContextTitle
    return $env:TERMCTX_ID
}

function Update-TermContext {
    if (-not $env:TERMCTX_ID) { return }
    $executable = Get-TermContextExecutable
    & $executable heartbeat --id $env:TERMCTX_ID --cwd (Get-Location).Path *> $null
    Set-TermContextTitle
}

function Set-TermContextName {
    [CmdletBinding()]
    param([Parameter(Mandatory, Position = 0)][string]$Name)
    $executable = Get-TermContextExecutable
    & $executable rename --id $env:TERMCTX_ID $Name
    if ($LASTEXITCODE -eq 0) { Set-TermContextTitle }
}

function Set-TermContextDescription {
    [CmdletBinding()]
    param([Parameter(Mandatory, Position = 0)][string]$Description)
    $executable = Get-TermContextExecutable
    & $executable describe --id $env:TERMCTX_ID $Description
    if ($LASTEXITCODE -eq 0) { Set-TermContextTitle }
}

function Stop-TermContext {
    if (-not $env:TERMCTX_ID) { return }
    $executable = Get-TermContextExecutable
    & $executable done --id $env:TERMCTX_ID
    if ($LASTEXITCODE -eq 0) {
        Remove-Item Env:TERMCTX_ID -ErrorAction SilentlyContinue
    }
}

function Invoke-TermContextCommand {
    if (-not $env:TERMCTX_ID) {
        throw 'This shell is not attached. Run tc-start first.'
    }
    $commandArguments = @($args)
    if ($commandArguments.Count -eq 0) {
        throw 'A command is required.'
    }
    $executable = Get-TermContextExecutable
    & $executable run --id $env:TERMCTX_ID -- @commandArguments
    $exitCode = $LASTEXITCODE
    Set-TermContextTitle
    $global:LASTEXITCODE = $exitCode
}

function Open-TermContextDashboard {
    $executable = Get-TermContextExecutable
    & $executable tui
    Set-TermContextTitle
}

function Initialize-TermContext {
    [CmdletBinding()]
    param([switch]$AutoPrompt)

    if ($env:TERMCTX_ID) {
        Update-TermContext
        return
    }
    if (-not $AutoPrompt) { return }
    if ($env:CI -or $env:SSH_CONNECTION -or $env:TERM_CONTEXT_DISABLE_AUTO_PROMPT) { return }
    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) { return }
    if ($Host.Name -notmatch 'ConsoleHost|Visual Studio Code Host') { return }

    # Profiles also run for powershell.exe -Command/-File. Prompting there can
    # block automation indefinitely and leave tc.exe locked during upgrades.
    $nonInteractiveLaunchOptions = @('c', 'command', 'e', 'enc', 'encodedcommand', 'f', 'file')
    foreach ($processArgument in [Environment]::GetCommandLineArgs() | Select-Object -Skip 1) {
        $normalizedArgument = $processArgument.TrimStart('-', '/').ToLowerInvariant()
        if ($normalizedArgument -in $nonInteractiveLaunchOptions) { return }
    }

    try { Start-TermContext | Out-Null } catch {
        Write-Warning "Terminal Context startup skipped: $($_.Exception.Message)"
    }
}

Set-Alias -Name tc-start -Value Start-TermContext
Set-Alias -Name tc-refresh -Value Update-TermContext
Set-Alias -Name tc-rename -Value Set-TermContextName
Set-Alias -Name tc-describe -Value Set-TermContextDescription
Set-Alias -Name tc-done -Value Stop-TermContext
Set-Alias -Name tc-run -Value Invoke-TermContextCommand
Set-Alias -Name tc-dashboard -Value Open-TermContextDashboard

Export-ModuleMember -Function @(
    'Start-TermContext',
    'Update-TermContext',
    'Set-TermContextName',
    'Set-TermContextDescription',
    'Stop-TermContext',
    'Invoke-TermContextCommand',
    'Open-TermContextDashboard',
    'Initialize-TermContext',
    'Set-TermContextTitle'
) -Alias @('tc-start', 'tc-refresh', 'tc-rename', 'tc-describe', 'tc-done', 'tc-run', 'tc-dashboard')
