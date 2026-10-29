#!/usr/bin/env node
'use strict'
// SIEGESTONE — 16-bit art generator.
//
// Draws every Siegestone graphic from code (procedural pixel art) inside the CastlePalm
// PPU contract: 8x8 4bpp tiles, one 15-colour palette bank per tile, BG0 + BG1 64x64
// maps, square sprites. Writes one binary the cart INCBINs and rewrites the EQU block
// in siegestone.asm (between the ART-EQU markers) so the offsets never drift.
// Same pipeline as examples/palmblast/gen_art.js.
//
//   node examples/siegestone/gen_art.js            # writes art.bin + the EQUs in siegestone.asm
//   node examples/siegestone/gen_art.js --png DIR  # also dumps a sprite-sheet / backdrop PNG
//
// VRAM: tile 0 is blank; every art tile follows it in one contiguous run (tiles
// 1..ART_NT), so the boot loads them with a single DMA.
//
// Binary layout (all little-endian); each section's byte offset is exported as an
// ART_* EQU, addressed in the cart as #artbin+ART_xxx:
//   TILES  ART_NT tiles x 32 bytes (VRAM tiles 1..ART_NT)
//   PAL    256 words: the whole palette (entry 0 = sky line 0)
//   SKY    224 words: per-scanline backdrop colour (hblank handler)
//   MAP0   BG0 frame (castle walls round both wells, NEXT boxes), row-major 40 x 28 u16
//          (tile | bank<<11 | hflip<<15); 0 = transparent
//   MAP1   BG1 backdrop, row-major 40 x 28 u16
//   CELLS  well cell looks x 4 BG0 entries (TL, TR, BL, BR), see LOOKS below
//   ARC    48 x (dx, dy) s16: the volley's flight path

const fs = require('fs')
const path = require('path')
const zlib = require('zlib')
const ASM = path.join(__dirname, 'siegestone.asm')
const OUT = path.join(__dirname, 'art.bin')

// ---------------- VRAM allocation ----------------
let nextTile = 1
const allocVram = n => { const t = nextTile; nextTile += n; if (nextTile > 2048) throw new Error('VRAM full'); return t }

// ---------------- colour / palettes ----------------
const hex = h => [parseInt(h.slice(1, 3), 16), parseInt(h.slice(3, 5), 16), parseInt(h.slice(5, 7), 16)]
const to555 = ([r, g, b]) => ((Math.max(0, Math.min(255, b)) >> 3) << 10) | ((Math.max(0, Math.min(255, g)) >> 3) << 5) | (Math.max(0, Math.min(255, r)) >> 3)
const BANKS = {}
function bank(n, name, colours) {
  if (colours.length > 15) throw new Error(`bank ${name} has too many colours`)
  const idx = {}, rgb = {}
  colours.forEach(([cn, h], i) => { idx[cn] = i + 1; rgb[i + 1] = hex(h) })
  const B = { bank: n, idx, rgb, name, colours }
  BANKS[n] = B
  return B
}

