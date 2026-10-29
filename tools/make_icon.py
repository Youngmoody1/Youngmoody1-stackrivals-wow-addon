"""Draws the StackRivals 'Versus' mark (two red blades crossing in an X, steel diamond at the
crossing) as WoW-ready TGA textures. Original art, generated from code - no external assets."""
import sys
from PIL import Image, ImageDraw

RED = (224, 36, 47, 255)
RED_LIGHT = (240, 80, 90, 255)
STEEL = (143, 192, 221, 255)
NAVY = (10, 14, 26, 255)
NAVY2 = (24, 32, 54, 255)

def blade(draw, S, flip):
    # A long chamfered bar from corner to corner, drawn as a rotated polygon.
    import math
    cx = cy = S / 2
    L, W = S * 0.46, S * 0.085
    ang = math.radians(-45 if flip else 45)
    ca, sa = math.cos(ang), math.sin(ang)
    pts = [(-L, -W), (L - W, -W), (L, 0), (L - W, W), (-L, W), (-L + W * 0.6, 0)]
    poly = [(cx + x * ca - y * sa, cy + x * sa + y * ca) for x, y in pts]
    draw.polygon(poly, fill=RED)
    # stacked horizontal cuts (the "stack" motif) drawn in the background colour later
    return ang

def mark(S, bg):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if bg:
        c = S * 0.14  # chamfered tile: top-left and bottom-right cut
        d.polygon([(c, 0), (S, 0), (S, S - c), (S - c, S), (0, S), (0, c)], fill=NAVY)
        d.polygon([(c, 0), (S, 0), (S, S * 0.04), (c * 0.96, S * 0.04)], fill=RED)
    blade(d, S, False)
    blade(d, S, True)
    # cuts across the blades
    cut = NAVY if bg else (0, 0, 0, 0)
    for k in (-0.2, -0.08, 0.08, 0.2):
        y = S / 2 + k * S
        d.rectangle([S * 0.08, y - S * 0.012, S * 0.92, y + S * 0.012], fill=cut)
    # steel diamond at the crossing
    r = S * 0.075
    d.polygon([(S / 2, S / 2 - r), (S / 2 + r, S / 2), (S / 2, S / 2 + r), (S / 2 - r, S / 2)], fill=STEEL)
    return img

def save(img, size, path):
    img.resize((size, size), Image.LANCZOS).save(path, compression=None)

out = sys.argv[1]
save(mark(512, True), 64, f"{out}/icon.tga")        # AddOn list / compartment icon
save(mark(512, False), 64, f"{out}/mark.tga")       # transparent mark for minimap + header
print("ok")
