(function(){
var __mods={},__cache={};
function __resolve(from,req){
  if(req.charAt(0)!=="."){return req.replace(/\.js$/,"");}
  var dir=from.indexOf("/")>=0?from.slice(0,from.lastIndexOf("/")):"";
  var parts=dir?dir.split("/"):[];
  req.replace(/\.js$/,"").split("/").forEach(function(p){
    if(p==="."){}else if(p===".."){parts.pop();}else{parts.push(p);}
  });
  return parts.join("/");
}
function __require(id){
  if(__cache[id]){return __cache[id].exports;}
  var m={exports:{}};__cache[id]=m;
  __mods[id](m,m.exports,function(r){return __require(__resolve(id,r));});
  return m.exports;
}
__mods["cpu/isa"]=function(module,exports,require){
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

};
__mods["cpu/asm"]=function(module,exports,require){
'use strict'
// CastlePalm assembler v0 — text .asm -> bytes, lowering through cpu/isa.js.
//
// Two-pass: pass A parses + classifies each instruction to a concrete isa variant
// (so sizes are known); pass B assigns addresses and resolves labels; pass C emits.
// Provisional, mirrors the docs/ISA_DRAFT.md direction. Syntax is documented in
// cpu/ENCODING_V0.md / examples; deliberately small and regular.

const isa = require('./isa.js')
const { packRegs } = isa

const reg = t => { const m = /^[Rr]([0-7])$/.exec(t); if (!m) throw new Error('expected R0-R7, got "' + t + '"'); return +m[1] }
const aregOrNull = t => { const m = /^[Aa]([0-3])$/.exec(t); return m ? +m[1] : null }
const areg = t => { const a = aregOrNull(t); if (a == null) throw new Error('expected A0-A3, got "' + t + '"'); return a }

function term(t, symbols) {
  t = t.trim()
  if (/^\$[0-9a-fA-F]+$/.test(t)) return parseInt(t.slice(1), 16)
  if (/^0x[0-9a-fA-F]+$/i.test(t)) return parseInt(t, 16)
  if (/^%[01]+$/.test(t)) return parseInt(t.slice(1), 2)
  if (/^-?\d+$/.test(t)) return parseInt(t, 10)
  if (/^'.'$/.test(t)) return t.charCodeAt(1)
  if (symbols && symbols.has(t)) return symbols.get(t)
  throw new Error('unknown symbol "' + t + '"')
}
function resolve(expr, symbols) {
  let total = 0, m; const re = /([+-])?\s*([^+\-\s][^+-]*)/g
  while ((m = re.exec(expr))) total += (m[1] === '-' ? -1 : 1) * term(m[2], symbols)
  return total
}
const isLiteral = expr => { try { resolve(expr, null); return true } catch { return false } }

// split operands on top-level commas (brackets contain no commas in this ISA)
const splitOps = s => s.trim() ? s.split(',').map(x => x.trim()) : []

function parseMem(s) {
  if (!/^\[.*\]$/.test(s)) return null
  const inner = s.slice(1, -1).replace(/\s+/g, '')
  if (inner.includes('+')) {
    const i = inner.indexOf('+')
    const l = inner.slice(0, i), r = inner.slice(i + 1)
    const a = aregOrNull(l)
    if (a != null) {                                  // [An+#disp] or [An+Rm]
      if (r.startsWith('#')) return { mode: 'dsp', a, disp: r.slice(1) }
      return { mode: 'idx', a, m: reg(r) }
    }
    return { mode: 'abs', addr: inner }               // [label+offset] absolute
  }
  const a = aregOrNull(inner)
  return a != null ? { mode: 'ind', a } : { mode: 'abs', addr: inner }
}

const BCC = new Set(['BEQ', 'BNE', 'BCS', 'BCC', 'BMI', 'BPL', 'BVS', 'BVC', 'BLT', 'BGE', 'BGT', 'BLE', 'BHI', 'BLS'])
const NULLARY = new Set(['NOP', 'RET', 'IRET', 'HALT', 'WAIT', 'EI', 'DI'])
const ALU = new Set(['ADD', 'SUB', 'CMP', 'AND', 'OR', 'XOR'])

// classify(mnem, ops) -> { isaName, build(symbols, addr) -> values[] }
function classify(mnem, ops) {
  const mk = (isaName, build) => ({ isaName, build })
  if (NULLARY.has(mnem)) return mk(mnem, () => [])

  if (mnem === 'MOV') {
    const d = reg(ops[0])
    if (ops[1].startsWith('#')) {
      const imm = ops[1].slice(1)
      const small = isLiteral(imm) && resolve(imm, null) >= 0 && resolve(imm, null) < 256
      return small ? mk('MOV.b', s => [packRegs(d, 0), resolve(imm, s) & 0xff])
                   : mk('MOV.i', s => [packRegs(d, 0), resolve(imm, s) & 0xffff])
    }
    return mk('MOV.r', () => [packRegs(d, reg(ops[1]))])
  }
  if (mnem === 'LDA') { const a = areg(ops[0]); const e = ops[1].replace(/^#/, ''); return mk('LDA', s => [packRegs(a, 0), resolve(e, s) & 0xffffff]) }
  if (mnem === 'LDADDR') { const a = areg(ops[0]); const m = parseMem(ops[1]); return mk('LDADDR', () => [packRegs(a, m.a)]) }
  if (mnem === 'MOVA') return mk('MOVA', () => [packRegs(areg(ops[0]), areg(ops[1]))])

  if (['LDW', 'LDB', 'STW', 'STB'].includes(mnem)) {
    const r = reg(ops[0]), m = parseMem(ops[1])
    if (!m) throw new Error(mnem + ' needs a [memory] operand')
    if (m.mode === 'ind') return mk(`${mnem}.ind`, () => [packRegs(r, m.a)])
    if (m.mode === 'dsp') return mk(`${mnem}.dsp`, s => [packRegs(r, m.a), resolve(m.disp, s) & 0xff])
    if (m.mode === 'idx') return mk(`${mnem}.idx`, () => [packRegs(r, m.a), packRegs(m.m, 0)])
    return mk(`${mnem}.abs`, s => [packRegs(r, 0), resolve(m.addr, s) & 0xffffff])
  }

  if (ALU.has(mnem)) {
    const dA = aregOrNull(ops[0])
    if (dA != null) { // address arithmetic
      if (mnem === 'ADD') return ops[1].startsWith('#')
        ? mk('ADDA.i', s => [packRegs(dA, 0), resolve(ops[1].slice(1), s) & 0xffff])
        : mk('ADDA.r', () => [packRegs(dA, reg(ops[1]))])
      if (mnem === 'CMP') return mk('CMPA', () => [packRegs(dA, areg(ops[1]))])
      throw new Error(mnem + ' not valid on address registers')
    }
    const d = reg(ops[0])
    return ops[1].startsWith('#')
      ? mk(`${mnem}.i`, s => [packRegs(d, 0), resolve(ops[1].slice(1), s) & 0xffff])
      : mk(`${mnem}.r`, () => [packRegs(d, reg(ops[1]))])
  }
  if (mnem === 'ADC' || mnem === 'SBC' || mnem === 'BIT') return mk(`${mnem}.r`, () => [packRegs(reg(ops[0]), reg(ops[1]))])
  if (mnem === 'NEG' || mnem === 'NOT' || mnem === 'TST') return mk(mnem, () => [packRegs(reg(ops[0]), 0)])
  if (['SHL', 'SHR', 'SAR'].includes(mnem)) {
    const d = reg(ops[0])
    return ops[1].startsWith('#')
      ? mk(`${mnem}.i`, s => [packRegs(d, 0), resolve(ops[1].slice(1), s) & 0xff])
      : mk(`${mnem}.r`, () => [packRegs(d, reg(ops[1]))])
  }
  if (mnem === 'INC' || mnem === 'INCA') return mk('INCA', () => [packRegs(areg(ops[0]), 0)])
  if (mnem === 'DEC' || mnem === 'DECA') return mk('DECA', () => [packRegs(areg(ops[0]), 0)])

  if (mnem === 'BRA') return mk('BRA', (s, addr) => [(resolve(ops[0], s) - (addr + 3)) & 0xffff])
  if (BCC.has(mnem)) return mk(mnem, (s, addr) => {
    const d = resolve(ops[0], s) - (addr + 2)
    if (d < -128 || d > 127) throw new Error(`${mnem} target out of range (${d}); use BRA`)
    return [d & 0xff]
  })
  if (mnem === 'JMP' || mnem === 'CALL') {
    const m = parseMem(ops[0])
    if (m && m.mode === 'ind') return mk(`${mnem}.ind`, () => [packRegs(m.a, 0)])
    return mk(`${mnem}.abs`, s => [resolve(ops[0], s) & 0xffffff])
  }
  if (mnem === 'PUSH' || mnem === 'POP') return mk(mnem, () => [packRegs(reg(ops[0]), 0)])
  if (mnem === 'PUSHA' || mnem === 'POPA') return mk(mnem, () => [packRegs(areg(ops[0]), 0)])

  throw new Error('unknown mnemonic ' + mnem)
}

function assemble(source, { origin = 0x300000 } = {}) {
  const symbols = new Map()
  const labelLine = new Map()    // label -> first-definition line (duplicate detection)
  const records = []             // {type, ...}
  const lines = source.split('\n')
  const errors = []
  const err = (line, msg) => errors.push({ line, msg, src: (lines[line - 1] || '').trim() })

  lines.forEach((raw, i) => {
    const ln = i + 1
    let line = raw.replace(/;.*$/, '').trim()
    if (!line) return
    const lm = /^([A-Za-z_.][\w.]*):\s*(.*)$/.exec(line)
    if (lm) {
      const name = lm[1]
      if (labelLine.has(name)) err(ln, `duplicate label "${name}" (first defined on line ${labelLine.get(name)})`)
      else { labelLine.set(name, ln); records.push({ type: 'label', name, line: ln }) }
      line = lm[2].trim(); if (!line) return
    }
    const parts = line.split(/\s+/)
    if (parts[1] === 'EQU') {
      try { symbols.set(parts[0], resolve(parts.slice(2).join(' '), symbols)) } catch (e) { err(ln, e.message) }
      return
    }
    const mnem = parts[0].toUpperCase()
    const rest = line.slice(parts[0].length).trim()
    try {
      if (mnem === 'ORG') { records.push({ type: 'org', addr: resolve(rest, symbols), line: ln }); return }
      if (mnem === 'DB' || mnem === 'DW' || mnem === 'DA') {
        const width = mnem === 'DB' ? 1 : mnem === 'DW' ? 2 : 3
        const items = splitOps(rest)
        records.push({ type: 'data', width, items, size: items.length * width, line: ln })
        return
      }
      const { isaName, build } = classify(mnem, splitOps(rest))
      records.push({ type: 'instr', isaName, build, size: isa.lengthOf(isa.instr(isaName).opcode), line: ln })
    } catch (e) { err(ln, e.message) }   // skip the bad line; keep collecting
  })

  // pass B: addresses + labels. lo is the lowest emitted address (no leading gap).
  let addr = origin, lo = Infinity, hi = origin
  for (const r of records) {
    if (r.type === 'org') { addr = r.addr; continue }
    if (r.type === 'label') { symbols.set(r.name, addr); continue }
    r.addr = addr; addr += r.size
    if (r.addr < lo) lo = r.addr
    if (addr > hi) hi = addr
  }
  if (lo === Infinity) lo = origin

  // pass C: emit (resolve errors collected, not thrown)
  const mem = new Map()
  const lineMap = new Map()      // address -> source line
  for (const r of records) {
    try {
      if (r.type === 'instr') {
        isa.encode(r.isaName, r.build(symbols, r.addr)).forEach((b, k) => mem.set(r.addr + k, b))
        lineMap.set(r.addr, r.line)
      } else if (r.type === 'data') {
        let p = r.addr
        for (const it of r.items) { let v = resolve(it, symbols); for (let b = 0; b < r.width; b++) { mem.set(p++, v & 0xff); v >>= 8 } }
        lineMap.set(r.addr, r.line)
      }
    } catch (e) { err(r.line, e.message) }
  }

  if (errors.length) {
    const body = errors.sort((a, b) => a.line - b.line)
      .map(e => `  line ${e.line}: ${e.msg}\n    > ${e.src}`).join('\n')
    throw new Error(`assembly failed (${errors.length} error${errors.length > 1 ? 's' : ''}):\n${body}`)
  }

  const image = new Uint8Array(Math.max(0, hi - lo))
  for (const [a, b] of mem) image[a - lo] = b
  const lineAddrs = new Map()    // source line -> first address (breakpoints by line)
  for (const [a, l] of lineMap) if (!lineAddrs.has(l)) lineAddrs.set(l, a)
  return { origin: lo, size: image.length, image, symbols, lineMap, lineAddrs }
}

module.exports = { assemble, resolve }

};
__mods["cpu/core"]=function(module,exports,require){
'use strict'
// CastlePalm CPU core v0 — deterministic fetch/decode/execute for Candidate A.
//
// Flat 24-bit little-endian bus with the docs/MEMORY_MAP.md regions. MMIO and the PPU
// port window are dispatched to a pluggable bus object (wired to the PPU + input
// register later); unmapped reads return 0, ROM writes are ignored. Provisional,
// no cycle table yet (step() counts 1 per instruction).

const isa = require('./isa.js')
const { unpackRegs, VECTOR_BASE, vectorAddr } = isa

const s8 = v => (v << 24) >> 24
const s16 = v => (v << 16) >> 16
const m16 = v => v & 0xffff
const m24 = v => v & 0xffffff

// status-register bit positions (for interrupt save/restore)
const FZ = 1, FN = 2, FC = 4, FV = 8, FI = 16

class CastlePalmCPU {
  constructor({ rom = new Uint8Array(0), romBase = 0x300000, mmio = null } = {}) {
    this.rom = rom; this.romBase = romBase
    this.mmio = mmio                       // { read(addr)->byte, write(addr,byte) }
    this.ram = new Uint8Array(0x100000)    // $000000-$0FFFFF work RAM (+reserved)
    this.save = new Uint8Array(0x8000)     // $200000-$207FFF
    this.R = new Uint16Array(8)
    this.A = [0, 0, 0, 0]                   // 24-bit address registers
    this.F = { z: false, n: false, c: false, v: false }
    this.reset()
  }

  reset() {
    this.PC = this.read24(VECTOR_BASE)      // reset vector
    this.SP = 0x00ff00
    this.A = [0, 0, 0, 0]
    this.R.fill(0)
    this.F = { z: false, n: false, c: false, v: false }
    this.ie = false; this.halted = false; this.waiting = false
    this.steps = 0
  }

  // ---- bus ----
  read8(a) {
    a = m24(a)
    if (a < 0x100000) return this.ram[a]
    if (a < 0x200000) return this.mmio ? this.mmio.read(a) & 0xff : 0  // MMIO + PPU + audio + reserved devices
    if (a >= 0x200000 && a < 0x208000) return this.save[a - 0x200000]
    if (a >= this.romBase && a < this.romBase + this.rom.length) return this.rom[a - this.romBase]
    return 0
  }
  write8(a, v) {
    a = m24(a); v &= 0xff
    if (a < 0x100000) { this.ram[a] = v; return }
    if (a < 0x200000) { if (this.mmio) this.mmio.write(a, v); return }  // MMIO + PPU + audio + reserved devices
    if (a >= 0x200000 && a < 0x208000) { this.save[a - 0x200000] = v; return }
    // ROM and unmapped: ignored
  }
  read16(a) { return this.read8(a) | (this.read8(a + 1) << 8) }
  read24(a) { return this.read16(a) | (this.read8(a + 2) << 16) }
  write16(a, v) { this.write8(a, v); this.write8(a + 1, v >> 8) }
  write24(a, v) { this.write16(a, v); this.write8(a + 2, v >> 16) }

  // ---- stack ----
  push16(v) { this.SP = m24(this.SP - 2); this.write16(this.SP, v) }
  pop16() { const v = this.read16(this.SP); this.SP = m24(this.SP + 2); return v }
  push24(v) { this.SP = m24(this.SP - 4); this.write24(this.SP, v) }   // 4-byte aligned slot
  pop24() { const v = this.read24(this.SP); this.SP = m24(this.SP + 4); return v }

  // ---- flags ----
  setZN(r) { this.F.z = (r & 0xffff) === 0; this.F.n = (r & 0x8000) !== 0 }
  add16(a, b) { const r = a + b; this.F.c = r > 0xffff; const rr = r & 0xffff; this.F.v = (~(a ^ b) & (a ^ rr) & 0x8000) !== 0; this.setZN(rr); return rr }
  sub16(a, b) { const r = a - b; this.F.c = a >= b; const rr = r & 0xffff; this.F.v = ((a ^ b) & (a ^ rr) & 0x8000) !== 0; this.setZN(rr); return rr }
  adc16(a, b) { return this.add16(a, b + (this.F.c ? 1 : 0)) }
  sbc16(a, b) { return this.sub16(a, b + (this.F.c ? 0 : 1)) }
  logic(r) { r &= 0xffff; this.setZN(r); this.F.v = false; return r }
  packStatus() { const f = this.F; return (f.z ? FZ : 0) | (f.n ? FN : 0) | (f.c ? FC : 0) | (f.v ? FV : 0) | (this.ie ? FI : 0) }
  loadStatus(s) { this.F = { z: !!(s & FZ), n: !!(s & FN), c: !!(s & FC), v: !!(s & FV) }; this.ie = !!(s & FI) }

  cond(name) {
    const f = this.F
    switch (name) {
      case 'BEQ': return f.z; case 'BNE': return !f.z
      case 'BCS': return f.c; case 'BCC': return !f.c
      case 'BMI': return f.n; case 'BPL': return !f.n
      case 'BVS': return f.v; case 'BVC': return !f.v
      case 'BLT': return f.n !== f.v; case 'BGE': return f.n === f.v
      case 'BGT': return !f.z && (f.n === f.v); case 'BLE': return f.z || (f.n !== f.v)
      case 'BHI': return f.c && !f.z; case 'BLS': return !f.c || f.z
    }
    return false
  }

  // raise an interrupt (used once the PPU/timers are wired). Returns whether taken.
  interrupt(name) {
    if (!this.ie) return false
    this.push16(this.packStatus()); this.push24(this.PC)
    this.ie = false; this.waiting = false; this.halted = false
    this.PC = this.read24(vectorAddr(name))
    return true
  }

  fetch() {
    const op = this.read8(this.PC), len = isa.lengthOf(op)
    const buf = new Uint8Array(len)
    for (let i = 0; i < len; i++) buf[i] = this.read8(m24(this.PC + i))
    return isa.decode(buf, 0)
  }

  step() {
    if (this.halted || this.waiting) return 0
    const at = this.PC
    const d = this.fetch()
    let next = m24(at + d.length)
    const R = this.R, A = this.A, v = d.values
    const rp = i => unpackRegs(v[i])
    switch (d.name) {
      case 'NOP': break
      case 'MOV.b': { const [x] = rp(0); R[x] = v[1] & 0xff; break }
      case 'MOV.i': { const [x] = rp(0); R[x] = m16(v[1]); break }
      case 'MOV.r': { const [x, y] = rp(0); R[x] = R[y]; break }
      case 'LDA': { const [x] = rp(0); A[x] = m24(v[1]); break }
      case 'LDADDR': { const [x, y] = rp(0); A[x] = this.read24(A[y]); break }
      case 'MOVA': { const [x, y] = rp(0); A[x] = A[y]; break }

      case 'LDW.ind': { const [x, a] = rp(0); R[x] = this.read16(A[a]); break }
      case 'LDW.dsp': { const [x, a] = rp(0); R[x] = this.read16(m24(A[a] + s8(v[1]))); break }
      case 'LDW.idx': { const [x, a] = rp(0); const [m] = rp(1); R[x] = this.read16(m24(A[a] + s16(R[m]))); break }
      case 'LDW.abs': { const [x] = rp(0); R[x] = this.read16(v[1]); break }
      case 'LDB.ind': { const [x, a] = rp(0); R[x] = this.read8(A[a]); break }
      case 'LDB.dsp': { const [x, a] = rp(0); R[x] = this.read8(m24(A[a] + s8(v[1]))); break }
      case 'LDB.idx': { const [x, a] = rp(0); const [m] = rp(1); R[x] = this.read8(m24(A[a] + s16(R[m]))); break }
      case 'LDB.abs': { const [x] = rp(0); R[x] = this.read8(v[1]); break }
      case 'STW.ind': { const [x, a] = rp(0); this.write16(A[a], R[x]); break }
      case 'STW.dsp': { const [x, a] = rp(0); this.write16(m24(A[a] + s8(v[1])), R[x]); break }
      case 'STW.idx': { const [x, a] = rp(0); const [m] = rp(1); this.write16(m24(A[a] + s16(R[m])), R[x]); break }
      case 'STW.abs': { const [x] = rp(0); this.write16(v[1], R[x]); break }
      case 'STB.ind': { const [x, a] = rp(0); this.write8(A[a], R[x]); break }
      case 'STB.dsp': { const [x, a] = rp(0); this.write8(m24(A[a] + s8(v[1])), R[x]); break }
      case 'STB.idx': { const [x, a] = rp(0); const [m] = rp(1); this.write8(m24(A[a] + s16(R[m])), R[x]); break }
      case 'STB.abs': { const [x] = rp(0); this.write8(v[1], R[x]); break }

      case 'ADD.r': { const [x, y] = rp(0); R[x] = this.add16(R[x], R[y]); break }
      case 'ADD.i': { const [x] = rp(0); R[x] = this.add16(R[x], m16(v[1])); break }
      case 'SUB.r': { const [x, y] = rp(0); R[x] = this.sub16(R[x], R[y]); break }
      case 'SUB.i': { const [x] = rp(0); R[x] = this.sub16(R[x], m16(v[1])); break }
      case 'ADC.r': { const [x, y] = rp(0); R[x] = this.adc16(R[x], R[y]); break }
      case 'SBC.r': { const [x, y] = rp(0); R[x] = this.sbc16(R[x], R[y]); break }
      case 'CMP.r': { const [x, y] = rp(0); this.sub16(R[x], R[y]); break }
      case 'CMP.i': { const [x] = rp(0); this.sub16(R[x], m16(v[1])); break }
      case 'NEG': { const [x] = rp(0); R[x] = this.sub16(0, R[x]); break }
      case 'AND.r': { const [x, y] = rp(0); R[x] = this.logic(R[x] & R[y]); break }
      case 'AND.i': { const [x] = rp(0); R[x] = this.logic(R[x] & m16(v[1])); break }
      case 'OR.r': { const [x, y] = rp(0); R[x] = this.logic(R[x] | R[y]); break }
      case 'OR.i': { const [x] = rp(0); R[x] = this.logic(R[x] | m16(v[1])); break }
      case 'XOR.r': { const [x, y] = rp(0); R[x] = this.logic(R[x] ^ R[y]); break }
      case 'XOR.i': { const [x] = rp(0); R[x] = this.logic(R[x] ^ m16(v[1])); break }
      case 'NOT': { const [x] = rp(0); R[x] = this.logic(~R[x]); break }
      case 'BIT.r': { const [x, y] = rp(0); this.logic(R[x] & R[y]); break }
      case 'TST': { const [x] = rp(0); this.logic(R[x]); break }
      case 'SHL.i': { const [x] = rp(0); const n = v[1] & 15; this.F.c = n ? !!(R[x] & (1 << (16 - n))) : this.F.c; R[x] = this.logic(R[x] << n) }
        break
      case 'SHR.i': { const [x] = rp(0); const n = v[1] & 15; this.F.c = n ? !!(R[x] & (1 << (n - 1))) : this.F.c; R[x] = this.logic(R[x] >>> n) }
        break
      case 'SAR.i': { const [x] = rp(0); const n = v[1] & 15; this.F.c = n ? !!(R[x] & (1 << (n - 1))) : this.F.c; R[x] = this.logic(s16(R[x]) >> n) }
        break
      case 'SHL.r': { const [x, y] = rp(0); R[x] = this.logic(R[x] << (R[y] & 15)); break }
      case 'SHR.r': { const [x, y] = rp(0); R[x] = this.logic(R[x] >>> (R[y] & 15)); break }
      case 'SAR.r': { const [x, y] = rp(0); R[x] = this.logic(s16(R[x]) >> (R[y] & 15)); break }

      case 'ADDA.i': { const [a] = rp(0); A[a] = m24(A[a] + s16(v[1])); break }
      case 'ADDA.r': { const [a, m] = rp(0); A[a] = m24(A[a] + s16(R[m])); break }
      case 'INCA': { const [a] = rp(0); A[a] = m24(A[a] + 1); break }
      case 'DECA': { const [a] = rp(0); A[a] = m24(A[a] - 1); break }
      case 'CMPA': { const [a, b] = rp(0); this.F.z = A[a] === A[b]; this.F.c = A[a] >= A[b]; break }

      case 'BRA': next = m24(next + s16(v[0])); break
      case 'BEQ': case 'BNE': case 'BCS': case 'BCC': case 'BMI': case 'BPL':
      case 'BVS': case 'BVC': case 'BLT': case 'BGE': case 'BGT': case 'BLE':
      case 'BHI': case 'BLS': if (this.cond(d.name)) next = m24(next + s8(v[0])); break
      case 'JMP.abs': next = v[0]; break
      case 'JMP.ind': { const [a] = rp(0); next = A[a]; break }
      case 'CALL.abs': this.push24(next); next = v[0]; break
      case 'CALL.ind': { const [a] = rp(0); this.push24(next); next = A[a]; break }
      case 'RET': next = this.pop24(); break

      case 'PUSH': { const [x] = rp(0); this.push16(R[x]); break }
      case 'POP': { const [x] = rp(0); R[x] = this.pop16(); break }
      case 'PUSHA': { const [a] = rp(0); this.push24(A[a]); break }
      case 'POPA': { const [a] = rp(0); A[a] = this.pop24(); break }
      case 'IRET': next = this.pop24(); this.loadStatus(this.pop16()); break

      case 'HALT': this.halted = true; next = at; break
      case 'WAIT': this.waiting = true; break  // advances; the frame loop clears `waiting` at vblank
      case 'EI': this.ie = true; break
      case 'DI': this.ie = false; break
      default: throw new Error('unimplemented instruction ' + d.name)
    }
    this.PC = next
    this.steps++
    return 1
  }

  run(maxSteps = 1e7) { let n = 0; while (n < maxSteps && !this.halted && !this.waiting) { this.step(); n++ } return n }
}

module.exports = { CastlePalmCPU, VECTOR_BASE }

};
__mods["cpu/cart"]=function(module,exports,require){
'use strict'
// CastlePalm cartridge format v0 (provisional).
//
// A 32-byte little-endian header followed by the ROM image. Deliberately minimal;
// relocation and richer save metadata are deferred (docs/DECISIONS.md).
//
//   off  size  field
//   0    4     magic "CPLM"
//   4    1     format version (1)
//   5    1     flags (bit0 = has save RAM)
//   6    2     reserved (0)
//   8    16    title (ASCII, null-padded)
//   24   3     load base (24-bit; where the ROM maps — normally $300000)
//   27   1     reserved (0)
//   28   4     ROM length in bytes
//   32   ...   ROM image

const { assemble } = require('./asm.js')
const { CastlePalmCPU } = require('./core.js')

const MAGIC = 'CPLM'
const HEADER = 32
const FLAG_SAVE = 1

function makeCart({ image, origin = 0x300000, title = '', hasSave = false }) {
  const out = new Uint8Array(HEADER + image.length)
  const dv = new DataView(out.buffer)
  for (let i = 0; i < 4; i++) out[i] = MAGIC.charCodeAt(i)
  out[4] = 1
  out[5] = hasSave ? FLAG_SAVE : 0
  for (let i = 0; i < 16 && i < title.length; i++) out[8 + i] = title.charCodeAt(i) & 0x7f
  out[24] = origin & 0xff; out[25] = (origin >> 8) & 0xff; out[26] = (origin >> 16) & 0xff
  dv.setUint32(28, image.length, true)
  out.set(image, HEADER)
  return out
}

function parseCart(bytes) {
  if (bytes.length < HEADER) throw new Error('cartridge too small')
  const magic = String.fromCharCode(bytes[0], bytes[1], bytes[2], bytes[3])
  if (magic !== MAGIC) throw new Error('bad cartridge magic "' + magic + '"')
  const version = bytes[4]
  if (version !== 1) throw new Error('unsupported cartridge version ' + version)
  const dv = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength)
  let title = ''
  for (let i = 0; i < 16; i++) { const c = bytes[8 + i]; if (c) title += String.fromCharCode(c) }
  const loadBase = bytes[24] | (bytes[25] << 8) | (bytes[26] << 16)
  const romLength = dv.getUint32(28, true)
  if (HEADER + romLength > bytes.length) throw new Error('cartridge ROM length exceeds file')
  return {
    version, title, loadBase, hasSave: !!(bytes[5] & FLAG_SAVE),
    rom: bytes.slice(HEADER, HEADER + romLength),
  }
}

// assemble .asm source straight into a cartridge image
function buildCart(source, { title = '' } = {}) {
  const r = assemble(source)
  return makeCart({ image: r.image, origin: r.origin, title })
}

// parse a cartridge and return a CPU ready to run it
function boot(cartBytes, { mmio = null } = {}) {
  const cart = parseCart(cartBytes)
  const cpu = new CastlePalmCPU({ rom: cart.rom, romBase: cart.loadBase, mmio })
  return { cpu, cart }
}

module.exports = { makeCart, parseCart, buildCart, boot, MAGIC, HEADER }

};
__mods["ppu"]=function(module,exports,require){
'use strict'

class FantasyPPU {
  static WIDTH=320
  static HEIGHT=224
  static VRAM_SIZE=128*1024
  static TILE_BYTES=32
  static TILE_COUNT=2048
  static MAP_WIDTH=64
  static MAP_HEIGHT=64
  static MAP_BYTES=64*64*4
  static MAP_OFFSETS=[0x10000,0x14000]
  static SPRITE_COUNT=128
  static SPRITES_PER_LINE=32

  constructor(){
    this.vram=new Uint8Array(FantasyPPU.VRAM_SIZE)
    this.view=new DataView(this.vram.buffer)
    this.palette=new Uint32Array(256)
    this.layers=[this.makeLayer(0),this.makeLayer(1)]
    this.sprites=Array.from({length:FantasyPPU.SPRITE_COUNT},()=>this.makeSprite())
    this.affineLines=Array(FantasyPPU.HEIGHT).fill(null)
    this.metrics={maxSpritesOnLine:0,droppedSprites:0,visibleSprites:0}
    this.setPalette(0,0,0,0)
  }

  makeLayer(index){
    return {index,enabled:true,scrollX:0,scrollY:0,basePriority:index*2,affine:false}
  }

  makeSprite(){
    return {x:0,y:0,tile:0,palette:0,size:8,priority:3,hflip:false,vflip:false,enabled:false}
  }

  reset(){
    this.vram.fill(0)
    this.palette.fill(0)
    this.layers=[this.makeLayer(0),this.makeLayer(1)]
    this.sprites=Array.from({length:FantasyPPU.SPRITE_COUNT},()=>this.makeSprite())
    this.affineLines.fill(null)
    this.setPalette(0,0,0,0)
  }

  setPalette(index,r,g,b){
    if(index<0||index>255)throw new RangeError('palette index must be 0..255')
    this.palette[index]=(0xff000000|((b&255)<<16)|((g&255)<<8)|(r&255))>>>0
  }

  setTile(index,pixels){
    if(index<0||index>=FantasyPPU.TILE_COUNT)throw new RangeError('tile index out of range')
    if(!pixels||pixels.length!==64)throw new RangeError('tile requires 64 pixels')
    const base=index*FantasyPPU.TILE_BYTES
    for(let i=0;i<64;i+=2)this.vram[base+(i>>1)]=((pixels[i]&15)<<4)|(pixels[i+1]&15)
  }

  tilePixel(index,x,y){
    if(index<0||index>=FantasyPPU.TILE_COUNT)return 0
    const offset=index*FantasyPPU.TILE_BYTES+y*4+(x>>1)
    const packed=this.vram[offset]
    return x&1?packed&15:packed>>4
  }

  encodeMapEntry({tile=0,palette=0,hflip=false,vflip=false,priority=0}={}){
    return ((tile&0x7ff)|((palette&15)<<11)|(hflip?1<<15:0)|(vflip?1<<16:0)|((priority&3)<<17))>>>0
  }

  setMapEntry(layer,x,y,entry){
    this.assertLayer(layer)
    const offset=this.mapOffset(layer,x,y)
    this.view.setUint32(offset,this.encodeMapEntry(entry),true)
  }

  getMapEntry(layer,x,y){
    this.assertLayer(layer)
    const raw=this.view.getUint32(this.mapOffset(layer,x,y),true)
    return {
      tile:raw&0x7ff,
      palette:(raw>>>11)&15,
      hflip:Boolean(raw&(1<<15)),
      vflip:Boolean(raw&(1<<16)),
      priority:(raw>>>17)&3
    }
  }

  mapOffset(layer,x,y){
    x=((x%FantasyPPU.MAP_WIDTH)+FantasyPPU.MAP_WIDTH)%FantasyPPU.MAP_WIDTH
    y=((y%FantasyPPU.MAP_HEIGHT)+FantasyPPU.MAP_HEIGHT)%FantasyPPU.MAP_HEIGHT
    return FantasyPPU.MAP_OFFSETS[layer]+(y*FantasyPPU.MAP_WIDTH+x)*4
  }

  assertLayer(layer){
    if(layer!==0&&layer!==1)throw new RangeError('layer must be 0 or 1')
  }

  setSprite(index,values){
    if(index<0||index>=FantasyPPU.SPRITE_COUNT)throw new RangeError('sprite index out of range')
    const next={...this.makeSprite(),...values}
    if(![8,16,32,64].includes(next.size))throw new RangeError('sprite size must be 8, 16, 32, or 64')
    this.sprites[index]=next
  }

  setAffineLine(y,{startX,startY,dx,dy}){
    if(y<0||y>=FantasyPPU.HEIGHT)throw new RangeError('scanline out of range')
    this.affineLines[y]={startX:startX|0,startY:startY|0,dx:dx|0,dy:dy|0}
  }

  clearAffineLines(){
    this.affineLines.fill(null)
  }

  sampleLayer(layerIndex,worldX,worldY){
    const tileX=Math.floor(worldX/8)
    const tileY=Math.floor(worldY/8)
    const entry=this.getMapEntry(layerIndex,tileX,tileY)
    let px=((worldX%8)+8)%8
    let py=((worldY%8)+8)%8
    if(entry.hflip)px=7-px
    if(entry.vflip)py=7-py
    const colour=this.tilePixel(entry.tile,px,py)
    if(colour===0)return null
    return {colour:this.palette[(entry.palette<<4)|colour],priority:this.layers[layerIndex].basePriority+entry.priority}
  }

  drawLayerLine(layerIndex,y,pixels,priorities){
    const layer=this.layers[layerIndex]
    if(!layer.enabled)return
    const affine=layer.affine?this.affineLines[y]:null
    if(layer.affine&&!affine)return
    let sx=affine?.startX||0,sy=affine?.startY||0
    for(let x=0;x<FantasyPPU.WIDTH;x++){
      const worldX=layer.affine?sx>>16:x+layer.scrollX
      const worldY=layer.affine?sy>>16:y+layer.scrollY
      const sample=this.sampleLayer(layerIndex,worldX,worldY)
      const out=y*FantasyPPU.WIDTH+x
      if(sample&&sample.priority>=priorities[out]){
        pixels[out]=sample.colour
        priorities[out]=sample.priority
      }
      if(layer.affine){sx=(sx+affine.dx)|0;sy=(sy+affine.dy)|0}
    }
  }

  spritePixel(sprite,localX,localY){
    if(sprite.hflip)localX=sprite.size-1-localX
    if(sprite.vflip)localY=sprite.size-1-localY
    const tilesWide=sprite.size>>3
    const tile=sprite.tile+(localY>>3)*tilesWide+(localX>>3)
    return this.tilePixel(tile,localX&7,localY&7)
  }

  drawSpritesLine(y,pixels,priorities){
    const accepted=[]
    let dropped=0
    for(let i=0;i<this.sprites.length;i++){
      const s=this.sprites[i]
      if(!s.enabled||y<s.y||y>=s.y+s.size||s.x>=FantasyPPU.WIDTH||s.x+s.size<=0)continue
      this._seen.add(i)
      if(accepted.length<FantasyPPU.SPRITES_PER_LINE)accepted.push({s,index:i})
      else dropped++
    }
    if(accepted.length>this.metrics.maxSpritesOnLine)this.metrics.maxSpritesOnLine=accepted.length
    this.metrics.droppedSprites+=dropped
    for(let n=accepted.length-1;n>=0;n--){
      const {s}=accepted[n]
      const localY=y-s.y
      for(let localX=0;localX<s.size;localX++){
        const x=s.x+localX
        if(x<0||x>=FantasyPPU.WIDTH)continue
        const colour=this.spritePixel(s,localX,localY)
        if(colour===0)continue
        const out=y*FantasyPPU.WIDTH+x
        if(s.priority>=priorities[out]){
          pixels[out]=this.palette[((s.palette&15)<<4)|colour]
          priorities[out]=s.priority
        }
      }
    }
    this.metrics.visibleSprites=this._seen.size
  }

  // reset per-frame sprite metrics (call once before rendering a frame line-by-line)
  beginFrame(){
    this._seen=new Set()
    this.metrics={maxSpritesOnLine:0,droppedSprites:0,visibleSprites:0}
  }

  // render a single scanline with the CURRENT register/scroll state (enables raster)
  renderLine(y,pixels,priorities){
    const bd=this.palette[0],base=y*FantasyPPU.WIDTH
    for(let x=0;x<FantasyPPU.WIDTH;x++){pixels[base+x]=bd;priorities[base+x]=-1}
    this.drawLayerLine(0,y,pixels,priorities)
    this.drawLayerLine(1,y,pixels,priorities)
    this.drawSpritesLine(y,pixels,priorities)
  }

  render(){
    const pixels=new Uint32Array(FantasyPPU.WIDTH*FantasyPPU.HEIGHT)
    const priorities=new Int8Array(pixels.length)
    this.beginFrame()
    for(let y=0;y<FantasyPPU.HEIGHT;y++)this.renderLine(y,pixels,priorities)
    return pixels
  }
}

if(typeof module!=='undefined')module.exports={FantasyPPU}


};
__mods["apu"]=function(module,exports,require){
'use strict'
// CastlePalm APU v0 (provisional) — 2 square channels + 1 noise channel.
//
// Memory-mapped (system.js routes the audio register block to it), deterministic
// sample generation. The host shell plays the per-frame buffer via Web Audio;
// the core stays headless and deterministic. Channel/register layout is
// provisional (docs/MMIO_V0.md, docs/DECISIONS.md). Square channels are 50% duty;
// a square toggles its sign every `period` samples, so freq = RATE / (2*period).

const RATE = 48000
const SAMPLES_PER_FRAME = 800   // RATE / 60

class CastlePalmAPU {
  constructor() { this.rate = RATE; this.reset() }
  reset() {
    this.sq = [{ period: 0, vol: 0, on: false, cnt: 0, sign: 1 },
               { period: 0, vol: 0, on: false, cnt: 0, sign: 1 }]
    this.noise = { period: 0, vol: 0, on: false, cnt: 0, lfsr: 0x7fff }
  }

  setSquare(i, field, v) {
    const c = this.sq[i]
    if (field === 'periodLo') c.period = (c.period & 0xff00) | (v & 0xff)
    else if (field === 'periodHi') c.period = (c.period & 0x00ff) | ((v & 0xff) << 8)
    else if (field === 'vol') c.vol = v & 0x0f
    else if (field === 'ctrl') c.on = !!(v & 1)
  }
  setNoise(field, v) {
    const n = this.noise
    if (field === 'periodLo') n.period = (n.period & 0xff00) | (v & 0xff)
    else if (field === 'periodHi') n.period = (n.period & 0x00ff) | ((v & 0xff) << 8)
    else if (field === 'vol') n.vol = v & 0x0f
    else if (field === 'ctrl') n.on = !!(v & 1)
  }

  // generate n mono samples in [-1,1] (Float32), advancing channel state.
  generate(n = SAMPLES_PER_FRAME) {
    const out = new Float32Array(n)
    for (let s = 0; s < n; s++) {
      let acc = 0
      for (const c of this.sq) {
        if (c.on && c.period > 0) {
          if (++c.cnt >= c.period) { c.cnt = 0; c.sign = -c.sign }
          acc += c.sign * c.vol
        }
      }
      const no = this.noise
      if (no.on && no.period > 0) {
        if (++no.cnt >= no.period) {
          no.cnt = 0
          const fb = (no.lfsr ^ (no.lfsr >> 1)) & 1
          no.lfsr = (no.lfsr >> 1) | (fb << 14)
        }
        acc += (no.lfsr & 1 ? 1 : -1) * no.vol
      }
      out[s] = acc / 64   // 3 channels * 15 max = 45 -> stays under 1.0
    }
    return out
  }
}

module.exports = { CastlePalmAPU, AUDIO_RATE: RATE, SAMPLES_PER_FRAME }

};
__mods["system"]=function(module,exports,require){
'use strict'
// CastlePalm system v0.2 — composes the CPU core, the PPU, the APU, and input,
// routes the CPU's MMIO ports onto them, and drives a timed scanline frame with
// vblank/hblank interrupts and a DMA channel. Provisional register map
// (docs/MMIO_V0.md); timing follows PPU_ARCHITECTURE_V0_2 at scanline granularity.
//
// v0 note: rendering is still frame-at-once (the PPU draws the whole frame after
// the scan timeline). Per-scanline rasterisation (so hblank-IRQ register changes
// show as splits) is the next increment; the timing/IRQ/DMA infrastructure is here.

const { boot } = require('./cpu/cart.js')
const { FantasyPPU } = require('./ppu.js')
const { CastlePalmAPU, AUDIO_RATE } = require('./apu.js')

const LINES = 262, VISIBLE_LINES = 224       // 512 ticks/line; vblank at line 224

const REG = {
  INPUT: 0x100000,        // u16 controller word, player 1 (read)
  INPUT1: 0x100002,       // u16 controller word, player 2 (read)
  IRQ_FLAGS: 0x100010,    // read: bit0 vblank, bit1 hblank; write-one-to-clear
  IRQ_ENABLE: 0x100012,   // bit0 vblank, bit1 hblank
  FRAME: 0x100014,        // u16 frame counter (read)
  DMA_SRC: 0x100020,      // 3 bytes: 24-bit source in CPU space
  DMA_DST: 0x100024,      // u16 destination offset within the dest space
  DMA_LEN: 0x100028,      // u16 byte length
  DMA_MODE: 0x10002a,     // u8: bits0-1 space (0 VRAM, 1 OAM, 2 palette), bit4 fill
  DMA_FILL: 0x10002c,     // u16 fill value
  DMA_CTRL: 0x10002e,     // u8: bit0 start
  VRAM_ADDR: 0x101000,    // 3 bytes: 17-bit VRAM pointer
  VRAM_DATA: 0x101004,    // 2-byte port: vram[ptr++]
  PAL_INDEX: 0x101008,    // u8 palette entry index
  PAL_DATA: 0x10100a,     // 2-byte port: RGB555 -> palette[index++]
  OAM_INDEX: 0x10100c,    // u16 byte offset into OAM
  OAM_DATA: 0x10100e,     // 1-byte port: oam[idx++]
  BG0_SX: 0x101010, BG0_SY: 0x101012, BG1_SX: 0x101014, BG1_SY: 0x101016,
  PPU_CTRL: 0x101018,     // u16: bit0 BG0 enable, bit1 BG1 enable
  PPU_SCANLINE: 0x10101a, // u16 current scanline (read)
}
const c5to8 = c => (c << 3) | (c >> 2)

class System {
  constructor(cartBytes) {
    this.ppu = new FantasyPPU()
    this.inputs = [0, 0]
    this.frame = 0
    this.scanline = 0
    this.vblank = false
    this.irqFlags = 0          // bit0 vblank, bit1 hblank
    this.irqEnable = 0
    this.va = 0; this.pi = 0; this.pl = 0; this.oi = 0
    this.scroll = [0, 0, 0, 0]
    this.oam = new Uint8Array(1024)
    this.dma = { src: 0, dst: 0, len: 0, mode: 0, fill: 0 }
    this.dmaBytes = 0
    this.apu = new CastlePalmAPU()
    this.audioRate = AUDIO_RATE
    this.audio = null
    const mmio = { read: a => this.read(a), write: (a, b) => this.write(a, b) }
    const r = boot(cartBytes, { mmio })
    this.cpu = r.cpu; this.cart = r.cart
    this.framebuffer = null
  }

  read(a) {
    switch (a) {
      case REG.INPUT: return this.inputs[0] & 0xff
      case REG.INPUT + 1: return (this.inputs[0] >> 8) & 0xff
      case REG.INPUT1: return this.inputs[1] & 0xff
      case REG.INPUT1 + 1: return (this.inputs[1] >> 8) & 0xff
      case REG.IRQ_FLAGS: return this.irqFlags & 0xff
      case REG.IRQ_FLAGS + 1: return (this.irqFlags >> 8) & 0xff
      case REG.FRAME: return this.frame & 0xff
      case REG.FRAME + 1: return (this.frame >> 8) & 0xff
      case REG.PPU_SCANLINE: return this.scanline & 0xff
      case REG.PPU_SCANLINE + 1: return (this.scanline >> 8) & 0xff
      case REG.VRAM_DATA: case REG.VRAM_DATA + 1: { const v = this.ppu.vram[this.va & 0x1ffff]; this.va++; return v }
    }
    return 0
  }

  write(a, b) {
    switch (a) {
      case REG.VRAM_ADDR: this.va = (this.va & 0x1ff00) | b; return
      case REG.VRAM_ADDR + 1: this.va = (this.va & 0x100ff) | (b << 8); return
      case REG.VRAM_ADDR + 2: this.va = (this.va & 0x0ffff) | ((b & 1) << 16); return
      case REG.VRAM_DATA: case REG.VRAM_DATA + 1: this.ppu.vram[this.va & 0x1ffff] = b; this.va++; return
      case REG.PAL_INDEX: this.pi = b & 0xff; return
      case REG.PAL_DATA: this.pl = (this.pl & 0xff00) | b; return
      case REG.PAL_DATA + 1: { this.pl = (this.pl & 0x00ff) | (b << 8); const v = this.pl; this.ppu.setPalette(this.pi, c5to8(v & 31), c5to8((v >> 5) & 31), c5to8((v >> 10) & 31)); this.pi = (this.pi + 1) & 0xff; return }
      case REG.OAM_INDEX: this.oi = (this.oi & 0xff00) | b; return
      case REG.OAM_INDEX + 1: this.oi = (this.oi & 0x00ff) | (b << 8); return
      case REG.OAM_DATA: this.oam[this.oi & 0x3ff] = b; this.oi++; return
      case REG.IRQ_ENABLE: this.irqEnable = b & 3; return
      case REG.IRQ_FLAGS: this.irqFlags &= ~b; this.vblank = !!(this.irqFlags & 1); return
      case REG.PPU_CTRL: this.ppu.layers[0].enabled = !!(b & 1); this.ppu.layers[1].enabled = !!(b & 2); return
      case REG.DMA_SRC: this.dma.src = (this.dma.src & 0xffff00) | b; return
      case REG.DMA_SRC + 1: this.dma.src = (this.dma.src & 0xff00ff) | (b << 8); return
      case REG.DMA_SRC + 2: this.dma.src = (this.dma.src & 0x00ffff) | (b << 16); return
      case REG.DMA_DST: this.dma.dst = (this.dma.dst & 0xff00) | b; return
      case REG.DMA_DST + 1: this.dma.dst = (this.dma.dst & 0x00ff) | (b << 8); return
      case REG.DMA_LEN: this.dma.len = (this.dma.len & 0xff00) | b; return
      case REG.DMA_LEN + 1: this.dma.len = (this.dma.len & 0x00ff) | (b << 8); return
      case REG.DMA_MODE: this.dma.mode = b; return
      case REG.DMA_FILL: this.dma.fill = (this.dma.fill & 0xff00) | b; return
      case REG.DMA_FILL + 1: this.dma.fill = (this.dma.fill & 0x00ff) | (b << 8); return
      case REG.DMA_CTRL: if (b & 1) this.runDMA(); return
      // audio register block ($102000)
      case 0x102000: this.apu.setSquare(0, 'periodLo', b); return
      case 0x102001: this.apu.setSquare(0, 'periodHi', b); return
      case 0x102002: this.apu.setSquare(0, 'vol', b); return
      case 0x102003: this.apu.setSquare(0, 'ctrl', b); return
      case 0x102004: this.apu.setSquare(1, 'periodLo', b); return
      case 0x102005: this.apu.setSquare(1, 'periodHi', b); return
      case 0x102006: this.apu.setSquare(1, 'vol', b); return
      case 0x102007: this.apu.setSquare(1, 'ctrl', b); return
      case 0x102008: this.apu.setNoise('periodLo', b); return
      case 0x102009: this.apu.setNoise('periodHi', b); return
      case 0x10200a: this.apu.setNoise('vol', b); return
      case 0x10200b: this.apu.setNoise('ctrl', b); return
    }
    // BG scroll: each is a 2-byte signed latch
    for (let i = 0; i < 4; i++) {
      const base = REG.BG0_SX + i * 2
      if (a === base) { this.scroll[i] = (this.scroll[i] & 0xff00) | b; return }
      if (a === base + 1) { this.scroll[i] = (this.scroll[i] & 0x00ff) | (b << 8); return }
    }
  }

  // one DMA transfer: CPU memory -> VRAM / OAM / palette, or constant fill.
  runDMA() {
    const d = this.dma, space = d.mode & 3, fill = !!(d.mode & 0x10)
    const srcByte = i => fill ? ((i & 1) ? (d.fill >> 8) & 0xff : d.fill & 0xff) : this.cpu.read8((d.src + i) & 0xffffff)
    if (space === 2) {                       // palette: byte pairs -> RGB555 entries
      for (let i = 0; i + 1 < d.len; i += 2) {
        const w = srcByte(i) | (srcByte(i + 1) << 8), e = ((d.dst + i) >> 1) & 0xff
        this.ppu.setPalette(e, c5to8(w & 31), c5to8((w >> 5) & 31), c5to8((w >> 10) & 31))
      }
    } else {
      const buf = space === 1 ? this.oam : this.ppu.vram
      const mask = space === 1 ? 0x3ff : 0x1ffff
      for (let i = 0; i < d.len; i++) buf[(d.dst + i) & mask] = srcByte(i)
    }
    this.dmaBytes = d.len
  }

  // decode the binary OAM (128 x 8 bytes, PPU v0.2 layout) into PPU sprites
  commitOAM() {
    const o = this.oam, s16 = v => (v << 16) >> 16
    for (let i = 0; i < 128; i++) {
      const p = i * 8
      const attr = o[p + 6] | (o[p + 7] << 8)
      this.ppu.setSprite(i, {
        x: s16(o[p] | (o[p + 1] << 8)), y: s16(o[p + 2] | (o[p + 3] << 8)),
        tile: (o[p + 4] | (o[p + 5] << 8)) & 0x7ff,
        palette: attr & 0xf, size: [8, 16, 32, 64][(attr >> 4) & 3],
        hflip: !!(attr & 0x40), vflip: !!(attr & 0x80),
        priority: (attr >> 8) & 7, enabled: !!(attr & 0x8000),
      })
    }
  }

  setInputs(pad, word) { this.inputs[pad & 1] = word & 0xffff }
  setInput(word) { this.inputs[0] = word & 0xffff }   // pad-0 alias (back-compat)

  // deliver an interrupt and run its handler to completion (back to WAIT/HALT)
  _irq(bit, name, budget) {
    if ((this.irqEnable & bit) && this.cpu.ie) { this.cpu.interrupt(name); this.cpu.run(budget) }
  }

  // run one timed frame: game logic burst, then a scanline timeline that renders
  // each visible line with the current (per-line latched) registers and fires the
  // vblank/hblank IRQs. hblank handlers can change scroll/palette mid-frame -> raster.
  runFrame(budget = 500000) {
    const cpu = this.cpu, ppu = this.ppu, L = ppu.layers
    const W = FantasyPPU.WIDTH, H = FantasyPPU.HEIGHT
    cpu.waiting = false
    cpu.run(budget)                               // game logic burst (until WAIT/HALT)
    this.commitOAM()                              // sprites latched for the frame
    const pixels = new Uint32Array(W * H), pri = new Int8Array(W * H)
    ppu.beginFrame()
    for (let line = 0; line < LINES; line++) {
      this.scanline = line
      if (line < VISIBLE_LINES) {
        // SCANLINE_START: latch scroll, then render this line
        L[0].scrollX = (this.scroll[0] << 16) >> 16; L[0].scrollY = (this.scroll[1] << 16) >> 16
        L[1].scrollX = (this.scroll[2] << 16) >> 16; L[1].scrollY = (this.scroll[3] << 16) >> 16
        ppu.renderLine(line, pixels, pri)
        if (this.irqEnable & 2) { this.irqFlags |= 2; this._irq(2, 'hblank', budget) }  // HBLANK
      } else if (line === VISIBLE_LINES) {          // VBLANK_START
        this.irqFlags |= 1; this.vblank = true
        this._irq(1, 'vblank', budget)
      }
    }
    this.frame = (this.frame + 1) & 0xffff
    this.framebuffer = pixels
    this.audio = this.apu.generate()
    return this.framebuffer
  }
}

module.exports = { System, REG }

};
var sys=__require("system"),cart=__require("cpu/cart");
function __b64(s){var b=atob(s),a=new Uint8Array(b.length);for(var i=0;i<b.length;i++){a[i]=b.charCodeAt(i);}return a;}
window.CastlePalm={System:sys.System,REG:sys.REG,buildCart:cart.buildCart,parseCart:cart.parseCart,carts:{pong:__b64("Q1BMTQEAAABQT05HAAAAAAAAAAAAAAAAAAAwAGIXAAAMADAAAAAAAAAAAAACAAEfAAgQEAEA/38bAAoQEAIAIB8AABAQAgAAHwABEBAfAAIQEAIQIAIgER8gBBAQMxABAFL1AgBAHwAAEBACAAAfAAEQEB8AAhAQAjAIAgAAHwAEEBACAAEfAAQQEAIAEB8ABBAQAgAAHwAEEBAzMAEAUtoCAAAfAAAQEAIAAh8AARAQAgAAHwACEBAEAGIFMAEQAAUUIB8gBBAQSgAzEAEAUvECAAAfAAAQEAIACB8AARAQAgAAHwACEBAEAGIKMAEQAA0UIB8gBBAQSgAzEAEAUvFibwMwEwASAQA3AAAAURczAAEAGwASAQA3AAAAUggCAAAfAAMgEBMAFAEANwAAAFIiEwAAABA6AAABUQ8CAAEbABQBAGJvAzBQKgBivwQwdlCx/xMAEAEANwAAAFEXEwAAABA6AAABUQRibwMwYh8EMHZQj/8TAAAAEAMQOhABAFEOEyAIAQAzIAMAGyAIAQADEDoQAgBRDhMgCAEAMSADABsgCAEAEyAIAQA3IAAAWgMCIAA3IMAAXAQBIMAAGyAIAQATIAoBABMwAgEANiNaBzEgAgBQBAAzIAIANyAAAFoDAiAANyDAAFwEASDAABsgCgEAEwAAAQATEAQBADABGwAAAQATAAIBABMQBgEAMAEbAAIBABMAAgEANwAAAFoeAgAAGwACAQATEAYBADgQGxAGAQACAB4CEARirgMwEwACAQA3ANgAXB8BANgAGwACAQATEAYBADgQGxAGAQACAB4CEARirgMwEwAAAQA3ABgAWkYDMDEwCAA3MBAAXDoTEAIBABMgCAEAAzIxMCAANhNaJgMxMTAIADYyXBwTEAQBADcQAABaETgQGxAEAQACAB4CEARirgMwEwAAAQADMDEwCAA3MCgBXEA3ADABWjoTEAIBABMgCgEAAzIxMCAANhNaJgMxMTAIADYyXBwTEAQBADcQAABcETgQGxAEAQACAB4CEARirgMwEwAAAQA3AAAAWioCAHgCEBhirgMwExAOAQAxEAEAGxAOAQBiXgMwNxAFAFkIAiACGyAQAQATAAABADcAOAFcKgIAeAIQGGKuAzATEAwBADEQAQAbEAwBAGJeAzA3EAUAWQgCIAEbIBABAGIfBDB2UIf9AgCYGwAAAQACAGwbAAIBAGRiBAQwAgAAGwAMAQAbAA4BABsAEAEAGwASAQAfAAMgEAIAYBsACAEAGwAKAQACAAIbAAQBABsABgEAYl4DMGQbAAAgEAIADB8AAiAQAgABHwADIBAbEBIBAGQfQA4QEAMEQwAIHwAOEBAfUA4QEAMFQwAIHwAOEBAfYA4QEAMGQwAIHwAOEBAfMA4QEAIAgB8ADhAQZAIAABsADBAQARAABAIAAB8ADhAQMxABAFLyZAIAABsADBAQAjAAE0AAAQATUAIBAAJgAWLJAzATUAgBAAJwBAFAEAACYAFiyQMwMVAIADNwAQBS6xNQCgEAAnAEAUAoAQJgAWLJAzAxUAgAM3ABAFLrAlAIAnAHAkCcAmACYskDMDFQIAAzcAEAUuwCMBACQIQCUAYTYAwBAEJgAjFgEABiyQMwAkCsAlAGE2AOAQBCYAIxYBAAYskDMGQCAAAbAAwQEAIwAAJAnAJQbAJgAWLJAzACUGACcAQBQBAAAmABYskDMDFQCAAzcAEAUusCUGACcAQBQCgBAmABYskDMDFQCAAzcAEAUusCMBACQIACUDAEEFIFMGIvBTACQFACUJYEEFcFMGIvBTBkFGE3YP8AURo3YBoAUQtCYAIxYEAAYskDMDFAEABKEFDe/2QPDg0G/w8UEgcaEhMAERP/AAAAAAAAAAAAAAAAAAABEQAAAREAAAEQAAABEAAAARAAAAAAAAAAAAAAAAAREAAAERAAAAEQAAABEAAAARAAAAAAARAAAAEQAAABEAAAAREAAAERAAAAAAAAAAAAAAAAARAAAAEQAAABEAAAERAAABEQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABAAAAAQAAAAEAAAABAAAAAQAAAAAAAAAAAAAAABAAAAAQAAAAEAAAABAAAAAQAAAAAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAAAAAAAAAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAREAAAERAAAAAAAAAAAAAAERAAAAAAAAAAAAAAAAERAAABEQAAABEAAAARAAABEQAAAAAAERAAABEAAAARAAAAERAAABEQAAAAAAAAAAAAAAABEQAAAAAAAAAAAAABEQAAAREAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABEQAAAREAAAAAAAAAAAAAAREAAAAAAAAAAAAAAAAREAAAERAAAAEQAAABEAAAERAAAAAAAREAAAAAAAAAAAAAAREAAAERAAAAAAAAAAAAAAAAERAAAAEQAAABEAAAERAAABEQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEQAAABEAAAARAAAAEQAAABEQAAAAAAAAAAAAAAAAEQAAABEAAAARAAAAEQAAAREAAAAAABEQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAREAAAARAAAAEQAAABEAAAARAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAREAAAERAAABEAAAARAAAAERAAAAAAAAAAAAAAAAERAAABEQAAAAAAAAAAAAABEQAAAAAAERAAAAAAAAAAAAAAERAAABEQAAAAAAAAAAAAAAABEQAAABEAAAARAAABEQAAAREAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABEQAAAREAAAEQAAABEAAAAREAAAAAAAAAAAAAAAAREAAAERAAAAAAAAAAAAAAERAAAAAAAREAAAEQAAABEAAAAREAAAERAAAAAAAAAAAAAAAAERAAAAEQAAABEAAAERAAABEQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAERAAABEQAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAABEQAAAREAAAARAAAAEQAAAQAAAAAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAAAAAAAAAAAAAQAAAAEAAAABAAAAAQAAAAEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAREAAAERAAABEAAAARAAAAERAAAAAAAAAAAAAAAAERAAABEQAAABEAAAARAAABEQAAAAAAERAAABEAAAARAAAAERAAABEQAAAAAAAAAAAAAAABEQAAABEAAAARAAABEQAAAREAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABEQAAAREAAAEQAAABEAAAAREAAAAAAAAAAAAAAAAREAAAERAAAAEQAAABEAAAERAAAAAAAREAAAAAAAAAAAAAAREAAAERAAAAAAAAAAAAAAAAERAAAAEQAAABEAAAERAAABEQAAAAAAAAAAAAAAAAAAAAAAAAAAAAEQAAABEAAAARABERAAAREQAAEREAABEREQAAAAARAAAAEQAAABEAAAAAEREAABERAAAREQAREREAABEREQAREREAEREAABERAAAREQAAEREAABERAAAREQAREREAERERAAAREQAAEREAABERAAAREQAAEREAABERAAAAAAAAERERABEREQAREREAEREAABERAAAREQAAERERAAAAABEAAAARAAAAEQAAAAAREQAAEREAABERABEAAAAAERERABEREQAREQAAEREAABERAAAREREAERERABEREREAAAARAAAAABERAAAREQAAEREAEQAAABEAAAARAAAAAAAAAAAAABEAAAARAAAAEQAREQAAEREAABERAAAREQAAAAAAERERABEREQAREREAAAAAAAAAAAAAAAAAAAAAAAAREQAAEREAABERAAAREQAAEREAAAAAEQAAABEAAAARAAAAAAAAAAAAAAAAAAAAAAAAAAAREREAERERABEREQAAAAAAABEREQAREREAERERABERAAAREQAAEREAABERAAAAAAARAAAAEQAAABEAAAAAEREAABERAAAREQAAEREAABERAAAREQAAEREAABERAAAREQAAERERABEREQAREREAEREAABERAAAREQAAEREAABERABEAAAARAAAAEQAAAAAAAAAAERERABEREQAREREAEREAABERAAAREQAAERERAAAAABEREQAREREAERERAAAAAAAAAAAAAAAAABEAAAAAERERABEREQAREQAAEREAABERAAAREREAERERABEREREAAAARAAAAAAAAAAAAAAAAAAAAERERABEREQAREREAAAAAAAAREREAERERABEREQAREQAAEREAABERAAAREREAAAAAERERABEREQAREREAAAAAAAAAAAAAAAAAEQAAAAAREREAERERABERAAAREQAAEREAABERAAAREQAAEREAEQAAABEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEQAAABEAAAARABERAAAREQAAEREAABERAAAAAAAREREAERERABEREQAAAAAAAAAAAAAAAAAAEREAABERAAAREQAAEREAABERAAAREQAAAAARAAAAEQAAABEAEREAABERAAAREQAAEREAABERABEREQAREREAERERAAAAAAAAEREAABERAAAREQAAEREAABERAAAREQAAERERAAAAAAAREQAAEREAABERAAAREQAAEREAABERABEREQAAERERABEREQAREQAAEREAABERAAAREQAAEREAABERABEREQAREREAABERAAAREQAAEREAABERAAAREQAAEREAAAAAAAAREREAERERABEREQAAABEAAAARAAAAEQAAABEAAAAAERERABEREQAREREAEQAAABEAAAARAAAAEQAAAAAAABEAAAARAAAAEQAAABEAAAARABEREQAREREAEREREQAAABEAAAARAAAAEQAAABEAAAAREREAERERABEREQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEREAABERAAAREQAAEREAABERAAAREQAAEREAAAAAAAAAAAAAEREAABERAAAREQAAAAARAAAAEQAAABEAEREAABERAAAREQAAEREAABERABEAAAARAAAAEQAAAAAAAAAAEREAABERAAAREQAAERERABEREQAREREAEREAAAAAAAAREQAAEREAABERABEAAAARAAAAEQAAAAAAAAAAEREAABERAAAREREAERERABEREQAREQAAEREAABERAAAAAAAAAAAAEQAAABEAAAARAAAAABERAAAREQAAEREAAAAAAAAREQAAEREAABERAAAREQAAEREAABERAAAREQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAREQAAEREAABERAAAREQAAEREAABEREQAREREAERERAAAAAAAAAAAAAAAAAAAAAAAAAAAREREAERERABEREQAAAAAAABERAAAREQAAEREAABEREQAREREAERERABEREQAAAAAAEREAABERAAAREQAREREAERERABEREQAREREAABEREQAREREAEREAABERAAAREQAAEREAABERAAAREQAREREAERERAAAREQAAEREAABERAAAREQAAEREAABERAAAAAAAAEREAABERAAAREQAAERERABEREQAREREAERERAAAAAAAREQAAEREAABERABEREQAREREAERERABEREQAAERERABEREQAREREAERERABEREQAREQAAEREAABERABEREQAREREAERERABEREQAREREAABERAAAREQAAEREAAAAAAAAAABEAAAARAAAAEQAREQAAEREAABERAAAREQAAAAAAEQAAABEAAAARAAAAABERAAAREQAAEREAABERAAAREQAAEREAABERAAAREQAAEREAAAAAEQAAABEAAAARABERAAAREQAAEREAABERAAAREQARAAAAEQAAABEAAAAAAAAAABEREQAREREAERERABERAAAREQAAEREAABEREQAAAAARAAAAEQAAABEAAAAAEREAABERAAAREQARAAAAABEREQAREREAEREAABERAAAREQAAEREAABERAAAREQARAAAAEQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAARAAAAEQAAABEAEREAABERAAAREQAAEREAAAAAABEAAAARAAAAEQAAAAAREQAAEREAABERAAAREQAAEREAABERAAAREREAERERABEREQAAABEAAAARAAAAEQAREQAAEREAEQAAABEAAAARAAAAERERABEREQAREREAAAAAAAAREREAERERABEREQAREQAAEREAABERAAAREREAAAAAEQAAABEAAAARAAAAABERAAAREQAAEREAEQAAAAAREREAERERABERAAAREQAAEREAABERAAAREQAAEREAEQAAABEAAAAAEREAABERAAAREQAAEREAABERAAAREQAAAAAAAAAAEQAAABEAAAARABERAAAREQAAEREAAAAAEQAAAAAREREAERERABEREQAAAAAAAAAAAAAAAAARAAAAAAAAEQAAABEAAAAAAAAAAAAAAAAAERERABEREQARERERAAAAEQAAAAAREQAAEREAABERABEAAAARAAAAEQAAAAAAAAAAERERABEREQAREREAAAARAAAAEQAAABEAAAARAAAAABEREQAREREAERERABEAAAARAAAAEQAAABEAAAAAAAARAAAAEQAAABEAAAARAAAAEQAAABEAAAARAAAAEREAAAARAAAAEQAAABEAAAARAAAAEQAAABEAAAARAAAAAAAAAAAREQAAEREAABERAAAREQAAEREAABERAAAREQAAAAAAABERAAAREQAAEREAABERAAAREQAAEREAABERAAAREQAAEREAABERAAAREQAAEREAABEREQAREREAERERABERAAAREQAAEREAABERAAAREQAREREAERERABEREQAAAAAAABERAAAREQAAEREAABERAAAREQAAEREAABERAAAAAAAAEREAABERAAAREQAAEREAABERAAAREQAAEREAABERAAAREQAAEREAABERAAAREQAAAAARAAAAEQAAABEAEREAABERAAAREQAAEREAABERABEAAAARAAAAEQAAAAAAAAAAEREAABERAAAREQAAEREAABERAAAREQAAERERAAAAAAAREQAAEREAABERAAAREQAAEREAABERABEREQAAERERABEREQAREREAERERABEREQAREQAAEREAABERABEREQAREREAERERABEREQAREREAABERAAAREQAAEREAAAAAAAAREQAAEREAABERAAAREQAAEREAABERAAAAABEAAAAAABERAAAREQAAEREAABERAAAREQAAEREAEQAAAAAAABEAAAARABERAAAREQAAEREAABERAAAREQAAEREAEQAAABEAAAAAEREAABERAAAREQAAEREAABERAAAREQAAAAAAABERAAAREQAAEREAAAAAEQAAABEAAAARAAAAEQAAAAAAEREAABERAAAREQARAAAAEQAAABEAAAARAAAAAAAAEQAAABEAAAARAAAAEQAAABEAAAARAAAAEQAAABERAAAAEQAAABEAAAARAAAAEQAAABEAAAARAAAAEQAAAAAAAAAAERERABEREQAREREAAAAAAAAAAAAAAAAAAAARAAAAABEREQAREREAERERAAAREQAAEREAABERABEAAAAAAAARAAAAEQAREQAAEREAABERAAAREREAERERABEREREAAAARAAAAAAAAAAAAAAAAAAAAERERABEREQAREREA"),snake:__b64("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AQBkEwAcAQA3AAAAURczAAEAGwAcAQA3AAAAUggCAAAfAAMgEGQCMAEbMA4BAAEAkAECEBRi0AYwZBINAAoE/w8UEgcaEhMAERP/BgAMBBoOFQQR/wAREQ4WEhoMDhUE/wAAAAAAAAAAAAAAADMzMzMzMzMzAAAAAAAAAAAAAAAAAAAAAAAREAAAEBAAABAQAAAQEAAAERAAAAAAAAAAAAAAAAAAAAEAAAABAAAAAQAAAAEAAAABAAAAAAAAAAAAAAAAAAAAERAAAAAQAAAREAAAEAAAABEQAAAAAAAAAAAAAAAAAAAREAAAABAAABEQAAAAEAAAERAAAAAAAAAAAAAAAAAAABAQAAAQEAAAERAAAAAQAAAAEAAAAAAAAAAAAAAAAAAAERAAABAAAAAREAAAABAAABEQAAAAAAAAAAAAAAAAAAAREAAAEAAAABEQAAAQEAAAERAAAAAAAAAAAAAAAAAAABEQAAAAEAAAAQAAAAEAAAABAAAAAAAAAAAAAAAAAAAAERAAABAQAAAREAAAEBAAABEQAAAAAAAAAAAAAAAAAAAREAAAEBAAABEQAAAAEAAAERAAAAAAAAAAAAAAAAAAAAEAAAAQEAAAERAAABAQAAAQEAAAAAAAAAAAAAAAAAAAEQAAABAQAAARAAAAEBAAABEAAAAAAAAAAAAAAAAAAAABEAAAEAAAABAAAAAQAAAAARAAAAAAAAAAAAAAAAAAABEAAAAQEAAAEBAAABAQAAARAAAAAAAAAAAAAAAAAAAAERAAABAAAAARAAAAEAAAABEQAAAAAAAAAAAAAAAAAAAREAAAEAAAABEAAAAQAAAAEAAAAAAAAAAAAAAAAAAAAAEQAAAQAAAAEBAAABAQAAABEAAAAAAAAAAAAAAAAAAAEBAAABAQAAAREAAAEBAAABAQAAAAAAAAAAAAAAAAAAAREAAAAQAAAAEAAAABAAAAERAAAAAAAAAAAAAAAAAAAAAQAAAAEAAAABAAABAQAAABAAAAAAAAAAAAAAAAAAAAEBAAABEAAAAQAAAAEQAAABAQAAAAAAAAAAAAAAAAAAAQAAAAEAAAABAAAAAQAAAAERAAAAAAAAAAAAAAAAAAABAQAAAREAAAERAAABAQAAAQEAAAAAAAAAAAAAAAAAAAEBAAABEQAAAREAAAERAAABAQAAAAAAAAAAAAAAAAAAABAAAAEBAAABAQAAAQEAAAAQAAAAAAAAAAAAAAAAAAABEAAAAQEAAAEQAAABAAAAAQAAAAAAAAAAAAAAAAAAAAAQAAABAQAAAQEAAAEQAAAAEQAAAAAAAAAAAAAAAAAAARAAAAEBAAABEAAAAQEAAAEBAAAAAAAAAAAAAAAAAAAAEQAAAQAAAAAQAAAAAQAAARAAAAAAAAAAAAAAAAAAAAERAAAAEAAAABAAAAAQAAAAEAAAAAAAAAAAAAAAAAAAAQEAAAEBAAABAQAAAQEAAAERAAAAAAAAAAAAAAAAAAABAQAAAQEAAAEBAAABAQAAABAAAAAAAAAAAAAAAAAAAAEBAAABAQAAAREAAAERAAABAQAAAAAAAAAAAAAAAAAAAQEAAAEBAAAAEAAAAQEAAAEBAAAAAAAAAAAAAAAAAAABAQAAABAAAAAQAAAAEAAAABAAAAAAAAAAAAAAAAAAAAERAAAAAQAAABAAAAEAAAABEQAAAAAAAAAAAAAAAAAAAREREAERERABEREQAREQAAEREAABERAAAREQAAAAAAERERABEREQAREREAABERAAAREQAAEREAABERAAAREQAAEREAABERAAAREQAAEREAABEREQAREREAERERABERAAAREQAAEREAABERAAAREQAREREAERERABEREQAAAAAAAAAAEQAAABEAAAARABEREQAREREAERERAAAAEQAAAAARAAAAEQAAABEAAAARAAAAEQAAABEAAAARAAAAAAAAEQAAABEAAAARAAAAEQAAABEAERERABEREQARERERAAAAEQAAABEAAAARAAAAEQAAABEREQAREREAERERAAAAAAAAERERABEREQAREREAAAAAAAAAAAAAAAAAERERAAAAABEREQAREREAERERAAAREQAAEREAABERABEREQAAERERABEREQAREQAAEREAABERAAAREREAERERABEREREREQAREREAAAAAAAAAAAAAAAAAERERABEREQAREREAAAAAAAAREREAERERABEREQAAAAAAAAAAAAAAAAAREREAAAAAERERABEREQAREREAABERAAAREQAAEREAERERAAAREREAERERAAAAAAAAAAAAAAAAABEREQAREREAERERERERABEREQAAEREAABERAAAREQAREREAERERABEREQAAAAAAABERAAAREQAAEREAABERAAAREQAAEREAABEREQAAAAAAEREAABERAAAREQAAEREAABERAAAREQAREREAABEREQAREREAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAREREAERERAAAREQAAEREAABERAAAREQAAEREAABERAAAAAAAAERERABEREQAREREAEREAABERAAAREQAAERERAAAAABEREQAREREAERERAAAAAAAAAAAAAAAAABEREQAAERERABEREQAAAAAAAAAAAAAAAAAREREAERERABEREREREQAREREAABERAAAREQAAEREAERERABEREQAREREAAAAAAAAREREAERERABEREQAREQAAEREAABERAAAREREAAAAAERERABEREQAREREAAAAAAAAAAAAAAAAAERERAAAREREAERERABERAAAREQAAEREAABEREQAREREAERERERERABEREQAAEREAABERAAAREQAREREAERERABEREQAAAAAAABEREQAREREAERERAAAAAAAAAAAAAAAAAAAAEQAAAAAREREAERERABEREQAAEREAABERAAAREQARAAAAAAAAEQAAABEAEREAABERAAAREQAAEREAABERAAAREQARAAAAEQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAERERABEREQAREREAEREAABERAAAREQAAERERAAAAABEREQAREREAERERAAAREQAAEREAABERABEREQAAERERABEREQAREQAAEREAABERAAAREREAERERABEREREREQAREREAABERAAAREQAAEREAERERABEREQAREREAAAAAAAAREREAERERABEREQAREQAAEREAABERAAAREREAAAAAERERABEREQAREREAABERAAAREQAAEREAERERAAAREREAERERAAAAAAAAAAAAAAAAABEREQAREREAERERERERABEREQAAEREAABERAAAREQAREREAERERABEREQAAAAAAAAAAEQAAABEAAAARABERAAAREQAAEREAABEREQAAAAARAAAAEQAAABEAAAAAEREAABERAAAREQAREREAABEREQAREREAEREAABERAAAREQAAEREAABERAAAREQAREREAERERAAAREQAAEREAABERAAAREQAAEREAABERAAAAAAAAERERABEREQAREREAEREAABERAAAREQAAERERAAAAABEAAAARAAAAEQAAAAAREQAAEREAABERABEAAAAAERERABEREQAREQAAEREAABERAAAREREAERERABEREREAAAARAAAAABERAAAREQAAEREAEQAAABEAAAARAAAAAAAAAAAAABEAAAARAAAAEQAREQAAEREAABERAAAREQAAAAAAERERABEREQAREREAAAAAAAAAAAAAAAAAAAAAAAAREQAAEREAABERAAAREQAAEREAAAAAEQAAABEAAAARAAAAAAAAAAAAAAAAAAAAAAAAAAAREREAERERABEREQAAAAAAABEREQAREREAERERABERAAAREQAAEREAABERAAAAAAARAAAAEQAAABEAAAAAEREAABERAAAREQAAEREAABERAAAREQAAEREAABERAAAREQAAERERABEREQAREREAEREAABERAAAREQAAEREAABERABEAAAARAAAAEQAAAAAAAAAAERERABEREQAREREAEREAABERAAAREQAAERERAAAAABEREQAREREAERERAAAAAAAAAAAAAAAAABEAAAAAERERABEREQAREQAAEREAABERAAAREREAERERABEREREAAAARAAAAAAAAAAAAAAAAAAAAERERABEREQAREREAAAAAAAAREREAERERABEREQAREQAAEREAABERAAAREREAAAAAERERABEREQAREREAAAAAAAAAAAAAAAAAEQAAAAAREREAERERABERAAAREQAAEREAABERAAAREQAAEREAEQAAABEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEQAAABEAAAARABERAAAREQAAEREAABERAAAAAAAREREAERERABEREQAAAAAAAAAAAAAAAAAAEREAABERAAAREQAAEREAABERAAAREQAAAAARAAAAEQAAABEAEREAABERAAAREQAAEREAABERABEREQAREREAERERAAAAAAAAEREAABERAAAREQAAEREAABERAAAREQAAERERAAAAAAAREQAAEREAABERAAAREQAAEREAABERABEREQAAERERABEREQAREQAAEREAABERAAAREQAAEREAABERABEREQAREREAABERAAAREQAAEREAABERAAAREQAAEREAAAAAAAAREREAERERABEREQAAABEAAAARAAAAEQAAABEAAAAAERERABEREQAREREAEQAAABEAAAARAAAAEQAAAAAAABEAAAARAAAAEQAAABEAAAARABEREQAREREAEREREQAAABEAAAARAAAAEQAAABEAAAAREREAERERABEREQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEREAABERAAAREQAAEREAABERAAAREQAAEREAAAAAAAAAAAAAEREAABERAAAREQAAAAARAAAAEQAAABEAEREAABERAAAREQAAEREAABERABEAAAARAAAAEQAAAAAAAAAAEREAABERAAAREQAAERERABEREQAREREAEREAAAAAAAAREQAAEREAABERABEAAAARAAAAEQAAAAAAAAAAEREAABERAAAREREAERERABEREQAREQAAEREAABERAAAAAAAAAAAAEQAAABEAAAARAAAAABERAAAREQAAEREAAAAAAAAREQAAEREAABERAAAREQAAEREAABERAAAREQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAREQAAEREAABERAAAREQAAEREAABEREQAREREAERERAAAAAAAAAAAAAAAAAAAAAAAAAAAREREAERERABEREQAAAAAAABERAAAREQAAEREAABEREQAREREAERERABEREQAAAAAAEREAABERAAAREQAREREAERERABEREQAREREAABEREQAREREAEREAABERAAAREQAAEREAABERAAAREQAREREAERERAAAREQAAEREAABERAAAREQAAEREAABERAAAAAAAAEREAABERAAAREQAAERERABEREQAREREAERERAAAAAAAREQAAEREAABERABEREQAREREAERERABEREQAAERERABEREQAREREAERERABEREQAREQAAEREAABERABEREQAREREAERERABEREQAREREAABERAAAREQAAEREAAAAAAAAAABEAAAARAAAAEQAREQAAEREAABERAAAREQAAAAAAEQAAABEAAAARAAAAABERAAAREQAAEREAABERAAAREQAAEREAABERAAAREQAAEREAAAAAEQAAABEAAAARABERAAAREQAAEREAABERAAAREQARAAAAEQAAABEAAAAAAAAAABEREQAREREAERERABERAAAREQAAEREAABEREQAAAAARAAAAEQAAABEAAAAAEREAABERAAAREQARAAAAABEREQAREREAEREAABERAAAREQAAEREAABERAAAREQARAAAAEQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAARAAAAEQAAABEAEREAABERAAAREQAAEREAAAAAABEAAAARAAAAEQAAAAAREQAAEREAABERAAAREQAAEREAABERAAAREREAERERABEREQAAABEAAAARAAAAEQAREQAAEREAEQAAABEAAAARAAAAERERABEREQAREREAAAAAAAAREREAERERABEREQAREQAAEREAABERAAAREREAAAAAEQAAABEAAAARAAAAABERAAAREQAAEREAEQAAAAAREREAERERABERAAAREQAAEREAABERAAAREQAAEREAEQAAABEAAAAAEREAABERAAAREQAAEREAABERAAAREQAAAAAAAAAAEQAAABEAAAARABERAAAREQAAEREAAAAAEQAAAAAREREAERERABEREQAAAAAAAAAAAAAAAAARAAAAAAAAEQAAABEAAAAAAAAAAAAAAAAAERERABEREQARERERAAAAEQAAAAAREQAAEREAABERABEAAAARAAAAEQAAAAAAAAAAERERABEREQAREREAAAARAAAAEQAAABEAAAARAAAAABEREQAREREAERERABEAAAARAAAAEQAAABEAAAAAAAARAAAAEQAAABEAAAARAAAAEQAAABEAAAARAAAAEREAAAARAAAAEQAAABEAAAARAAAAEQAAABEAAAARAAAAAAAAAAAREQAAEREAABERAAAREQAAEREAABERAAAREQAAAAAAABERAAAREQAAEREAABERAAAREQAAEREAABERAAAREQAAEREAABERAAAREQAAEREAABEREQAREREAERERABERAAAREQAAEREAABERAAAREQAREREAERERABEREQAAAAAAABERAAAREQAAEREAABERAAAREQAAEREAABERAAAAAAAAEREAABERAAAREQAAEREAABERAAAREQAAEREAABERAAAREQAAEREAABERAAAREQAAAAARAAAAEQAAABEAEREAABERAAAREQAAEREAABERABEAAAARAAAAEQAAAAAAAAAAEREAABERAAAREQAAEREAABERAAAREQAAERERAAAAAAAREQAAEREAABERAAAREQAAEREAABERABEREQAAERERABEREQAREREAERERABEREQAREQAAEREAABERABEREQAREREAERERABEREQAREREAABERAAAREQAAEREAAAAAAAAREQAAEREAABERAAAREQAAEREAABERAAAAABEAAAAAABERAAAREQAAEREAABERAAAREQAAEREAEQAAAAAAABEAAAARABERAAAREQAAEREAABERAAAREQAAEREAEQAAABEAAAAAEREAABERAAAREQAAEREAABERAAAREQAAAAAAABERAAAREQAAEREAAAAAEQAAABEAAAARAAAAEQAAAAAAEREAABERAAAREQARAAAAEQAAABEAAAARAAAAAAAAEQAAABEAAAARAAAAEQAAABEAAAARAAAAEQAAABERAAAAEQAAABEAAAARAAAAEQAAABEAAAARAAAAEQAAAAAAAAAAERERABEREQAREREAAAAAAAAAAAAAAAAAAAARAAAAABEREQAREREAERERAAAREQAAEREAABERABEAAAAAAAARAAAAEQAREQAAEREAABERAAAREREAERERABEREREAAAARAAAAAAAAAAAAAAAAAAAAERERABEREQAREREA"),palmblast:__b64("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AAAAAAAAAAAAIiIAAiERACEREQIjMxECEzMRAhMzEQAAAAAAAAAAIiIAABESIAARERIAETMyIBEzMSARMzEgAhMzEQIRERECERERAhEREQIhEREAIRERAAIhEQAAIiIRMzEgERERIBERESAREREgERESIBEREgAREiAAIiIAAAAAAAAAAAAAAAAAAAAAABEAABERAAEiEQABIhEAERERMwAAADMAAAAzAAAAEQAAABERAAARERAAEREQABEREQAAERERABEREQAREREAARERAAEREQAAEREAAAARAAAAABEREQAREREAERERABEREAARERAAEREAABEAAAAAAAAAAAAAAAAAABEAAAERAAEREQABESIAERIiAREiIwERIjMAAAAAEQAAABEQAAARERAAIhEQACIhEQAyIhEQMyIREAERIjMBESIjABESIgABESIAARERAAABEQAAABEAAAAAMyIREDIiERAiIREAIhEQABEREAAREAAAEQAAAAAAAAAAAAAAABEREQAREREAERERABERAAAREQAAEREAABERAAAAAAAREREAERERABEREQAAEREAABERAAAREQAAEREAABERAAAREQAAEREAABERAAAREQAAERERABEREQAREREAEREAABERAAAREQAAEREAABERABEREQAREREAERERAAAAAAAAAAARAAAAEQAAABEAERERABEREQAREREAAAARAAAAABEAAAARAAAAEQAAABEAAAARAAAAEQAAABEAAAAAAAARAAAAEQAAABEAAAARAAAAEQAREREAERERABEREREAAAARAAAAEQAAABEAAAARAAAAERERABEREQAREREAAAAAAAAREREAERERABEREQAAAAAAAAAAAAAAAAAREREAAAAAERERABEREQAREREAABERAAAREQAAEREAERERAAAREREAERERABERAAAREQAAEREAABEREQAREREAERERERERABEREQAAAAAAAAAAAAAAAAAREREAERERABEREQAAAAAAABEREQAREREAERERAAAAAAAAAAAAAAAAABEREQAAAAAREREAERERABEREQAAEREAABERAAAREQAREREAABEREQAREREAAAAAAAAAAAAAAAAAERERABEREQAREREREREAERERAAAREQAAEREAABERABEREQAREREAERERAAAAAAAAEREAABERAAAREQAAEREAABERAAAREQAAERERAAAAAAAREQAAEREAABERAAAREQAAEREAABERABEREQAAERERABEREQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABEREQAREREAABERAAAREQAAEREAABERAAAREQAAEREAAAAAAAAREREAERERABEREQAREQAAEREAABERAAAREREAAAAAERERABEREQAREREAAAAAAAAAAAAAAAAAERERAAAREREAERERAAAAAAAAAAAAAAAAABEREQAREREAERERERERABEREQAAEREAABERAAAREQAREREAERERABEREQAAAAAAABEREQAREREAERERABERAAAREQAAEREAABEREQAAAAAREREAERERABEREQAAAAAAAAAAAAAAAAAREREAABEREQAREREAEREAABERAAAREQAAERERABEREQAREREREREAERERAAAREQAAEREAABERABEREQAREREAERERAAAAAAAAERERABEREQAREREAAAAAAAAAAAAAAAAAAAARAAAAABEREQAREREAERERAAAREQAAEREAABERABEAAAAAAAARAAAAEQAREQAAEREAABERAAAREQAAEREAABERABEAAAARAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAREREAERERABEREQAREQAAEREAABERAAAREREAAAAAERERABEREQAREREAABERAAAREQAAEREAERERAAAREREAERERABERAAAREQAAEREAABEREQAREREAERERERERABEREQAAEREAABERAAAREQAREREAERERABEREQAAAAAAABEREQAREREAERERABERAAAREQAAEREAABEREQAAAAAREREAERERABEREQAAEREAABERAAAREQAREREAABEREQAREREAAAAAAAAAAAAAAAAAERERABEREQAREREREREAERERAAAREQAAEREAABERABEREQAREREAERERAAAAAAAAAAARAAAAEQAAABEAEREAABERAAAREQAAERERAAAAABEAAAARAAAAEQAAAAAREQAAEREAABERABEREQAAERERABEREQAREQAAEREAABERAAAREQAAEREAABERABEREQAREREAABERAAAREQAAEREAABERAAAREQAAEREAAAAAAAAREREAERERABEREQAREQAAEREAABERAAAREREAAAAAEQAAABEAAAARAAAAABERAAAREQAAEREAEQAAAAAREREAERERABERAAAREQAAEREAABEREQAREREAEREREQAAABEAAAAAEREAABERAAAREQARAAAAEQAAABEAAAAAAAAAAAAAEQAAABEAAAARABERAAAREQAAEREAABERAAAAAAAREREAERERABEREQAAAAAAAAAAAAAAAAAAAAAAABERAAAREQAAEREAABERAAAREQAAAAARAAAAEQAAABEAAAAAAAAAAAAAAAAAAAAAAAAAABEREQAREREAERERAAAAAAAAERERABEREQAREREAEREAABERAAAREQAAEREAAAAAABEAAAARAAAAEQAAAAAREQAAEREAABERAAAREQAAEREAABERAAAREQAAEREAABERAAAREREAERERABEREQAREQAAEREAABERAAAREQAAEREAEQAAABEAAAARAAAAAAAAAAAREREAERERABEREQAREQAAEREAABERAAAREREAAAAAERERABEREQAREREAAAAAAAAAAAAAAAAAEQAAAAAREREAERERABERAAAREQAAEREAABEREQAREREAEREREQAAABEAAAAAAAAAAAAAAAAAAAAREREAERERABEREQAAAAAAABEREQAREREAERERABERAAAREQAAEREAABEREQAAAAAREREAERERABEREQAAAAAAAAAAAAAAAAARAAAAABEREQAREREAEREAABERAAAREQAAEREAABERAAAREQARAAAAEQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAARAAAAEQAAABEAEREAABERAAAREQAAEREAAAAAABEREQAREREAERERAAAAAAAAAAAAAAAAAAAREQAAEREAABERAAAREQAAEREAABERAAAAABEAAAARAAAAEQAREQAAEREAABERAAAREQAAEREAERERABEREQAREREAAAAAAAAREQAAEREAABERAAAREQAAEREAABERAAAREREAAAAAABERAAAREQAAEREAABERAAAREQAAEREAERERAAAREREAERERABERAAAREQAAEREAABERAAAREQAAEREAERERABEREQAAEREAABERAAAREQAAEREAABERAAAREQAAAAAAABEREQAREREAERERAAAAEQAAABEAAAARAAAAEQAAAAAREREAERERABEREQARAAAAEQAAABEAAAARAAAAAAAAEQAAABEAAAARAAAAEQAAABEAERERABEREQARERERAAAAEQAAABEAAAARAAAAEQAAABEREQAREREAERERAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAREQAAEREAABERAAAREQAAEREAABERAAAREQAAAAAAAAAAAAAREQAAEREAABERAAAAABEAAAARAAAAEQAREQAAEREAABERAAAREQAAEREAEQAAABEAAAARAAAAAAAAAAAREQAAEREAABERAAAREREAERERABEREQAREQAAAAAAABERAAAREQAAEREAEQAAABEAAAARAAAAAAAAAAAREQAAEREAABEREQAREREAERERABERAAAREQAAEREAAAAAAAAAAAARAAAAEQAAABEAAAAAEREAABERAAAREQAAAAAAABERAAAREQAAEREAABERAAAREQAAEREAABERAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABERAAAREQAAEREAABERAAAREQAAERERABEREQAREREAAAAAAAAAAAAAAAAAAAAAAAAAABEREQAREREAERERAAAAAAAAEREAABERAAAREQAAERERABEREQAREREAERERAAAAAAAREQAAEREAABERABEREQAREREAERERABEREQAAERERABEREQAREQAAEREAABERAAAREQAAEREAABERABEREQAREREAABERAAAREQAAEREAABERAAAREQAAEREAAAAAAAAREQAAEREAABERAAAREREAERERABEREQAREREAAAAAABERAAAREQAAEREAERERABEREQAREREAERERAAAREREAERERABEREQAREREAERERABERAAAREQAAEREAERERABEREQAREREAERERABEREQAAEREAABERAAAREQAAAAAAAAAAEQAAABEAAAARABERAAAREQAAEREAABERAAAAAAARAAAAEQAAABEAAAAAEREAABERAAAREQAAEREAABERAAAREQAAEREAABERAAAREQAAAAARAAAAEQAAABEAEREAABERAAAREQAAEREAABERABEAAAARAAAAEQAAAAAAAAAAERERABEREQAREREAEREAABERAAAREQAAERERAAAAABEAAAARAAAAEQAAAAAREQAAEREAABERABEAAAAAERERABEREQAREQAAEREAABERAAAREQAAEREAABERABEAAAARAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABEAAAARAAAAEQAREQAAEREAABERAAAREQAAAAAAEQAAABEAAAARAAAAABERAAAREQAAEREAABERAAAREQAAEREAABEREQAREREAERERAAAAEQAAABEAAAARABERAAAREQARAAAAEQAAABEAAAAREREAERERABEREQAAAAAAABEREQAREREAERERABERAAAREQAAEREAABEREQAAAAARAAAAEQAAABEAAAAAEREAABERAAAREQARAAAAABEREQAREREAEREAABERAAAREQAAEREAABERAAAREQARAAAAEQAAAAAREQAAEREAABERAAAREQAAEREAABERAAAAAAAAAAARAAAAEQAAABEAEREAABERAAAREQAAAAARAAAAABEREQAREREAERERAAAAAAAAAAAAAAAAABEAAAAAAAARAAAAEQAAAAAAAAAAAAAAAAAREREAERERABEREREAAAARAAAAABERAAAREQAAEREAEQAAABEAAAARAAAAAAAAAAAREREAERERABEREQAAABEAAAARAAAAEQAAABEAAAAAERERABEREQAREREAEQAAABEAAAARAAAAEQAAAAAAABEAAAARAAAAEQAAABEAAAARAAAAEQAAABEAAAAREQAAABEAAAARAAAAEQAAABEAAAARAAAAEQAAABEAAAAAAAAAABERAAAREQAAEREAABERAAAREQAAEREAABERAAAAAAAAEREAABERAAAREQAAEREAABERAAAREQAAEREAABERAAAREQAAEREAABERAAAREQAAERERABEREQAREREAEREAABERAAAREQAAEREAABERABEREQAREREAERERAAAAAAAAEREAABERAAAREQAAEREAABERAAAREQAAEREAAAAAAAAREQAAEREAABERAAAREQAAEREAABERAAAREQAAEREAABERAAAREQAAEREAABERAAAAABEAAAARAAAAEQAREQAAEREAABERAAAREQAAEREAEQAAABEAAAARAAAAAAAAAAAREQAAEREAABERAAAREQAAEREAABERAAAREREAAAAAABERAAAREQAAEREAABERAAAREQAAEREAERERAAAREREAERERABEREQAREREAERERABERAAAREQAAEREAERERABEREQAREREAERERABEREQAAEREAABERAAAREQAAAAAAABERAAAREQAAEREAABERAAAREQAAEREAAAAAEQAAAAAAEREAABERAAAREQAAEREAABERAAAREQARAAAAAAAAEQAAABEAEREAABERAAAREQAAEREAABERAAAREQARAAAAEQAAAAAREQAAEREAABERAAAREQAAEREAABERAAAAAAAAEREAABERAAAREQAAAAARAAAAEQAAABEAAAARAAAAAAAREQAAEREAABERABEAAAARAAAAEQAAABEAAAAAAAARAAAAEQAAABEAAAARAAAAEQAAABEAAAARAAAAEREAAAARAAAAEQAAABEAAAARAAAAEQAAABEAAAARAAAAAAAAAAAREREAERERABEREQAAAAAAAAAAAAAAAAAAABEAAAAAERERABEREQAREREAABERAAAREQAAEREAEQAAAAAAABEAAAARABERAAAREQAAEREAABEREQAREREAEREREQAAABEAAAAAAAAAAAAAAAAAAAAREREAERERABEREQA=")}};
})();
