# Making art — PNG to cart sprites with png2tiles

`tools/png2tiles.js` turns a normal PNG into cart-ready 4bpp tiles plus an RGB555
palette, so you draw in any image editor instead of hand-packing nibbles. It is
asset-pipeline step A2 (see `docs/ASSET_PIPELINE_PLAN.md`). Zero dependencies:
Node built-ins only.

## 1. Draw and export a PNG

- Use **<= 15 visible colours** (palette index 0 is reserved for transparency, so a
  16-colour bank shows 15 colours plus see-through).
- Make see-through pixels **fully transparent** (alpha 0), or pick a key colour and
  pass `--transparent`.
- Export **non-interlaced, 8-bit** PNG. Colour type indexed (3), RGB (2), or RGBA (6)
  all work.
- Size the canvas to whole sprite blocks for your `--size`: a 16x16 sprite is a
  16x16 image; a sheet of four 16x16 sprites is 64x16 or 32x32, etc.

## 2. Convert

```
node tools/png2tiles.js ship.png --out gen --name ship --size 16 --bank 1
```

This writes three files into `gen/`:

| file | purpose |
| --- | --- |
| `ship.bin` | raw 4bpp tile bytes — pull in with `INCBIN "ship.bin"` |
| `ship.pal.asm` | a `CALL`able routine that seeds the palette via PAL_INDEX/PAL_DATA |
| `ship.json` | metadata (width, height, size, tileCount, palette, bank) |

### CLI options

```
node tools/png2tiles.js <in.png> [options]

  --out DIR             output directory (default: next to the input)
  --name LABEL          base name for the outputs + asm label (default: input filename)
  --size 8|16|32|64     sprite block size; the image is a row-major sheet of these (default: 8)
  --bank N              palette bank 0..15 to seed (default: 0)
  --transparent RRGGBB  treat this colour as transparent (index 0) as well as alpha 0
  --quantize            merge down to 16 colours instead of erroring when there are more
```

Tile order within a block is plain row-major, matching the PPU's sprite tile
addressing: a 16x16 is `TL, TR, BL, BR`; a 32x32 is its 16 tiles row by row; a
larger image is a row-major sheet of those blocks.

Without `--quantize`, more than 15 visible colours is an error (so a mistake in
your export is caught, not silently mangled). With `--quantize`, png2tiles merges
the least-used colours into their nearest neighbours until it fits.

> RGB555 note: the console packs colours as `(b5<<10)|(g5<<5)|r5` — **red in the
> low 5 bits** (e.g. `$001F` = red, `$03E0` = green), matching `system.js` and the
> shipped carts. png2tiles emits that format; you never have to compute it.

## 3. Use it in a cart

Load the tiles to VRAM, seed the palette, and draw a sprite:

```asm
VRAM_ADDR EQU $101000
VRAM_DATA EQU $101004
OAM_INDEX EQU $10100C
OAM_DATA  EQU $10100E

  ORG $300000
  DA start
  DA 0
  DA 0
  DA 0

start:
  ; copy the tile blob to VRAM tile 16 (byte offset $200)
  MOV R0, #$00
  STB R0, [VRAM_ADDR]
  MOV R0, #$02
  STB R0, [VRAM_ADDR+1]
  MOV R0, #0
  STB R0, [VRAM_ADDR+2]
  LDA A0, #tiledata
  MOV R1, #128            ; 4 tiles x 32 bytes (see ship.json tileCount)
cploop:
  LDB R2, [A0]
  STB R2, [VRAM_DATA]
  INC A0
  SUB R1, #1
  BNE cploop

  CALL ship_pal          ; seed bank 1 (label from ship.pal.asm)

  ; one 16x16 sprite, tile 16, palette bank 1, at (40,48)
  MOV R0, #0
  STW R0, [OAM_INDEX]
  MOV R0, #40
  STB R0, [OAM_DATA]     ; X lo
  MOV R0, #0
  STB R0, [OAM_DATA]     ; X hi
  MOV R0, #48
  STB R0, [OAM_DATA]     ; Y lo
  MOV R0, #0
  STB R0, [OAM_DATA]     ; Y hi
  MOV R0, #16
  STB R0, [OAM_DATA]     ; tile lo
  MOV R0, #0
  STB R0, [OAM_DATA]     ; tile hi
  MOV R0, #$11           ; attr lo: size 16x16 ($10) | palette bank 1
  STB R0, [OAM_DATA]
  MOV R0, #$80
  STB R0, [OAM_DATA]     ; attr hi: enable (bit 15)
main:
  WAIT
  BRA main

tiledata:
  INCBIN "ship.bin"

; --- paste ship.pal.asm here (the assembler has INCBIN but no INCLUDE yet) ---
ship_pal:
  MOV R0, #16
  STB R0, [$101008]      ; PAL_INDEX = bank*16
  MOV R0, #$001F
  STW R0, [$10100A]      ; ... one STW per colour (see ship.pal.asm)
  RET
```

