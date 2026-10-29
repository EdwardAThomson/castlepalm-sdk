#!/usr/bin/env node
'use strict'
// SWORN RIVALS — art generator for the versus fighter.
//
// Draws every asset from code and writes the blobs swornrivals.asm INCBINs:
//
//   tiles.bin   VRAM tile region from tile 0 (HUD, fonts, sparks, courtyard)
//   maps.bin    BG0 then BG1 map, 64x28 cells x 4 bytes each
//   pal.bin     all 256 palette entries (fighter banks 8/9 are filled at runtime)
//   stages.bin  per rival: a 224-word sky gradient + sky bank 1 (12 words)
//   bodies.bin  NBODY bodies x NPOSE poses x 64 tiles: streamed into the
//               fighter slots every frame by DMA
//
// The creator's colour ramps are Street Brawl's (examples/streetbrawl/charpal.bin), and the
// bodies are Street Brawl's eight, drawn in the extra fighting poses of examples/streetbrawl/rig.js.
//
// The courtyard is painted with named colours; packLayer then picks, per 8x8 tile, the
// first background bank that holds every colour in it (and throws if none does).
//
//   node examples/swornrivals/gen_art.js

const fs = require('fs')
const path = require('path')
const Rig = require('../streetbrawl/rig.js')
const SB = require('../streetbrawl/gen_art.js')

const TITLE = 'SWORN RIVALS'

// ---- fixed tile indices (keep in sync with the EQUs in swornrivals.asm) ----
const T = {
  HP_FULL: 1, HP_HALF: 2, HP_EMPTY: 3, MT_FULL: 4, MT_EMPTY: 5, MT_READY: 6,
  SEAL_OK: 7, SEAL_BROKE: 8, SEAL_NONE: 9, PIP_ON: 10, PIP_OFF: 11, HP_HALFR: 12,
  SOLID: 16,               // 15 swatches: SOLID + k - 1 is filled with colour k
  FONT: 0,                 // 8x8 font: tile = ASCII code (32..95)
  P1SLOT: 128, P2SLOT: 192,// 64 tiles each: the fighters' current frame (DMA'd each frame)
  BIG: 256,                // 16x16 font: BIG + (ASCII - 32) * 4
  TITLE: 512,              // 32x32 title letters, 16 tiles each, in TITLE order (spaces skipped)
  SPARK: 688, BSPARK: 696, // 16x16 hit / block sparks, 2 frames each
  SHADOW: 704,             // 32x32
  BG_BASE: 720,
}
const BANK = { HUD: 0, SKY: 1, STONE: 2, FONT: 3, FLASH: 4, SPARK: 5, GATE: 6, PALM: 7, P2: 8, P1: 9, FLOOR: 10, BANNER: 11, BIG: 12, TITLE: 13, SHADOW: 15 }
const POSES = [['guard', 0], ['gwalk', Math.PI / 2], ['gwalk', Math.PI * 1.5], ['crouch', 0], ['jump', 0], ['punch', 0], ['kick', 0],
  ['cpunch', 0], ['lowkick', 0], ['airpunch', 0], ['airkick', 0], ['block', 0], ['cblock', 0], ['hurt', 0], ['down', 0], ['rise', 0], ['win', 0]]
const POSE = Object.fromEntries(POSES.map(([n], i) => [n, i]))   // gwalk -> 1 (2 is the second walk frame)
const POSE_BYTES = 64 * 32
const BODIES = SB.BODIES
// 1P ladder: body + creator picks (skin, hair, top, legs, shoes) per rival
const RIVALS = [
  { body: 'TANK', picks: [3, 1, 6, 1, 3] },
  { body: 'MARA', picks: [1, 4, 2, 3, 1] },
  { body: 'KENJI', picks: [2, 1, 1, 7, 0] },
  { body: 'WOLF', picks: [4, 5, 5, 8, 0] },
]

// ---------- colour / palette ----------
const hex = h => [parseInt(h.slice(1, 3), 16), parseInt(h.slice(3, 5), 16), parseInt(h.slice(5, 7), 16)]
const to555 = ([r, g, b]) => ((b >> 3) << 10) | ((g >> 3) << 5) | (r >> 3)
const palette = new Uint16Array(256)
const BANKS = {}
function bank(n, colours) {                 // [[name, '#rrggbb'], ...] -> entries 1..15
  if (colours.length > 15) throw new Error(`bank ${n} has ${colours.length} colours`)
  const idx = {}
  colours.forEach(([cn, h], i) => { idx[cn] = i + 1; palette[n * 16 + i + 1] = to555(hex(h)) })
  return (BANKS[n] = { bank: n, idx, colours })
}

