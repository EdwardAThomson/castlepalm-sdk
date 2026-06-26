#!/usr/bin/env node
'use strict'
// STREET BRAWL — tile-sheet generator.
//
// Hand-packing 4bpp nibbles is miserable, so we draw everything here as ASCII art
// and emit a single `assets.bin` the cart INCBINs and copies to VRAM at boot.
// Tiles land at index N -> VRAM byte N*32, so the .bin IS the VRAM tile region.
//
// 8x8 tile = 32 bytes (each byte two pixels, the LEFT/even pixel in the high nibble —
// matches ppu.js setTile). 16x16 sprite = 4 tiles in TL,TR,BL,BR order (the order
// ppu.js spritePixel walks: base + (ly>>3)*2 + (lx>>3)).
//
//   node gen_assets.js        # writes assets.bin next to this file

const fs = require('fs')
const path = require('path')

// ---- tile sheet layout (tile index -> what lives there). Keep in sync with the .asm. ----
const T = {
  BLANK: 0,
  BRICK: 1, SIDEWALK: 2, ROAD: 3, CURB: 4, HP_FULL: 5, HP_EMPTY: 6, WIN_TILE: 7,
  PL_WALKA: 16, PL_WALKB: 20, PL_PUNCH: 24,   // player 16x16 frames (4 tiles each)
  EN_WALKA: 32, EN_WALKB: 36,                 // enemy 16x16 frames
  FONT: 64,                                   // FONT + (letter 0..25)
}
const SHEET_TILES = 96            // tiles 0..95 -> 96*32 = 3072 bytes
const sheet = new Uint8Array(SHEET_TILES * 32)

const put = (idx, bytes) => sheet.set(bytes, idx * 32)
const put16 = (base, quads) => quads.forEach((q, i) => put(base + i, q))

// rows: 8 strings of width 8; map: char -> palette index (0..15). default 0.
function tile8(rows, map) {
  const px = []
  for (let y = 0; y < 8; y++) {
    const row = (rows[y] || '').padEnd(8, ' ')
    for (let x = 0; x < 8; x++) px.push(map[row[x]] || 0)
  }
  const b = []
  for (let i = 0; i < 64; i += 2) b.push(((px[i] & 15) << 4) | (px[i + 1] & 15))
  return b
}

// rows: 16 strings of width 16 -> [TL,TR,BL,BR]
function tile16(rows, map) {
  const quad = (ox, oy) => {
    const r8 = []
    for (let y = 0; y < 8; y++) r8.push((rows[oy + y] || '').slice(ox, ox + 8))
    return tile8(r8, map)
  }
  return [quad(0, 0), quad(8, 0), quad(0, 8), quad(8, 8)]
}

// solid/patterned 8x8 background tiles
const BG = { ' ': 0, '#': 1, '%': 2, 'm': 8, 's': 3, 'r': 4, 'c': 5, 'g': 6, 'e': 7 }
put(T.BRICK, tile8([
  '##%###%#',
  '##%###%#',
  'mmmmmmmm',
  '###%###%',
  '###%###%',
  'mmmmmmmm',
  '%###%###',
  '%###%###',
], BG))
put(T.SIDEWALK, tile8([
  'ssssssss',
  'ssssssss',
  'sssmssss',
  'ssssssss',
  'ssssssss',
  'ssssmsss',
  'ssssssss',
  'mmmmmmmm',
], BG))
put(T.ROAD, tile8([
  'rrrrrrrr', 'rrrrrrrr', 'rrrrrrrr', 'rrrrrrrr',
  'rrrrrrrr', 'rrrrrrrr', 'rrrrrrrr', 'rrrrrrrr',
], BG))
put(T.CURB, tile8([
  'cccccccc', 'cccccccc', 'mmmmmmmm', 'rrrrrrrr',
  'rrrrrrrr', 'rrrrrrrr', 'rrrrrrrr', 'rrrrrrrr',
], BG))
put(T.HP_FULL, tile8(['gggggggg','gggggggg','gggggggg','gggggggg','gggggggg','gggggggg','gggggggg','gggggggg'], BG))
put(T.HP_EMPTY, tile8(['eeeeeeee','eeeeeeee','eeeeeeee','eeeeeeee','eeeeeeee','eeeeeeee','eeeeeeee','eeeeeeee'], BG))

