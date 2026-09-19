#!/usr/bin/env python3
"""Generate the main-menu background image procedurally (no art tools).

Draws a dark low-poly corridor in perspective with a bodycam look: red REC
glow, sensor grain, scanlines, chromatic fringe and a heavy vignette.
Output: textures/menu_bg.png (1280x720)
"""
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter

W, H = 1280, 720
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "textures", "menu_bg.png")

random.seed(20260916)


def lerp(a, b, t):
    return a + (b - a) * t


def col(c, f):
    return tuple(max(0, min(255, int(v * f))) for v in c)


def build_corridor():
    img = Image.new("RGB", (W, H), (7, 8, 10))
    d = ImageDraw.Draw(img)

    vx, vy = W * 0.52, H * 0.54           # vanishing point
    far_w, far_h = W * 0.10, H * 0.14      # far doorway opening

    fl, fr = vx - far_w, vx + far_w
    ft, fb = vy - far_h, vy + far_h

    # floor
    d.polygon([(0, H), (W, H), (fr, fb), (fl, fb)], fill=(26, 25, 24))
    # ceiling
    d.polygon([(0, 0), (W, 0), (fr, ft), (fl, ft)], fill=(15, 16, 18))
    # left / right walls
    d.polygon([(0, 0), (fl, ft), (fl, fb), (0, H)], fill=(38, 39, 42))
    d.polygon([(W, 0), (fr, ft), (fr, fb), (W, H)], fill=(31, 32, 35))
    # far door opening
    d.rectangle([fl, ft, fr, fb], fill=(9, 10, 12))
    d.rectangle([fl, ft, fr, fb], outline=(64, 66, 70), width=3)

    # floor tile lines receding to the vanishing point
    for i in range(1, 16):
        t = (i / 16.0) ** 2.1
        y = lerp(H, fb, 1.0 - (1.0 - t))
        y = lerp(fb, H, (1.0 - t))
        xl = lerp(fl, 0, (1.0 - t))
        xr = lerp(fr, W, (1.0 - t))
        shade = int(lerp(60, 26, t))
        d.line([(xl, y), (xr, y)], fill=(shade, shade - 1, shade - 2), width=2)
    for i in range(-6, 7):
        x_near = vx + i * W * 0.16
        x_far = lerp(vx, x_near, 0.12)
        d.line([(x_near, H), (x_far, fb)], fill=(46, 45, 44), width=2)

    # wall panel seams + ceiling lamps
    for i in range(1, 9):
        t = (i / 9.0) ** 1.6
        xl = lerp(0, fl, t)
        xr = lerp(W, fr, t)
        yt = lerp(0, ft, t)
        yb = lerp(H, fb, t)
        d.line([(xl, yt), (xl, yb)], fill=(54, 55, 58), width=2)
        d.line([(xr, yt), (xr, yb)], fill=(48, 49, 52), width=2)
        # lamp panel in the ceiling
        lw = lerp(W * 0.10, far_w * 0.5, t)
        ly = lerp(H * 0.10, ft + 4, t)
        glow = int(lerp(230, 120, t))
        d.rectangle([vx - lw, ly - 6 * (1 - t) - 3, vx + lw, ly + 6 * (1 - t) + 3],
                    fill=(glow, glow - 6, glow - 22))

    # crates / cover boxes on the floor
    boxes = [(0.16, 0.80, 0.20), (0.74, 0.86, 0.24), (0.33, 0.68, 0.12), (0.63, 0.71, 0.13)]
    for cx, cy, s in boxes:
        x, y = W * cx, H * cy
        w, h = W * s, W * s * 0.72
        top = (int(lerp(92, 60, cy)),) * 1
        base = (74, 58, 40)
        d.polygon([(x, y), (x + w, y - h * 0.18), (x + w, y - h * 0.9),
                   (x, y - h * 0.72)], fill=col(base, 1.0))
        d.polygon([(x, y - h * 0.72), (x + w, y - h * 0.9),
                   (x + w * 0.62, y - h * 1.12), (x - w * 0.35, y - h * 0.92)],
                  fill=col(base, 1.35))
        d.polygon([(x, y), (x, y - h * 0.72), (x - w * 0.35, y - h * 0.92),
                   (x - w * 0.35, y - h * 0.2)], fill=col(base, 0.7))
        del top

    return img


