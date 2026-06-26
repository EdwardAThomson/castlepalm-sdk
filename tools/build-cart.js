#!/usr/bin/env node
'use strict'
// Assemble a .asm into a .cpc cartridge.  Usage: node tools/build-cart.js in.asm out.cpc [TITLE]
const fs = require('fs')
const path = require('path')
const { buildCart } = require('../cpu/cart.js')

const [, , inp, outp, title = ''] = process.argv
if (!inp || !outp) { console.error('usage: build-cart.js <in.asm> <out.cpc> [title]'); process.exit(2) }
const baseDir = path.dirname(inp)   // INCBIN paths resolve relative to the .asm file
const cart = buildCart(fs.readFileSync(inp, 'utf8'), { title, readBinary: rel => fs.readFileSync(path.resolve(baseDir, rel)) })
fs.writeFileSync(outp, Buffer.from(cart))
console.log(`assembled ${inp} -> ${outp} (${cart.length} bytes, title "${title}")`)
