'use strict'
// CastlePalm CPU ISA v0 — concrete variable-length encoding (PROVISIONAL).
//
// Single source of truth for the assembler and the CPU core. Opcode-byte-first,
// single-pass: byte 0 (the opcode) fully determines the instruction and its total
// length via the operand kinds below. See cpu/ENCODING_V0.md and docs/ISA_DRAFT.md.
//
// Operand-kind byte sizes. 'regs' is one byte packing up to two 4-bit register
// fields (hi nibble = first operand, lo nibble = second); the assembler/core
// interpret the nibbles per-instruction. Multi-byte values are little-endian.
const KIND_BYTES = { regs: 1, imm8: 1, imm16: 2, addr24: 3, disp8: 1, disp16: 2 }

// [mnemonic, opcode, [operand kinds]]. Opcodes are unique and stable.
const TABLE = [
  ['NOP', 0x00, []],

  // --- data movement ---
  ['MOV.i', 0x01, ['regs', 'imm16']],   // MOV Rd,#imm16   (regs: Rd in hi nibble)
  ['MOV.b', 0x02, ['regs', 'imm8']],    // MOV Rd,#imm8
  ['MOV.r', 0x03, ['regs']],            // MOV Rd,Rs
  ['LDA', 0x04, ['regs', 'addr24']],    // LDA An,#imm24
  ['LDADDR', 0x05, ['regs']],           // LDADDR An,[Am]
  ['MOVA', 0x06, ['regs']],             // MOVA Ad,As

  // --- loads / stores: word + byte over the addressing-mode family ---
  ['LDW.ind', 0x10, ['regs']],          // LDW Rd,[An]
  ['LDW.dsp', 0x11, ['regs', 'disp8']], // LDW Rd,[An+#d8]
  ['LDW.idx', 0x12, ['regs', 'regs']],  // LDW Rd,[An+Rm]  (byte1 Rd|An, byte2 Rm)
  ['LDW.abs', 0x13, ['regs', 'addr24']],// LDW Rd,[abs24]
  ['LDB.ind', 0x14, ['regs']],
  ['LDB.dsp', 0x15, ['regs', 'disp8']],
  ['LDB.idx', 0x16, ['regs', 'regs']],
  ['LDB.abs', 0x17, ['regs', 'addr24']],
  ['STW.ind', 0x18, ['regs']],
  ['STW.dsp', 0x19, ['regs', 'disp8']],
  ['STW.idx', 0x1a, ['regs', 'regs']],
  ['STW.abs', 0x1b, ['regs', 'addr24']],
  ['STB.ind', 0x1c, ['regs']],
  ['STB.dsp', 0x1d, ['regs', 'disp8']],
  ['STB.idx', 0x1e, ['regs', 'regs']],
  ['STB.abs', 0x1f, ['regs', 'addr24']],

  // --- multiply / divide (Rd,Rs). MUL: 16x16 -> 32-bit, low word -> Rd, high word
  //     -> R(d+1 mod 8). DIV: 32-bit dividend R(d+1):Rd / Rs -> quotient -> Rd,
  //     remainder -> R(d+1). See cpu/core.js for flags + div-by-zero behaviour. ---
  ['MULU', 0x20, ['regs']],
  ['MULS', 0x21, ['regs']],
  ['DIVU', 0x22, ['regs']],
  ['DIVS', 0x23, ['regs']],

  // --- arithmetic (16-bit) ---
  ['ADD.r', 0x30, ['regs']],
  ['ADD.i', 0x31, ['regs', 'imm16']],
  ['SUB.r', 0x32, ['regs']],
  ['SUB.i', 0x33, ['regs', 'imm16']],
  ['ADC.r', 0x34, ['regs']],
  ['SBC.r', 0x35, ['regs']],
  ['CMP.r', 0x36, ['regs']],
  ['CMP.i', 0x37, ['regs', 'imm16']],
  ['NEG', 0x38, ['regs']],

  // --- logic ---
  ['AND.r', 0x39, ['regs']],
  ['AND.i', 0x3a, ['regs', 'imm16']],
  ['OR.r', 0x3b, ['regs']],
  ['OR.i', 0x3c, ['regs', 'imm16']],
  ['XOR.r', 0x3d, ['regs']],
  ['XOR.i', 0x3e, ['regs', 'imm16']],
  ['NOT', 0x3f, ['regs']],
  ['BIT.r', 0x40, ['regs']],
  ['TST', 0x41, ['regs']],

  // --- shifts ---
  ['SHL.i', 0x42, ['regs', 'imm8']],
  ['SHR.i', 0x43, ['regs', 'imm8']],
  ['SAR.i', 0x44, ['regs', 'imm8']],
  ['SHL.r', 0x45, ['regs']],
  ['SHR.r', 0x46, ['regs']],
  ['SAR.r', 0x47, ['regs']],

  // --- address arithmetic (24-bit, address regs) ---
  ['ADDA.i', 0x48, ['regs', 'imm16']],  // ADD An,#simm16
  ['ADDA.r', 0x49, ['regs']],           // ADD An,Rm
  ['INCA', 0x4a, ['regs']],
  ['DECA', 0x4b, ['regs']],
  ['CMPA', 0x4c, ['regs']],

  // --- control flow (Bcc are signed + unsigned; disp8 relative) ---
  ['BRA', 0x50, ['disp16']],
  ['BEQ', 0x51, ['disp8']], ['BNE', 0x52, ['disp8']],
  ['BCS', 0x53, ['disp8']], ['BCC', 0x54, ['disp8']],
  ['BMI', 0x55, ['disp8']], ['BPL', 0x56, ['disp8']],
  ['BVS', 0x57, ['disp8']], ['BVC', 0x58, ['disp8']],
  ['BLT', 0x59, ['disp8']], ['BGE', 0x5a, ['disp8']],
  ['BGT', 0x5b, ['disp8']], ['BLE', 0x5c, ['disp8']],
  ['BHI', 0x5d, ['disp8']], ['BLS', 0x5e, ['disp8']],
  ['JMP.abs', 0x60, ['addr24']],
  ['JMP.ind', 0x61, ['regs']],          // JMP [An]
  ['CALL.abs', 0x62, ['addr24']],
  ['CALL.ind', 0x63, ['regs']],         // CALL [An]
  ['RET', 0x64, []],

  // --- stack / system ---
  ['PUSH', 0x70, ['regs']],             // PUSH Rn (word)
  ['POP', 0x71, ['regs']],
  ['PUSHA', 0x72, ['regs']],            // PUSHA An (24-bit, 4-byte slot)
  ['POPA', 0x73, ['regs']],
  ['IRET', 0x74, []],
  ['HALT', 0x75, []],
  ['WAIT', 0x76, []],                   // wait for next vblank
  ['EI', 0x77, []], ['DI', 0x78, []],   // enable / disable interrupts
]