def add_light(img):
    """Warm pool of light from the corridor lamps, cool bounce from the door."""
    glow = Image.new("RGB", (W, H), (0, 0, 0))
    g = ImageDraw.Draw(glow)
    for i, (gx, gy, r, c) in enumerate([
        (W * 0.52, H * 0.16, 260, (255, 226, 176)),
        (W * 0.52, H * 0.54, 200, (150, 180, 220)),
        (W * 0.14, H * 0.30, 190, (255, 210, 150)),
        (W * 0.88, H * 0.34, 170, (210, 180, 255)),
    ]):
        steps = 26
        for s in range(steps, 0, -1):
            t = s / float(steps)
            rr = r * t
            f = (1.0 - t) ** 2 * 0.55
            g.ellipse([gx - rr, gy - rr * 0.8, gx + rr, gy + rr * 0.8], fill=col(c, f))
        del i
    glow = glow.filter(ImageFilter.GaussianBlur(28))
    return Image.blend(img, Image.new("RGB", (W, H), (0, 0, 0)), 0.0).point(lambda v: v), glow


def main():
    img = build_corridor()
    img = img.filter(ImageFilter.GaussianBlur(0.6))
    _, glow = add_light(img)

    px = img.load()
    gx = glow.load()
    cx, cy = W * 0.5, H * 0.5
    maxd = math.hypot(cx, cy)

    for y in range(H):
        for x in range(W):
            r, g, b = px[x, y]
            lr, lg, lb = gx[x, y]
            # additive lighting
            r += lr
            g += lg
            b += lb
            # radial vignette (bodycam lens)
            d = math.hypot(x - cx, y - cy) / maxd
            v = 1.0 - 0.95 * d * d
            r *= v
            g *= v
            b *= v
            # scanlines + rolling sensor bar
            if y % 3 == 0:
                r *= 0.9
                g *= 0.9
                b *= 0.9
            bar = math.exp(-((y - H * 0.72) ** 2) / (2 * 40.0 ** 2))
            r += 16 * bar
            g += 16 * bar
            b += 18 * bar
            # sensor grain
            n = random.gauss(0.0, 7.0)
            r += n
            g += n
            b += n * 1.15
            # warm bodycam grade + slight red REC tint in the corners
            r *= 1.06
            b *= 0.96
            px[x, y] = (
                max(0, min(255, int(r))),
                max(0, min(255, int(g))),
                max(0, min(255, int(b))),
            )

    # chromatic aberration: shift the red and blue channels outward
    r, g, b = img.split()
    r = r.transform(r.size, Image.AFFINE, (1.004, 0, -2.4, 0, 1.004, -1.2),
                    resample=Image.BILINEAR)
    b = b.transform(b.size, Image.AFFINE, (0.996, 0, 2.4, 0, 0.996, 1.2),
                    resample=Image.BILINEAR)
    img = Image.merge("RGB", (r, g, b))

    d = ImageDraw.Draw(img, "RGBA")
    # horizontal tear glitches
    for _ in range(7):
        y = random.randint(0, H - 1)
        h = random.randint(2, 7)
        box = img.crop((0, y, W, min(H, y + h)))
        img.paste(box, (random.randint(-16, 16), y))
    # REC dot + labels drawn as simple shapes (the engine draws real text)
    d.ellipse([46, 44, 70, 68], fill=(238, 42, 36, 235))
    d.rectangle([0, 0, W - 1, H - 1], outline=(0, 0, 0, 140), width=6)

    img.save(OUT, optimize=True)
    print("wrote %s  %d bytes" % (OUT, os.path.getsize(OUT)))


if __name__ == "__main__":
    main()
