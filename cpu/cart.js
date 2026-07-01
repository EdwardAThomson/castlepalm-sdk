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
function buildCart(source, { title = '', readBinary = null, hasSave = false } = {}) {
  const r = assemble(source, { readBinary })
  return makeCart({ image: r.image, origin: r.origin, title, hasSave })
}

// parse a cartridge and return a CPU ready to run it
function boot(cartBytes, { mmio = null } = {}) {
  const cart = parseCart(cartBytes)
  const cpu = new CastlePalmCPU({ rom: cart.rom, romBase: cart.loadBase, mmio })
  return { cpu, cart }
}

module.exports = { makeCart, parseCart, buildCart, boot, MAGIC, HEADER }
