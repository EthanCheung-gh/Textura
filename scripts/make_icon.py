"""Generate the Textura / 织理 brand icon (1024x1024) with Pillow."""
from PIL import Image, ImageDraw

S = 1024
BG = (32, 29, 26, 255)       # deep ink
LINE = (235, 226, 214, 255)  # warm paper
GRID = (235, 226, 214, 54)   # faint woven thread
ACCENT = (192, 102, 58, 255) # terracotta

img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(img)

# Rounded square, deep ink.
d.rounded_rectangle((32, 32, S - 32, S - 32), radius=216, fill=BG)

# Woven grid: 5 / 5 warp-weft lines with soft opacity.
for i in range(1, 6):
    t = i / 6
    x = int(96 + t * (S - 192))
    y = int(96 + t * (S - 192))
    d.line((x, 140, x, S - 140), fill=GRID, width=6)
    d.line((140, y, S - 140, y), fill=GRID, width=6)

# Four paper nodes at the weaving intersections.
nodes = [(0.28, 0.28), (0.72, 0.28), (0.28, 0.72), (0.72, 0.72)]
for nx, ny in nodes:
    cx, cy = int(96 + nx * (S - 192)), int(96 + ny * (S - 192))
    d.ellipse((cx - 34, cy - 34, cx + 34, cy + 34), fill=LINE)

# Accent node + connecting thread (the one live node).
ax, ay = int(96 + 0.5 * (S - 192)), int(96 + 0.5 * (S - 192))
d.line((int(96 + 0.28 * (S - 192)), int(96 + 0.28 * (S - 192)), ax, ay), fill=ACCENT, width=14)
d.line((ax, ay, int(96 + 0.72 * (S - 192)), int(96 + 0.72 * (S - 192))), fill=ACCENT, width=14)
d.ellipse((ax - 56, ay - 56, ax + 56, ay + 56), fill=ACCENT)

img.save("src-tauri/icons/source.png")
print("wrote src-tauri/icons/source.png", img.size)