// per-rival skies: gradient stops + the BG0 bank (clouds, far palace, domes, far palms, lamps)
const SKY_NAMES = ['cl0', 'cl1', 'cl2', 'cl3', 'pa0', 'pa1', 'pa2', 'dm0', 'dm1', 'pf0', 'pf1', 'lamp']
const STAGES = [
  { // morning
    sky: [[0, '#3a6cc0'], [60, '#6a9ad8'], [110, '#b4d0ec'], [140, '#f0e4c8']],
    bank: ['#b8c8e4', '#d8e2f2', '#f0f4fa', '#ffffff', '#7a8cb4', '#94a6c8', '#b2c0da', '#c09a48', '#f0d488', '#5a7aa0', '#6a8cb0', '#fff0b0'],
  },
  { // noon
    sky: [[0, '#1a58c8'], [70, '#3a80e0'], [130, '#88c0f0']],
    bank: ['#a8c4ec', '#cadcf6', '#ecf2fc', '#ffffff', '#c8b490', '#dcc8a4', '#f0e2c4', '#c8902c', '#ffd65a', '#4a8a5a', '#5ea06a', '#fff4c0'],
  },
  { // sunset
    sky: [[0, '#241848'], [40, '#5a2a70'], [90, '#c0506a'], [124, '#f49a5a'], [140, '#ffd27a']],
    bank: ['#6a3a6e', '#a8507a', '#e88a7a', '#ffc49a', '#3a2650', '#4c3062', '#603c74', '#a05a30', '#ffb04a', '#2a1a3a', '#3a2448', '#ffd070'],
  },
  { // dusk
    sky: [[0, '#06081c'], [60, '#121a40'], [110, '#2c3466'], [140, '#5a4a78']],
    bank: ['#1c2244', '#2a3258', '#3c4670', '#5a6690', '#141a34', '#1c2444', '#283258', '#6a5020', '#e0b048', '#0c1024', '#141a32', '#ffe08a'],
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

const HUD = bank(BANK.HUD, [
  ['k', '#08080e'], ['h0', '#1e7a2e'], ['h1', '#48c040'], ['h2', '#a8f07a'], ['e0', '#3e0c10'], ['e1', '#6a181c'],
  ['m0', '#8a5a08'], ['m1', '#e0a020'], ['m2', '#fff07a'], ['n0', '#2a2a36'], ['n1', '#4a4a5a'],
  ['r0', '#7a1418'], ['r1', '#e04838'], ['w', '#ffffff'], ['c', '#6ae0ff'],
])
const SKY = bank(BANK.SKY, SKY_NAMES.map((n, i) => [n, STAGES[0].bank[i]]))
bank(BANK.FONT, [['w', '#ffffff'], ['sh', '#101018'], ['y', '#ffe08a']])
bank(BANK.FLASH, [['ol', '#5a1020'], ...Array.from({ length: 14 }, (_, i) => ['f' + i, i % 3 === 0 ? '#ffd8d8' : '#ffffff'])])
const SPARK = bank(BANK.SPARK, [['y0', '#ff8a20'], ['y1', '#ffd040'], ['y2', '#fff8c0'], ['b0', '#2a6ae0'], ['b1', '#7ac8ff'], ['b2', '#e8f8ff']])
const BIGB = bank(BANK.BIG, [['ol', '#140a10'], ['g0', '#8a4a10'], ['g1', '#d08a20'], ['g2', '#ffd050'], ['g3', '#fff4b0']])
const TITB = bank(BANK.TITLE, [['ol', '#100810'], ['d0', '#4a0e18'], ['d1', '#8a1a24'], ['d2', '#d03a30'], ['d3', '#ff8a50'], ['g2', '#ffd050'], ['g3', '#fff4c0']])
bank(BANK.SHADOW, [['s', '#0e0c14']])

// courtyard colours by name; banks are lists of these names
const C = {
  mo: '#2e2630', s0: '#5c5058', s1: '#7a6c6e', s2: '#9a8a84', s3: '#bcaa9c', hi: '#e2d4c0', dp: '#1a141e',
  w0: '#3a1e12', w1: '#5e3420', w2: '#84502e', i0: '#24242c', i1: '#4c4c58', g0: '#b07a1c', g1: '#ffd65a',
  p0: '#14401e', p1: '#22662a', p2: '#3e9438', p3: '#7cc850', t0: '#4a2e1a', t1: '#7a5230', pot0: '#7a3018', pot1: '#c0602e',
  r0: '#5a0e1a', r1: '#9a1c28', r2: '#d8383a',
  f0: '#5a4c44', f1: '#76665a', f2: '#928070', f3: '#b09c86', fg: '#2e2622', fh: '#d4c2a8', fd: '#201a1c',
}
const STONE7 = ['mo', 's0', 's1', 's2', 's3', 'hi', 'dp']
const BGBANKS = [
  [BANK.STONE, STONE7],
  [BANK.GATE, [...STONE7, 'w0', 'w1', 'w2', 'i0', 'i1', 'g0', 'g1']],
  [BANK.BANNER, [...STONE7, 'r0', 'r1', 'r2', 'g0', 'g1']],
  [BANK.PALM, [...STONE7, 'p0', 'p1', 'p2', 'p3', 't0', 't1', 'pot0', 'pot1']],
  [BANK.FLOOR, ['f0', 'f1', 'f2', 'f3', 'fg', 'fh', 'fd']],
]
for (const [n, names] of BGBANKS) bank(n, names.map(k => [k, C[k]]))

// ---------- canvases: named colour per pixel ----------
const W = 512, H = 224
class Canvas {
  constructor() { this.c = new Array(W * H).fill(null) }
  set(x, y, name) { x = ((x % W) + W) % W; if (y >= 0 && y < H) this.c[y * W + x] = name }
  get(x, y) { x = ((x % W) + W) % W; return this.c[y * W + x] }
  rect(x0, y0, x1, y1, fn) { for (let y = y0; y < y1; y++) for (let x = x0; x < x1; x++) { const v = fn(x, y); if (v) this.set(x, y, v) } }
}
const hash = (x, y, s = 0) => { let h = (x * 374761393 + y * 668265263 + s * 2147483647) | 0; h = (h ^ (h >>> 13)) * 1274126177 | 0; return ((h ^ (h >>> 16)) >>> 0) / 4294967296 }
const bg0 = new Canvas(), bg1 = new Canvas()

// ---------- BG0: clouds, far palace domes and minarets, far palms ----------
function cloud(cx, cy, rx, ry) {
  for (let y = cy - ry; y <= cy + ry; y++) for (let x = cx - rx; x <= cx + rx; x++) {
    let inside = false
    for (let k = -3; k <= 3; k++) {
      const px = cx + k * rx / 3.6, pr = ry * (1 - Math.abs(k) / 5), py = cy - pr * 0.35
      if (Math.hypot(x - px, (y - py) * 1.25) / pr < 1) inside = true
    }
    if (!inside || y > cy + ry * 0.45) continue
    const lit = 1 - (y - (cy - ry)) / (ry * 1.45) + hash(x >> 1, y, 3) * 0.12   // lit from above
    bg0.set(x, y, lit > 0.8 ? 'cl3' : lit > 0.55 ? 'cl2' : lit > 0.3 ? 'cl1' : 'cl0')
  }
}
cloud(70, 34, 50, 12); cloud(230, 22, 36, 9); cloud(350, 40, 60, 13); cloud(470, 28, 40, 10)
const BG0BASE = 112
for (let x = 0; x < W; x++) for (let y = 96; y < H; y++) bg0.set(x, y, y < BG0BASE ? null : 'pa0')
function dome(cx, top, r, body) {             // onion-ish dome on a drum
  for (let y = top; y < BG0BASE + 8; y++) for (let x = cx - r - 2; x <= cx + r + 2; x++) {
    const dy = y - (top + r)
    let inDome = false
    if (dy < 0) { const w = r * Math.sqrt(Math.max(0, 1 - (dy / r) ** 2)) * (1 - 0.35 * Math.max(0, -dy / r - 0.6)); inDome = Math.abs(x - cx) <= w }
    else if (dy < r * 0.25) inDome = Math.abs(x - cx) <= r
    const inDrum = y >= top + r * 1.25 && Math.abs(x - cx) <= body
    if (inDome) bg0.set(x, y, x < cx - r * 0.35 ? 'dm1' : 'dm0')
    else if (inDrum) bg0.set(x, y, x < cx - body + 2 ? 'pa2' : x > cx + body - 3 ? 'pa0' : 'pa1')
  }
  for (let y = top - 7; y < top; y++) bg0.set(cx, y, 'dm1')
}
function minaret(cx, top) {
  for (let y = top; y < BG0BASE + 8; y++) for (let x = cx - 3; x <= cx + 3; x++) bg0.set(x, y, x === cx - 3 ? 'pa2' : x === cx + 3 ? 'pa0' : 'pa1')
  for (let y = top - 4; y < top; y++) for (let x = cx - 5; x <= cx + 5; x++) bg0.set(x, y, 'pa1')
  for (let y = top - 12; y < top - 4; y++) { const w = Math.round((y - (top - 12)) / 2); for (let x = cx - w; x <= cx + w; x++) bg0.set(x, y, 'dm0') }
  for (let k = 0; k < 3; k++) bg0.set(cx, top + 8 + k * 14, 'lamp')
}
function block(x0, x1, top) {
  for (let y = top; y < BG0BASE + 8; y++) for (let x = x0; x < x1; x++) bg0.set(x, y, x - x0 < 2 ? 'pa2' : x1 - x <= 2 ? 'pa0' : 'pa1')
  for (let x = x0 + 4; x + 3 < x1 - 2; x += 8) for (let y = top + 6; y < top + 12; y++) bg0.set(x, y, y === top + 6 ? 'pa0' : 'lamp')
}
block(0, 120, 84); block(150, 260, 78); block(300, 420, 86); block(440, 512, 80)
dome(60, 50, 22, 18); dome(205, 38, 30, 24); dome(360, 56, 20, 16); dome(470, 46, 24, 20)
minaret(120, 40); minaret(290, 30); minaret(420, 44)
function farPalm(cx, base, h) {
  for (let y = base - h; y < base; y++) { const xx = cx + Math.round(Math.sin((base - y) / h * 1.2) * 3); bg0.set(xx, y, 'pf1'); bg0.set(xx + 1, y, 'pf0') }
  const top = [cx + Math.round(Math.sin(1.2) * 3), base - h]
  for (let a = 0; a < 7; a++) {
    const ang = -Math.PI + a * Math.PI / 6
    for (let t = 0; t < 16; t++) { const x = top[0] + Math.round(Math.cos(ang) * t), y = top[1] + Math.round(Math.sin(ang) * t * 0.6 + t * t * 0.03); bg0.set(x, y, 'pf0'); bg0.set(x, y + 1, 'pf1') }
  }
}
farPalm(20, 112, 30); farPalm(140, 112, 36); farPalm(330, 112, 28); farPalm(400, 112, 40)

// ---------- BG1: the courtyard ----------
const WALL_TOP = 96, PLINTH = 160, FLOOR = 176
function stoneWall(x0, x1, y0, y1, seed = 0) {   // ashlar blocks 16x8, staggered
  for (let y = y0; y < y1; y++) for (let x = x0; x < x1; x++) {
    const row = (y - y0) >> 3, ry = (y - y0) & 7, bx = (x + (row & 1) * 8) & 15
    const v = hash((x + (row & 1) * 8) >> 4, row, 5 + seed)
    let c = v < 0.25 ? 's0' : v < 0.7 ? 's1' : 's2'
    if (ry === 0) c = c === 's0' ? 's1' : c === 's1' ? 's2' : 's3'
    if (ry === 6) c = 's0'
    if (ry === 7 || bx === 15) c = 'mo'
    bg1.set(x, y, c)
  }
}
function merlons(x0, x1, top) {                 // crenellations: 8-wide merlons every 16
  for (let y = top; y < top + 8; y++) for (let x = x0; x < x1; x++) {
    const k = (x - x0) & 15
    if (k < 8) bg1.set(x, y, y === top ? 'hi' : k === 0 ? 's3' : k === 7 ? 's0' : 's2')
  }
  for (let x = x0; x < x1; x++) { bg1.set(x, top + 8, 'hi'); bg1.set(x, top + 9, 's3'); bg1.set(x, top + 10, 'dp') }
}
stoneWall(0, W, WALL_TOP + 8, PLINTH)
merlons(0, W, WALL_TOP)
// gatehouse (taller) with two flanking towers
const GX0 = 192, GX1 = 320, TW = 32
stoneWall(GX0, GX1, 64, PLINTH, 1)
merlons(GX0, GX1, 56)
for (let y = 66; y < PLINTH; y++) { bg1.set(GX0, y, 'hi'); bg1.set(GX0 + TW - 1, y, 'dp'); bg1.set(GX1 - TW, y, 'hi'); bg1.set(GX1 - 1, y, 'dp') }
for (const tx of [GX0 + 12, GX1 - 20]) for (let y = 80; y < 104; y++) for (let x = tx; x < tx + 8; x++) {   // arrow slits
  const inner = x > tx && x < tx + 7 && y > 80
  bg1.set(x, y, !inner ? 's3' : (x === tx + 3 || x === tx + 4) ? 'dp' : 'mo')
}
// the arch and the gate
const AX = 256, AY = 120, AR = 28
for (let y = AY - AR - 6; y < PLINTH; y++) for (let x = AX - AR - 6; x < AX + AR + 6; x++) {
  const dx = x - AX, dy = y - AY, d = y < AY ? Math.hypot(dx, dy) : Math.abs(dx)
  if (d < AR) {                                   // opening: wooden doors behind an iron portcullis
    const gx = (x - (AX - AR)) % 10, gy = (y - (AY - AR)) % 10
    let c = ((x - AX + 64) % 14 === 0) ? 'w0' : (x - AX + 64) % 14 < 3 ? 'w2' : 'w1'
    if (x === AX || x === AX - 1) c = 'w0'
    if (y > PLINTH - 24 && y < PLINTH - 20) c = 'i1'
    if (gx === 0 || gy === 0) c = gx === 0 && gy === 0 ? 'i1' : 'i0'
    bg1.set(x, y, c)
  } else if (d < AR + 6) {                        // voussoirs
    const ang = Math.atan2(dy, dx), seg = Math.floor((ang + Math.PI) / (Math.PI / 9))
    const edge = d > AR + 5 || Math.abs(((ang + Math.PI) / (Math.PI / 9)) - seg) < 0.08
    bg1.set(x, y, edge ? 'mo' : d < AR + 1.2 ? 'dp' : (seg & 1) ? 's3' : 'hi')
  }
}
// gold palm emblem over the arch
for (let y = 66; y < 86; y++) for (let x = AX - 12; x < AX + 12; x++) {
  const dx = x - AX + 0.5, dy = y - 76
  const plaque = Math.abs(dx) + Math.abs(dy) * 1.1 < 12
  if (!plaque) continue
  let c = Math.abs(dx) + Math.abs(dy) * 1.1 > 10.5 ? 'g0' : 'w0'
  if (Math.abs(dx) < 1.2 && dy > -2 && dy < 7) c = 'g1'
  for (let a = -2; a <= 2; a++) { const ex = a * 2.2, ey = -3 + Math.abs(a) * 1.2; if (Math.hypot(dx - ex, (dy - ey) * 1.6) < 1.6) c = 'g1' }
  bg1.set(x, y, c)
}
// banners hanging on the wall
function banner(x0) {
  for (let y = 112; y < 152; y++) for (let x = x0; x < x0 + 24; x++) {
    const fx = x - x0, fy = y - 112
    let c = fx < 2 ? 'r2' : fx > 20 ? 'r0' : 'r1'
    if (fy < 2) c = fy === 0 ? 'g1' : 'g0'
    if (fy >= 34) { const v = Math.abs(fx - 11.5); if (fy - 34 > 6 - v * 0.55) c = null }   // swallow-tail
    if (c && (fx === 3 || fx === 20) && fy > 2) c = 'g0'
    const ex = fx - 11.5, ey = fy - 16                                                     // emblem: a crossed palm and gate
    if (c && Math.abs(ex) < 6 && ey > -2 && ey < 8 && (Math.abs(ex) > 4 || ey < 0)) c = 'g1'
    if (c && Math.abs(ex) < 1 && ey >= -8 && ey < -2) c = 'g1'
    if (c && ey > -10 && ey < -6 && Math.abs(Math.abs(ex) - (ey + 10) * 1.2) < 1) c = 'g1'
    if (c) bg1.set(x, y, c)
  }
  for (let x = x0 - 2; x < x0 + 26; x++) bg1.set(x, 111, 'w0')
}
banner(88); banner(400)
// plinth along the wall foot
for (let y = PLINTH; y < FLOOR; y++) for (let x = 0; x < W; x++) {
  const d = y - PLINTH
  bg1.set(x, y, d === 0 ? 'hi' : d === 1 ? 's3' : d > 13 ? 'dp' : ((x & 31) === 0 ? 'mo' : d < 6 ? 's2' : 's1'))
}
// potted palms on the plinth
function palm(cx, h, lean) {
  const potTop = PLINTH - 16
  for (let y = potTop; y < PLINTH + 2; y++) for (let x = cx - 10; x <= cx + 10; x++) {
    const fy = y - potTop, w = fy < 3 ? 10 : 9 - Math.floor((fy - 3) / 5)
    if (Math.abs(x - cx + 0.5) > w) continue
    bg1.set(x, y, fy < 3 ? (fy === 0 ? 'pot1' : 'pot0') : x < cx - w + 3 ? 'pot1' : x > cx + w - 3 ? 'dp' : 'pot0')
  }
  const top = []
  for (let y = potTop; y > potTop - h; y--) {
    const t = (potTop - y) / h, xx = cx + Math.round(lean * t * t * 14)
    for (let k = -2; k <= 2; k++) bg1.set(xx + k, y, k < 0 ? 't1' : (((y >> 2) & 1) && k === 1) ? 't1' : 't0')
    top[0] = xx; top[1] = y
  }
  for (let a = 0; a < 9; a++) {
    const ang = -Math.PI * 1.05 + a * Math.PI * 1.1 / 8, len = 22 + (a % 3) * 4
    for (let t = 0; t < len; t++) {
      const sag = t * t * 0.022, x = top[0] + Math.round(Math.cos(ang) * t), y = top[1] + Math.round(Math.sin(ang) * t * 0.55 + sag)
      const w = Math.max(1, Math.round(3.2 * Math.sin(Math.PI * Math.min(1, t / len + 0.08))))
      for (let k = -w; k <= w; k++) bg1.set(x, y + k, k < -w / 2 ? 'p3' : k > w / 2 ? 'p0' : (t & 3) === 0 ? 'p1' : 'p2')
    }
  }
}
palm(40, 92, 0.6); palm(160, 80, -0.5); palm(352, 80, 0.5); palm(472, 92, -0.6)
// flagstone floor
const FROWS = [[FLOOR, 10, 0], [FLOOR + 10, 14, 11], [FLOOR + 24, 24, 5]]
for (const [y0, h, off] of FROWS) for (let y = y0; y < Math.min(H, y0 + h); y++) for (let x = 0; x < W; x++) {
  const len = 16 + (h - 10) * 2, sx = (x + off * 4 + Math.round((y - FLOOR) * 0.25)) % len, fy = y - y0
  const v = hash(Math.floor((x + off * 4) / len), y0, 9)
  let c = v < 0.3 ? 'f0' : v < 0.75 ? 'f1' : 'f2'
  if (fy === 0) c = 'fg'
  else if (fy === 1) c = 'fh'
  else if (fy === 2) c = 'f3'
  if (sx === 0) c = 'fg'
  else if (sx === 1 && fy > 1) c = 'f3'
  if (y < FLOOR + 3) c = 'fd'
  bg1.set(x, y, c)
}
for (let y = 0; y < 24; y++) for (let x = 0; x < W; x++) bg1.set(x, y, null)   // HUD rows stay clear

// ---------- tiles ----------
const tiles = new Uint8Array(2048 * 32)
let topTile = T.BG_BASE
function putTile(t, px) {
  if (px.length !== 64) throw new Error('tile needs 64 px')
  for (let i = 0; i < 64; i += 2) tiles[t * 32 + (i >> 1)] = ((px[i] & 15) << 4) | (px[i + 1] & 15)
}
function putBlock(base, img, S) {
  const n = S >> 3
  for (let ty = 0; ty < n; ty++) for (let tx = 0; tx < n; tx++) {
    const px = []; for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x++) px.push(img[(ty * 8 + y) * S + tx * 8 + x])
    putTile(base + ty * n + tx, px)
  }
}
// HUD cells (bank HUD)
const h = HUD.idx
const rowsTile = rows => { const px = []; rows.forEach(c => { for (let i = 0; i < 8; i++) px.push(Array.isArray(c) ? c[i] : c) }); return px }
const halfRow = (a, b) => [a, a, a, a, b, b, b, b]
putTile(T.HP_FULL, rowsTile([h.k, h.h2, h.h1, h.h1, h.h1, h.h0, h.h0, h.k]))
putTile(T.HP_HALF, rowsTile([h.k, halfRow(h.h2, h.e1), halfRow(h.h1, h.e1), halfRow(h.h1, h.e0), halfRow(h.h1, h.e0), halfRow(h.h0, h.e0), halfRow(h.h0, h.e0), h.k]))
putTile(T.HP_HALFR, rowsTile([h.k, halfRow(h.e1, h.h2), halfRow(h.e1, h.h1), halfRow(h.e0, h.h1), halfRow(h.e0, h.h1), halfRow(h.e0, h.h0), halfRow(h.e0, h.h0), h.k]))
putTile(T.HP_EMPTY, rowsTile([h.k, h.e1, h.e1, h.e0, h.e0, h.e0, h.e0, h.k]))
putTile(T.MT_FULL, rowsTile([h.k, h.m2, h.m1, h.m1, h.m0, h.k, 0, 0]))
putTile(T.MT_EMPTY, rowsTile([h.k, h.n1, h.n0, h.n0, h.n0, h.k, 0, 0]))
putTile(T.MT_READY, rowsTile([h.k, h.w, h.c, h.c, h.m2, h.k, 0, 0]))
const sealTile = (rim, face, crack) => {
  const px = []
  for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x++) {
    const d = Math.hypot(x - 3.5, y - 3.5)
    let c = d > 3.9 ? 0 : d > 2.9 ? rim : face
    if (crack && c && (x === y || x === y + 1)) c = h.k
    if (!crack && c === face && Math.abs(x - 3.5) < 1 && y > 1 && y < 6) c = rim
    px.push(c)
  }
  return px
}
putTile(T.SEAL_OK, sealTile(h.m0, h.m2, false))
putTile(T.SEAL_BROKE, sealTile(h.r0, h.r1, true))
putTile(T.SEAL_NONE, sealTile(h.n0, h.n1, false))
putTile(T.PIP_ON, sealTile(h.k, h.m2, false).map(v => v === h.m0 ? h.k : v))
putTile(T.PIP_OFF, sealTile(h.k, h.n0, false).map(v => v === h.n0 || v === h.m0 ? h.n0 : v))
for (let k = 1; k <= 15; k++) putTile(T.SOLID + k - 1, new Array(64).fill(k))

