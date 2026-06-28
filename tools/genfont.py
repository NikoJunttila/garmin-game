#!/usr/bin/env python3
"""Generate a 1-bit Connect IQ bitmap font (AngelCode .fnt + PNG atlas) from a TTF.

The Instinct 3 Solar is a 1-bit MIP panel: no anti-aliasing, no grays. So every
glyph is hard-thresholded to pure black/white before packing. Output matches the
AngelCode BMFont *text* format that the Connect IQ resource compiler accepts
(see the SDK sample Analog/.../fonts/blackdiamond.fnt): a grayscale "L" PNG where
white (255) is the ink that dc.drawText() colorizes, on a black (0) background.

Usage:
    python3 tools/genfont.py --ttf FONT.ttf --size 84 \
        --chars "0123456789:" --out resources/fonts/nordic_hero \
        --threshold 128 --mono-digits

Writes <out>.fnt and <out>_0.png (the .fnt references the PNG by sibling filename).
"""

import argparse
import os
import sys

from PIL import Image, ImageDraw, ImageFont


def render_glyph(font, ch, threshold):
    """Render one character to a tight 1-bit (0/255) numpy-free bitmap.

    Returns (pixels, w, h, ink_left, ink_top, advance) where pixels is a flat
    list of 0/255 ints row-major, and ink_left/ink_top locate the ink box
    relative to the pen origin with the baseline at y=ascent (see caller).
    """
    ascent, descent = font.getmetrics()
    line_h = ascent + descent
    advance = round(font.getlength(ch))

    # Draw onto a canvas tall enough for the whole line, baseline at ascent.
    # A generous left/right margin avoids clipping italic/overhanging glyphs.
    pad = max(8, line_h)
    canvas_w = advance + 2 * pad
    canvas_h = line_h + 2 * pad
    img = Image.new("L", (canvas_w, canvas_h), 0)
    draw = ImageDraw.Draw(img)
    # Anchor "la" = left edge, ascender line; so the baseline sits at y+ascent.
    # We draw at (pad, pad) meaning cell-top is at y=pad, baseline at pad+ascent.
    draw.text((pad, pad), ch, fill=255, font=font)

    # Hard threshold: kill all anti-aliasing -> pure 1-bit.
    img = img.point(lambda v: 255 if v >= threshold else 0, mode="L")

    bbox = img.getbbox()  # (l, t, r, b) of non-zero ink, or None for blank
    if bbox is None:
        return [], 0, 0, 0, 0, advance

    l, t, r, b = bbox
    w, h = r - l, b - t
    crop = img.crop(bbox)
    px = list(crop.tobytes())  # mode "L" -> one byte (0 or 255) per pixel, row-major

    # ink_left/ink_top relative to the pen cell origin (cell-top = pad).
    ink_left = l - pad
    ink_top = t - pad
    return px, w, h, ink_left, ink_top, advance


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--ttf", required=True, help="path to a .ttf")
    ap.add_argument("--size", type=int, required=True, help="pixel size")
    ap.add_argument("--chars", required=True, help="glyphs to include")
    ap.add_argument("--out", required=True, help="output prefix (no extension)")
    ap.add_argument("--threshold", type=int, default=128, help="0-255 ink cutoff")
    ap.add_argument("--pad", type=int, default=1, help="px between glyphs in atlas")
    ap.add_argument("--mono-digits", action="store_true",
                    help="force 0-9 to a uniform advance (clock never jitters)")
    ap.add_argument("--colon-rise", type=int, default=0,
                    help="raise ':' by N px (negative lowers) for optical centering")
    ap.add_argument("--preview", action="store_true",
                    help="print an ASCII preview of each glyph")
    args = ap.parse_args()

    if not os.path.isfile(args.ttf):
        sys.exit(f"TTF not found: {args.ttf}")

    font = ImageFont.truetype(args.ttf, args.size)
    ascent, descent = font.getmetrics()
    line_h = ascent + descent
    base = ascent

    glyphs = []  # dicts: ch, code, px, w, h, xoff, yoff, adv
    for ch in args.chars:
        px, w, h, ink_left, ink_top, adv = render_glyph(font, ch, args.threshold)
        xoff = ink_left
        yoff = ink_top  # distance from cell-top to first inked row
        if ch == ":" and args.colon_rise:
            yoff -= args.colon_rise
        glyphs.append({
            "ch": ch, "code": ord(ch), "px": px, "w": w, "h": h,
            "xoff": xoff, "yoff": yoff, "adv": adv,
        })

    # Mono-width digits: every 0-9 advances by the widest digit (centered).
    if args.mono_digits:
        digit_advs = [g["adv"] for g in glyphs if g["ch"].isdigit()]
        if digit_advs:
            mono = max(digit_advs)
            for g in glyphs:
                if g["ch"].isdigit():
                    g["xoff"] += (mono - g["adv"]) // 2  # center in the wider cell
                    g["adv"] = mono

    # Pack glyphs left-to-right in a single row.
    atlas_h = max((g["h"] for g in glyphs), default=1) + 2 * args.pad
    x = args.pad
    placements = []  # (g, ax, ay)
    for g in glyphs:
        placements.append((g, x, args.pad))
        x += g["w"] + args.pad
    atlas_w = max(x + args.pad, 1)

    atlas = Image.new("L", (atlas_w, atlas_h), 0)
    for g, ax, ay in placements:
        if g["w"] and g["h"]:
            glyph_img = Image.new("L", (g["w"], g["h"]))
            glyph_img.putdata(g["px"])
            atlas.paste(glyph_img, (ax, ay))
        g["ax"], g["ay"] = ax, ay

    png_name = os.path.basename(args.out) + "_0.png"
    png_path = args.out + "_0.png"
    fnt_path = args.out + ".fnt"
    os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
    atlas.save(png_path, "PNG", optimize=True)

    face = os.path.splitext(os.path.basename(args.ttf))[0]
    lines = []
    lines.append(
        f'info face="{face}" size=-{args.size} bold=0 italic=0 charset="" '
        f'unicode=1 stretchH=100 smooth=0 aa=0 padding=0,0,0,0 spacing=1,1 outline=0'
    )
    lines.append(
        f'common lineHeight={line_h} base={base} scaleW={atlas_w} scaleH={atlas_h} '
        f'pages=1 packed=0 alphaChnl=1 redChnl=0 greenChnl=0 blueChnl=0'
    )
    lines.append(f'page id=0 file="{png_name}"')
    lines.append(f'chars count={len(glyphs)}')
    for g in glyphs:
        lines.append(
            f'char id={g["code"]:<5} x={g["ax"]:<5} y={g["ay"]:<5} '
            f'width={g["w"]:<5} height={g["h"]:<5} xoffset={g["xoff"]:<5} '
            f'yoffset={g["yoff"]:<5} xadvance={g["adv"]:<5} page=0 chnl=15'
        )
    lines.append("kernings count=0")
    with open(fnt_path, "w") as f:
        f.write("\n".join(lines) + "\n")

    print(f"Wrote {fnt_path} and {png_path}")
    print(f"  face={face} size={args.size} lineHeight={line_h} base={base} "
          f"atlas={atlas_w}x{atlas_h} png={os.path.getsize(png_path)}B "
          f"glyphs={len(glyphs)}")

    if args.preview:
        for g in glyphs:
            print(f"\n'{g['ch']}' (w={g['w']} h={g['h']} xoff={g['xoff']} "
                  f"yoff={g['yoff']} adv={g['adv']}):")
            if not g["w"]:
                print("  (blank)")
                continue
            for row in range(g["h"]):
                line = "".join(
                    "#" if g["px"][row * g["w"] + col] else "." for col in range(g["w"])
                )
                print("  " + line)


if __name__ == "__main__":
    main()
