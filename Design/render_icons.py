from PIL import Image, ImageDraw, ImageFilter, ImageFont
import math, sys

S = 2048; OUT = 1024
GREEN = (52, 199, 89); YELLOW = (255, 204, 0); ORANGE = (255, 149, 0); RED = (255, 59, 48); PURPLE = (175, 82, 222)
RAINBOW = [GREEN, YELLOW, ORANGE, RED, PURPLE]
WHITE = (255, 255, 255); NAVY = (12, 27, 56)

def lerp(a, b, t): return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))
def multi(colors, t):
    t = max(0.0, min(1.0, t)); n = len(colors) - 1
    i = min(int(t * n), n - 1); return lerp(colors[i], colors[i + 1], t * n - i)

def vgradient(top, bottom):
    img = Image.new("RGB", (S, S)); px = img.load()
    for y in range(S):
        c = lerp(top, bottom, y / (S - 1))
        for x in range(S): px[x, y] = c
    return img.convert("RGBA")

def dgradient(colors):
    img = Image.new("RGB", (S, S)); px = img.load()
    for y in range(S):
        for x in range(S): px[x, y] = multi(colors, (x + y) / (2 * S - 2))
    return img.convert("RGBA")

def glow(img, center, radius, color, alpha=120, blur=200):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0)); d = ImageDraw.Draw(layer)
    cx, cy = center; d.ellipse((cx - radius, cy - radius, cx + radius, cy + radius), fill=color + (alpha,))
    return Image.alpha_composite(img, layer.filter(ImageFilter.GaussianBlur(blur)))

def composite(img, layer, alpha=255):
    if alpha < 255:
        layer.putalpha(layer.getchannel("A").point(lambda v: v * alpha // 255))
    return Image.alpha_composite(img, layer)

def stroke(img, pts, width, color=WHITE, alpha=255):
    """A solid stroke built from dense stamped circles: no seams, round caps for free."""
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0)); d = ImageDraw.Draw(layer)
    r = width / 2; step = 1.5
    fill = color + (255,)
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        dist = math.hypot(x1 - x0, y1 - y0); n = max(1, int(dist / step))
        for i in range(n + 1):
            t = i / n; x = x0 + (x1 - x0) * t; y = y0 + (y1 - y0) * t
            d.ellipse((x - r, y - r, x + r, y + r), fill=fill)
    return composite(img, layer, alpha)

def wave_points(x0, y0, x1, amp, phase=0.0, n=60):
    return [(x0 + (x1 - x0) * i / n, y0 + amp * math.sin(i / n * math.pi * 1.2 + phase)) for i in range(n + 1)]

def curl_points(xe, ye, r, up=True, sweep=250, n=40):
    pts = []
    for i in range(1, n + 1):
        a = i / n * math.radians(sweep)
        if up: cx, cy = xe, ye - r; th = math.pi / 2 - a
        else:  cx, cy = xe, ye + r; th = -math.pi / 2 + a
        pts.append((cx + r * math.cos(th), cy + r * math.sin(th)))
    return pts

def wind_glyph(img, x, y, w, width, color=WHITE, alpha=255):
    """Three breezes like the SF Symbol: top curls up, middle curls down, bottom is short."""
    amp = w * 0.02; r = width * 1.35
    top = wave_points(x, y, x + w * 0.62, amp, 0.3) + curl_points(x + w * 0.62, y, r, up=True)
    mid = wave_points(x, y + w * 0.27, x + w * 0.86, amp, 1.1) + curl_points(x + w * 0.86, y + w * 0.27, r, up=False)
    low = wave_points(x, y + w * 0.54, x + w * 0.46, amp, 2.0)
    for pts in (top, mid, low):
        img = stroke(img, pts, width, color, alpha)
    return img