// fonts: 5x7 glyphs, ASCII-indexed
const PUNCT = {
  '.': ['     ', '     ', '     ', '     ', '     ', ' ##  ', ' ##  '], '!': ['  #  ', '  #  ', '  #  ', '  #  ', '  #  ', '     ', '  #  '],
  '-': ['     ', '     ', '     ', ' ### ', '     ', '     ', '     '], '?': [' ### ', '#   #', '    #', '   # ', '  #  ', '     ', '  #  '],
  ':': ['     ', ' ##  ', ' ##  ', '     ', ' ##  ', ' ##  ', '     '], "'": ['  #  ', '  #  ', ' #   ', '     ', '     ', '     ', '     '],
  '<': SB.ARROWS.l, '>': SB.ARROWS.r,
}
const glyphOf = ch => /[A-Z]/.test(ch) ? SB.GLYPHS[ch] : /[0-9]/.test(ch) ? SB.DIGITS[+ch] : PUNCT[ch]
function glyphTile(g) {                       // 8x8, bank FONT: white top, warm lower rows, dark drop shadow
  const px = new Array(64).fill(0)
  g.forEach((row, y) => [...row].forEach((v, x) => { if (v === '#') { const k = (y + 1) * 8 + x + 2; if (px[k] === 0) px[k] = 2 } }))
  g.forEach((row, y) => [...row].forEach((v, x) => { if (v === '#') px[y * 8 + x + 1] = y < 3 ? 1 : 3 }))
  return px
}
function bigGlyph(g, S, scale, ramp, ol) {     // SxS: scaled glyph, vertical ramp, 1px outline + drop shadow
  const img = new Uint8Array(S * S), on = (x, y) => { const gx = Math.floor((x - 1) / scale), gy = Math.floor((y - 1) / scale); return gx >= 0 && gy >= 0 && gy < 7 && gx < 5 && g[gy][gx] === '#' }
  for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
    if (on(x, y)) { const t = (y - 1) / (7 * scale); img[y * S + x] = ramp[Math.min(ramp.length - 1, Math.floor((1 - t) * ramp.length))] }
  }
  const res = img.slice()
  for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
    if (img[y * S + x]) continue
    let near = false
    for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1], [-1, -1], [1, 1], [0, 2], [1, 2]]) { const xx = x + dx, yy = y + dy; if (xx >= 0 && yy >= 0 && xx < S && yy < S && img[yy * S + xx]) near = true }
    if (near) res[y * S + x] = ol
  }
  return res
}
for (let a = 32; a < 96; a++) {
  const g = glyphOf(String.fromCharCode(a))
  if (!g) continue
  putTile(T.FONT + a, glyphTile(g))
  putBlock(T.BIG + (a - 32) * 4, bigGlyph(g, 16, 2, [BIGB.idx.g0, BIGB.idx.g1, BIGB.idx.g2, BIGB.idx.g3], BIGB.idx.ol), 16)
}
;[...TITLE.replace(/ /g, '')].forEach((ch, i) => putBlock(T.TITLE + i * 16, bigGlyph(glyphOf(ch), 32, 4, [TITB.idx.d0, TITB.idx.d1, TITB.idx.d2, TITB.idx.d3, TITB.idx.g2, TITB.idx.g3], TITB.idx.ol), 32))
// sparks (16x16, 2 frames) and the shadow
function spark(f, cols) {
  const img = new Uint8Array(256)
  for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {
    const dx = x - 7.5, dy = y - 7.5, r = Math.hypot(dx, dy), a = Math.atan2(dy, dx)
    const spike = Math.abs(Math.cos(a * (f ? 3 : 4))) ** 6 * (f ? 7.5 : 6) + (f ? 1.5 : 3)
    if (r < spike) img[y * 16 + x] = r < spike * 0.4 ? cols[2] : r < spike * 0.75 ? cols[1] : cols[0]
  }
  return img
}
for (let f = 0; f < 2; f++) putBlock(T.SPARK + f * 4, spark(f, [SPARK.idx.y0, SPARK.idx.y1, SPARK.idx.y2]), 16)
for (let f = 0; f < 2; f++) putBlock(T.BSPARK + f * 4, spark(f, [SPARK.idx.b0, SPARK.idx.b1, SPARK.idx.b2]), 16)
const shadow = new Uint8Array(32 * 32)
for (let y = 0; y < 32; y++) for (let x = 0; x < 32; x++) if (Math.hypot((x + 0.5 - 16) / 15, (y + 0.5 - 28) / 3.4) < 1) shadow[y * 32 + x] = 1
putBlock(T.SHADOW, shadow, 32)

