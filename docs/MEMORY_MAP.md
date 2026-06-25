# CastlePalm Memory Map (flat 24-bit)

A flat, little-endian, byte-addressed 24-bit space (~16 MiB).

VRAM (128 KiB), OAM (1 KiB), and palette RAM (512 B) are **PPU-owned and not mapped
into CPU space** — reach them only through the PPU port window and the DMA channel
(see [PPU.md](PPU.md)).

## Map

| Range | Size | Region | Purpose |
| --- | ---: | --- | --- |
| `$000000–$00FFFF` | 64 KiB | **Work RAM** | Stack (descending `SP`), globals, game state, and DMA staging buffers (OAM lists, map columns built here then DMA'd to the PPU). Low, so reset/IRQ vectors and globals get short addresses. Word accesses even-aligned. |
| `$010000–$0FFFFF` | 960 KiB | reserved | Work-RAM growth without moving MMIO/ROM. |
| `$100000–$100FFF` | 4 KiB | **System / CPU MMIO** | Interrupt controller (vblank/hblank/DMA enables + write-1-to-clear flags), timers, the 16-bit controller input words (D-pad + A/B/X/Y + Start + Power), and DMA submission/control. 16-bit registers at even offsets. |
| `$101000–$101FFF` | 4 KiB | **PPU port window** | The PPU register block (see [MMIO.md](MMIO.md)). The **only** CPU path to graphics. |
| `$102000–$1FFFFF` | ~1 MiB | **APU + reserved** | APU register block at `$102000` (2 square + 1 noise; see [MMIO.md](MMIO.md)); the rest reserved. |
| `$200000–$207FFF` | 32 KiB | **Cartridge save RAM** | Battery/persistent storage. Uniform 24-bit pointer access, no banking. Word accesses even-aligned. |
| `$208000–$2FFFFF` | ~992 KiB | reserved | Save-RAM growth without moving ROM. |
| `$300000–$3FFFFF` | 1 MiB | **Cartridge ROM** | Executable code and read-only data (tile/map/palette sources). Reset + interrupt vectors at the ROM base `$300000`; boot entry `$300000`. |
| `$400000–$FFFFFF` | 12 MiB | reserved | ROM/expansion growth. No device decodes here. |

## Notes

- RAM low / ROM high keeps common data pointers and vectors short, and lets `SP`
  initialise near the top of Work RAM and grow down.
- Reserved gaps **fault** rather than alias, so adding hardware or growing a region
  never disturbs the established map.
