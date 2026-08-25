# Omarchy Nerd Font patch

Splices the real [Omarchy](https://omarchy.org) logo into JetBrainsMono Nerd Font at `U+FFF00`, sized to match `nf-fa-home` (`U+F015`) so it sits correctly next to other glyphs in a bar or prompt. Normally invoked by `../install-statusline.sh` on Omarchy; can also be run standalone.

## Standalone usage

```bash
python -m pip install --user fonttools pillow   # or: sudo pacman -S python-fonttools python-pillow
sudo bash apply.sh
```

Patches all 4 installed `JetBrainsMonoNerdFont-{Regular,Bold,Italic,BoldItalic}.ttf` weights in `/usr/share/fonts/TTF/`. Requires `/usr/share/fonts/omarchy/omarchy.ttf` (ships with the `omarchy-settings` package). Idempotent and safe to re-run — always backs up the pristine pre-patch font as `*.ttf.orig` on first run, and re-patches from that backup (never from a previously-patched file) on subsequent runs.

## How it works

`patch_font.py` does a table-level splice only (`glyf`/`hmtx`/`cmap`) — it never calls a full font regenerate/resave pipeline, which was found to silently corrupt unrelated glyph outlines. Every glyph other than the new one is byte-identical to the input. `validate_font.py` then checks the result before `apply.sh` ever lets it touch a live system font: `fc-validate` can open it, FreeType can rasterize a broad random sample of codepoints with no exceptions, and every pre-existing codepoint renders to an identical bbox.

## Licensing

Nothing here redistributes font bytes — it's a transformation tool that runs against fonts already on your machine, installed via your own package manager.

- `ttf-jetbrains-mono-nerd` is `OFL-1.1-no-RFN` (SIL Open Font License) — explicitly permits modifying and redistributing fonts; conditions are keeping the copyright/license notice with any redistributed copy, not selling the font by itself, and not implying JetBrains endorses the modified version.
- `omarchy.ttf` (the glyph source, from the `omarchy-settings` package) is MIT licensed, from [basecamp/omarchy](https://github.com/basecamp/omarchy).

This is an unofficial, community-made patch — not affiliated with or endorsed by JetBrains or Basecamp/Omarchy.
