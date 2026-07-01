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
  WPN_ICON: 8, BHP_FULL: 9,                   // 8x8 HUD: armed icon, boss-bar cell
  PL_WALKA: 16, PL_WALKB: 20, PL_PUNCH: 24,   // player 16x16 frames (4 tiles each)
  EN_WALKA: 32, EN_WALKB: 36,                 // grunt 16x16 frames
  WEAPON: 40, FOOD: 44, BOSS: 48,             // pickups + boss (16x16 each)
  WEAPON_UP: 52,                              // pipe mid-swing (raised diagonal)
  FONT: 64,                                   // FONT + (letter 0..25)
  DIGIT: 96,                                  // DIGIT + (0..9)
  EN2_WALKA: 112, EN2_WALKB: 116,             // runner 16x16 frames (lean silhouette)
  EN3_WALKA: 120, EN3_WALKB: 124,             // bruiser 16x16 frames (bulky silhouette)
}
const SHEET_TILES = 128           // tiles 0..127 -> 128*32 = 4096 bytes
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
put(T.WPN_ICON, tile8([    // little grey pipe, drawn in BG colour 8 (mortar grey)
  '        ',
  '        ',
  ' mmmmmm ',
  ' m    m ',
  ' mmmmmm ',
  '        ',
  '        ',
  '        ',
], BG))
put(T.BHP_FULL, tile8(['%%%%%%%%','%%%%%%%%','%%%%%%%%','%%%%%%%%','%%%%%%%%','%%%%%%%%','%%%%%%%%','%%%%%%%%'], BG))  // boss-bar cell (BG colour 2)

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

// ---- runner 16x16: lean, forward-leaning sprinter with a headband. Same EMAP so
//      the type palettes (bank 7) recolour it. Distinctly slimmer than the grunt. ----
put16(T.EN2_WALKA, tile16([
  '................',
  '....dddd........',
  '...dkkkkd.......',
  '...dddddd.......',   // headband
  '...dwkkkd.......',
  '....dkkd........',
  '....drrd........',
  '...drrrrd.......',
  '..drrrrd........',   // torso leaning left, trailing arm back
  '.drrrd..........',
  '..drrd..........',
  '...drd..........',
  '..dr.rd.........',   // legs split mid-stride
  '.dr...rd........',
  '.d.....d........',
  '................',
], EMAP))
put16(T.EN2_WALKB, tile16([
  '................',
  '....dddd........',
  '...dkkkkd.......',
  '...dddddd.......',
  '...dwkkkd.......',
  '....dkkd........',
  '....drrd........',
  '...drrrrd.......',
  '...drrrrd.......',   // more upright, opposite stride
  '..drrrrd........',
  '...drrd.........',
  '...drd..........',
  '...drrd.........',
  '..dr..d.........',
  '..d...dd........',
  '................',
], EMAP))

// ---- bruiser 16x16: hulking, wide-shouldered brute (palette bank 8). Fills the
//      whole tile so it reads as much bigger than the grunt/runner. ----
put16(T.EN3_WALKA, tile16([
  '......dddd......',
  '.....dkkkkd.....',
  '.....dwkkkd.....',
  '.....dkkkkd.....',
  '....dddddddd....',   // thick neck / traps
  '..dddddddddddd..',   // huge shoulders
  '..drrrrrrrrrrd..',
  '..drrrrrrrrrrd..',
  '..drrrrrrrrrrd..',
  '..drrrrrrrrrrd..',
  '..drrrrrrrrrrd..',
  '..ddrrrrrrrrdd..',
  '...drrrrrrrrd...',
  '...dd.rrrr.dd...',   // thick legs planted wide
  '..drr......rrd..',
  '..dd........dd..',
], EMAP))
put16(T.EN3_WALKB, tile16([
  '......dddd......',
  '.....dkkkkd.....',
  '.....dwkkkd.....',
  '.....dkkkkd.....',
  '....dddddddd....',
  '..dddddddddddd..',
  '..drrrrrrrrrrd..',
  '..drrrrrrrrrrd..',
  '..drrrrrrrrrrd..',
  '..drrrrrrrrrrd..',
  '..drrrrrrrrrrd..',
  '..ddrrrrrrrrdd..',
  '...drrrrrrrrd...',
  '....drrrrrrd....',   // weight shifts, feet closer
  '...drr....rrd...',
  '...dd......dd...',
], EMAP))

