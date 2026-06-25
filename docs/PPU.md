# CastlePalm PPU (Graphics)

How to draw on CastlePalm. All register addresses are in [MMIO.md](MMIO.md); this
page explains the data formats behind them.

## Screen

- **320×224** pixels, rendered per scanline at ~60 fps.
- Two background layers (BG0, BG1) plus up to **128 sprites** (max 32 per scanline).

## Tiles & VRAM

Everything is built from **8×8 tiles at 4 bits-per-pixel** (16 colours each). A tile
is **32 bytes** (each byte = two pixels, low nibble first). Tile *N*'s pixel data
lives at VRAM byte offset `N * 32`.

You write VRAM through a port: set the 24-bit pointer in `VRAM_ADDR` (three bytes:
lo, mid, hi), then write bytes to `VRAM_DATA` — the pointer auto-increments. To
build tile 1 (offset `$20`):

```
MOV R0, #$20
STB R0, [VRAM_ADDR]      ; pointer lo
MOV R0, #0
STB R0, [VRAM_ADDR+1]    ; mid
STB R0, [VRAM_ADDR+2]    ; hi
; ...then write 32 bytes to [VRAM_DATA]
```

## Palette

256 colours total = **16 sub-palettes of 16 colours**, each colour **RGB555**
(`0bbbbbgggggrrrrr`, 15 bits). Write via `PAL_INDEX` (entry 0–255) then `PAL_DATA`
(auto-increments). A tile or sprite chooses which 16-colour sub-palette it uses via
its palette attribute. For sprites, **colour 0 is transparent**.

## Backgrounds

Two `64×64`-tile maps that wrap and scroll independently:

- Enable them with `PPU_CTRL` (bit0 = BG0, bit1 = BG1).
- Scroll with `BG0_SX/SY`, `BG1_SX/SY` (signed).
- The BG0 tile map lives in VRAM at offset `$10000`. Each map cell is **4 bytes**:
  tile index (11 bits), palette sub-palette, h/v flip, and priority.

(The Snake and PalmBlast examples drive the background; Pong is sprites-only.)

## Sprites (OAM)

128 sprite slots in a 1 KiB OAM, **8 bytes each**, written via `OAM_INDEX` (byte
offset, so slot *n* is `n*8`) then `OAM_DATA` (auto-increments). Each descriptor:

| Bytes | Field | Notes |
| --- | --- | --- |
| 0–1 | **X** | signed 16-bit |
| 2–3 | **Y** | signed 16-bit |
| 4–5 | **tile** | tile index (bits 0–10) |
| 6–7 | **attr** | palette (0–3), size (bits 4–5), hflip (6), vflip (7), priority (8–10), **enable (bit 15)** |

Sizes are **8 / 16 / 32 / 64** px (square). A sprite is only drawn if the enable
bit (`$80` in the high attr byte) is set — zeroing OAM hides everything. See
`examples/hello.asm` for the minimal "emit one sprite" sequence.

## DMA

For bulk transfers (a whole tile sheet, an OAM list, a palette) use the DMA channel
(`DMA_SRC/DST/LEN/MODE/CTRL` in [MMIO.md](MMIO.md)) instead of looping the ports —
it can copy from CPU memory into VRAM/OAM/palette, or fill a region with a constant.
