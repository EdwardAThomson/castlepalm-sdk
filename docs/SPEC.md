# CastlePalm Platform Specification

A single-page reference for the CastlePalm machine. The detailed contracts live in
the per-subsystem docs linked below; start with [GOTCHAS.md](GOTCHAS.md) before
writing code.

## CPU

- Flat **24-bit little-endian** address space (~16 MiB); one uniform pointer model.
- Registers: `R0–R7` (16-bit general purpose), `A0–A3` (24-bit address), `PC`/`SP`
  (24-bit), status flags (`Z/N/C/V`). General arithmetic is 16-bit.
- ISA: **variable-length, opcode-byte-first**, explicit flags, `CALL`/`RET` via the
  stack. **No hardware multiply or divide** — use shifts and adds (see GOTCHAS).
- Calling convention: `R0–R3` caller-saved (args/results), `R4–R7` callee-saved;
  `A0–A1` caller-saved, `A2–A3` callee-saved.
- Detail: [CPU.md](CPU.md), [../cpu/ENCODING_V0.md](../cpu/ENCODING_V0.md).

## Memory map (flat 24-bit)

| Base | Region |
| --- | --- |
| `$000000` | Work RAM (64 KiB) |
| `$100000` | System / CPU MMIO (IRQ, timers, input, DMA) |
| `$101000` | PPU port window |
| `$102000` | APU registers |
| `$200000` | Cartridge save RAM (32 KiB) |
| `$300000` | Cartridge ROM (1 MiB) — reset + IRQ vectors at base |

Detail: [MEMORY_MAP.md](MEMORY_MAP.md), [MMIO.md](MMIO.md).

## Graphics (PPU)

- **320×224**, `8×8` 4 bpp tiles, 256-colour palette (16 banks × 16, RGB555),
  two `64×64` wrapping background layers, 128 sprites (32 per line; sizes
  8/16/32/64), 128 KiB VRAM (reached via ports + DMA).
- Per-scanline rendering with scanline-latched scroll; vblank + hblank IRQs and a
  `PPU_SCANLINE` counter (512 ticks/line × 262 lines; visible 0–223, vblank 224–261).
- Detail: [PPU.md](PPU.md).

## Audio (APU)

- 2 square + 1 noise channels, MMIO at `$102000`, deterministic per-frame samples
  (48 kHz). Detail: [MMIO.md](MMIO.md) (Audio section).

## Input

- Two **16-bit controller words**: `INPUT0` at `$100000` (player 1) and `INPUT1`
  at `$100002` (player 2), identical bit layout: Up=1, Down=2, Left=4, Right=8,
  A=16, B=32, X=64, Y=128, Start=256, Power=512.

## Cartridge format — `CPLM`

- A 32-byte header (magic `CPLM`, version, flags, 16-char title, 24-bit load base,
  ROM length) followed by the ROM image. The assembler in this SDK writes it for
  you; see [../cpu/cart.js](../cpu/cart.js).

## Determinism

Execution, rendering, and audio are **deterministic given inputs**, and the core is
headlessly testable. A host shell handles only presentation and input mapping; the
core sees a framebuffer, an audio buffer, and the input registers. That's why
`tools/run.js` can build a cart and screenshot an exact frame.
