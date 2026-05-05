# claudex

[![test](https://github.com/richandpoor/claudex/actions/workflows/test.yml/badge.svg)](https://github.com/richandpoor/claudex/actions/workflows/test.yml)

Multi-account manager and rate-limit-aware wrapper for [Claude Code](https://docs.claude.com/claude-code).

Two small Bash tools that let you keep several Claude Pro/Max OAuth sessions side by side, switch between them with one command, and have your `claude` session automatically continue on a different account when the active one hits the 5-hour usage limit.

- **`claude-acct`** — store multiple OAuth credential files under `~/.claude/accounts/`, swap the active one by re-pointing a single symlink (`~/.claude/.credentials.json`). Token refresh keeps following the symlink, so each per-account file stays current.
- **`claudex`** — drop-in wrapper for `claude` that records the session via `script(1)`, watches the log for rate-limit messages, and on detection runs `claude-acct switch` and re-launches with `--continue` so the conversation resumes seamlessly on the next account.

No daemons, no config file. State lives in plain files under `~/.claude/accounts/`.

## Requirements

- Bash 4+
- `claude` (Claude Code CLI) on `PATH`
- `script` from `util-linux` (the Linux flavor — argument order differs from BSD)
- `python3` (used to parse OAuth JSON for the listing)
- GNU `date` (used by `set-reset-at` to parse `'+3 hours'` and similar strings)
- `flock` (used to serialize concurrent auto-switches in claudex)
- Optional: `notify-send` for desktop notifications

**Platform support:**

- **Linux**: both tools fully supported and tested in CI.
- **macOS**: `claude-acct` works (CI runs the full claude-acct testsuite on `macos-latest`). `claudex` is Linux-only — `script(1)` argument order differs on BSD and `flock` isn't installed by default. Use `claude-acct` standalone or run `claudex` inside a Linux VM/container.
- **Windows**: not supported. WSL2 should work like Linux (untested).

## Install

One-liner (clones into `~/.local/share/claudex` and symlinks both binaries into `~/.local/bin`):

```sh
curl -fsSL https://raw.githubusercontent.com/richandpoor/claudex/main/install.sh | bash
```

Re-running the installer pulls the latest changes. Override `CLAUDEX_HOME` and `CLAUDEX_BIN` to install elsewhere.

Manual alternative:

```sh
git clone https://github.com/richandpoor/claudex.git ~/.local/share/claudex
ln -sf ~/.local/share/claudex/bin/claude-acct ~/.local/bin/claude-acct
ln -sf ~/.local/share/claudex/bin/claudex     ~/.local/bin/claudex
```

**Symlinks are required for `claudex`** (not for `claude-acct`). `claudex` resolves its own path to find the repo root and writes session recordings to `<repo>/claudex-logs/`. A copied binary loses that anchor.

After install, verify the environment:

```sh
claude-acct doctor
```

## Bootstrap (one-time)

If you have never used multi-account, your `~/.claude/.credentials.json` is a regular file. Migrate it with:

```sh
claude-acct init main
```

Replace `main` with whatever name you want for your first account. The command moves `~/.claude/.credentials.json` into `accounts/main.json`, fixes permissions, and re-creates the symlink. From now on `~/.claude/.credentials.json` must remain a symlink — `claude-acct` refuses to run otherwise (and tells you how to recover).

Add a second account interactively:

```sh
claude-acct add work
```

This backs up the current credentials, runs `claude auth logout` then `claude auth login` so you can sign in to the new account, and on success offers to activate it. Ctrl+C at any point rolls everything back to the previous state.

## Daily use

```sh
claude-acct init main           # one-shot bootstrap from the legacy single-credential layout
claude-acct list                # show all accounts, active marker, sub tier, email, reset countdown
claude-acct list --json         # machine-readable output for status-line scripts
claude-acct status              # active account + claude auth status
claude-acct use work            # set 'work' active (swap symlink)
claude-acct switch              # round-robin to the next account, skipping ones still rate-limited
claude-acct switch personal     # alias of 'use'
claude-acct rm scratch          # delete an account (confirmation required)
claude-acct mark-limit [<name>] # record a rate-limit timestamp now
claude-acct refresh-info [--force]  # repopulate cached emails for every account
claude-acct set-email <name> <addr> # pin the displayed email when auth status can't switch cleanly
claude-acct set-reset-at <name> <t> # wall-clock reset for the list display
claude-acct doctor              # diagnose install: PATH, perms, deps, layout
claude-acct doctor --fix        # also auto-recover common breakages
claude-acct help
```

`switch` skips any account whose `last-limit` is less than 5 hours old (or whose `reset-at` is still in the future). When every other account is also limited it falls back to plain round-robin and prints a notice.

`<t>` for `set-reset-at` is either a unix epoch or any string GNU `date -d` can parse, e.g. `'2026-05-04 20:30:00'` or `'+3 hours 39 minutes'`.

### Rate-limit-aware wrapper

Use `claudex` exactly like `claude` — it forwards every argument:

```sh
claudex                # interactive session
claudex -c             # continue the latest conversation
claudex -p "do X"      # one-shot prompt
```

What it adds:

- Tees the session through `script(1)` into `<repo>/claudex-logs/<timestamp>.cycleN.log`
- Tails the log live; on the first match of a rate-limit pattern, alerts via terminal bell + `notify-send` + a yellow on-screen banner
- When `claude` exits, re-checks the last 80 log lines to confirm the match, then runs `claude-acct switch` and re-launches `claude --continue` on the next account
- Logs older than 30 days are deleted on startup
- Always passes `--remote-control` for interactive sessions (so the session is reachable from claude.ai/code and the mobile app), unless you opt out

Wrapper-only flags (stripped before forwarding to `claude`):

| Flag | Effect |
|------|--------|
| `--no-auto-switch` | don't switch after exit, even if a limit is detected |
| `--no-watch` | disable the live log watcher; only check at the end |
| `--no-remote-control` | don't add `--remote-control` |

Env var:

| Name | Default | Effect |
|------|---------|--------|
| `CLAUDEX_AUTO_EXIT_DELAY` | `3` | seconds to wait after detection before SIGINT-ing `claude` (lets the limit message finish printing) |

A `flock`-protected critical section ensures two concurrent `claudex` sessions don't fight over the active account when both hit a limit at once.

## File layout

```
~/.claude/
├── .credentials.json           → symlink to accounts/<active>.json
├── .claudex.switch.lock        # flock target for the auto-switch critical section
└── accounts/
    ├── active                  # one-line file: name of the active account
    ├── <name>.json             # OAuth credentials, chmod 600
    ├── <name>.email            # cached email for the listing (optional)
    ├── <name>.last-limit       # epoch timestamp of last detected rate-limit
    └── <name>.reset-at         # optional wall-clock reset (epoch or date string)

<repo>/
└── claudex-logs/               # per-cycle session recordings (auto-rotated, 30 days)
```

Every per-account file is `chmod 600` and named after the account. Removing an account deletes all its sidecar files in one go.

## Troubleshooting

Run `claude-acct doctor` first — it covers most issues with a one-line diagnosis.

### `~/.claude/.credentials.json is a regular file, not a symlink`

Claude Code occasionally rewrites this path directly when it refreshes its OAuth token, replacing our symlink with a regular file containing the fresh credentials. `claude-acct` detects this on every state-changing operation (`use`, `switch`, `add`, `init`) and self-heals by re-absorbing the fresh credentials into the active account's JSON file. If you want to heal proactively without changing accounts:

```sh
claude-acct doctor --fix
```

If the fresh credentials are valuable (recent token refresh), the heal preserves them — the active account's old JSON is saved as `<name>.json.before-fix.<pid>` for one-revert safety.

### `Active account` shows the wrong email in `claude-acct list`

After a symlink swap, `claude auth status` may keep returning the previous identity for a few requests. Pin the displayed email manually:

```sh
claude-acct set-email <name> you@domain.tld
```

### `switch requires at least 2 accounts`

You only have one account configured. Add a second:

```sh
claude-acct add <name>
```

## Notes and caveats

- **Reset estimate.** Without `<name>.reset-at`, the listing falls back to a 5-hour sliding window from the last `mark-limit`. This is an estimate and often differs from the real reset shown by Claude `/extra-usage`. Use `set-reset-at` for a wall-clock value.
- **Per-account limits, shared models.** Switching accounts gives you a fresh quota on a different OAuth identity; it does not bypass any per-organization limit imposed by Anthropic.
- **No support for API keys.** This tool is OAuth-only (Claude Pro/Max). Setting `ANTHROPIC_API_KEY` in the environment bypasses both the credentials file and Remote Control.
- **Pattern matching is fundamentally fragile.** `claudex` detects rate-limits by grepping the session log for phrases Claude Code emits. If Anthropic changes the wording in a future release, auto-switch will silently stop firing until `LIMIT_PATTERNS` and `test/fixtures/` are updated. The fixture-based test under `test/patterns.bats` documents the current set; PRs adding new fixtures are welcome.

## Tests

A small `bats` testsuite covers the script invariants:

```sh
test/run.sh
```

The runner clones [`bats-core`](https://github.com/bats-core/bats-core) into `test/.bats/` (gitignored) on the first run. Tests use a temp `HOME` and a stub `claude` binary on `PATH`, so they never touch your real credentials.
