# Platform support

## PowerShell on Windows

Import `shell/term-context.psm1`. `Start-TermContext` registers the parent PowerShell PID, sets `TERMCTX_ID`, and sets `$Host.UI.RawUI.WindowTitle`.

The module decodes captured `tc title` output as UTF-8 and restores the original console output encoding afterward. This prevents mojibake in Windows PowerShell 5.1 terminals that use a legacy code page such as CP936.

Automatic naming prompts run only for an interactive shell launch. The integration skips them for `powershell.exe -Command`, `-EncodedCommand`, and `-File` automation so background commands do not block or leave `tc.exe` running.

Windows Terminal must allow application-controlled titles. A profile configured with `suppressApplicationTitle: true` prevents the visible tab title from following the shell title.

## Bash on Linux

Source `shell/term-context.bash`. The integration composes with the existing `PROMPT_COMMAND`, sends a throttled heartbeat, and reapplies the title with an OSC title sequence. It does not prompt in non-interactive, redirected, CI, inherited, or SSH shells.

## WSL

The Bash integration prefers native `tc`. If it is unavailable and `tc.exe` is on the Windows PATH, it calls that executable through WSL interoperability. This keeps Windows and WSL session records in the Windows database while preserving the WSL path, PID, and distribution metadata.

Do not share a live SQLite database file directly between Windows and Linux processes through `/mnt/c`. Prefer the Windows executable fallback or separate platform-local databases.

## Installation safety

Installers add only a marked `terminal-context` block to the PowerShell profile or `.bashrc`. Obtain permission before executing an installer because it modifies files outside the current repository. Uninstallers remove only the marked block and installed binaries; they retain session data.

On Windows, the installer keeps an existing `tc.exe` when its SHA-256 hash already matches the requested binary, allowing the PowerShell module and Skill to be refreshed even while that identical executable is in use. A different locked binary still requires the user to close terminals and retry.
