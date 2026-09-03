[CmdletBinding()]
param(
    [ValidateSet('check', 'test', 'build', 'fmt', 'clippy')]
    [string]$Action = 'test'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$dataRoot = if ($env:TERM_CONTEXT_DEV_DATA) {
    $env:TERM_CONTEXT_DEV_DATA
} else {
    Join-Path (Split-Path -Parent $repoRoot) 'data'
}

$env:CARGO_HOME = Join-Path $dataRoot 'cargo-home'
$env:RUSTUP_HOME = Join-Path $dataRoot 'rustup-home'
$env:CARGO_TARGET_DIR = Join-Path $dataRoot 'target'
$cargo = Join-Path $env:CARGO_HOME 'bin\cargo.exe'

if (-not (Test-Path -LiteralPath $cargo)) {
    $cargo = (Get-Command cargo -ErrorAction Stop).Source
}

Push-Location $repoRoot
try {
    switch ($Action) {
        'check' { & $cargo check --workspace }
        'test' { & $cargo test --workspace }
        'build' { & $cargo build --release --workspace }
        'fmt' { & $cargo fmt --all -- --check }
        'clippy' { & $cargo clippy --workspace --all-targets -- -D warnings }
    }
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} finally {
    Pop-Location
}
