#!/usr/bin/env node
'use strict'
// STREET BRAWL — 16-bit art generator.
//
// Draws every asset the cart uses from code (no hand-packed nibbles) and writes the
// cart-ready binaries the .asm INCBINs:
//
//   tiles.bin   VRAM tile region (tile N at byte N*32), DMA'd at boot
//   maps.bin    BG0 then BG1 map, 64x28 cells x 4 bytes each
//   pal.bin     all 256 palette entries (RGB555), stage-1 colours
//   levels.bin  per stage: 224-word sky gradient + banks 1, 2, 10
//   bodies.bin  the player's selectable bodies: 6 frames x 64 tiles each,
//               DMA'd over PL_WALK..PL_DOWN by the character creator
//   charpal.bin the creator's colour ramps (RGB555) for the player bank
//
// Layers: BG0 = clouds + two depths of skyline (parallax, scrolls at cam/4).
//         BG1 = the street (buildings, fence, sidewalk, road) + the HUD in rows 0-1;
//               an hblank handler holds BG1 scroll at 0 for lines 0-23 (HUD) and
//               rewrites palette entry 0 every line (the sky gradient).
// Sprites: fighters are rigged figures rendered with directional light into 64x64
//          frames; one 15-colour bank per character; 16x16 pickups; a 32x32 shadow.
//
// Constraint the art is built around: one palette bank per 8x8 tile, so every
// material boundary sits on a tile edge (packLayer throws if one does not).
//
//   node examples/streetbrawl/gen_art.js

const fs = require('fs')
const path = require('path')
const Rig = require('./rig.js')

// ---- fixed tile indices (keep in sync with the EQUs in streetbrawl.asm) ----
const T = {
  HP_FULL: 5, HP_EMPTY: 6, WPN_ICON: 8, BHP_FULL: 9,
  SOLID: 16,               // 15 solid swatches: SOLID + k - 1 is filled with colour k
  FONT: 64, ARROWL: 91, ARROWR: 92, DIGIT: 96,
  PL_WALK: 128,            // 4 frames, 64 tiles apart
  PL_PUNCH: 384, PL_DOWN: 448,
  GR_WALK: 512,            // 2 frames (grunt + runner share them, recoloured)
  GR_DOWN: 640,
  BR_WALK: 704,            // 2 frames (bruiser + boss share them, recoloured)
  BR_DOWN: 832,
  SHADOW: 896,             // 32x32
  WEAPON: 912, WEAPON_UP: 916, FOOD: 920,
  GR_WIND: 924, GR_PUNCH: 988,   // thug attack: wind-up (telegraph), then the punch
  BR_WIND: 1052, BR_PUNCH: 1116,
  BG_BASE: 1180,           // background tiles are deduped from here up
}
// ---- palette banks (keep in sync with the cart) ----
const BANK = { HUD: 0, SKY: 1, GRUNT: 2, FONT: 3, FLASH: 4, PICK: 5, BOSS: 6, RUNNER: 7, BRUISER: 8, PLAYER: 9, BRICK: 10, SHOP: 11, WALK: 12, ROAD: 13, FENCE: 14, SHADOW: 15 }

// ---------- colour / palette ----------
const hex = h => [parseInt(h.slice(1, 3), 16), parseInt(h.slice(3, 5), 16), parseInt(h.slice(5, 7), 16)]
const to555 = ([r, g, b]) => ((b >> 3) << 10) | ((g >> 3) << 5) | (r >> 3)
const palette = new Uint16Array(256)
const BANKS = {}
function bank(n, colours) {          // colours: [[name, '#rrggbb'], ...] -> entries 1..15
  if (colours.length > 15) throw new Error(`bank ${n} has ${colours.length} colours`)
  const idx = {}
  colours.forEach(([cn, h], i) => { idx[cn] = i + 1; palette[n * 16 + i + 1] = to555(hex(h)) })
  return (BANKS[n] = { bank: n, idx, colours })
}
const words = (cols) => cols.map(([, h]) => to555(hex(h)))

// three stage themes: sky gradient, sky/skyline bank, brick bank, grunt bank
const SKY_NAMES = ['cl0', 'cl1', 'cl2', 'cl3', 'far0', 'far1', 'far2', 'near0', 'near1', 'near2', 'win0', 'win1', 'tank']
const STAGES = [
  { // 1: sunset
    sky: [[0, '#120e30'], [20, '#2a1a56'], [56, '#5a2a70'], [88, '#a8466e'], [108, '#ec7e58'], [124, '#ffc46e']],
    skyBank: ['#4a2f6e', '#7c4882', '#c46a86', '#f4a890', '#4c3a78', '#5e4888', '#7a5c98', '#1c1630', '#2a2044', '#3a2e5a', '#c0703a', '#ffd070', '#120e20'],
    brick: ['#4a1c1a', '#6e2a22', '#8c3a2a', '#ac5438'],
    vest: ['#1a3a1a', '#2e6a2e', '#5aa04a'],
  },
  { // 2: night
    sky: [[0, '#04040e'], [40, '#0a0c24'], [80, '#141c40'], [112, '#22305a'], [124, '#2e3e66']],
    skyBank: ['#141a30', '#222a48', '#34406a', '#56648e', '#1a2040', '#222a4e', '#2c365e', '#0a0c18', '#121628', '#1c2238', '#c08a3a', '#ffe48a', '#06060e'],
    brick: ['#1e2236', '#2c3250', '#3c4468', '#525c84'],
    vest: ['#4a1040', '#8a2078', '#c848b0'],
  },
  { // 3: hazy morning, industrial district
    sky: [[0, '#4a78b4'], [40, '#6e98c8'], [84, '#a8c0d8'], [112, '#e0d8c4'], [124, '#f4e4b8']],
    skyBank: ['#8a94b0', '#b4bccc', '#dcdee6', '#ffffff', '#7a8ca8', '#8c9cb6', '#a2b0c6', '#44506a', '#56627c', '#6c7890', '#6c6040', '#e8c870', '#2c3444'],
    brick: ['#26301e', '#34442a', '#46583a', '#5e704c'],
    vest: ['#6a3008', '#b05a12', '#e8963a'],
  },
]
function skyLines(stops) {
  const out = []
  for (let y = 0; y < 224; y++) {
    let i = 0; while (i < stops.length - 2 && y > stops[i + 1][0]) i++
    const [y0, h0] = stops[i], [y1, h1] = stops[i + 1], t = Math.max(0, Math.min(1, (y - y0) / (y1 - y0)))
    const a = hex(h0), b = hex(h1)
    out.push(to555(a.map((v, k) => Math.round(v + (b[k] - v) * t))))
  }
  return out
}

