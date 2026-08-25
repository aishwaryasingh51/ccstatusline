# Claude Code Adaptive Statusline

This project provides an adaptive statusline for Claude Code and an installer that sets it up on any machine. The **installer** (`install-statusline.sh`) detects the distro, installs the JetBrainsMono Nerd Font, configures the terminal font, writes the statusline to `~/.claude/statusline-command.sh`, and patches `~/.claude/settings.json` to register it. The **statusline** (`statusline-command.sh`) runs on every Claude Code prompt render — it reads live theme colors from the user's wallpaper tool (Noctalia, Matugen, Wallust, pywal, or Omarchy), and outputs **two lines**:

- **Line 1:** distro icon + path (owns the full terminal width)
- **Line 2:** git status (GitHub icon + branch + colour-coded flags), plan badge, model name, context-window usage (`󰍛 N%`), weekly rate-limit (`Week: N%`), session rate-limit with countdown (`Sess: N% (Xh Ym)`)

Claude Code appends its own mode indicator (`accept edits on`, plan mode, etc.) as a third line automatically.

---

## Files in this folder

| File | Role |
|---|---|
| `install-statusline.sh` | The installer. Patches `~/.claude/settings.json`, installs statusline, configures terminal font, writes `~/.claude/.distro-icon`, offers the Omarchy Nerd Font patch on Omarchy |
| `statusline-command.sh` | **Working copy** of the statusline for development. The live copy is at `~/.claude/statusline-command.sh` |
| `nerdfont-patch/` | `apply.sh` / `patch_font.py` / `validate_font.py` — splices the Omarchy logo glyph into JetBrainsMono Nerd Font at U+FFF00 (table-level `glyf`/`hmtx`/`cmap` edit, validated against the original before install). Only offered by the installer when `$DISTRO == omarchy`; reads `/usr/share/fonts/omarchy/omarchy.ttf` (ships with `omarchy-settings`, MIT) as the glyph source, never redistributes font bytes itself |

---

## The two-file invariant (most important rule)

`install-statusline.sh` contains the entire statusline body verbatim inside a `<<'STATUSEOF'` heredoc. **The heredoc copy must always match the working/installed statusline.** Whenever `statusline-command.sh` is edited, re-splice it back into the installer:

```bash
INSTALLER=~/Documents/ccstatusline/install-statusline.sh
STATUSLINE=~/Documents/ccstatusline/statusline-command.sh
OPEN=$(grep -n "<<'STATUSEOF'" "$INSTALLER" | cut -d: -f1)
CLOSE=$(grep -n "^STATUSEOF$" "$INSTALLER" | cut -d: -f1)
head -"$OPEN" "$INSTALLER" > /tmp/i.sh
cat "$STATUSLINE" >> /tmp/i.sh
tail -n +"$CLOSE" "$INSTALLER" >> /tmp/i.sh
mv /tmp/i.sh "$INSTALLER" && chmod +x "$INSTALLER"
```

Verify and deploy:
```bash
diff <(sed -n "$((OPEN+1)),$((CLOSE-1))p" "$INSTALLER") "$STATUSLINE"  # expect empty
cp "$STATUSLINE" ~/.claude/statusline-command.sh
```

If only editing the installer's banner / detection / prompts (not the heredoc body), no re-splice is needed.

---

## Editing workflow

1. Edit `statusline-command.sh` in this folder.
2. Test the render directly:
   ```bash
   echo '{"workspace":{"current_dir":"'"$PWD"'"},"model":{"display_name":"Claude Sonnet 4.6"}}' \
     | bash statusline-command.sh
   ```
3. Re-splice into installer (see above).
4. Run `bash install-statusline.sh -y` to update the live installation non-interactively.
5. Verify in a fresh `claude` session.

---

## Critical gotchas

### PUA glyph encoding
Private Use Area characters (U+E000–U+FFFF, used for Nerd Font glyphs) are silently dropped when some tools serialize file contents. Always use bash ANSI-C escape syntax `$'\uXXXX'` in source code — never embedded literal bytes. Bash evaluates the escape at runtime. The single-quoted heredoc `<<'STATUSEOF'` passes the literal text `$'\uXXXX'` through to the installed file, where bash evaluates it on execution.