// the well masonry colours lead every bank a well cell can use, so a stone painted on
// the BG still has its well behind it (BG colour 0 would show the sky instead)
const WELLC = [['w0', '#0d0b16'], ['w1', '#1b1929'], ['w2', '#2a2840'], ['ol', '#07060c']]
const WELL = bank(0, 'well', [...WELLC,
  ['r0', '#30251c'], ['r1', '#5c4936'], ['r2', '#887158'], ['r3', '#bca486'],
  ['m0', '#353c46'], ['m1', '#58636e'], ['m2', '#8794a2'], ['m3', '#c6d2de'],
  ['hl', '#ffffff'], ['cr', '#120c08'],
])
const stoneBank = (n, name, ramp, e0, e1) => bank(n, name, [...WELLC,
  ['s0', ramp[0]], ['s1', ramp[1]], ['s2', ramp[2]], ['s3', ramp[3]], ['s4', ramp[4]],
  ['e0', e0], ['e1', e1], ['hl', '#ffffff'], ['i0', '#34343f'], ['i1', '#7c7c90'], ['i2', '#c0c0d0'],
])
const RED = stoneBank(1, 'red', ['#4c0a16', '#8c1824', '#c42e2e', '#e85c4a', '#ffa48c'], '#3a0610', '#f6c84a')
const BLUE = stoneBank(2, 'blue', ['#0c1a4c', '#18388c', '#2a62c8', '#4a94ee', '#a0d2ff'], '#08123a', '#eaf6ff')
const GREEN = stoneBank(3, 'green', ['#0c3814', '#186a24', '#2c9a34', '#5ac84a', '#acee86'], '#062a0c', '#f6f2a2')
const GOLD = stoneBank(4, 'gold', ['#5a3806', '#9a6a10', '#d2a222', '#f2ce42', '#fff2a6'], '#3e2204', '#8a2a12')
const STONES = [RED, BLUE, GREEN, GOLD]
const FRAME = bank(5, 'frame', [
  ['k0', '#16141e'], ['k1', '#34303e'], ['k2', '#54505f'], ['k3', '#787385'], ['k4', '#a09cac'], ['k5', '#cecad8'],
  ['mo0', '#2c5624'], ['mo1', '#4a8634'], ['ol', '#07060c'], ['bn0', '#5a1016'], ['bn1', '#a82a26'], ['bn2', '#e8584a'],
  ['gd', '#f0c040'],
])
const FONTG = bank(6, 'font-gold', [
  ['ol', '#2a1006'], ['t0', '#fffbd8'], ['t1', '#ffe060'], ['t2', '#f6a822'], ['t3', '#d06a14'], ['t4', '#8c3a0a'],
])
const FONTW = bank(7, 'font-white', [
  ['ol', '#121428'], ['t0', '#ffffff'], ['t1', '#eef2fa'], ['t2', '#cfd8ec'], ['t3', '#a2b0d4'], ['t4', '#6c7aaa'],
])
const SKYB = bank(8, 'sky', [
  ['cl0', '#9ab4d8'], ['cl1', '#c8dcf2'], ['cl2', '#ffffff'],
  ['mt0', '#4a5c8a'], ['mt1', '#6478a6'], ['mt2', '#8a9cc4'], ['sn', '#e6eefa'],
  ['h0', '#3c6a5a'], ['h1', '#4e8468'], ['h2', '#6a9e72'],
])
const FIELD = bank(9, 'field', [
  ['g0', '#24501e'], ['g1', '#346e28'], ['g2', '#4a8c34'], ['g3', '#6aac46'], ['g4', '#9ad064'],
  ['d0', '#4a3420'], ['d1', '#6e5032'], ['d2', '#94704a'], ['d3', '#bc9868'],
  ['t0', '#163a1c'], ['t1', '#22582a'], ['t2', '#347a36'], ['tr', '#3a2616'],
])
const CATA = bank(11, 'catapult', [
  ['ol', '#0a0608'], ['wd0', '#3a2010'], ['wd1', '#6a4020'], ['wd2', '#9a6434'], ['wd3', '#c89458'],
  ['rp0', '#8a7448'], ['rp1', '#d2bc84'], ['ir0', '#2c2c38'], ['ir1', '#5c5c70'], ['ir2', '#a0a0b8'],
  ['ld0', '#4a3a2c'], ['ld1', '#7c6a56'], ['ld2', '#b4a48c'], ['sh', '#2a4a1e'],
])
const FLASH = bank(12, 'flash', [...WELLC, ['f0', '#ff7a18'], ['f1', '#ffc038'], ['f2', '#fff27a'], ['f3', '#ffffff']])
const CROWN = bank(13, 'crown', [
  ['ol', '#1a0e04'], ['g0', '#8a5208'], ['g1', '#c88a14'], ['g2', '#f0c03a'], ['g3', '#fff2a0'],
  ['gm0', '#8a0c20'], ['gm1', '#ee3a50'], ['bl0', '#163a8a'], ['bl1', '#4a8aee'], ['wh', '#ffffff'],
  ['dm0', '#2a2838'], ['dm1', '#4a4860'],
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
}
const hash = (x, y, s = 0) => { let h = (x * 374761393 + y * 668265263 + s * 2147483647) | 0; h = (h ^ (h >>> 13)) * 1274126177 | 0; return ((h ^ (h >>> 16)) >>> 0) / 4294967296 }
const clamp = (v, a, b) => Math.max(a, Math.min(b, v))

// ================= well cells (16x16 each) =================
// dark ashlar inside the well: 16x8 blocks, running bond, faint top-lit edge
function wellPx(x, y) {
  const row = y >> 3, bx = (x + (row & 1) * 8) & 15, by = y & 7
  if (by === 7 || bx === 15) return 'w0'
  if (by === 0 && bx < 14) return 'w2'
  return hash(bx >> 2, row, 5) < 0.25 && hash(x, y, 6) < 0.3 ? 'w2' : 'w1'
}
function wellCell(B = WELL) {
  const cv = new Canvas(16, 16)
  for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) cv.set(x, y, B, wellPx(x, y))
  return cv
}
// shape mask helpers: a list of [x,y] -> 1 inside
const inRound = (x, y, x0, y0, x1, y1, r) => {
  if (x < x0 || x > x1 || y < y0 || y > y1) return false
  const cx = x < x0 + r ? x0 + r : x > x1 - r ? x1 - r : x, cy = y < y0 + r ? y0 + r : y > y1 - r ? y1 - r : y
  return (x - cx) ** 2 + (y - cy) ** 2 <= r * r + 0.5
}
// mason's marks, 8x8, centred in the stone
const MARKS = [
  ['########', '########', '###..###', '###..###', '.######.', '.######.', '..####..', '...##...'],   // shield (red)
  ['........', '.##...##', '#..#.#..', '....#...', '.##...##', '#..#.#..', '....#...', '........'],   // waves (blue)
  ['.....###', '...#####', '..#####.', '.#####..', '.####...', '.###....', '#.......', '........'],   // leaf (green)
  ['#..##..#', '#..##..#', '##.##.##', '########', '########', '.######.', '........', '########'],   // crown (gold)
]
// stone image (16x16 colour names, null = outside): bevelled cut stone with its mark
function stoneImg(k) {
  const img = []
  const inside = (x, y) => inRound(x, y, 1, 1, 14, 14, 3)
  for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {
    let c = null
    if (inside(x, y)) {
      const dt = y - 1, dl = x - 1, db = 14 - y, dr = 14 - x
      if (dt <= 1 && dt <= dr) c = dt === 0 ? 's4' : 's3'
      else if (dl <= 1 && dl <= db) c = dl === 0 ? 's3' : 's3'
      else if (db <= 1) c = db === 0 ? 's0' : 's1'
      else if (dr <= 1) c = dr === 0 ? 's0' : 's1'
      else {
        const t = (x + y) / 30 + (hash(x, y, 11 + k) - 0.5) * 0.18
        c = t < 0.42 ? 's3' : t < 0.78 ? 's2' : 's1'
      }
    } else if (inside(x - 1, y) || inside(x + 1, y) || inside(x, y - 1) || inside(x, y + 1)) c = 'ol'
    img.push(c)
  }
  const M = MARKS[k], on = (x, y) => x >= 4 && y >= 4 && x < 12 && y < 12 && M[y - 4][x - 4] === '#'
  for (let y = 4; y < 13; y++) for (let x = 4; x < 13; x++) {
    if (on(x, y)) img[y * 16 + x] = (!on(x - 1, y) || !on(x, y - 1)) ? 'e0' : 'e1'
    else if (on(x - 1, y) || on(x, y - 1)) img[y * 16 + x] = 's4'
  }
  img[3 * 16 + 3] = 'hl'; img[3 * 16 + 4] = 'hl'; img[4 * 16 + 3] = 'hl'
  return img
}
const onWell = (img, B) => {
  const cv = new Canvas(16, 16)
  for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) cv.set(x, y, B, img[y * 16 + x] || wellPx(x, y))
  return cv
}
// glued stone: iron bands across the top and bottom, riveted, so it reads as fixed
function gluedImg(k) {
  const img = stoneImg(k)
  for (const y0 of [1, 11]) for (let y = y0; y < y0 + 4; y++) for (let x = 0; x < 16; x++) {
    const edge = y === y0 || y === y0 + 3 || x === 0 || x === 15
    img[y * 16 + x] = edge ? 'i0' : (y === y0 + 1 ? 'i2' : 'i1')
  }
  for (const [x, y] of [[3, 2], [12, 2], [3, 12], [12, 12]]) { img[y * 16 + x] = 'hl'; img[(y + 1) * 16 + x] = 'i0' }
  return img
}
// lumpy rocks shaded from the top-left (rubble, boulders)
function rocks(list, B, ramp, seed) {
  const S = 16, img = new Array(S * S).fill(null), L = [-0.6, -0.7, 0.55]
  for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
    for (const [cx, cy, r] of list) {
      const ang = Math.atan2(y - cy, x - cx), rr = r * (1 + 0.16 * Math.sin(ang * 3 + seed + cx) + 0.08 * Math.sin(ang * 5 + cy))
      const dx = (x + 0.5 - cx) / rr, dy = (y + 0.5 - cy) / rr
      if (dx * dx + dy * dy > 1) continue
      const nz = Math.sqrt(Math.max(0, 1 - dx * dx - dy * dy))
      let I = dx * L[0] + dy * L[1] + nz * L[2] + (hash(x, y, seed) - 0.5) * 0.25
      img[y * S + x] = ramp[I < 0.05 ? 0 : I < 0.4 ? 1 : I < 0.75 ? 2 : 3]
    }
  }
  return outlineNames(img, S, 'ol')
}
function outlineNames(img, S, ol) {
  const r = img.slice()
  for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) if (!img[y * S + x]) for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
    const xx = x + dx, yy = y + dy
    if (xx >= 0 && yy >= 0 && xx < S && yy < S && img[yy * S + xx] && img[yy * S + xx] !== ol) { r[y * S + x] = ol; break }
  }
  return r
}
const RUBBLE = [[5, 10, 4.6], [11, 10.5, 4.4], [8, 5, 4.2]]
function rubbleImg(cracked) {
  const img = rocks(RUBBLE, WELL, ['r0', 'r1', 'r2', 'r3'], 3)
  if (cracked) {
    for (const [x, y] of [[8, 2], [8, 3], [7, 4], [8, 5], [9, 6], [9, 7], [10, 8], [4, 8], [5, 9], [5, 10], [6, 11], [12, 9], [12, 10], [13, 11], [11, 12]]) if (img[y * 16 + x]) img[y * 16 + x] = 'cr'
    for (const [x, y] of [[2, 12], [3, 13], [13, 13], [14, 12], [10, 2]]) img[y * 16 + x] = null   // chipped
  }
  return img
}
// wet mortar: a glossy grey slump; dries darker over three stages
function mortarImg(stage) {
  const img = new Array(256).fill(null)
  const ramp = stage === 0 ? ['m1', 'm2', 'm2', 'm3'] : stage === 1 ? ['m0', 'm1', 'm2', 'm2'] : ['m0', 'm0', 'm1', 'm1']
  for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {
    const top = 3 + 1.6 * Math.sin(x * 0.7 + 1) + (x < 3 || x > 12 ? 2 : 0)
    if (y < top || y > 14 || x < 1 || x > 14) continue
    const I = 1 - (y - top) / (15 - top) * 0.8 - x / 40 + (hash(x, y, 21) - 0.5) * 0.15
    img[y * 16 + x] = ramp[I > 0.85 ? 3 : I > 0.6 ? 2 : I > 0.35 ? 1 : 0]
  }
  if (stage < 2) for (const [x, y] of [[4, 5], [5, 5], [5, 6], [10, 7], [11, 7]]) if (img[y * 16 + x]) img[y * 16 + x] = 'hl'
  if (stage === 0) for (let y = 13; y < 16; y++) img[y * 16 + 6] = 'm2'                 // drip
  return outlineNames(img, 16, 'ol')
}
// set mortar: a hard square block, trowel-scored, bolted
function setImg(cracked) {
  const img = new Array(256).fill(null)
  for (let y = 1; y < 15; y++) for (let x = 1; x < 15; x++) {
    let c = y === 1 || x === 1 ? 'm2' : y === 14 || x === 14 ? 'm0' : ((x + y * 2) % 7 === 0 ? 'm0' : 'm1')
    img[y * 16 + x] = c
  }
  for (const [x, y] of [[3, 3], [12, 3], [3, 12], [12, 12]]) { img[y * 16 + x] = 'r3'; img[(y + 1) * 16 + x] = 'r0' }
  if (cracked) for (const [x, y] of [[7, 1], [7, 2], [8, 3], [8, 4], [7, 5], [6, 6], [6, 7], [7, 8], [9, 8], [10, 9], [11, 10], [5, 9], [4, 10], [4, 11], [8, 12], [8, 13]]) img[y * 16 + x] = 'cr'
  return outlineNames(img, 16, 'ol')
}
// clear flash: a starburst over the well
function flashImg() {
  const img = new Array(256).fill(null)
  for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {
    const dx = x - 7.5, dy = y - 7.5, r = Math.hypot(dx, dy), a = Math.atan2(dy, dx)
    const ray = 4 + 3.5 * Math.pow(Math.abs(Math.cos(a * 4)), 6)
    if (r > ray) continue
    const t = r / ray
    img[y * 16 + x] = t < 0.35 ? 'f3' : t < 0.6 ? 'f2' : t < 0.85 ? 'f1' : 'f0'
  }
  return img
}

