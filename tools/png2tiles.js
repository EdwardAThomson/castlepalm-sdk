#!/usr/bin/env node
'use strict'
// png2tiles — asset-pipeline step A2 (docs/ASSET_PIPELINE_PLAN.md).
//
// Converts a PNG into cart-ready 4bpp tiles + an RGB555 palette so artists draw
// in an image editor instead of hand-packing nibbles. Zero dependencies: Node
// built-ins only (zlib for the PNG IDAT, fs/path for I/O). Deterministic output.
//
// Console contract (the conversion target):
//   Tile  = 8x8, 4bpp packed, 32 bytes, byte = (leftPixel<<4)|rightPixel, colour 0 = transparent.
//   Sprite tile order = plain row-major within a block: 16x16 -> TL,TR,BL,BR; a
//     larger image at a given --size is a row-major sheet of those blocks.
//   Palette = RGB555, value = (b5<<10)|(g5<<5)|r5 (r5 = r8>>3); index 0 = transparent.
//     NB: the live hardware (system.js) and the shipped carts put RED in the low 5
//     bits (snake.asm: $001F = red, $03E0 = green), so we pack that way to round-trip.
//
// Outputs (to --out, default next to the input):
//   NAME.bin      raw tile bytes (for INCBIN)
//   NAME.pal.asm  a CALLable routine seeding the chosen bank via PAL_INDEX/PAL_DATA
//   NAME.json     metadata (width,height,size,tileCount,palette,bank)

const fs = require('fs')
const path = require('path')
const zlib = require('zlib')

const MAX_VISIBLE = 15            // index 0 is the hard-transparent slot, leaving 15

// ---- colour helpers ----
const c5to8 = c => (((c & 31) << 3) | ((c & 31) >> 2)) & 255          // 5-bit -> 8-bit (matches system.js)
const rgb555 = (r, g, b) => ((((b >> 3) & 31) << 10) | (((g >> 3) & 31) << 5) | ((r >> 3) & 31)) >>> 0
const hex4 = v => (v & 0xffff).toString(16).toUpperCase().padStart(4, '0')

// ---- PNG decode ----
function paeth(a, b, c) {
  const p = a + b - c, pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c)
  if (pa <= pb && pa <= pc) return a
  if (pb <= pc) return b
  return c
}

// Undo the 5 PNG row filters in place, returning the raw (unfiltered) scanlines.
function unfilter(raw, width, height, bpp) {
  const stride = width * bpp
  const out = new Uint8Array(height * stride)
  let pos = 0
  for (let y = 0; y < height; y++) {
    const ft = raw[pos++]
    const row = y * stride, prev = (y - 1) * stride
    for (let i = 0; i < stride; i++) {
      const x = raw[pos++]
      const a = i >= bpp ? out[row + i - bpp] : 0
      const up = y > 0 ? out[prev + i] : 0
      const c = (i >= bpp && y > 0) ? out[prev + i - bpp] : 0
      let v
      switch (ft) {
        case 0: v = x; break
        case 1: v = x + a; break
        case 2: v = x + up; break
        case 3: v = x + ((a + up) >> 1); break
        case 4: v = x + paeth(a, up, c); break
        default: throw new Error('unknown PNG row filter ' + ft)
      }
      out[row + i] = v & 255
    }
  }
  return out
}