If a glyph must be written as literal bytes (e.g. to a data file), use Python:
```python
with open(path, 'wb') as f:
    f.write(b'\xef\x8c\x83\n')  # U+F303 Arch logo
```

### Bash tilde in parameter substitution
`${var/#$home/~}` does NOT produce `~` — bash tilde-expands the replacement to `$HOME`, making the substitution a no-op. Always escape the tilde:
```bash
short_cwd="${cwd/#$home/\~}"   # correct
short_cwd="${cwd/#$home/~}"    # WRONG
```

### IFS whitespace collapse with `@tsv` — use `\x1f` + `join` instead

`IFS=$'\t' read` collapses **consecutive tabs**, so empty TSV fields vanish and all subsequent fields shift left. This caused `five_hour.resets_at` (a Unix timestamp) to land in `$five` and render as `Sess: 1780267200%` whenever `five_hour.used_percentage` was null or missing (e.g. at session start).

**Fix:** use a non-whitespace delimiter so `read` never collapses:
```bash
IFS=$'\x1f' read -r cwd model used week five five_reset < <(
  jq -r '[…, (.rate_limits.five_hour.resets_at | numbers | tostring) // ""] | join("")' <<<"$input"
)
```
`\x1f` (ASCII Unit Separator) is not an IFS whitespace character; `read` preserves empty fields. `join("\x1f")` requires all array elements to be strings, so every field must be `tostring`-ed or `// ""` before joining.

### Nerd Font glyph rendering — always put a space after a glyph when text follows

Terminal emulators render Nerd Font PUA glyphs at reduced size when a non-space character immediately follows the glyph. This affects the home icon (`U+F015`) when it appears in the middle of a path:

```bash
# Bad:  🏠/Documents/foo  — terminal renders 🏠 small
# Good: 🏠 /Documents/foo — space gives the glyph a full cell
[[ "$short_cwd" == "${home_icon}/"* ]] && short_cwd="${home_icon} ${short_cwd#${home_icon}}"
```

The distro icon (`_icon`) is unaffected because it already has a hard-coded space after it in the `line1` construction.

### Git status — branch/flags are built in two stages

The git section (runs before palette detection) stores `_git_branch`, `_git_staged`, `_git_modified`, `_git_untracked` as separate variables. The build block (after palette detection) assembles the coloured git segment using those, so each flag can get its own colour:

| Symbol | Colour variable | Meaning |
|---|---|---|
| `✓` (U+F00C) | `_G1` (gradient green) | Working tree clean |
| `+` | `C_ROSE` | Staged changes |
| `!` | `C_GOLD` | Unstaged modifications |
| `?` | `C_MUTED` | Untracked files |

GitHub icon is `nf-fa-github` U+F09B (`$'\xef\x82\x9b'`), always gold. A single space separates the branch name from the flag(s).

### Banner box alignment
The banner uses Unicode box-drawing chars (`╭╮╰╯│─`). All inner rows must have exactly `IW + 2` visible characters between the two `│` borders. ANSI escape sequences (`\033[…m`) are invisible but count toward string length in `printf "%-*s"` — you must subtract them manually when computing the padding width. If the title line looks broken on the right, the padding formula `$((IW - N))` has the wrong `N`.

---

## Performance budget

The statusline runs on **every prompt render** — keep it fast.

| Target | Current |
|---|---|
| No git | ~18ms |
| In git repo | ~28ms |

Rules:
- **One `jq` call max.** Batch all fields via `@tsv` + `IFS=$'\t' read -r …`
- **No subshells in hot paths.** Use `printf -v VAR` to assign, builtin redirect `read -r v < file` to read single values
- **`$EPOCHSECONDS` not `$(date +%s)`** — bash 5.x builtin, zero-fork
- **Git status:** one `git status --porcelain` piped through a `while read` loop, not separate `grep -c` calls
- **Path truncation:** `IFS='/' read -ra _p` + bash arithmetic, not awk

---

## Palette detection (OS-branched)

The probe block is gated on `$OSTYPE` at the top, so macOS and Linux never overlap.

### macOS — terminal emulator (probed in order, first success wins)

