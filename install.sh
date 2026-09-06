#!/usr/bin/env bash
#
# Installer for claude-account (macOS and Linux).
#
#   curl -fsSL https://raw.githubusercontent.com/ebrahimelbarody74/claude-multi-account/main/install.sh | bash
#
# Environment:
#   INSTALL_DIR       where to put the executable (default: $HOME/.local/bin)
#   NO_MODIFY_PATH=1  do not touch shell rc files
#   REPO              owner/name to download from
#   REF               branch or tag to download from (default: main)

set -euo pipefail

REPO="${REPO:-ebrahimelbarody74/claude-multi-account}"
REF="${REF:-main}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
BIN_NAME="claude-account"
RAW_URL="https://raw.githubusercontent.com/${REPO}/${REF}/bin/${BIN_NAME}"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_DIM=$'\033[2m'
else
  C_RESET=""; C_BOLD=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_DIM=""
fi

info() { printf '%s\n' "$*"; }
warn() { printf '%swarning:%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die()  { printf '%serror:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

info "${C_BOLD}Installing claude-account${C_RESET}"
info ""

# --- sanity ---------------------------------------------------------------

case "$(uname -s)" in
  Darwin|Linux) ;;
  *) die "unsupported platform: $(uname -s). On Windows use install.ps1." ;;
esac

if ! command -v claude >/dev/null 2>&1; then
  warn "Claude Code ('claude') is not on your PATH yet."
  warn "claude-account will install fine, but install Claude Code before using it:"
  warn "  https://claude.com/claude-code"
  info ""
fi

# --- locate the source ----------------------------------------------------

SOURCE=""
SCRIPT_DIR=""
# $0 is "bash" when piped from curl, so only trust it when it is a real path.
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  SCRIPT_DIR="$(cd "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
fi

if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/bin/$BIN_NAME" ]; then
  SOURCE="$SCRIPT_DIR/bin/$BIN_NAME"
  info "Using local copy: $SOURCE"
else
  command -v curl >/dev/null 2>&1 || die "curl is required to download $BIN_NAME"
  TMP="$(mktemp -t claude-account.XXXXXX)" || die "could not create a temporary file"
  trap 'rm -f "$TMP"' EXIT
  info "Downloading from $RAW_URL"
  curl -fsSL "$RAW_URL" -o "$TMP" || die "download failed. Check the repository URL and your connection."
  # Refuse anything that is not the script we expect (e.g. a GitHub 404 page).
  head -n1 "$TMP" | grep -q '^#!' || die "downloaded file does not look like a shell script"
  grep -q 'CLAUDE_CONFIG_DIR' "$TMP" || die "downloaded file does not look like claude-account"
  SOURCE="$TMP"
fi

# --- install --------------------------------------------------------------

mkdir -p "$INSTALL_DIR" || die "could not create $INSTALL_DIR"
[ -w "$INSTALL_DIR" ] || die "$INSTALL_DIR is not writable. Set INSTALL_DIR to somewhere you own."

TARGET="$INSTALL_DIR/$BIN_NAME"
cp -- "$SOURCE" "$TARGET" || die "could not write $TARGET"
chmod 755 "$TARGET" || die "could not make $TARGET executable"

info "${C_GREEN}Installed${C_RESET} $TARGET"

# --- PATH -----------------------------------------------------------------

on_path() {
  case ":${PATH}:" in
    *":$INSTALL_DIR:"*) return 0 ;;
    *) return 1 ;;
  esac
}

PATH_LINE="export PATH=\"$INSTALL_DIR:\$PATH\""
MARKER="# added by claude-multi-account installer"

add_to_rc() {
  local rc="$1"
  [ -e "$rc" ] || return 1
  if grep -Fq "$MARKER" "$rc" 2>/dev/null; then
    info "${C_DIM}PATH entry already present in $rc${C_RESET}"
    return 0
  fi
  {
    printf '\n%s\n' "$MARKER"
    printf '%s\n' "$PATH_LINE"
  } >> "$rc" || return 1
  info "Added $INSTALL_DIR to your PATH in $rc"
  return 0
}

if on_path; then
  info "${C_DIM}$INSTALL_DIR is already on your PATH${C_RESET}"
elif [ -n "${NO_MODIFY_PATH:-}" ]; then
  warn "$INSTALL_DIR is not on your PATH. Add this line yourself:"
  info "  $PATH_LINE"
else
  updated=0
  for rc in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; do
    if add_to_rc "$rc"; then updated=1; fi
  done
  if [ "$updated" -eq 0 ]; then
    # No rc file existed. Create the one matching the current shell.
    case "${SHELL:-}" in
      */zsh) rc="$HOME/.zshrc" ;;
      *)     rc="$HOME/.bashrc" ;;
    esac
    printf '%s\n%s\n' "$MARKER" "$PATH_LINE" >> "$rc"
    info "Created $rc and added $INSTALL_DIR to your PATH"
  fi
  info "Open a new terminal, or run: ${C_BOLD}$PATH_LINE${C_RESET}"
fi

# --- verify ---------------------------------------------------------------

if ! "$TARGET" version >/dev/null 2>&1; then
  die "the installed executable did not run. Please open an issue."
fi

info ""
info "${C_GREEN}Done.${C_RESET} $("$TARGET" version)"
info ""
info "${C_BOLD}Next steps${C_RESET}"
info "  claude-account add work        # create an account and sign in"
info "  claude-account add personal"
info "  claude-account list"
info "  claude-account work            # run Claude Code as 'work'"
info "  claude-account default         # your normal Claude Code, untouched"
info ""
info "Accounts are stored in ~/.claude-accounts and are never removed by the uninstaller."