const S1 = STAGES[0]
const HUD = bank(BANK.HUD, [
  ['k', '#08080e'], ['h0', '#1e7a2e'], ['h1', '#48c040'], ['h2', '#a8f07a'], ['e0', '#3e0c10'], ['e1', '#6a181c'],
  ['r0', '#8a2008'], ['r1', '#e0501c'], ['r2', '#ffb050'], ['p0', '#6c6c7c'], ['p1', '#c4c4d0'],
])
const SKY = bank(BANK.SKY, SKY_NAMES.map((n, i) => [n, S1.skyBank[i]]))
const CHAR_NAMES = ['ol', 'sk0', 'sk1', 'sk2', 'hr0', 'hr1', 'jk0', 'jk1', 'jk2', 'jn0', 'jn1', 'jn2', 'sh0', 'sh1', 'wh']
const charBank = (n, hexes) => bank(n, CHAR_NAMES.map((cn, i) => [cn, hexes[i]]))
const GRUNT = charBank(BANK.GRUNT, ['#140e14', '#8a5a4a', '#c09078', '#ecc4a4', '#6a1a7a', '#d046d8', ...S1.vest, '#30303a', '#52525e', '#80808e', '#201818', '#4a3a3a', '#f4f0e8'])
bank(BANK.FONT, [['w', '#ffffff'], ['sh', '#101018'], ['y', '#ffe08a']])
bank(BANK.FLASH, [['ol', '#5a1020'], ...Array.from({ length: 14 }, (_, i) => ['f' + i, i % 3 === 0 ? '#ffd8d8' : '#ffffff'])])
const PICK = bank(BANK.PICK, [
  ['ol', '#141018'], ['pp0', '#4a4e5a'], ['pp1', '#8a92a0'], ['pp2', '#d8e0ea'],
  ['mt0', '#5a240e'], ['mt1', '#a0501e'], ['mt2', '#e09040'], ['bn0', '#b8a888'], ['bn1', '#f4ecd8'],
])
charBank(BANK.BOSS, ['#100810', '#4a2818', '#7a4a30', '#b07a56', '#d8d8e0', '#ffffff', '#2a0e3a', '#5a1c74', '#9a40b8', '#141018', '#26222e', '#403a4c', '#0e0a10', '#2a2430', '#ffd040'])
charBank(BANK.RUNNER, ['#0c1414', '#8a5a4a', '#c09078', '#ecc4a4', '#b08a1a', '#f4d050', '#0a3a3a', '#127070', '#30b0a0', '#1e2a4a', '#2e4070', '#4a64a0', '#201818', '#4a3a3a', '#f4f0e8'])
charBank(BANK.BRUISER, ['#140c0a', '#4a2818', '#7a4a30', '#b07a56', '#24160e', '#3e2a1c', '#3a2414', '#6a4626', '#9a6c40', '#3a2414', '#6a4626', '#9a6c40', '#1a1a1e', '#3e3e46', '#d8d8e0'])
const BRUTE_FRAME_BANK = BANKS[BANK.BRUISER]
// ---- character creator: selectable bodies and colour choices (index 0 = default) ----
// Every body uses the same bank layout (CHAR_NAMES), so any colour choice fits any body.
const BODIES = [
  { name: 'RIO', build: 'athletic', hair: 'short', face: ['band'], top: 'tank', gloves: true },
  { name: 'MARA', build: 'slim', hair: 'ponytail', face: [], top: 'jacket' },
  { name: 'TANK', build: 'heavy', hair: 'bald', face: ['beard'], top: 'vest' },
  { name: 'KENJI', build: 'athletic', hair: 'spiky', face: [], top: 'gi' },
  { name: 'ZED', build: 'slim', hair: 'mohawk', face: ['scar'], top: 'jacket' },
  { name: 'FOX', build: 'athletic', hair: 'afro', face: [], top: 'tank', gloves: true },
  { name: 'LIN', build: 'slim', hair: 'long', face: [], top: 'gi' },
  { name: 'WOLF', build: 'stocky', hair: 'long', face: ['shades', 'beard'], top: 'jacket', gloves: true },
]
const CHOICES = {        // creator rows after BODY, in cart order; ramp length per choice
  skin: { n: 3, hexes: ['#e0a070', '#f0c8a0', '#c08060', '#a86848', '#7a4a34', '#5a3424'] },
  hair: { n: 2, hexes: ['#3a2418', '#202028', '#6a4024', '#d8a040', '#b04020', '#888890', '#e030a0', '#3080e0'] },
  top: { n: 3, hexes: ['#b02028', '#e8e4dc', '#2f78d0', '#30a060', '#f0c030', '#5a2a6a', '#303038', '#e07020', '#30b0a0', '#7a4a28'] },
  bottom: { n: 3, hexes: ['#3a5ca8', '#2a2a3a', '#4a5a3a', '#ece8e0', '#c04030', '#5a6a8a', '#4a4038', '#3a1e48', '#808890', '#b09060'] },
  shoes: { n: 2, hexes: ['#3a3030', '#e8e8e8', '#c83030', '#3a2a20', '#e0c060', '#2f78d0', '#30a060', '#e030a0'] },
}
const CHAR_OUTLINE = '#140c14', CHAR_TRIM = '#f4f0e8'
const charColours = sel => ({ ...Object.fromEntries(Object.entries(CHOICES).map(([k, c]) => [k, c.hexes[sel[k] || 0]])), outline: CHAR_OUTLINE, accent: CHAR_TRIM })
Rig.makeBank(charColours({})).colours.forEach((c, i) => { palette[BANK.PLAYER * 16 + i + 1] = to555(c) })
const BODY_POSES = [['walk', 0], ['walk', Math.PI / 2], ['walk', Math.PI], ['walk', Math.PI * 1.5], ['punch', 0], ['down', 0]]   // PL_WALK x4, PL_PUNCH, PL_DOWN
const BRICK = bank(BANK.BRICK, [
  ['b0', S1.brick[0]], ['b1', S1.brick[1]], ['b2', S1.brick[2]], ['b3', S1.brick[3]], ['deep', '#200e12'],
  ['m0', '#3e3234'], ['m1', '#5e5250'], ['s0', '#8a847c'], ['s1', '#c4bcae'],
  ['g0', '#10222e'], ['g1', '#1e4a60'], ['g2', '#3c84a0'], ['g3', '#a8e4f0'], ['lit', '#ffcc66'], ['lit0', '#c4823a'],
])
const SHOP = bank(BANK.SHOP, [
  ['deep', '#0c1414'], ['w0', '#1c4444'], ['w1', '#2c6660'], ['w2', '#4a8a78'],
  ['t0', '#b4a47c'], ['t1', '#eee2bc'], ['a0', '#5e1220'], ['a1', '#a4262e'], ['a2', '#dc4a40'],
  ['aw0', '#bcb2b2'], ['aw1', '#f6f0ea'], ['gl0', '#0e1c26'], ['gl1', '#2a5a6a'], ['gl2', '#9ad4dc'], ['neon', '#ff5cc4'],
])
const WALK = bank(BANK.WALK, [
  ['sh', '#2a2832'], ['c0', '#4c4854'], ['c1', '#66626e'], ['c2', '#827e8a'], ['c3', '#9c98a2'],
  ['j', '#38343e'], ['k0', '#bab6bc'], ['k1', '#e2dee2'], ['f0', '#504c58'], ['f1', '#36323c'],
])
const ROAD = bank(BANK.ROAD, [
  ['a0', '#18181e'], ['a1', '#24242c'], ['a2', '#2e2e38'], ['a3', '#3a3a46'], ['a4', '#4a4a56'],
  ['y0', '#7c5e18'], ['y1', '#c89a2c'], ['y2', '#f0d060'],
  ['m0', '#221e1a'], ['m1', '#3e362e'], ['m2', '#5e5244'], ['m3', '#7e6e5a'],
])
const FENCE = bank(BANK.FENCE, [
  ['l0', '#4c4c5a'], ['l1', '#8e8e9c'], ['l2', '#c4c4d0'], ['p0', '#2a2a34'], ['p1', '#545462'], ['p2', '#7e7e8c'],
  ['bin0', '#1a2a1c'], ['bin1', '#2c4a30'], ['bin2', '#467a4a'],
])
bank(BANK.SHADOW, [['s', '#0e0c14']])