const BYNAME = new Map(TABLE.map(([n, op, k]) => [n, { name: n, opcode: op, kinds: k }]))
const BYOP = new Map(TABLE.map(([n, op, k]) => [op, { name: n, opcode: op, kinds: k }]))

function instr(name) { const e = BYNAME.get(name); if (!e) throw new Error('unknown instruction ' + name); return e }
function lengthOf(opcode) {
  const e = BYOP.get(opcode); if (!e) throw new Error('unknown opcode 0x' + opcode.toString(16))
  return 1 + e.kinds.reduce((s, k) => s + KIND_BYTES[k], 0)
}

// encode(name, values[]) -> Uint8Array. values align with the instruction's
// operand kinds; a 'regs' value is the packed byte. Multi-byte values little-endian.
function encode(name, values = []) {
  const e = instr(name), out = [e.opcode]
  if (values.length !== e.kinds.length) throw new Error(`${name}: expected ${e.kinds.length} operands, got ${values.length}`)
  e.kinds.forEach((k, i) => { let v = values[i] | 0; for (let b = 0; b < KIND_BYTES[k]; b++) { out.push(v & 0xff); v >>>= 8 } })
  return Uint8Array.from(out)
}

// decode(bytes, off) -> { name, opcode, values, length }.
function decode(bytes, off = 0) {
  const op = bytes[off], e = BYOP.get(op)
  if (!e) throw new Error('unknown opcode 0x' + (op || 0).toString(16) + ' at ' + off)
  let p = off + 1; const values = []
  for (const k of e.kinds) {
    const n = KIND_BYTES[k]; let v = 0
    for (let b = 0; b < n; b++) v |= bytes[p++] << (8 * b)
    values.push(v >>> 0)
  }
  return { name: e.name, opcode: op, values, length: p - off }
}

// pack two register numbers into a 'regs' byte (hi = first, lo = second).
const packRegs = (a = 0, b = 0) => ((a & 0xf) << 4) | (b & 0xf)
const unpackRegs = byte => [(byte >> 4) & 0xf, byte & 0xf]

// Interrupt / reset vectors: a table of 24-bit addresses at the ROM base.
const VECTOR_BASE = 0x300000     // matches docs/MEMORY_MAP.md ROM base
const VECTOR_BYTES = 3
const VECTORS = ['reset', 'vblank', 'hblank', 'dmaDone']  // entry i at VECTOR_BASE + i*3
const vectorAddr = name => {
  const i = VECTORS.indexOf(name); if (i < 0) throw new Error('unknown vector ' + name)
  return VECTOR_BASE + i * VECTOR_BYTES
}

module.exports = {
  KIND_BYTES, TABLE, BYNAME, BYOP, instr, lengthOf, encode, decode,
  packRegs, unpackRegs, VECTOR_BASE, VECTOR_BYTES, VECTORS, vectorAddr,
}
