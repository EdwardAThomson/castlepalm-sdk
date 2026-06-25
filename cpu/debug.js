'use strict'
// CastlePalm headless debugger — disassembler + step/inspect/breakpoints.
// Works on a CPU core (or a System); leverages the deterministic execution.

const isa = require('./isa.js')

const s8 = v => (v << 24) >> 24
const s16 = v => (v << 16) >> 16
const hx = (x, w) => '$' + (x >>> 0).toString(16).padStart(w, '0')

const NULLARY = new Set(['NOP', 'RET', 'IRET', 'HALT', 'WAIT', 'EI', 'DI'])
const BCC = new Set(['BEQ', 'BNE', 'BCS', 'BCC', 'BMI', 'BPL', 'BVS', 'BVC', 'BLT', 'BGE', 'BGT', 'BLE', 'BHI', 'BLS'])

// format a decoded instruction at `addr` into re-assemblable text
function format(d, addr) {
  const v = d.values
  const [hi, lo] = v[0] !== undefined ? isa.unpackRegs(v[0]) : [0, 0]
  const R = n => 'R' + n, A = n => 'A' + n
  const n = d.name

  if (NULLARY.has(n)) return n
  if (BCC.has(n)) return `${n} ${hx((addr + d.length + s8(v[0])) & 0xffffff, 6)}`

  switch (n) {
    case 'MOV.i': return `MOV ${R(hi)}, #${hx(v[1], 4)}`
    case 'MOV.b': return `MOV ${R(hi)}, #${hx(v[1], 2)}`
    case 'MOV.r': return `MOV ${R(hi)}, ${R(lo)}`
    case 'LDA': return `LDA ${A(hi)}, #${hx(v[1], 6)}`
    case 'LDADDR': return `LDADDR ${A(hi)}, [${A(lo)}]`
    case 'MOVA': return `MOVA ${A(hi)}, ${A(lo)}`
    case 'NEG': return `NEG ${R(hi)}`
    case 'NOT': return `NOT ${R(hi)}`
    case 'TST': return `TST ${R(hi)}`
    case 'INCA': return `INC ${A(hi)}`
    case 'DECA': return `DEC ${A(hi)}`
    case 'CMPA': return `CMP ${A(hi)}, ${A(lo)}`
    case 'ADDA.i': return `ADD ${A(hi)}, #${hx(v[1], 4)}`
    case 'ADDA.r': return `ADD ${A(hi)}, ${R(lo)}`
    case 'BRA': return `BRA ${hx((addr + d.length + s16(v[0])) & 0xffffff, 6)}`
    case 'JMP.abs': return `JMP ${hx(v[0], 6)}`
    case 'JMP.ind': return `JMP [${A(hi)}]`
    case 'CALL.abs': return `CALL ${hx(v[0], 6)}`
    case 'CALL.ind': return `CALL [${A(hi)}]`
    case 'PUSH': return `PUSH ${R(hi)}`
    case 'POP': return `POP ${R(hi)}`
    case 'PUSHA': return `PUSHA ${A(hi)}`
    case 'POPA': return `POPA ${A(hi)}`
  }

  // load/store families: <LDW|LDB|STW|STB>.<ind|dsp|idx|abs>
  if (/^(LDW|LDB|STW|STB)\./.test(n)) {
    const [base, mode] = n.split('.')
    if (mode === 'ind') return `${base} ${R(hi)}, [${A(lo)}]`
    if (mode === 'dsp') return `${base} ${R(hi)}, [${A(lo)}+#${s8(v[1])}]`
    if (mode === 'idx') return `${base} ${R(hi)}, [${A(lo)}+${R(isa.unpackRegs(v[1])[0])}]`
    return `${base} ${R(hi)}, [${hx(v[1], 6)}]`              // abs
  }
  // ALU reg/imm and shifts: <MNEM>.<r|i>
  if (/\.(r|i)$/.test(n)) {
    const [base, form] = n.split('.')
    if (base === 'SHL' || base === 'SHR' || base === 'SAR') {
      return form === 'i' ? `${base} ${R(hi)}, #${v[1]}` : `${base} ${R(hi)}, ${R(lo)}`
    }
    return form === 'i' ? `${base} ${R(hi)}, #${hx(v[1], 4)}` : `${base} ${R(hi)}, ${R(lo)}`
  }
  return `??? ${hx(d.opcode, 2)}`
}

// disassemble one instruction read via read8(addr)
function disasm1(read8, addr) {
  const op = read8(addr)
  if (!isa.BYOP.has(op)) return { addr, length: 1, name: '???', text: `??? ${hx(op, 2)}` }
  const len = isa.lengthOf(op)
  const buf = new Uint8Array(len)
  for (let i = 0; i < len; i++) buf[i] = read8((addr + i) & 0xffffff)
  const d = isa.decode(buf, 0)
  return { addr, length: len, name: d.name, values: d.values, text: format(d, addr) }
}

class Debugger {
  constructor(target) {
    this.cpu = target.cpu || target          // accept a System or a CPU
    this.breakpoints = new Set()
  }
  read8(a) { return this.cpu.read8(a & 0xffffff) }
  disasm(addr) { return disasm1(a => this.cpu.read8(a), addr & 0xffffff) }
  disasmRange(addr, count) {
    const out = []; let p = addr & 0xffffff
    for (let i = 0; i < count; i++) { const d = this.disasm(p); out.push(d); p = (p + d.length) & 0xffffff }
    return out
  }
  step() { const at = this.cpu.PC; const d = this.disasm(at); this.cpu.step(); return { pc: at, ...d } }
  setBreak(a) { this.breakpoints.add(a & 0xffffff); return this }
  clearBreak(a) { this.breakpoints.delete(a & 0xffffff); return this }
  // run until a breakpoint, halt/wait, or the step budget; resumable across a bp.
  run(maxSteps = 1e7) {
    let n = 0
    while (n < maxSteps && !this.cpu.halted && !this.cpu.waiting) {
      this.cpu.step(); n++
      if (this.breakpoints.has(this.cpu.PC)) return { reason: 'breakpoint', pc: this.cpu.PC, steps: n }
    }
    const reason = this.cpu.halted ? 'halt' : this.cpu.waiting ? 'wait' : 'budget'
    return { reason, pc: this.cpu.PC, steps: n }
  }
  state() {
    const c = this.cpu
    return { R: Array.from(c.R), A: c.A.slice(), PC: c.PC, SP: c.SP, F: { ...c.F }, halted: c.halted, waiting: c.waiting }
  }
  dump(addr, len) { const o = []; for (let i = 0; i < len; i++) o.push(this.cpu.read8((addr + i) & 0xffffff)); return o }
  // human-readable snapshot: registers + the next few instructions
  format() {
    const c = this.cpu, f = c.F
    const flags = `${f.z ? 'Z' : '-'}${f.n ? 'N' : '-'}${f.c ? 'C' : '-'}${f.v ? 'V' : '-'}`
    const regs = Array.from(c.R, (r, i) => `R${i}=${hx(r, 4)}`).join(' ')
    const aregs = c.A.map((a, i) => `A${i}=${hx(a, 6)}`).join(' ')
    const dis = this.disasmRange(c.PC, 4).map(d => `  ${hx(d.addr, 6)}: ${d.text}`).join('\n')
    return `PC=${hx(c.PC, 6)} SP=${hx(c.SP, 6)} [${flags}]\n${regs}\n${aregs}\n${dis}`
  }
}

module.exports = { Debugger, disasm1, format }
