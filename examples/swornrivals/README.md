# SWORN RIVALS — a 1v1 versus fighter

Two fighters from the Street Brawl character creator duel in the courtyard of the
Palmgate. Before each round both players secretly **swear an oath** with a face
button. Keep it and your Oath meter fills; break it and the whole meter goes to your
rival. A full meter powers the **Oath Surge** super.

| Button | Oath | Broken when you… |
| --- | --- | --- |
| **A** | No Guard | block an attack |
| **B** | Fists Only | start any kick (including the Oath Surge) |
| **X** | Sky Striker | land a ground attack |
| **Y** | Stand Fast | walk backwards for 16 frames in a row, or jump backwards |

Nothing on screen shows which oath was sworn; the round-end screen reveals both.

| Controls | |
| --- | --- |
| **Left / Right** | walk (hold away to block) |
| **Down** | crouch |
| **Up** | jump |
| **A / B** | punch / kick |
| **↓ ↘ → + A** | Gate Rush |
| **→ ↓ ↘ + A** | Palm Rise |
| **↓ ↘ → + B** | Oath Surge (full meter) |

**1P Arcade** is a ladder of four CPU rivals; **2P Versus** puts player 2 on
`INPUT1`.

## Build & run

This example shares Street Brawl's fighter rig and colour ramps, so it reads files
from `examples/streetbrawl/` (`rig.js`, `gen_art.js` and `charpal.bin`). The art
blobs are committed; to rebuild them:

```sh
node examples/swornrivals/gen_art.js
node tools/build-cart.js examples/swornrivals/swornrivals.asm swornrivals.cpc "SWORN RIVALS"
node tools/run.js swornrivals.cpc 240 shot.png --start
```

Then open `play.html` and pick **Sworn Rivals**, or drag `swornrivals.cpc` on.

## How it works

- **Streamed fighter frames.** Eight bodies × 17 poses of 64×64 art would never fit
  in VRAM at once, so they live in the cart (`bodies.bin`) and each frame the cart
  DMAs the current pose of each fighter into its own 64-tile VRAM slot (4 KB a
  frame). This is the main technique the example shows.
- **Special-move input.** `motionrec` logs each fighter's direction changes
  (relative to facing) into a short buffer, and `motion` looks for a three-step
  pattern inside a 16-frame window (`MOTIONW`) when a button is pressed.
- **Layers.** BG0 is the sky and far palace (half-speed parallax); BG1 is the
  courtyard with the HUD in its top rows. The hblank handler paints a per-line sky
  gradient into palette entry 0 and holds BG1 unscrolled for the HUD, like Street
  Brawl.
- **Art.** `gen_art.js` draws the courtyard, HUD and fonts and renders every body in
  the extra fighting poses of `examples/streetbrawl/rig.js`.