// ---------- layer canvases (bank + index per pixel) ----------
class Canvas {
  constructor(w, h) { this.w = w; this.h = h; this.b = new Int8Array(w * h).fill(-1); this.i = new Uint8Array(w * h) }
  set(x, y, B, c) {
    x = ((x % this.w) + this.w) % this.w
    if (y < 0 || y >= this.h) return
    const k = y * this.w + x
    if (!c) { this.b[k] = -1; this.i[k] = 0; return }
    this.b[k] = B.bank; this.i[k] = typeof c === 'string' ? B.idx[c] : c
    if (!this.i[k]) throw new Error('unknown colour ' + c)
  }
}
const hash = (x, y, s = 0) => { let h = (x * 374761393 + y * 668265263 + s * 2147483647) | 0; h = (h ^ (h >>> 13)) * 1274126177 | 0; return ((h ^ (h >>> 16)) >>> 0) / 4294967296 }

const W = 512, H = 224
const bg0 = new Canvas(W, H), bg1 = new Canvas(W, H)
const STREET_TOP = 120, CURB = 152, ROAD_TOP = 160

// ---------- BG0: clouds + two-depth skyline ----------
function cloud(cx, cy, rx, ry) {
  for (let y = cy - ry; y <= cy + ry; y++) for (let x = cx - rx; x <= cx + rx; x++) {
    let inside = false
    for (let k = -3; k <= 3; k++) {
      const px = cx + k * rx / 3.6, pr = ry * (1 - Math.abs(k) / 5), py = cy - pr * 0.35
      if (Math.hypot(x - px, (y - py) * 1.25) / pr < 1) inside = true
    }
    if (!inside || y > cy + ry * 0.45) continue
    const lit = (y - (cy - ry)) / (ry * 1.45) + hash(x >> 1, y, 3) * 0.12   // lit from below (low sun)
    bg0.set(x, y, SKY, lit > 0.82 ? 'cl3' : lit > 0.58 ? 'cl2' : lit > 0.32 ? 'cl1' : 'cl0')
  }
}
cloud(60, 22, 46, 12); cloud(210, 12, 34, 8); cloud(330, 30, 58, 13); cloud(460, 16, 40, 10)
let x = 0
while (x < W) {                       // far skyline (hazy)
  const w = 24 + Math.floor(hash(x, 1) * 5) * 8, top = 32 + Math.floor(hash(x, 2) * 5) * 8
  for (let yy = top; yy < H; yy++) for (let xx = x; xx < Math.min(W, x + w); xx++) bg0.set(xx, yy, SKY, xx === x ? 'far2' : (xx >= x + w - 3 ? 'far0' : 'far1'))
  if (hash(x, 9) > 0.5) for (let yy = top - 12; yy < top; yy++) bg0.set(x + (w >> 1), yy, SKY, 'far1')
  x += w
}
x = 8
while (x < W + 8) {                   // near skyline (dark) with lit windows + water towers
  const w = 32 + Math.floor(hash(x, 4) * 4) * 8, top = 56 + Math.floor(hash(x, 5) * 3) * 8
  for (let yy = top; yy < H; yy++) for (let xx = x; xx < x + w; xx++) bg0.set(xx, yy, SKY, (xx - x) < 2 ? 'near2' : (x + w - xx) <= 4 ? 'near0' : 'near1')
  for (let wy = top + 6; wy < 124; wy += 8) for (let wx = x + 4; wx < x + w - 6; wx += 6) {
    const r = hash(wx, wy, 7)
    if (r < 0.35) { const c = r < 0.15 ? 'win1' : 'win0'; bg0.set(wx, wy, SKY, c); bg0.set(wx + 1, wy, SKY, c); bg0.set(wx, wy + 1, SKY, 'win0'); bg0.set(wx + 1, wy + 1, SKY, 'win0') }
  }
  if (hash(x, 6) > 0.6) {
    const tx = x + 8
    for (let yy = top - 14; yy < top - 4; yy++) for (let xx = tx; xx < tx + 12; xx++) bg0.set(xx, yy, SKY, (yy === top - 14 || xx === tx + 11) ? 'tank' : 'near1')
    for (let yy = top - 4; yy < top; yy++) { bg0.set(tx + 1, yy, SKY, 'tank'); bg0.set(tx + 10, yy, SKY, 'tank') }
  }
  x += w + 8 * Math.floor(hash(x, 8) * 2)
}

