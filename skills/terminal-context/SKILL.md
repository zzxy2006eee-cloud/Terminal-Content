---
name: terminal-context
description: Name, describe, list, update, and monitor terminal work sessions with the tc command. Use when opening project terminals, organizing multiple shells, identifying what a terminal is doing, or tracking a command in a managed terminal. Do not use for ordinary one-off shell commands that do not need session management.
---

# Terminal Context

Use `tc` to give terminal sessions concise, useful work context.

## Workflow

1. Check availability with `tc doctor`. If it is missing, explain that Terminal Context must be built or installed; do not modify a shell profile without the user's permission.
2. When the user asks to create or organize a terminal, derive a short name and purpose-focused description from their request. Ask only if the purpose is materially ambiguous.
3. In an integrated shell, prefer `tc-start`, which sets `TERMCTX_ID` in the parent shell and applies the terminal title. Do not substitute plain `tc start` when later commands must address the same current session.
4. Use `tc-run <command>` for commands whose running and exit status should be tracked. Preserve the user's command and arguments.
5. Verify mutations with `tc show --json` or `tc list --json` before reporting success.

Never store credentials, tokens, private keys, connection strings, or other secrets in a session name or description. Do not terminate a shell or process unless the user explicitly requests it; `tc done` only marks the session complete.

For exact commands and JSON behavior, read [references/cli.md](references/cli.md). For PowerShell, Bash, WSL, title, and installation decisions, read [references/platform-support.md](references/platform-support.md).
