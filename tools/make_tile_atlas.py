#!/usr/bin/env python3
"""
make_tile_atlas.py — generate numbered tile reference images.

For each tileset, produces a PNG where every tile has its index number
printed over it so you can identify which tile to use in Godot.

Run from the project root:
    python3 tools/make_tile_atlas.py

Requires Pillow:  pip3 install pillow
Output goes to:   tools/tile_atlas/
"""

import os
import sys

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    print("Pillow not installed.  Run:  pip3 install pillow")
    sys.exit(1)

OUT_DIR = os.path.join(os.path.dirname(__file__), "tile_atlas")
os.makedirs(OUT_DIR, exist_ok=True)

TILESETS = [
    {
        "name"       : "micro_roguelike",
        "src"        : "assets/sprites/tilesets/micro_roguelike_packed.png",
        "tile_w"     : 8,
        "tile_h"     : 8,
        "spacing"    : 0,
        "scale"      : 4,   # 8px → 32px display
    },
    {
        "name"       : "urban",
        "src"        : "assets/sprites/tilesets/urban_packed.png",
        "tile_w"     : 16,
        "tile_h"     : 16,
        "spacing"    : 0,
        "scale"      : 2,   # 16px → 32px display
    },
    {
        "name"       : "1bit",
        "src"        : "assets/sprites/tilesets/1bit_packed.png",
        "tile_w"     : 16,
        "tile_h"     : 16,
        "spacing"    : 0,
        "scale"      : 2,
    },
]

LABEL_COLOR  = (255, 255, 0, 220)   # yellow, semi-transparent
BORDER_COLOR = (80, 80, 80, 128)
LABEL_SIZE   = 7   # font size in pixels for PIL default font


def make_atlas(cfg: dict) -> None:
    src_path = cfg["src"]
    if not os.path.exists(src_path):
        print(f"  SKIP (not found): {src_path}")
        return

    img   = Image.open(src_path).convert("RGBA")
    tw, th = cfg["tile_w"], cfg["tile_h"]
    sp    = cfg["spacing"]
    scale = cfg["scale"]
    step  = tw + sp

    cols  = img.width  // step
    rows  = img.height // step
    total = cols * rows

    cell  = tw * scale          # display cell size
    atlas = Image.new("RGBA", (cols * cell, rows * cell), (30, 30, 30, 255))
    draw  = ImageDraw.Draw(atlas)

    for idx in range(total):
        row, col = divmod(idx, cols)
        sx = col * step
        sy = row * step
        tile = img.crop((sx, sy, sx + tw, sy + th))
        tile = tile.resize((cell, cell), Image.NEAREST)

        dx = col * cell
        dy = row * cell
        atlas.paste(tile, (dx, dy))

        # Draw border
        draw.rectangle([dx, dy, dx + cell - 1, dy + cell - 1],
                       outline=(60, 60, 60, 180))

        # Draw index label (white text with dark shadow)
        label = str(idx)
        # Shadow
        draw.text((dx + 2, dy + 2), label, fill=(0, 0, 0, 200))
        # Label
        draw.text((dx + 1, dy + 1), label, fill=LABEL_COLOR)

    out_path = os.path.join(OUT_DIR, cfg["name"] + "_atlas.png")
    atlas.save(out_path)
    print(f"  {cfg['name']}: {cols}×{rows} = {total} tiles  →  {out_path}")


def main() -> None:
    print(f"Writing tile atlases to {os.path.abspath(OUT_DIR)}/\n")
    for cfg in TILESETS:
        make_atlas(cfg)
    print("\nOpen the atlas PNGs to identify tile numbers.")
    print("Key character tiles to look for:")
    print("  micro_roguelike: rows 6-9 (tiles 96-159) — characters/items")
    print("  urban:           rows 15-17 (tiles 378-485) — characters/people")


if __name__ == "__main__":
    main()
