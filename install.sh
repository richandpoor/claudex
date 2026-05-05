#!/usr/bin/env bash
# claudex installer.
#
#   curl -fsSL https://raw.githubusercontent.com/richandpoor/claudex/main/install.sh | bash
#
# Clones the repo into ~/.local/share/claudex (or $CLAUDEX_HOME if set) and
# symlinks both binaries into ~/.local/bin (or $CLAUDEX_BIN). Re-running the
# installer updates the existing checkout via git pull. Idempotent.
set -euo pipefail

readonly REPO_URL="${CLAUDEX_REPO:-https://github.com/richandpoor/claudex.git}"
readonly INSTALL_HOME="${CLAUDEX_HOME:-$HOME/.local/share/claudex}"
readonly INSTALL_BIN="${CLAUDEX_BIN:-$HOME/.local/bin}"

if [[ -t 1 ]]; then
  C_BOLD=$'\e[1m'; C_GREEN=$'\e[32m'; C_YEL=$'\e[33m'; C_RED=$'\e[31m'; C_RESET=$'\e[0m'
else
  C_BOLD=''; C_GREEN=''; C_YEL=''; C_RED=''; C_RESET=''
fi
info() { echo "${C_GREEN}→${C_RESET} $*"; }
warn() { echo "${C_YEL}⚠${C_RESET}  $*" >&2; }
die()  { echo "${C_RED}✗${C_RESET}  $*" >&2; exit 1; }

command -v git &>/dev/null || die "git is required"
command -v claude &>/dev/null || warn "Claude Code CLI ('claude') not on PATH — install from https://docs.claude.com/claude-code first."

mkdir -p "$INSTALL_BIN"

if [[ -d "$INSTALL_HOME/.git" ]]; then
  info "updating existing checkout at $INSTALL_HOME"
  git -C "$INSTALL_HOME" pull --ff-only --quiet
else
  info "cloning $REPO_URL → $INSTALL_HOME"
  mkdir -p "$(dirname "$INSTALL_HOME")"
  git clone --depth=1 --quiet "$REPO_URL" "$INSTALL_HOME"
fi

ln -sfn "$INSTALL_HOME/bin/claude-acct" "$INSTALL_BIN/claude-acct"
ln -sfn "$INSTALL_HOME/bin/claudex"     "$INSTALL_BIN/claudex"
info "linked into $INSTALL_BIN"

case ":$PATH:" in
  *":$INSTALL_BIN:"*) ;;
  *) warn "$INSTALL_BIN is not on your PATH. Add this to your shell rc:
    export PATH=\"$INSTALL_BIN:\$PATH\"" ;;
esac

echo
echo "${C_BOLD}claudex installed.${C_RESET}"
echo "Next steps:"
echo "  1. claude-acct doctor       # verify your environment"
echo "  2. claude-acct init <name>  # bootstrap from your existing ~/.claude/.credentials.json"
echo "  3. claude-acct add <other>  # add a second account"
echo "  4. claudex                  # use it instead of \`claude\`"
