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
| `$10002A` | `DMA_MODE` | write u8 | bits0-1 space (0 VRAM, 1 OAM, 2 palette), bit4 = constant fill |
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

OAM descriptor (8 bytes, little-endian, per `PPU.md`): X (s16),
Y (s16), tile (bits 0-10), attr (palette 0-3, size 4-5, hflip 6, vflip 7,
priority 8-10, enable 15).

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
