# Audio Brief — Awakening Brochacho

## Music Vision

**Reference**: Diablo II OST by Matt Uelmen.
**Instruments**: Solo acoustic Spanish guitar (primary), orchestral strings, low brass,
hand percussion, ambient pads.
**Mood**: Dark pastoral. The land has weight. Every track should feel like memory.

---

## Music Tracks

All tracks: `.ogg` format, stereo, loop points set in Godot import settings.
Place files in `assets/audio/music/`.

| File | Chapter | Description |
|------|---------|-------------|
| `ch1_brochan_hold.ogg` | Act 1 — The Hold | Solo Spanish guitar, A-minor arpeggios, slow. Warm but quietly melancholic — home, but under shadow. Think Tristram Village. No percussion yet. |
| `ch2_the_unmooring.ogg` | Act 2 — The Unmooring | Guitar theme starts, cuts off mid-phrase. Strings enter dissonant — unresolved cadence hangs in the air. Jambione's death leaves a musical hole. |
| `ch3_the_seduction.ogg` | Act 3 — The Seduction | Harpsichord and pizzicato strings introduce the Settlement motif — charming, almost dance-like. Underneath, the Hold theme plays slightly out of phase. Two worlds pulling. |
| `ch4_the_reckoning.ogg` | Act 4 — The Reckoning | Full orchestral tension. Driving low strings, brass stabs. The Settlement motif returns inverted, ugly. No guitar — Brochacho has betrayed his roots. |
| `ch5_the_embers.ogg` | Act 5 — The Embers | Single aged guitar, slower than ch1, no percussion. The Hold theme reduced to three notes. Long silences between phrases. Old man's lament. |
| `ch6_the_awakening.ogg` | Act 6 — The Awakening | Guitar returns full force. Orchestra swells. The ch1 theme recapitulated at double tempo — triumphant. The Spanish guitar earns its resolution. |

---

## Sound Effects

All SFX: `.ogg` format, mono, normalized to -3 dBFS.
Place files in `assets/audio/sfx/`.

### Movement
| File | Description |
|------|-------------|
| `footstep_grass.ogg` | Soft dirt/grass step. Atari-era will be lo-fi filtered automatically. |
| `footstep_stone.ogg` | Hard stone floor — dungeon / hold interior. |
| `footstep_wood.ogg` | Wooden floor — buildings, docks. |

### Interaction
| File | Description |
|------|-------------|
| `interact.ogg` | Brief chime/click when player activates an NPC or object. |
| `chest_open.ogg` | Creak + jingle. Classic RPG chest. |
| `door_open.ogg` | Wooden door creak. |

### Dialogue
| File | Description |
|------|-------------|
| `dialogue_open.ogg` | Soft whoosh — dialogue box slides in. |
| `dialogue_next.ogg` | Subtle click/tick — text advances. Use something from Uelmen's UI palette. |
| `dialogue_close.ogg` | Reverse whoosh — box dismisses. |

### Inventory
| File | Description |
|------|-------------|
| `item_pickup.ogg` | Satisfying pickup chime. |
| `item_equip.ogg` | Metal/cloth rustle — equip sound. |
| `gold_pickup.ogg` | Coin jingle. |

### Quests
| File | Description |
|------|-------------|
| `quest_start.ogg` | Rising two-note motif — "something begins". |
| `quest_complete.ogg` | Resolved four-note phrase — the Hold theme's final bar. |

### UI
| File | Description |
|------|-------------|
| `menu_open.ogg` | Soft paper/book sound. |
| `menu_close.ogg` | Reverse of above. |
| `button_confirm.ogg` | Soft click. |
| `button_cancel.ogg` | Lower soft click. |

### Era Transition
| File | Description |
|------|-------------|
| `era_transition.ogg` | Shimmering sweep — time passing. Used when the visual era upgrades. |

### Combat
| File | Description |
|------|-------------|
| `sword_swing.ogg` | Whoosh — blade cut. |
| `hit_impact.ogg` | Blunt thud — impact landing. |
| `player_hurt.ogg` | Sharp sting — Brochacho hurt. |
| `enemy_death.ogg` | Enemy death — distinct per enemy type in future. |

### Dungeon
| File | Description |
|------|-------------|
| `dungeon_descend.ogg` | Hollow rumble — entering the dungeon. |

---

## Era Audio Processing

AudioManager applies these effects to the **Music bus** automatically:

| Era | Lowpass Filter | Reverb |
|-----|---------------|--------|
| Atari | 2 200 Hz | None |
| NES | 4 000 Hz | None |
| GBC | 7 000 Hz | None |
| SNES | Off | Light (room 0.35) |
| PS1 | Off | Medium (room 0.55) |
| Modern | Off | None |

SFX bus is **not** filtered — sfx always sound present regardless of era.
This mirrors how Diablo II's sfx cut through even ambient music.
