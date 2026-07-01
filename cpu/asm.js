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
  if (mnem === 'MULU' || mnem === 'MULS' || mnem === 'DIVU' || mnem === 'DIVS') return mk(mnem, () => [packRegs(reg(ops[0]), reg(ops[1]))])
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

// readBinary(relPath) -> bytes lets `INCBIN "file"` embed a raw binary at the current
// address. It is injected by the Node build tools (build-cart/bundle); the browser
// never assembles INCBIN carts, so asm.js itself stays filesystem-free.
function assemble(source, { origin = 0x300000, readBinary = null } = {}) {
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
      if (mnem === 'INCBIN') {
        const m = /^"([^"]*)"$/.exec(rest)
        if (!m) { err(ln, 'INCBIN expects a quoted path, e.g. INCBIN "art/ship.bin"'); return }
        if (typeof readBinary !== 'function') { err(ln, 'INCBIN is unavailable here (no binary reader provided to the assembler)'); return }
        let bytes
        try { bytes = Uint8Array.from(readBinary(m[1])) } catch (e) { err(ln, `INCBIN cannot read "${m[1]}": ${e.message}`); return }
        records.push({ type: 'incbin', bytes, size: bytes.length, line: ln })
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
      } else if (r.type === 'incbin') {
        let p = r.addr
        for (const b of r.bytes) mem.set(p++, b & 0xff)
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
