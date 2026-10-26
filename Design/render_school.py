from render_icons import *
from PIL import Image, ImageDraw

NAVY = (12, 27, 56)

def stamp_edges(d, pts, r, fill, step=1.5):
    closed = pts + [pts[0]]
    for (x0, y0), (x1, y1) in zip(closed, closed[1:]):
        dist = math.hypot(x1 - x0, y1 - y0); n = max(1, int(dist / step))
        for i in range(n + 1):
            t = i / n; x = x0 + (x1 - x0) * t; y = y0 + (y1 - y0) * t
            d.ellipse((x - r, y - r, x + r, y + r), fill=fill)

def shrink(pts, k):
    cx = sum(p[0] for p in pts) / len(pts); cy = sum(p[1] for p in pts) / len(pts)
    return [(cx + (x - cx) * k, cy + (y - cy) * k) for x, y in pts]

def rounded_polygon(d, pts, radius, fill, k=0.9):
    inner = shrink(pts, k); d.polygon(inner, fill=fill); stamp_edges(d, inner, radius, fill)

def graduation_cap(size, color, cx, cy, w=340, h=136):
    """A mortarboard in the proportions of SF Symbols' graduationcap.fill."""
    layer = Image.new("RGBA", size, (0, 0, 0, 0)); d = ImageDraw.Draw(layer); fill = color + (255,)
    # shallow crown band tucked under the board
    d.ellipse((cx - w * 0.56, cy + 70 - 150, cx + w * 0.56, cy + 70 + 150), fill=fill)
    d.rectangle((cx - w, cy - 400, cx + w, cy + 14), fill=(0, 0, 0, 0))
    board = [(cx, cy - h), (cx + w, cy), (cx, cy + h), (cx - w, cy)]
    rounded_polygon(d, board, 34, fill, k=0.9)
    tx, ty = cx + w * 0.86, cy + 4
    for i in range(0, 221, 2):
        t = i / 220; x = tx + 12 * t; y = ty + 206 * t
        d.ellipse((x - 13, y - 13, x + 13, y + 13), fill=fill)
    d.ellipse((tx + 12 - 38, ty + 206 - 38 + 20, tx + 12 + 38, ty + 206 + 38 + 20), fill=fill)
    return layer

def schoolhouse(size, color, bg, cx, cy):
    layer = Image.new("RGBA", size, (0, 0, 0, 0)); d = ImageDraw.Draw(layer); fill = color + (255,)
    house = [(cx - 300, cy + 190), (cx - 300, cy - 90), (cx, cy - 330), (cx + 300, cy - 90), (cx + 300, cy + 190)]
    rounded_polygon(d, house, 34, fill, k=0.9)
    d.rounded_rectangle((cx - 64, cy - 10, cx + 64, cy + 172), radius=64, fill=bg + (255,))
    d.rectangle((cx - 64, cy + 100, cx + 64, cy + 172), fill=bg + (255,))
    d.rounded_rectangle((cx - 12, cy - 470, cx + 12, cy - 300), radius=12, fill=fill)
    d.polygon([(cx + 12, cy - 466), (cx + 132, cy - 420), (cx + 12, cy - 374)], fill=fill)
    return layer

def gradient_fill(layer, top, bottom):
    bbox = layer.getbbox(); grad = Image.new("RGBA", layer.size, (0, 0, 0, 0)); px = grad.load()
    y0, y1 = bbox[1], bbox[3]
    for y in range(y0, y1 + 1):
        c = lerp(top, bottom, (y - y0) / max(1, y1 - y0)) + (255,)
        for x in range(bbox[0], bbox[2] + 1): px[x, y] = c
    grad.putalpha(layer.getchannel("A")); return grad

def ring(img, marker_at=0.33, marker_fill=NAVY, width=150, marker=True):
    img, (cx, cy, r) = gradient_arc(img, (300, 300, 1748, 1748), 135, 405, width, RAINBOW)
    if marker:
        ang = math.radians(135 + 270 * marker_at); p = (cx + r * math.cos(ang), cy + r * math.sin(ang))
        img = dot(img, p, 90, WHITE); img = dot(img, p, 56, marker_fill)
    return img

def render(which=None):
    icons = {}; size = (S, S)
    def white(): return vgradient((255, 255, 255), (240, 241, 247))
    if which in (None, "G1"):
        img = ring(white()); icons["G1"] = finish(Image.alpha_composite(img, graduation_cap(size, NAVY, 1024, 990)), "G1_cap_navy")
    if which in (None, "G2"):
        img = ring(white(), marker=False)
        cap = gradient_fill(graduation_cap(size, NAVY, 1024, 990), (64, 156, 255), (0, 88, 220))
        icons["G2"] = finish(Image.alpha_composite(img, cap), "G2_cap_blue")
    if which in (None, "G3"):
        img = ring(vgradient((12, 27, 56), (22, 50, 96)))
        icons["G3"] = finish(Image.alpha_composite(img, graduation_cap(size, WHITE, 1024, 990)), "G3_cap_dark")
    if which in (None, "G4"):
        img = ring(white()); icons["G4"] = finish(Image.alpha_composite(img, schoolhouse(size, NAVY, (252, 252, 254), 1024, 1060)), "G4_schoolhouse")
    return icons

if __name__ == "__main__":
    icons = render()
    contact_sheet(icons, {"G1": "G1 · Cap, navy", "G2": "G2 · Cap, blue gradient", "G3": "G3 · Cap, dark", "G4": "G4 · Schoolhouse"}, "icon_options_school.png")
    print("ok")
