"""Draws the Loot Duel icon (an original cut gem in WoW's epic purple on a dark tile with a gold
rim) as a WoW-ready 64x64 TGA.

    python3 tools/make_loot_icon.py StackRivals/Media     -> lootduel.tga

Supersampled, transparent corners bled (see make_icon.bleed) so small sizes stay clean.
"""
import os
import sys
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(__file__))
from make_icon import bleed  # noqa: E402

SS = 8
N = 64 * SS
GOLD = (0xF2, 0xCF, 0x6B, 255)
GOLD_DEEP = (0x8A, 0x6A, 0x22, 255)
TILE = (0x10, 0x16, 0x2A, 255)
EPIC = (0xA3, 0x35, 0xEE)


def shade(c, f, a=255):
    return (max(0, min(255, int(c[0] * f))), max(0, min(255, int(c[1] * f))), max(0, min(255, int(c[2] * f))), a)


def p(*pts):
    return [(x * SS, y * SS) for x, y in pts]


def main(out):
    im = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    # tile with a gold rim
    d.rounded_rectangle([1 * SS, 1 * SS, 63 * SS, 63 * SS], radius=10 * SS, fill=GOLD_DEEP)
    d.rounded_rectangle([3 * SS, 3 * SS, 61 * SS, 61 * SS], radius=8 * SS, fill=GOLD)
    d.rounded_rectangle([5 * SS, 5 * SS, 59 * SS, 59 * SS], radius=7 * SS, fill=TILE)
    # the gem: crown (top) and pavilion (bottom point), facets in light / dark purple
    L, R, T, G, B = 12, 52, 18, 28, 54   # left, right, top, girdle, bottom tip
    a, b = 22, 42                         # table edges
    m = 32
    d.polygon(p((L, G), (a, T), (b, T), (R, G), (m, B)), fill=shade(EPIC, 0.75))
    d.polygon(p((a, T), (b, T), (38, G), (26, G)), fill=shade(EPIC, 1.25))       # table
    d.polygon(p((L, G), (a, T), (26, G)), fill=shade(EPIC, 1.05))
    d.polygon(p((R, G), (b, T), (38, G)), fill=shade(EPIC, 0.9))
    d.polygon(p((L, G), (26, G), (m, B)), fill=shade(EPIC, 0.85))                  # pavilion
    d.polygon(p((26, G), (38, G), (m, B)), fill=shade(EPIC, 1.1))
    d.polygon(p((38, G), (R, G), (m, B)), fill=shade(EPIC, 0.6))
    # gold outline and a small sparkle
    d.line(p((L, G), (a, T), (b, T), (R, G), (m, B), (L, G)), fill=GOLD, width=int(1.6 * SS), joint="curve")
    d.line(p((L, G), (R, G)), fill=shade(GOLD, 0.85), width=int(1.0 * SS))
    d.polygon(p((47, 9), (48.5, 13), (52.5, 14.5), (48.5, 16), (47, 20), (45.5, 16), (41.5, 14.5), (45.5, 13)), fill=(255, 246, 214, 255))
    small = im.resize((64, 64), Image.LANCZOS)
    os.makedirs(out, exist_ok=True)
    bleed(small).save(os.path.join(out, "lootduel.tga"), compression=None)
    small.save("/tmp/lootduel_preview.png")
    print("lootduel.tga")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "StackRivals/Media")
