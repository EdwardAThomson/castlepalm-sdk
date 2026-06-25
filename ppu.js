'use strict'

class FantasyPPU {
  static WIDTH=320
  static HEIGHT=224
  static VRAM_SIZE=128*1024
  static TILE_BYTES=32
  static TILE_COUNT=2048
  static MAP_WIDTH=64
  static MAP_HEIGHT=64
  static MAP_BYTES=64*64*4
  static MAP_OFFSETS=[0x10000,0x14000]
  static SPRITE_COUNT=128
  static SPRITES_PER_LINE=32

  constructor(){
    this.vram=new Uint8Array(FantasyPPU.VRAM_SIZE)
    this.view=new DataView(this.vram.buffer)
    this.palette=new Uint32Array(256)
    this.layers=[this.makeLayer(0),this.makeLayer(1)]
    this.sprites=Array.from({length:FantasyPPU.SPRITE_COUNT},()=>this.makeSprite())
    this.affineLines=Array(FantasyPPU.HEIGHT).fill(null)
    this.metrics={maxSpritesOnLine:0,droppedSprites:0,visibleSprites:0}
    this.setPalette(0,0,0,0)
  }

  makeLayer(index){
    return {index,enabled:true,scrollX:0,scrollY:0,basePriority:index*2,affine:false}
  }

  makeSprite(){
    return {x:0,y:0,tile:0,palette:0,size:8,priority:3,hflip:false,vflip:false,enabled:false}
  }

  reset(){
    this.vram.fill(0)
    this.palette.fill(0)
    this.layers=[this.makeLayer(0),this.makeLayer(1)]
    this.sprites=Array.from({length:FantasyPPU.SPRITE_COUNT},()=>this.makeSprite())
    this.affineLines.fill(null)
    this.setPalette(0,0,0,0)
  }

  setPalette(index,r,g,b){
    if(index<0||index>255)throw new RangeError('palette index must be 0..255')
    this.palette[index]=(0xff000000|((b&255)<<16)|((g&255)<<8)|(r&255))>>>0
  }

  setTile(index,pixels){
    if(index<0||index>=FantasyPPU.TILE_COUNT)throw new RangeError('tile index out of range')
    if(!pixels||pixels.length!==64)throw new RangeError('tile requires 64 pixels')
    const base=index*FantasyPPU.TILE_BYTES
    for(let i=0;i<64;i+=2)this.vram[base+(i>>1)]=((pixels[i]&15)<<4)|(pixels[i+1]&15)
  }

  tilePixel(index,x,y){
    if(index<0||index>=FantasyPPU.TILE_COUNT)return 0
    const offset=index*FantasyPPU.TILE_BYTES+y*4+(x>>1)
    const packed=this.vram[offset]
    return x&1?packed&15:packed>>4
  }

  encodeMapEntry({tile=0,palette=0,hflip=false,vflip=false,priority=0}={}){
    return ((tile&0x7ff)|((palette&15)<<11)|(hflip?1<<15:0)|(vflip?1<<16:0)|((priority&3)<<17))>>>0
  }

  setMapEntry(layer,x,y,entry){
    this.assertLayer(layer)
    const offset=this.mapOffset(layer,x,y)
    this.view.setUint32(offset,this.encodeMapEntry(entry),true)
  }

  getMapEntry(layer,x,y){
    this.assertLayer(layer)
    const raw=this.view.getUint32(this.mapOffset(layer,x,y),true)
    return {
      tile:raw&0x7ff,
      palette:(raw>>>11)&15,
      hflip:Boolean(raw&(1<<15)),
      vflip:Boolean(raw&(1<<16)),
      priority:(raw>>>17)&3
    }
  }

  mapOffset(layer,x,y){
    x=((x%FantasyPPU.MAP_WIDTH)+FantasyPPU.MAP_WIDTH)%FantasyPPU.MAP_WIDTH
    y=((y%FantasyPPU.MAP_HEIGHT)+FantasyPPU.MAP_HEIGHT)%FantasyPPU.MAP_HEIGHT
    return FantasyPPU.MAP_OFFSETS[layer]+(y*FantasyPPU.MAP_WIDTH+x)*4
  }

  assertLayer(layer){
    if(layer!==0&&layer!==1)throw new RangeError('layer must be 0 or 1')
  }

  setSprite(index,values){
    if(index<0||index>=FantasyPPU.SPRITE_COUNT)throw new RangeError('sprite index out of range')
    const next={...this.makeSprite(),...values}
    if(![8,16,32,64].includes(next.size))throw new RangeError('sprite size must be 8, 16, 32, or 64')
    this.sprites[index]=next
  }

