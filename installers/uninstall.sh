#!/usr/bin/env bash
set -euo pipefail

install_root="${XDG_DATA_HOME:-$HOME/.local/share}/term-context"
bashrc="${HOME}/.bashrc"
remove_skill="${1:-}"

read -r -p "Remove Terminal Context integration and binaries? Session data is kept. [y/N] " answer
[[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]] || exit 0

if [[ -f "$bashrc" ]]; then
    python3 - "$bashrc" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
text = re.sub(r"\n?# >>> terminal-context >>>.*?# <<< terminal-context <<<\n?", "\n", text, flags=re.S)
path.write_text(text.rstrip() + "\n", encoding="utf-8")
PY
fi

rm -f -- "$HOME/.local/bin/tc"
rm -rf -- "$install_root/shell"
if [[ "$remove_skill" == "--remove-skill" ]]; then
    rm -rf -- "${CODEX_HOME:-$HOME/.codex}/skills/terminal-context"
fi
printf 'Terminal Context removed. Database retained under %s.\n' "$install_root"
