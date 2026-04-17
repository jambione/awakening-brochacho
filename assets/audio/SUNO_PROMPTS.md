# Suno Prompts — Awakening Brochacho Music

## How to use
1. Go to suno.com (free account, ~10 songs/day)
2. Click **Create** → **Custom Mode**
3. Paste the **Style** into the Style of Music field
4. Paste the **Prompt** into the Lyrics field (or leave lyrics blank for instrumental)
5. Check **Instrumental**
6. Generate — download the best result as `.mp3`, rename to the filename below
7. Convert to `.ogg`: `ffmpeg -i input.mp3 output.ogg` (or use Audacity, free)
8. Drop into `assets/audio/music/`

---

## ch1_brochan_hold.ogg
**Filename**: `ch1_brochan_hold.ogg`

**Style**:
```
acoustic Spanish guitar, dark ambient RPG, fingerpicking arpeggios, A minor, slow tempo 60bpm, melancholic, pastoral, Matt Uelmen Diablo 2 style, no drums, solo guitar, intimate
```

**Prompt** (leave blank for pure instrumental, or use):
```
[Intro]
[Spanish guitar solo, slow fingerpicking, A minor arpeggio, warm and melancholic]
[the sound of ancient land, a family home under shadow]
[loop seamlessly]
```

**Target feel**: Tristram Village. Home, but quietly threatened. A boy learning from his father on old land. 90-second loop.

---

## ch2_the_unmooring.ogg
**Filename**: `ch2_the_unmooring.ogg`

**Style**:
```
dark orchestral, strings dissonant, Spanish guitar interrupted, minor key, slow, grief, unresolved cadence, chamber ensemble, cello, violin, Matt Uelmen inspired, no resolution
```

**Prompt**:
```
[Intro]
[guitar begins familiar theme, suddenly cuts off mid-phrase]
[dissonant strings enter, unresolved, hanging]
[cello low drone, grief, loss, emptiness]
[no resolution, the silence where father used to be]
[loop at dissonant section]
```

**Target feel**: Jambione's death. The guitar starts the ch1 theme, stops. Strings fill the silence wrongly. 90-second loop ending on an unresolved chord.

---

## ch3_the_seduction.ogg
**Filename**: `ch3_the_seduction.ogg`

**Style**:
```
dark baroque, harpsichord, pizzicato strings, charming but sinister, D minor, moderate tempo 80bpm, two competing themes, civil elegant surface hiding corruption, Diablo 2 court music
```

**Prompt**:
```
[Intro]
[harpsichord, elegant dance rhythm, pizzicato strings, charming and refined]
[underneath: familiar guitar theme plays slightly out of phase, distorted]
[two worlds in conflict, the settlement's charm vs the hold's memory]
[builds slightly, harpsichord wins, guitar fades]
[loop]
```

**Target feel**: Elder Cassin's world. Beautiful on the surface, wrong underneath. The Hold theme is still there but can barely be heard beneath society's music.

---

## ch4_the_reckoning.ogg
**Filename**: `ch4_the_reckoning.ogg`

**Style**:
```
dark orchestral tension, dramatic, full ensemble, driving low strings, brass stabs, no guitar, betrayal, climax, dissonant, powerful, Diablo 2 Act 3 style, building dread
```

**Prompt**:
```
[Intro]
[low strings driving rhythm, urgent]
[brass stabs, dissonant, Settlement motif inverted and ugly]
[no guitar — Brochacho has abandoned his roots]
[tension builds, full orchestra, no resolution]
[loop at peak tension]
```

**Target feel**: Full orchestral force. Betrayal revealed. No Spanish guitar at all — its absence is the point. Settlement allies turn on Brochacho.

---

## ch5_the_embers.ogg
**Filename**: `ch5_the_embers.ogg`

**Style**:
```
solo acoustic guitar, aged, slow, sparse, only three notes, old man grief, long silences between phrases, intimate, quiet, exhausted, Matt Uelmen minimal, no percussion, no orchestra
```

**Prompt**:
```
[Intro]
[aged guitar, three notes only, very slow]
[long silence]
[three notes again, slightly different]
[long silence — the family is gone, the land is taken]
[loop with silences intact]
```

**Target feel**: Old Brochacho. The ch1 theme reduced to three notes. Most of his family has died. Long silences between phrases. The quietest, saddest track.

---

## ch6_the_awakening.ogg
**Filename**: `ch6_the_awakening.ogg`

**Style**:
```
Spanish guitar triumphant, full orchestra swell, A minor to A major resolution, double tempo from chapter 1, heroic, emotional payoff, flamenco energy, Matt Uelmen climax, guitar and strings together
```

**Prompt**:
```
[Intro]
[guitar returns — the ch1 theme but double tempo, full energy]
[orchestra swells behind, strings now supporting the guitar not fighting it]
[builds to full ensemble, brass triumphant]
[resolution to major key — the land reclaimed]
[loop at full swell]
```

**Target feel**: Cathartic release. The Spanish guitar that went silent in Act 4 comes back stronger than ever. Everything the story has been building toward. The Brochan Hold theme finally resolves.

---

## Tips for best Suno results

- Generate 4–6 variations, pick the best
- Use **Remaster** on the winner to extend or improve it
- Set duration to 2:00+ to get a full loop
- If the guitar starts with singing, regenerate — we need instrumental only
- The `[loop]` tag at the end helps Suno make the ending blend into the beginning
- Download as `.mp3` (320kbps), convert to `.ogg` with ffmpeg or Audacity

## Free alternatives to Suno

- **Udio** (udio.com) — similar quality, different model, sometimes better for orchestral
- **Stable Audio** (stableaudio.com) — 45-second free clips, good for looping ambience
- **OpenGameArt.org** — search "RPG OST" or "dark ambient guitar" for CC-licensed tracks