// background layers -> deduped tiles (with flips) + map entries, bank picked per tile
const tileKey = new Map([['0'.repeat(64), { t: 0 }]])
function addBgTile(px) {
  for (const [hf, vf] of [[false, false], [true, false], [false, true], [true, true]]) {
    const f = []; for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x++) f.push(px[(vf ? 7 - y : y) * 8 + (hf ? 7 - x : x)])
    const hit = tileKey.get(f.join(','))
    if (hit) return { t: hit.t, h: hf, v: vf }
  }
  const t = topTile++
  if (t >= 2048) throw new Error('VRAM tile budget exceeded')
  putTile(t, px); tileKey.set(px.join(','), { t })
  return { t, h: false, v: false }
}
function packLayer(cv, banks) {
  const map = new Uint32Array(64 * 28)
  for (let ty = 0; ty < 28; ty++) for (let tx = 0; tx < 64; tx++) {
    const names = new Set()
    for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x++) { const n = cv.c[(ty * 8 + y) * W + tx * 8 + x]; if (n) names.add(n) }
    const B = names.size ? banks.find(b => [...names].every(n => b.idx[n])) : banks[0]
    if (!B) throw new Error(`tile (${tx},${ty}) has colours ${[...names]} that no one bank holds`)
    const px = []
    for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x++) { const n = cv.c[(ty * 8 + y) * W + tx * 8 + x]; px.push(n ? B.idx[n] : 0) }
    const r = addBgTile(px)
    map[ty * 64 + tx] = ((r.t & 0x7ff) | (B.bank << 11) | (r.h ? 1 << 15 : 0) | (r.v ? 1 << 16 : 0)) >>> 0
  }
  return map
}
const map0 = packLayer(bg0, [SKY])
const map1 = packLayer(bg1, BGBANKS.map(([n]) => BANKS[n]))

