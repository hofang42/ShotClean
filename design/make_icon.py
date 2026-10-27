"""Generates ShotClean app icon: python make_icon.py  (needs Pillow)."""
import os, math
from PIL import Image, ImageDraw, ImageFilter

S = 4096  # 4x supersample of 1024
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "ShotClean", "Support", "AppIcon.png")

def lerp(a, b, t): return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

def gradient(size, c1, c2):
    # diagonal gradient built from a small ramp, scaled up
    n = 512
    g = Image.new("RGB", (n, n))
    px = g.load()
    for y in range(n):
        for x in range(n):
            px[x, y] = lerp(c1, c2, (x + y) / (2 * (n - 1)))
    return g.resize((size, size), Image.BICUBIC)

def star(d, cx, cy, r, fill, pinch=0.18):
    pts = []
    for i in range(8):
        a = math.pi / 2 * (i / 2) - math.pi / 2
        rr = r if i % 2 == 0 else r * pinch
        pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    d.polygon(pts, fill=fill)

img = gradient(S, (0x2A, 0x1B, 0x9C), (0x14, 0xD6, 0xB8))

# soft glow
glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(glow).ellipse((S*0.15, S*0.1, S*0.85, S*0.8), fill=(255, 255, 255, 40))
glow = glow.filter(ImageFilter.GaussianBlur(S * 0.08))
img = Image.alpha_composite(img.convert("RGBA"), glow)

# phone shadow
sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
pw, ph = S * 0.44, S * 0.70
x0, y0 = (S - pw) / 2, (S - ph) / 2
ImageDraw.Draw(sh).rounded_rectangle((x0, y0 + S*0.02, x0 + pw, y0 + ph + S*0.02), S*0.08, fill=(10, 5, 60, 110))
img = Image.alpha_composite(img, sh.filter(ImageFilter.GaussianBlur(S * 0.02)))

d = ImageDraw.Draw(img)
d.rounded_rectangle((x0, y0, x0 + pw, y0 + ph), S*0.08, fill=(255, 255, 255, 255))
# screen
m = S * 0.028
sx0, sy0, sx1, sy1 = x0 + m, y0 + m, x0 + pw - m, y0 + ph - m
screen = gradient(S, (0x3B, 0x2D, 0xC4), (0x1B, 0xA8, 0xA0)).convert("RGBA")
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle((sx0, sy0, sx1, sy1), S*0.058, fill=255)
img.paste(screen, (0, 0), mask)
d = ImageDraw.Draw(img)
# notch pill
d.rounded_rectangle((S*0.5 - S*0.05, sy0 + S*0.02, S*0.5 + S*0.05, sy0 + S*0.04), S*0.01, fill=(255, 255, 255, 90))

# clean-sweep: bright diagonal swoosh wiping across the screen
sw = Image.new("RGBA", (S, S), (0, 0, 0, 0))
sd = ImageDraw.Draw(sw)
sd.polygon([(sx0 - S*0.02, sy1 - S*0.20), (sx1 + S*0.02, sy0 + S*0.30), (sx1 + S*0.02, sy0 + S*0.42), (sx0 - S*0.02, sy1 - S*0.06)], fill=(255, 255, 255, 46))
sw = Image.composite(sw, Image.new("RGBA", (S, S), (0, 0, 0, 0)), mask)
img = Image.alpha_composite(img, sw)
d = ImageDraw.Draw(img)

# big sparkle + small sparkles
star(d, S*0.5, S*0.47, S*0.17, (255, 255, 255, 255))
star(d, S*0.60, S*0.31, S*0.055, (255, 255, 255, 235))
star(d, S*0.39, S*0.65, S*0.05, (255, 255, 255, 220))

out = img.convert("RGB").resize((1024, 1024), Image.LANCZOS)
out.save(OUT, "PNG")
out.resize((256, 256), Image.LANCZOS).save(os.path.join(HERE, "icon-preview.png"), "PNG")
print("ok", out.mode, out.size)
