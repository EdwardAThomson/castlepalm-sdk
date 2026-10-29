# STREET BRAWL — a beat-'em-up prototype

A Streets-of-Rage-style brawler for the CastlePalm console. Walk your hero along a
scrolling sidewalk, clear waves of thugs across three stages, beat the boss at the
end of each, and grab weapons and food along the way before the gang wears down
your health bar.

| Controls | |
| --- | --- |
| **D-pad** | move (8-way, within the sidewalk band) |
| **A** | punch, or swing your weapon if you're holding one |
| **Start** | begin / restart |

After the title comes a **character creator**: Up/Down picks a row (body, skin,
hair, top, legs, shoes), Left/Right changes it, **A** throws a test punch and
**Start** fights. There are eight bodies (Rio, Mara, Tank, Kenji, Zed, Fox, Lin,
Wolf), and your pick is kept in the cart's save RAM.

Thugs don't just walk into you: they square up, wind a punch back (the tell) and
swing, and only a punch that lands costs health.

Each **stage** is three thug waves and then a **boss** (its red health bar shows
under the stage label). Clearing the boss rolls a **"STAGE n — GET READY"**
interstitial and scrolls you into the next, freshly recoloured street. Clear the
final boss and it's **YOU WIN**; let the thugs drain the health bar up top and it's
**GAME OVER**.

Three **thug types** come at you, colour-coded and mixed in escalating combinations
per wave (see the `wavedef` table):

| Type | Look | Behaviour |
| --- | --- | --- |
| **Grunt** | average build, stage-coloured (red / magenta / orange) | average speed and toughness |
| **Runner** | lean, teal — headband and a sprinter's stance | fast but fragile — rushes you, drops in one pipe hit |
| **Bruiser** | hulking, brown — wide shoulders, fills the tile | slow (moves every other frame) but tanky and hits for double |

Each type has its own silhouette, not just a recolour, so you can read the threat at
a glance.

Hits land with a brief **hit-stop** freeze and the camera **shakes** when you take a
blow or drop an enemy, and a looping chiptune riff plays underneath (square-1; the
sound effects stay on square-0).

Bare fists take three hits to drop a thug. A **lead pipe** hits harder (one shot),
reaches farther, and swings faster, but only for a handful of swings — its
remaining swings show as green pips at the top-right next to a pipe icon. A
**drumstick** restores health. A pipe waits at the start, every cleared wave drops
food, and waves 2 and 4 drop a fresh pipe.

## Build & run

All the art is drawn from code by `gen_art.js` into six binaries (already
committed), which the cart `INCBIN`s. To rebuild them from source:

```sh
node examples/streetbrawl/gen_art.js
```

Assemble and screenshot it headlessly:

```sh
node tools/build-cart.js examples/streetbrawl/streetbrawl.asm streetbrawl.cpc BRAWL
node tools/run.js streetbrawl.cpc 1 title.png          # title screen
node tools/run.js streetbrawl.cpc 90 play.png --start  # 90 frames into a fight
```

> Note: run `run.js` against the built **`.cpc`**, not the `.asm` directly — the
> in-browser/`run.js` assembler path can't read `INCBIN` files; `build-cart.js` can.

Then play it interactively: open `play.html` and drag `streetbrawl.cpc` on, or load
it into Castle Arcade.

## How it works

- **`gen_art.js`** paints everything procedurally (street, parallax skyline, HUD
  font, pickups) and writes the blobs the cart `INCBIN`s:
  - `tiles.bin`: the VRAM tile region (tile *N* at byte `N*32`), DMA'd at boot
  - `maps.bin`: the BG0 skyline and BG1 street maps
  - `pal.bin`: all 256 palette entries (stage 1 colours)
  - `levels.bin`: per stage, a 224-line sky gradient plus three recoloured banks
  - `bodies.bin`: the eight selectable bodies, 6 frames each, DMA'd by the creator
  - `charpal.bin`: the creator's colour ramps for the player's palette bank

  Every material boundary sits on a tile edge, because a tile can only use one
  15-colour bank; the generator throws if one doesn't.
- **`rig.js`** is the fighter rig: body options in, a shaded 64×64 indexed frame
  and a 15-colour bank out (directional light, outline, per-part colour ramps).
  `gen_art.js` uses it for the player's bodies and the thugs.
- **Layers and raster effects.** BG0 is clouds and skyline, scrolled at `cam/4`
  for parallax; BG1 is the street with the HUD in its top two rows. An hblank
  handler rewrites palette entry 0 every line (the sky gradient) and holds BG1's
  scroll at 0 for lines 0-23, so the HUD stays put while the street scrolls.
- **`streetbrawl.asm`** is the game: a `title → play → win/over` state machine, a
  per-frame loop of *read pad → move → punch → enemy AI → pickups → camera → build
  OAM → `WAIT`*, a directional strike hitbox (longer + stronger while armed),
  chasing enemies that stagger/flash and get knocked back when hit, contact damage
  with i-frames, weapon/food pickups, and a BG-tile health + weapon HUD.
- **Enemy types** are data-driven. A per-type stat table (`TYPEHP`/`TYPESPD`/
  `TYPEDMG`/`TYPEBANK`) and a per-wave `wavedef` table describe who spawns where, so
  tuning difficulty or adding a wave is a data edit, not new code. The type lives in
  a parallel `ETYPE[]` array so the enemy slot keeps its tight 8-byte stride. Each
  type has its own rigged frames (picked via `TYPETILE`) and palette bank
  (`TYPEBANK`, recoloured per stage) — so they differ in both shape and colour.
- **Feel.** A `hitstop` counter freezes the whole scene for a few frames on impact;
  a `shakeT` counter adds a decaying horizontal camera jitter (folded into the same
  `cam` value the sprites and scroll already read). A tiny sequencer (`musictick`)
  walks a `song[]` period list on square-1 for background music, independent of the
  square-0 sound effects.
- **Scrolling & waves.** The street map repeats every 64 tiles, so writing the
  scroll register wraps seamlessly. A camera follows the player up to a
  per-wave limit that grows each time a wave is cleared; sprites are drawn at
  `worldX − camera`. The HUD lives on a second, non-scrolling layer (BG1) that
  composites over the street.
- **Stages, bosses & interstitials.** Each stage runs `NORMW` thug waves then a
  boss wave (one high-HP brute in enemy slot 0, drawn from its own palette with a
  red boss bar). Beating it enters an interstitial state with a countdown, then
  `loadlevel` copies the stage's record from `levels.bin` (sky gradient, brick and
  thug colours) and resets the camera. The font carries
  digits and a full A–Z so the HUD and screens can print "STAGE 2", "GET READY".

Grid math uses shifts where it can (`tileY*256 → tileY<<8`); the CPU also has
hardware `MULU`/`DIVU` for the rest.
