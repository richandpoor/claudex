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