// ---------- BG1: street ----------
for (let y = STREET_TOP; y < CURB; y++) for (let x = 0; x < W; x++) {   // sidewalk, slanted slab joints
  const d = y - STREET_TOP, jx = (x - Math.floor(d * 0.75)) & 31
  let c = d < 3 ? 'sh' : d < 5 ? 'c0' : 'c2'
  if (d >= 5) { const n = hash(x & 31, y, 11); c = n < 0.08 ? 'c1' : n > 0.95 ? 'c3' : (d > 24 ? 'c1' : 'c2') }
  if (jx === 0 && d >= 3) c = 'j'
  if (jx === 1 && d >= 3) c = 'c3'
  if (d === 16) c = jx === 0 ? 'j' : 'c1'
  bg1.set(x, y, WALK, c)
}
for (let y = CURB; y < ROAD_TOP; y++) for (let x = 0; x < W; x++) { const d = y - CURB; bg1.set(x, y, WALK, d === 0 ? 'k1' : d < 3 ? 'k0' : d < 5 ? 'f0' : 'f1') }
for (let y = ROAD_TOP; y < H; y++) for (let x = 0; x < W; x++) {         // asphalt, 32px period so tiles dedupe
  const d = y - ROAD_TOP, n = hash(x & 31, y, 21)
  let c = d < 3 ? 'a0' : d < 6 ? 'a1' : (n < 0.10 ? 'a1' : n > 0.985 ? 'a4' : n > 0.93 ? 'a3' : 'a2')
  if (y >= 192 && y < 196 && (x & 63) >= 8 && (x & 63) < 40) c = y === 192 ? 'y2' : y === 195 ? 'y0' : 'y1'
  bg1.set(x, y, ROAD, c)
}
for (let y = 204; y <= 216; y++) for (let x = 136; x <= 168; x++) {     // manhole
  const e = Math.hypot((x - 152) / 16, (y - 210) / 6)
  if (e <= 1) bg1.set(x, y, ROAD, e > 0.82 ? (y < 210 ? 'm0' : 'm3') : e > 0.7 ? 'm1' : ((x + y * 2) & 3) === 0 ? 'm1' : 'm2')
}

function brickA(x0, x1, top) {
  for (let y = top; y < STREET_TOP; y++) for (let x = x0; x < x1; x++) {
    const row = Math.floor((y - top) / 6), ry = (y - top) % 6, bx = (x - x0 + (row & 1) * 8) & 15
    let c
    if (ry === 5 || bx === 15) c = 'm0'
    else {
      const v = hash(Math.floor((x - x0 + (row & 1) * 8) / 16), row, 31)
      c = v < 0.3 ? 'b1' : v > 0.85 ? 'b3' : 'b2'
      if (ry === 0) c = c === 'b1' ? 'b2' : 'b3'
      if (ry === 4) c = 'b1'
    }
    bg1.set(x, y, BRICK, c)
  }
  for (let y = top - 8; y < top; y++) for (let x = x0; x < x1; x++) {     // cornice
    const d = y - (top - 8)
    bg1.set(x, y, BRICK, d === 0 ? 's1' : d < 5 ? ((x & 7) === 0 && d > 1 ? 's0' : 's1') : d === 5 ? 's0' : 'deep')
  }
  for (let x = x0; x < x1; x++) bg1.set(x, top, BRICK, 'deep')
  for (let wx = x0 + 16; wx + 32 <= x1 - 8; wx += 48) {                  // one floor of windows
    const wy = top + 10, lit = hash(wx, 0, 41) > 0.55
    for (let y = wy - 2; y < wy + 30; y++) for (let x = wx - 2; x < wx + 26; x++) {
      const fx = x - wx, fy = y - wy
      let c
      if (fy < 0) c = fy === -2 ? 's1' : 's0'
      else if (fy >= 26) c = fy === 26 ? 's1' : fy === 27 ? 's0' : 'deep'
      else if (fx < 0 || fx >= 24) c = fx === -2 ? 'deep' : 'm1'
      else if (fx === 11 || fx === 12 || fy === 12) c = fx === 12 ? 's0' : 's1'
      else if (lit) c = (fy > 18 && ((fx + fy) & 3) === 0) ? 'lit0' : 'lit'
      else { const s = (fx - fy + 40) % 22; c = s < 3 ? 'g3' : s < 6 ? 'g2' : fy < 4 ? 'g0' : 'g1' }
      bg1.set(x, y, BRICK, c)
    }
  }
  const sy = 80                                                           // roller shutter
  for (let y = sy; y < STREET_TOP; y++) for (let x = x0 + 12; x < x1 - 12; x++) {
    const d = y - sy
    let c = d < 4 ? (d === 0 ? 's1' : 'm1') : ((d & 3) === 0 ? 'm0' : (d & 3) === 1 ? 's1' : 's0')
    if (x === x0 + 12 || x === x1 - 13) c = 'deep'
    bg1.set(x, y, BRICK, c)
  }
}
brickA(0, 200, 32)
brickA(480, 512, 32)

