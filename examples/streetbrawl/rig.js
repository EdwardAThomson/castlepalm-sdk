'use strict'
// Street Brawl fighter rig: options -> a 64x64 indexed frame + a 15-colour RGB555 bank
// (index 0 transparent), the same contract the PPU uses. Used by gen_art.js
// for the player's selectable bodies; colour ramps come from ramp().
;(function (root) {
  const SIZE = 64
  // ---------- colour ----------
  const hexToRgb = h => [parseInt(h.slice(1, 3), 16), parseInt(h.slice(3, 5), 16), parseInt(h.slice(5, 7), 16)]
  const q5 = v => { const c = Math.max(0, Math.min(255, Math.round(v))) >> 3; return (c << 3) | (c >> 2) }   // RGB555 round trip
  const rgbToHsl = ([r, g, b]) => {
    r /= 255; g /= 255; b /= 255
    const mx = Math.max(r, g, b), mn = Math.min(r, g, b), l = (mx + mn) / 2
    if (mx === mn) return [0, 0, l]
    const d = mx - mn, s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
    const h = mx === r ? (g - b) / d + (g < b ? 6 : 0) : mx === g ? (b - r) / d + 2 : (r - g) / d + 4
    return [h * 60, s, l]
  }
  const hslToRgb = ([h, s, l]) => {
    h = ((h % 360) + 360) % 360 / 360
    if (s === 0) return [l * 255, l * 255, l * 255]
    const f = (p, q, t) => { t = (t + 1) % 1; return t < 1 / 6 ? p + (q - p) * 6 * t : t < 1 / 2 ? q : t < 2 / 3 ? p + (q - p) * (2 / 3 - t) * 6 : p }
    const q = l < 0.5 ? l * (1 + s) : l + s - l * s, p = 2 * l - q
    return [f(p, q, h + 1 / 3) * 255, f(p, q, h) * 255, f(p, q, h - 1 / 3) * 255]
  }
  // pixel-art ramp: shadows shift hue toward blue/purple, highlights toward warm
  function ramp(hex, n = 3) {
    const [h, s, l] = rgbToHsl(hexToRgb(hex))
    const toward = (a, b, t) => a + (((b - a + 540) % 360) - 180) * t
    const steps = n === 2 ? [-0.12, 0.08] : [-0.16, 0, 0.13]
    return steps.map(dl => {
      const hh = dl < 0 ? toward(h, 250, 0.1) : dl > 0 ? toward(h, 55, 0.12) : h
      const ss = Math.min(1, s * (dl < 0 ? 0.92 : dl > 0 ? 0.9 : 1))
      return hslToRgb([hh, ss, Math.max(0.04, Math.min(0.96, l + dl))]).map(q5)
    })
  }
  const NAMES = ['ol', 'sk0', 'sk1', 'sk2', 'hr0', 'hr1', 'jk0', 'jk1', 'jk2', 'jn0', 'jn1', 'jn2', 'sh0', 'sh1', 'wh']
  function makeBank(c) {
    const sk = ramp(c.skin), hr = ramp(c.hair, 2), jk = ramp(c.top), jn = ramp(c.bottom), sh = ramp(c.shoes, 2)
    const ol = hexToRgb(c.outline || '#140c14').map(q5), wh = hexToRgb(c.accent || '#f4f0e8').map(q5)
    const cols = [ol, ...sk, ...hr, ...jk, ...jn, ...sh, wh]
    const idx = {}; NAMES.forEach((n, i) => { idx[n] = i + 1 })
    return { idx, colours: cols }
  }

  // ---------- rig ----------
  const L = (() => { const v = [-0.55, -0.7, 0.55], m = Math.hypot(...v); return v.map(c => c / m) })()
  const add = (a, b) => [a[0] + b[0], a[1] + b[1]]
  const pol = (len, ang) => [Math.sin(ang) * len, Math.cos(ang) * len]   // angle from straight down, + = forward (+x)

  function render(B, parts) {
    const S = SIZE, part = new Int16Array(S * S).fill(-1), shade = new Float32Array(S * S), mat = new Array(S * S)
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
        if (p.flat) I = p.flat
        const k = y * S + x
        part[k] = pi; shade[k] = I; mat[k] = p.mat
      }
    })
    const out = new Uint8Array(S * S)
    for (let k = 0; k < S * S; k++) {
      if (part[k] < 0) continue
      const m = mat[k]
      if (m === 'ol' || m === 'wh') { out[k] = B.idx[m]; continue }
      const r = [B.idx[m + '0'], B.idx[m + '1'], B.idx[m + '2']].filter(Boolean)
      const s = shade[k] > 0.62 ? 2 : shade[k] > 0.2 ? 1 : 0
      out[k] = r[Math.min(s, r.length - 1)]
    }
    for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {           // separation line where a part passes in front
      const k = y * S + x
      if (part[k] < 0 || mat[k] === 'ol' || mat[k] === 'wh') continue
      for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
        const xx = x + dx, yy = y + dy
        if (xx < 0 || yy < 0 || xx >= S || yy >= S) continue
        if (part[yy * S + xx] > part[k] && mat[yy * S + xx] !== mat[k] && !parts[part[yy * S + xx]].noSep) { if (B.idx[mat[k] + '0']) out[k] = B.idx[mat[k] + '0']; break }
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

  const BUILDS = {
    slim:     { scale: 0.96, bulk: 0.82, belly: 0.9, chest: 0.85 },
    athletic: { scale: 1, bulk: 1, belly: 1, chest: 1 },
    stocky:   { scale: 0.94, bulk: 1.2, belly: 1.25, chest: 1.15 },
    heavy:    { scale: 1, bulk: 1.35, belly: 1.45, chest: 1.25 },
    giant:    { scale: 1.0, bulk: 1.5, belly: 1.35, chest: 1.45 },
  }

  // opt: { build, hair, face, top, pose, phase }
  function figure(opt) {
    const b = BUILDS[opt.build] || BUILDS.athletic
    const s = b.scale, bulk = b.bulk, thigh = 12 * s, shin = 12 * s, torso = 16 * s
    const pose = opt.pose || 'walk', phase = opt.phase || 0
    let legs = [phase + Math.PI, phase].map(ph => {
      const th = 0.5 * Math.sin(ph)
      return { th, sh: th - (0.15 + 0.7 * Math.max(0, Math.cos(ph))) }
    })
    let lean = 0, arms
    if (pose === 'walk') arms = [{ up: -0.6 * Math.sin(phase), fo: -0.6 * Math.sin(phase) + 0.8 }, { up: 0.6 * Math.sin(phase), fo: 0.6 * Math.sin(phase) + 0.8 }]
    const stance = [{ th: -0.28, sh: -0.18 }, { th: 0.32, sh: 0.12 }]
    if (pose === 'guard') { legs = stance; arms = [{ up: 0.8, fo: 2.3 }, { up: 0.45, fo: 2.0 }] }
    if (pose === 'punch') { legs = stance; lean = 1.5; arms = [{ up: 0.6, fo: 2.2 }, { up: 1.55, fo: 1.6 }] }
    if (pose === 'kick') { legs = [{ th: -0.15, sh: -0.1 }, { th: 1.45, sh: 1.6 }]; lean = -3; arms = [{ up: -0.4, fo: 0.6 }, { up: 0.9, fo: 2.4 }] }
    if (pose === 'hurt') { legs = [{ th: -0.35, sh: -0.2 }, { th: 0.25, sh: 0.05 }]; lean = -4.5; arms = [{ up: -1.2, fo: -1.6 }, { up: 1.9, fo: 2.5 }] }
    // versus-fighter poses (examples/swornrivals/gen_art.js); the Street Brawl poses above are unchanged
    let hipDx = pose === 'kick' ? -6 : 0, stoop = 1
    const crouch = [{ th: 1.35, sh: -0.55 }, { th: 1.75, sh: -0.2 }], tuck = [{ th: 0.7, sh: -1.2 }, { th: 1.6, sh: 0.2 }]
    const guardArms = [{ up: 0.8, fo: 2.3 }, { up: 0.45, fo: 2.0 }], blockArms = [{ up: 1.1, fo: 2.9 }, { up: 0.85, fo: 2.85 }]
    const punchArms = [{ up: 0.6, fo: 2.2 }, { up: 1.55, fo: 1.6 }]
    if (pose === 'gwalk') arms = guardArms
    if (pose === 'crouch') { legs = crouch; arms = guardArms; lean = 2; stoop = 0.82 }
    if (pose === 'cpunch') { legs = crouch; arms = punchArms; lean = 3; stoop = 0.82 }
    if (pose === 'cblock') { legs = crouch; arms = blockArms; lean = 0; stoop = 0.82 }
    if (pose === 'block') { legs = stance; arms = blockArms; lean = -1.5 }
    if (pose === 'lowkick') { legs = [{ th: 1.2, sh: -0.6 }, { th: 1.52, sh: 1.6 }]; arms = [{ up: -0.2, fo: 0.4 }, { up: 0.9, fo: 2.4 }]; lean = -2; hipDx = -9; stoop = 0.9 }
    if (pose === 'jump') { legs = tuck; arms = [{ up: 1.1, fo: 2.6 }, { up: 0.8, fo: 2.3 }] }
    if (pose === 'airpunch') { legs = tuck; arms = punchArms; lean = 2 }
    if (pose === 'airkick') { legs = [{ th: 0.6, sh: -1.1 }, { th: 1.05, sh: 1.0 }]; arms = [{ up: -0.4, fo: 0.6 }, { up: 0.9, fo: 2.4 }]; lean = -3; hipDx = -6 }
    if (pose === 'rise') { legs = [{ th: -0.15, sh: -0.1 }, { th: 1.35, sh: 0.1 }]; arms = [{ up: -0.5, fo: 0.3 }, { up: 2.75, fo: 3.0 }]; lean = 1.5 }
    if (pose === 'win') { legs = [{ th: -0.18, sh: -0.12 }, { th: 0.18, sh: 0.1 }]; arms = [{ up: -0.35, fo: 1.9 }, { up: 2.7, fo: 3.05 }]; lean = 0 }
    const legDrop = l => Math.cos(l.th) * thigh + Math.cos(l.sh) * shin
    const hip = [32 + hipDx, 61 - Math.max(...legs.map(legDrop)) - 2]
    const sho = add(hip, [2 * s + lean, -torso * stoop])
    const head = add(sho, [1.5 * s + lean * 0.5, -8 * s])
    const sleeves = opt.top === 'jacket' ? 'long' : opt.top === 'tee' ? 'short' : 'none'
    const P = []
    const hairBack = () => {
      if (opt.hair === 'long') P.push({ cap: [add(head, [-3.5, -3]), add(head, [-5, 9])], r: [5.2, 3.2], mat: 'hr' })
      if (opt.hair === 'ponytail') P.push({ cap: [add(head, [-5, -3]), add(head, [-9, 6])], r: [2.6, 1.6], mat: 'hr' })
      if (opt.hair === 'afro') P.push({ ell: add(head, [-1.2, -1.6]), rx: 8.4 * s, ry: 7.4 * s, mat: 'hr' })
    }
    const leg = (l, back) => {
      const knee = add(hip, pol(thigh, l.th)), ankle = add(knee, pol(shin, l.sh))
      P.push({ cap: [hip, knee], r: [4.6 * s * bulk, 3.9 * s * bulk], mat: 'jn', back })
      P.push({ cap: [knee, ankle], r: [3.8 * s * bulk, 3.2 * s * Math.max(1, bulk * 0.9)], mat: 'jn', back })
      P.push({ ell: add(ankle, pol(2.4 * s, l.sh + Math.PI / 2).map((v, i) => i ? Math.abs(v) * 0.3 + 0.8 : Math.abs(v))), rx: 4.4 * s, ry: 2.6 * s, mat: 'sh', back })
    }
    const arm = (a, back) => {
      const elb = add(sho, pol(9 * s, a.up)), wr = add(elb, pol(9 * s, a.fo))
      P.push({ cap: [sho, elb], r: [3.8 * s * bulk, 3.2 * s * bulk], mat: sleeves === 'none' ? 'sk' : 'jk', back })
      P.push({ cap: [elb, wr], r: [3.2 * s * bulk, 2.8 * s * Math.max(1, bulk * 0.9)], mat: sleeves === 'long' ? 'jk' : 'sk', back })
      P.push({ ell: add(wr, pol(1.2, a.fo)), rx: 3.4 * s * Math.max(1, bulk * 0.9), ry: 3.2 * s, mat: opt.gloves ? 'sh' : 'sk', back })
    }
    arm(arms[0], true)
    hairBack()
    leg(legs[0], true)
    leg(legs[1], false)
    P.push({ ell: add(hip, [0, -1]), rx: 6.2 * s * bulk, ry: 4.2 * s, mat: 'jn' })
    P.push({ cap: [add(hip, [0, -3]), add(sho, [0, 3])], r: [6 * s * b.belly, 8 * s * b.chest], mat: 'jk' })
    if (opt.top === 'vest') P.push({ cap: [add(hip, [3 * s, -4]), add(sho, [3.5 * s, 4])], r: [2.2 * s, 2.6 * s], mat: 'sk', noSep: true })
    if (opt.top === 'gi') P.push({ cap: [add(sho, [3.2 * s, 2]), add(hip, [2.5 * s, -8])], r: [1.4, 0.9], mat: 'sk', noSep: true }, { cap: [add(hip, [-6 * s * bulk, -3]), add(hip, [6 * s * bulk, -3])], r: [1.3, 1.3], mat: 'sh' })
    if (opt.top === 'suit') P.push({ cap: [add(sho, [4 * s, 2]), add(hip, [3 * s, -6])], r: [1.6, 1], mat: 'wh', noSep: true }, { cap: [add(sho, [4.5 * s, 3]), add(sho, [4.5 * s, 10])], r: [0.9, 0.7], mat: 'sh', noSep: true })
    P.push({ cap: [sho, add(head, [0, 4])], r: [2.8 * s * Math.max(1, bulk * 0.9), 2.6 * s], mat: 'sk' })
    P.push({ ell: head, rx: 5.6 * s, ry: 6.4 * s, mat: 'sk' })
    const H = opt.hair
    if (H === 'short' || H === 'long' || H === 'ponytail') P.push({ ell: add(head, [-1.6, -2.6]), rx: 6.2 * s, ry: 5.2 * s, mat: 'hr', clip: (x, y) => y < head[1] - 1.5 || x < head[0] - 2 })
    if (H === 'mohawk') P.push({ cap: [add(head, [-4, -4]), add(head, [3, -8])], r: [2.2, 1.6], mat: 'hr' })
    if (H === 'spiky') for (const [dx, dy] of [[-6, -5], [-3, -8], [1, -7.5], [4, -6]]) P.push({ cap: [add(head, [-1, -3]), add(head, [dx, dy])], r: [2.6, 0.8], mat: 'hr' })
    if (H === 'spiky') P.push({ ell: add(head, [-1.4, -2.8]), rx: 5.8 * s, ry: 4.4 * s, mat: 'hr', clip: (x, y) => y < head[1] - 1.5 || x < head[0] - 2 })
    if (H === 'afro') P.push({ ell: add(head, [-1, -3.6]), rx: 7.6 * s, ry: 4.6 * s, mat: 'hr', clip: (x, y) => y < head[1] - 2 || x < head[0] - 3 })
    if (H === 'cap') {
      P.push({ ell: add(head, [-0.5, -2.8]), rx: 6.2 * s, ry: 4.6 * s, mat: 'jk', clip: (x, y) => y < head[1] - 1.8 })
      P.push({ cap: [add(head, [2, -2.2]), add(head, [9, -1.6])], r: [1.2, 1], mat: 'jk' })
      P.push({ ell: add(head, [-3.5, 0]), rx: 2.6, ry: 2.4, mat: 'hr', clip: (x, y) => x < head[0] - 2.5 })
    }
    if (H === 'bald') P.push({ ell: add(head, [-1.5, -2.8]), rx: 1.2, ry: 0.8, mat: 'wh', flat: 1 })   // shine
    const F = opt.face || []
    if (F.includes('beard')) P.push({ ell: add(head, [1.5, 3.5]), rx: 4.4 * s, ry: 3.4 * s, mat: 'hr', clip: (x, y) => y > head[1] + 0.5 })
    if (F.includes('mask')) P.push({ ell: add(head, [1.2, 3]), rx: 5.2 * s, ry: 3.2 * s, mat: 'jk', clip: (x, y) => y > head[1] + 0.8 })
    if (F.includes('band')) { P.push({ cap: [add(head, [-5.6, -2.4]), add(head, [5.6, -3.0])], r: [0.9, 0.9], mat: 'jk' }); P.push({ cap: [add(head, [-5.2, -2.6]), add(head, [-11, 1 + Math.sin(phase * 2)])], r: [1.2, 0.8], mat: 'jk' }) }
    if (F.includes('shades')) P.push({ cap: [add(head, [0.8 * s, -0.8]), add(head, [5.6 * s, -0.6])], r: [1.4, 1.4], mat: 'ol' })
    else P.push({ ell: add(head, [2.8 * s, -0.4]), rx: 0.7, ry: 1.2, mat: 'ol' })
    if (F.includes('scar')) P.push({ cap: [add(head, [1.5, 1]), add(head, [4, 4])], r: [0.5, 0.5], mat: 'wh', flat: 1 })
    arm(arms[1], false)
    return P
  }
  function knockedDown(img) {
    const out = new Uint8Array(SIZE * SIZE)
    let maxY = 0
    for (let oy = 0; oy < 64; oy++) for (let ox = 0; ox < 64; ox++) if (img[oy * 64 + ox]) maxY = Math.max(maxY, 63 - ox)
    const dy = 62 - maxY
    for (let oy = 0; oy < 64; oy++) for (let ox = 0; ox < 64; ox++) {
      const v = img[oy * 64 + ox]; if (!v) continue
      const ny = 63 - ox + dy
      if (ny >= 0 && ny < 64) out[ny * 64 + oy] = v
    }
    return out
  }
  // one frame: { img: Uint8Array(4096) of bank indices, colours: [[r,g,b] x15] }
  function draw(opt) {
    const B = makeBank(opt.colours)
    const pose = opt.pose === 'down' ? { ...opt, pose: 'walk', phase: 0 } : opt
    let img = render(B, figure(pose))
    if (opt.pose === 'down') img = knockedDown(img)
    return { img, colours: B.colours }
  }
  const api = { draw, makeBank, ramp, BUILDS, SIZE }
  if (typeof module !== 'undefined') module.exports = api
  else root.Rig = api
})(this)
