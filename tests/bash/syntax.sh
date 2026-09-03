#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
bash -n "$repo_root/shell/term-context.bash"
bash -n "$repo_root/installers/install.sh"
bash -n "$repo_root/installers/uninstall.sh"
printf 'Bash syntax checks passed.\n'
