#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
binary_path="${1:-$repo_root/target/release/tc}"
install_skill="${2:-}"
install_root="${XDG_DATA_HOME:-$HOME/.local/share}/term-context"
bin_dir="${HOME}/.local/bin"
integration="$install_root/shell/term-context.bash"
bashrc="${HOME}/.bashrc"

if [[ ! -x "$binary_path" ]]; then
    printf 'Binary not found or not executable: %s\n' "$binary_path" >&2
    exit 1
fi

read -r -p "Install Terminal Context and update $bashrc? [y/N] " answer
[[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]] || exit 0

mkdir -p "$install_root/shell" "$bin_dir"
install -m 755 "$binary_path" "$bin_dir/tc"
install -m 644 "$repo_root/shell/term-context.bash" "$integration"
touch "$bashrc"

python3 - "$bashrc" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
text = re.sub(r"\n?# >>> terminal-context >>>.*?# <<< terminal-context <<<\n?", "\n", text, flags=re.S)
block = """# >>> terminal-context >>>
export TERM_CONTEXT_AUTO_PROMPT=1
source \"${XDG_DATA_HOME:-$HOME/.local/share}/term-context/shell/term-context.bash\"
# <<< terminal-context <<<
"""
path.write_text(text.rstrip() + "\n" + block, encoding="utf-8")
PY

if [[ "$install_skill" == "--install-skill" ]]; then
    skill_target="$HOME/.agents/skills/terminal-context"
    mkdir -p "$skill_target"
    cp -R "$repo_root/skills/terminal-context/." "$skill_target/"
    printf 'Installed personal Codex skill to %s.\n' "$skill_target"
    legacy_skill="$HOME/.codex/skills/terminal-context"
    if [[ -d "$legacy_skill" ]]; then
        printf 'Warning: a legacy Skill copy still exists at %s.\n' "$legacy_skill" >&2
    fi
    if [[ -n "${CODEX_HOME:-}" && -d "$CODEX_HOME/skills/terminal-context" ]]; then
        printf 'Warning: a legacy Skill copy still exists at %s.\n' "$CODEX_HOME/skills/terminal-context" >&2
    fi
fi

printf 'Installed. Run: source %q\n' "$bashrc"
