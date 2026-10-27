"""Centres the white "b" inside the violet square of the app icons.

The glyph sat 4.5 % right of the square's centre (a geometric centre would
put a "b" visibly right because of its stem, but here the bounding box itself
was off). The square's background is re-created where the glyph was (a smooth surface
fitted to the rest of the square), and the glyph is laid on top again, moved.

Run from budget_buddy/:  python3 tool/center_icon_glyph.py
then:  dart run flutter_launcher_icons && dart run flutter_native_splash:create
"""
import sys
import numpy as np
from PIL import Image

FILES = ['assets/icon/icon.png', 'assets/icon/splash.png', 'assets/icon/splash_android12.png', 'assets/icon/icon_fg.png']


def is_square(px):
    r, g, b, a = px[..., 0], px[..., 1], px[..., 2], px[..., 3]
    return (a > 200) & (b > 150) & (r < 190) & (g < 140)


def is_glyph(px):
    r, g, b, a = px[..., 0], px[..., 1], px[..., 2], px[..., 3]
    return (a > 40) & (r > 170) & (g > 170) & (b > 170)


def bbox(mask):
    ys, xs = np.nonzero(mask)
    return xs.min(), ys.min(), xs.max(), ys.max()


def center(path):
    img = np.asarray(Image.open(path).convert('RGBA')).astype(np.float64)
    h, w, _ = img.shape
    square = is_square(img)
    # on a transparent canvas the glyph is whatever is clearly drawn
    glyph = is_glyph(img) if square.any() else img[..., 3] > 128
    if not glyph.any():
        print(path, 'no glyph found, left as it is')
        return
    gx0, gy0, gx1, gy1 = bbox(glyph)
    if square.any():
        sx0, sy0, sx1, sy1 = bbox(square)
    else:
        # the adaptive-icon foreground: only the glyph, centred on the canvas
        sx0, sy0, sx1, sy1 = 0, 0, w - 1, h - 1
    dx = int(round((sx0 + sx1) / 2 - (gx0 + gx1) / 2))
    if dx == 0:
        print(path, 'already centred')
        return

    pad = 10
    x0, x1 = max(gx0 - pad, 0), min(gx1 + pad, w - 1)
    y0, y1 = max(gy0 - pad, 0), min(gy1 + pad, h - 1)
    region = np.zeros((h, w), bool)
    region[y0:y1 + 1, x0:x1 + 1] = True

    out = img.copy()
    if square.any():
        # the square underneath, re-created as a smooth surface fitted to the
        # square everywhere away from the glyph (off by under 3 of 255 levels)
        from scipy import ndimage as nd
        keep = nd.binary_erosion(square, iterations=4) & ~nd.binary_dilation(glyph, iterations=12)
        ys, xs = np.nonzero(keep)
        deg = 5
        def terms(x, y):
            return np.stack([x ** i * y ** j for i in range(deg + 1) for j in range(deg + 1 - i)], -1)
        A = terms(xs / w, ys / h)
        yy, xx = np.mgrid[0:h, 0:w]
        T = terms(xx / w, yy / h)
        bg = img.copy()
        for c in range(3):
            coef, *_ = np.linalg.lstsq(A, img[ys, xs, c], rcond=None)
            bg[..., c] = T @ coef
        # how much glyph each pixel holds: 0 on the background, 1 on pure glyph
        top = np.percentile(img[glyph][:, :3], 95, axis=0)
        # (least squares over the colour channels: the blue of the square is
        # nearly white already, dividing by it alone would turn noise into streaks)
        diff = top - bg[..., :3]
        alpha = np.clip(((img[..., :3] - bg[..., :3]) * diff).sum(-1) / np.maximum((diff * diff).sum(-1), 1), 0, 1)
        alpha[~region] = 0
        # clear the old glyph, then draw it again dx to the side
        out[region, :3] = bg[region, :3]
        shifted = np.zeros_like(alpha)
        if dx < 0:
            shifted[:, :dx] = alpha[:, -dx:]
        else:
            shifted[:, dx:] = alpha[:, :-dx]
        a = shifted[..., None]
        out[..., :3] = out[..., :3] * (1 - a) + top * a
    else:
        # transparent canvas: move the glyph pixels themselves
        moved = np.zeros_like(img)
        if dx < 0:
            moved[:, :dx] = img[:, -dx:]
        else:
            moved[:, dx:] = img[:, :-dx]
        out = moved

    Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), 'RGBA').save(path)
    print(path, f'glyph moved {dx:+d} px')


if __name__ == '__main__':
    for f in sys.argv[1:] or FILES:
        center(f)
