# CastlePalm CPU & Instruction Set

The reference for the CPU as the assembler in this SDK implements it. Read
[GOTCHAS.md](GOTCHAS.md) alongside this — it covers the things that bite first.

## Registers

- **`R0`–`R7`** — eight 16-bit general-purpose registers. General arithmetic is 16-bit.
- **`A0`–`A3`** — four 24-bit address registers (the flat pointer model).
- **`PC`** (24-bit), **`SP`** (24-bit, descending), and status flags **`Z N C V`**.

Conventionally `R0–R3` / `A0–A1` are caller-saved (use them for args and scratch),
`R4–R7` / `A2–A3` are callee-saved (preserve them across `CALL`).

## Encoding

Variable-length, **opcode-byte-first**: the first byte determines the instruction's
length and operand layout. Code is byte-aligned; 16-bit data is even-aligned.
Bit-level details are in [../cpu/ENCODING_V0.md](../cpu/ENCODING_V0.md).

## Addressing modes

| Form | Meaning |
| --- | --- |
| `Rn`, `An` | register direct |
| `#imm` | immediate literal (**always needs `#`** — see GOTCHAS) |
| `[An]` | address-register indirect |
| `[An+#disp]` | indirect + signed displacement (**the `#` is required**) |
| `[An+Rm]` | indirect + register index (`array[i]`) |
| `[abs]` | absolute address, e.g. `LDW R0, [INPUT]` |

Load a full 24-bit address into an address register with `LDA An, #addr`
(e.g. `LDA A0, #mytable`).

## Instruction set

**Move / load / store**
`MOV` · `MOVA` · `LDA An,#addr` · `LDB`/`LDW` (load byte/word) · `STB`/`STW` (store byte/word)

**Arithmetic (16-bit, on `Rn`)**
`ADD` · `SUB` · `ADC` · `SBC` (multi-word carry) · `CMP` · `NEG`
`MULU`/`MULS` · `DIVU`/`DIVS`
&nbsp;&nbsp;*(`MUL` is 16×16→32: low word → `Rd`, high word → `R(d+1 mod 8)`. `DIV` is
32/16→16: dividend `R(d+1):Rd` → quotient `Rd`, remainder `R(d+1)`; divide-by-zero
sets `V` with no trap. MUL costs 8 cycles, DIV 16.)*

**Address registers (24-bit)**
`INC`/`DEC` (a.k.a. `INCA`/`DECA`) · `ADD An,Rm` · `CMPA` · `LDA`

**Logic**
`AND` · `OR` · `XOR` · `NOT` · `TST` · `BIT`

**Shifts** (by `#imm` or by register)
`SHL` · `SHR` (logical) · `SAR` (arithmetic / sign-preserving)

**Control flow**
`BRA` (unconditional) · conditional `Bcc`: `BEQ BNE BLT BGE BGT BLE BHI BLS BCC BCS BMI BPL BVC BVS`
&nbsp;&nbsp;*(`Bcc` reach is ±127 bytes — see GOTCHAS)* · `JMP` · `CALL` · `RET` · `IRET`

**Stack**
`PUSH`/`POP` (`Rn`) · `PUSHA`/`POPA` (`An`)

**System**
`WAIT` (sleep until the next frame / vblank) · `HALT` · `NOP` · `DI`/`EI` (interrupt enable)

## Reset & interrupts

Code starts at `ORG $300000`. The first four `DA` words are the vector table —
reset first, then three IRQ vectors. The CPU jumps to the reset vector on power-up.
`WAIT` is the normal way to pace a game to 60 fps without a busy loop.
