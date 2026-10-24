#!/usr/bin/env python3
"""Generate the HarmonyOS app-icon set from the Linux brand mark.

Source of truth for the artwork: `scripts/make_icon.py` (the Linux/Tauri icon) — same deep-ink
rounded square, same faint woven grid, same four paper nodes, same terracotta centre node with its
two diagonals. This script only re-arranges that one mark for HarmonyOS's *layered* icon format:

  background.png  1024x1024, opaque `#201D1A`, no rounding (the system applies its own mask).
  foreground.png  1024x1024, transparent; the mark is scaled to ~66% of the canvas and centred so
                  it stays inside the launcher's safe area on every device mask.
  startIcon.png   1024x1024, the rounded square plus the mark, i.e. the mark as it looks on Linux
                  (HarmonyOS uses it as the splash/startup image).

Colours are the Linux brand palette verbatim:
  ink #201D1A, paper #EBE2D6, terracotta #C0663A.

Usage (from anywhere):
    python3 cangjie/scripts/harmony/make_icons.py            # write the files below
    python3 cangjie/scripts/harmony/make_icons.py --preview  # also write 32/64/128 px previews

Outputs (overwritten in place, all committed):
    cangjie/harmony/AppScope/resources/base/media/background.png
    cangjie/harmony/AppScope/resources/base/media/foreground.png
    cangjie/harmony/entry/src/main/resources/base/media/background.png
    cangjie/harmony/entry/src/main/resources/base/media/foreground.png
    cangjie/harmony/entry/src/main/resources/base/media/startIcon.png
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw

# --- brand palette (Linux `scripts/make_icon.py`) -------------------------------------------
INK = (32, 29, 26, 255)        # #201D1A deep ink
PAPER = (235, 226, 214, 255)   # #EBE2D6 warm paper
TERRACOTTA = (192, 102, 58, 255)  # #C0663A

# The Linux source draws on a 1024 canvas with a 32px outer margin and a 216 corner radius; the
# floating layer repeats the same proportions so the two platform icons read as one mark.
SOURCE_SIZE = 1024
SOURCE_MARGIN = 32
SOURCE_RADIUS = 216

# Foreground safe area: the launcher mask is applied on top, so the artwork must stay inside a
# centred box of this share of the canvas (66% keeps a comfortable margin under HarmonyOS's
# squircle and circle masks).
FOREGROUND_ART_RATIO = 0.66

# Small-size legibility: on the foreground the grid is drawn a little heavier and a little more
# opaque than on the Linux icon (which is normally seen at >= 32px with a dark plate behind it),
# because the floating layer is composited over the background and shrunk by the launcher.
FOREGROUND_GRID_WIDTH = 8
FOREGROUND_GRID_ALPHA = 76     # of 255 -> ~30%
FOREGROUND_NODE_BUMP = 1.15    # nodes read as dots, not specks, once the mark is 66% of the canvas
FOREGROUND_ACCENT_BUMP = 1.10  # the live node stays "slightly larger" than the paper ones

ICON_SIZE = 1024


def _mark(size: int, *, grid_width: float, grid_alpha: int, margin: int,
          node_bump: float = 1.0, accent_bump: float = 1.0) -> Image.Image:
    """The brand mark on a transparent canvas of `size`, matching `scripts/make_icon.py`."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # The mark's own coordinate system: `scripts/make_icon.py` insets by 96px of 1024 and scales
    # everything against that inner box.
    def px(ratio: float) -> float:
        return margin + ratio * (size - 2 * margin)

    scale = (size - 2 * margin) / (SOURCE_SIZE - 2 * SOURCE_MARGIN)
    grid = (PAPER[0], PAPER[1], PAPER[2], grid_alpha)

    # Woven grid: 5 warp / 5 weft threads across the inner box.
    for i in range(1, 6):
        t = i / 6
        x = px(t)
        y = px(t)
        draw.line((x, px(0.05), x, px(0.95)), fill=grid, width=round(grid_width))
        draw.line((px(0.05), y, px(0.95), y), fill=grid, width=round(grid_width))

    # Four paper nodes on the weaving intersections.
    node_radius = 34 * scale * node_bump
    for nx, ny in ((0.28, 0.28), (0.72, 0.28), (0.28, 0.72), (0.72, 0.72)):
        cx, cy = px(nx), px(ny)
        draw.ellipse((cx - node_radius, cy - node_radius, cx + node_radius, cy + node_radius), fill=PAPER)

    # The one live node: terracotta, slightly larger, joined to two paper corners.
    cx, cy = px(0.5), px(0.5)
    for tx, ty in ((0.28, 0.28), (0.72, 0.72)):
        draw.line((px(tx), px(ty), cx, cy), fill=TERRACOTTA, width=max(2, round(14 * scale)))
    accent_radius = 56 * scale * accent_bump
    draw.ellipse((cx - accent_radius, cy - accent_radius, cx + accent_radius, cy + accent_radius),
                 fill=TERRACOTTA)
    return img


