#!/usr/bin/env node
'use strict'
// PALMBLAST — 16-bit art generator.
//
// Draws every PalmBlast graphic from code (procedural pixel art) inside the CastlePalm
// PPU contract: 8x8 4bpp tiles, one 15-colour palette bank per tile, BG0 + BG1 64x64
// maps, square sprites. Writes one binary the cart INCBINs and rewrites the EQU block
// in palmblast.asm (between the ART-EQU markers) so the offsets never drift.
//
//   node examples/palmblast/gen_art.js            # writes art.bin + the EQUs in palmblast.asm
//   node examples/palmblast/gen_art.js --png DIR  # also dumps sprite-sheet / backdrop PNGs
//
// Only the look changes: the arena is still the 13x11 grid of 16x16 cells, the knights
// keep their 16x16 hitboxes (drawn as 32x32 sprites at (px-8, py-16) so the helmet
// rises above the cell), and bombs/flames still sit one per cell.
//
// VRAM: tile 0 is blank; every art tile follows it in one contiguous run (tiles
// 1..ART_NT), so the boot loads them with a single DMA.
//
// Binary layout (all little-endian); each section's byte offset is exported as an
// ART_* EQU, addressed in the cart as #artbin+ART_xxx:
//   TILES  ART_NT tiles x 32 bytes (VRAM tiles 1..ART_NT)
//   PAL    256 words: the whole palette (entry 0 = sky line 0)
//   SKY    224 words: per-scanline backdrop colour (hblank handler)
//   MAP1   BG1 backdrop, row-major 40 x 28 u16 (tile | bank<<11 | hflip<<15)
//   CELLS  33 arena cell looks x 4 BG0 entries (TL, TR, BL, BR):
//          0..15  floor: bit0 shadow from the cell above, bit1 from the left,
//                 bit2 from the upper-left, bit3 checker parity ((cx+cy)&1)
//          16     crate (SOFT)
//          17..32 stone (HARD): 17 + border code (1 top, 2 bottom, 4 left, 8 right);
//                 17 itself is an inner pillar
//   FLPC   16 words, flame piece by neighbour mask (1 L, 2 R, 4 U, 8 D):
//          low byte = tile offset of the piece, high byte = OAM flip bits
//   FLFR   32 bytes, flame frame tile offset by time-to-live (0..31)

const fs = require('fs')
const path = require('path')
const ROOT = __dirname
const ASM = path.join(ROOT, 'palmblast.asm')
const OUT = path.join(ROOT, 'art.bin')

// ---------------- VRAM allocation ----------------
let nextTile = 1
const allocVram = n => { const t = nextTile; nextTile += n; if (nextTile > 2048) throw new Error('VRAM full'); return t }

// ---------------- colour / palettes ----------------
const c5to8 = c => (c << 3) | (c >> 2)
const hex = h => [parseInt(h.slice(1, 3), 16), parseInt(h.slice(3, 5), 16), parseInt(h.slice(5, 7), 16)]
const to555 = ([r, g, b]) => ((Math.max(0, Math.min(255, b)) >> 3) << 10) | ((Math.max(0, Math.min(255, g)) >> 3) << 5) | (Math.max(0, Math.min(255, r)) >> 3)
const from555 = v => [c5to8(v & 31), c5to8((v >> 5) & 31), c5to8((v >> 10) & 31)]
const BANKS = {}
function bank(n, name, colours) {
  if (colours.length > 15) throw new Error(`bank ${name} has too many colours`)
  const idx = {}, rgb = {}
  colours.forEach(([cn, h], i) => { idx[cn] = i + 1; rgb[i + 1] = hex(h) })
  const B = { bank: n, idx, rgb, name, colours }
  BANKS[n] = B
  return B
}

// --- BG banks 0..7 ---
const GRASS = bank(0, 'grass', [                // arena floor (entry 0 = sky backdrop)
  ['g0', '#2c6428'], ['g1', '#3b8231'], ['g2', '#4c9c3a'], ['g3', '#62b649'], ['g4', '#8cd262'],
  ['s0', '#1a3f1e'], ['s1', '#245226'],
  ['fy', '#f6e070'], ['fw', '#fff8ea'], ['fr', '#e86a7a'], ['p0', '#6e6a5a'], ['p1', '#aaa48e'],
])
const CRATE = bank(1, 'crate', [
  ['w0', '#2a160c'], ['w1', '#5a3218'], ['w2', '#8a5228'], ['w3', '#b8763a'], ['w4', '#dca15a'], ['w5', '#f2c886'],
  ['i0', '#1c1e28'], ['i1', '#464c5e'], ['i2', '#7e8698'], ['i3', '#c4cad8'],
])
const STONE = bank(2, 'stone', [
  ['k0', '#1a1824'], ['k1', '#36344a'], ['k2', '#55536a'], ['k3', '#76748a'], ['k4', '#9c9aac'], ['k5', '#c8c6d2'], ['k6', '#eeecf2'],
  ['sa0', '#6a5034'], ['sa1', '#9a7a4e'], ['sa2', '#c8a670'],
  ['mo0', '#2e5a26'], ['mo1', '#4c8a34'], ['mo2', '#82c050'],
])
const SKY = bank(3, 'sky', [                    // clouds + far island (the sky itself is the hblank gradient)
  ['cl0', '#a4bede'], ['cl1', '#d2e2f4'], ['cl2', '#ffffff'],
  ['is0', '#2a5c62'], ['is1', '#3c7c6a'], ['is2', '#5c9c74'], ['hz', '#86aac4'],
  ['l0', '#1d4a24'], ['l1', '#2f7a30'], ['l2', '#56a83c'], ['l3', '#8ed05a'],
])
const BEACH = bank(4, 'beach', [
  ['sea0', '#1c5a98'], ['sea1', '#2c78b6'], ['sea2', '#48a0d0'], ['sea3', '#92d6e8'], ['foam', '#f4fbff'],
  ['sa0', '#c49654'], ['sa1', '#dcb26e'], ['sa2', '#efcc8a'],
  ['tr0', '#43291a'], ['tr1', '#76502e'], ['tr2', '#a87646'],
  ['l0', '#1d4a24'], ['l1', '#2f7a30'], ['l2', '#56a83c'], ['l3', '#8ed05a'],
])
const BADGE = bank(5, 'badge', [
  ['ol', '#141018'], ['wd0', '#4a2c16'], ['wd1', '#7a4c26'], ['wd2', '#a8743e'], ['gd0', '#a06a10'], ['gd1', '#f0c444'],
  ['wh', '#ffffff'], ['gr0', '#1c6a28'], ['gr1', '#40b448'], ['rd0', '#8a1818'], ['rd1', '#e44a3a'],
  ['st0', '#56627c'], ['st1', '#a4b0c6'], ['st2', '#eaf0fa'],
])
const FONTG = bank(6, 'font-gold', [
  ['ol', '#2a1006'], ['t0', '#fffbd8'], ['t1', '#ffe060'], ['t2', '#f6a822'], ['t3', '#d06a14'], ['t4', '#8c3a0a'],
])
const FONTW = bank(7, 'font-white', [
  ['ol', '#121428'], ['t0', '#ffffff'], ['t1', '#eef2fa'], ['t2', '#cfd8ec'], ['t3', '#a2b0d4'], ['t4', '#6c7aaa'],
])
// --- sprite banks 8..11 ---
const knightBank = (n, name, acc) => bank(n, name, [
  ['ol', '#10101c'], ['st0', '#3a4458'], ['st1', '#6c7890'], ['st2', '#a8b4c8'], ['st3', '#eef4fc'],
  ['ac0', acc[0]], ['ac1', acc[1]], ['ac2', acc[2]], ['ac3', acc[3]],
  ['gd0', '#9a6410'], ['gd1', '#f0c040'], ['lt0', '#3a2416'], ['lt1', '#6e4628'], ['wh', '#ffffff'], ['sh', '#1a3c1c'],
])
const KN1 = knightBank(8, 'knight-p1', ['#14481c', '#23802c', '#3cb43a', '#8ae070'])
const KN2 = knightBank(9, 'knight-p2', ['#5a0c12', '#a01c22', '#e0443a', '#ff9a80'])
const BOMB = bank(10, 'bomb', [
  ['ol', '#08080e'], ['b0', '#141a2e'], ['b1', '#262f4c'], ['b2', '#3e4a72'], ['b3', '#6a7aa8'], ['wh', '#ffffff'],
  ['gd0', '#7a5a22'], ['gd1', '#d0b060'], ['fu', '#c8b48a'], ['sp0', '#ff8a1c'], ['sp1', '#ffe860'], ['sh', '#1a3c1c'],
])
const FLAME = bank(11, 'flame', [
  ['f0', '#7a1008'], ['f1', '#d63c10'], ['f2', '#ff8c1c'], ['f3', '#ffd840'], ['f4', '#fffbe0'],
])