// ---- pickups 16x16 (palette bank 5: 1 pipe-light, 2 pipe-dark, 3 meat, 4 bone) ----
const WMAP = { '.': 0, 'L': 1, 'D': 2 }
put16(T.WEAPON, tile16([           // a chrome lead pipe with a dark centre line
  '................',
  '................',
  '................',
  '.....LLLLLLLLL..',
  '....LLLLLLLLLLL.',
  '....LDDDDDDDDDL.',
  '....LLLLLLLLLLL.',
  '.....LLLLLLLLL..',
  '................',
  '................',
  '................',
  '................',
  '................',
  '................',
  '................',
  '................',
], WMAP))
put16(T.WEAPON_UP, tile16([        // pipe raised on the diagonal: the swing wind-up
  '............LL..',
  '...........LLL..',
  '..........LLDL..',
  '.........LLDL...',
  '........LLDL....',
  '.......LLDL.....',
  '......LLDL......',
  '.....LLDL.......',
  '....LLDL........',
  '...LLDL.........',
  '..LLDL..........',
  '..LLL...........',
  '..LL............',
  '................',
  '................',
  '................',
], WMAP))
const FDMAP = { '.': 0, 'M': 3, 'B': 4 }
put16(T.FOOD, tile16([             // a chicken drumstick: round meat over a bone
  '................',
  '.......MMMM.....',
  '......MMMMMM....',
  '.....MMMMMMMM...',
  '.....MMMMMMMM...',
  '.....MMMMMMMM...',
  '......MMMMMM....',
  '.......MMMM.....',
  '........MM......',
  '........BB......',
  '........BB......',
  '.......BBBB.....',
  '.......BBBB.....',
  '................',
  '................',
  '................',
], FDMAP))

// ---- boss 16x16 (palette bank 6: 1 body, 2 dark, 3 skin, 4 white). Horned brute. ----
const BSMAP = { '.': 0, 'R': 1, 'D': 2, 'K': 3, 'W': 4 }
put16(T.BOSS, tile16([
  '..D........D....',
  '..DD......DD....',
  '...DDDDDDDD.....',
  '..DKKKKKKKKD....',
  '..DKWKKKKWKD....',
  '..DKKKKKKKKD....',
  '..DDKKKKKKDD....',
  '...DDDDDDDD.....',
  '..DRRRRRRRRD....',
  '.DRRRRRRRRRRD...',
  '.DRRRRRRRRRRD...',
  '.DRRRRRRRRRRD...',
  '.DDRRRRRRRRDD...',
  '..DRR....RRD....',
  '..DD......DD....',
  '.DD........DD...',
], BSMAP))

