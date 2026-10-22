[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$BinaryPath,
    [switch]$NoAutoPrompt,
    [switch]$InstallCodexSkill,
    [switch]$ConfigureExecutionPolicy,
    [switch]$Force,
    [string]$InstallRoot,
    [string]$ProfilePath,
    [string]$SkillRoot,
    [string]$BuildTargetDir,
    [switch]$SkipPathUpdate
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$userHome = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)

if (-not $InstallRoot) {
    if (-not $env:LOCALAPPDATA) {
        throw 'LOCALAPPDATA is not set. Pass -InstallRoot explicitly.'
    }
    $InstallRoot = Join-Path $env:LOCALAPPDATA 'TermContext'
}
if (-not $ProfilePath) { $ProfilePath = $PROFILE.CurrentUserAllHosts }
if (-not $SkillRoot) { $SkillRoot = Join-Path $userHome '.agents\skills' }
if (-not $BuildTargetDir) {
    $dataRoot = if ($env:TERM_CONTEXT_DEV_DATA) {
        $env:TERM_CONTEXT_DEV_DATA
    } else {
        Join-Path (Split-Path -Parent $repoRoot) 'data'
    }
    $BuildTargetDir = Join-Path $dataRoot 'target'
}

function Resolve-TermContextBinary {
    param([string]$RequestedPath)

    if ($RequestedPath) {
        if (-not (Test-Path -LiteralPath $RequestedPath -PathType Leaf)) {
            throw "Binary not found: $RequestedPath"
        }
        return (Resolve-Path -LiteralPath $RequestedPath).Path
    }

    $candidates = @(
        (Join-Path $BuildTargetDir 'release\tc.exe'),
        (Join-Path $repoRoot 'target\release\tc.exe')
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    $cargoCommand = Get-Command cargo -ErrorAction SilentlyContinue
    if (-not $cargoCommand) {
        throw @"
tc.exe was not found and Cargo is unavailable.
Install Rust from https://rustup.rs/, or pass an existing executable with -BinaryPath.
"@
    }

    Write-Host "tc.exe was not found. Building a release binary in $BuildTargetDir ..."
    New-Item -ItemType Directory -Force -Path $BuildTargetDir | Out-Null
    & $cargoCommand.Source build --release --workspace --manifest-path (Join-Path $repoRoot 'Cargo.toml') --target-dir $BuildTargetDir
    if ($LASTEXITCODE -ne 0) { throw "Cargo build failed with exit code $LASTEXITCODE." }

    $builtBinary = Join-Path $BuildTargetDir 'release\tc.exe'
    if (-not (Test-Path -LiteralPath $builtBinary -PathType Leaf)) {
        throw "Cargo completed but tc.exe was not found at $builtBinary"
    }
    return (Resolve-Path -LiteralPath $builtBinary).Path
}

function Get-EffectiveExecutionPolicy {
    $policies = Get-ExecutionPolicy -List
    foreach ($scope in 'MachinePolicy', 'UserPolicy', 'CurrentUser', 'LocalMachine') {
        $value = ($policies | Where-Object Scope -eq $scope).ExecutionPolicy
        if ($value -and $value -ne 'Undefined') { return $value }
    }
    return 'Restricted'
}

function Test-LocalModulePolicy {
    param([string]$Policy)
    return $Policy -in @('Bypass', 'Unrestricted', 'RemoteSigned')
}

$BinaryPath = Resolve-TermContextBinary -RequestedPath $BinaryPath
$moduleSource = Join-Path $repoRoot 'shell\term-context.psm1'
$skillSource = Join-Path $repoRoot 'skills\terminal-context'
$binDir = Join-Path $InstallRoot 'bin'
$moduleDir = Join-Path $InstallRoot 'shell'
$installedBinary = Join-Path $binDir 'tc.exe'
$installedModule = Join-Path $moduleDir 'term-context.psm1'
$skillTarget = Join-Path $SkillRoot 'terminal-context'

& $BinaryPath --version | Out-Null
if ($LASTEXITCODE -ne 0) { throw "The selected tc.exe failed its version check: $BinaryPath" }

$currentPolicy = Get-EffectiveExecutionPolicy
$policyNeedsChange = -not (Test-LocalModulePolicy -Policy $currentPolicy)
$changeSummary = "Install Terminal Context to $InstallRoot and update $ProfilePath"
if ($InstallCodexSkill) { $changeSummary += "; install the Codex Skill to $skillTarget" }
if ($ConfigureExecutionPolicy -and $policyNeedsChange) {
    $changeSummary += '; set the CurrentUser PowerShell execution policy to RemoteSigned'
}

if (-not $Force) {
    $answer = Read-Host "$changeSummary? [y/N]"
    if ($answer -notmatch '^(y|yes)$') { return }
}

if ($PSCmdlet.ShouldProcess($InstallRoot, 'Install Terminal Context')) {
    if ($ConfigureExecutionPolicy -and $policyNeedsChange) {
        $policyList = Get-ExecutionPolicy -List
        $machinePolicy = ($policyList | Where-Object Scope -eq 'MachinePolicy').ExecutionPolicy
        $userPolicy = ($policyList | Where-Object Scope -eq 'UserPolicy').ExecutionPolicy
        if (($machinePolicy -and $machinePolicy -ne 'Undefined') -or ($userPolicy -and $userPolicy -ne 'Undefined')) {
            throw "Execution policy is controlled by Group Policy ($currentPolicy). Ask your administrator to allow local PowerShell modules."
        }
        Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
        $currentPolicy = Get-EffectiveExecutionPolicy
        if (-not (Test-LocalModulePolicy -Policy $currentPolicy)) {
            throw "Execution policy remains $currentPolicy after requesting RemoteSigned."
        }
        Write-Host 'PowerShell execution policy set to RemoteSigned for CurrentUser.'
    } elseif ($policyNeedsChange) {
        Write-Warning "PowerShell execution policy is $currentPolicy. The profile integration may be blocked in new terminals. Re-run with -ConfigureExecutionPolicy if you want the installer to set CurrentUser to RemoteSigned."
    }

    New-Item -ItemType Directory -Force -Path $binDir, $moduleDir | Out-Null
    Copy-Item -LiteralPath $BinaryPath -Destination $installedBinary -Force
    Copy-Item -LiteralPath $moduleSource -Destination $installedModule -Force
    Unblock-File -LiteralPath $installedBinary, $installedModule -ErrorAction SilentlyContinue

    $profileDir = Split-Path -Parent $ProfilePath
    if ($profileDir) { New-Item -ItemType Directory -Force -Path $profileDir | Out-Null }
    $existing = if (Test-Path -LiteralPath $ProfilePath) { Get-Content -Raw -LiteralPath $ProfilePath } else { '' }
    $start = '# >>> terminal-context >>>'
    $end = '# <<< terminal-context <<<'
    $escapedStart = [regex]::Escape($start)
    $escapedEnd = [regex]::Escape($end)
    $existing = [regex]::Replace($existing, "(?s)\r?\n?$escapedStart.*?$escapedEnd\r?\n?", "`r`n")
    $autoPrompt = if ($NoAutoPrompt) { '' } else { ' -AutoPrompt' }
    $moduleLiteral = $installedModule.Replace("'", "''")
    $binaryLiteral = $installedBinary.Replace("'", "''")
    $block = @"
$start
`$env:TERM_CONTEXT_BIN = '$binaryLiteral'
Import-Module '$moduleLiteral'
Initialize-TermContext$autoPrompt
$end
"@
    $profileContent = $existing.TrimEnd()
    if ($profileContent) { $profileContent += "`r`n" }
    Set-Content -LiteralPath $ProfilePath -Value ($profileContent + $block) -Encoding utf8

    if (-not $SkipPathUpdate) {
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        $parts = @($userPath -split ';' | Where-Object { $_ })
        if ($parts -notcontains $binDir) {
            [Environment]::SetEnvironmentVariable('Path', (($parts + $binDir) -join ';'), 'User')
        }
    }
    $currentParts = @($env:Path -split ';' | Where-Object { $_ })
    if ($currentParts -notcontains $binDir) { $env:Path = "$binDir;$env:Path" }

    if ($InstallCodexSkill) {
        New-Item -ItemType Directory -Force -Path $skillTarget | Out-Null
        Copy-Item -Path (Join-Path $skillSource '*') -Destination $skillTarget -Recurse -Force
        Write-Host "Installed personal Codex Skill to $skillTarget"

        $legacySkills = @((Join-Path $userHome '.codex\skills\terminal-context'))
        if ($env:CODEX_HOME) {
            $legacySkills += Join-Path $env:CODEX_HOME 'skills\terminal-context'
        }
        foreach ($legacySkill in $legacySkills | Select-Object -Unique) {
            if (Test-Path -LiteralPath $legacySkill) {
                Write-Warning "A legacy Skill copy still exists at $legacySkill. After verifying this install, remove it with uninstall.ps1 -RemoveCodexSkill or delete that exact directory."
            }
        }
    }

    $env:TERM_CONTEXT_BIN = $installedBinary
    Import-Module $installedModule -Force
    if (-not (Get-Command tc-start -ErrorAction SilentlyContinue)) {
        throw 'PowerShell module verification failed: tc-start is unavailable.'
    }
    & $installedBinary doctor
    if ($LASTEXITCODE -ne 0) { throw "Installed tc.exe failed 'tc doctor'." }

    Write-Host ''
    Write-Host 'Terminal Context installed and verified.'
    Write-Host 'Open a new PowerShell terminal, then try: tc --help, tc-start, tc-stop'
    Write-Host 'The integration will load automatically from your PowerShell profile.'
}