def background(size: int = ICON_SIZE) -> Image.Image:
    """Opaque deep-ink plate, full bleed: the system mask supplies the corner radius."""
    return Image.new("RGBA", (size, size), INK)


def foreground(size: int = ICON_SIZE) -> Image.Image:
    """Transparent layer: the mark alone, scaled into the safe area (no dark plate)."""
    # `_mark` insets by `inset` and draws between 5% and 95% of what is left, so the visible artwork
    # is 0.9 * (1 - 2 * 0.10) = 0.72 of its own canvas. Undo that here so the *visible* mark is
    # exactly `FOREGROUND_ART_RATIO` of the icon (measured back with `Image.getbbox()`).
    visible_share = 0.90 * (1.0 - 2 * 0.10)
    art_span = round(size * FOREGROUND_ART_RATIO / visible_share)
    inset = round(art_span * 0.10)
    art = _mark(art_span, grid_width=FOREGROUND_GRID_WIDTH, grid_alpha=FOREGROUND_GRID_ALPHA, margin=inset,
                node_bump=FOREGROUND_NODE_BUMP, accent_bump=FOREGROUND_ACCENT_BUMP)
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    offset = ((size - art_span) // 2, (size - art_span) // 2)
    layer.alpha_composite(art, offset)
    return layer


def start_icon(size: int = ICON_SIZE) -> Image.Image:
    """Linux look: the rounded ink square with the mark inside it (used as the splash image)."""
    plate = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(plate)
    margin = round(SOURCE_MARGIN * size / SOURCE_SIZE)
    radius = round(SOURCE_RADIUS * size / SOURCE_SIZE)
    draw.rounded_rectangle((margin, margin, size - margin, size - margin), radius=radius, fill=INK)

    art_span = round((size - 2 * margin) * (SOURCE_SIZE - 2 * 96) / (SOURCE_SIZE - 2 * SOURCE_MARGIN))
    art = _mark(art_span, grid_width=max(2, round(6 * art_span / (SOURCE_SIZE - 2 * SOURCE_MARGIN))),
                grid_alpha=54, margin=round(96 * art_span / (SOURCE_SIZE - 2 * SOURCE_MARGIN)))
    plate.alpha_composite(art, ((size - art_span) // 2, (size - art_span) // 2))
    return plate


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    app_media = root / "harmony/AppScope/resources/base/media"
    entry_media = root / "harmony/entry/src/main/resources/base/media"

    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--preview", action="store_true",
                        help="also write 32/64/128 px previews of the icon to /tmp/textura-icon-preview")
    parser.add_argument("--size", type=int, default=ICON_SIZE)
    args = parser.parse_args()

    bg = background(args.size)
    fg = foreground(args.size)
    start = start_icon(args.size)

    outputs = {
        app_media / "background.png": bg,
        app_media / "foreground.png": fg,
        entry_media / "background.png": bg,
        entry_media / "foreground.png": fg,
        entry_media / "startIcon.png": start,
    }
    for path, image in outputs.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        image.save(path)
        print(f"wrote {path.relative_to(root)} {image.size[0]}x{image.size[1]} {image.mode}")

    if args.preview:
        out = Path("/tmp/textura-icon-preview")
        out.mkdir(parents=True, exist_ok=True)
        for label, image in (("background", bg), ("foreground", fg), ("starticon", start)):
            for edge in (32, 64, 128):
                small = image.resize((edge, edge), Image.LANCZOS)
                target = out / f"{label}-{edge}.png"
                small.save(target)
                print(f"preview {target} {small.size[0]}x{small.size[1]}")
        # Launcher-style composite: background + foreground, which is what the device shows.
        for edge in (32, 64, 128):
            composed = Image.alpha_composite(bg.resize((edge, edge), Image.LANCZOS),
                                             fg.resize((edge, edge), Image.LANCZOS))
            target = out / f"composited-{edge}.png"
            composed.save(target)
            print(f"preview {target} {composed.size[0]}x{composed.size[1]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
