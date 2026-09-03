# CLI reference

Use shell integration commands when operating on the current terminal because they maintain `TERMCTX_ID` and refresh the visible title.

```text
tc-start [--name NAME] [--description TEXT]
tc-rename NAME
tc-describe TEXT
tc-refresh
tc-run COMMAND [ARGS...]
tc-dashboard
tc-done
```

The portable executable also provides:

```text
tc start [--name NAME] [--description TEXT] [--print-id] [--json]
tc list [--json] [--all]
tc show [--id ID] [--json]
tc title [--id ID] [--max-length N]
tc rename NAME [--id ID]
tc describe TEXT [--id ID]
tc heartbeat [--id ID] [--cwd PATH]
tc done [--id ID]
tc run [--id ID] -- COMMAND [ARGS...]
tc tui
tc doctor
```

IDs may be full UUIDs or six-character short IDs. When `--id` is omitted, commands use `TERMCTX_ID`.

`tc run` stores only a redacted summary. Even with redaction, avoid passing secrets on command lines when a safer environment-variable or secret-store mechanism exists.