// decodePng(buffer) -> { width, height, colorType, pixels (RGBA, width*height*4) }
function decodePng(buffer) {
  const b = buffer instanceof Uint8Array ? buffer : Uint8Array.from(buffer)
  const sig = [137, 80, 78, 71, 13, 10, 26, 10]
  for (let i = 0; i < 8; i++) if (b[i] !== sig[i]) throw new Error('not a PNG (bad signature)')
  const u32 = o => ((b[o] * 0x1000000) + (b[o + 1] * 0x10000) + (b[o + 2] * 0x100) + b[o + 3]) >>> 0
  let width = 0, height = 0, bitDepth = 0, colorType = 0, interlace = 0
  let plte = null, trns = null
  const idat = []
  let pos = 8
  while (pos + 8 <= b.length) {
    const len = u32(pos)
    const type = String.fromCharCode(b[pos + 4], b[pos + 5], b[pos + 6], b[pos + 7])
    const d = pos + 8
    if (type === 'IHDR') {
      width = u32(d); height = u32(d + 4); bitDepth = b[d + 8]; colorType = b[d + 9]; interlace = b[d + 12]
    } else if (type === 'PLTE') plte = b.slice(d, d + len)
    else if (type === 'tRNS') trns = b.slice(d, d + len)
    else if (type === 'IDAT') idat.push(Buffer.from(b.slice(d, d + len)))
    else if (type === 'IEND') break
    pos = d + len + 4                      // skip chunk data + CRC
  }
  if (!width || !height) throw new Error('PNG has no IHDR')
  if (interlace !== 0) throw new Error('interlaced PNGs are not supported (re-export non-interlaced)')
  if (bitDepth !== 8) throw new Error(`only 8-bit-depth PNGs are supported (got bit depth ${bitDepth})`)
  if (![2, 3, 6].includes(colorType)) throw new Error(`unsupported PNG colour type ${colorType} (need 2 RGB, 3 indexed, or 6 RGBA)`)
  if (colorType === 3 && !plte) throw new Error('indexed PNG is missing its PLTE chunk')
  if (!idat.length) throw new Error('PNG has no IDAT image data')

  const channels = colorType === 2 ? 3 : colorType === 6 ? 4 : 1
  const raw = zlib.inflateSync(Buffer.concat(idat))
  const unf = unfilter(raw, width, height, channels)
  const pixels = new Uint8Array(width * height * 4)
  for (let i = 0; i < width * height; i++) {
    let r, g, bl, a
    if (colorType === 2) { r = unf[i * 3]; g = unf[i * 3 + 1]; bl = unf[i * 3 + 2]; a = 255 }
    else if (colorType === 6) { r = unf[i * 4]; g = unf[i * 4 + 1]; bl = unf[i * 4 + 2]; a = unf[i * 4 + 3] }
    else { const idx = unf[i]; r = plte[idx * 3]; g = plte[idx * 3 + 1]; bl = plte[idx * 3 + 2]; a = (trns && idx < trns.length) ? trns[idx] : 255 }
    pixels[i * 4] = r; pixels[i * 4 + 1] = g; pixels[i * 4 + 2] = bl; pixels[i * 4 + 3] = a
  }
  return { width, height, colorType, pixels }
}

// ---- palette ----
// Greedy deterministic merge: repeatedly fold the least-used colour into its
// nearest remaining colour until <= maxColors representatives remain.
function quantizeMerge(order, maxColors) {
  const dist = (a, b) => { const dr = a.r - b.r, dg = a.g - b.g, db = a.b - b.b; return dr * dr + dg * dg + db * db }
  const reps = order.map(c => ({ v555: c.v555, r: c.r, g: c.g, b: c.b, count: c.count, members: [c.v555] }))
  while (reps.length > maxColors) {
    let mi = 0
    for (let i = 1; i < reps.length; i++) if (reps[i].count < reps[mi].count) mi = i   // fewest pixels (tie: lowest index)
    const m = reps[mi]
    let bj = -1, bd = Infinity
    for (let j = 0; j < reps.length; j++) { if (j === mi) continue; const dd = dist(m, reps[j]); if (dd < bd) { bd = dd; bj = j } }
    reps[bj].members.push(...m.members)
    reps[bj].count += m.count
    reps.splice(mi, 1)
  }
  const mapV = new Map()
  reps.forEach((rep, idx) => { for (const v of rep.members) mapV.set(v, idx) })
  return { reps, mapV }
}

