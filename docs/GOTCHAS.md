# CastlePalm Assembly — Gotchas (read this first)

A handful of things bite almost everyone writing their first CastlePalm cart.
None are hard once you know them.

## 1. Immediates need `#`
A number on its own is an address/register context, not a literal. Use `#`:

```
MOV R0, #5        ; load the value 5
MOV R0, 5         ; WRONG (not a literal)
```

## 2. Memory displacement needs `#` too: `[An+#disp]`
To read at "address register + offset", the offset is an immediate, so it needs `#`:

```
STW R0, [A1+#2]   ; store at A1 + 2
STW R0, [A1+2]    ; WRONG: '2' is parsed as an index register -> error
```

## 3. Conditional branches reach only ±127 bytes
`Bcc` (BEQ, BNE, BLT, …) are signed 8-bit relative — about ±127 bytes. If the
target is too far you'll get a "branch out of range" error. Fix it with a short
local hop plus an unconditional `BRA` (which has far more range):

```
  CMP R0, #0
  BNE near_skip      ; was: BNE far_label  (out of range)
  BRA far_label
near_skip:
  ...
```

## 4. Multiply/divide use a register pair
The CPU has `MULU`/`MULS` and `DIVU`/`DIVS`, but 16-bit registers can't hold a 32-bit
result, so they use an implicit pair: `MUL Rd, Rs` writes the low word to `Rd` and the
high word to `R(d+1 mod 8)`. `DIV Rd, Rs` reads a 32-bit dividend from `R(d+1):Rd` and
writes quotient→`Rd`, remainder→`R(d+1)`. So `MUL R0,Rs` clobbers `R1`, and you must
set up `R(d+1)` (often to 0) before a `DIV`. Divide-by-zero sets `V` and does not trap.

For a power-of-two factor a shift is still smaller and faster than a full `MUL` — a
16-wide grid makes the index a shift, not a multiply:

```
; cell index = cy*16 + cx   -> (cy << 4) + cx
MOV R0, R_cy
SHL R0, #4
ADD R0, R_cx
```

## 5. `SHR` is logical — use `SAR` for signed values
`SHL` and `SHR` are *logical* shifts (they shift in zeros). For a sign-preserving
(arithmetic) right shift — e.g. dividing a signed number by a power of two — use
`SAR`. `SHR`-ing a negative value gives the wrong result; reach for `SAR` instead.

## 6. Bytes vs words
`LDB`/`STB` move 8 bits, `LDW`/`STW` move 16 bits. Match the width to your data
(a 16-bit coordinate needs `STW`, a single tile byte needs `STB`).

## 7. The cartridge header is the vector table
Your code starts at `ORG $300000`, and the first four `DA` entries are the vector
table: reset first, then three IRQ vectors. The CPU jumps to the reset vector on
power-up:

```
  ORG $300000
  DA start    ; reset
  DA 0        ; IRQ vectors (0 = unused)
  DA 0
  DA 0
start:
  ...
```

See `examples/hello.asm` for the smallest complete program, and `docs/CPU.md` /
`docs/MMIO.md` for the full instruction set and register map.
