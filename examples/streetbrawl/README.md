# STREET BRAWL — a beat-'em-up prototype

A Streets-of-Rage-style brawler for the CastlePalm console. Walk your hero around
a sidewalk, throw punches, and clear the street of thugs before they wear down
your health bar.

| Controls | |
| --- | --- |
| **D-pad** | move (8-way, within the sidewalk band) |
| **A** | punch (a short directional jab in front of you) |
| **Start** | begin / restart |

Clear all six thugs and it's **YOU WIN**; let them drain the health bar up top and
it's **GAME OVER**.

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
  per-frame loop of *read pad → move → punch → run enemy AI → build OAM → `WAIT`*,
  a directional punch hitbox, chasing enemies that stagger/flash and get knocked
  back when hit, contact damage with i-frames, and a BG-tile health bar.

Everything is built only from what the hardware has — note there's no multiply, so
grid math is done with shifts (`tileY*256 → tileY<<8`).
