"""Draws the StackRivals "Versus" mark as WoW-ready TGA textures, from the exact geometry of the
website's brand mark (src/components/brand/BrandMark.tsx in the web project: MarkE / MarkESmall,
64x64 viewBox). Cuts and gaps are transparent, so the mark works on any background.

    python3 tools/make_icon.py StackRivals/Media

    mark.tga       128x128  full mark (blades, two horizontal cuts, steel diamond)  - header
    marksmall.tga   64x64   simplified mark (thicker blades, one gap, no cuts)       - minimap, <32 px
    icon.tga        64x64   simplified mark on the dark rounded tile (web favicon)   - AddOn list
    glow.tga       256x256  soft red radial glow (alpha only)                         - window halo

Transparent pixels get the colour of their nearest opaque neighbour ("bleed"), so bilinear
filtering at small sizes never pulls black into the red edges.
"""
import sys
from PIL import Image, ImageDraw

RED = (0xE0, 0x24, 0x2F)
STEEL = (0x4F, 0xA8, 0xFF)
INK = (0x0B, 0x0C, 0x10)
SS = 8  # supersampling


def poly(d, pts, k, fill, ox=0.0, oy=0.0, s=1.0):
    d.polygon([((ox + x * s) * k, (oy + y * s) * k) for x, y in pts], fill=fill)


def stroke(d, pts, k, width, fill, ox=0.0, oy=0.0, s=1.0):
    p = [((ox + x * s) * k, (oy + y * s) * k) for x, y in pts]
    d.line(p + [p[0], p[1]], fill=fill, width=max(1, int(round(width * s * k))), joint="curve")


def full_mark(size):
    """MarkE: polygons 5,5 20,5 59,59 44,59 / 44,5 59,5 20,59 5,59 (stroke 3.5 in the cut colour),
    cut rects y=19..22 and y=42..45, steel diamond 32,28 35.5,32 32,36 28.5,32."""
    k = size * SS / 64.0
    red = Image.new("L", (size * SS, size * SS), 0)
    d = ImageDraw.Draw(red)
    a = [(5, 5), (20, 5), (59, 59), (44, 59)]
    b = [(44, 5), (59, 5), (20, 59), (5, 59)]
    poly(d, a, k, 255)
    stroke(d, b, k, 3.5, 0)           # the gap where blade b crosses blade a
    poly(d, b, k, 255)
    d.rectangle([0, 19 * k, 64 * k, 22 * k], fill=0)
    d.rectangle([0, 42 * k, 64 * k, 45 * k], fill=0)
    steel = Image.new("L", red.size, 0)
    poly(ImageDraw.Draw(steel), [(32, 28), (35.5, 32), (32, 36), (28.5, 32)], k, 255)
    return compose(size, [(red, RED), (steel, STEEL)])


def small_mark(size, ox=0.0, oy=0.0, s=1.0, tile=False):
    """MarkESmall: 2,4 22,4 62,60 42,60 / 42,4 62,4 22,60 2,60 with a 6-wide gap stroke."""
    k = size * SS / 64.0
    red = Image.new("L", (size * SS, size * SS), 0)
    d = ImageDraw.Draw(red)
    a = [(2, 4), (22, 4), (62, 60), (42, 60)]
    b = [(42, 4), (62, 4), (22, 60), (2, 60)]
    poly(d, a, k, 255, ox, oy, s)
    stroke(d, b, k, 6, 0, ox, oy, s)
    poly(d, b, k, 255, ox, oy, s)
    layers = [(red, RED)]
    if tile:  # favicon: rounded ink tile rx=12 behind the mark
        bg = Image.new("L", red.size, 0)
        ImageDraw.Draw(bg).rounded_rectangle([0, 0, size * SS - 1, size * SS - 1], radius=12 * k, fill=255)
        layers.insert(0, (bg, INK))
    return compose(size, layers)


def compose(size, layers):
    out = Image.new("RGBA", layers[0][0].size, (0, 0, 0, 0))
    for mask, rgb in layers:
        out.paste(Image.new("RGBA", out.size, rgb + (255,)), (0, 0), mask)
    return bleed(out.resize((size, size), Image.LANCZOS))


def bleed(img, passes=8):
    """Give fully transparent pixels the RGB of an opaque neighbour (alpha unchanged)."""
    w, h = img.size
    px = img.load()
    known = [[px[x, y][3] > 0 for y in range(h)] for x in range(w)]
    for _ in range(passes):
        fill = []
        for x in range(w):
            for y in range(h):
                if known[x][y]:
                    continue
                acc, n = [0, 0, 0], 0
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and known[nx][ny]:
                        r, g, b, _ = px[nx, ny]
                        acc[0] += r; acc[1] += g; acc[2] += b; n += 1
                if n:
                    fill.append((x, y, tuple(c // n for c in acc)))
        if not fill:
            break
        for x, y, rgb in fill:
            px[x, y] = rgb + (0,)
            known[x][y] = True
    return img


def glow(size):
    """Radial falloff, solid red RGB everywhere; only alpha varies (smooth, no banding)."""
    img = Image.new("RGBA", (size, size), RED + (0,))
    px = img.load()
    c = (size - 1) / 2.0
    for y in range(size):
        for x in range(size):
            d = (((x - c) ** 2 + (y - c) ** 2) ** 0.5) / c
            a = max(0.0, 1.0 - d)
            px[x, y] = RED + (int(round(255 * a * a)),)
    return img


def save(img, path):
    img.save(path, compression=None)  # uncompressed TGA (WoW reads it on every client)


if __name__ == "__main__":
    out = sys.argv[1]
    save(full_mark(128), f"{out}/mark.tga")
    save(small_mark(64), f"{out}/marksmall.tga")
    # favicon.svg: <rect rx=12 fill=#0b0c10/> + MarkESmall at translate(6 6) scale(0.8125)
    save(small_mark(64, ox=6, oy=6, s=0.8125, tile=True), f"{out}/icon.tga")
    save(glow(256), f"{out}/glow.tga")
    print("ok")