// buildPalette -> { entries: [{v555,r,g,b,transparent?}], indices: Uint8Array }
// entries[0] is always the transparent slot; visible colours follow in a stable
// deterministic order (first appearance in raster scan).
function buildPalette(pixels, width, height, { transparent = null, quantize = false } = {}) {
  const n = width * height
  const isTransparent = (r, g, b, a) => a === 0 || (transparent && r === transparent.r && g === transparent.g && b === transparent.b)
  const px = new Int32Array(n)                  // per-pixel RGB555, or -1 for transparent
  const seen = new Map()                        // v555 -> colour record
  const order = []
  for (let i = 0; i < n; i++) {
    const r = pixels[i * 4], g = pixels[i * 4 + 1], b = pixels[i * 4 + 2], a = pixels[i * 4 + 3]
    if (isTransparent(r, g, b, a)) { px[i] = -1; continue }
    const v = rgb555(r, g, b)
    px[i] = v
    let c = seen.get(v)
    if (!c) { c = { v555: v, r: c5to8(r >> 3), g: c5to8(g >> 3), b: c5to8(b >> 3), count: 0 }; seen.set(v, c); order.push(c) }
    c.count++
  }

  let entries, mapToIndex
  if (order.length > MAX_VISIBLE) {
    if (!quantize) throw new Error(`${order.length} distinct visible colours exceeds the ${MAX_VISIBLE}-colour limit (index 0 is transparent); pass --quantize to merge`)
    const { reps, mapV } = quantizeMerge(order, MAX_VISIBLE)
    entries = [{ v555: 0, r: 0, g: 0, b: 0, transparent: true }, ...reps.map(rp => ({ v555: rp.v555, r: rp.r, g: rp.g, b: rp.b }))]
    mapToIndex = v => mapV.get(v) + 1
  } else {
    const idxOf = new Map(); order.forEach((c, i) => idxOf.set(c.v555, i + 1))
    entries = [{ v555: 0, r: 0, g: 0, b: 0, transparent: true }, ...order.map(c => ({ v555: c.v555, r: c.r, g: c.g, b: c.b }))]
    mapToIndex = v => idxOf.get(v)
  }

  const indices = new Uint8Array(n)
  for (let i = 0; i < n; i++) indices[i] = px[i] < 0 ? 0 : mapToIndex(px[i])
  return { entries, indices }
}

// ---- tiling ----
// toTiles(indices, width, height, size) -> Uint8Array of packed 4bpp tile bytes.
// The image is a row-major sheet of size x size sprite blocks; tiles within a
// block are plain row-major (8x8), matching the PPU's sprite tile addressing.
function toTiles(indices, width, height, size) {
  if (![8, 16, 32, 64].includes(size)) throw new Error('size must be 8, 16, 32, or 64')
  if (width % size || height % size) throw new Error(`image ${width}x${height} is not a whole number of ${size}x${size} blocks`)
  const tpb = size >> 3, bw = width / size, bh = height / size
  const out = new Uint8Array(bw * bh * tpb * tpb * 32)
  let t = 0
  for (let by = 0; by < bh; by++)
    for (let bx = 0; bx < bw; bx++)
      for (let ty = 0; ty < tpb; ty++)
        for (let tx = 0; tx < tpb; tx++) {
          const px0 = bx * size + tx * 8, py0 = by * size + ty * 8, base = t * 32
          for (let y = 0; y < 8; y++)
            for (let x = 0; x < 8; x += 2) {
              const row = (py0 + y) * width + px0 + x
              out[base + y * 4 + (x >> 1)] = ((indices[row] & 15) << 4) | (indices[row + 1] & 15)
            }
          t++
        }
  return out
}

// ---- asm / json emit ----
const sanitize = name => (name.replace(/[^A-Za-z0-9_.]/g, '_').replace(/^([0-9])/, '_$1')) || 'art'

function emitPalAsm(name, bank, entries) {
  const label = sanitize(name) + '_pal'
  const base = bank * 16
  const L = []
  L.push(`; ${name} palette -> bank ${bank} (palette indices ${base}..${base + entries.length - 1})`)
  L.push('; generated by png2tiles (do not hand-edit). Ports: PAL_INDEX $101008, PAL_DATA $10100A.')
  L.push(`; CALL ${label} once during init to seed the palette.`)
  L.push(`${label}:`)
  L.push(`  MOV R0, #${base}`)
  L.push('  STB R0, [$101008]        ; PAL_INDEX = bank*16')
  for (const e of entries) {
    L.push(`  MOV R0, #$${hex4(e.v555)}`)
    L.push('  STW R0, [$10100A]        ; PAL_DATA (index auto-increments)')
  }
  L.push('  RET')
  return L.join('\n') + '\n'
}

