#!/usr/bin/env bash
set -euo pipefail

tc_bin="${1:-tc}"
"$tc_bin" doctor
"$tc_bin" list --json >/dev/null
printf 'Terminal Context is available.\n'