// LOOKS (cell look -> canvas). The cart maps cell codes to looks (siegestone.asm lookOf).
const LOOKS = [
  wellCell(),                                       // 0 empty
  ...STONES.map((B, k) => onWell(stoneImg(k), B)),  // 1..4 stones
  onWell(rubbleImg(false), WELL),                   // 5 rubble
  onWell(rubbleImg(true), WELL),                    // 6 cracked rubble
  onWell(mortarImg(0), WELL),                       // 7 wet mortar
  onWell(setImg(false), WELL),                      // 8 set mortar
  onWell(setImg(true), WELL),                       // 9 cracked set mortar
  onWell(mortarImg(1), WELL),                       // 10 mortar drying
  onWell(mortarImg(2), WELL),                       // 11 mortar nearly set
  onWell(flashImg(), FLASH),                        // 12 clear flash
  ...STONES.map((B, k) => onWell(gluedImg(k), B)),  // 13..16 glued stones
]

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
for (const cv of LOOKS) cellEntries.push(packCell(cv, 0, 0), packCell(cv, 1, 0), packCell(cv, 0, 1), packCell(cv, 1, 1))
const cellTiles = tiles.length

// ================= BG0 frame: castle walls round both wells, NEXT boxes =================
const bg0 = new Canvas(320, 224)
// ashlar block: lit top-left bevel, dark bottom-right, a little moss
function ashlar(x0, y0, w, h, seed) {
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    let c
    if (x === w - 1 || y === h - 1) c = 'k0'
    else if (y === 0 || x === 0) c = 'k5'
    else if (y === h - 2 || x === w - 2) c = 'k2'
    else c = hash(x0 + x, y0 + y, seed) < 0.22 ? 'k3' : 'k4'
    if (c === 'k4' && y === h - 3 && hash(x0 + x, seed, 7) < 0.3) c = 'mo1'
    bg0.set(x0 + x, y0 + y, FRAME, c)
  }
}
function tower(ix) {                               // ix = inner-left pixel of the well
  const L = ix - 8, R = ix + 96
  for (let y = 24, n = 0; y < 216; y += 8, n++) { ashlar(L, y, 8, 8, n * 2 + ix); ashlar(R, y, 8, 8, n * 2 + 1 + ix) }
  // wall walk + merlons on the top course
  for (let x = L; x < R + 8; x += 8) ashlar(x, 19, 8, 5, x)
  for (let x = L; x < R + 8; x += 16) ashlar(x, 12, 8, 8, x + 3)
  // base course: deep plinth blocks
  for (let x = L; x < R + 8; x += 16) ashlar(x, 216, 16, 8, x + 9)
}
tower(16); tower(208)
// NEXT boxes (stone-framed niches the next pair sits in)
function niche(x0, y0) {
  for (let y = 0; y < 40; y++) for (let x = 0; x < 24; x++) {
    const ex = Math.min(x, 23 - x), ey = Math.min(y, 39 - y)
    let c = ex < 3 || ey < 3 ? (ex === 0 || ey === 0 ? 'ol' : (x < 3 || y < 3 ? 'k4' : 'k1')) : (y < 6 ? 'k0' : 'k1')
    if ((ex === 1 || ey === 1) && (x < 12 || y < 20)) c = 'k5'
    bg0.set(x0 + x, y0 + y, FRAME, c)
  }
}
niche(124, 28); niche(172, 28)
const map0 = new Uint16Array(40 * 28)
for (let ty = 0; ty < 28; ty++) for (let tx = 0; tx < 40; tx++) map0[ty * 40 + tx] = packCell(bg0, tx, ty)
const bg0Tiles = tiles.length

