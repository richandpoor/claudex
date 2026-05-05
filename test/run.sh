#!/usr/bin/env bash
# Run the bats testsuite, bootstrapping a local bats-core checkout the first
# time (so the user doesn't need apt/sudo for an integration-test framework).
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
bats_root="$here/.bats"

if [[ ! -x "$bats_root/bin/bats" ]]; then
  echo "→ bootstrapping bats-core into $bats_root"
  rm -rf "$bats_root"
  git clone --depth=1 --quiet https://github.com/bats-core/bats-core.git "$bats_root"
fi

# Default: run every *.bats under test/. Pass explicit paths to override.
if (( $# > 0 )); then
  exec "$bats_root/bin/bats" "$@"
fi
exec "$bats_root/bin/bats" "$here"/*.bats