for (let y = 64; y < STREET_TOP; y++) for (let x = 200; x < 272; x++) {  // chain-link fence (skyline shows through)
  const fx = x - 200, fy = y - 64
  let c = 0
  if (fx % 24 === 2 || fx % 24 === 3) c = fx % 24 === 2 ? 'p2' : 'p0'
  else if (fy < 2) c = fy === 0 ? 'p2' : 'p1'
  else if ((fx + fy) % 6 === 0) c = 'l2'
  else if ((fx - fy + 600) % 6 === 0) c = 'l0'
  if (c) bg1.set(x, y, FENCE, c)
}
for (let y = 96; y < STREET_TOP; y++) for (let x = 216; x < 256; x++) {  // dumpster
  const fx = x - 216, fy = y - 96
  let c = fy < 4 ? (fy === 0 ? 'bin2' : 'bin1') : (fx < 3 ? 'bin2' : fx > 36 ? 'bin0' : (fx % 10 === 5 ? 'bin0' : 'bin1'))
  if (fy >= 20) c = (fx === 4 || fx === 35) ? 'p0' : 0
  if (c) bg1.set(x, y, FENCE, c)
}

// ---------- 5x7 font ----------
const GLYPHS = {
  A: [' ### ', '#   #', '#   #', '#####', '#   #', '#   #', '#   #'], B: ['#### ', '#   #', '#   #', '#### ', '#   #', '#   #', '#### '],
  C: [' ####', '#    ', '#    ', '#    ', '#    ', '#    ', ' ####'], D: ['#### ', '#   #', '#   #', '#   #', '#   #', '#   #', '#### '],
  E: ['#####', '#    ', '#    ', '#### ', '#    ', '#    ', '#####'], F: ['#####', '#    ', '#    ', '#### ', '#    ', '#    ', '#    '],
  G: [' ####', '#    ', '#    ', '#  ##', '#   #', '#   #', ' ### '], H: ['#   #', '#   #', '#   #', '#####', '#   #', '#   #', '#   #'],
  I: ['#####', '  #  ', '  #  ', '  #  ', '  #  ', '  #  ', '#####'], J: ['  ###', '   # ', '   # ', '   # ', '#  # ', '#  # ', ' ##  '],
  K: ['#   #', '#  # ', '# #  ', '##   ', '# #  ', '#  # ', '#   #'], L: ['#    ', '#    ', '#    ', '#    ', '#    ', '#    ', '#####'],
  M: ['#   #', '## ##', '# # #', '#   #', '#   #', '#   #', '#   #'], N: ['#   #', '##  #', '# # #', '#  ##', '#   #', '#   #', '#   #'],
  O: [' ### ', '#   #', '#   #', '#   #', '#   #', '#   #', ' ### '], P: ['#### ', '#   #', '#   #', '#### ', '#    ', '#    ', '#    '],
  Q: [' ### ', '#   #', '#   #', '#   #', '# # #', '#  # ', ' ## #'], R: ['#### ', '#   #', '#   #', '#### ', '# #  ', '#  # ', '#   #'],
  S: [' ####', '#    ', '#    ', ' ### ', '    #', '    #', '#### '], T: ['#####', '  #  ', '  #  ', '  #  ', '  #  ', '  #  ', '  #  '],
  U: ['#   #', '#   #', '#   #', '#   #', '#   #', '#   #', ' ### '], V: ['#   #', '#   #', '#   #', '#   #', '#   #', ' # # ', '  #  '],
  W: ['#   #', '#   #', '#   #', '# # #', '# # #', '## ##', '#   #'], X: ['#   #', '#   #', ' # # ', '  #  ', ' # # ', '#   #', '#   #'],
  Y: ['#   #', '#   #', ' # # ', '  #  ', '  #  ', '  #  ', '  #  '], Z: ['#####', '    #', '   # ', '  #  ', ' #   ', '#    ', '#####'],
}
const ARROWS = { l: ['   # ', '  ## ', ' ### ', '#### ', ' ### ', '  ## ', '   # '], r: [' #   ', ' ##  ', ' ### ', ' ####', ' ### ', ' ##  ', ' #   '] }
const DIGITS = [
  [' ### ', '#   #', '#  ##', '# # #', '##  #', '#   #', ' ### '], ['  #  ', ' ##  ', '  #  ', '  #  ', '  #  ', '  #  ', ' ### '],
  [' ### ', '#   #', '    #', '   # ', '  #  ', ' #   ', '#####'], ['#####', '   # ', '  #  ', '   # ', '    #', '#   #', ' ### '],
  ['   # ', '  ## ', ' # # ', '#  # ', '#####', '   # ', '   # '], ['#####', '#    ', '#### ', '    #', '    #', '#   #', ' ### '],
  ['  ## ', ' #   ', '#    ', '#### ', '#   #', '#   #', ' ### '], ['#####', '    #', '   # ', '  #  ', ' #   ', ' #   ', ' #   '],
  [' ### ', '#   #', '#   #', ' ### ', '#   #', '#   #', ' ### '], [' ### ', '#   #', '#   #', ' ####', '    #', '   # ', ' ##  '],
]
// 8x8 glyph tile, bank FONT: white upper rows, warm lower rows, dark drop shadow at (+1,+1)
function glyphTile(g) {
  const px = new Array(64).fill(0)
  g.forEach((row, y) => [...row].forEach((v, x) => { if (v === '#') { const k = (y + 1) * 8 + x + 2; if (px[k] === 0) px[k] = 2 } }))
  g.forEach((row, y) => [...row].forEach((v, x) => { if (v === '#') px[y * 8 + x + 1] = y < 3 ? 1 : 3 }))
  return px
}