// ================= BG1 backdrop: sky, clouds, hills, field =================
const bg1 = new Canvas(320, 224)
function cloud(cx, cy, rx, ry) {
  for (let y = -ry - 2; y <= ry; y++) for (let x = -rx - 2; x <= rx + 2; x++) {
    const bumps = 1 + 0.25 * Math.sin(x * 0.45 + cx) + 0.15 * Math.sin(x * 0.9)
    const d = (x / rx) ** 2 + (y / (ry * bumps)) ** 2
    if (d > 1 || y > ry * 0.55) continue
    bg1.set(cx + x, cy + y, SKYB, y < -ry * 0.35 ? 'cl2' : y < ry * 0.15 ? 'cl1' : 'cl0')
  }
}
for (const [cx, cy, rx, ry] of [[40, 30, 22, 9], [160, 22, 26, 10], [150, 60, 16, 6], [282, 40, 22, 9], [100, 74, 12, 5]]) cloud(cx, cy, rx, ry)
for (let x = 0; x < 320; x++) {
  const m = 118 - 26 * Math.max(0, Math.sin(x * 0.024 + 0.4)) - 14 * Math.max(0, Math.sin(x * 0.061 + 1.3))
  for (let y = Math.round(m); y < 168; y++) {
    const snow = y < m + 4 && m < 104
    bg1.set(x, y, SKYB, snow ? 'sn' : hash(x >> 1, y >> 2, 12) < 0.12 ? 'mt2' : y < m + 10 ? 'mt1' : 'mt0')
  }
  const h = 150 - 10 * Math.sin(x * 0.035 + 2) - 5 * Math.sin(x * 0.09)
  for (let y = Math.round(h); y < 178; y++) bg1.set(x, y, SKYB, y < h + 2 ? 'h2' : (hash(x, y, 4) < 0.15 ? 'h2' : y < h + 8 ? 'h1' : 'h0'))
}
// field + the dirt yard the catapults stand on
for (let y = 172; y < 224; y++) for (let x = 0; x < 320; x++) {
  const n = hash(x, y, 8)
  let c = y < 175 ? 'g3' : n < 0.15 ? 'g1' : n > 0.88 ? 'g3' : 'g2'
  if ((x * 3 + y * 5) % 11 === 0 && n > 0.4) c = 'g4'
  if (y > 200) c = n < 0.3 ? 'g0' : 'g1'
  const yard = Math.abs(x - 160) < 46 - (212 - y) * 0.6 && y > 196
  if (yard) c = n < 0.18 ? 'd0' : n < 0.6 ? 'd1' : n < 0.92 ? 'd2' : 'd3'
  bg1.set(x, y, FIELD, c)
}
// a few trees on the hills
function tree(x0, y0, s) {
  for (let y = -10 * s; y <= 0; y++) for (let x = -6 * s; x <= 6 * s; x++) {
    const d = (x / (5.5 * s)) ** 2 + ((y + 5 * s) / (5.5 * s)) ** 2
    if (d <= 1) bg1.set(x0 + x, y0 + y, FIELD, x + y < -6 * s ? 't2' : d < 0.5 ? 't1' : 't0')
  }
  for (let y = 1; y < 4 * s; y++) bg1.set(x0, y0 + y, FIELD, 'tr')
}
for (const [x, y, s] of [[128, 176, 1], [196, 178, 1], [140, 182, 0.8], [182, 174, 0.7], [4, 180, 1], [316, 180, 1]]) tree(x, y, s)
const map1 = new Uint16Array(40 * 28)
for (let ty = 0; ty < 28; ty++) for (let tx = 0; tx < 40; tx++) map1[ty * 40 + tx] = packCell(bg1, tx, ty)
const bgTiles = tiles.length

