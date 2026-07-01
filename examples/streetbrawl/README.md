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

Each **stage** is three thug waves and then a **boss** (its red health bar shows
under the stage label). Clearing the boss rolls a **"STAGE n — GET READY"**
interstitial and scrolls you into the next, freshly recoloured street. Clear the
final boss and it's **YOU WIN**; let the thugs drain the health bar up top and it's
**GAME OVER**.

Three **thug types** come at you, colour-coded and mixed in escalating combinations
per wave (see the `wavedef` table):

| Type | Look | Behaviour |
| --- | --- | --- |
| **Grunt** | stage-coloured (red / magenta / orange) | average speed and toughness |
| **Runner** | teal | fast but fragile — rushes you, drops in one pipe hit |
| **Bruiser** | brown | slow (moves every other frame) but tanky and hits for double |

Hits land with a brief **hit-stop** freeze and the camera **shakes** when you take a
blow or drop an enemy, and a looping chiptune riff plays underneath (square-1; the
sound effects stay on square-0).

Bare fists take three hits to drop a thug. A **lead pipe** hits harder (one shot),
reaches farther, and swings faster, but only for a handful of swings — its
remaining swings show as green pips at the top-right next to a pipe icon. A
**drumstick** restores health. A pipe waits at the start, every cleared wave drops
food, and waves 2 and 4 drop a fresh pipe.

## Build & run

The art is generated into `assets.bin` (already committed) and `INCBIN`'d by the
cart. To rebuild the art from source:

```sh
node examples/streetbrawl/gen_assets.js
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

- **`gen_assets.js`** draws every tile as ASCII art and packs it into a 4bpp tile
  sheet (`assets.bin`). Tile *N* lands at VRAM byte `N*32`, so the cart just copies
  the whole blob to VRAM offset 0 at boot. 16×16 sprites are sliced into the 2×2
  tile order the PPU expects (TL, TR, BL, BR).
- **`streetbrawl.asm`** is the game: a `title → play → win/over` state machine, a
  per-frame loop of *read pad → move → punch → enemy AI → pickups → camera → build
  OAM → `WAIT`*, a directional strike hitbox (longer + stronger while armed),
  chasing enemies that stagger/flash and get knocked back when hit, contact damage
  with i-frames, weapon/food pickups, and a BG-tile health + weapon HUD.
- **Enemy types** are data-driven. A per-type stat table (`TYPEHP`/`TYPESPD`/
  `TYPEDMG`/`TYPEBANK`) and a per-wave `wavedef` table describe who spawns where, so
  tuning difficulty or adding a wave is a data edit, not new code. The type lives in
  a parallel `ETYPE[]` array so the enemy slot keeps its tight 8-byte stride, and
  each type is a palette swap (no extra tiles) — classic beat-'em-up recolouring.
- **Feel.** A `hitstop` counter freezes the whole scene for a few frames on impact;
  a `shakeT` counter adds a decaying horizontal camera jitter (folded into the same
  `cam` value the sprites and scroll already read). A tiny sequencer (`musictick`)
  walks a `song[]` period list on square-1 for background music, independent of the
  square-0 sound effects.
- **Scrolling & waves.** The 64-tile street map is column-uniform, so writing the
  `BG0_SX` scroll register wraps seamlessly. A camera follows the player up to a
  per-wave limit that grows each time a wave is cleared; sprites are drawn at
  `worldX − camera`. The HUD lives on a second, non-scrolling layer (BG1) that
  composites over the street.
- **Stages, bosses & interstitials.** Each stage runs `NORMW` thug waves then a
  boss wave (one high-HP brute in enemy slot 0, drawn from its own palette with a
  red boss bar). Beating it enters an interstitial state with a countdown, then
  `loadlevel` rebuilds the street, swaps in the stage's palette (brick / sidewalk /
  enemy-body colours from a small table), and resets the camera. The font carries
  digits and a full A–Z so the HUD and screens can print "STAGE 2", "GET READY".

Everything is built only from what the hardware has — note there's no multiply, so
grid math is done with shifts (`tileY*256 → tileY<<8`).
