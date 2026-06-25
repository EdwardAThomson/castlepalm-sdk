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
