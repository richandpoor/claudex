# Changelog

All notable changes to this project. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