// ---- top level ----
function convert(buffer, opts = {}) {
  const { size = 8, bank = 0, transparent = null, quantize = false, name = 'art' } = opts
  if (![8, 16, 32, 64].includes(size)) throw new Error('--size must be 8, 16, 32, or 64')
  if (!(bank >= 0 && bank <= 15)) throw new Error('--bank must be 0..15')
  const png = decodePng(buffer)
  const { width, height, pixels } = png
  if (width % size || height % size) throw new Error(`image ${width}x${height} is not a multiple of --size ${size}`)
  const { entries, indices } = buildPalette(pixels, width, height, { transparent, quantize })
  const bin = toTiles(indices, width, height, size)
  const tileCount = bin.length / 32
  const palAsm = emitPalAsm(name, bank, entries)
  const json = {
    name, width, height, size, bank, tileCount,
    colorsUsed: entries.length - 1,
    palette: entries.map((e, i) => ({ index: bank * 16 + i, r: e.r, g: e.g, b: e.b, rgb555: e.v555, transparent: !!e.transparent })),
  }
  return { name, width, height, size, bank, tileCount, palette: entries, bin, palAsm, json }
}

function writeOutputs(res, outDir) {
  fs.mkdirSync(outDir, { recursive: true })
  const binPath = path.join(outDir, res.name + '.bin')
  const palPath = path.join(outDir, res.name + '.pal.asm')
  const jsonPath = path.join(outDir, res.name + '.json')
  fs.writeFileSync(binPath, Buffer.from(res.bin))
  fs.writeFileSync(palPath, res.palAsm)
  fs.writeFileSync(jsonPath, JSON.stringify(res.json, null, 2) + '\n')
  return { binPath, palPath, jsonPath }
}

function parseHex(s) {
  const m = /^#?([0-9a-fA-F]{6})$/.exec(s || '')
  if (!m) throw new Error(`--transparent expects RRGGBB hex, got "${s}"`)
  const n = parseInt(m[1], 16)
  return { r: (n >> 16) & 255, g: (n >> 8) & 255, b: n & 255 }
}

const USAGE = `png2tiles — PNG -> 4bpp tiles + RGB555 palette (CastlePalm asset pipeline)

usage: node tools/png2tiles.js <in.png> [options]

options:
  --out DIR             output directory (default: next to the input)
  --name LABEL          base name for the outputs + asm label (default: input filename)
  --size 8|16|32|64     sprite block size; the image is a sheet of these (default: 8)
  --bank N              palette bank 0..15 to seed (default: 0)
  --transparent RRGGBB  treat this colour as transparent (index 0) as well as alpha 0
  --quantize            merge down to 16 colours instead of erroring when there are more

outputs NAME.bin (INCBIN), NAME.pal.asm (PAL_INDEX/PAL_DATA), NAME.json (metadata).`

function main(argv) {
  const args = argv.slice(2)
  if (!args.length || args.includes('-h') || args.includes('--help')) { console.log(USAGE); return 0 }
  let input = null, out = null, name = null, size = 8, bank = 0, transparent = null, quantize = false
  for (let i = 0; i < args.length; i++) {
    const a = args[i]
    if (a === '--out') out = args[++i]
    else if (a === '--name') name = args[++i]
    else if (a === '--size') size = parseInt(args[++i], 10)
    else if (a === '--bank') bank = parseInt(args[++i], 10)
    else if (a === '--transparent') transparent = parseHex(args[++i])
    else if (a === '--quantize') quantize = true
    else if (a.startsWith('--')) throw new Error('unknown option ' + a)
    else input = a
  }
  if (!input) throw new Error('no input PNG given (see --help)')
  name = name || path.basename(input).replace(/\.[^.]+$/, '')
  const res = convert(fs.readFileSync(input), { size, bank, transparent, quantize, name })
  const outDir = out || path.dirname(path.resolve(input))
  const paths = writeOutputs(res, outDir)
  console.log(`png2tiles: ${res.width}x${res.height} -> ${res.tileCount} tiles (size ${size}), ${res.palette.length - 1} colours used, bank ${bank}`)
  console.log(`  ${paths.binPath}  (${res.bin.length} bytes)`)
  console.log(`  ${paths.palPath}`)
  console.log(`  ${paths.jsonPath}`)
  return 0
}

module.exports = { decodePng, unfilter, buildPalette, toTiles, convert, writeOutputs, emitPalAsm, rgb555, c5to8, parseHex }

if (require.main === module) {
  try { process.exit(main(process.argv)) }
  catch (e) { console.error('png2tiles: ' + e.message); process.exit(1) }
}
