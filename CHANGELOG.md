# Changelog

All notable changes to this project. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-05-05

### Added
- `claude-acct doctor [--fix]` — diagnoses install (deps, permissions, layout, PATH) and optionally auto-recovers from common breakages.
- Self-healing: `use`, `switch`, `add`, and `init` detect when Claude Code has rewritten `~/.claude/.credentials.json` as a regular file (token refresh) and re-absorb the fresh credentials into the active account's JSON file before doing anything else. Previously this would silently discard the refresh on next switch.
- `install.sh` for one-liner installation: `curl -fsSL .../install.sh | bash`. Idempotent: re-running pulls the latest changes.
- macOS support for `claude-acct` (`claudex` remains Linux-only). CI matrix runs both `ubuntu-latest` and `macos-latest`.

### Changed
- `claude-acct` no longer uses `mapfile` or GNU `date -d` directly — both are wrapped in portability helpers (`to_epoch`, `format_epoch`, `read_lines_into`) so the script runs on macOS bash 3.2 + BSD date.

### Documentation
- README: install one-liner, troubleshooting section covering the symlink-rewrite case and `doctor --fix`, honest platform matrix, explicit note about pattern-matching fragility.

## [0.1.0] - 2026-05-05

First tagged release.

### Added
- `claude-acct init <name>` — one-shot bootstrap that migrates a legacy `~/.claude/.credentials.json` into the multi-account layout.
- `claude-acct list --json` — machine-readable output for status-line scripts and external tooling. Stable schema: `{ active, accounts: [ { name, active, sub, tier, email, last_limit, reset_at, rate_limited } ] }`.
- `claude-acct switch` now skips accounts still inside their rate-limit window (5h sliding window from `last-limit`, or wall-clock `reset-at` in the future). Falls back to plain round-robin when every other account is also limited.

### Changed
- `claudex` rate-limit detection patterns tightened to phrases Claude Code actually emits in its rate-limit UI. Removed the broad `rate.?limit` pattern that false-positived on any unrelated mention of "rate limit" in tool output. Coverage verified by `test/patterns.bats` against real-log fixtures under `test/fixtures/`.
- `claudex` writes session recordings to `<repo>/claudex-logs/` instead of `~/.claude/claudex-logs/`. This requires installing via symlink.

### Fixed
- `claude-acct add` now has a single trap-based rollback path covering Ctrl+C between logout and the activation prompt, plus unexpected errors at any intermediate step.
- Temporary credential switches in `cache_missing_emails_for_list` and `cmd_refresh_info` restore the original active account on Ctrl+C via a shared `restore_active_account` helper.

### Infrastructure
- GitHub Actions CI runs `bash -n` + bats on push and PR.
- bats testsuite under `test/` (22 cases) with bootstrapping `run.sh`.