// ---------------- canvases ----------------
class Canvas {
  constructor(w, h) { this.w = w; this.h = h; this.b = new Int8Array(w * h).fill(-1); this.i = new Uint8Array(w * h) }
  set(x, y, B, c) {
    x = Math.round(x); y = Math.round(y)
    if (x < 0 || y < 0 || x >= this.w || y >= this.h) return
    const k = y * this.w + x
    if (!c) { this.b[k] = -1; this.i[k] = 0; return }
    const i = typeof c === 'string' ? B.idx[c] : c
    if (!i) throw new Error('unknown colour ' + c + ' in ' + B.name)
    this.b[k] = B.bank; this.i[k] = i
  }
  get(x, y) { if (x < 0 || y < 0 || x >= this.w || y >= this.h) return null; const k = y * this.w + x; return this.b[k] < 0 ? null : [this.b[k], this.i[k]] }
}
const hash = (x, y, s = 0) => { let h = (x * 374761393 + y * 668265263 + s * 2147483647) | 0; h = (h ^ (h >>> 13)) * 1274126177 | 0; return ((h ^ (h >>> 16)) >>> 0) / 4294967296 }
const clamp = (v, a, b) => Math.max(a, Math.min(b, v))
const nameOf = (B, i) => B.colours[i - 1][0]

// ================= BG0: arena cells (16x16 each) =================
const SHADE = { g4: 'g2', g3: 'g1', g2: 's1', g1: 's0', g0: 's0', fy: 'g1', fw: 'g2', fr: 's1', p1: 'p0', p0: 's0' }
function floorCell(bits) {
  const cv = new Canvas(16, 16), par = (bits >> 3) & 1
  const up = bits & 1, left = bits & 2, ul = bits & 4
  for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {
    const n = hash(x, y, 3 + par)
    let c = par ? (n < 0.18 ? 'g0' : n > 0.86 ? 'g2' : 'g1') : (n < 0.16 ? 'g1' : n > 0.84 ? 'g3' : 'g2')
    if ((x + y * 3) % 7 === 0 && n > 0.5) c = par ? 'g2' : 'g3'                     // grass blades
    if (!par && hash(x, y, 9) > 0.965) c = 'g4'
    cv.set(x, y, GRASS, c)
  }
  // a few flowers / pebbles in the lighter squares (fixed spots, so tiles still dedupe)
  if (!par) { cv.set(11, 4, GRASS, 'fy'); cv.set(12, 4, GRASS, 'g1'); cv.set(4, 11, GRASS, 'fw'); cv.set(4, 12, GRASS, 'g1') }
  else { cv.set(9, 10, GRASS, 'p1'); cv.set(10, 10, GRASS, 'p0'); cv.set(9, 11, GRASS, 'p0') }
  // cast shadows from blocks up / left / up-left (light comes from the top-left)
  for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {
    const deep = (up && y < 5) || (left && x < 4) || (ul && x < 4 && y < 5)
    const edge = !deep && ((up && y === 5 && !(left && x < 4)) || (left && x === 4 && !(up && y < 5)) || (ul && ((x === 4 && y < 5) || (y === 5 && x < 4))))
    if (!deep && !edge) continue
    const [, i] = cv.get(x, y)
    let c = SHADE[nameOf(GRASS, i)] || 's0'
    if (deep) c = SHADE[c] || 's0'
    if (edge && (x + y) & 1) continue                                               // dithered soft edge
    cv.set(x, y, GRASS, c)
  }
  return cv
}
function crateCell() {
  const cv = new Canvas(16, 16)
  for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {
    let c
    if (y < 4) c = y === 0 ? 'w5' : (x & 3) === 3 ? 'w3' : 'w4'                   // lid (top face)
    else if (y === 4) c = 'w1'
    else {                                                                          // front face: planks
      const py = (y - 5) % 4
      c = py === 3 ? 'w1' : py === 0 ? 'w4' : (hash(x, y, 31) < 0.2 ? 'w2' : 'w3')
      if (y === 15) c = 'w0'
    }
    if (x === 0 || x === 15) c = y < 4 ? 'w2' : 'w0'
    if (x === 1 && y > 0 && y < 15) c = y < 4 ? 'w4' : 'w2'
    if (x === 14 && y > 4 && y < 15) c = 'w1'
    cv.set(x, y, CRATE, c)
  }
  // diagonal brace on the front face
  for (let k = 0; k < 10; k++) { const x = 3 + k, y = 14 - k; if (y > 4) { cv.set(x, y, CRATE, 'w4'); cv.set(x + 1, y, CRATE, 'w2') } }
  // iron corner brackets + rivets
  for (const [x0, y0, sx, sy] of [[1, 5, 1, 1], [14, 5, -1, 1], [1, 14, 1, -1], [14, 14, -1, -1]]) {
    for (let k = 0; k < 3; k++) { cv.set(x0 + sx * k, y0, CRATE, k ? 'i2' : 'i1'); cv.set(x0, y0 + sy * k, CRATE, 'i1') }
    cv.set(x0 + sx, y0 + sy, CRATE, 'i3')
  }
  for (const x of [2, 13]) { cv.set(x, 1, CRATE, 'i1'); cv.set(x, 2, CRATE, 'i2') }
  return cv
}
// stone block in 3/4 view: a lit top face, and a darker front face when the cell below is open
function blockCell({ front, eT, eL, eR, brick, pillar }) {
  const cv = new Canvas(16, 16), top = front ? 11 : 16
  for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {
    let c
    if (y < top) {
      if (brick) {                                                                   // wall walk: running-bond bricks
        const row = y >> 2, bx = (x + (row & 1) * 4) & 7, by = y & 3
        c = by === 3 || bx === 7 ? 'k2' : by === 0 || bx === 0 ? 'k5' : (hash((x + (row & 1) * 4) >> 3, row, 41) < 0.35 ? 'k3' : 'k4')
      } else {                                                                       // pillar cap: bevelled slab
        const ex = Math.min(x, 15 - x), ey = Math.min(y, top - 1 - y)
        c = ex === 0 || ey === 0 ? (x === 15 || y === top - 1 ? 'k2' : 'k5') : ex === 1 || ey === 1 ? (x >= 14 || y >= top - 2 ? 'k3' : 'k6') : (hash(x, y, 42) < 0.18 ? 'k3' : 'k4')
        if (pillar && ex >= 4 && ey >= 3 && (ex === 4 || ey === 3)) c = (x < 8 && y < 6) ? 'k3' : 'k5'   // carved inset
      }
      if (eT && y === 0) c = 'k6'
      if (eL && x === 0) c = y === 0 ? 'k6' : 'k5'
      if (eR && x === 15) c = 'k2'
    } else {                                                                         // front face
      const fy = y - top
      c = fy === 0 ? 'k1' : fy === 4 ? 'k0' : (x & 7) === 7 ? 'k1' : fy === 1 ? 'k3' : 'k2'
      if (eL && x === 0) c = 'k3'
      if (eR && x === 15) c = 'k0'
    }
    cv.set(x, y, STONE, c)
  }
  if (brick && eT) for (let x = 0; x < 16; x++) if (hash(x, 1, 43) < 0.3) cv.set(x, 1, STONE, 'mo1')     // moss on the outer rim
  return cv
}
const cells = []
for (let v = 0; v < 16; v++) cells.push(floorCell(v))
cells.push(crateCell())
for (let code = 0; code < 16; code++) {
  const t = !!(code & 1), b = !!(code & 2), l = !!(code & 4), r = !!(code & 8), side = l || r
  if (!code || (t && b) || (l && r)) { cells.push(blockCell({ front: true, eT: true, eL: true, eR: true, pillar: true })); continue }
  // walls: the top/bottom runs show a front face onto the arena / off the platform edge;
  // the side runs are one continuous wall walk with an edge on both sides
  cells.push(blockCell({ brick: true, front: (t && !side) || b, eT: t || (b && !side), eL: l || (r && !t && !b), eR: r || (l && !t && !b) }))
}

