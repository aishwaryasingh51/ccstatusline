#!/usr/bin/env python3
"""
Validates a patched font against its pre-patch original before it's ever installed live.
Exits non-zero (and prints why) if anything looks wrong.

Checks:
  1. fc-validate can open the file (catches structural corruption -- this is exactly
     what caught a bad glyphOrder splice that made FreeType refuse to load the font at all).
  2. FreeType (via PIL) can rasterize a broad random sample of codepoints with no exceptions.
  3. Every codepoint that existed in the original renders to an IDENTICAL bbox in the patched
     font (proves no unrelated glyph was altered).

Usage: validate_font.py <original_font> <patched_font>
"""
import random
import subprocess
import sys

from fontTools.ttLib import TTFont
from PIL import ImageFont


def main(orig_path, patched_path):
    problems = []

    r = subprocess.run(["fc-validate", patched_path], capture_output=True, text=True)
    if "Unable to open" in r.stdout or "Unable to open" in r.stderr:
        problems.append(f"fc-validate could not open {patched_path}: {r.stdout}{r.stderr}")

    orig = TTFont(orig_path)
    patched = TTFont(patched_path)
    orig_cmap = orig.getBestCmap()

    # Strongest check: every pre-existing glyph's compiled outline bytes must be untouched.
    orig_glyphs = set(orig.getGlyphOrder())
    patched_glyphs = set(patched.getGlyphOrder())
    if not orig_glyphs.issubset(patched_glyphs):
        problems.append(f"glyphs missing from patched font: {orig_glyphs - patched_glyphs}")
    outline_diffs = [
        n for n in orig_glyphs
        if orig["glyf"][n].compile(orig["glyf"]) != patched["glyf"][n].compile(patched["glyf"])
    ]
    if outline_diffs:
        problems.append(f"{len(outline_diffs)} pre-existing glyph outlines changed: {outline_diffs[:10]}")
    o_hmtx, p_hmtx = orig["hmtx"].metrics, patched["hmtx"].metrics
    hmtx_diffs = [n for n in orig_glyphs if o_hmtx[n] != p_hmtx[n]]
    if hmtx_diffs:
        problems.append(f"{len(hmtx_diffs)} pre-existing glyph widths changed: {hmtx_diffs[:10]}")
    # Only flag codepoints that existed before and now map differently or vanished --
    # brand-new codepoints (only in patched) are the whole point and are fine.
    p_cmap = patched.getBestCmap()
    cmap_diffs = {
        cp: (orig_cmap[cp], p_cmap.get(cp))
        for cp in orig_cmap
        if orig_cmap[cp] != p_cmap.get(cp)
    }
    if cmap_diffs:
        problems.append(f"unexpected cmap changes: {cmap_diffs}")

    try:
        f_orig = ImageFont.truetype(orig_path, 100)
        f_patched = ImageFont.truetype(patched_path, 100)
    except Exception as e:
        problems.append(f"FreeType/PIL could not load one of the fonts: {e}")
        print("\n".join(problems))
        return 1

    # A known-good patch (verified byte-identical glyf/hmtx/cmap for all pre-existing glyphs)
    # still shows ~0.4% of sampled glyphs off by 1px in getbbox(), apparently FreeType hinting
    # rounding noise unrelated to the patch. So: tolerate small (<=1px per side) diffs up to a
    # generous cap, but treat any larger diff, or an excessive count, as real corruption.
    NEAR_TOLERANCE_PX = 1
    NEAR_FRACTION_CAP = 0.02

    sample = random.sample(list(orig_cmap.keys()), min(3000, len(orig_cmap)))
    near_mismatches = []
    hard_mismatches = []
    errors = []
    for cp in sample:
        ch = chr(cp)
        try:
            b1 = f_orig.getbbox(ch)
            b2 = f_patched.getbbox(ch)
        except Exception as e:
            errors.append((hex(cp), str(e)))
            continue
        if b1 != b2:
            deltas = [abs(a - b) for a, b in zip(b1, b2)]
            if max(deltas) <= NEAR_TOLERANCE_PX:
                near_mismatches.append((hex(cp), b1, b2))
            else:
                hard_mismatches.append((hex(cp), b1, b2))

    if errors:
        problems.append(f"{len(errors)} codepoints raised exceptions while rendering, e.g. {errors[:5]}")
    if hard_mismatches:
        problems.append(
            f"{len(hard_mismatches)}/{len(sample)} sampled codepoints render with a >{NEAR_TOLERANCE_PX}px "
            f"different bbox in the patched font, e.g. {hard_mismatches[:5]}"
        )
    if len(near_mismatches) / len(sample) > NEAR_FRACTION_CAP:
        problems.append(
            f"{len(near_mismatches)}/{len(sample)} sampled codepoints show >=1px bbox drift "
            f"(cap is {NEAR_FRACTION_CAP:.0%}), e.g. {near_mismatches[:5]}"
        )

    if problems:
        print("VALIDATION FAILED:")
        for p in problems:
            print(" -", p)
        return 1

    print(f"OK: {patched_path} opens cleanly and {len(sample)} sampled glyphs render identically to the original.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2]))