// ---- 8x8 font: '#'=colour 1. Authored 5x7, placed at cols 1..5 / rows 0..6. ----
const GLYPHS = {
  A: [' ### ', '#   #', '#   #', '#####', '#   #', '#   #', '#   #'],
  B: ['#### ', '#   #', '#   #', '#### ', '#   #', '#   #', '#### '],
  C: [' ####', '#    ', '#    ', '#    ', '#    ', '#    ', ' ####'],
  D: ['#### ', '#   #', '#   #', '#   #', '#   #', '#   #', '#### '],
  E: ['#####', '#    ', '#    ', '#### ', '#    ', '#    ', '#####'],
  F: ['#####', '#    ', '#    ', '#### ', '#    ', '#    ', '#    '],
  G: [' ####', '#    ', '#    ', '#  ##', '#   #', '#   #', ' ### '],
  H: ['#   #', '#   #', '#   #', '#####', '#   #', '#   #', '#   #'],
  I: ['#####', '  #  ', '  #  ', '  #  ', '  #  ', '  #  ', '#####'],
  J: ['  ###', '   # ', '   # ', '   # ', '#  # ', '#  # ', ' ##  '],
  K: ['#   #', '#  # ', '# #  ', '##   ', '# #  ', '#  # ', '#   #'],
  L: ['#    ', '#    ', '#    ', '#    ', '#    ', '#    ', '#####'],
  M: ['#   #', '## ##', '# # #', '#   #', '#   #', '#   #', '#   #'],
  N: ['#   #', '##  #', '# # #', '#  ##', '#   #', '#   #', '#   #'],
  O: [' ### ', '#   #', '#   #', '#   #', '#   #', '#   #', ' ### '],
  P: ['#### ', '#   #', '#   #', '#### ', '#    ', '#    ', '#    '],
  Q: [' ### ', '#   #', '#   #', '#   #', '# # #', '#  # ', ' ## #'],
  R: ['#### ', '#   #', '#   #', '#### ', '# #  ', '#  # ', '#   #'],
  S: [' ####', '#    ', '#    ', ' ### ', '    #', '    #', '#### '],
  T: ['#####', '  #  ', '  #  ', '  #  ', '  #  ', '  #  ', '  #  '],
  U: ['#   #', '#   #', '#   #', '#   #', '#   #', '#   #', ' ### '],
  V: ['#   #', '#   #', '#   #', '#   #', '#   #', ' # # ', '  #  '],
  W: ['#   #', '#   #', '#   #', '# # #', '# # #', '## ##', '#   #'],
  X: ['#   #', '#   #', ' # # ', '  #  ', ' # # ', '#   #', '#   #'],
  Y: ['#   #', '#   #', ' # # ', '  #  ', '  #  ', '  #  ', '  #  '],
  Z: ['#####', '    #', '   # ', '  #  ', ' #   ', '#    ', '#####'],
}
const DIGITS = [
  [' ### ', '#   #', '#  ##', '# # #', '##  #', '#   #', ' ### '],  // 0
  ['  #  ', ' ##  ', '  #  ', '  #  ', '  #  ', '  #  ', ' ### '],  // 1
  [' ### ', '#   #', '    #', '   # ', '  #  ', ' #   ', '#####'],  // 2
  ['#####', '   # ', '  #  ', '   # ', '    #', '#   #', ' ### '],  // 3
  ['   # ', '  ## ', ' # # ', '#  # ', '#####', '   # ', '   # '],  // 4
  ['#####', '#    ', '#### ', '    #', '    #', '#   #', ' ### '],  // 5
  ['  ## ', ' #   ', '#    ', '#### ', '#   #', '#   #', ' ### '],  // 6
  ['#####', '    #', '   # ', '  #  ', ' #   ', ' #   ', ' #   '],  // 7
  [' ### ', '#   #', '#   #', ' ### ', '#   #', '#   #', ' ### '],  // 8
  [' ### ', '#   #', '#   #', ' ####', '    #', '   # ', ' ##  '],  // 9
]
const FMAP = { ' ': 0, '#': 1 }
for (let i = 0; i < 26; i++) {
  const ch = String.fromCharCode(65 + i)
  const g = GLYPHS[ch]
  if (!g) continue
  const rows = g.map(r => ' ' + r.padEnd(5, ' ') + '  ')   // pad 5x7 -> 8x8 (left-margin 1)
  while (rows.length < 8) rows.push('')
  put(T.FONT + i, tile8(rows, FMAP))
}
DIGITS.forEach((g, d) => {
  const rows = g.map(r => ' ' + r.padEnd(5, ' ') + '  ')
  while (rows.length < 8) rows.push('')
  put(T.DIGIT + d, tile8(rows, FMAP))
})

const outFile = path.join(__dirname, 'assets.bin')
fs.writeFileSync(outFile, Buffer.from(sheet))
console.log(`wrote ${outFile} (${sheet.length} bytes, ${SHEET_TILES} tiles)`)
