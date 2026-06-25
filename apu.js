'use strict'
// CastlePalm APU v0 (provisional) — 2 square channels + 1 noise channel.
//
// Memory-mapped (system.js routes the audio register block to it), deterministic
// sample generation. The host shell plays the per-frame buffer via Web Audio;
// the core stays headless and deterministic. Channel/register layout is
// provisional (docs/MMIO_V0.md, docs/DECISIONS.md). Square channels are 50% duty;
// a square toggles its sign every `period` samples, so freq = RATE / (2*period).

const RATE = 48000
const SAMPLES_PER_FRAME = 800   // RATE / 60

class CastlePalmAPU {
  constructor() { this.rate = RATE; this.reset() }
  reset() {
    this.sq = [{ period: 0, vol: 0, on: false, cnt: 0, sign: 1 },
               { period: 0, vol: 0, on: false, cnt: 0, sign: 1 }]
    this.noise = { period: 0, vol: 0, on: false, cnt: 0, lfsr: 0x7fff }
  }

  setSquare(i, field, v) {
    const c = this.sq[i]
    if (field === 'periodLo') c.period = (c.period & 0xff00) | (v & 0xff)
    else if (field === 'periodHi') c.period = (c.period & 0x00ff) | ((v & 0xff) << 8)
    else if (field === 'vol') c.vol = v & 0x0f
    else if (field === 'ctrl') c.on = !!(v & 1)
  }
  setNoise(field, v) {
    const n = this.noise
    if (field === 'periodLo') n.period = (n.period & 0xff00) | (v & 0xff)
    else if (field === 'periodHi') n.period = (n.period & 0x00ff) | ((v & 0xff) << 8)
    else if (field === 'vol') n.vol = v & 0x0f
    else if (field === 'ctrl') n.on = !!(v & 1)
  }

  // generate n mono samples in [-1,1] (Float32), advancing channel state.
  generate(n = SAMPLES_PER_FRAME) {
    const out = new Float32Array(n)
    for (let s = 0; s < n; s++) {
      let acc = 0
      for (const c of this.sq) {
        if (c.on && c.period > 0) {
          if (++c.cnt >= c.period) { c.cnt = 0; c.sign = -c.sign }
          acc += c.sign * c.vol
        }
      }
      const no = this.noise
      if (no.on && no.period > 0) {
        if (++no.cnt >= no.period) {
          no.cnt = 0
          const fb = (no.lfsr ^ (no.lfsr >> 1)) & 1
          no.lfsr = (no.lfsr >> 1) | (fb << 14)
        }
        acc += (no.lfsr & 1 ? 1 : -1) * no.vol
      }
      out[s] = acc / 64   // 3 channels * 15 max = 45 -> stays under 1.0
    }
    return out
  }
}

module.exports = { CastlePalmAPU, AUDIO_RATE: RATE, SAMPLES_PER_FRAME }
