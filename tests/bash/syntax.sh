#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
bash -n "$repo_root/shell/term-context.bash"
bash -n "$repo_root/installers/install.sh"
bash -n "$repo_root/installers/uninstall.sh"
printf 'Bash syntax checks passed.\n'

data_root="${TERM_CONTEXT_DEV_DATA:-$(dirname "$repo_root")/data}"
binary_path="$repo_root/target/debug/tc"
if [[ ! -x "$binary_path" ]]; then
    binary_path="$data_root/target/debug/tc"
fi
if [[ ! -x "$binary_path" && -x "$data_root/target/debug/tc.exe" ]]; then
    binary_path="$data_root/target/debug/tc.exe"
fi
if [[ ! -x "$binary_path" && -x "$data_root/target/release/tc.exe" ]]; then
    binary_path="$data_root/target/release/tc.exe"
fi
if [[ ! -x "$binary_path" ]]; then
    printf 'A built tc binary is required for installer tests.\n' >&2
    exit 1
fi

sandbox_parent="$data_root/test-sandboxes"
mkdir -p "$sandbox_parent"
sandbox="$(mktemp -d "$sandbox_parent/bash-XXXXXXXX")"
case "$sandbox" in
    "$sandbox_parent"/bash-*) ;;
    *) printf 'Unsafe test sandbox path: %s\n' "$sandbox" >&2; exit 1 ;;
esac
trap 'rm -rf -- "$sandbox"' EXIT

test_home="$sandbox/home"
test_data="$sandbox/xdg-data"
mkdir -p "$test_home"
touch "$test_home/.bashrc"

HOME="$test_home" XDG_DATA_HOME="$test_data" TERM_CONTEXT_DATA_DIR="$sandbox/session-data" \
    "$repo_root/installers/install.sh" "$binary_path" --install-skill <<< "y"
HOME="$test_home" XDG_DATA_HOME="$test_data" TERM_CONTEXT_DATA_DIR="$sandbox/session-data" \
    "$repo_root/installers/install.sh" "$binary_path" --install-skill <<< "y"

test -x "$test_home/.local/bin/tc"
test -f "$test_data/term-context/shell/term-context.bash"
test -f "$test_home/.agents/skills/terminal-context/SKILL.md"
[[ "$(grep -c '^# >>> terminal-context >>>$' "$test_home/.bashrc")" -eq 1 ]]

HOME="$test_home" XDG_DATA_HOME="$test_data" \
    "$repo_root/installers/uninstall.sh" --remove-skill <<< "y"

test ! -e "$test_home/.local/bin/tc"
test ! -e "$test_home/.agents/skills/terminal-context"
! grep -q 'terminal-context' "$test_home/.bashrc"
printf 'Bash installer round-trip checks passed.\n'