// ================= sprites =================
const LIGHT = (() => { const v = [-0.6, -0.65, 0.6], m = Math.hypot(...v); return v.map(c => c / m) })()
// parts: {mat, ell:[cx,cy], rx, ry} | {mat, cap:[[ax,ay],[bx,by]], r:[r0,r1]} | {mat, rect}
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
        if (p.ring && dx * dx + dy * dy < p.ring) continue
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
  return outline(out, S, B.idx.ol)
}
function outline(a, S, ol) {
  const r = a.slice()
  for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) if (!a[y * S + x]) for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
    const xx = x + dx, yy = y + dy
    if (xx >= 0 && yy >= 0 && xx < S && yy < S && a[yy * S + xx] && a[yy * S + xx] !== ol) { r[y * S + x] = ol; break }
  }
  return r
}
const namesToIdx = (img, B) => Uint8Array.from(img, c => c ? B.idx[c] : 0)

// THE CATAPULT: side view facing right, 32x32. frame 0 cocked + loaded, 1 cocked empty,
// 2 mid-swing, 3 thrown (arm forward against the stop)
function catapult(frame) {
  const P = [], piv = [15, 14]
  const ang = [205, 205, 270, 325][frame] * Math.PI / 180      // direction of the bucket end
  const tip = [piv[0] + Math.cos(ang) * 14, piv[1] + Math.sin(ang) * 14]
  const back = [piv[0] - Math.cos(ang) * 5, piv[1] - Math.sin(ang) * 5]
  P.push({ cap: [[17, 25], [22, 13]], r: [1.6, 1.4], mat: 'wd', back: true })     // far upright
  P.push({ cap: [[3, 25], [29, 25]], r: [2.2, 2.2], mat: 'wd' })                  // base beam
  P.push({ ell: [7, 27], rx: 4, ry: 4, mat: 'ir', ring: 0.35 })                   // wheels (iron rims)
  P.push({ ell: [7, 27], rx: 1.6, ry: 1.6, mat: 'wd' })
  P.push({ ell: [25, 27], rx: 4, ry: 4, mat: 'ir', ring: 0.35 })
  P.push({ ell: [25, 27], rx: 1.6, ry: 1.6, mat: 'wd' })
  P.push({ cap: [[11, 24], [15, 13]], r: [1.7, 1.4], mat: 'wd' })                 // near A-frame
  P.push({ cap: [[21, 24], [15.5, 13]], r: [1.7, 1.4], mat: 'wd' })
  P.push({ cap: [[22.5, 11], [22.5, 24]], r: [1.1, 1.3], mat: 'wd' })             // stop post
  P.push({ rect: [20.5, 9.5, 24.5, 11.5], mat: 'rp', tone: 0.5 })                 // padded cross-bar
  P.push({ cap: [back, tip], r: [1.9, 1.3], mat: 'wd' })                          // throwing arm
  P.push({ ell: back, rx: 2.6, ry: 2.6, mat: 'ir' })                              // counterweight
  const cupDir = ang + Math.PI / 2
  const cup = [tip[0] + Math.cos(cupDir) * 1.2, tip[1] + Math.sin(cupDir) * 1.2]
  P.push({ ell: cup, rx: 3.2, ry: 2.6, mat: 'rp' })                               // rope basket
  if (frame === 0) P.push({ ell: [cup[0], cup[1] - 1.8], rx: 2.6, ry: 2.2, mat: 'ld' })   // the load
  P.push({ ell: piv, rx: 1.5, ry: 1.5, mat: 'ir', tone: 0.9 })                    // axle
  const img = renderRig(CATA, P, 32)
  for (let x = 2; x < 30; x++) if (!img[31 * 32 + x]) img[31 * 32 + x] = CATA.idx.sh                 // ground shadow
  return img
}
function boulder(r, seed) { return namesToIdx(rocks([[7.5, 8, r]], WELL, ['r0', 'r1', 'r2', 'r3'], seed), WELL) }
function crown(lit) {
  const S = 16, img = new Uint8Array(S * S)
  const M = ['................', '................', '..#....##....#..', '..##...##...##..', '..###.####.###..', '..############..', '..############..', '..############..', '..############..', '...##########...', '...##########...', '................']
  for (let y = 0; y < M.length; y++) for (let x = 0; x < S; x++) if (M[y][x] === '#') {
    img[y * S + x] = lit ? CROWN.idx[y < 4 ? 'g3' : y < 6 ? 'g2' : y < 9 ? 'g1' : 'g0'] : CROWN.idx[y < 6 ? 'dm1' : 'dm0']
  }
  if (lit) { for (const x of [5, 10]) img[7 * S + x] = CROWN.idx.gm1; img[7 * S + 7] = CROWN.idx.bl1; img[7 * S + 8] = CROWN.idx.bl1; img[3 * S + 7] = CROWN.idx.wh }
  return outline(img, S, CROWN.idx.ol)
}
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
// 16x16 font from the 5x7 glyphs at 2x: bevelled strokes, vertical gradient, dark outline.
// Glyph order matches the cart's strings: 0-25 = A-Z, then the digits 0-9.
function glyph(ch) {
  const S = 16, g = FONT5[ch], img = new Uint8Array(S * S)
  const on = (x, y) => { const gx = x - 3, gy = y - 1; return gx >= 0 && gy >= 0 && gx < 10 && gy < 14 && g[gy >> 1][gx >> 1] === '1' }
  for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
    if (on(x, y)) {
      let t = y < 4 ? 1 : y < 7 ? 2 : y < 10 ? 3 : y < 13 ? 4 : 5
      if (!on(x, y - 1)) t = Math.max(1, t - 2)
      else if (!on(x, y + 1)) t = Math.min(5, t + 1)
      img[y * S + x] = FONTG.idx['t' + (t - 1)]
    } else if (on(x - 1, y) || on(x + 1, y) || on(x, y - 1) || on(x, y + 1) || on(x - 1, y - 1) || on(x + 1, y - 1) || on(x - 1, y + 1) || on(x + 1, y + 1)) img[y * S + x] = FONTG.idx.ol
  }
  return img
}
for (const n of Object.keys(FONTG.idx)) if (FONTG.idx[n] !== FONTW.idx[n]) throw new Error('font banks out of step')
for (const B of STONES) for (const n of Object.keys(RED.idx)) if (B.idx[n] !== RED.idx[n]) throw new Error('stone banks out of step')

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
// sprite stones (transparent corners): 4 colours (banks 1..4 share one index layout) + wet mortar
STONES.forEach((B, k) => addSprite(k ? null : 'A_STONE', namesToIdx(stoneImg(k), RED), 16, B))
addSprite(null, namesToIdx(mortarImg(0), WELL), 16, WELL)
for (let f = 0; f < 4; f++) addSprite(f ? null : 'A_CATA', catapult(f), 32, CATA)
addSprite('A_BOULDER', boulder(6.2, 1), 16, WELL)
addSprite('A_PEBBLE', boulder(3.6, 2), 16, WELL)
addSprite('A_CROWN', crown(true), 16, CROWN)
addSprite(null, crown(false), 16, CROWN)
const FONTCH = [...'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789']
FONTCH.forEach((ch, i) => addSprite(i ? null : 'A_FONT', glyph(ch), 16, FONTG))
const NT = tiles.length
if (NT !== nextTile - 1) throw new Error('tile run is not contiguous')
tiles.sort((p, q) => p.v - q.v)

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
const sky = skyLines([[0, '#2a3c8c'], [40, '#4a6cc0'], [80, '#86aee0'], [112, '#cfe2f2'], [224, '#cfe2f2']])
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
section('ART_MAP0', words(Array.from(map0)))
section('ART_MAP1', words(Array.from(map1)))
section('ART_CELLS', words(cellEntries))
// volley arc: FLYTIME (48) steps of (dx, dy) from P1's catapult cup to over P2's well
// (P2's volley mirrors dx). s16 words, launch at t = 0.
const arc = []
for (let t = 0; t < 48; t++) { const u = t / 47; arc.push(Math.round(116 * u) & 0xffff, Math.round(-176 * u - 64 * Math.sin(Math.PI * u)) & 0xffff) }
section('ART_ARC', words(arc))
const bin = Buffer.concat(parts)
fs.writeFileSync(OUT, bin)

