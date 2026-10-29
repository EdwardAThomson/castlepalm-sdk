# SIEGESTONE — a versus falling-stone puzzle

Two castle wells sit side by side, each 6 × 12 cells. Pairs of mason's stones fall
into each well; four or more touching stones of one colour clear. Every clear loads
your **catapult basket**, and **B** looses it: cracked rubble flies over the wall
into your rival's well. Fill the rival's well to the top to win.

| Controls | |
| --- | --- |
| **D-pad Left / Right** | shift the falling pair |
| **D-pad Down** | soft drop |
| **A** | turn clockwise |
| **X / Y** | turn counter-clockwise |
| **B** | loose the catapult |
| **Start** | begin; pause in play |

On the title, **A** starts the **Solo Ladder** (pad 1 against five CPU rivals) and
**B** starts **2 Players** (pad 2 on `INPUT1`).

The twists:

- **Rubble** needs two separate neighbouring clears to break (it cracks first).
- **Wet mortar** glues its neighbours in place when it sets, unless a clear touches
  it in time. Its look darkens as the timer runs down.
- A volley that lands while **your** basket holds stones spills half of it, so
  hoarding for a big chain is a gamble. Chains multiply the load (×1, 2, 3, 5, 8, 12).

## Build & run

All the art is drawn from code by `gen_art.js` into `art.bin` (already
committed), which the cart `INCBIN`s. To rebuild it:

```sh
node examples/siegestone/gen_art.js                   # art.bin + the ART-EQU block
node examples/siegestone/gen_art.js --png /tmp/sg     # plus a sprite-sheet preview
node tools/build-cart.js examples/siegestone/siegestone.asm siegestone.cpc SIEGESTONE
node tools/run.js siegestone.cpc 200 shot.png --start
```

Then open `play.html` and pick **Siegestone**, or drag `siegestone.cpc` on.

## How it works

- **One state machine, two wells.** Each well is a player block (`PL0` / `PL1`) and
  every well routine takes `A3` = the block, so both players run the same
  *spawn → fall → lock → settle → check* loop every frame.
- **Sentinel grid.** A well is stored 8 cells wide with `$FF` in the two spare
  columns and in the rows above and below, so neighbour and bounds checks need no
  range tests. Clears are found with a flood fill.
- **The CPU rival** writes a virtual pad 2, the same trick PalmBlast uses, so the
  game logic can't tell a CPU from a second player.
- **Art.** `gen_art.js` paints the stones, castle frame, backdrop, catapult and fonts
  procedurally, packs them into one contiguous run of tiles (one DMA at boot), and
  rewrites the `ART-EQU` block in `siegestone.asm` with every tile index and byte
  offset so the cart and the binary never drift. An hblank handler writes the sky
  gradient into palette entry 0 every scanline.