`INCBIN` paths resolve relative to the `.asm` file. Until the assembler gains an
`INCLUDE` directive, paste the body of `ship.pal.asm` into your cart (it is a
self-contained `name_pal:` routine ending in `RET` — just `CALL` it once at init).

Build it:

```
node tools/build-cart.js ship_cart.asm ship.cpc SHIP
```

## 4. Round-trip evidence

The pipeline is verified end to end in `tests/png2tiles.test.js`: a known PNG is
converted, INCBIN'd into a tiny cart, run in the headless `System`, and the
framebuffer pixels are checked against the source colours. A 16x16 RGBA quadrant
(red / green / blue / white, with a transparent corner) renders back as exactly
those colours, and the transparent pixel shows the backdrop. The same flow works
from the command line against an on-disk PNG and `build-cart.js`.

## 5. Procedural art: Oathbound's 16-bit pass

Oathbound's graphics are not drawn in PNGs. `tools/oathbound-art.js` paints them from
code (shaded rigs for the characters, layered scenery for the backdrop) and writes
`carts/oathbound.art.bin`, which the cart INCBINs at `artbin` and DMAs into VRAM at
boot. The tool also rewrites the `ART-EQU` and `ART-RUNS` blocks in
`carts/oathbound.asm` with every tile index, section offset and VRAM run, so the cart
and the binary never drift apart.

```
node tools/oathbound-art.js                    # art.bin + EQUs
node tools/oathbound-art.js --png /tmp/oath    # plus sprite-sheet + backdrop previews
node tools/build-cart.js carts/oathbound.asm carts/oathbound.cpc OATHBOUND
node tools/oathrender.js carts/oathbound.cpc png 120 /tmp/oath/screen.png   # check in the cart
```

What it encodes:

- **Level picture vs collision.** The tool reads `levelBase` from the cart and
  auto-tiles it (grass, earth, mossy masonry, stone ledges, rope bridges, spikes,
  coins), plus decorations that never collide. The cart still streams collision from
  `levelBase`; only the BG0 picture comes from the visual map (`ART_VMAP0`).
- **One bank per tile.** Where two materials meet inside one 8x8 tile, the minority
  pixels are re-coloured to the nearest colour of the tile's bank. Zone accents (lit
  windows, flowers) are never used as stand-ins, because they change colour per zone.
- **Zone moods.** Scenery banks 0..5 are colour-graded per zone (morning, torchlit
  night, overcast, violet dusk), and each zone has a 224-line sky table that the
  hblank handler writes into palette entry 0 every scanline.
- **Three backdrops.** BG1 has an outdoor loop (zones 1 and 4), a torchlit dungeon
  (zone 2) and a great hall (zone 3). The indoor ones bring their own colours for
  banks 1..2, and `loadzonepal` copies the zone's map into BG1. They repeat every
  128 px and mirror inside each bay, so most tiles fold onto their h-flipped twins.
  The dungeon torches flicker by palette cycling (`ART_FLICK`, in `tickpalcycle`).
- **VRAM budget.** Tile 0 is blank and the front end owns its text glyphs (the boxed
  letters and digits and their pixel-doubled copies). The tool allocates art around
  them, so the art lands in a few contiguous runs, which the boot DMAs one by one
  from `artRuns`. It fails loudly if the art does not fit in 2048 tiles.
