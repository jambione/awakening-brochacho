# Sprite Guide — Awakening Brochacho

## Free Asset Sources (No Attribution Required)

### Kenney.nl — Best Starting Point
Everything is CC0 (public domain). Download, drop in, done.

| Pack | URL | Use for |
|------|-----|---------|
| Tiny Dungeon | kenney.nl/assets/tiny-dungeon | Characters, dungeon tiles, items |
| Micro Roguelike | kenney.nl/assets/micro-roguelike | Overworld tiles, NPCs |
| RPG Urban Pack | kenney.nl/assets/rpg-urban-pack | Settlement/city tiles (Act 3) |
| 1-Bit Pack | kenney.nl/assets/1-bit-pack | Perfect for Atari/NES era look |

**Setup**: Download → unzip → copy the `16x16` sprite sheets into `assets/sprites/`.

### OpenGameArt.org
Search for: "LPC characters" (Liberated Pixel Cup) — high quality 16x16/32x32 RPG sprites, CC-BY or CC0.

---

## What the Game Needs Right Now

### Characters (16×16 or 16×32)

| Sprite | File | Notes |
|--------|------|-------|
| Player (Brochacho) | `characters/player.png` | Walk 4-direction + idle. Kenney Tiny Dungeon has good hero base. |
| Jambione | `characters/jambione.png` | Older male NPC. Static is fine for now. |
| Jesse | `characters/jesse.png` | Young male NPC, similar age to player. |
| Cassin | `characters/cassin.png` | Elder, well-dressed, Settlement style. |
| Generic NPC | `characters/npc.png` | Fallback for unnamed characters. |

### Tilesets (16×16 tiles)

| Tileset | File | Notes |
|---------|------|-------|
| Overworld | `tilesets/overworld.png` | Grass, dirt paths, stone walls, trees, boundary stones |
| Hold Interior | `tilesets/hold_interior.png` | Stone floor, wooden details, hearth |
| Dungeon | `tilesets/dungeon.png` | Dark stone, torch sconces, rubble |
| Settlement | `tilesets/settlement.png` | Cobblestone, city architecture (Act 3+) |

### UI Elements

| Element | File | Notes |
|---------|------|-------|
| Dialogue box skin | `ui/dialogue_box.png` | 9-patch border for the dialogue panel |
| Health bar | `ui/healthbar.png` | Party member HP display |
| Portrait frames | `ui/portrait_frame.png` | Border for combat party portraits |

---

## Recommended Kenney Workflow

1. **Download Kenney Tiny Dungeon** — this covers most Act 1 needs
2. Open in any image viewer — it's a spritesheet (16×16 grid)
3. In Godot: import as Texture2D, set filter to **Nearest** (critical for pixel-perfect look)
4. Use Godot's SpriteFrames editor to slice into individual frames
5. For TileMapLayer: create a TileSet, import the tileset PNG, define 16×16 tile regions

---

## Era Visual System Note

The `era_post.gdshader` post-process applies palette reduction and pixelation on top of whatever sprites you use. This means:

- **Atari era**: even detailed sprites will look like 4-color B&W blobs
- **NES era**: 16-color palette reduces sprites to chunky art
- **SNES/PS1**: sprites look close to their original quality
- **Modern era**: full fidelity, sprites as-drawn

So you don't need era-specific sprite variants — one set of sprites looks right across all eras because the shader handles the transformation.

---

## Aseprite (Pixel Art Editor)

If you want to draw custom sprites:

- **Aseprite** — $20 on Steam/itch.io, industry standard, worth it
- **Libresprite** — free fork, slightly outdated but functional
- **Piskel** — free, browser-based (piskelapp.com), good for quick edits
- **Lospec** — lospec.com has era-accurate palettes (NES, Game Boy, SNES) and tutorials

### Quick sprite spec for this game
- Canvas: 16×16 pixels per frame
- Animation: 4 frames per direction (idle can be 1 frame)
- Export as PNG spritesheet, horizontal strip
- Use the Lospec NES palette or GBC palette to stay era-accurate
