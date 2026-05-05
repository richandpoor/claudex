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

**Linux only at the moment.** macOS is not supported — `script(1)` has different
argument order on BSD, the default bash 3.2 lacks `mapfile`, BSD `date` doesn't
take `-d`, and `flock` isn't installed by default. Patches welcome.

## Install

Clone the repo and symlink both scripts onto your `PATH`:

```sh
git clone https://github.com/<your-fork>/claudex.git
cd claudex
ln -sf "$PWD/bin/claude-acct" ~/.local/bin/claude-acct
ln -sf "$PWD/bin/claudex"     ~/.local/bin/claudex
```

**Symlinks are recommended.** `claudex` resolves its own path to find the repo root and writes session recordings to `<repo>/claudex-logs/`. A copied binary loses that anchor and would log next to the install dir instead, so prefer `ln -sf` over `install`/`cp`.

`claudex` looks for `claude-acct` on `PATH` first, then in the same directory as itself, so co-located installs work even without `PATH`.

## Bootstrap (one-time)

If you have never used multi-account, your `~/.claude/.credentials.json` is a regular file. Migrate it into the new layout:

```sh
mkdir -p ~/.claude/accounts
mv ~/.claude/.credentials.json ~/.claude/accounts/main.json
chmod 600 ~/.claude/accounts/main.json
ln -s accounts/main.json ~/.claude/.credentials.json
echo main > ~/.claude/accounts/active
```

Replace `main` with whatever name you want for your first account. From now on `~/.claude/.credentials.json` must remain a symlink — `claude-acct` refuses to run otherwise (and tells you how to recover).

Add a second account interactively:

```sh
claude-acct add work
```

This backs up the current credentials, runs `claude auth logout` then `claude auth login` so you can sign in to the new account, and on success offers to activate it. Ctrl+C at any point rolls everything back to the previous state.

## Daily use

```sh
claude-acct list                # show all accounts, active marker, sub tier, email, reset countdown
claude-acct status              # active account + claude auth status
claude-acct use work            # set 'work' active (swap symlink)
claude-acct switch              # round-robin to the next account (alphabetical order)
claude-acct switch personal     # alias of 'use'
claude-acct rm scratch          # delete an account (confirmation required)
claude-acct mark-limit [<name>] # record a rate-limit timestamp now
claude-acct refresh-info [--force]  # repopulate cached emails for every account
claude-acct set-email <name> <addr> # pin the displayed email when auth status can't switch cleanly
claude-acct set-reset-at <name> <t> # wall-clock reset for the list display
claude-acct help
```

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

## Notes and caveats

- **`claude auth status` cache.** Native Claude sometimes keeps reporting the previous identity after the symlink is repointed. `claude-acct` works around this when populating cached emails, but if you see the wrong email in `list`, pin it explicitly with `set-email`.
- **Reset estimate.** Without `<name>.reset-at`, the listing falls back to a 5-hour sliding window from the last `mark-limit`. This is an estimate and often differs from the real reset shown by Claude `/extra-usage`. Use `set-reset-at` for a wall-clock value.
- **Per-account limits, shared models.** Switching accounts gives you a fresh quota on a different OAuth identity; it does not bypass any per-organization limit imposed by Anthropic.
- **No support for API keys.** This tool is OAuth-only (Claude Pro/Max). Setting `ANTHROPIC_API_KEY` in the environment bypasses both the credentials file and Remote Control.

## Tests

A small `bats` testsuite covers the script invariants:

```sh
test/run.sh
```

The runner clones [`bats-core`](https://github.com/bats-core/bats-core) into `test/.bats/` (gitignored) on the first run. Tests use a temp `HOME` and a stub `claude` binary on `PATH`, so they never touch your real credentials.
