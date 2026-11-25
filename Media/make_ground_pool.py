# Generates GroundPool.tga: the circle of light drawn under each marker in
# QuickRaidMark's ground-marker menu. A 128x128 32-bit TGA, white with the
# shape in the alpha channel, so the game can tint it to each marker's colour.
# It is drawn squashed into a flat ellipse, so it reads as lying on the ground.
#
# Layers, from the centre out:
#   - soft glow filling the circle, brightest in the middle
#   - thin inner ring
#   - eight small rune dots between the rings
#   - bright outer ring with a soft halo around it
#
# Usage: python make_ground_pool.py <output folder>
import math, os, struct, sys

SIZE = 128
C = SIZE / 2
SS = 4  # supersampling per axis

# radii as fractions of the half-size
OUTER_RING, OUTER_WIDTH = 0.80, 0.055
INNER_RING, INNER_WIDTH = 0.50, 0.03
DOT_RADIUS, DOT_SIZE, DOTS = 0.655, 0.045, 8
HALO = 0.14  # how far the outer ring's glow spreads


def ring(r, centre, width):
    """1 on the ring, fading smoothly to 0 just outside its width."""
    d = abs(r - centre)
    if d <= width / 2:
        return 1.0
    return max(0.0, 1.0 - (d - width / 2) / (width * 0.6))


def alpha_at(x, y):
    r = math.hypot(x, y)
    if r > 1.0:
        return 0.0
    a = 0.0
    # soft fill, strongest in the middle, fading to nothing at the outer ring
    if r < OUTER_RING:
        a = max(a, 0.30 * (1 - r / OUTER_RING) ** 1.2 + 0.12)
    # halo around the outer ring
    a = max(a, 0.45 * max(0.0, 1 - abs(r - OUTER_RING) / HALO) ** 2)
    # rings
    a = max(a, 1.00 * ring(r, OUTER_RING, OUTER_WIDTH))
    a = max(a, 0.65 * ring(r, INNER_RING, INNER_WIDTH))
    # rune dots, offset half a step so they sit between the marker's corners
    ang = math.atan2(y, x)
    step = 2 * math.pi / DOTS
    nearest = round((ang - step / 2) / step) * step + step / 2
    dx = x - math.cos(nearest) * DOT_RADIUS
    dy = y - math.sin(nearest) * DOT_RADIUS
    dd = math.hypot(dx, dy)
    if dd < DOT_SIZE * 1.6:
        a = max(a, 0.85 * max(0.0, min(1.0, (DOT_SIZE * 1.6 - dd) / (DOT_SIZE * 0.6))))
    return min(1.0, a)


def main(out_dir):
    pixels = bytearray()
    # TGA rows go bottom to top; the image is symmetric, so order doesn't matter
    for py in range(SIZE):
        for px in range(SIZE):
            total = 0.0
            for sy in range(SS):
                for sx in range(SS):
                    x = (px + (sx + 0.5) / SS - C) / C
                    y = (py + (sy + 0.5) / SS - C) / C
                    total += alpha_at(x, y)
            a = int(round(255 * total / (SS * SS)))
            pixels += bytes((255, 255, 255, a))  # BGRA
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 8)
    path = os.path.join(out_dir, "GroundPool.tga")
    with open(path, "wb") as f:
        f.write(header + bytes(pixels))
    print("wrote", path)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__)))
