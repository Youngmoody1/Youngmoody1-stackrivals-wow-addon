"""Draws Loot Duel status icons (original, simple shapes) as WoW-ready 32x32 TGAs, so a status never
depends on colour alone:

    python3 tools/make_status_icons.py StackRivals/Media/Status

    winner.tga  trophy, green        lost.tga     cross in a circle, red
    passed.tga  minus in a circle, red   tie.tga  equals sign, gold
    playing.tga play triangle, steel     unknown.tga  question mark, amber (not checked)
    warn.tga    exclamation, amber (no result / disconnected / replay failed)
    ready.tga   check mark, green (joined / ready)
    done.tga    flag, grey (run over: topped out / time up, not checked yet)
"""
import os
import sys
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(__file__))
from make_icon import bleed  # noqa: E402

SS = 8
N = 32 * SS
GREEN = (0x7B, 0xE3, 0xA0, 255)
RED = (0xFF, 0x4D, 0x5A, 255)
GOLD = (0xF2, 0xCF, 0x6B, 255)
STEEL = (0x4F, 0xA8, 0xFF, 255)
AMBER = (0xE8, 0xA0, 0x40, 255)
GREY = (0xA8, 0xB0, 0xC0, 255)


def p(*pts):
    return [(x * SS, y * SS) for x, y in pts]


def canvas():
    im = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    return im, ImageDraw.Draw(im)


def ring(d, c, w=2.6):
    d.ellipse([3 * SS, 3 * SS, 29 * SS, 29 * SS], outline=c, width=int(w * SS))


def save(im, out, name):
    bleed(im.resize((32, 32), Image.LANCZOS)).save(os.path.join(out, name + ".tga"), compression=None)


def main(out):
    os.makedirs(out, exist_ok=True)
    im, d = canvas()  # trophy
    d.polygon(p((9, 6), (23, 6), (22, 14), (19, 18), (13, 18), (10, 14)), fill=GREEN)
    d.arc([3 * SS, 6 * SS, 12 * SS, 15 * SS], 90, 270, fill=GREEN, width=int(2 * SS))
    d.arc([20 * SS, 6 * SS, 29 * SS, 15 * SS], 270, 90, fill=GREEN, width=int(2 * SS))
    d.rectangle([14.5 * SS, 18 * SS, 17.5 * SS, 23 * SS], fill=GREEN)
    d.rectangle([10 * SS, 23 * SS, 22 * SS, 26.5 * SS], fill=GREEN)
    save(im, out, "winner")
    im, d = canvas()  # cross
    ring(d, RED)
    d.line(p((11, 11), (21, 21)), fill=RED, width=int(3 * SS)); d.line(p((21, 11), (11, 21)), fill=RED, width=int(3 * SS))
    save(im, out, "lost")
    im, d = canvas()  # minus
    ring(d, RED)
    d.rectangle([10 * SS, 14.5 * SS, 22 * SS, 17.5 * SS], fill=RED)
    save(im, out, "passed")
    im, d = canvas()  # equals
    d.rectangle([7 * SS, 10 * SS, 25 * SS, 13.5 * SS], fill=GOLD); d.rectangle([7 * SS, 18.5 * SS, 25 * SS, 22 * SS], fill=GOLD)
    save(im, out, "tie")
    im, d = canvas()  # play
    d.polygon(p((10, 7), (25, 16), (10, 25)), fill=STEEL)
    save(im, out, "playing")
    im, d = canvas()  # question
    ring(d, AMBER)
    d.arc([11 * SS, 8 * SS, 21 * SS, 17 * SS], 200, 70, fill=AMBER, width=int(2.6 * SS))
    d.line(p((17.7, 15.7), (16, 18), (16, 20)), fill=AMBER, width=int(2.6 * SS))
    d.ellipse([14.6 * SS, 22 * SS, 17.4 * SS, 24.8 * SS], fill=AMBER)
    save(im, out, "unknown")
    im, d = canvas()  # exclamation
    d.polygon(p((16, 3), (30, 28), (2, 28)), outline=AMBER, width=int(2.4 * SS))
    d.rectangle([14.7 * SS, 11 * SS, 17.3 * SS, 20 * SS], fill=AMBER)
    d.ellipse([14.6 * SS, 22 * SS, 17.4 * SS, 24.8 * SS], fill=AMBER)
    save(im, out, "warn")
    im, d = canvas()  # check
    d.line(p((7, 17), (13, 23), (25, 9)), fill=GREEN, width=int(3.4 * SS), joint="curve")
    save(im, out, "ready")
    im, d = canvas()  # finish flag
    d.rectangle([8 * SS, 5 * SS, 10.4 * SS, 28 * SS], fill=GREY)
    d.polygon(p((10.4, 5), (25, 9.5), (10.4, 14)), fill=GREY)
    save(im, out, "done")
    print("9 icons")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "StackRivals/Media/Status")
