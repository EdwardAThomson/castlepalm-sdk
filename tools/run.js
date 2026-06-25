#!/usr/bin/env node
'use strict'
// Build (or load) a CastlePalm cart, run it headlessly, and save a PNG screenshot.
// Great for a fast edit -> build -> see-it loop without a browser.
//
//   node tools/run.js <in.asm|in.cpc> [frames] [out.png] [--start]
//     frames   how many frames to run (default 1)
//     out.png  output image (default: input name + .png)
//     --start  tap START once before running (to get past a title screen)
//
const fs = require('fs')
const zlib = require('zlib')
const { buildCart } = require('../cpu/cart.js')
const { System } = require('../system.js')

const args = process.argv.slice(2)
const flags = args.filter(a => a.startsWith('--'))
const pos = args.filter(a => !a.startsWith('--'))
const input = pos[0]
if (!input) { console.error('usage: run.js <in.asm|in.cpc> [frames] [out.png] [--start]'); process.exit(2) }
const frames = parseInt(pos[1] || '1', 10)
const out = pos[2] || input.replace(/\.[^.]+$/, '') + '.png'
const pressStart = flags.includes('--start')

const cart = (input.endsWith('.cpc') || input.endsWith('.cplm'))
  ? new Uint8Array(fs.readFileSync(input))
  : buildCart(fs.readFileSync(input, 'utf8'), { title: '' })

const W = 320, H = 224
const sys = new System(cart)
let fb = sys.runFrame()
if (pressStart) { sys.setInput(256); sys.runFrame(); sys.setInput(0) }   // 256 = START
for (let i = 1; i < frames; i++) fb = sys.runFrame()

// framebuffer is Uint32 0xAABBGGRR; expand to RGBA bytes at 2x (nearest) for legibility
const S = 2, OW = W * S, OH = H * S
const rgba = Buffer.alloc(OW * OH * 4)
for (let y = 0; y < OH; y++) for (let x = 0; x < OW; x++) {
  const v = fb[((y / S) | 0) * W + ((x / S) | 0)] >>> 0
  const o = (y * OW + x) * 4
  rgba[o] = v & 255; rgba[o + 1] = (v >> 8) & 255; rgba[o + 2] = (v >> 16) & 255; rgba[o + 3] = 255
}
fs.writeFileSync(out, encodePNG(OW, OH, rgba))
console.log(`ran ${frames} frame(s)${pressStart ? ' (START pressed)' : ''} -> ${out}`)

// ---- minimal PNG encoder (node's zlib, no external deps) ----
function encodePNG(w, h, rgba) {
  const stride = w * 4
  const raw = Buffer.alloc((stride + 1) * h)
  for (let y = 0; y < h; y++) { raw[y * (stride + 1)] = 0; rgba.copy(raw, y * (stride + 1) + 1, y * stride, y * stride + stride) }
  const ihdr = Buffer.alloc(13)
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 6 // 8-bit RGBA
  const sig = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])
  return Buffer.concat([sig, chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))])
}
function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length, 0)
  const body = Buffer.concat([Buffer.from(type, 'ascii'), data])
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(body), 0)
  return Buffer.concat([len, body, crc])
}
var CRCT
function crc32(buf) {
  if (!CRCT) { CRCT = []; for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1); CRCT[n] = c >>> 0 } }
  let c = 0xFFFFFFFF
  for (let i = 0; i < buf.length; i++) c = CRCT[(c ^ buf[i]) & 255] ^ (c >>> 8)
  return (c ^ 0xFFFFFFFF) >>> 0
}
