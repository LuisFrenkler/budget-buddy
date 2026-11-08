"""Draws the app icons: the white "b" (stem and coin ring) on the brand copper.

Same geometry as MarkPainter in lib/widgets/brand.dart, on a 1024 grid.
Run from budget_buddy/:  python3 tool/make_icons.py
then:  dart run flutter_launcher_icons && dart run flutter_native_splash:create
"""
from PIL import Image, ImageDraw

COPPER = (0xB0, 0x60, 0x30, 255)
WHITE = (255, 255, 255, 255)
SS = 4  # supersampling for smooth edges


def glyph(d, x, y, size):
    s = size / 1024
    w = 118 * s
    d.rounded_rectangle([x + 277 * s, y + 210 * s, x + 277 * s + w, y + 812 * s], radius=w / 2, fill=WHITE)
    cx, cy = x + 529 * s, y + 594 * s
    d.ellipse([cx - 218 * s, cy - 218 * s, cx + 218 * s, cy + 218 * s], fill=WHITE)
    return cx, cy, s


def draw(path, square, radius_share, full_bleed=False, transparent_bg=False):
    n = 1024 * SS
    img = Image.new('RGBA', (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    x0 = (1024 - square) / 2 * SS
    size = square * SS
    if not transparent_bg:
        if full_bleed:
            d.rectangle([0, 0, n, n], fill=COPPER)
        else:
            d.rounded_rectangle([x0, x0, x0 + size, x0 + size], radius=size * radius_share, fill=COPPER)
    cx, cy, s = glyph(d, x0, x0, size)
    # the ring's hole shows whatever is behind the mark
    hole = (0, 0, 0, 0) if transparent_bg else COPPER
    d.ellipse([cx - 104 * s, cy - 104 * s, cx + 104 * s, cy + 104 * s], fill=hole)
    img.resize((1024, 1024), Image.LANCZOS).save(path)


draw('assets/icon/icon.png', 1024, 0, full_bleed=True)
draw('assets/icon/icon_fg.png', 700, 0, transparent_bg=True)
draw('assets/icon/splash.png', 440, 0.23)
draw('assets/icon/splash_android12.png', 560, 0.23)
