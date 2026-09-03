# Terminal Context

Terminal Context (`tc`) names and describes terminal sessions so you can see what each shell is responsible for. It supports PowerShell on Windows, Bash on Linux, and Bash inside WSL.

The first nine planned milestones are included:

- Rust workspace and SQLite session storage
- `start`, `list`, `show`, `rename`, `describe`, `heartbeat`, and `done`
- safe title formatting and command-line secret redaction
- PowerShell integration
- Bash and WSL integration
- idempotent installers and uninstallers
- `tc run` command lifecycle tracking
- a packaged Codex skill under `skills/terminal-context`
- an interactive `tc tui` session manager

The mouse-hover overlay is intentionally reserved for the next milestone because it requires terminal- and desktop-specific APIs.

## Build

```powershell
cargo build --release --workspace
```

For a build that keeps generated files outside this repository:

```powershell
./scripts/dev.ps1 test
./scripts/dev.ps1 build
```

By default that script places Cargo state under the sibling directory `../data`. Override it with `TERM_CONTEXT_DEV_DATA`.

## Quick start

Without installing shell hooks:

```powershell
$env:TERM_CONTEXT_DATA_DIR = "$PWD/.term-context-test"
$id = ./target/release/tc.exe start --name "API" --description "Debug login" --print-id
$env:TERMCTX_ID = $id
./target/release/tc.exe list
./target/release/tc.exe run -- pwsh -NoProfile -Command "Write-Output ok"
./target/release/tc.exe tui
```

Install PowerShell integration:

```powershell
./installers/install.ps1 -BinaryPath ../data/target/release/tc.exe -InstallCodexSkill
```

Install Bash integration after building on Linux:

```bash
./installers/install.sh ./target/release/tc --install-skill
```

After installation, a new interactive terminal asks for a work name and description. Useful shell commands are:

```text
tc-start
tc-refresh
tc-rename "New name"
tc-describe "New description"
tc-run <command> [args...]
tc-dashboard
tc-done
```

Set `TERM_CONTEXT_DISABLE_AUTO_PROMPT=1` to suppress startup prompting for a shell. CI, redirected, inherited, and SSH shells skip the prompt automatically.

## WSL

The Bash integration prefers a native `tc`, then falls back to `tc.exe` when running inside WSL. Using `tc.exe` stores Windows and WSL sessions in the same Windows database. The WSL shell passes its Linux working directory and distribution name as metadata.

## Data and privacy

The database defaults to the platform-local application data directory. Set `TERM_CONTEXT_DATA_DIR` or pass `--database` to choose another location. `tc run` redacts common password, token, secret, and API-key arguments before storing the command summary.

## TUI keys

```text
↑ / k    previous session
↓ / j    next session
Enter    show details
r        rename
d        edit description
x        mark done
q        quit
```
