"""Renders the shipping app icon in light, dark and tinted variants, with depth.

Run from this folder: python3 render_final.py
Writes into ../SchoolAir/Assets.xcassets/AppIcon.appiconset/
"""
from render_icons import *
from render_school import graduation_cap, gradient_fill
from PIL import Image, ImageDraw, ImageFilter
import math, pathlib

OUTDIR = pathlib.Path(__file__).resolve().parent.parent / "SchoolAir" / "Assets.xcassets" / "AppIcon.appiconset"
size = (S, S)
MARKER_AT = 0.33

def ring_layer(colors, width=150):
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    layer, geo = gradient_arc(layer, (300, 300, 1748, 1748), 135, 405, width, colors)
    return layer, geo

def marker_layer(geo, outer, inner):
    cx, cy, r = geo; ang = math.radians(135 + 270 * MARKER_AT); p = (cx + r * math.cos(ang), cy + r * math.sin(ang))
    layer = Image.new("RGBA", size, (0, 0, 0, 0)); d = ImageDraw.Draw(layer)
    d.ellipse((p[0] - 90, p[1] - 90, p[0] + 90, p[1] + 90), fill=outer + (255,))
    d.ellipse((p[0] - 56, p[1] - 56, p[0] + 56, p[1] + 56), fill=inner + (255,))
    return layer

def shadow_of(layer, offset=(0, 26), blur=44, alpha=110, color=(20, 30, 60)):
    """A soft shadow shaped like the layer, dropped a little below it."""
    sh = Image.new("RGBA", size, color + (0,))
    sh.putalpha(layer.getchannel("A").point(lambda v: v * alpha // 255))
    sh = sh.filter(ImageFilter.GaussianBlur(blur))
    moved = Image.new("RGBA", size, (0, 0, 0, 0)); moved.paste(sh, offset); return moved

def highlight_of(layer, strength=70):
    """A faint top-down sheen inside the shape, like light catching a glossy surface."""
    bbox = layer.getbbox(); grad = Image.new("RGBA", size, (255, 255, 255, 0)); px = grad.load()
    y0, y1 = bbox[1], bbox[3]
    for y in range(y0, y1 + 1):
        t = (y - y0) / max(1, y1 - y0); a = int(strength * max(0.0, 1 - t * 2.2))
        for x in range(bbox[0], bbox[2] + 1): px[x, y] = (255, 255, 255, a)
    mask = layer.getchannel("A"); out = Image.new("RGBA", size, (0, 0, 0, 0)); out.paste(grad, (0, 0), mask); return out

def build(background, cap_top, cap_bottom, marker_outer, marker_inner, shadow_color, shadow_alpha, ring_colors=RAINBOW):
    img = background
    ring, geo = ring_layer(ring_colors)
    img = Image.alpha_composite(img, shadow_of(ring, offset=(0, 18), blur=36, alpha=shadow_alpha // 2, color=shadow_color))
    img = Image.alpha_composite(img, ring)
    marker = marker_layer(geo, marker_outer, marker_inner)
    img = Image.alpha_composite(img, shadow_of(marker, offset=(0, 12), blur=24, alpha=shadow_alpha // 2, color=shadow_color))
    img = Image.alpha_composite(img, marker)
    cap = gradient_fill(graduation_cap(size, (0, 0, 0), 1024, 990), cap_top, cap_bottom)
    img = Image.alpha_composite(img, shadow_of(cap, offset=(0, 30), blur=48, alpha=shadow_alpha, color=shadow_color))
    img = Image.alpha_composite(img, cap)
    img = Image.alpha_composite(img, highlight_of(cap))
    return img

def save(img, name, keep_alpha=False):
    out = img.resize((OUT, OUT), Image.LANCZOS)
    if not keep_alpha: out = out.convert("RGB")
    out.save(OUTDIR / name); print("wrote", name)

# Light: white tile, Apple-blue cap.
light = build(vgradient((255, 255, 255), (240, 241, 247)), (64, 156, 255), (0, 88, 220), WHITE, (0, 96, 230), (20, 30, 60), 110)
save(light, "AppIcon.png")

# Dark: charcoal tile, a brighter cap so it still pops, deeper shadows.
dark = build(vgradient((52, 52, 58), (22, 22, 28)), (96, 182, 255), (16, 108, 245), (235, 238, 245), (60, 150, 255), (0, 0, 0), 170)
save(dark, "AppIcon-Dark.png")

# Tinted: grayscale on a transparent tile; iOS paints the color the user picked.
tinted = Image.new("RGBA", size, (0, 0, 0, 0))
ring, geo = ring_layer([(150, 150, 150), (200, 200, 200), (255, 255, 255)])
tinted = Image.alpha_composite(tinted, ring)
tinted = Image.alpha_composite(tinted, marker_layer(geo, (255, 255, 255), (110, 110, 110)))
cap = gradient_fill(graduation_cap(size, (0, 0, 0), 1024, 990), (255, 255, 255), (215, 215, 215))
tinted = Image.alpha_composite(tinted, cap)
save(tinted, "AppIcon-Tinted.png", keep_alpha=True)

# Preview sheet: light and dark on their home-screen backgrounds.
sheet = Image.new("RGB", (1000, 560), (242, 242, 247)); d = ImageDraw.Draw(sheet)
d.rectangle((500, 0, 1000, 560), fill=(18, 18, 20))
for i, (icon, bg) in enumerate(((light, None), (dark, None))):
    tile = 360; x = 70 + i * 500; y = 100
    ic = icon.convert("RGB").resize((tile, tile), Image.LANCZOS)
    m = Image.new("L", (tile, tile), 0); ImageDraw.Draw(m).rounded_rectangle((0, 0, tile - 1, tile - 1), radius=int(tile * 0.2237), fill=255)
    sh = Image.new("RGBA", (tile + 80, tile + 80), (0, 0, 0, 0)); ImageDraw.Draw(sh).rounded_rectangle((40, 54, tile + 40, tile + 54), radius=int(tile * 0.2237), fill=(0, 0, 0, 90))
    sh = sh.filter(ImageFilter.GaussianBlur(24)); sheet.paste(sh, (x - 40, y - 40), sh)
    sheet.paste(ic, (x, y), m)
sheet.save(pathlib.Path(__file__).resolve().parent / "icon_preview.png"); print("preview written")
