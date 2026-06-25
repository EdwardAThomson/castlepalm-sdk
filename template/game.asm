; CastlePalm — game template. Copy this to start a new cart.
;   node tools/build-cart.js template/game.asm mygame.cpc MYGAME
;   node tools/run.js template/game.asm 60 out.png
; See examples/hello.asm for a working sprite, and docs/ for the full machine.

; --- MMIO (see docs/MMIO.md) ---
INPUT     EQU $100000
VRAM_ADDR EQU $101000
VRAM_DATA EQU $101004
PAL_INDEX EQU $101008
PAL_DATA  EQU $10100A
OAM_INDEX EQU $10100C
OAM_DATA  EQU $10100E

; --- input bits ---
UP    EQU 1
DOWN  EQU 2
LEFT  EQU 4
RIGHT EQU 8
A     EQU 16
B     EQU 32
X     EQU 64
Y     EQU 128
START EQU 256

  ORG $300000
  DA start          ; reset vector
  DA 0              ; IRQ vectors (unused)
  DA 0
  DA 0

start:
  ; one-time setup: palettes, tiles, initial state.
  ; (see examples/hello.asm)

loop:
  ; per-frame: read INPUT, update state, write OAM / VRAM.

  WAIT              ; wait for the next frame
  BRA loop
