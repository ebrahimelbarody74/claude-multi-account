# claude-multi-account

Run several **Claude Code** accounts side by side and switch between them
instantly — no `logout` / `login` cycle, no lost sessions.

> بالعربية: [README.ar.md](README.ar.md)

```console
$ claude-account list
ACCOUNT            EMAIL                              PLAN       STATUS
default            me@personal.com                    max        logged in *
work               me@company.com                     max        logged in
client             hello@client.io                    pro        logged in

$ claude-account work            # a Claude Code session as me@company.com
$ claude-account client -p "review this PR"
$ claude-account default         # your normal Claude Code, untouched
```

Each account keeps its **own** login, settings, MCP servers, projects and
history. Signing in to one never signs you out of another.

---

## Contents

- [Why](#why)
- [Install](#install)
- [Commands](#commands)
- [Examples](#examples)
- [How it works](#how-it-works)
- [Security](#security)
- [Troubleshooting](#troubleshooting)
- [Uninstall](#uninstall)
- [License](#license)

---

## Why

Claude Code stores one signed-in identity at a time. If you have a work account
and a personal account, switching means logging out and back in — and losing
that session's local state each way.

`claude-account` gives every account its own **`CLAUDE_CONFIG_DIR`**. Switching
becomes a single word on the command line, and all accounts stay signed in at
the same time.

**It does not touch `HOME`.** Some multi-account tricks re-point `HOME` at a
fake home directory; on macOS that breaks Keychain access and produces confusing
sign-in failures. This tool only ever sets one environment variable, for one
child process.

---

## Install

**Requirements:** [Claude Code](https://claude.com/claude-code) already
installed, and either macOS/Linux with bash, or Windows with PowerShell 5.1+.

### macOS and Linux

```bash
curl -fsSL https://raw.githubusercontent.com/ebrahimelbarody74/claude-multi-account/main/install.sh | bash
```

Installs `claude-account` into `~/.local/bin` and adds that directory to your
`PATH` if it is not there already.

<details>
<summary>Install options</summary>

```bash
# Somewhere else
INSTALL_DIR=/usr/local/bin curl -fsSL .../install.sh | bash

# Do not edit any shell rc file
NO_MODIFY_PATH=1 curl -fsSL .../install.sh | bash

# From a clone (no download)
git clone https://github.com/ebrahimelbarody74/claude-multi-account
cd claude-multi-account && ./install.sh
```
</details>

### Windows (PowerShell)

```powershell
irm https://raw.githubusercontent.com/ebrahimelbarody74/claude-multi-account/main/install.ps1 | iex
```

Installs into `%LOCALAPPDATA%\Programs\claude-multi-account` and adds it to your
user `PATH`. No administrator rights are needed. Open a new terminal afterwards.

<details>
<summary>Install options</summary>

```powershell
# Somewhere else, and leave PATH alone
.\install.ps1 -InstallDir "D:\tools\claude-account" -NoModifyPath
```

If PowerShell refuses to run the script, allow local scripts for your user:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```
</details>

---

## Commands

| Command | What it does |
| --- | --- |
| `claude-account add work` | Create the `work` account and sign in to it |
| `claude-account add work --no-login` | Create it now, sign in later |
| `claude-account list` | Every account with its email, plan and login status |
| `claude-account work` | Run Claude Code as `work` |
| `claude-account use work` | The same thing, written out |
| `claude-account default` | Run plain Claude Code, with `CLAUDE_CONFIG_DIR` unset |
| `claude-account status work` | Email, plan, org and login status for one account |
| `claude-account remove work` | Delete that stored account (asks first; `--yes` skips) |
| `claude-account rename work company` | Rename an account, session intact |
| `claude-account link work claude1` | Create a short command: `claude1` now runs the `work` account |
| `claude-account links` | List the shortcuts |
| `claude-account unlink claude1` | Remove a shortcut |
| `claude-account path work` | Print the account's config directory |
| `claude-account env work` | Print the `export` line, for your own scripts |
| `claude-account shell work` | Open a subshell already pointed at `work` |
| `claude-account help` / `version` | Help and version |

Everything after the account name is handed to `claude` untouched:

```bash
claude-account work -p "summarise the README"  --model opus
claude-account work mcp list
claude-account work auth status
```

---

## Examples

### macOS / Linux

```bash
# One-time setup: two accounts, two different emails
claude-account add work        # opens the sign-in flow for the work email
claude-account add personal    # opens the sign-in flow for the personal email

# Check who is who
claude-account list
# ACCOUNT            EMAIL                              PLAN       STATUS
# default            me@personal.com                    max        logged in *
# work               me@company.com                     max        logged in
# personal           side@project.dev                   pro        logged in

# Day-to-day
cd ~/work/api    && claude-account work        # interactive session, work identity
cd ~/side/blog   && claude-account personal    # interactive session, personal identity

# One-shot prompts
claude-account work -p "explain this stack trace" 
claude-account personal --model opus

# Your original, untouched installation
claude-account default

# Stay on one account for a whole terminal session
claude-account shell work
#   ... every `claude` in this subshell is the work account ...
exit

# Or wire it into your own script, without eval
export CLAUDE_CONFIG_DIR="$(claude-account path work)"
claude -p "run the work-account task"

# Housekeeping
claude-account status work
claude-account rename work company
claude-account remove personal
```

### Shorter commands

`link` writes a tiny executable next to `claude-account`, so the shortcut works
everywhere — scripts, cron, any shell — not just an interactive session:

```bash
claude-account link work claude1
claude-account link personal claude2
claude-account link default claude0

claude1                       # a session on the work account
claude1 -p "fix this test"    # arguments still pass through
claude2 --model opus

claude-account links          # SHORTCUT  ACCOUNT
                              # claude1   work
                              # claude2   personal
claude-account unlink claude1
```

A shell alias also works, but only inside an interactive shell of that type:

```bash
alias cw='claude-account work'
```

> **A shell alias beats a shortcut.** If `claude1` is already an `alias` in your
> `~/.zshrc`, the alias wins and the shortcut is never reached. Delete the alias
> first, or `hash -r` after removing it.

### Windows (PowerShell)

```powershell
# One-time setup
claude-account add work
claude-account add personal

# Check who is who
claude-account list

# Day-to-day
Set-Location C:\src\api ; claude-account work
Set-Location C:\src\blog; claude-account personal

# One-shot prompts
claude-account work -p "explain this stack trace"
claude-account personal --model opus

# Your original, untouched installation
claude-account default

# Stay on one account for a whole terminal session
claude-account shell work
#   ... every `claude` in this child shell is the work account ...
exit

# Or wire it into your own script, without Invoke-Expression
$env:CLAUDE_CONFIG_DIR = claude-account path work
claude -p "run the work-account task"

# Housekeeping
claude-account status work
claude-account rename work company
claude-account remove personal
```

### Shorter commands

```powershell
claude-account link work claude1
claude-account link personal claude2

claude1                       # a session on the work account
claude1 -p "fix this test"    # arguments still pass through

claude-account links
claude-account unlink claude1
```

`link` writes a `.cmd` shim next to `claude-account`, so it works from
PowerShell and `cmd.exe` alike. A `$PROFILE` function also works, inside
PowerShell only:

```powershell
function cw { claude-account work @args }
```

> **If PowerShell swallows a flag.** PowerShell parses `-something` before your
> script sees it. `claude-account work -p "hi"` works, but for an unusual flag
> you can stop PowerShell's parsing with `--%`:
>
> ```powershell
> claude-account work --% -p "hi" --model opus
> ```

---

## How it works

Claude Code reads its entire state — credentials, settings, MCP config, project
history — from the directory named by the `CLAUDE_CONFIG_DIR` environment
variable, defaulting to `~/.claude`.

So an account is just a directory:

```
~/.claude-accounts/            (0700)
├── work/                      → CLAUDE_CONFIG_DIR for "work"
├── personal/                  → CLAUDE_CONFIG_DIR for "personal"
└── client/                    → CLAUDE_CONFIG_DIR for "client"
```

On Windows the same tree lives at `%USERPROFILE%\.claude-accounts\`.

Running an account is exactly this, and nothing more:

```bash
CLAUDE_CONFIG_DIR=~/.claude-accounts/work claude "$@"
```

Three details worth knowing:

- **`HOME` is never modified.** The macOS Keychain keeps working normally, so
  sign-in behaves the same as a plain Claude Code install.
- **`default` is a real, reserved account name.** It runs Claude Code with
  `CLAUDE_CONFIG_DIR` explicitly *removed*, so it is your existing `~/.claude`
  installation — even if your shell already exported that variable.
- **There is no "current account" state file.** The account is chosen per
  command, so two terminals can use two different accounts at the same time.

### Environment variables

| Variable | Default | Meaning |
| --- | --- | --- |
| `CLAUDE_ACCOUNTS_HOME` | `~/.claude-accounts` | Where accounts are stored |
| `CLAUDE_BIN` | `claude` | The Claude Code executable to run |
| `NO_COLOR` | unset | Set to disable coloured output (bash) |

---

## Security

This tool is deliberately boring. It stores nothing of its own.

- **No credentials in this repository, and none written by this tool.**
  Tokens are handled entirely by Claude Code, inside each account's own config
  directory (and, on macOS, the Keychain). `claude-account` never reads, copies,
  prints or transmits them.
- **No `eval`, and no `Invoke-Expression`.** Arguments are passed to `claude` as
  a real argument vector (`exec env … claude "$@"` / `& claude @args`), so
  nothing you type is re-parsed as shell code. `claude-account env` *prints* an
  export line for you to use; it never runs it.
- **Path traversal is blocked at the name.** Account names must match
  `^[A-Za-z0-9._-]+$`, may not start with `.` or `-`, may not be `.` or `..`,
  and are capped at 64 characters. `../`, `/`, `\`, `~`, spaces, shell
  metacharacters and Windows device names (`CON`, `NUL`, `LPT1`, …) are all
  rejected before any path is built.
- **Deletion is guarded twice.** `remove` resolves the directory, then refuses
  unless its parent is exactly the accounts root — and refuses outright for
  `$HOME`, `~/.claude`, the accounts root itself and `/`. It also asks for
  confirmation unless you pass `--yes`, and refuses entirely when there is no
  terminal to ask on.
- **`~/.claude` is never written or deleted.** The only way this tool touches
  your original installation is by running `claude` with no `CLAUDE_CONFIG_DIR`.
- **Uninstalling never deletes accounts.** The uninstallers remove the
  executable and the `PATH` entry, then print where your accounts still are so
  you can delete them yourself if you want to.
- **Account directories are created `0700`** (owner-only) on macOS and Linux.
- **Shortcuts cannot hijack a command.** `link` refuses reserved names — `claude`
  above all, since a shim by that name would call itself forever — refuses to
  overwrite any file it did not write, and refuses a name that already resolves
  to an unrelated command on your `PATH`. `unlink` deletes only files carrying
  its own marker.

The test suites include the hostile-input cases above; see
[`tests/`](tests/).

---

## Troubleshooting

**`claude-account: command not found` right after installing.**
The install directory is not on this shell's `PATH` yet. Open a new terminal, or
run `export PATH="$HOME/.local/bin:$PATH"` (PowerShell: open a new terminal —
the user `PATH` was updated).

**`'claude' was not found on PATH`.**
Install Claude Code first: <https://claude.com/claude-code>. If it lives
somewhere unusual, point at it: `CLAUDE_BIN=/opt/claude/bin/claude claude-account list`.

**`list` shows an account as `logged out`.**
That account's session expired or was never created. Sign in again with
`claude-account <name>` — it will prompt.

**Two accounts show the same email.**
You signed in to both with the same address. Remove one
(`claude-account remove <name>`) and re-add it with the other email.

**PowerShell: "cannot be loaded because running scripts is disabled".**
`Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`. The installed `.cmd`
shim already passes `-ExecutionPolicy Bypass`, so this normally only affects
running `claude-account.ps1` directly.

**PowerShell: a flag is being eaten.**
Use the stop-parsing token: `claude-account work --% -p "hi"`.

**My shortcut runs the wrong account.**
A shell alias of the same name takes priority over the shim. Check with
`type claude1` (zsh/bash) or `Get-Command claude1` (PowerShell); if it reports
an alias, remove it from your `~/.zshrc` or `$PROFILE`.

**I want to see exactly what will run.**
`claude-account path work` prints the directory; the command is always
`CLAUDE_CONFIG_DIR=<that> claude <your args>`.

---

## Uninstall

Both uninstallers remove the tool and leave every account signed in and intact.

**macOS / Linux**

```bash
curl -fsSL https://raw.githubusercontent.com/ebrahimelbarody74/claude-multi-account/main/uninstall.sh | bash
```

**Windows**

```powershell
irm https://raw.githubusercontent.com/ebrahimelbarody74/claude-multi-account/main/uninstall.ps1 | iex
```

To delete the stored accounts too — this signs those accounts out permanently:

```bash
rm -rf ~/.claude-accounts                                   # macOS / Linux
Remove-Item -Recurse -Force "$env:USERPROFILE\.claude-accounts"   # Windows
```

---

## Development

```bash
./tests/run-tests.sh          # bash suite
pwsh -File tests/run-tests.ps1  # PowerShell suite
```

Both run against a temporary accounts directory and a fake `claude`
executable, so they never touch your real accounts and never hit the network.

---

## License

[MIT](LICENSE).

Not affiliated with Anthropic. "Claude" and "Claude Code" are trademarks of
Anthropic, PBC.