const equ = [
  '; >>> ART-EQU (generated by examples/siegestone/gen_art.js; do not edit by hand) >>>',
  `ART_NT    EQU ${NT}       ; art tiles 1..${NT} (${cellTiles} well + ${bgTiles - cellTiles} frame/backdrop + ${NT - bgTiles} sprite/font)`,
  `ART_TBYTES EQU ${NT * 32}    ; bytes in the tile run (one DMA to VRAM $20)`,
  ...Object.entries(offs).map(([k, v]) => `${k.padEnd(9)} EQU ${v}       ; byte offset into artbin`),
  ...Object.entries(sym).map(([k, v]) => `${k.padEnd(9)} EQU ${v}`),
  `B_WELL    EQU ${WELL.bank}         ; palette banks`,
  `B_RED     EQU ${RED.bank}`,
  `B_CATA    EQU ${CATA.bank}`,
  `B_CROWN   EQU ${CROWN.bank}`,
  `T_GOLD    EQU $${(FONTG.bank << 11).toString(16).toUpperCase()}      ; BG0 entry bits: gold title text (bank ${FONTG.bank})`,
  `T_WHITE   EQU $${(FONTW.bank << 11).toString(16).toUpperCase()}      ; BG0 entry bits: white menu text (bank ${FONTW.bank})`,
  '; <<< ART-EQU <<<',
].join('\n')
if (fs.existsSync(ASM)) {
  const asmText = fs.readFileSync(ASM, 'utf8')
  const re = /; >>> ART-EQU[\s\S]*?; <<< ART-EQU <<</
  if (re.test(asmText)) fs.writeFileSync(ASM, asmText.replace(re, () => equ))
  else console.warn('ART-EQU markers not found in siegestone.asm; block:\n' + equ)
}
console.log(`art.bin: ${bin.length} bytes, ${NT} tiles (${cellTiles} well, ${bg0Tiles - cellTiles} frame, ${bgTiles - bg0Tiles} backdrop, ${NT - bgTiles} sprite/font), ${remapped} pixels re-coloured for one-bank tiles`)