// ---------- fighter bodies: every body in every pose ----------
const charColours = { ...Object.fromEntries(Object.entries(SB.CHOICES).map(([k, c]) => [k, c.hexes[0]])), outline: SB.CHAR_OUTLINE, accent: SB.CHAR_TRIM }
const bodyBlobs = BODIES.map(b => {
  const blk = new Uint8Array(POSES.length * POSE_BYTES)
  POSES.forEach(([pose, phase], f) => {
    const { img } = Rig.draw({ ...b, pose, phase, colours: charColours })
    for (let ty = 0; ty < 8; ty++) for (let tx = 0; tx < 8; tx++) for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x += 2) {
      const k = (ty * 8 + y) * 64 + tx * 8 + x
      blk[(f * 64 + ty * 8 + tx) * 32 + y * 4 + (x >> 1)] = (img[k] << 4) | img[k + 1]
    }
  })
  return blk
})
// the default creator colours also fill banks 8 and 9 so the title shows something sane
Rig.makeBank(charColours).colours.forEach((c, i) => { palette[BANK.P1 * 16 + i + 1] = to555(c); palette[BANK.P2 * 16 + i + 1] = to555(c) })

// ---------- write ----------
const le16 = arr => { const b = Buffer.alloc(arr.length * 2); arr.forEach((v, i) => b.writeUInt16LE(v, i * 2)); return b }
const tileBytes = topTile * 32
if (tileBytes > 0xffff) throw new Error('tile region too large for one DMA')
const files = {
  'tiles.bin': Buffer.from(tiles.subarray(0, tileBytes)),
  'maps.bin': Buffer.concat([Buffer.from(map0.buffer), Buffer.from(map1.buffer)]),
  'pal.bin': le16([...palette]),
  'stages.bin': Buffer.concat(STAGES.map(st => le16([...skyLines(st.sky), ...st.bank.map(c => to555(hex(c)))]))),
  'bodies.bin': Buffer.concat(bodyBlobs.map(b => Buffer.from(b))),
}
const stageRecordBytes = files['stages.bin'].length / STAGES.length
if (require.main === module) {
  for (const [name, buf] of Object.entries(files)) fs.writeFileSync(path.join(__dirname, name), buf)
  console.log(`swornrivals art: ${topTile} tiles (${topTile - T.BG_BASE} background), ${POSES.length} poses x ${BODIES.length} bodies, stage record ${stageRecordBytes} bytes`)
}
module.exports = { T, BANK, POSE, POSES, BODIES, RIVALS, TITLE, files, tileCount: topTile, stageRecordBytes, bodyBytes: POSES.length * POSE_BYTES, nStages: STAGES.length }
