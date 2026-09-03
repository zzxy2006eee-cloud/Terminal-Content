# shellcheck shell=bash

_term_context_find_bin() {
    if [[ -n "${TERM_CONTEXT_BIN:-}" && -x "$TERM_CONTEXT_BIN" ]]; then
        printf '%s\n' "$TERM_CONTEXT_BIN"
    elif command -v tc >/dev/null 2>&1; then
        command -v tc
    elif [[ -n "${WSL_DISTRO_NAME:-}" ]] && command -v tc.exe >/dev/null 2>&1; then
        command -v tc.exe
    else
        return 1
    fi
}

_term_context_set_title() {
    [[ -n "${TERMCTX_ID:-}" ]] || return 0
    local tc_bin title
    tc_bin="$(_term_context_find_bin)" || return 0
    title="$("$tc_bin" title --id "$TERMCTX_ID" --max-length 64 2>/dev/null)" || return 0
    printf '\033]0;%s\007' "$title"
}

tc-start() {
    local tc_bin session_id
    tc_bin="$(_term_context_find_bin)" || {
        printf 'Terminal Context executable not found. Set TERM_CONTEXT_BIN or run install.sh.\n' >&2
        return 127
    }

    local args=(start --print-id --pid "$$" --shell bash --cwd "$PWD")
    if [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
        args+=(--platform wsl --distro "$WSL_DISTRO_NAME")
    fi
    session_id="$("$tc_bin" "${args[@]}" "$@")" || return
    export TERMCTX_ID="$session_id"
    _term_context_set_title
    printf '%s\n' "$TERMCTX_ID"
}

tc-refresh() {
    [[ -n "${TERMCTX_ID:-}" ]] || return 0
    local tc_bin
    tc_bin="$(_term_context_find_bin)" || return 0
    "$tc_bin" heartbeat --id "$TERMCTX_ID" --cwd "$PWD" >/dev/null 2>&1 || return 0
    _term_context_set_title
}

tc-rename() {
    local tc_bin
    tc_bin="$(_term_context_find_bin)" || return 127
    "$tc_bin" rename --id "$TERMCTX_ID" "$@" && _term_context_set_title
}

tc-describe() {
    local tc_bin
    tc_bin="$(_term_context_find_bin)" || return 127
    "$tc_bin" describe --id "$TERMCTX_ID" "$@" && _term_context_set_title
}

tc-done() {
    [[ -n "${TERMCTX_ID:-}" ]] || return 0
    local tc_bin
    tc_bin="$(_term_context_find_bin)" || return 127
    "$tc_bin" done --id "$TERMCTX_ID" && unset TERMCTX_ID
}

tc-run() {
    [[ -n "${TERMCTX_ID:-}" ]] || {
        printf 'This shell is not attached. Run tc-start first.\n' >&2
        return 2
    }
    local tc_bin status
    tc_bin="$(_term_context_find_bin)" || return 127
    "$tc_bin" run --id "$TERMCTX_ID" -- "$@"
    status=$?
    _term_context_set_title
    return "$status"
}

tc-dashboard() {
    local tc_bin
    tc_bin="$(_term_context_find_bin)" || return 127
    "$tc_bin" tui
    _term_context_set_title
}

_term_context_prompt_hook() {
    local now="${SECONDS:-0}"
    if (( now - ${_TERM_CONTEXT_LAST_HEARTBEAT:-0} >= 5 )); then
        _TERM_CONTEXT_LAST_HEARTBEAT=$now
        tc-refresh
    else
        _term_context_set_title
    fi
}

_term_context_install_prompt_hook() {
    if declare -p PROMPT_COMMAND 2>/dev/null | grep -q 'declare -a'; then
        local item
        for item in "${PROMPT_COMMAND[@]}"; do
            [[ "$item" == "_term_context_prompt_hook" ]] && return
        done
        PROMPT_COMMAND+=("_term_context_prompt_hook")
    elif [[ "${PROMPT_COMMAND:-}" != *"_term_context_prompt_hook"* ]]; then
        PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND;}_term_context_prompt_hook"
    fi
}

_term_context_maybe_start() {
    [[ $- == *i* ]] || return 0
    [[ -z "${TERMCTX_ID:-}" ]] || return 0
    [[ "${TERM_CONTEXT_AUTO_PROMPT:-0}" == "1" ]] || return 0
    [[ -z "${CI:-}" && -z "${SSH_CONNECTION:-}" && -z "${TERM_CONTEXT_DISABLE_AUTO_PROMPT:-}" ]] || return 0
    [[ -t 0 && -t 1 ]] || return 0
    tc-start >/dev/null
}

_term_context_install_prompt_hook
_term_context_maybe_start