def gradient_arc(img, bbox, start_deg, end_deg, width, colors, segments=300):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0)); d = ImageDraw.Draw(layer)
    span = end_deg - start_deg
    for i in range(segments):
        t0 = i / segments; a0 = start_deg + span * t0; a1 = start_deg + span * (i + 1) / segments + 0.7
        d.arc(bbox, a0, a1, fill=multi(colors, t0) + (255,), width=width)
    x0, y0, x1, y1 = bbox; cx, cy = (x0 + x1) / 2, (y0 + y1) / 2; r = (x1 - x0) / 2 - width / 2
    for ang, col in ((start_deg, colors[0]), (end_deg, colors[-1])):
        px = cx + r * math.cos(math.radians(ang)); py = cy + r * math.sin(math.radians(ang))
        d.ellipse((px - width / 2, py - width / 2, px + width / 2, py + width / 2), fill=col + (255,))
    return Image.alpha_composite(img, layer), (cx, cy, r)

def gradient_bar(img, box, colors):
    x0, y0, x1, y1 = box; w, h = x1 - x0, y1 - y0
    strip = Image.new("RGBA", (w, h)); sp = strip.load()
    for x in range(w):
        c = multi(colors, x / (w - 1)) + (255,)
        for y in range(h): sp[x, y] = c
    mask = Image.new("L", (w, h), 0); ImageDraw.Draw(mask).rounded_rectangle((0, 0, w - 1, h - 1), radius=h // 2, fill=255)
    img = img.copy(); img.paste(strip, (x0, y0), mask); return img

def dot(img, center, r, color=WHITE, alpha=255, halo=0, halo_alpha=70):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0)); d = ImageDraw.Draw(layer); cx, cy = center
    if halo: d.ellipse((cx - r - halo, cy - r - halo, cx + r + halo, cy + r + halo), fill=color + (halo_alpha,))
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=color + (alpha,))
    return Image.alpha_composite(img, layer)

def finish(img, name):
    out = img.convert("RGB").resize((OUT, OUT), Image.LANCZOS); out.save(f"{name}.png"); return out