// ---- player 16x16 (faces RIGHT; the cart hflips for left) ----
// . transparent  o outline  s skin  b shirt  p pants  w white
const PMAP = { '.': 0, 'o': 4, 's': 1, 'b': 2, 'p': 3, 'w': 5 }
put16(T.PL_WALKA, tile16([
  '................',
  '.....oooo.......',
  '....osssso......',
  '....oswssw.o....',
  '....osssso......',
  '.....oooo.......',
  '....obbbbo......',
  '...obbbbbbo.....',
  '...obbbbbbo.....',
  '...obbbbbbo.....',
  '...oobbbboo.....',
  '....op..po......',
  '....op..po......',
  '....pp..pp......',
  '...ww....ww.....',
  '................',
], PMAP))
put16(T.PL_WALKB, tile16([                 // walk frame B: legs swapped (stride)
  '................',
  '.....oooo.......',
  '....osssso......',
  '....oswssw.o....',
  '....osssso......',
  '.....oooo.......',
  '....obbbbo......',
  '...obbbbbbo.....',
  '...obbbbbbo.....',
  '...obbbbbbo.....',
  '...oobbbboo.....',
  '...op..po.......',
  '..op...po.......',
  '..pp....pp......',
  '.ww......ww.....',
  '................',
], PMAP))
put16(T.PL_PUNCH, tile16([                 // punch: arm + fist thrust to the right
  '................',
  '.....oooo.......',
  '....osssso......',
  '....oswssw.o....',
  '....osssso......',
  '.....oooo.......',
  '....obbbbo......',
  '...obbbbbbosssso',
  '...obbbbbboooooo',
  '...obbbbbbo.....',
  '...oobbbboo.....',
  '....op..po......',
  '....op..po......',
  '....pp..pp......',
  '...ww....ww.....',
  '................',
], PMAP))

// ---- enemy 16x16 (faces LEFT toward player spawn by default; cart hflips as needed) ----
// r body  d dark  k skin  w white
const EMAP = { '.': 0, 'r': 1, 'd': 2, 'k': 3, 'w': 4 }
put16(T.EN_WALKA, tile16([
  '................',
  '...dddddd.......',
  '..dkkkkkkd......',
  '..dwkkkwkd......',
  '..dkkkkkkd......',
  '...dddddd.......',
  '..drrrrrrd......',
  '.drrrrrrrrd.....',
  '.drrrrrrrrd.....',
  '.ddrrrrrrdd.....',
  '..dr....rd......',
  '..dr....rd......',
  '..dd....dd......',
  '..rr....rr......',
  '.dd......dd.....',
  '................',
], EMAP))
put16(T.EN_WALKB, tile16([
  '................',
  '...dddddd.......',
  '..dkkkkkkd......',
  '..dwkkkwkd......',
  '..dkkkkkkd......',
  '...dddddd.......',
  '..drrrrrrd......',
  '.drrrrrrrrd.....',
  '.drrrrrrrrd.....',
  '.ddrrrrrrdd.....',
  '..dr....rd......',
  '...dr..rd.......',
  '...dd..dd.......',
  '..rr....rr......',
  '..dd....dd.....',
  '................',
], EMAP))

// ---- 8x8 font: '#'=colour 1. Authored 5x7, placed at cols 1..5 / rows 0..6. ----
const GLYPHS = {
  A: [' ### ', '#   #', '#   #', '#####', '#   #', '#   #', '#   #'],
  B: ['#### ', '#   #', '#   #', '#### ', '#   #', '#   #', '#### '],
  E: ['#####', '#    ', '#    ', '#### ', '#    ', '#    ', '#####'],
  G: [' ####', '#    ', '#    ', '#  ##', '#   #', '#   #', ' ### '],
  H: ['#   #', '#   #', '#   #', '#####', '#   #', '#   #', '#   #'],
  I: ['#####', '  #  ', '  #  ', '  #  ', '  #  ', '  #  ', '#####'],
  K: ['#   #', '#  # ', '# #  ', '##   ', '# #  ', '#  # ', '#   #'],
  L: ['#    ', '#    ', '#    ', '#    ', '#    ', '#    ', '#####'],
  M: ['#   #', '## ##', '# # #', '#   #', '#   #', '#   #', '#   #'],
  N: ['#   #', '##  #', '# # #', '#  ##', '#   #', '#   #', '#   #'],
  O: [' ### ', '#   #', '#   #', '#   #', '#   #', '#   #', ' ### '],
  P: ['#### ', '#   #', '#   #', '#### ', '#    ', '#    ', '#    '],
  R: ['#### ', '#   #', '#   #', '#### ', '# #  ', '#  # ', '#   #'],
  S: [' ####', '#    ', '#    ', ' ### ', '    #', '    #', '#### '],
  T: ['#####', '  #  ', '  #  ', '  #  ', '  #  ', '  #  ', '  #  '],
  U: ['#   #', '#   #', '#   #', '#   #', '#   #', '#   #', ' ### '],
  V: ['#   #', '#   #', '#   #', '#   #', '#   #', ' # # ', '  #  '],
  W: ['#   #', '#   #', '#   #', '# # #', '# # #', '## ##', '#   #'],
  Y: ['#   #', '#   #', ' # # ', '  #  ', '  #  ', '  #  ', '  #  '],
}
const FMAP = { ' ': 0, '#': 1 }
for (let i = 0; i < 26; i++) {
  const ch = String.fromCharCode(65 + i)
  const g = GLYPHS[ch]
  if (!g) continue
  const rows = g.map(r => ' ' + r.padEnd(5, ' ') + '  ')   // pad 5x7 -> 8x8 (left-margin 1)
  while (rows.length < 8) rows.push('')
  put(T.FONT + i, tile8(rows, FMAP))
}

const outFile = path.join(__dirname, 'assets.bin')
fs.writeFileSync(outFile, Buffer.from(sheet))
console.log(`wrote ${outFile} (${sheet.length} bytes, ${SHEET_TILES} tiles)`)
