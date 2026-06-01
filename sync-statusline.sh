#!/usr/bin/env bash
# sync-statusline.sh — keep the installer heredoc in sync with statusline-command.sh
#
# Usage:
#   ./sync-statusline.sh           # re-splice + deploy to ~/.claude/
#   ./sync-statusline.sh --check   # exit non-zero if heredoc drifted (CI / pre-commit)
#   ./sync-statusline.sh --splice  # re-splice only, no deploy
#
# The installer embeds statusline-command.sh verbatim inside a <<'STATUSEOF' heredoc.
# Edit statusline-command.sh, then run this script to bake the change in.

set -euo pipefail

INSTALLER="$(cd "$(dirname "$0")" && pwd)/install-statusline.sh"
STATUSLINE="$(cd "$(dirname "$0")" && pwd)/statusline-command.sh"
CLAUDE_DEST="$HOME/.claude/statusline-command.sh"

_die() { printf 'error: %s\n' "$*" >&2; exit 1; }

[[ -f "$INSTALLER" ]]  || _die "installer not found: $INSTALLER"
[[ -f "$STATUSLINE" ]] || _die "statusline not found: $STATUSLINE"

OPEN=$(grep -n "<<'STATUSEOF'" "$INSTALLER" | cut -d: -f1)
CLOSE=$(grep -n "^STATUSEOF$"   "$INSTALLER" | cut -d: -f1)
[[ -n "$OPEN" && -n "$CLOSE" ]] || _die "could not locate STATUSEOF markers in $INSTALLER"

MODE="${1:-}"

# --check: diff only, no writes
if [[ "$MODE" == "--check" ]]; then
  if diff -q <(sed -n "$((OPEN+1)),$((CLOSE-1))p" "$INSTALLER") "$STATUSLINE" >/dev/null 2>&1; then
    printf 'OK  heredoc matches statusline-command.sh\n'
    exit 0
  else
    printf 'DRIFT  heredoc differs from statusline-command.sh:\n'
    diff <(sed -n "$((OPEN+1)),$((CLOSE-1))p" "$INSTALLER") "$STATUSLINE" || true
    exit 1
  fi
fi

# --splice or default: re-splice heredoc
head -n "$OPEN"   "$INSTALLER"           >  /tmp/_installer_new.sh
cat               "$STATUSLINE"          >> /tmp/_installer_new.sh
tail -n +"$CLOSE" "$INSTALLER"           >> /tmp/_installer_new.sh
chmod +x /tmp/_installer_new.sh

# Verify the splice landed cleanly (recompute markers from the new file)
NEW_OPEN=$(grep -n "<<'STATUSEOF'" /tmp/_installer_new.sh | cut -d: -f1)
NEW_CLOSE=$(grep -n "^STATUSEOF$"   /tmp/_installer_new.sh | cut -d: -f1)
if ! diff -q <(sed -n "$((NEW_OPEN+1)),$((NEW_CLOSE-1))p" /tmp/_installer_new.sh) "$STATUSLINE" >/dev/null 2>&1; then
  rm -f /tmp/_installer_new.sh
  _die "splice verification failed — installer not updated"
fi

mv /tmp/_installer_new.sh "$INSTALLER"
printf 'OK  heredoc re-spliced from statusline-command.sh\n'

# deploy unless --splice-only
if [[ "$MODE" == "--splice" ]]; then
  printf '    (skipping deploy — run without --splice to also copy to %s)\n' "$CLAUDE_DEST"
  exit 0
fi

cp "$STATUSLINE" "$CLAUDE_DEST"
printf 'OK  deployed to %s\n' "$CLAUDE_DEST"