def render_all():
    icons = {}
    # A. Gauge arc on midnight navy.
    img = vgradient((12, 27, 56), (26, 62, 110))
    img = glow(img, (1550, 350), 700, (70, 150, 210), alpha=110, blur=260)
    img, (cx, cy, r) = gradient_arc(img, (330, 470, 1718, 1858), 180, 360, 176, RAINBOW)
    ang = math.radians(180 + 180 * 0.3)
    img = dot(img, (cx + r * math.cos(ang), cy + r * math.sin(ang)), 84, WHITE, halo=36)
    img = wind_glyph(img, 700, 1330, 650, 72)
    icons["A"] = finish(img, "A_gauge_arc")

    # B. Gauge bar on deep teal.
    img = vgradient((8, 62, 84), (28, 132, 158))
    img = glow(img, (1650, 250), 650, (120, 220, 235), alpha=100, blur=240)
    img = wind_glyph(img, 380, 520, 1240, 112)
    img = gradient_bar(img, (330, 1330, 1718, 1478), RAINBOW)
    img = dot(img, (330 + 1388 * 0.3, 1404), 104, WHITE, halo=40)
    icons["B"] = finish(img, "B_gauge_bar")

    # C. Wind and particles on sky teal.
    img = dgradient([(18, 96, 130), (72, 190, 210)])
    img = glow(img, (1550, 350), 700, (170, 235, 245), alpha=110, blur=260)
    img = wind_glyph(img, 300, 640, 1350, 150)
    for (x, y, rr, a) in [(1500, 1560, 90, 235), (1690, 1430, 56, 205), (1690, 1690, 42, 175), (1840, 1560, 30, 150)]:
        img = dot(img, (x, y), rr, WHITE, alpha=a)
    icons["C"] = finish(img, "C_wind_particles")

    # D. Glass tile over the rainbow.
    bg = dgradient([GREEN, YELLOW, ORANGE, RED, PURPLE])
    bg = glow(bg, (500, 500), 600, WHITE, alpha=70, blur=260)
    tile = (360, 360, 1688, 1688); tw = tile[2] - tile[0]
    frosted = bg.crop(tile).filter(ImageFilter.GaussianBlur(60))
    frosted = Image.alpha_composite(frosted, Image.new("RGBA", frosted.size, (255, 255, 255, 110)))
    mask = Image.new("L", frosted.size, 0); ImageDraw.Draw(mask).rounded_rectangle((0, 0, tw - 1, tw - 1), radius=300, fill=255)
    img = bg.copy(); img.paste(frosted, tile[:2], mask)
    edge = Image.new("RGBA", img.size, (0, 0, 0, 0)); ImageDraw.Draw(edge).rounded_rectangle(tile, radius=300, outline=(255, 255, 255, 150), width=8)
    img = Image.alpha_composite(img, edge)
    img = wind_glyph(img, 560, 780, 930, 110)
    icons["D"] = finish(img, "D_glass_tile")

    # E. Inside and outside.
    img = Image.new("RGB", (S, S)); px = img.load()
    for y in range(S):
        warm = lerp((255, 149, 0), (255, 94, 58), y / (S - 1)); cool = lerp((80, 170, 230), (20, 90, 170), y / (S - 1))
        for x in range(S):
            k = 1 / (1 + math.exp(-((x / (S - 1)) - 0.5) * 18)); px[x, y] = lerp(warm, cool, k)
    img = img.convert("RGBA")
    img = glow(img, (1500, 480), 500, WHITE, alpha=60, blur=220)
    img = wind_glyph(img, 330, 640, 1350, 150)
    icons["E"] = finish(img, "E_inside_outside")

    # F. Ring gauge on white.
    img = vgradient((252, 252, 254), (236, 238, 246))
    img, (cx, cy, r) = gradient_arc(img, (300, 300, 1748, 1748), 135, 405, 150, RAINBOW)
    ang = math.radians(135 + 270 * 0.33)
    img = dot(img, (cx + r * math.cos(ang), cy + r * math.sin(ang)), 88, WHITE)
    img = dot(img, (cx + r * math.cos(ang), cy + r * math.sin(ang)), 56, NAVY)
    img = wind_glyph(img, 690, 820, 660, 76, color=NAVY)
    icons["F"] = finish(img, "F_ring_gauge")
    return icons

def contact_sheet(icons, names, path):
    tile = 420; pad = 60; cols = 3; rows = (len(icons) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * tile + (cols + 1) * pad, rows * (tile + 90) + (rows + 1) * pad), (242, 242, 247))
    sd = ImageDraw.Draw(sheet)
    try: font = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", 34)
    except Exception: font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 34)
    for i, key in enumerate(sorted(icons)):
        rr, c = divmod(i, cols); x = pad + c * (tile + pad); y = pad + rr * (tile + 90 + pad)
        icon = icons[key].resize((tile, tile), Image.LANCZOS)
        m = Image.new("L", (tile, tile), 0); ImageDraw.Draw(m).rounded_rectangle((0, 0, tile - 1, tile - 1), radius=int(tile * 0.2237), fill=255)
        sh = Image.new("RGBA", (tile + 80, tile + 80), (0, 0, 0, 0)); ImageDraw.Draw(sh).rounded_rectangle((40, 52, tile + 40, tile + 52), radius=int(tile * 0.2237), fill=(0, 0, 0, 60))
        sh = sh.filter(ImageFilter.GaussianBlur(22)); sheet.paste(sh, (x - 40, y - 40), sh)
        sheet.paste(icon, (x, y), m); sd.text((x + tile / 2, y + tile + 44), names[key], fill=(60, 60, 67), font=font, anchor="mm")
    sheet.save(path)

if __name__ == "__main__":
    icons = render_all()
    contact_sheet(icons, {"A": "A · Gauge arc", "B": "B · Gauge bar", "C": "C · Wind and particles", "D": "D · Glass tile", "E": "E · Inside and outside", "F": "F · Ring gauge"}, "icon_options.png")
    print("ok")
