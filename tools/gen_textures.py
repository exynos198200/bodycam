#!/usr/bin/env python3
"""Generate the low-poly surface textures used by the map and props.

No external 3D or image editor is required: everything is procedural and is
written as small 128x128 PNG files under textures/. They are tiny in memory
(a few hundred KB total after ETC2 compression) so they are safe on low-end
Android devices.
"""
import math
import os
import random

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "textures")
SIZE = 128


def clamp(v):
    return max(0, min(255, int(v)))


def new_img():
    return Image.new("RGB", (SIZE, SIZE))


def value_noise(seed, freq):
    """Tileable value noise as a 2D list of floats in [0, 1]."""
    rnd = random.Random(seed)
    grid = [[rnd.random() for _ in range(freq)] for _ in range(freq)]
    out = []
    for y in range(SIZE):
        row = []
        fy = y / SIZE * freq
        y0 = int(fy) % freq
        y1 = (y0 + 1) % freq
        ty = fy - int(fy)
        ty = ty * ty * (3 - 2 * ty)
        for x in range(SIZE):
            fx = x / SIZE * freq
            x0 = int(fx) % freq
            x1 = (x0 + 1) % freq
            tx = fx - int(fx)
            tx = tx * tx * (3 - 2 * tx)
            a = grid[y0][x0] * (1 - tx) + grid[y0][x1] * tx
            b = grid[y1][x0] * (1 - tx) + grid[y1][x1] * tx
            row.append(a * (1 - ty) + b * ty)
        out.append(row)
    return out


def fbm(seed, freqs, weights):
    layers = [value_noise(seed + i, f) for i, f in enumerate(freqs)]
    total = sum(weights)
    out = []
    for y in range(SIZE):
        row = []
        for x in range(SIZE):
            v = sum(layers[i][y][x] * weights[i] for i in range(len(freqs))) / total
            row.append(v)
        out.append(row)
    return out


def save(img, name):
    path = os.path.join(OUT, name)
    img.save(path, "PNG", optimize=True)
    print("wrote %-18s %5d bytes" % (name, os.path.getsize(path)))


def concrete():
    n = fbm(11, [4, 8, 32], [0.5, 0.3, 0.2])
    rnd = random.Random(3)
    img = new_img()
    px = img.load()
    for y in range(SIZE):
        for x in range(SIZE):
            v = 132 + (n[y][x] - 0.5) * 70 + rnd.uniform(-7, 7)
            px[x, y] = (clamp(v), clamp(v * 1.005), clamp(v * 1.02))
    # a few darker stains
    for _ in range(9):
        cx, cy, r = rnd.randrange(SIZE), rnd.randrange(SIZE), rnd.uniform(8, 22)
        for y in range(SIZE):
            for x in range(SIZE):
                dx = min(abs(x - cx), SIZE - abs(x - cx))
                dy = min(abs(y - cy), SIZE - abs(y - cy))
                d = math.hypot(dx, dy)
                if d < r:
                    f = 1.0 - d / r
                    r0, g0, b0 = px[x, y]
                    px[x, y] = (clamp(r0 - 26 * f), clamp(g0 - 26 * f), clamp(b0 - 24 * f))
    save(img, "concrete.png")


