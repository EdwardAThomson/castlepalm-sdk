# CastlePalm MMIO Register Map

The concrete register addresses the CPU uses to reach input, video, and audio, as
implemented by the engine, within the [MEMORY_MAP.md](MEMORY_MAP.md) windows.

## System / CPU MMIO (`$100000`)

| Address | Name | Access | Meaning |
| --- | --- | --- | --- |
| `$100000` | `INPUT` / `INPUT0` | read u16 | Player 1 controller word: Up=1, Down=2, Left=4, Right=8, A=16, B=32, X=64, Y=128, Start=256, Power=512 |
| `$100002` | `INPUT1` | read u16 | Player 2 controller word (identical bit layout). `$100004`/`$100006` reserved for `INPUT2`/`INPUT3`. |
| `$100010` | `IRQ_FLAGS` | read / write-1-clear | bit0 = vblank, bit1 = hblank (occurred since last clear) |
| `$100012` | `IRQ_ENABLE` | write | bit0 = vblank enable, bit1 = hblank enable |
| `$100014` | `FRAME` | read u16 | frame counter |
| `$100016` | `SAVE_COMMIT` | write u8 | poke nonzero once save RAM (`$200000+`) holds a coherent record; the host drains this and persists the save. Lets the host store whole records, not torn multi-byte writes. |
| `$100020` | `DMA_SRC` | write 3 bytes | 24-bit source address in CPU space |
| `$100024` | `DMA_DST` | write u16 | destination offset within the destination space |
| `$100028` | `DMA_LEN` | write u16 | byte length |
| `$10002A` | `DMA_MODE` | write u8 | bits0-1 space (0 VRAM, 1 OAM, 2 palette, 3 affine table), bit4 = constant fill |
| `$10002C` | `DMA_FILL` | write u16 | fill value (fill mode) |
| `$10002E` | `DMA_CTRL` | write u8 | bit0 = start the transfer |

## PPU port window (`$101000`)

| Address | Name | Access | Meaning |
| --- | --- | --- | --- |
| `$101000` | `VRAM_ADDR` | write 3 bytes | 17-bit VRAM pointer (lo, mid, hi) |
| `$101004` | `VRAM_DATA` | read/write | byte at `vram[ptr]`, pointer auto-increments (2-byte port so `STW` writes two bytes) |
| `$101008` | `PAL_INDEX` | write u8 | palette entry index (0-255) |
| `$10100A` | `PAL_DATA` | write u16 | RGB555 colour → `palette[index]`, index auto-increments |
| `$10100C` | `OAM_INDEX` | write u16 | byte offset into the 1 KiB OAM |
| `$10100E` | `OAM_DATA` | write u8 | byte → `oam[index++]` (128×8 descriptors, v0.2 layout) |
| `$101010..$101016` | `BG0_SX/SY`, `BG1_SX/SY` | write u16 | signed background scroll |
| `$101018` | `PPU_CTRL` | write u16 | bit0 BG0 enable, bit1 BG1 enable |
| `$10101A` | `PPU_SCANLINE` | read u16 | current scanline (0-261; vblank starts at 224) |
| `$10101C` | `AFFINE_CTRL` | write u16 | bit0 = affine enable, bit1 = which layer is affine (0 = BG0, 1 = BG1), bit2 reserved (page, single-buffered in v0.2), bit3 = transparent-outside (0 = repeat/toroidal, the default) |
| `$10101E` | `AFFINE_FIRST` | write u16 | first affine scanline: affine-table row 0 maps to this line |
| `$101020` | `AFFINE_LAST` | write u16 | last affine scanline (inclusive; informational in v0.2) |
| `$101022` | `AFFINE_MAPSZ` | write u8 | affine map size as log2(tiles per side): 6 = 64×64 (default), 7 = 128×128 |

OAM descriptor (8 bytes, little-endian, per `PPU.md`): X (s16),
Y (s16), tile (bits 0-10), attr (palette 0-3, size 4-5, hflip 6, vflip 7,
priority 8-10, enable 15).

### Affine (Mode-7) line table

The per-scanline affine parameters are too much data for register pokes, so they
arrive by DMA: set `DMA_MODE` space 3 and blast an `N×16`-byte table from CPU
memory. Each 16-byte row is four signed 32-bit little-endian values in **16.16
fixed point**: `startX, startY, dx, dy`. Row *i* drives scanline
`AFFINE_FIRST + i`: the PPU samples the layer's tile map starting at
(`startX`,`startY`), stepping by (`dx`,`dy`) per screen pixel. An affine DMA
clears the whole table first, so any scanline the table does not cover renders
transparent and the other layer shows through (a free horizon). See `PPU.md` for
the layer semantics.

## Audio / APU (`$102000`)

| Address | Name | Access | Meaning |
| --- | --- | --- | --- |
| `$102000` | `SQ0_PERIOD` | write u16 | square-0 period (freq = 48000 / 2·period) |
| `$102002` | `SQ0_VOL` | write u8 | square-0 volume 0–15 |
| `$102003` | `SQ0_CTRL` | write u8 | bit0 = enable |
| `$102004`–`$102007` | `SQ1_*` | write | square-1 period (u16) / vol / ctrl |
| `$102008` | `NOISE_PERIOD` | write u16 | noise clock period |
| `$10200A` | `NOISE_VOL` | write u8 | noise volume 0–15 |
| `$10200B` | `NOISE_CTRL` | write u8 | bit0 = enable |

The APU generates one deterministic mono buffer per `runFrame()` (48000 Hz, 800
samples); the host shell plays it via Web Audio. Square channels are 50% duty.
