#!/usr/bin/env bats

load test_helper

@test "list shows both configured accounts and marks active" {
  run "$CLAUDE_ACCT_BIN" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"A"* ]]
  [[ "$output" == *"B"* ]]
  # The active marker (asterisk) should appear on the A row, not the B row.
  [[ "$output" =~ \*[[:space:]]+.*A ]]
}

@test "use <name> swaps the credentials symlink and active file" {
  run "$CLAUDE_ACCT_BIN" use B
  [ "$status" -eq 0 ]
  [ "$(active_target)" = "B.json" ]
  [ "$(active_file_contents)" = "B" ]
}

@test "use <unknown> fails without changing state" {
  run "$CLAUDE_ACCT_BIN" use ZZZ
  [ "$status" -ne 0 ]
  [ "$(active_target)" = "A.json" ]
  [ "$(active_file_contents)" = "A" ]
}

@test "use <active> is a no-op (still succeeds)" {
  run "$CLAUDE_ACCT_BIN" use A
  [ "$status" -eq 0 ]
  [ "$(active_target)" = "A.json" ]
}

@test "switch (no arg) round-robins to the next account" {
  run "$CLAUDE_ACCT_BIN" switch
  [ "$status" -eq 0 ]
  [ "$(active_target)" = "B.json" ]

  run "$CLAUDE_ACCT_BIN" switch
  [ "$status" -eq 0 ]
  [ "$(active_target)" = "A.json" ]
}

@test "mark-limit writes a numeric epoch into <name>.last-limit" {
  run "$CLAUDE_ACCT_BIN" mark-limit
  [ "$status" -eq 0 ]
  [ -f "$HOME/.claude/accounts/A.last-limit" ]
  ts=$(cat "$HOME/.claude/accounts/A.last-limit")
  [[ "$ts" =~ ^[0-9]+$ ]]
}

@test "set-email persists the address with chmod 600" {
  run "$CLAUDE_ACCT_BIN" set-email B foo@bar.test
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/.claude/accounts/B.email")" = "foo@bar.test" ]
  perms=$(stat -c '%a' "$HOME/.claude/accounts/B.email")
  [ "$perms" = "600" ]
}

@test "set-reset-at converts a datetime string to epoch" {
  run "$CLAUDE_ACCT_BIN" set-reset-at A "2099-01-01 00:00:00"
  [ "$status" -eq 0 ]
  ts=$(cat "$HOME/.claude/accounts/A.reset-at")
  [[ "$ts" =~ ^[0-9]+$ ]]
  expected=$(date -d "2099-01-01 00:00:00" +%s)
  [ "$ts" = "$expected" ]
}

@test "rm refuses to remove the active account" {
  run "$CLAUDE_ACCT_BIN" rm A <<<"yes"
  [ "$status" -ne 0 ]
  [ -f "$HOME/.claude/accounts/A.json" ]
}

@test "rm removes a non-active account when confirmed" {
  run "$CLAUDE_ACCT_BIN" rm B <<<"yes"
  [ "$status" -eq 0 ]
  [ ! -f "$HOME/.claude/accounts/B.json" ]
}

@test "ensure_setup fails when the symlink has been replaced by a regular file" {
  rm "$HOME/.claude/.credentials.json"
  echo '{"x":1}' > "$HOME/.claude/.credentials.json"
  run "$CLAUDE_ACCT_BIN" list
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a symlink"* ]]
}

@test "switch fails when only one account exists" {
  rm "$HOME/.claude/accounts/B.json"
  run "$CLAUDE_ACCT_BIN" switch
  [ "$status" -ne 0 ]
  [[ "$output" == *"requires at least 2 accounts"* ]]
}

@test "switch skips accounts marked rate-limited recently" {
  # Add a third account C, mark B as rate-limited just now. From A, switch
  # should skip B and land on C.
  cat > "$HOME/.claude/accounts/C.json" <<'JSON'
{"claudeAiOauth":{"subscriptionType":"pro","rateLimitTier":"default_tier_1","accessToken":"c"}}
JSON
  chmod 600 "$HOME/.claude/accounts/C.json"
  date +%s > "$HOME/.claude/accounts/B.last-limit"
  run "$CLAUDE_ACCT_BIN" switch
  [ "$status" -eq 0 ]
  [ "$(active_target)" = "C.json" ]
}

@test "switch falls back to round-robin when every other account is rate-limited" {
  date +%s > "$HOME/.claude/accounts/B.last-limit"
  run "$CLAUDE_ACCT_BIN" switch
  [ "$status" -eq 0 ]
  [ "$(active_target)" = "B.json" ]
  [[ "$output" == *"falling back"* ]]
}

@test "init bootstraps a single-credential layout into accounts/" {
  # Reset to legacy layout: regular credentials.json, no accounts/.
  rm -rf "$HOME/.claude"
  mkdir -p "$HOME/.claude"
  echo '{"claudeAiOauth":{"subscriptionType":"max20","accessToken":"x"}}' \
    > "$HOME/.claude/.credentials.json"

  run "$CLAUDE_ACCT_BIN" init main
  [ "$status" -eq 0 ]
  [ -L "$HOME/.claude/.credentials.json" ]
  [ "$(active_target)" = "main.json" ]
  [ "$(active_file_contents)" = "main" ]
  [ -f "$HOME/.claude/accounts/main.json" ]
  perms=$(stat -c '%a' "$HOME/.claude/accounts/main.json")
  [ "$perms" = "600" ]
}

@test "init refuses to clobber an already-initialised setup" {
  run "$CLAUDE_ACCT_BIN" init main
  [ "$status" -ne 0 ]
  [[ "$output" == *"already initialised"* ]]
}

@test "list --json emits well-formed JSON with both accounts" {
  run "$CLAUDE_ACCT_BIN" list --json
  [ "$status" -eq 0 ]
  # The output must round-trip through python's json parser.
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['active'] == 'A', d
names = sorted(a['name'] for a in d['accounts'])
assert names == ['A', 'B'], names
active = [a for a in d['accounts'] if a['active']]
assert len(active) == 1 and active[0]['name'] == 'A', active
"
}

@test "list --json marks recently rate-limited accounts" {
  date +%s > "$HOME/.claude/accounts/B.last-limit"
  run "$CLAUDE_ACCT_BIN" list --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
b = next(a for a in d['accounts'] if a['name'] == 'B')
assert b['rate_limited'] is True, b
assert isinstance(b['last_limit'], int), b
"
}
