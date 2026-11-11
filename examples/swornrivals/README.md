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
| **Down** | crouch (down + away blocks low) |
| **Up** | jump |
| **A / X** | light / heavy punch |
| **B / Y** | light / heavy kick |
| **Fwd or Back + X**, up close | throw |
| **Motion + button** | the character's specials (QCF+P, DP+P, QCB+P, QCB+K, DP+K) |
| **↓ ↘ → + B** | Oath Surge (full meter) |

There are eight characters, each with their own specials, epithet, home stage and win
quote. The game also has chains and special cancels, combos with damage scaling, stun,
and chip damage.

- **1P Arcade:** pick a character, then climb a ladder of four CPU rivals, with a
  wreck-the-cart bonus stage after the second. Each character has their own ending.
- **2P Versus:** both players pick on one select screen; player 2 uses `INPUT1`.
- **Training:** an endless round against a dummy. Start cycles the dummy through
  stand, crouch, jump, guard, CPU, record and play. Holding Start quits.
- Leave the title alone for 15 seconds and a CPU-vs-CPU demo plays.

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

- **Streamed fighter frames.** Eight bodies × 22 poses of 64×64 art would never fit
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
- **Stages and lighting.** Each stage record holds a sky gradient plus the courtyard
  colour banks re-lit for the time of day, DMA'd together, so night stages darken
  the whole scene.
- **Sound.** The APU has no envelopes, so square 0 steps through short per-frame
  pitch and volume sequences (`SFXDATA`) for each kind of special.
- **Art.** `gen_art.js` draws the courtyard, HUD and fonts and renders every body in
  the extra fighting poses of `examples/streetbrawl/rig.js`.
