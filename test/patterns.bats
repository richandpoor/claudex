#!/usr/bin/env bats
#
# Verify that the LIMIT_PATTERNS array in bin/claudex still matches every
# real-world rate-limit log we have on file under test/fixtures/.
#
# When Claude Code changes the wording of its rate-limit message and these
# tests start failing on a NEW fixture, that's the signal to update
# LIMIT_PATTERNS in bin/claudex. When they fail on an OLD fixture after a
# pattern edit, you've broken backwards compatibility — fix the pattern.
#
# The test extracts the patterns directly from bin/claudex (no copy-paste)
# so there is no drift between source-of-truth and test.

setup() {
  CLAUDEX_BIN="$BATS_TEST_DIRNAME/../bin/claudex"
  FIXTURES="$BATS_TEST_DIRNAME/fixtures"

  # Pull the LIMIT_PATTERNS array out of bin/claudex without sourcing the
  # whole script (which would run main()). Result: one regex per line.
  PATTERNS=$(awk '
    /^readonly LIMIT_PATTERNS=\(/ { in_arr = 1; next }
    in_arr && /^\)/ { in_arr = 0; next }
    in_arr {
      gsub(/^[[:space:]]*'\''/, "")
      gsub(/'\''[[:space:]]*$/, "")
      if ($0 != "") print
    }
  ' "$CLAUDEX_BIN")
  [ -n "$PATTERNS" ] || { echo "could not extract LIMIT_PATTERNS from $CLAUDEX_BIN"; return 1; }

  # Build the alternation the same way build_pattern() does in claudex.
  ALT=$(echo "$PATTERNS" | paste -sd '|')
}

# Asserts at least one pattern matches the fixture (the way claudex's
# tail|grep watcher would).
assert_match() {
  local fixture="$1"
  [ -f "$fixture" ] || { echo "missing fixture: $fixture"; return 1; }
  grep -qiE "$ALT" "$fixture"
}

assert_no_match() {
  local fixture="$1"
  [ -f "$fixture" ] || { echo "missing fixture: $fixture"; return 1; }
  if grep -qiE "$ALT" "$fixture"; then
    echo "false positive on $fixture — these patterns matched:"
    grep -iE "$ALT" "$fixture" | head -5
    return 1
  fi
  return 0
}

@test "patterns extracted from claudex are non-empty" {
  [ -n "$PATTERNS" ]
  [ "$(echo "$PATTERNS" | wc -l)" -ge 5 ]
}

@test "matches: 'You're out of extra usage' notification" {
  assert_match "$FIXTURES/limit-out-of-extra-usage.log"
}

@test "matches: /rate-limit-options menu" {
  assert_match "$FIXTURES/limit-rate-limit-options.log"
}

@test "no false positive on logs that mention 'rate limit' in unrelated context" {
  # Includes lines like "Set new connection rate limit to 100 req/sec" and
  # 'see "rate limit" section in README'. The patterns are tuned to phrases
  # Claude Code actually emits, not generic word combinations.
  assert_no_match "$FIXTURES/no-limit.log"
}