def tile():
    n = fbm(23, [8, 32], [0.6, 0.4])
    img = new_img()
    px = img.load()
    cell = 32
    grout = 3
    rnd = random.Random(5)
    shade = {}
    for y in range(SIZE):
        for x in range(SIZE):
            gx, gy = x % cell, y % cell
            key = (x // cell, y // cell)
            if key not in shade:
                shade[key] = rnd.uniform(-12, 12)
            if gx < grout or gy < grout:
                v = 74 + (n[y][x] - 0.5) * 16
                px[x, y] = (clamp(v), clamp(v), clamp(v * 1.05))
            else:
                v = 150 + (n[y][x] - 0.5) * 26 + shade[key]
                edge = min(gx - grout, gy - grout, cell - 1 - gx, cell - 1 - gy)
                if edge < 2:
                    v -= 18
                px[x, y] = (clamp(v), clamp(v * 1.01), clamp(v * 1.03))
    save(img, "tile.png")


def plaster():
    n = fbm(37, [3, 12, 48], [0.55, 0.3, 0.15])
    rnd = random.Random(7)
    img = new_img()
    px = img.load()
    for y in range(SIZE):
        for x in range(SIZE):
            v = 168 + (n[y][x] - 0.5) * 46 + rnd.uniform(-5, 5)
            px[x, y] = (clamp(v * 1.02), clamp(v), clamp(v * 0.96))
    # scuff lines near the bottom of the tile
    for _ in range(22):
        x0 = rnd.randrange(SIZE)
        y0 = rnd.randrange(SIZE)
        length = rnd.randrange(6, 26)
        for i in range(length):
            x = (x0 + i) % SIZE
            y = (y0 + int(math.sin(i * 0.4) * 2)) % SIZE
            r0, g0, b0 = px[x, y]
            px[x, y] = (clamp(r0 - 22), clamp(g0 - 22), clamp(b0 - 20))
    save(img, "plaster.png")


def metal():
    n = fbm(51, [6, 24], [0.6, 0.4])
    rnd = random.Random(11)
    img = new_img()
    px = img.load()
    for y in range(SIZE):
        streak = rnd.uniform(-9, 9)
        for x in range(SIZE):
            v = 118 + (n[y][x] - 0.5) * 30 + streak + math.sin(x * 0.7) * 3
            px[x, y] = (clamp(v * 0.98), clamp(v), clamp(v * 1.06))
    # rivet rows
    for cy in range(16, SIZE, 48):
        for cx in range(16, SIZE, 48):
            for y in range(cy - 3, cy + 4):
                for x in range(cx - 3, cx + 4):
                    d = math.hypot(x - cx, y - cy)
                    if d <= 3:
                        f = 1.0 - d / 3.0
                        r0, g0, b0 = px[x % SIZE, y % SIZE]
                        px[x % SIZE, y % SIZE] = (clamp(r0 + 34 * f), clamp(g0 + 34 * f), clamp(b0 + 34 * f))
    save(img, "metal.png")


def wood():
    n = fbm(67, [4, 16], [0.65, 0.35])
    rnd = random.Random(13)
    img = new_img()
    px = img.load()
    plank = 32
    for y in range(SIZE):
        for x in range(SIZE):
            grain = math.sin((x * 0.35) + n[y][x] * 7.0) * 0.5 + 0.5
            v = 96 + grain * 40 + (n[y][x] - 0.5) * 26
            r0 = v * 1.28
            g0 = v * 0.92
            b0 = v * 0.6
            if y % plank < 2:
                r0, g0, b0 = r0 * 0.6, g0 * 0.6, b0 * 0.6
            px[x, y] = (clamp(r0), clamp(g0), clamp(b0))
    for _ in range(5):
        cx, cy, r = rnd.randrange(SIZE), rnd.randrange(SIZE), rnd.uniform(3, 6)
        for y in range(SIZE):
            for x in range(SIZE):
                d = math.hypot(min(abs(x - cx), SIZE - abs(x - cx)), min(abs(y - cy), SIZE - abs(y - cy)))
                if d < r:
                    f = 1.0 - d / r
                    r0, g0, b0 = px[x, y]
                    px[x, y] = (clamp(r0 - 45 * f), clamp(g0 - 38 * f), clamp(b0 - 28 * f))
    save(img, "wood.png")


def sensor_noise():
    """Static grain tile sampled by the bodycam shader."""
    rnd = random.Random(29)
    img = new_img()
    px = img.load()
    for y in range(SIZE):
        for x in range(SIZE):
            v = rnd.gauss(128, 46)
            px[x, y] = (clamp(v), clamp(v + rnd.uniform(-10, 10)), clamp(v + rnd.uniform(-10, 10)))
    save(img, "sensor_noise.png")


def main():
    os.makedirs(OUT, exist_ok=True)
    concrete()
    tile()
    plaster()
    metal()
    wood()
    sensor_noise()


if __name__ == "__main__":
    main()
