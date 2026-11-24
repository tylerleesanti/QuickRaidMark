# Generates the two layers of QuickRaidMark's hovered-slice highlight, each a
# 256x256 32-bit TGA of a 45-degree slice pointing up from the texture centre
# (drawn at 250 UI px in game, so 1 texture px is about 1 UI px):
#   WedgeFill.tga    - plain white slice; tinted black in game to darken it
#   WedgeOutline.tga - gold outline of the slice with a soft glow
# Usage: python make_wedge_layers.py <output folder>
import math, os, struct, sys

SIZE = 256
C = SIZE / 2
HALF = 22.5                      # half the slice angle, degrees
R_IN, R_OUT = 27.0, 110.0        # inner edge hugs the centre circle; outer edge
                                 # just inside the 223 px menu background
SS = 4                           # supersampling per axis
GOLD = (255, 200, 50)
WHITE = (255, 255, 255)


def polar(px, py):
    dx, dy = px - C, C - py
    return math.hypot(dx, dy), math.degrees(math.atan2(dx, dy))  # 0 = up


def inside(r, ang):
    return R_IN <= r <= R_OUT and abs(ang) <= HALF


def dist_to_outline(px, py):
    """Distance from the point to the slice's outline (two sides, two arcs)."""
    r, ang = polar(px, py)
    best = float("inf")
    x, y = px - C, C - py
    # straight sides
    for side in (-HALF, HALF):
        ux, uy = math.sin(math.radians(side)), math.cos(math.radians(side))
        t = max(R_IN, min(R_OUT, x * ux + y * uy))
        best = min(best, math.hypot(x - ux * t, y - uy * t))
    # arcs
    for radius in (R_IN, R_OUT):
        if abs(ang) <= HALF:
            best = min(best, abs(r - radius))
        else:
            a = math.radians(HALF if ang > 0 else -HALF)
            best = min(best, math.hypot(x - radius * math.sin(a), y - radius * math.cos(a)))
    return best


def outline_alpha(px, py):
    d = dist_to_outline(px, py)
    r, ang = polar(px, py)
    core = math.exp(-((d / 1.1) ** 2))          # crisp gold line
    glow = 0.55 * math.exp(-d / 4.0)            # soft glow around it
    if not inside(r, ang):
        glow *= 0.6                             # glow spills out a little less
    return min(1.0, core + glow)


def fill_alpha(px, py):
    r, ang = polar(px, py)
    if not inside(r, ang):
        return 0.0
    d = dist_to_outline(px, py)
    return min(1.0, d / 1.5)                    # soft 1-2 px edge


def write(path, alpha_fn, color):
    out = bytearray(struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 0x28))
    for y in range(SIZE):
        for x in range(SIZE):
            s = 0.0
            for sy in range(SS):
                for sx in range(SS):
                    s += alpha_fn(x + (sx + 0.5) / SS, y + (sy + 0.5) / SS)
            a = int(round(255 * s / (SS * SS)))
            out += bytes((color[2], color[1], color[0], a))  # TGA stores BGRA
    with open(path, "wb") as f:
        f.write(out)


folder = sys.argv[1] if len(sys.argv) > 1 else "."
write(os.path.join(folder, "WedgeFill.tga"), fill_alpha, WHITE)
write(os.path.join(folder, "WedgeOutline.tga"), outline_alpha, GOLD)
