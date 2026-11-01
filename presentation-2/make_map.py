"""Locator map for 24-32 Farnsworth St from OpenStreetMap standard tiles.

    uv run --with pillow python presentation-2/make_map.py
"""

import io
import math
import urllib.request
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

LAT, LON = 42.35169, -71.04856  # 24 Farnsworth St (OpenStreetMap Nominatim)
ZOOM, W, H, SCALE = 16, 1400, 1180, 1  # output pixels; SCALE sizes the marker and labels
TILE = 256
LABEL = 2
OUT = Path(__file__).resolve().parent / "img" / "map.png"


def to_px(lat, lon, z):
    n = 2**z * TILE
    x = (lon + 180) / 360 * n
    y = (1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * n
    return x, y


cx, cy = to_px(LAT, LON, ZOOM)
w, h = W * SCALE, H * SCALE
x0, y0 = cx - w / 2, cy - h / 2
img = Image.new("RGB", (w, h), "white")
for tx in range(int(x0 // TILE), int((x0 + w) // TILE) + 1):
    for ty in range(int(y0 // TILE), int((y0 + h) // TILE) + 1):
        url = f"https://tile.openstreetmap.org/{ZOOM}/{tx}/{ty}.png"
        req = urllib.request.Request(url, headers={"User-Agent": "DS5500 course project map"})
        tile = Image.open(io.BytesIO(urllib.request.urlopen(req, timeout=30).read())).convert("RGB")
        img.paste(tile, (int(tx * TILE - x0), int(ty * TILE - y0)))

d = ImageDraw.Draw(img)
r = 8 * LABEL
px, py = w / 2, h / 2
d.ellipse([px - r - 6, py - r - 6, px + r + 6, py + r + 6], fill="white")
d.ellipse([px - r, py - r, px + r, py + r], fill="#eb6834")


def font(size):
    for f in ("/System/Library/Fonts/Supplemental/Arial Bold.ttf", "/Library/Fonts/Arial.ttf"):
        try:
            return ImageFont.truetype(f, size)
        except OSError:
            pass
    return ImageFont.load_default()


label = "24 Farnsworth St"
f = font(17 * LABEL)
tb = d.textbbox((0, 0), label, font=f)
lx, ly = px + r + 14, py - (tb[3] - tb[1]) / 2 - 4
d.rounded_rectangle([lx - 8, ly - 4, lx + tb[2] + 8, ly + tb[3] + 10], radius=8, fill="white", outline="#1d3557", width=3)
d.text((lx, ly), label, font=f, fill="#1d3557")

credit = "© OpenStreetMap contributors"
fc = font(10 * LABEL)
cb = d.textbbox((0, 0), credit, font=fc)
d.rectangle([w - cb[2] - 16, h - cb[3] - 12, w, h], fill="white")
d.text((w - cb[2] - 8, h - cb[3] - 8), credit, font=fc, fill="#52514e")

OUT.parent.mkdir(exist_ok=True)
img.save(OUT, optimize=True)
print(OUT, img.size)
