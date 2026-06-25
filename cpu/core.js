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