// ---------- rigged characters ----------
const L = (() => { const v = [-0.55, -0.7, 0.55], m = Math.hypot(...v); return v.map(c => c / m) })()
function renderRig(B, parts, S = 64) {
  const part = new Int16Array(S * S).fill(-1), shade = new Float32Array(S * S), mat = new Array(S * S)
  parts.forEach((p, pi) => {
    for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
      const px = x + 0.5, py = y + 0.5
      let nx, ny
      if (p.cap) {
        const [ax, ay] = p.cap[0], [bx, by] = p.cap[1], vx = bx - ax, vy = by - ay
        const t = Math.max(0, Math.min(1, ((px - ax) * vx + (py - ay) * vy) / (vx * vx + vy * vy || 1)))
        const r = p.r[0] + (p.r[1] - p.r[0]) * t, dx = px - (ax + vx * t), dy = py - (ay + vy * t)
        if (dx * dx + dy * dy > r * r) continue
        nx = dx / r; ny = dy / r
      } else {
        const [cx, cy] = p.ell, dx = (px - cx) / p.rx, dy = (py - cy) / p.ry
        if (dx * dx + dy * dy > 1) continue
        if (p.clip && !p.clip(px, py)) continue
        nx = dx; ny = dy
      }
      const nz = Math.sqrt(Math.max(0, 1 - nx * nx - ny * ny))
      let I = nx * L[0] + ny * L[1] + nz * L[2]
      if (p.back) I -= 0.35
      const k = y * S + x
      part[k] = pi; shade[k] = I; mat[k] = p.mat
    }
  })
  const out = new Uint8Array(S * S)
  for (let k = 0; k < S * S; k++) {
    if (part[k] < 0) continue
    const m = mat[k]
    if (m === 'ol' || m === 'wh') { out[k] = B.idx[m]; continue }
    const ramp = [B.idx[m + '0'], B.idx[m + '1'], B.idx[m + '2']].filter(Boolean)
    let s = shade[k] > 0.62 ? 2 : shade[k] > 0.2 ? 1 : 0
    out[k] = ramp[Math.min(s, ramp.length - 1)]
  }
  for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {         // separation line where a part passes in front
    const k = y * S + x
    if (part[k] < 0) continue
    for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
      const xx = x + dx, yy = y + dy
      if (xx < 0 || yy < 0 || xx >= S || yy >= S) continue
      const o = part[yy * S + xx]
      if (o > part[k] && mat[yy * S + xx] !== mat[k] && mat[k] !== 'ol') { if (B.idx[mat[k] + '0']) out[k] = B.idx[mat[k] + '0']; break }
    }
  }
  const res = out.slice()                                              // exterior outline
  for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
    const k = y * S + x
    if (out[k]) continue
    for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) { const xx = x + dx, yy = y + dy; if (xx >= 0 && yy >= 0 && xx < S && yy < S && out[yy * S + xx]) { res[k] = B.idx.ol; break } }
  }
  return res
}
const add = (a, b) => [a[0] + b[0], a[1] + b[1]]
const pol = (len, ang) => [Math.sin(ang) * len, Math.cos(ang) * len]   // angle from straight down, + = forward (+x)
function figure(opt, phase) {
  const s = opt.scale || 1, bulk = opt.bulk || 1, thigh = 13 * s, shin = 13 * s, torso = 18 * s
  const legs = [phase + Math.PI, phase].map(ph => {    // [back, front]
    const th = (opt.stride || 0) * Math.sin(ph)
    return { th, sh: th - (0.15 + 0.7 * Math.max(0, Math.cos(ph)) * (opt.stride ? 1 : 0)) }
  })
  if (opt.stance) { legs[0] = { th: -0.28, sh: -0.18 }; legs[1] = { th: 0.32, sh: 0.12 } }
  const legDrop = l => Math.cos(l.th) * thigh + Math.cos(l.sh) * shin
  const hip = [32 + (opt.dx || 0), 61 - Math.max(...legs.map(legDrop)) - 2]
  const sho = add(hip, [2 * s + (opt.lean || 0), -torso])
  const head = add(sho, [1.5 * s + (opt.lean || 0) * 0.5, -8.5 * s])
  const P = []
  const leg = (l, back) => {
    const knee = add(hip, pol(thigh, l.th)), ankle = add(knee, pol(shin, l.sh))
    P.push({ cap: [hip, knee], r: [4.6 * s * bulk, 3.9 * s * bulk], mat: 'jn', back })
    P.push({ cap: [knee, ankle], r: [3.8 * s * bulk, 3.2 * s], mat: 'jn', back })
    P.push({ ell: add(ankle, [2.4 * s, 0.8]), rx: 4.4 * s, ry: 2.6 * s, mat: 'sh', back })
  }
  const arm = (a, back) => {
    const elb = add(sho, pol(9 * s, a.up)), wr = add(elb, pol(9 * s, a.fo))
    P.push({ cap: [sho, elb], r: [3.8 * s * bulk, 3.2 * s * bulk], mat: opt.sleeves ? 'jk' : 'sk', back })
    P.push({ cap: [elb, wr], r: [3.2 * s * bulk, 2.8 * s], mat: opt.sleeves === 'long' ? 'jk' : 'sk', back })
    P.push({ ell: add(wr, pol(1.2, a.fo)), rx: 3.4 * s, ry: 3.2 * s, mat: 'sk', back })
  }
  let arms = [{ up: -0.6 * Math.sin(phase), fo: -0.6 * Math.sin(phase) + 0.8 }, { up: 0.6 * Math.sin(phase), fo: 0.6 * Math.sin(phase) + 0.8 }]
  if (opt.guard) arms = [{ up: 0.8, fo: 2.3 }, { up: 0.45, fo: 2.0 }]
  if (opt.punch) arms = [{ up: 0.6, fo: 2.2 }, { up: 1.55, fo: 1.6 }]
  if (opt.windup) arms = [{ up: 1.1, fo: 2.4 }, { up: -1.35, fo: -2.6 }]   // lead fist cocked back by the ear
  arm(arms[0], true)
  leg(legs[0], true)
  leg(legs[1], false)
  P.push({ ell: add(hip, [0, -1]), rx: 6.2 * s * bulk, ry: 4.2 * s, mat: 'jn' })
  P.push({ cap: [add(hip, [0, -3]), add(sho, [0, 3])], r: [6 * s * (opt.belly || 1), 8 * s * bulk], mat: 'jk' })
  if (opt.vestOpen) P.push({ cap: [add(hip, [3 * s, -4]), add(sho, [3.5 * s, 4])], r: [2.2 * s, 2.6 * s], mat: 'sk' })
  P.push({ cap: [sho, add(head, [0, 4])], r: [2.8 * s, 2.6 * s], mat: 'sk' })
  P.push({ ell: head, rx: 5.6 * s, ry: 6.4 * s, mat: 'sk' })
  if (opt.hair === 'short') P.push({ ell: add(head, [-1.6, -2.6]), rx: 6.2 * s, ry: 5.2 * s, mat: 'hr', clip: (x, y) => y < head[1] - 1.5 || x < head[0] - 2 })
  if (opt.hair === 'mohawk') P.push({ cap: [add(head, [-4, -4]), add(head, [3, -8])], r: [2.2, 1.6], mat: 'hr' })
  if (opt.hair === 'beard') P.push({ ell: add(head, [1.5, 3.5]), rx: 4.2 * s, ry: 3.2 * s, mat: 'hr', clip: (x, y) => y > head[1] + 1 })
  if (opt.band) { P.push({ cap: [add(head, [-5.6, -2.4]), add(head, [5.6, -3.0])], r: [0.9, 0.9], mat: 'jk' }); P.push({ cap: [add(head, [-5.2, -2.6]), add(head, [-11, 1 + Math.sin(phase * 2)])], r: [1.2, 0.8], mat: 'jk' }) }
  P.push({ ell: add(head, [2.8 * s, -0.4]), rx: 0.7, ry: 1.2, mat: 'ol' })
  arm(arms[1], false)
  return P
}
// lying on the back (head to the left), sat on the bottom of the 64x64 box
function knockedDown(img) {
  const out = new Uint8Array(64 * 64)
  let maxY = 0
  for (let oy = 0; oy < 64; oy++) for (let ox = 0; ox < 64; ox++) if (img[oy * 64 + ox]) maxY = Math.max(maxY, 63 - ox)
  const dy = 62 - maxY
  for (let oy = 0; oy < 64; oy++) for (let ox = 0; ox < 64; ox++) {
    const v = img[oy * 64 + ox]; if (!v) continue
    const nx = oy, ny = 63 - ox + dy
    if (ny >= 0 && ny < 64) out[ny * 64 + nx] = v
  }
  return out
}