// ================= tile packing =================
const tiles = []                                   // { px: 64 indices, v: VRAM tile }
const tileKey = new Map([['0'.repeat(64), 0]])
function addTile(px, allowFlip) {
  const k = px.join(',')
  if (tileKey.has(k)) return { t: tileKey.get(k), h: false }
  if (allowFlip) {
    const f = []; for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x++) f.push(px[y * 8 + 7 - x])
    const fk = f.join(','); if (tileKey.has(fk)) return { t: tileKey.get(fk), h: true }
  }
  const v = allocVram(1)
  tiles.push({ px, v }); tileKey.set(k, v)
  return { t: v, h: false }
}
let remapped = 0
function packCell(cv, tx, ty) {
  const count = new Map()
  for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x++) { const b = cv.b[(ty * 8 + y) * cv.w + tx * 8 + x]; if (b >= 0) count.set(b, (count.get(b) || 0) + 1) }
  if (!count.size) return 0
  const bk = [...count.entries()].sort((a, b) => b[1] - a[1])[0][0]
  const B = BANKS[bk], px = []
  for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x++) {
    const k = (ty * 8 + y) * cv.w + tx * 8 + x
    if (cv.b[k] < 0) { px.push(0); continue }
    if (cv.b[k] === bk) { px.push(cv.i[k]); continue }
    const want = BANKS[cv.b[k]].rgb[cv.i[k]]          // one bank per tile: nearest colour of the tile's bank
    let best = 1, bd = 1e9
    for (const i of Object.values(B.idx)) { const c = B.rgb[i], d = (c[0] - want[0]) ** 2 * 2 + (c[1] - want[1]) ** 2 * 3 + (c[2] - want[2]) ** 2; if (d < bd) { bd = d; best = i } }
    px.push(best); remapped++
  }
  const r = addTile(px, true)
  if (!r.t) return 0
  return (r.t & 0x7ff) | (bk << 11) | (r.h ? 0x8000 : 0)
}
const cellEntries = []
for (const cv of cells) for (const [tx, ty] of [[0, 0], [1, 0], [0, 1], [1, 1]]) cellEntries.push(packCell(cv, tx, ty))
const bg0Tiles = tiles.length

