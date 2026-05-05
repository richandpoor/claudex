# Shared setup for claude-acct bats tests.
#
# Each test gets a fresh temp HOME with a two-account layout (A active, B idle)
# and a stub `claude` binary on PATH so the script never reaches the real CLI.

setup() {
  export ORIG_HOME="$HOME"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/accounts"

  cat > "$HOME/.claude/accounts/A.json" <<'JSON'
{"claudeAiOauth":{"subscriptionType":"max20","rateLimitTier":"default_tier_1","accessToken":"a"}}
JSON
  cat > "$HOME/.claude/accounts/B.json" <<'JSON'
{"claudeAiOauth":{"subscriptionType":"max5","rateLimitTier":"default_tier_2","accessToken":"b"}}
JSON
  chmod 600 "$HOME/.claude/accounts/"*.json

  echo A > "$HOME/.claude/accounts/active"
  ln -s accounts/A.json "$HOME/.claude/.credentials.json"

  # Stub `claude` so capture_active_email + cmd_status don't shell out for real.
  export STUB_BIN="$BATS_TEST_TMPDIR/stub"
  mkdir -p "$STUB_BIN"
  cat > "$STUB_BIN/claude" <<'SH'
#!/usr/bin/env bash
# Minimal stub: respond to `auth status` with no email so capture_active_email
# becomes a no-op. Other subcommands return success.
exit 0
SH
  chmod +x "$STUB_BIN/claude"
  export PATH="$STUB_BIN:$PATH"

  # Path to the script under test. Override with CLAUDE_ACCT_BIN if needed.
  CLAUDE_ACCT_BIN="${CLAUDE_ACCT_BIN:-$BATS_TEST_DIRNAME/../bin/claude-acct}"
  export CLAUDE_ACCT_BIN
}

teardown() {
  export HOME="$ORIG_HOME"
}

# Resolve the basename of the credentials symlink target (e.g. "A.json").
active_target() {
  basename "$(readlink "$HOME/.claude/.credentials.json")"
}

active_file_contents() {
  tr -d '[:space:]' < "$HOME/.claude/accounts/active"
}

# Portable file-permission read (GNU stat first, BSD stat fallback).
file_perms() {
  stat -c '%a' "$1" 2>/dev/null || stat -f '%OLp' "$1" 2>/dev/null
}
