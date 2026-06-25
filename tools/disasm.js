#!/usr/bin/env node
'use strict'
// Disassemble a .cpc cartridge from its reset-vector entry point.
// Usage: node tools/disasm.js <cart.cpc> [instruction-count]
const fs = require('fs')
const { parseCart } = require('../cpu/cart.js')
const { CastlePalmCPU } = require('../cpu/core.js')
const { Debugger } = require('../cpu/debug.js')

const [, , file, countArg] = process.argv
if (!file) { console.error('usage: disasm.js <cart.cpc> [count]'); process.exit(2) }

const cart = parseCart(new Uint8Array(fs.readFileSync(file)))
const cpu = new CastlePalmCPU({ rom: cart.rom, romBase: cart.loadBase })
const dbg = new Debugger(cpu)
const count = +(countArg || 48)

console.log(`; ${file} "${cart.title}"  entry ${'$' + cpu.PC.toString(16).padStart(6, '0')}`)
for (const d of dbg.disasmRange(cpu.PC, count)) {
  console.log(`${'$' + d.addr.toString(16).padStart(6, '0')}: ${d.text}`)
}