// ================= BG1: the beach backdrop (320 x 224, static) =================
const W1 = 320, H1 = 224, HORIZON = 80, SHORE = 120
const bg1 = new Canvas(W1, H1)
function cloud(cx, cy, rx, ry) {
  for (let y = Math.floor(cy - ry * 1.4); y <= cy + ry; y++) for (let x = cx - rx; x <= cx + rx; x++) {
    let inside = false
    for (let k = -3; k <= 3; k++) {
      const px = cx + k * rx / 3.6, pr = ry * (1 - Math.abs(k) / 5) * (0.85 + hash(cx, k, 61) * 0.4), py = cy - pr * 0.3
      if (Math.hypot(x - px, (y - py) * 1.2) < pr) inside = true
    }
    if (!inside || y > cy + ry * 0.35) continue
    const lit = 1 - (y - (cy - ry * 1.3)) / (ry * 1.7) + hash(x >> 1, y, 62) * 0.12
    bg1.set(x, y, SKY, lit > 0.62 ? 'cl2' : lit > 0.3 ? 'cl1' : 'cl0')
  }
}
cloud(92, 14, 30, 7); cloud(168, 8, 22, 5); cloud(236, 16, 34, 8); cloud(130, 46, 40, 9); cloud(250, 58, 26, 6)
// far island on the horizon (seen on the title / pause screens)
for (let x = 120; x < 220; x++) {
  const u = (x - 170) / 50, h = Math.round(22 * Math.max(0, 1 - u * u) ** 1.4 + 3 * Math.sin(x / 5))
  for (let y = HORIZON - h; y < HORIZON; y++) {
    const s = (x < 170 ? 1 : -1) * (HORIZON - y) / Math.max(1, h)
    bg1.set(x, y, SKY, y > HORIZON - 3 ? 'hz' : s > 0.4 ? 'is2' : s > -0.2 ? 'is1' : 'is0')
  }
}
for (let x = 0; x < W1; x++) {
  for (let y = HORIZON - 2; y < HORIZON; y++) if (!bg1.get(x, y)) bg1.set(x, y, SKY, 'hz')
}
// sea: deep at the horizon, lighter toward the shore, with sun glints
for (let y = HORIZON; y < SHORE + 6; y++) for (let x = 0; x < W1; x++) {
  const t = (y - HORIZON) / (SHORE - HORIZON), n = hash(x >> 1, y, 71)
  let c = t < 0.3 ? 'sea0' : t < 0.65 ? (n < 0.5 - (t - 0.3) ? 'sea0' : 'sea1') : (n < 0.3 ? 'sea1' : 'sea2')
  if (hash(x >> 2, y, 72) > 0.94 && (y & 1)) c = t < 0.4 ? 'sea2' : 'sea3'
  bg1.set(x, y, BEACH, c)
}
// shore: foam line then sand
const shoreY = x => SHORE + Math.round(2.5 * Math.sin(x / 13) + 1.5 * Math.sin(x / 5.3 + 1))
for (let x = 0; x < W1; x++) {
  const sy = shoreY(x)
  for (let y = sy - 2; y < H1; y++) {
    const d = y - sy
    let c
    if (d < 0) c = 'foam'
    else if (d < 2) c = hash(x, y, 81) < 0.5 ? 'sa0' : 'sea3'
    else {
      const rip = Math.sin(x / 6 + Math.sin(y / 9) * 2.2 + y * 0.9)
      c = d < 5 ? ((x + y) & 1 && d > 2 ? 'sa1' : 'sa0') : rip > 0.93 && ((x + y) & 1) ? 'sa0' : rip < -0.9 && ((x + y) & 1) ? 'sa2' : 'sa1'
      if (hash(x, y, 83) > 0.993) c = 'sa2'
    }
    bg1.set(x, y, BEACH, c)
  }
  if (hash(x >> 3, 84) > 0.5) bg1.set(x, sy - 3, BEACH, 'sea3')
}
// palm trees in the side margins
function palm(bx, by, tx, ty, lean, seed) {
  const pts = []
  for (let i = 0; i <= 60; i++) {
    const t = i / 60, cx = bx + (tx - bx) * t + lean * Math.sin(t * Math.PI) , cy = by + (ty - by) * t
    pts.push([cx, cy, 4.2 - t * 1.6])
  }
  for (const [cx, cy, r] of pts) for (let y = Math.floor(cy - r); y <= cy + r; y++) for (let x = Math.floor(cx - r); x <= cx + r; x++) {
    const d = (x + 0.5 - cx) / r
    if (Math.abs(d) > 1 || Math.abs(y + 0.5 - cy) > 1) continue
    const ring = ((Math.round(cy) + seed) % 5)
    let c = d < -0.35 ? 'tr2' : d > 0.45 ? 'tr0' : 'tr1'
    if (ring === 0) c = d > 0.1 ? 'tr0' : 'tr1'
    bg1.set(x, y, BEACH, c)
  }
  // fronds: drooping spines with leaflets swept back and down
  const leaves = [[-2.4, 44, 2.2], [-1.7, 40, 1.6], [-0.9, 30, 0.9], [-0.2, 20, 0.3], [0.6, 28, 0.8], [1.4, 40, 1.5], [2.1, 44, 2.1], [2.9, 26, 1.4], [-3.0, 24, 1.2]]
  for (const [a0, len, droop] of leaves) {
    let px = tx, py = ty, ang = a0 + (hash(seed, a0 * 10, 91) - 0.5) * 0.3
    const dirSign = Math.sin(ang) >= 0 ? 1 : -1
    for (let s = 0; s < len; s++) {
      const t = s / len
      px += Math.sin(ang); py -= Math.cos(ang)
      ang += dirSign * droop * 0.06 * (0.3 + t)
      bg1.set(px, py, BEACH, t < 0.7 ? 'l3' : 'l2')
      if (s < 2 || (s & 1)) continue
      const L = 1 + 6.5 * Math.pow(Math.sin(Math.PI * Math.min(1, t * 1.1 + 0.08)), 0.8)
      for (const side of [-1, 1]) {
        let dx = Math.sin(ang + side * 1.05) - Math.sin(ang) * 0.6, dy = -Math.cos(ang + side * 1.05) + Math.cos(ang) * 0.6 + 0.55
        const m = Math.hypot(dx, dy); dx /= m; dy /= m
        const upper = dy < 0.35
        for (let j = 1; j <= L; j++) {
          const lx = px + dx * j, ly = py + dy * j + j * j * 0.03
          bg1.set(lx, ly, BEACH, upper ? (j < L * 0.5 ? 'l3' : 'l2') : (j < L * 0.5 ? 'l1' : 'l0'))
          bg1.set(lx + 0.5, ly + 0.5, BEACH, upper ? 'l2' : 'l0')
        }
      }
    }
  }
  for (const [ox, oy] of [[-2, 2], [2, 3], [0, 4]]) for (let y = -2; y <= 2; y++) for (let x = -2; x <= 2; x++) {
    if (x * x + y * y > 4.5) continue
    bg1.set(tx + ox + x, ty + oy + y, BEACH, x + y < -1 ? 'tr2' : x + y > 1 ? 'tr0' : 'tr1')
  }
}
palm(30, 194, 22, 52, -6, 1)
palm(292, 196, 300, 58, 7, 2)
// grass tufts and shells on the sand near the corners
function tuft(x0, y0) { for (let k = -3; k <= 3; k++) { const h = 3 + ((k + 3) % 3) + (k === 0 ? 2 : 0); for (let j = 0; j < h; j++) bg1.set(x0 + k + Math.round(k * j * 0.15), y0 - j, BEACH, j > h - 2 ? 'l3' : k < 0 ? 'l2' : 'l1') } }
for (const [x, y] of [[8, 150], [46, 168], [272, 160], [314, 146], [52, 132], [266, 136]]) tuft(x, y)
for (const [x, y] of [[14, 176], [304, 172], [40, 140]]) { bg1.set(x, y, BEACH, 'foam'); bg1.set(x + 1, y, BEACH, 'sa2'); bg1.set(x, y + 1, BEACH, 'sa0') }
// player plaques in the bottom corners: helmet in the player's colour + P1 / P2
const FONT5 = {
  A: ['01110', '10001', '10001', '11111', '10001', '10001', '10001'], B: ['11110', '10001', '10001', '11110', '10001', '10001', '11110'],
  C: ['01110', '10001', '10000', '10000', '10000', '10001', '01110'], D: ['11110', '10001', '10001', '10001', '10001', '10001', '11110'],
  E: ['11111', '10000', '10000', '11110', '10000', '10000', '11111'], F: ['11111', '10000', '10000', '11110', '10000', '10000', '10000'],
  G: ['01110', '10001', '10000', '10111', '10001', '10001', '01111'], H: ['10001', '10001', '10001', '11111', '10001', '10001', '10001'],
  I: ['01110', '00100', '00100', '00100', '00100', '00100', '01110'], J: ['00111', '00010', '00010', '00010', '00010', '10010', '01100'],
  K: ['10001', '10010', '10100', '11000', '10100', '10010', '10001'], L: ['10000', '10000', '10000', '10000', '10000', '10000', '11111'],
  M: ['10001', '11011', '10101', '10101', '10001', '10001', '10001'], N: ['10001', '11001', '10101', '10011', '10001', '10001', '10001'],
  O: ['01110', '10001', '10001', '10001', '10001', '10001', '01110'], P: ['11110', '10001', '10001', '11110', '10000', '10000', '10000'],
  Q: ['01110', '10001', '10001', '10001', '10101', '10010', '01101'], R: ['11110', '10001', '10001', '11110', '10100', '10010', '10001'],
  S: ['01111', '10000', '10000', '01110', '00001', '00001', '11110'], T: ['11111', '00100', '00100', '00100', '00100', '00100', '00100'],
  U: ['10001', '10001', '10001', '10001', '10001', '10001', '01110'], V: ['10001', '10001', '10001', '10001', '10001', '01010', '00100'],
  W: ['10001', '10001', '10001', '10101', '10101', '10101', '01010'], X: ['10001', '10001', '01010', '00100', '01010', '10001', '10001'],
  Y: ['10001', '10001', '01010', '00100', '00100', '00100', '00100'], Z: ['11111', '00001', '00010', '00100', '01000', '10000', '11111'],
  0: ['01110', '10001', '10011', '10101', '11001', '10001', '01110'], 1: ['00100', '01100', '00100', '00100', '00100', '00100', '01110'],
  2: ['01110', '10001', '00001', '00010', '00100', '01000', '11111'], 3: ['11110', '00001', '00001', '01110', '00001', '00001', '11110'],
  4: ['00010', '00110', '01010', '10010', '11111', '00010', '00010'], 5: ['11111', '10000', '11110', '00001', '00001', '10001', '01110'],
  6: ['00110', '01000', '10000', '11110', '10001', '10001', '01110'], 7: ['11111', '00001', '00010', '00100', '01000', '01000', '01000'],
  8: ['01110', '10001', '10001', '01110', '10001', '10001', '01110'], 9: ['01110', '10001', '10001', '01111', '00001', '00010', '01100'],
}
function plaque(x0, y0, acc0, acc1, label) {
  const W = 46, H = 22
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    const ex = Math.min(x, W - 1 - x), ey = Math.min(y, H - 1 - y)
    if (ex + ey < 2) continue                                                        // clipped corners
    let c = ex === 0 || ey === 0 || ex + ey === 2 ? 'ol' : ex === 1 || ey === 1 ? (y < 2 || x < 2 ? 'gd1' : 'gd0') : ((y - 2) % 6 === 5 ? 'wd0' : x < 4 || y < 4 ? 'wd2' : 'wd1')
    bg1.set(x0 + x, y0 + y, BADGE, c)
  }
  // helmet icon
  const hx = x0 + 11, hy = y0 + 11
  for (let y = -7; y <= 7; y++) for (let x = -7; x <= 7; x++) {
    const d = (x / 6.5) ** 2 + ((y + 0.5) / 6.5) ** 2
    if (d <= 1) bg1.set(hx + x, hy + y, BADGE, y > -1 && y < 2 && x > -5 && x < 5 ? 'ol' : x + y < -4 ? 'st2' : x + y < 3 ? 'st1' : 'st0')
    else if (d <= 1.35) bg1.set(hx + x, hy + y, BADGE, 'ol')
  }
  for (let y = -9; y <= -5; y++) for (let x = -2; x <= 2; x++) if (x * x + (y + 7) ** 2 <= 5) bg1.set(hx + x + 1, hy + y, BADGE, x < 0 ? acc1 : acc0)
  bg1.set(hx - 2, hy, BADGE, 'wh'); bg1.set(hx + 2, hy, BADGE, 'wh')
  // label, 5x7 glyphs at 2x2 with a dark outline
  ;[...label].forEach((ch, i) => {
    const g = FONT5[ch], gx = x0 + 22 + i * 12, gy = y0 + 4
    const on = (x, y) => x >= 0 && y >= 0 && x < 10 && y < 14 && g[y >> 1][x >> 1] === '1'
    for (let y = -1; y < 15; y++) for (let x = -1; x < 11; x++) {
      if (on(x, y)) bg1.set(gx + x, gy + y, BADGE, y < 7 ? 'wh' : 'st2')
      else if (on(x - 1, y) || on(x + 1, y) || on(x, y - 1) || on(x, y + 1) || on(x - 1, y - 1)) bg1.set(gx + x, gy + y, BADGE, 'ol')
    }
  })
}
plaque(5, 200, 'gr1', 'gr0', 'P1')
plaque(269, 200, 'rd1', 'rd0', 'P2')

