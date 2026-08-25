#!/usr/bin/env python3
"""
Splices the Omarchy logo glyph (from /usr/share/fonts/omarchy/omarchy.ttf, U+E900)
into a JetBrains Mono Nerd Font weight at U+FFF00, sized to match nf-fa-home (U+F015).

Table-level splice only (glyf/hmtx/cmap) -- never calls a full font regenerate/resave
pipeline (e.g. FontForge's font.generate()), which was found to silently corrupt
unrelated glyph outlines. Every other glyph in the output is byte-identical to the input.

Usage: patch_font.py <src_icon_font> <dst_font_in> <dst_font_out>
"""
import sys
import copy
from fontTools.ttLib import TTFont

SRC_CODEPOINT = 0xE900
TARGET_CODEPOINT = 0xFFF00
REFERENCE_CODEPOINT = 0xF015  # nf-fa-home: height/baseline to match
GLYPH_NAME = "omarchy-logo"


def patch(src_icon_font_path, dst_font_in_path, dst_font_out_path):
    src = TTFont(src_icon_font_path)
    dst = TTFont(dst_font_in_path)

    src_gname = src.getBestCmap()[SRC_CODEPOINT]
    src_glyph = src["glyf"][src_gname]
    if src_glyph.isComposite():
        raise SystemExit(f"source glyph {src_gname} is composite; script assumes simple glyph")

    home_gname = dst.getBestCmap()[REFERENCE_CODEPOINT]
    home_glyph = dst["glyf"][home_gname]
    home_glyph.recalcBounds(dst["glyf"])
    home_ymin, home_ymax = home_glyph.yMin, home_glyph.yMax
    home_height = home_ymax - home_ymin
    cell_width = dst["hmtx"]["A"][0]

    src_glyph.recalcBounds(src["glyf"])
    raw_ymin, raw_ymax = src_glyph.yMin, src_glyph.yMax
    raw_xmin = src_glyph.xMin
    raw_h = raw_ymax - raw_ymin

    scale = home_height / raw_h
    tx = -raw_xmin * scale
    ty = home_ymin - raw_ymin * scale

    new_glyph = copy.deepcopy(src_glyph)
    new_glyph.coordinates.scale((scale, scale))
    new_glyph.coordinates.translate((tx, ty))
    new_glyph.recalcBounds(src["glyf"])

    dst["glyf"].glyphs[GLYPH_NAME] = new_glyph
    new_order = dst.getGlyphOrder() + [GLYPH_NAME]
    dst.setGlyphOrder(new_order)  # canonical API only -- do NOT also set glyf.glyphOrder by hand
    dst["hmtx"][GLYPH_NAME] = (cell_width, 0)

    for t in dst["cmap"].tables:
        if t.format == 12:
            t.cmap[TARGET_CODEPOINT] = GLYPH_NAME

    dst["maxp"].numGlyphs = len(new_order)

    dst.save(dst_font_out_path)
    return new_glyph.xMin, new_glyph.yMin, new_glyph.xMax, new_glyph.yMax


if __name__ == "__main__":
    src_icon_font, dst_in, dst_out = sys.argv[1:4]
    bbox = patch(src_icon_font, dst_in, dst_out)
    print(f"patched {dst_out}: new glyph bbox={bbox}")
