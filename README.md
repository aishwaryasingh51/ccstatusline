# ClaudeCode Statusline

An adaptive, theme-aware statusline for [Claude Code](https://claude.ai/code) that shows your current path, git status, active plan, model, context-window usage, and session rate-limit countdown — all in your terminal's own color palette.

![Statusline preview — Rosé Pine Moon theme in Ghostty](https://raw.githubusercontent.com/placeholder/preview.png)

---

## What it looks like

```
 ~/Documents/MyProject
  OpusPlan  Sonnet 4.6 󰍛 16% | Week: 11% | Sess: 25% (4h33m)
 ▶▶ accept edits on  (shift+tab to cycle) · ← for agents
```

- **Line 1** — distro/OS icon + full path (home shown as  icon)
- **Line 2** — plan badge · model · context % · weekly rate-limit · session rate-limit with countdown
- **Line 3** — Claude Code's own mode indicator (always automatic)

Colors are sourced live from your terminal emulator or wallpaper tool — no hardcoded palette.

---

## Features

- **macOS:** reads Ghostty, Alacritty, or iTerm2 config for the active theme's exact hex colors
- **Linux:** reads Noctalia, Matugen, Wallust, pywal, or Omarchy for Material You / pywal palettes
- **ANSI fallback** when no config is found — works everywhere
- **Nerd Font gradient** on usage percentages: green → gold → red as limits approach
- **Distro icon** auto-detected at install time (macOS, Arch, Ubuntu, Fedora, Debian, Manjaro, EndeavourOS, Mint, Omarchy)
- **Zero fork hot path** — `$EPOCHSECONDS`, `printf -v`, bash builtins; ~18–28ms render time

---

## Requirements

- [Claude Code](https://claude.ai/code) CLI
- A [Nerd Font](https://www.nerdfonts.com/) (installer offers to set up JetBrainsMono Nerd Font automatically)
- `jq` (used for JSON parsing)
- bash 5+ (macOS ships bash 3; installer will warn — install via `brew install bash`)

---

## Install

```bash
bash install-statusline.sh
```

The installer will:
1. Detect your OS and terminal emulator
2. Offer to install JetBrainsMono Nerd Font and configure your terminal font
3. Write `~/.claude/statusline-command.sh`
4. Patch `~/.claude/settings.json` to register it

**Non-interactive (accept all defaults):**
```bash
bash install-statusline.sh -y
```

After install, open a new Claude Code session — the statusline appears immediately.

---

## Supported terminals / color sources

| Platform | Source | Notes |
|---|---|---|
| macOS | Ghostty `~/.config/ghostty/config` | Theme file + inline overrides, one awk pass |
| macOS | Alacritty `~/.config/alacritty/alacritty.toml` | TOML parser |
| macOS | iTerm2 `~/Library/Preferences/com.googlecode.iterm2.plist` | `plutil` + `jq` |
| macOS | Terminal.app | Falls through to ANSI (NSColor blobs require a binary decoder) |
| Linux | Noctalia `~/.config/noctalia/colors.json` | Material You |
| Linux | Matugen `~/.config/matugen/colors.json` | Material You |
| Linux | Wallust `~/.cache/wallust/colors.json` | pywal-compatible |
| Linux | pywal `~/.cache/wal/colors.json` | 16-color |
| Linux | Omarchy `~/.config/omarchy/current/theme/alacritty.toml` | |
| Any | ANSI fallback | Used when no config is found |

---

## Statusline fields

| Segment | Source | Notes |
|---|---|---|
| Distro icon | `~/.claude/.distro-icon` | Written at install time |
|  Home icon | Replaces `$HOME` prefix in path | U+F015 nf-fa-home |
| Git branch + flags | `git status --porcelain` | `+` staged · `!` modified · `?` untracked |
| Plan badge | `~/.claude/settings.json` `.model` | Shown in rose/pink |
| Model name | Claude Code JSON input | Shown in iris/purple |
| `󰍛 N%` | `context_window.used_percentage` | Context window used |
| `Week: N%` | `rate_limits.seven_day.used_percentage` | 7-day rolling usage |
| `Sess: N% (Xh Ym)` | `rate_limits.five_hour.*` | 5-hour session usage + countdown to reset |

---

## Manual update / development

The working copy is `statusline-command.sh`. The installer embeds the entire statusline inside a heredoc at lines 303–606 — both must always match (see `CLAUDE.md`).

**Test render:**
```bash
printf '%s' '{"workspace":{"current_dir":"'"$PWD"'"},"model":{"display_name":"Claude Sonnet 4.6"},"context_window":{"used_percentage":10},"rate_limits":{"seven_day":{"used_percentage":20},"five_hour":{"used_percentage":5,"resets_at":'"$(( $(date +%s) + 14400 ))"'}}}' \
  | bash statusline-command.sh
```

**Re-sync after editing `statusline-command.sh`:**
```bash
INSTALLER=~/Documents/CC_Statusline/install-statusline.sh
STATUSLINE=~/Documents/CC_Statusline/statusline-command.sh
head -303 "$INSTALLER" > /tmp/i.sh
cat "$STATUSLINE" >> /tmp/i.sh
tail -n +607 "$INSTALLER" >> /tmp/i.sh
mv /tmp/i.sh "$INSTALLER" && chmod +x "$INSTALLER"
diff <(sed -n '304,606p' "$INSTALLER") "$STATUSLINE"   # expect empty
```

See `CLAUDE.md` for the full developer guide including gotchas, palette mapping tables, and performance notes.

---

## License

MIT