const map1 = new Uint16Array(40 * 28)
for (let r = 0; r < 28; r++) for (let c = 0; c < 40; c++) map1[r * 40 + c] = packCell(bg1, c, r)
const bgTiles = tiles.length

// ================= sprites =================
const LIGHT = (() => { const v = [-0.6, -0.65, 0.6], m = Math.hypot(...v); return v.map(c => c / m) })()
// parts: {mat, ell:[cx,cy], rx, ry} | {mat, cap:[[ax,ay],[bx,by]], r:[r0,r1]} ; options: tone (flat), back (darker)
function renderRig(B, parts, S) {
  const part = new Int16Array(S * S).fill(-1), shade = new Float32Array(S * S), mat = new Array(S * S)
  parts.forEach((p, pi) => {
    for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
      const px = x + 0.5, py = y + 0.5
      let nx = 0, ny = 0
      if (p.cap) {
        const [ax, ay] = p.cap[0], [bx, by] = p.cap[1], vx = bx - ax, vy = by - ay
        const t = Math.max(0, Math.min(1, ((px - ax) * vx + (py - ay) * vy) / (vx * vx + vy * vy || 1)))
        const r = p.r[0] + (p.r[1] - p.r[0]) * t, dx = px - (ax + vx * t), dy = py - (ay + vy * t)
        if (dx * dx + dy * dy > r * r) continue
        nx = dx / r; ny = dy / r
      } else if (p.ell) {
        const dx = (px - p.ell[0]) / p.rx, dy = (py - p.ell[1]) / p.ry
        if (dx * dx + dy * dy > 1) continue
        nx = dx; ny = dy
      } else if (p.rect) {
        const [x0, y0, x1, y1] = p.rect
        if (px < x0 || px > x1 || py < y0 || py > y1) continue
      }
      const nz = Math.sqrt(Math.max(0, 1 - nx * nx - ny * ny))
      let I = p.tone !== undefined ? p.tone : nx * LIGHT[0] + ny * LIGHT[1] + nz * LIGHT[2]
      if (p.back) I -= 0.35
      const k = y * S + x
      part[k] = pi; shade[k] = I; mat[k] = p.mat
    }
  })
  const out = new Uint8Array(S * S)
  for (let k = 0; k < S * S; k++) {
    if (part[k] < 0) continue
    const m = mat[k]
    if (B.idx[m]) { out[k] = B.idx[m]; continue }
    const ramp = [0, 1, 2, 3].map(i => B.idx[m + i]).filter(Boolean)
    if (!ramp.length) throw new Error(`no material ${m} in ${B.name}`)
    const th = ramp.length === 4 ? [0.05, 0.42, 0.82] : ramp.length === 3 ? [0.15, 0.6] : [0.35]
    let s = 0; while (s < th.length && shade[k] > th[s]) s++
    out[k] = ramp[s]
  }
  for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {     // inner contour along part seams
    const k = y * S + x
    if (part[k] < 0 || parts[part[k]].noseam) continue
    for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
      const xx = x + dx, yy = y + dy
      if (xx < 0 || yy < 0 || xx >= S || yy >= S) continue
      const o = part[yy * S + xx]
      if (o > part[k] && mat[yy * S + xx] !== mat[k] && !parts[o].noseam) { const d = B.idx[mat[k] + '0']; if (d) out[k] = d; break }
    }
  }
  return outline(out, S, B.idx.ol)
}
function outline(a, S, ol) {
  const r = a.slice()
  for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) if (!a[y * S + x]) for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
    const xx = x + dx, yy = y + dy
    if (xx >= 0 && yy >= 0 && xx < S && yy < S && a[yy * S + xx]) { r[y * S + x] = ol; break }
  }
  return r
}
function dropShadow(img, S, cx, cy, rx, ry, c) {
  for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
    if (img[y * S + x]) continue
    if (((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2 <= 1) img[y * S + x] = c
  }
  return img
}

// THE KNIGHTS: chibi armoured knights, ~29 px tall in a 32x32 cell; feet on row 30.
// dir 0 = facing down (toward the viewer), 1 = up (away), 2 = right (left = h-flipped)
// step 0 = standing, 1 / 2 = the two walking strides
function knight(dir, step) {
  const P = [], sw = step === 0 ? 0 : step === 1 ? 1 : -1
  const bob = step ? 1 : 0
  if (dir === 2) {
    const hip = [15.5, 24 - bob]
    const legA = [hip[0] + 3 * sw, 29.5], legB = [hip[0] - 3 * sw, 29.5]
    P.push({ cap: [hip, legB], r: [2.0, 1.8], mat: 'st', back: true })
    P.push({ ell: [legB[0] + 0.8, legB[1] - 0.3], rx: 2.6, ry: 1.6, mat: 'lt', back: true })
    P.push({ cap: [[12, 19 - bob], [10.5 - 2 * sw, 24 - bob]], r: [1.9, 1.7], mat: 'st', back: true })   // far arm
    P.push({ ell: [15.5, 20.5 - bob], rx: 5, ry: 4.6, mat: 'ac' })                                       // tabard
    P.push({ rect: [10.5, 22.6 - bob, 20.5, 23.8 - bob], mat: 'gd', tone: 0.5 })
    P.push({ cap: [hip, legA], r: [2.0, 1.8], mat: 'st' })
    P.push({ ell: [legA[0] + 0.8, legA[1] - 0.3], rx: 2.6, ry: 1.6, mat: 'lt' })
    P.push({ cap: [[16.5, 18.5 - bob], [17.5 + 2.5 * sw, 23 - bob]], r: [2.1, 1.8], mat: 'st' })         // near arm
    P.push({ ell: [17.5 + 2.5 * sw, 23.6 - bob], rx: 1.7, ry: 1.6, mat: 'lt' })
    P.push({ cap: [[14, 5 - bob], [7, 9 - bob]], r: [2.6, 1.4], mat: 'ac' })                             // plume
    P.push({ ell: [16.5, 11.5 - bob], rx: 7, ry: 7, mat: 'st' })                                       // helmet
    P.push({ rect: [17.5, 11.2 - bob, 23.6, 13.4 - bob], mat: 'ol', noseam: true })                     // visor slit
    P.push({ rect: [20.5, 11.6 - bob, 21.5, 12.6 - bob], mat: 'wh', noseam: true })
  } else {
    const back = dir === 1
    const lf = [13, 29 - (sw > 0 ? 1 : 0)], rf = [19, 29 - (sw < 0 ? 1 : 0)]
    P.push({ cap: [[13, 24 - bob], lf], r: [1.9, 1.8], mat: 'st' })
    P.push({ cap: [[19, 24 - bob], rf], r: [1.9, 1.8], mat: 'st' })
    P.push({ ell: [lf[0], lf[1] + 0.3], rx: 2.3, ry: 1.6, mat: 'lt' })
    P.push({ ell: [rf[0], rf[1] + 0.3], rx: 2.3, ry: 1.6, mat: 'lt' })
    if (back) P.push({ ell: [16, 21 - bob], rx: 6.2, ry: 5.2, mat: 'ac', back: true })                 // cape
    P.push({ ell: [16, 20.5 - bob], rx: 5.8, ry: 4.6, mat: back ? 'ac' : 'ac' })
    P.push({ rect: [10.5, 22.6 - bob, 21.5, 23.8 - bob], mat: 'gd', tone: 0.5 })
    if (!back) P.push({ ell: [16, 20 - bob], rx: 1.6, ry: 1.8, mat: 'gd', tone: 0.8, noseam: true })    // chest boss
    P.push({ ell: [9.6, 21 + sw * 0.8 - bob], rx: 2.3, ry: 3.1, mat: 'st' })
    P.push({ ell: [22.4, 21 - sw * 0.8 - bob], rx: 2.3, ry: 3.1, mat: 'st' })
    P.push({ ell: [9.6, 23.6 + sw * 0.8 - bob], rx: 1.7, ry: 1.4, mat: 'lt' })
    P.push({ ell: [22.4, 23.6 - sw * 0.8 - bob], rx: 1.7, ry: 1.4, mat: 'lt' })
    if (!back) P.push({ ell: [16, 3.8 - bob], rx: 2.6, ry: 3.2, mat: 'ac' })                            // plume
    P.push({ ell: [16, 11.5 - bob], rx: 7.6, ry: 7, mat: 'st' })                                       // helmet
    if (back) P.push({ cap: [[16, 4 - bob], [16, 13 - bob]], r: [2.8, 2.0], mat: 'ac' })                // plume down the back
    if (!back) {
      P.push({ rect: [9.6, 11.2 - bob, 22.4, 13.6 - bob], mat: 'ol', noseam: true })                    // visor
      P.push({ rect: [12.5, 11.8 - bob, 13.5, 12.8 - bob], mat: 'wh', noseam: true })
      P.push({ rect: [18.5, 11.8 - bob, 19.5, 12.8 - bob], mat: 'wh', noseam: true })
      P.push({ rect: [15.4, 5 - bob, 16.6, 10.8 - bob], mat: 'gd', tone: 0.6, noseam: true })           // crest ridge
    }
  }
  const img = renderRig(KN1, P, 32)
  return dropShadow(img, 32, 16, 30, 7.5, 2.2, KN1.idx.sh)
}
// knight banks share index layout, so one set of tiles serves both players
for (const n of Object.keys(KN1.idx)) if (KN1.idx[n] !== KN2.idx[n]) throw new Error('knight banks out of step')

function bomb(frame) {
  const S = 16, sc = [1, 1.08, 1, 0.93][frame], r = 5.9 * sc, cx = 7.5, cy = 9.3 - (sc - 1) * 2
  const P = [{ ell: [cx, cy], rx: r, ry: r, mat: 'b' }]
  P.push({ rect: [8.6, 2.6, 11.6, 4.8], mat: 'gd', tone: 0.6 })                                     // fuse cap
  const img = renderRig(BOMB, P, S)
  for (const [x, y] of [[5, 6], [6, 6], [5, 7]]) if (img[y * S + x]) img[y * S + x] = BOMB.idx.wh  // specular
  if (img[5 * S + 4]) img[5 * S + 4] = BOMB.idx.b3
  for (const [x, y] of [[11, 2], [12, 1], [12, 0]]) img[y * S + x] = BOMB.idx.fu
  const spark = [[[13, 0], [14, 1], [13, 1]], [[14, 0], [13, 1], [15, 2]], [[13, 0], [14, 0], [14, 1]], [[12, 0], [13, 1], [14, 2]]][frame]
  spark.forEach(([x, y], i) => { img[y * S + x] = i === 0 ? BOMB.idx.wh : i === 1 ? BOMB.idx.sp1 : BOMB.idx.sp0 })
  return dropShadow(img, S, 7.8, 14.8, 6.2, 1.4, BOMB.idx.sh)
}

// flame pieces: 0 centre (plus), 1 end-h (open left, tip right), 2 mid-h, 3 end-v (open top, tip
// bottom), 4 mid-v. The band wobble repeats every 16 px so neighbouring pieces join up.
function flamePiece(kind, frame) {
  const S = 16, W = [6.6, 5.6, 5.6, 3.4][frame], ph = [0, 1.7, 3.6, 0.9][frame]
  const band = (u, v, end) => {                     // u along the band (0..16), v across (centre 7.5)
    const w = W + 0.9 * Math.sin(u * Math.PI / 4 + ph) + 0.5 * Math.sin(u * Math.PI / 2 + ph * 2)
    let I = 1 - Math.abs(v - 7.5) / w
    if (end && u > 7) I -= ((u - 7) / 7.5) ** 2 * 1.1                         // round tip
    return I
  }
  const img = new Uint8Array(S * S)
  for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
    const u = x + 0.5, v = y + 0.5
    let I
    if (kind === 0) I = Math.max(band(u, v), band(v, u), 1.15 - Math.hypot(u - 8, v - 8) / (W + 1.6))
    else if (kind === 1) I = band(u, v, true)
    else if (kind === 2) I = band(u, v)
    else if (kind === 3) I = band(v, u, true)
    else I = band(v, u)
    I += (hash(x, y, 101 + frame) - 0.5) * 0.12
    if (frame === 3) I -= 0.1
    img[y * S + x] = I > 0.82 ? FLAME.idx.f4 : I > 0.62 ? FLAME.idx.f3 : I > 0.4 ? FLAME.idx.f2 : I > 0.2 ? FLAME.idx.f1 : I > 0.04 ? FLAME.idx.f0 : 0
  }
  return img
}

