$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$modulePath = Join-Path $repoRoot 'shell\term-context.psm1'
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
    throw "A built tc.exe is required for the title encoding test. Checked: $($binaryCandidates -join ', ')"
}

$sandboxParent = Join-Path $dataRoot 'test-sandboxes'
$sandbox = Join-Path $sandboxParent ("title-encoding-" + [guid]::NewGuid().ToString('N'))
$previousBinary = $env:TERM_CONTEXT_BIN
$previousDataDir = $env:TERM_CONTEXT_DATA_DIR
$previousSessionId = $env:TERMCTX_ID
$previousOutputEncoding = [Console]::OutputEncoding
$previousTitle = $Host.UI.RawUI.WindowTitle

try {
    New-Item -ItemType Directory -Force -Path $sandbox | Out-Null
    $env:TERM_CONTEXT_BIN = $binaryPath
    $env:TERM_CONTEXT_DATA_DIR = Join-Path $sandbox 'session-data'
    Remove-Module term-context -Force -ErrorAction SilentlyContinue
    Import-Module $modulePath -Force

    $legacyEncoding = [Text.Encoding]::GetEncoding(936)
    [Console]::OutputEncoding = $legacyEncoding
    $name = -join ([char[]]@(0x7F16, 0x7801, 0x6D4B, 0x8BD5))
    $description = -join ([char[]]@(0x4E2D, 0x6587, 0x6807, 0x9898))
    $sessionId = tc-start -Name $name -Description $description
    if (-not $sessionId) { throw 'tc-start did not create the encoding test session.' }

    $statusSymbol = [char]0x25CB
    $separator = [char]0xFF5C
    $expectedTitle = "$statusSymbol $name$separator$description$separator$($sessionId.Substring(0, 6).ToUpperInvariant())"
    $actualTitle = $Host.UI.RawUI.WindowTitle
    if ($actualTitle -ne $expectedTitle) {
        throw "UTF-8 title mismatch. Expected '$expectedTitle', found '$actualTitle'."
    }
    if ([Console]::OutputEncoding.CodePage -ne $legacyEncoding.CodePage) {
        throw 'PowerShell module did not restore the original console output encoding.'
    }

    tc-done | Out-Null
    Write-Host 'Windows PowerShell CP936 UTF-8 title check passed.'
} finally {
    Remove-Module term-context -Force -ErrorAction SilentlyContinue
    [Console]::OutputEncoding = $previousOutputEncoding
    try { $Host.UI.RawUI.WindowTitle = $previousTitle } catch { }

    foreach ($entry in @(
        @{ Name = 'TERM_CONTEXT_BIN'; Value = $previousBinary },
        @{ Name = 'TERM_CONTEXT_DATA_DIR'; Value = $previousDataDir },
        @{ Name = 'TERMCTX_ID'; Value = $previousSessionId }
    )) {
        if ($null -eq $entry.Value) {
            Remove-Item "Env:$($entry.Name)" -ErrorAction SilentlyContinue
        } else {
            Set-Item "Env:$($entry.Name)" $entry.Value
        }
    }

    $resolvedParent = [IO.Path]::GetFullPath($sandboxParent).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $resolvedSandbox = [IO.Path]::GetFullPath($sandbox)
    if ($resolvedSandbox.StartsWith($resolvedParent, [StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $resolvedSandbox)) {
        Remove-Item -LiteralPath $resolvedSandbox -Recurse -Force
    }
}
