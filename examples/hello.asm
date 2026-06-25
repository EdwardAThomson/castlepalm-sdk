; CastlePalm — Hello, World
; The smallest useful cart: set one palette colour, build one tile, and push a
; sprite around the screen with the D-pad. Read this top-to-bottom to learn the
; basic shape of a CastlePalm program. See docs/CPU.md for the assembly gotchas.

; --- MMIO registers (full list in docs/MMIO.md) ---
INPUT     EQU $100000     ; controller 1 (read): a 16-bit bitmask of held buttons
VRAM_ADDR EQU $101000     ; 24-bit VRAM write pointer (write 3 bytes: lo, mid, hi)
VRAM_DATA EQU $101004     ; write bytes here; VRAM_ADDR auto-increments
PAL_INDEX EQU $101008     ; which palette entry to write next
PAL_DATA  EQU $10100A     ; 15-bit colour for that entry
OAM_INDEX EQU $10100C     ; which sprite (0..127) to write next
OAM_DATA  EQU $10100E     ; write 8 bytes per sprite: X, Y, tile, attr (16-bit each)

; --- input bits (see docs/MMIO.md) ---
UP    EQU 1
DOWN  EQU 2
LEFT  EQU 4
RIGHT EQU 8

SPEED EQU 2               ; pixels moved per frame

; --- RAM work area (low RAM is free for your variables) ---
spx EQU $000100           ; sprite X
spy EQU $000102           ; sprite Y

  ORG $300000             ; cartridge code lives at $300000
  DA start                ; reset vector  -> where the CPU starts
  DA 0                    ; (three IRQ vectors, unused here)
  DA 0
  DA 0

start:
  ; palette entry 1 = white (15-bit colour $7FFF)
  MOV R0, #1
  STB R0, [PAL_INDEX]
  MOV R0, #$7FFF
  STW R0, [PAL_DATA]

  ; build tile 1 = a solid 8x8 block of colour 1.
  ; tiles are 4bpp = 32 bytes each, so tile 1 starts at VRAM byte 1*32 = $20.
  ; each byte holds two pixels; $11 means "colour 1, colour 1".
  MOV R0, #$20
  STB R0, [VRAM_ADDR]     ; pointer lo
  MOV R0, #0
  STB R0, [VRAM_ADDR+1]   ; pointer mid
  STB R0, [VRAM_ADDR+2]   ; pointer hi
  MOV R1, #32
  MOV R2, #$11
fill:
  STB R2, [VRAM_DATA]
  SUB R1, #1
  BNE fill

  ; place the sprite near the centre of the 320x224 screen
  MOV R0, #156
  STW R0, [spx]
  MOV R0, #108
  STW R0, [spy]

loop:
  LDW R0, [INPUT]         ; read held buttons once

  MOV R1, R0
  AND R1, #UP
  BEQ no_up
  LDW R2, [spy]
  SUB R2, #SPEED
  STW R2, [spy]
no_up:
  MOV R1, R0
  AND R1, #DOWN
  BEQ no_down
  LDW R2, [spy]
  ADD R2, #SPEED
  STW R2, [spy]
no_down:
  MOV R1, R0
  AND R1, #LEFT
  BEQ no_left
  LDW R2, [spx]
  SUB R2, #SPEED
  STW R2, [spx]
no_left:
  MOV R1, R0
  AND R1, #RIGHT
  BEQ no_right
  LDW R2, [spx]
  ADD R2, #SPEED
  STW R2, [spx]
no_right:

  ; draw sprite 0 = (spx, spy), tile 1, enabled, 8x8, palette 0
  MOV R0, #0
  STW R0, [OAM_INDEX]     ; start writing at sprite 0
  LDW R4, [spx]
  STB R4, [OAM_DATA]      ; X lo
  MOV R0, R4
  SHR R0, #8
  STB R0, [OAM_DATA]      ; X hi
  LDW R5, [spy]
  STB R5, [OAM_DATA]      ; Y lo
  MOV R0, R5
  SHR R0, #8
  STB R0, [OAM_DATA]      ; Y hi
  MOV R0, #1
  STB R0, [OAM_DATA]      ; tile lo (tile 1)
  MOV R0, #0
  STB R0, [OAM_DATA]      ; tile hi
  STB R0, [OAM_DATA]      ; attr lo (0 = 8x8, palette 0)
  MOV R0, #$80
  STB R0, [OAM_DATA]      ; attr hi ($80 = sprite enabled)

  WAIT                    ; sleep until the next frame
  BRA loop
