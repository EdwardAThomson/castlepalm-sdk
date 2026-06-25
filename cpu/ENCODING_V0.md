# CastlePalm Opcode Encoding

The concrete byte-level encoding behind [../docs/CPU.md](../docs/CPU.md).
**`cpu/isa.js` is the authoritative source** — this document describes it.

## Scheme

Variable-length, **opcode-byte-first, single-pass**: byte 0 is the opcode and
fully determines the instruction and its total length. Operands follow, each a
whole number of bytes; multi-byte values are **little-endian**.

| Operand kind | Bytes | Meaning |
| --- | ---: | --- |
| `regs` | 1 | up to two 4-bit register fields (hi nibble = first operand, lo = second) |
| `imm8` | 1 | 8-bit immediate |
| `imm16` | 2 | 16-bit immediate |
| `addr24` | 3 | 24-bit absolute address / `LDA` immediate |
| `disp8` | 1 | signed 8-bit branch/index displacement |
| `disp16` | 2 | signed 16-bit branch displacement |

`length = 1 + Σ(operand kind bytes)`. A decoder reads the opcode, looks up its
operand kinds, and advances exactly that far — no second pass, no prefixes.

## Opcode ranges

| Range | Group |
| --- | --- |
| `$00` | NOP |
| `$01–$06` | data movement (MOV, LDA, LDADDR, MOVA) |
| `$10–$1F` | loads / stores (LDW/LDB/STW/STB × ind/dsp/idx/abs) |
| `$30–$41` | arithmetic + logic |
| `$42–$47` | shifts |
| `$48–$4C` | address arithmetic (24-bit) |
| `$50–$64` | control flow (BRA, Bcc, JMP, CALL, RET) |
| `$70–$78` | stack + system (PUSH/POP, IRET, HALT, WAIT, EI/DI) |

The full table (mnemonic → opcode → operand kinds) lives in `cpu/isa.js`; round-trip
encode/decode and uniqueness are covered by `tests/isa.test.js`.

## Vectors

A table of 24-bit addresses at the ROM base (`docs/MEMORY_MAP.md`):

| Vector | Address |
| --- | --- |
| reset | `$300000` |
| vblank | `$300003` |
| hblank | `$300006` |
| dmaDone | `$300009` |

Boot jumps through the reset vector; the interrupt controller dispatches the rest.
