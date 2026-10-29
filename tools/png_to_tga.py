"""PNG -> WoW TGA (64x64, uncompressed, RGB bled into transparent pixels).

    python3 tools/png_to_tga.py <png dir> StackRivals/Media/Spells
Used for the spell icons rendered by tools/make_spell_icons.mjs.
"""
import os
import sys
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from make_icon import bleed  # noqa: E402

src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
n = 0
for f in sorted(os.listdir(src)):
    if f.endswith(".png"):
        im = Image.open(os.path.join(src, f)).convert("RGBA").resize((64, 64), Image.LANCZOS)
        bleed(im).save(os.path.join(out, f[:-4] + ".tga"), compression=None)
        n += 1
print(n, "icons")
