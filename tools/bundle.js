#!/usr/bin/env node
'use strict'
// Minimal CommonJS bundler for the browser. Wraps the CPU + system + PPU modules
// into dist/castlepalm.js, exposing window.CastlePalm = { System, REG, buildCart,
// parseCart }. No external deps; a tiny require shim resolves relative paths.

const fs = require('fs')
const path = require('path')
const root = path.join(__dirname, '..')

// embed cartridges so the shell runs from file:// with no fetch
const { buildCart } = require(path.join(root, 'cpu', 'cart.js'))
const examplesDir = path.join(root, 'examples')
const embedCart = (file, title) => Buffer.from(
  buildCart(fs.readFileSync(path.join(examplesDir, file), 'utf8'), { title, readBinary: rel => fs.readFileSync(path.resolve(examplesDir, rel)) })
).toString('base64')
const pongB64 = embedCart('pong.asm', 'PONG')
const snakeB64 = embedCart('snake.asm', 'SNAKE')
const palmblastB64 = embedCart('palmblast.asm', 'PalmBlast')

// module id -> source file (id mirrors the path so relative requires resolve)
const FILES = {
  'cpu/isa': 'cpu/isa.js',
  'cpu/asm': 'cpu/asm.js',
  'cpu/core': 'cpu/core.js',
  'cpu/cart': 'cpu/cart.js',
  'ppu': 'ppu.js',
  'apu': 'apu.js',
  'system': 'system.js',
}

let out = '(function(){\n'
out += 'var __mods={},__cache={};\n'
out += 'function __resolve(from,req){\n'
out += '  if(req.charAt(0)!=="."){return req.replace(/\\.js$/,"");}\n'
out += '  var dir=from.indexOf("/")>=0?from.slice(0,from.lastIndexOf("/")):"";\n'
out += '  var parts=dir?dir.split("/"):[];\n'
out += '  req.replace(/\\.js$/,"").split("/").forEach(function(p){\n'
out += '    if(p==="."){}else if(p===".."){parts.pop();}else{parts.push(p);}\n'
out += '  });\n'
out += '  return parts.join("/");\n'
out += '}\n'
out += 'function __require(id){\n'
out += '  if(__cache[id]){return __cache[id].exports;}\n'
out += '  var m={exports:{}};__cache[id]=m;\n'
out += '  __mods[id](m,m.exports,function(r){return __require(__resolve(id,r));});\n'
out += '  return m.exports;\n'
out += '}\n'

for (const [id, file] of Object.entries(FILES)) {
  const src = fs.readFileSync(path.join(root, file), 'utf8')
  out += `__mods[${JSON.stringify(id)}]=function(module,exports,require){\n${src}\n};\n`
}

out += 'var sys=__require("system"),cart=__require("cpu/cart");\n'
out += 'function __b64(s){var b=atob(s),a=new Uint8Array(b.length);for(var i=0;i<b.length;i++){a[i]=b.charCodeAt(i);}return a;}\n'
out += 'window.CastlePalm={System:sys.System,REG:sys.REG,buildCart:cart.buildCart,parseCart:cart.parseCart,'
out += 'carts:{pong:__b64(' + JSON.stringify(pongB64) + '),snake:__b64(' + JSON.stringify(snakeB64) + '),palmblast:__b64(' + JSON.stringify(palmblastB64) + ')}};\n'
out += '})();\n'

fs.mkdirSync(path.join(root, 'dist'), { recursive: true })
fs.writeFileSync(path.join(root, 'dist', 'castlepalm.js'), out)
console.log('wrote dist/castlepalm.js (' + out.length + ' bytes)')