// ---------- VRAM ----------
const tiles = new Uint8Array(2048 * 32)
let topTile = T.BG_BASE
function putTile(t, px) {
  if (px.length !== 64) throw new Error('tile needs 64 px')
  for (let i = 0; i < 64; i += 2) tiles[t * 32 + (i >> 1)] = ((px[i] & 15) << 4) | (px[i + 1] & 15)
}
function putBlock(base, img, S) {                     // SxS image -> consecutive row-major tiles
  const n = S >> 3
  for (let ty = 0; ty < n; ty++) for (let tx = 0; tx < n; tx++) {
    const px = []; for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x++) px.push(img[(ty * 8 + y) * S + tx * 8 + x])
    putTile(base + ty * n + tx, px)
  }
}
// HUD cells (bank HUD)
const H_ = HUD.idx
const rowsTile = rows => { const px = []; rows.forEach(c => { for (let i = 0; i < 8; i++) px.push(Array.isArray(c) ? c[i] : c) }); return px }
putTile(T.HP_FULL, rowsTile([H_.k, H_.h2, H_.h1, H_.h1, H_.h1, H_.h0, H_.h0, H_.k]))
putTile(T.HP_EMPTY, rowsTile([H_.k, H_.e1, H_.e1, H_.e0, H_.e0, H_.e0, H_.e0, H_.k]))
putTile(T.BHP_FULL, rowsTile([H_.k, H_.r2, H_.r1, H_.r1, H_.r1, H_.r0, H_.r0, H_.k]))
putTile(T.WPN_ICON, rowsTile([0, 0, [0, H_.k, H_.k, H_.k, H_.k, H_.k, H_.k, 0], [H_.k, H_.p1, H_.p1, H_.p1, H_.p1, H_.p1, H_.p1, H_.k], [H_.k, H_.p0, H_.p0, H_.p0, H_.p0, H_.p0, H_.p0, H_.k], [0, H_.k, H_.k, H_.k, H_.k, H_.k, H_.k, 0], 0, 0]))
Object.keys(GLYPHS).forEach(ch => putTile(T.FONT + ch.charCodeAt(0) - 65, glyphTile(GLYPHS[ch])))
putTile(T.ARROWL, glyphTile(ARROWS.l))
putTile(T.ARROWR, glyphTile(ARROWS.r))
for (let k = 1; k <= 15; k++) putTile(T.SOLID + k - 1, new Array(64).fill(k))
DIGITS.forEach((g, d) => putTile(T.DIGIT + d, glyphTile(g)))

