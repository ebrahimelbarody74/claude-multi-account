#!/usr/bin/env bash
#
# Uninstaller for claude-account (macOS and Linux).
#
#   curl -fsSL https://raw.githubusercontent.com/ebrahimelbarody74/claude-multi-account/main/uninstall.sh | bash
#
# This removes the executable and the PATH line the installer added.
# It NEVER removes your accounts (~/.claude-accounts) and NEVER touches ~/.claude.

set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
BIN_NAME="claude-account"
ACCOUNTS_HOME="${CLAUDE_ACCOUNTS_HOME:-$HOME/.claude-accounts}"
MARKER="# added by claude-multi-account installer"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_DIM=$'\033[2m'
else
  C_RESET=""; C_BOLD=""; C_GREEN=""; C_YELLOW=""; C_DIM=""
fi

info() { printf '%s\n' "$*"; }
warn() { printf '%swarning:%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }

info "${C_BOLD}Uninstalling claude-account${C_RESET}"
info ""

removed=0

# --- the executable -------------------------------------------------------

# Remove the copy in INSTALL_DIR, plus any other copy found on PATH.
candidates="$INSTALL_DIR/$BIN_NAME"
if found="$(command -v "$BIN_NAME" 2>/dev/null)"; then
  if [ "$found" != "$INSTALL_DIR/$BIN_NAME" ]; then
    candidates="$candidates
$found"
  fi
fi

while IFS= read -r target; do
  [ -n "$target" ] || continue
  [ -e "$target" ] || continue
  # Only delete something that really is our script.
  if ! grep -q 'claude-multi-account' "$target" 2>/dev/null; then
    warn "skipping $target — it does not look like claude-account"
    continue
  fi
  if rm -f -- "$target"; then
    info "${C_GREEN}removed${C_RESET} $target"
    removed=1
  else
    warn "could not remove $target (try again with sudo)"
  fi
done <<EOF
$candidates
EOF

if [ "$removed" -eq 0 ]; then
  info "${C_DIM}No installed executable found.${C_RESET}"
fi

# --- the PATH line --------------------------------------------------------

for rc in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; do
  [ -f "$rc" ] || continue
  grep -Fq "$MARKER" "$rc" 2>/dev/null || continue
  tmp="$(mktemp -t claude-account-rc.XXXXXX)" || continue
  # Drop the marker line and the export line that follows it.
  awk -v marker="$MARKER" '
    $0 == marker { skip = 2; next }
    skip > 0 && $0 ~ /^export PATH=/ { skip = 0; next }
    { skip = 0; print }
  ' "$rc" > "$tmp" && cat "$tmp" > "$rc" && rm -f "$tmp"
  info "${C_GREEN}cleaned${C_RESET} the PATH entry from $rc"
done

# --- what we deliberately keep -------------------------------------------

info ""
info "${C_BOLD}Kept, on purpose:${C_RESET}"
if [ -d "$ACCOUNTS_HOME" ]; then
  count="$(find "$ACCOUNTS_HOME" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
  info "  $ACCOUNTS_HOME  ($count account(s), still signed in)"
else
  info "  $ACCOUNTS_HOME  (does not exist)"
fi
info "  $HOME/.claude  (your default Claude Code installation — never touched)"
info ""
info "If you also want the stored account sessions gone, delete them yourself:"
info "  ${C_BOLD}rm -rf $ACCOUNTS_HOME${C_RESET}"
info ""
info "${C_GREEN}Done.${C_RESET}"
