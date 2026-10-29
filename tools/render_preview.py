"""Developer previews of every StackRivals screen, drawn from the addon's real layout code running
in the WoW API mock (tests/screens.lua -> tests/layout.lua dump). NOT in-game screenshots:
fonts and text metrics are approximations, Blizzard textures are placeholders.

    lua5.1 tests/dump_screens.lua <outdir>    (writes <name>.txt dumps)
    python3 tools/render_preview.py <outdir> <addon Media dir>
"""
import glob, os, sys
from PIL import Image, ImageDraw, ImageFont

SCALE = 2  # render at 2x for crisp text
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed.ttf"
FONT_B = "/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf"
BANNER = "DEVELOPER PREVIEW - generated from the addon layout code, not an in-game screenshot"


def load_tex(media, path):
    name = path.replace("\\", "/").split("/")[-1].lower()
    for ext in (".tga", ".png", ""):
        p = os.path.join(media, name + ext)
        if os.path.isfile(p):
            return Image.open(p).convert("RGBA")
    return None


def render(dump, media, out_png):
    rows = [l.rstrip("\n").split("\t") for l in open(dump, encoding="utf-8")]
    _, w, h, title = rows[0]
    w, h = int(w), int(h)
    pad, top = 24, 56
    img = Image.new("RGBA", ((w + pad * 2) * SCALE, (h + pad * 2 + top) * SCALE), (36, 30, 26, 255))
    d = ImageDraw.Draw(img, "RGBA")
    # backdrop that hints "game world" behind the window
    for i in range(0, img.size[1], 6 * SCALE):
        d.line([(0, i), (img.size[0], i)], fill=(44, 37, 32, 255))
    ox, oy = pad, pad + top

    def box(l, b, r, t):
        return ((ox + l) * SCALE, (oy + h - t) * SCALE, (ox + r) * SCALE, (oy + h - b) * SCALE)

    for row in rows[1:]:
        kind = row[0]
        if kind == "RECT":
            l, b, r, t, cr, cg, cb, a = map(float, row[1:9])
            if a <= 0.001 or r - l <= 0 or t - b <= 0:
                continue
            layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
            ImageDraw.Draw(layer).rectangle(box(l, b, r, t), fill=(int(cr * 255), int(cg * 255), int(cb * 255), int(a * 255)))
            img = Image.alpha_composite(img, layer)
            d = ImageDraw.Draw(img, "RGBA")
        elif kind == "IMG":
            l, b, r, t, a = map(float, row[1:6])
            tex = load_tex(media, row[6])
            x0, y0, x1, y1 = map(int, box(l, b, r, t))
            if x1 <= x0 or y1 <= y0:
                continue
            if tex is None:  # Blizzard texture we don't have: neutral placeholder ring
                d.ellipse((x0, y0, x1, y1), outline=(150, 150, 150, int(160 * a)), width=SCALE)
                continue
            tex = tex.resize((x1 - x0, y1 - y0), Image.LANCZOS)
            if a < 1:
                alpha = tex.split()[3].point(lambda v: int(v * a))
                tex.putalpha(alpha)
            img.alpha_composite(tex, (x0, y0))
            d = ImageDraw.Draw(img, "RGBA")
        elif kind == "TEXT":
            l, b, r, t, cr, cg, cb, a = map(float, row[1:9])
            size, justify, flags, text = int(row[9]), row[10], row[11], row[12]
            if a <= 0.02:
                continue
            font = ImageFont.truetype(FONT_B if size >= 14 else FONT, int(size * SCALE * 1.02))
            color = (int(cr * 255), int(cg * 255), int(cb * 255), int(a * 255))
            lines = text.split("\\n")
            x0, y0, x1, y1 = box(l, b, r, t)
            lh = size * 1.2 * SCALE
            total = lh * len(lines)
            y = (y0 + y1) / 2 - total / 2
            for line in lines:
                tw = d.textlength(line, font=font)
                if justify == "LEFT":
                    x = x0
                elif justify == "RIGHT":
                    x = x1 - tw
                else:
                    x = (x0 + x1) / 2 - tw / 2
                if "OUTLINE" in flags:
                    for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                        d.text((x + dx * SCALE, y + dy * SCALE), line, font=font, fill=(0, 0, 0, color[3]))
                d.text((x + SCALE, y + SCALE), line, font=font, fill=(0, 0, 0, int(color[3] * 0.7)))
                d.text((x, y), line, font=font, fill=color)
                y += lh
    # banner
    bf = ImageFont.truetype(FONT_B, 13 * SCALE)
    sf = ImageFont.truetype(FONT, 12 * SCALE)
    d.rectangle((0, 0, img.size[0], 44 * SCALE), fill=(242, 207, 107, 255))
    d.text((12 * SCALE, 6 * SCALE), title, font=bf, fill=(10, 14, 26, 255))
    d.text((12 * SCALE, 24 * SCALE), BANNER, font=sf, fill=(60, 50, 20, 255))
    img.convert("RGB").save(out_png, optimize=True)
    return img


def main():
    outdir, media = sys.argv[1], sys.argv[2]
    pngs = []
    for dump in sorted(glob.glob(os.path.join(outdir, "*.txt"))):
        png = dump[:-4] + ".png"
        render(dump, media, png)
        pngs.append(png)
    # contact sheet
    ims = [Image.open(p) for p in pngs]
    cols = 4
    cw, ch = max(i.size[0] for i in ims), max(i.size[1] for i in ims)
    sheet = Image.new("RGB", (cw * cols // 2, ch * ((len(ims) + cols - 1) // cols) // 2), (20, 20, 20))
    for k, im in enumerate(ims):
        im = im.resize((im.size[0] // 2, im.size[1] // 2), Image.LANCZOS)
        sheet.paste(im, ((k % cols) * cw // 2, (k // cols) * ch // 2))
    sheet.save(os.path.join(outdir, "overview.png"), optimize=True)
    print("\n".join(pngs + [os.path.join(outdir, "overview.png")]))


if __name__ == "__main__":
    main()