// ================= optional preview: sprite sheet =================
const pngDir = process.argv.includes('--png') ? process.argv[process.argv.indexOf('--png') + 1] : null
if (pngDir) {
  const rgbOf = (B, i) => B.rgb[i]
  const Z = 3, cellW = 36, cols = 10, rows = Math.ceil(preview.length / cols)
  const W = cols * cellW * Z, H = rows * cellW * Z
  const px = new Uint32Array(W * H).fill(0xff404040)
  preview.forEach(([, img, S, B], n) => {
    const ox = (n % cols) * cellW * Z + 2 * Z, oy = Math.floor(n / cols) * cellW * Z + 2 * Z
    for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
      const i = img[y * S + x]; if (!i) continue
      const [r, g, b] = rgbOf(B, i)
      for (let dy = 0; dy < Z; dy++) for (let dx = 0; dx < Z; dx++) px[(oy + y * Z + dy) * W + ox + x * Z + dx] = (0xff000000 | b << 16 | g << 8 | r) >>> 0
    }
  })
  fs.mkdirSync(pngDir, { recursive: true })
  writePng(path.join(pngDir, 'siegestone-sprites.png'), W, H, px)
}

// pixels as System.framebuffer (0xAABBGGRR) -> PNG file
function writePng(file, W, H, px, Z = 1) {
  const w = W * Z, h = H * Z
  const raw = Buffer.alloc((w * 3 + 1) * h)
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const v = px[Math.floor(y / Z) * W + Math.floor(x / Z)] >>> 0, o = y * (w * 3 + 1) + 1 + x * 3
    raw[o] = v & 255; raw[o + 1] = (v >> 8) & 255; raw[o + 2] = (v >> 16) & 255
  }
  const T = []; for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; T[n] = c >>> 0 }
  const crc = b => { let c = ~0; for (const x of b) c = T[(c ^ x) & 255] ^ (c >>> 8); return (~c) >>> 0 }
  const ch = (t, d) => { const l = Buffer.alloc(4); l.writeUInt32BE(d.length); const td = Buffer.concat([Buffer.from(t), d]); const c = Buffer.alloc(4); c.writeUInt32BE(crc(td)); return Buffer.concat([l, td, c]) }
  const ih = Buffer.alloc(13); ih.writeUInt32BE(w, 0); ih.writeUInt32BE(h, 4); ih[8] = 8; ih[9] = 2
  fs.writeFileSync(file, Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), ch('IHDR', ih), ch('IDAT', zlib.deflateSync(raw)), ch('IEND', Buffer.alloc(0))]))
}