1. **Ghostty** — `~/.config/ghostty/config`
   - Reads `theme = <name>` (handles `dark:name, light:name` syntax and names with spaces).
   - Resolves theme file: `~/.config/ghostty/themes/<name>` first, then `/Applications/Ghostty.app/Contents/Resources/ghostty/themes/<name>`.
   - Inline color keys in `config` override the theme file (both fed to `_gh_batch` in order).
   - Parsed in **one awk pass** via `_gh_batch()`.
2. **Alacritty** — `~/.config/alacritty/alacritty.toml` — reuses `_alac_val`.
3. **iTerm2** — `~/Library/Preferences/com.googlecode.iterm2.plist` — `plutil -extract` + `jq`; requires both tools.
4. **Terminal.app** — NSColor blobs in the plist are not decodable from pure bash; falls through to ANSI.
5. ANSI semantic fallback.

### Linux — wallpaper / theme tool (probed in order, first success wins)

1. `~/.config/noctalia/colors.json` — Noctalia Material You
2. `~/.config/matugen/colors.json` or `~/.cache/matugen/colors.json` — Matugen Material You
3. `~/.cache/wallust/colors.json` — Wallust (pywal-compatible 16-color)
4. `~/.cache/wal/colors.json` — Pywal 16-color
5. `~/.config/omarchy/current/theme/alacritty.toml` — Omarchy, parsed with awk
6. ANSI semantic fallback

Wallpaper changes regenerate `colors.json`, so new colors propagate to the statusline automatically — no reinstall needed.

---

## Color role → source key mapping

### Material You (Linux: noctalia / matugen)

| Role | Key | Used for |
|---|---|---|
| `C_IRIS` | `mTertiary` | distro icon, model name |
| `C_ROSE` | `mPrimary` | plan badge |
| `C_GOLD` | `mSecondary` | git info |
| `C_TEXT` | `mOnSurface` | path |
| `C_MUTED` | `mOnSurfaceVariant` | labels, separators |
| `G1`→`G4` | `mPrimary`→`mSecondary`→`mTertiary`→`mError` | usage gradient |

### Ghostty / Alacritty / pywal palette slots

| Role | Slot | Semantic (Rosé Pine Moon example) | Used for |
|---|---|---|---|
| `C_IRIS` | palette 5 (magenta) | `#c4a7e7` iris | distro icon, model name |
| `C_ROSE` | palette 6 (cyan) | `#ea9a97` rose | plan badge |
| `C_GOLD` | palette 3 (yellow) | `#f6c177` gold | git info |
| `C_TEXT` | `foreground` | `#e0def4` text | path |
| `C_MUTED` | palette 8 (bright black) | `#6e6a86` muted | labels, separators |
| `G1` | palette 2 (green) | `#3e8fb0` pine | gradient — low usage |
| `G2` | palette 3 (yellow) | `#f6c177` gold | gradient — medium |
| `G3` | palette 1 (red) | `#eb6f92` love | gradient — high |
| `G4` | palette 9 (bright red) | `#eb6f92` love | gradient — critical |

`grad(p)` and `grad_rem(rem)` smooth-interpolate RGB across four stops at 0/33/66/100%. ANSI fallback uses 4 discrete bands.

---

## Distro glyph mapping

Written to `~/.claude/.distro-icon` at install time. Runtime fallback if missing: U+F31A (`nf-linux-tux`).

All codepoints verified against `ryanoasis/nerd-fonts` `bin/scripts/lib/i_logos.sh` (font-logos set).

| Distro(s) | Codepoint | Glyph name |
|---|---|---|
| macOS | U+F302 | nf-linux-apple |
| arch | U+F303 | nf-linux-archlinux |
| cachyos, archlabs, artix, archcraft, arcolinux | U+F303 | nf-linux-archlinux (no official glyph; arch fallback) |
| omarchy | U+FFF00 | Omarchy logo, patched directly into JetBrainsMono Nerd Font by `nerdfont-patch/` (installer offers this step on Omarchy; falls back to the raw omarchy.ttf codepoint U+E900 rendering as tofu if declined — the terminal font has no glyph there until patched) |
| ubuntu | U+F31B | nf-linux-ubuntu |
| fedora | U+F30A | nf-linux-fedora |
| linuxmint | U+F30E | nf-linux-linuxmint |
| debian | U+F306 | nf-linux-debian |
| manjaro | U+F312 | nf-linux-manjaro |
| endeavouros | U+F322 | nf-linux-endeavour |
| (fallback) | U+F31A | nf-linux-tux |