// 16x16 font from the 5x7 glyphs at 2x: bevelled strokes, vertical gradient, dark outline.
// Glyph order matches the cart's strings: 0-25 = A-Z, then the digits 0-9.
function glyph(ch) {
  const S = 16, g = FONT5[ch], img = new Uint8Array(S * S)
  const on = (x, y) => { const gx = x - 3, gy = y - 1; return gx >= 0 && gy >= 0 && gx < 10 && gy < 14 && g[gy >> 1][gx >> 1] === '1' }
  for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
    if (on(x, y)) {
      let t = y < 4 ? 1 : y < 7 ? 2 : y < 10 ? 3 : y < 13 ? 4 : 5
      if (!on(x, y - 1)) t = Math.max(1, t - 2)                               // lit top edges
      else if (!on(x, y + 1)) t = Math.min(5, t + 1)                          // shaded bottom edges
      img[y * S + x] = FONTG.idx['t' + (t - 1)]
    } else if (on(x - 1, y) || on(x + 1, y) || on(x, y - 1) || on(x, y + 1) || on(x - 1, y - 1) || on(x + 1, y - 1) || on(x - 1, y + 1) || on(x + 1, y + 1)) img[y * S + x] = FONTG.idx.ol
  }
  return img
}
for (const n of Object.keys(FONTG.idx)) if (FONTG.idx[n] !== FONTW.idx[n]) throw new Error('font banks out of step')

