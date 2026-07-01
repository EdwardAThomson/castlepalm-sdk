'use strict'
// CastlePalm CPU core v0 — deterministic fetch/decode/execute for Candidate A.
//
// Flat 24-bit little-endian bus with the docs/MEMORY_MAP.md regions. MMIO and the PPU
// port window are dispatched to a pluggable bus object (wired to the PPU + input
// register later); unmapped reads return 0, ROM writes are ignored. Provisional,
// no cycle table yet (step() counts 1 per instruction).

const isa = require('./isa.js')
const { VECTOR_BASE, vectorAddr } = isa

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

  // Decode the instruction at PC into a { name, opcode, values, length } object.
  // Retained for tooling/introspection (the disassembler/debugger and tests use
  // isa.decode directly); step() no longer calls this, so the allocation it does
  // is off the hot path. The hot loop reads operands inline (see step()).
  fetch() {
    const op = this.read8(this.PC), len = isa.lengthOf(op)
    const buf = new Uint8Array(len)
    for (let i = 0; i < len; i++) buf[i] = this.read8(m24(this.PC + i))
    return isa.decode(buf, 0)
  }

  // Allocation-free fetch/decode/execute. Operands are read inline from the bus
  // (no Uint8Array, no decode object, no `values` array, no per-step register
  // unpack arrays) and dispatch is on the numeric opcode byte (a dense integer
  // jump) instead of the decoded string `name`. Semantics — operand order,
  // sign-extension (s8/s16), flag effects, shift carry reads, and PC math — are
  // byte-identical to the decode-based reference; tests/determinism.test.js guards
  // that against every future edit.
  step() {
    if (this.halted || this.waiting) return 0
    const at = this.PC
    const R = this.R, A = this.A, F = this.F
    const op = this.read8(at)
    let p = m24(at + 1)            // cursor over operands; advances as we read

    // inline operand readers (advance p, no allocation). The regs byte packs the
    // first operand in the hi nibble (x/a) and the second in the lo nibble (y/m/b).
    let rb = 0, x = 0, y = 0
    const readRegs = () => { rb = this.read8(p); p = m24(p + 1); x = (rb >> 4) & 0xf; y = rb & 0xf }
    const readImm8 = () => { const t = this.read8(p); p = m24(p + 1); return t }
    const readImm16 = () => { const t = this.read16(p); p = m24(p + 2); return t }
    const readAddr24 = () => { const t = this.read24(p); p = m24(p + 3); return t }

    let next                       // set only by control flow; otherwise = address after operands
    let cost = 1                    // cycle cost returned to run() (1 default; MUL/DIV are heavier)
    switch (op) {
      case 0x00: break                                                            // NOP
      case 0x01: { readRegs(); const i = readImm16(); R[x] = m16(i); break }       // MOV.i
      case 0x02: { readRegs(); const i = readImm8(); R[x] = i & 0xff; break }      // MOV.b
      case 0x03: { readRegs(); R[x] = R[y]; break }                               // MOV.r
      case 0x04: { readRegs(); const a = readAddr24(); A[x] = m24(a); break }      // LDA
      case 0x05: { readRegs(); A[x] = this.read24(A[y]); break }                  // LDADDR
      case 0x06: { readRegs(); A[x] = A[y]; break }                              // MOVA

      case 0x10: { readRegs(); R[x] = this.read16(A[y]); break }                                   // LDW.ind
      case 0x11: { readRegs(); const d = readImm8(); R[x] = this.read16(m24(A[y] + s8(d))); break } // LDW.dsp
      case 0x12: { readRegs(); const m = (this.read8(p) >> 4) & 0xf; p = m24(p + 1); R[x] = this.read16(m24(A[y] + s16(R[m]))); break } // LDW.idx
      case 0x13: { readRegs(); const a = readAddr24(); R[x] = this.read16(a); break }               // LDW.abs
      case 0x14: { readRegs(); R[x] = this.read8(A[y]); break }                                     // LDB.ind
      case 0x15: { readRegs(); const d = readImm8(); R[x] = this.read8(m24(A[y] + s8(d))); break }  // LDB.dsp
      case 0x16: { readRegs(); const m = (this.read8(p) >> 4) & 0xf; p = m24(p + 1); R[x] = this.read8(m24(A[y] + s16(R[m]))); break } // LDB.idx
      case 0x17: { readRegs(); const a = readAddr24(); R[x] = this.read8(a); break }                // LDB.abs
      case 0x18: { readRegs(); this.write16(A[y], R[x]); break }                                    // STW.ind
      case 0x19: { readRegs(); const d = readImm8(); this.write16(m24(A[y] + s8(d)), R[x]); break } // STW.dsp
      case 0x1a: { readRegs(); const m = (this.read8(p) >> 4) & 0xf; p = m24(p + 1); this.write16(m24(A[y] + s16(R[m])), R[x]); break } // STW.idx
      case 0x1b: { readRegs(); const a = readAddr24(); this.write16(a, R[x]); break }               // STW.abs
      case 0x1c: { readRegs(); this.write8(A[y], R[x]); break }                                     // STB.ind
      case 0x1d: { readRegs(); const d = readImm8(); this.write8(m24(A[y] + s8(d)), R[x]); break }  // STB.dsp
      case 0x1e: { readRegs(); const m = (this.read8(p) >> 4) & 0xf; p = m24(p + 1); this.write8(m24(A[y] + s16(R[m])), R[x]); break } // STB.idx
      case 0x1f: { readRegs(); const a = readAddr24(); this.write8(a, R[x]); break }                // STB.abs

      // multiply / divide. Operands read before any write (Rs may alias R(d+1)).
      // MUL: 16x16 -> 32-bit; low word -> Rd, high word -> R(d+1 mod 8). N/Z reflect
      // the full 32-bit result; V,C cleared. DIV: dividend R(d+1):Rd / Rs -> quotient
      // -> Rd, remainder -> R(d+1); V set on divide-by-zero or quotient overflow
      // (result 0 on div-by-zero); N/Z reflect the 16-bit quotient; C cleared.
      case 0x20: { readRegs(); const hx = (x + 1) & 7, a = R[x], b = R[y]; const P = (a * b) >>> 0    // MULU
                   R[x] = P & 0xffff; R[hx] = (P >>> 16) & 0xffff
                   F.z = P === 0; F.n = (P & 0x80000000) !== 0; F.v = false; F.c = false; cost = 8; break }
      case 0x21: { readRegs(); const hx = (x + 1) & 7, a = s16(R[x]), b = s16(R[y]); const P = a * b   // MULS
                   R[x] = P & 0xffff; R[hx] = (P >> 16) & 0xffff
                   F.z = P === 0; F.n = P < 0; F.v = false; F.c = false; cost = 8; break }
      case 0x22: { readRegs(); const hx = (x + 1) & 7, lo = R[x], hi = R[hx], dv = R[y]                // DIVU
                   const D = (hi * 65536 + lo) >>> 0
                   if (dv === 0) { R[x] = 0; R[hx] = 0; F.z = true; F.n = false; F.v = true; F.c = false }
                   else { const Q = Math.floor(D / dv), Rem = D % dv; F.v = Q > 0xffff
                          R[x] = Q & 0xffff; R[hx] = Rem & 0xffff; F.z = (Q & 0xffff) === 0; F.n = (Q & 0x8000) !== 0; F.c = false }
                   cost = 16; break }
      case 0x23: { readRegs(); const hx = (x + 1) & 7, lo = R[x], hi = s16(R[hx]), dv = s16(R[y])      // DIVS
                   const D = hi * 65536 + lo
                   if (dv === 0) { R[x] = 0; R[hx] = 0; F.z = true; F.n = false; F.v = true; F.c = false }
                   else { const Q = Math.trunc(D / dv), Rem = D - Q * dv; F.v = (Q > 32767 || Q < -32768)
                          R[x] = Q & 0xffff; R[hx] = Rem & 0xffff; F.z = (Q & 0xffff) === 0; F.n = (Q & 0x8000) !== 0; F.c = false }
                   cost = 16; break }

      case 0x30: { readRegs(); R[x] = this.add16(R[x], R[y]); break }                  // ADD.r
      case 0x31: { readRegs(); const i = readImm16(); R[x] = this.add16(R[x], m16(i)); break } // ADD.i
      case 0x32: { readRegs(); R[x] = this.sub16(R[x], R[y]); break }                  // SUB.r
      case 0x33: { readRegs(); const i = readImm16(); R[x] = this.sub16(R[x], m16(i)); break } // SUB.i
      case 0x34: { readRegs(); R[x] = this.adc16(R[x], R[y]); break }                  // ADC.r
      case 0x35: { readRegs(); R[x] = this.sbc16(R[x], R[y]); break }                  // SBC.r
      case 0x36: { readRegs(); this.sub16(R[x], R[y]); break }                         // CMP.r
      case 0x37: { readRegs(); const i = readImm16(); this.sub16(R[x], m16(i)); break }// CMP.i
      case 0x38: { readRegs(); R[x] = this.sub16(0, R[x]); break }                     // NEG
      case 0x39: { readRegs(); R[x] = this.logic(R[x] & R[y]); break }                 // AND.r
      case 0x3a: { readRegs(); const i = readImm16(); R[x] = this.logic(R[x] & m16(i)); break } // AND.i
      case 0x3b: { readRegs(); R[x] = this.logic(R[x] | R[y]); break }                 // OR.r
      case 0x3c: { readRegs(); const i = readImm16(); R[x] = this.logic(R[x] | m16(i)); break } // OR.i
      case 0x3d: { readRegs(); R[x] = this.logic(R[x] ^ R[y]); break }                 // XOR.r
      case 0x3e: { readRegs(); const i = readImm16(); R[x] = this.logic(R[x] ^ m16(i)); break } // XOR.i
      case 0x3f: { readRegs(); R[x] = this.logic(~R[x]); break }                       // NOT
      case 0x40: { readRegs(); this.logic(R[x] & R[y]); break }                        // BIT.r
      case 0x41: { readRegs(); this.logic(R[x]); break }                              // TST
      case 0x42: { readRegs(); const n = readImm8() & 15; F.c = n ? !!(R[x] & (1 << (16 - n))) : F.c; R[x] = this.logic(R[x] << n); break }  // SHL.i
      case 0x43: { readRegs(); const n = readImm8() & 15; F.c = n ? !!(R[x] & (1 << (n - 1))) : F.c; R[x] = this.logic(R[x] >>> n); break }  // SHR.i
      case 0x44: { readRegs(); const n = readImm8() & 15; F.c = n ? !!(R[x] & (1 << (n - 1))) : F.c; R[x] = this.logic(s16(R[x]) >> n); break } // SAR.i
      case 0x45: { readRegs(); R[x] = this.logic(R[x] << (R[y] & 15)); break }         // SHL.r
      case 0x46: { readRegs(); R[x] = this.logic(R[x] >>> (R[y] & 15)); break }        // SHR.r
      case 0x47: { readRegs(); R[x] = this.logic(s16(R[x]) >> (R[y] & 15)); break }    // SAR.r

      case 0x48: { readRegs(); const i = readImm16(); A[x] = m24(A[x] + s16(i)); break } // ADDA.i
      case 0x49: { readRegs(); A[x] = m24(A[x] + s16(R[y])); break }                     // ADDA.r
      case 0x4a: { readRegs(); A[x] = m24(A[x] + 1); break }                             // INCA
      case 0x4b: { readRegs(); A[x] = m24(A[x] - 1); break }                             // DECA
      case 0x4c: { readRegs(); F.z = A[x] === A[y]; F.c = A[x] >= A[y]; break }          // CMPA

      // branch displacement base = address after the operand (cursor p)
      case 0x50: { const d = readImm16(); next = m24(m24(p) + s16(d)); break }                       // BRA (disp16)
      case 0x51: { const d = readImm8(); next = F.z ? m24(p + s8(d)) : m24(p); break }               // BEQ
      case 0x52: { const d = readImm8(); next = !F.z ? m24(p + s8(d)) : m24(p); break }              // BNE
      case 0x53: { const d = readImm8(); next = F.c ? m24(p + s8(d)) : m24(p); break }               // BCS
      case 0x54: { const d = readImm8(); next = !F.c ? m24(p + s8(d)) : m24(p); break }              // BCC
      case 0x55: { const d = readImm8(); next = F.n ? m24(p + s8(d)) : m24(p); break }               // BMI
      case 0x56: { const d = readImm8(); next = !F.n ? m24(p + s8(d)) : m24(p); break }              // BPL
      case 0x57: { const d = readImm8(); next = F.v ? m24(p + s8(d)) : m24(p); break }               // BVS
      case 0x58: { const d = readImm8(); next = !F.v ? m24(p + s8(d)) : m24(p); break }              // BVC
      case 0x59: { const d = readImm8(); next = (F.n !== F.v) ? m24(p + s8(d)) : m24(p); break }     // BLT
      case 0x5a: { const d = readImm8(); next = (F.n === F.v) ? m24(p + s8(d)) : m24(p); break }     // BGE
      case 0x5b: { const d = readImm8(); next = (!F.z && (F.n === F.v)) ? m24(p + s8(d)) : m24(p); break } // BGT
      case 0x5c: { const d = readImm8(); next = (F.z || (F.n !== F.v)) ? m24(p + s8(d)) : m24(p); break }  // BLE
      case 0x5d: { const d = readImm8(); next = (F.c && !F.z) ? m24(p + s8(d)) : m24(p); break }     // BHI
      case 0x5e: { const d = readImm8(); next = (!F.c || F.z) ? m24(p + s8(d)) : m24(p); break }     // BLS

      case 0x60: { const a = readAddr24(); next = a; break }                            // JMP.abs
      case 0x61: { readRegs(); next = A[x]; break }                                     // JMP.ind
      case 0x62: { const a = readAddr24(); this.push24(m24(p)); next = a; break }        // CALL.abs
      case 0x63: { readRegs(); this.push24(m24(p)); next = A[x]; break }                 // CALL.ind
      case 0x64: { next = this.pop24(); break }                                          // RET

      case 0x70: { readRegs(); this.push16(R[x]); break }                               // PUSH
      case 0x71: { readRegs(); R[x] = this.pop16(); break }                             // POP
      case 0x72: { readRegs(); this.push24(A[x]); break }                              // PUSHA
      case 0x73: { readRegs(); A[x] = this.pop24(); break }                            // POPA
      case 0x74: { next = this.pop24(); this.loadStatus(this.pop16()); break }           // IRET

      case 0x75: this.halted = true; next = at; break                                   // HALT (re-executes its own address)
      case 0x76: this.waiting = true; break                                             // WAIT (advances; frame loop clears `waiting` at vblank)
      case 0x77: this.ie = true; break                                                  // EI
      case 0x78: this.ie = false; break                                                 // DI
      default: throw new Error('unimplemented opcode 0x' + op.toString(16))
    }

    this.PC = (next === undefined) ? m24(p) : next
    this.steps++
    return cost
  }

  // `maxSteps` is now a CYCLE budget (most instructions cost 1; MUL/DIV cost more).
  // Existing carts are unaffected: they all cost 1 and stop at WAIT/HALT well inside it.
  run(maxSteps = 1e7) { let n = 0; while (n < maxSteps && !this.halted && !this.waiting) { n += this.step() } return n }
}

module.exports = { CastlePalmCPU, VECTOR_BASE }