Arch-derivative distros without their own font-logos glyph fall back to U+F303 (Arch logo).

---

## Testing

**Statusline render (outputs two lines):**
```bash
cd ~/Documents/ccstatusline
printf '%s' '{"workspace":{"current_dir":"'"$PWD"'"},"model":{"display_name":"Claude"}}' \
  | bash statusline-command.sh
```

**Test the timestamp bug fix — all three shapes must be clean (no `<timestamp>%`):**
```bash
cd ~/Documents/ccstatusline
# five=0 → "Sess: 0% (Xh Ym)"
printf '%s' '{"workspace":{"current_dir":"$HOME"},"model":{"display_name":"Sonnet 4.6"},"context_window":{"used_percentage":16},"rate_limits":{"seven_day":{"used_percentage":10},"five_hour":{"used_percentage":0,"resets_at":'"$(( $(date +%s) + 16800 ))"'}}}' | bash statusline-command.sh
# five=null → Sess segment absent, Week still shows
printf '%s' '{"workspace":{"current_dir":"$HOME"},"model":{"display_name":"Sonnet 4.6"},"context_window":{"used_percentage":16},"rate_limits":{"seven_day":{"used_percentage":10},"five_hour":{"used_percentage":null,"resets_at":'"$(( $(date +%s) + 16800 ))"'}}}' | bash statusline-command.sh
# five missing → same
printf '%s' '{"workspace":{"current_dir":"$HOME"},"model":{"display_name":"Sonnet 4.6"},"context_window":{"used_percentage":16},"rate_limits":{"seven_day":{"used_percentage":10},"five_hour":{"resets_at":'"$(( $(date +%s) + 16800 ))"'}}}' | bash statusline-command.sh
```

**Verify macOS Ghostty palette is picked up (expect RGB values matching your theme, not ANSI codes):**
```bash
cd ~/Documents/ccstatusline
printf '%s' '{"workspace":{"current_dir":"'"$HOME"'"},"model":{"display_name":"Opus 4.8"},"context_window":{"used_percentage":4},"rate_limits":{"seven_day":{"used_percentage":48},"five_hour":{"used_percentage":5,"resets_at":'"$(( $(date +%s) + 16800 ))"'}}}' \
  | bash statusline-command.sh | sed 's/\x1b\[/ESC[/g'
# Ghostty active: ESC[38;2;...m (RGB values)
# ANSI fallback:  ESC[95m, ESC[97m etc. (semantic codes)
```

**Force ANSI fallback (move Ghostty config aside):**
```bash
mv ~/.config/ghostty ~/.config/ghostty.bak
echo '{"workspace":{"current_dir":"/tmp"},"model":{"display_name":"Claude"}}' | bash statusline-command.sh
mv ~/.config/ghostty.bak ~/.config/ghostty
```

**Non-interactive full install:**
```bash
bash install-statusline.sh -y
```

**Alacritty font branch (3 paths):**
```bash
# Path 2: [font.normal] exists with wrong family — should rewrite in-place
printf '[font.normal]\nfamily = "JetBrains Mono"\n' > /tmp/al.toml
# run alacritty branch logic; expect single [font.normal] with updated family
grep -c '^\[font\.normal\]' /tmp/al.toml  # should be 1
```

**No-jq guard (M5):** mask jq from PATH — Step 3 should print a red ✗ rather than falsely claiming success.

**No-claude guard (M3):** mask claude from PATH — "Start Claude Code now?" should print a friendly message instead of `exec: not found`.

---

## Where else state lives

| Path | Purpose |
|---|---|
| `~/.claude/statusline-command.sh` | Live installed statusline (what Claude Code invokes) |
| `~/.claude/settings.json` | Registered via `.statusLine.command` key |
| `~/.claude/.distro-icon` | Single-line file: the distro glyph, read at render time |
| `~/.claude/projects/-home-jim/memory/project_statusline_installer.md` | User-scoped memory (persists across all sessions) |