// ---- lay out the sprite tiles (row-major per sprite, as the PPU addresses them) ----
const sym = {}
const preview = []
function addSprite(name, image, S, B) {
  const n = S >> 3, base = allocVram(n * n)
  for (let ty = 0; ty < n; ty++) for (let tx = 0; tx < n; tx++) {
    const px = []; for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x++) px.push(image[(ty * 8 + y) * S + tx * 8 + x])
    tiles.push({ px, v: base + ty * n + tx })
  }
  if (name) sym[name] = base
  preview.push([name, image, S, B])
  return base
}
for (let d = 0; d < 3; d++) for (let s = 0; s < 3; s++) addSprite(d || s ? null : 'A_KNIGHT', knight(d, s), 32, KN1)
for (let f = 0; f < 4; f++) addSprite(f ? null : 'A_BOMB', bomb(f), 16, BOMB)
for (let f = 0; f < 4; f++) for (let k = 0; k < 5; k++) addSprite(f || k ? null : 'A_FLAME', flamePiece(k, f), 16, FLAME)
const FONTCH = [...'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789']
FONTCH.forEach((ch, i) => addSprite(i ? null : 'A_FONT', glyph(ch), 16, FONTG))
const NT = tiles.length
if (NT !== nextTile - 1) throw new Error('tile run is not contiguous')
tiles.sort((p, q) => p.v - q.v)

// flame lookup tables
const flpc = []
for (let m = 0; m < 16; m++) {
  const h = m & 3, v = m & 12
  let piece = 0, flip = 0
  if (h && v) piece = 0
  else if (h === 3) piece = 2
  else if (h === 1) piece = 1
  else if (h === 2) { piece = 1; flip = 0x40 }
  else if (v === 12) piece = 4
  else if (v === 4) piece = 3
  else if (v === 8) { piece = 3; flip = 0x80 }
  flpc.push(piece * 4 | flip << 8)
}
const flfr = []
for (let ttl = 0; ttl < 32; ttl++) flfr.push((ttl > 22 ? 0 : ttl > 7 ? 1 + ((ttl >> 1) & 1) : 3) * 20)

