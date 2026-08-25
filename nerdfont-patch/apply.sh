#!/usr/bin/env bash
# Patches the omarchy logo glyph (U+FFF00) into all 4 JetBrainsMono Nerd Font weights,
# validating each before it's allowed to touch the live system font.
#
# Must be run as root (it writes to /usr/share/fonts/TTF/).
# Safe to re-run any time, including from the pacman hook after a package update:
# it always treats whatever is currently on disk as the pristine base to back up + patch.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "must be run as root (writes to /usr/share/fonts/TTF/)" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_ICON_FONT="/usr/share/fonts/omarchy/omarchy.ttf"
FONT_DIR="/usr/share/fonts/TTF"
WEIGHTS=(Regular Bold Italic BoldItalic)

if [[ ! -r "$SRC_ICON_FONT" ]]; then
  echo "source icon font not found: $SRC_ICON_FONT" >&2
  exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

any_failed=0
for w in "${WEIGHTS[@]}"; do
  live="$FONT_DIR/JetBrainsMonoNerdFont-${w}.ttf"
  backup="${live}.orig"
  out="$work/JetBrainsMonoNerdFont-${w}.ttf"

  if [[ ! -r "$live" ]]; then
    echo "skip: $live not found"
    continue
  fi

  # Detect if $live is already one of our own patches (glyph present) -- if so, the true
  # pristine base is the existing .orig backup, not the live file, so re-patching from
  # live wouldn't touch a corrupted/stale patch by accident. Otherwise live IS pristine
  # (fresh install/upgrade) and becomes the new backup.
  base="$live"
  if python3 -c "
from fontTools.ttLib import TTFont
import sys
f = TTFont('$live')
sys.exit(0 if 0xfff00 in f.getBestCmap() else 1)
" ; then
    if [[ -r "$backup" ]]; then
      echo "$w: live file is already patched, using existing backup as pristine base"
      base="$backup"
    else
      echo "$w: live file is already patched but no backup exists -- refusing to guess, skipping" >&2
      any_failed=1
      continue
    fi
  fi

  echo "$w: patching from $base ..."
  if ! python3 "$SCRIPT_DIR/patch_font.py" "$SRC_ICON_FONT" "$base" "$out"; then
    echo "$w: patch_font.py failed" >&2
    any_failed=1
    continue
  fi

  echo "$w: validating ..."
  if ! python3 "$SCRIPT_DIR/validate_font.py" "$base" "$out"; then
    echo "$w: validation FAILED -- not installing" >&2
    any_failed=1
    continue
  fi

  # Only now touch anything live.
  if [[ "$base" == "$live" ]]; then
    cp "$live" "$backup"
  fi
  # Install via write-temp-then-rename rather than cp: cp truncates $live in
  # place, and anything with the live font mmap'd (e.g. a running terminal's
  # renderer) can get SIGBUS'd mid-read when that happens. rename(2) within
  # the same directory is atomic -- readers keep the old (unlinked) inode
  # until they reopen, so nobody ever observes a truncated file.
  install -m 644 "$out" "${live}.new"
  mv -f "${live}.new" "$live"
  echo "$w: installed"
done

fc-cache -f >/dev/null

if [[ $any_failed -ne 0 ]]; then
  echo "one or more weights failed -- see above" >&2
  exit 1
fi

echo "all weights patched and installed successfully"