  setAffineLine(y,{startX,startY,dx,dy}){
    if(y<0||y>=FantasyPPU.HEIGHT)throw new RangeError('scanline out of range')
    this.affineLines[y]={startX:startX|0,startY:startY|0,dx:dx|0,dy:dy|0}
  }

  clearAffineLines(){
    this.affineLines.fill(null)
  }

  sampleLayer(layerIndex,worldX,worldY){
    const tileX=Math.floor(worldX/8)
    const tileY=Math.floor(worldY/8)
    const entry=this.getMapEntry(layerIndex,tileX,tileY)
    let px=((worldX%8)+8)%8
    let py=((worldY%8)+8)%8
    if(entry.hflip)px=7-px
    if(entry.vflip)py=7-py
    const colour=this.tilePixel(entry.tile,px,py)
    if(colour===0)return null
    return {colour:this.palette[(entry.palette<<4)|colour],priority:this.layers[layerIndex].basePriority+entry.priority}
  }

  drawLayerLine(layerIndex,y,pixels,priorities){
    const layer=this.layers[layerIndex]
    if(!layer.enabled)return
    const affine=layer.affine?this.affineLines[y]:null
    if(layer.affine&&!affine)return
    let sx=affine?.startX||0,sy=affine?.startY||0
    for(let x=0;x<FantasyPPU.WIDTH;x++){
      const worldX=layer.affine?sx>>16:x+layer.scrollX
      const worldY=layer.affine?sy>>16:y+layer.scrollY
      const sample=this.sampleLayer(layerIndex,worldX,worldY)
      const out=y*FantasyPPU.WIDTH+x
      if(sample&&sample.priority>=priorities[out]){
        pixels[out]=sample.colour
        priorities[out]=sample.priority
      }
      if(layer.affine){sx=(sx+affine.dx)|0;sy=(sy+affine.dy)|0}
    }
  }

  spritePixel(sprite,localX,localY){
    if(sprite.hflip)localX=sprite.size-1-localX
    if(sprite.vflip)localY=sprite.size-1-localY
    const tilesWide=sprite.size>>3
    const tile=sprite.tile+(localY>>3)*tilesWide+(localX>>3)
    return this.tilePixel(tile,localX&7,localY&7)
  }

  drawSpritesLine(y,pixels,priorities){
    const accepted=[]
    let dropped=0
    for(let i=0;i<this.sprites.length;i++){
      const s=this.sprites[i]
      if(!s.enabled||y<s.y||y>=s.y+s.size||s.x>=FantasyPPU.WIDTH||s.x+s.size<=0)continue
      this._seen.add(i)
      if(accepted.length<FantasyPPU.SPRITES_PER_LINE)accepted.push({s,index:i})
      else dropped++
    }
    if(accepted.length>this.metrics.maxSpritesOnLine)this.metrics.maxSpritesOnLine=accepted.length
    this.metrics.droppedSprites+=dropped
    for(let n=accepted.length-1;n>=0;n--){
      const {s}=accepted[n]
      const localY=y-s.y
      for(let localX=0;localX<s.size;localX++){
        const x=s.x+localX
        if(x<0||x>=FantasyPPU.WIDTH)continue
        const colour=this.spritePixel(s,localX,localY)
        if(colour===0)continue
        const out=y*FantasyPPU.WIDTH+x
        if(s.priority>=priorities[out]){
          pixels[out]=this.palette[((s.palette&15)<<4)|colour]
          priorities[out]=s.priority
        }
      }
    }
    this.metrics.visibleSprites=this._seen.size
  }

  // reset per-frame sprite metrics (call once before rendering a frame line-by-line)
  beginFrame(){
    this._seen=new Set()
    this.metrics={maxSpritesOnLine:0,droppedSprites:0,visibleSprites:0}
  }

  // render a single scanline with the CURRENT register/scroll state (enables raster)
  renderLine(y,pixels,priorities){
    const bd=this.palette[0],base=y*FantasyPPU.WIDTH
    for(let x=0;x<FantasyPPU.WIDTH;x++){pixels[base+x]=bd;priorities[base+x]=-1}
    this.drawLayerLine(0,y,pixels,priorities)
    this.drawLayerLine(1,y,pixels,priorities)
    this.drawSpritesLine(y,pixels,priorities)
  }

  render(){
    const pixels=new Uint32Array(FantasyPPU.WIDTH*FantasyPPU.HEIGHT)
    const priorities=new Int8Array(pixels.length)
    this.beginFrame()
    for(let y=0;y<FantasyPPU.HEIGHT;y++)this.renderLine(y,pixels,priorities)
    return pixels
  }
}

if(typeof module!=='undefined')module.exports={FantasyPPU}