// ================= palette & sky =================
const pal = new Array(256).fill(0)
for (const B of Object.values(BANKS)) for (const [cn, h] of B.colours) pal[B.bank * 16 + B.idx[cn]] = to555(hex(h))
function skyLines(stops) {
  const out = []
  for (let y = 0; y < 224; y++) {
    let i = 0; while (i < stops.length - 2 && y > stops[i + 1][0]) i++
    const [y0, h0] = stops[i], [y1, h1] = stops[i + 1], t = clamp((y - y0) / (y1 - y0), 0, 1)
    const a = hex(h0), b = hex(h1)
    out.push(to555(a.map((v, k) => Math.round(v + (b[k] - v) * t))))
  }
  return out
}
const sky = skyLines([[0, '#1c48a0'], [30, '#2f68c0'], [56, '#5c9ad8'], [74, '#a8d4ee'], [80, '#d4ecf4'], [224, '#d4ecf4']])
pal[0] = sky[0]

// ================= write the binary + the EQU block =================
const parts = [], offs = {}
let at = 0
function section(name, bytes) { offs[name] = at; parts.push(Buffer.from(bytes)); at += bytes.length }
const tileBytes = new Uint8Array(NT * 32)
tiles.forEach(({ px }, t) => { for (let i = 0; i < 64; i += 2) tileBytes[t * 32 + (i >> 1)] = ((px[i] & 15) << 4) | (px[i + 1] & 15) })
const words = a => { const b = new Uint8Array(a.length * 2); a.forEach((v, i) => { b[i * 2] = v & 255; b[i * 2 + 1] = (v >> 8) & 255 }); return b }
section('ART_TILES', tileBytes)
section('ART_PAL', words(pal))
section('ART_SKY', words(sky))
section('ART_MAP1', words(Array.from(map1)))
section('ART_CELLS', words(cellEntries))
section('ART_FLPC', words(flpc))
section('ART_FLFR', flfr)
const bin = Buffer.concat(parts)
fs.writeFileSync(OUT, bin)

const equ = [
  '; >>> ART-EQU (generated by examples/palmblast/gen_art.js; do not edit by hand) >>>',
  `ART_NT    EQU ${NT}       ; art tiles 1..${NT} (${bg0Tiles} arena + ${bgTiles - bg0Tiles} backdrop + ${NT - bgTiles} sprite/font)`,
  `ART_TBYTES EQU ${NT * 32}    ; bytes in the tile run (one DMA to VRAM $20)`,
  ...Object.entries(offs).map(([k, v]) => `${k.padEnd(9)} EQU ${v}       ; byte offset into artbin`),
  ...Object.entries(sym).map(([k, v]) => `${k.padEnd(9)} EQU ${v}`),
  `B_KN1     EQU ${KN1.bank}         ; sprite palette banks`,
  `B_KN2     EQU ${KN2.bank}`,
  `B_BOMB    EQU ${BOMB.bank}`,
  `B_FLAME   EQU ${FLAME.bank}`,
  `T_GOLD    EQU $${(FONTG.bank << 11).toString(16).toUpperCase()}      ; BG0 entry bits: gold title text (bank ${FONTG.bank})`,
  `T_WHITE   EQU $${(FONTW.bank << 11).toString(16).toUpperCase()}      ; BG0 entry bits: white menu text (bank ${FONTW.bank})`,
  '; <<< ART-EQU <<<',
].join('\n')
const asmText = fs.readFileSync(ASM, 'utf8')
const re = /; >>> ART-EQU[\s\S]*?; <<< ART-EQU <<</
if (re.test(asmText)) fs.writeFileSync(ASM, asmText.replace(re, () => equ))
else console.warn('ART-EQU markers not found in palmblast.asm; block:\n' + equ)
console.log(`art.bin: ${bin.length} bytes, ${NT} tiles (${bg0Tiles} arena, ${bgTiles - bg0Tiles} backdrop, ${NT - bgTiles} sprite/font), ${remapped} backdrop pixels re-coloured for one-bank tiles`)

// ================= optional previews =================
const pngDir = process.argv.includes('--png') ? process.argv[process.argv.indexOf('--png') + 1] : null
if (pngDir) {
  const zlib = require('zlib')
  const png = (file, W, Hh, at) => {
    const raw = Buffer.alloc((W * 3 + 1) * Hh)
    for (let y = 0; y < Hh; y++) for (let x = 0; x < W; x++) { const [r, g, b] = at(x, y); const o = y * (W * 3 + 1) + 1 + x * 3; raw[o] = r; raw[o + 1] = g; raw[o + 2] = b }
    const T2 = []; for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; T2[n] = c >>> 0 }
    const crc = b => { let c = ~0; for (const x of b) c = T2[(c ^ x) & 255] ^ (c >>> 8); return (~c) >>> 0 }
    const ch = (t, d) => { const l = Buffer.alloc(4); l.writeUInt32BE(d.length); const td = Buffer.concat([Buffer.from(t), d]); const c = Buffer.alloc(4); c.writeUInt32BE(crc(td)); return Buffer.concat([l, td, c]) }
    const ih = Buffer.alloc(13); ih.writeUInt32BE(W, 0); ih.writeUInt32BE(Hh, 4); ih[8] = 8; ih[9] = 2
    fs.writeFileSync(path.join(pngDir, file), Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), ch('IHDR', ih), ch('IDAT', zlib.deflateSync(raw)), ch('IEND', Buffer.alloc(0))]))
  }
  fs.mkdirSync(pngDir, { recursive: true })
  const Z = 3, cellW = 36, cols = 9, rows = Math.ceil(preview.length / cols)
  png('sprites.png', cols * cellW * Z, rows * cellW * Z, (x, y) => {
    x = Math.floor(x / Z); y = Math.floor(y / Z)
    const p = preview[Math.floor(y / cellW) * cols + Math.floor(x / cellW)]
    if (!p) return [90, 150, 70]
    const [, im, S, B] = p, lx = x % cellW - 2, ly = y % cellW - 2
    if (lx < 0 || ly < 0 || lx >= S || ly >= S || !im[ly * S + lx]) return [76, 156, 58]
    return B.rgb[im[ly * S + lx]]
  })
  png('backdrop.png', W1 * 2, H1 * 2, (x, y) => {
    x >>= 1; y >>= 1
    const k = y * W1 + x
    return bg1.b[k] < 0 ? from555(sky[y]) : BANKS[bg1.b[k]].rgb[bg1.i[k]]
  })
  png('cells.png', 33 * 18 * 3, 18 * 3, (x, y) => {
    x = Math.floor(x / 3); y = Math.floor(y / 3)
    const cv = cells[Math.floor(x / 18)], lx = x % 18 - 1, ly = y - 1
    if (lx < 0 || ly < 0 || lx >= 16 || ly >= 16) return [0, 0, 0]
    const k = ly * 16 + lx
    return BANKS[cv.b[k]].rgb[cv.i[k]]
  })
}