// fighters
// the player: every selectable body as 6 consecutive 64x64 frames; body 0 also boots in VRAM
const bodyTiles = BODIES.map(b => {
  const blk = new Uint8Array(BODY_POSES.length * 64 * 32)
  BODY_POSES.forEach(([pose, phase], f) => {
    const { img } = Rig.draw({ ...b, pose, phase, colours: charColours({}) })
    for (let ty = 0; ty < 8; ty++) for (let tx = 0; tx < 8; tx++) for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x += 2) {
      const o = ((f * 64 + ty * 8 + tx) * 32) + y * 4 + (x >> 1), k = (ty * 8 + y) * 64 + tx * 8 + x
      blk[o] = (img[k] << 4) | img[k + 1]
    }
  })
  return blk
})
tiles.set(bodyTiles[0], T.PL_WALK * 32)
const gruntOpt = { hair: 'mohawk', guard: true, vestOpen: true, stride: 0.35 }
for (let f = 0; f < 2; f++) putBlock(T.GR_WALK + f * 64, renderRig(GRUNT, figure(gruntOpt, f * Math.PI + Math.PI / 2)), 64)
putBlock(T.GR_DOWN, knockedDown(renderRig(GRUNT, figure({ ...gruntOpt, guard: false, stride: 0 }, 0))), 64)
putBlock(T.GR_WIND, renderRig(GRUNT, figure({ ...gruntOpt, guard: false, windup: true, stride: 0.2, lean: -3 }, Math.PI / 2)), 64)
putBlock(T.GR_PUNCH, renderRig(GRUNT, figure({ ...gruntOpt, guard: false, punch: true, stride: 0.45, lean: 2.5 }, Math.PI / 2)), 64)
const bruteOpt = { hair: 'beard', guard: true, bulk: 1.35, belly: 1.45, sleeves: true, stride: 0.25 }
for (let f = 0; f < 2; f++) putBlock(T.BR_WALK + f * 64, renderRig(BRUTE_FRAME_BANK, figure(bruteOpt, f * Math.PI + Math.PI / 2)), 64)
putBlock(T.BR_DOWN, knockedDown(renderRig(BRUTE_FRAME_BANK, figure({ ...bruteOpt, guard: false, stride: 0 }, 0))), 64)
putBlock(T.BR_WIND, renderRig(BRUTE_FRAME_BANK, figure({ ...bruteOpt, guard: false, windup: true, stride: 0.15, lean: -3 }, Math.PI / 2)), 64)
putBlock(T.BR_PUNCH, renderRig(BRUTE_FRAME_BANK, figure({ ...bruteOpt, guard: false, punch: true, stride: 0.35, lean: 2.5 }, Math.PI / 2)), 64)
// shadow (32x32, ellipse near the bottom) and 16x16 pickups
const shadow = new Uint8Array(32 * 32)
for (let y = 0; y < 32; y++) for (let x = 0; x < 32; x++) if (Math.hypot((x + 0.5 - 16) / 14, (y + 0.5 - 28) / 3.4) < 1) shadow[y * 32 + x] = 1
putBlock(T.SHADOW, shadow, 32)
putBlock(T.WEAPON, renderRig(PICK, [{ cap: [[2, 8], [14, 7]], r: [1.8, 1.8], mat: 'pp' }], 16), 16)
putBlock(T.WEAPON_UP, renderRig(PICK, [{ cap: [[3, 13], [13, 2]], r: [1.8, 1.8], mat: 'pp' }], 16), 16)
putBlock(T.FOOD, renderRig(PICK, [
  { cap: [[8, 9], [11, 13]], r: [1.2, 1.2], mat: 'bn' }, { ell: [12, 13.5], rx: 2, ry: 1.4, mat: 'bn' },
  { ell: [6.5, 6.5], rx: 5, ry: 4.4, mat: 'mt' },
], 16), 16)

// background layers -> deduped tiles (with flips) + map entries
const tileKey = new Map([['0'.repeat(64), { t: 0 }]])
function addBgTile(px) {
  const variants = [[false, false], [true, false], [false, true], [true, true]]
  for (const [h, v] of variants) {
    const f = []; for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x++) f.push(px[(v ? 7 - y : y) * 8 + (h ? 7 - x : x)])
    const hit = tileKey.get(f.join(','))
    if (hit) return { t: hit.t, h, v }
  }
  const t = topTile++
  if (t >= 2048) throw new Error('VRAM tile budget exceeded')
  putTile(t, px); tileKey.set(px.join(','), { t })
  return { t, h: false, v: false }
}
function packLayer(cv) {
  const map = new Uint32Array(64 * 28)
  for (let ty = 0; ty < 28; ty++) for (let tx = 0; tx < 64; tx++) {
    const px = [], banks = new Set()
    for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x++) { const k = (ty * 8 + y) * W + tx * 8 + x; px.push(cv.i[k]); if (cv.b[k] >= 0) banks.add(cv.b[k]) }
    if (banks.size > 1) throw new Error(`tile (${tx},${ty}) mixes palette banks ${[...banks]}: move the edge onto a tile boundary`)
    const r = addBgTile(px), pal = banks.size ? [...banks][0] : 0
    map[ty * 64 + tx] = ((r.t & 0x7ff) | (pal << 11) | (r.h ? 1 << 15 : 0) | (r.v ? 1 << 16 : 0)) >>> 0
  }
  return map
}
const map0 = packLayer(bg0), map1 = packLayer(bg1)

// ---------- write ----------
const le16 = arr => { const b = Buffer.alloc(arr.length * 2); arr.forEach((v, i) => b.writeUInt16LE(v, i * 2)); return b }
const tileBytes = topTile * 32
if (tileBytes > 0xffff) throw new Error('tile region too large for one DMA')
const levelRec = st => le16([...skyLines(st.sky), ...st.skyBank.map(h => to555(hex(h))),
  ...words(BANKS[BANK.GRUNT].colours.map(([n, h], i) => [n, (i >= 6 && i <= 8) ? st.vest[i - 6] : h])),
  ...words(BANKS[BANK.BRICK].colours.map(([n, h], i) => [n, i < 4 ? st.brick[i] : h]))])
const files = {
  'tiles.bin': Buffer.from(tiles.subarray(0, tileBytes)),
  'maps.bin': Buffer.concat([Buffer.from(map0.buffer), Buffer.from(map1.buffer)]),
  'pal.bin': le16([...palette]),
  'levels.bin': Buffer.concat(STAGES.map(levelRec)),
  'bodies.bin': Buffer.concat(bodyTiles.map(b => Buffer.from(b))),
  'charpal.bin': le16([...Object.values(CHOICES).flatMap(c => c.hexes.flatMap(h => Rig.ramp(h, c.n).map(to555))),
    to555(hex(CHAR_OUTLINE)), to555(hex(CHAR_TRIM))]),
}
const levelRecordBytes = files['levels.bin'].length / STAGES.length
if (require.main === module) {
  for (const [name, buf] of Object.entries(files)) fs.writeFileSync(path.join(__dirname, name), buf)
  console.log(`streetbrawl art: ${topTile} tiles (${topTile - T.BG_BASE} background), level record ${levelRecordBytes} bytes`)
}
const bodyBytes = bodyTiles[0].length
module.exports = { T, BANK, files, tileCount: topTile, levelRecordBytes, BODIES, CHOICES, bodyBytes, GLYPHS, DIGITS, ARROWS, CHAR_OUTLINE, CHAR_TRIM }
