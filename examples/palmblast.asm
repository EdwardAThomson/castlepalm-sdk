; CastlePalm — Arena (PALMBLAST), per docs/ARENA_DESIGN.md
; Milestone M1: destructible board generation + render. A 13x11 grid of 16x16
; cells (each a 2x2 cluster of 8x8 BG0 tiles), origin (56,24). Border + even/even
; pillar lattice = HARD, spawn pockets forced FLOOR, the rest a seeded-RNG SOFT
; fill. Movement, bombs, etc. arrive in later milestones.

; --- MMIO ---
INPUT0    EQU $100000
INPUT1    EQU $100002
VRAM_ADDR EQU $101000
VRAM_DATA EQU $101004
PAL_INDEX EQU $101008
PAL_DATA  EQU $10100A
OAM_INDEX EQU $10100C
OAM_DATA  EQU $10100E
PPU_CTRL  EQU $101018
UP    EQU 1
DOWN  EQU 2
LEFT  EQU 4
RIGHT EQU 8
ABTN  EQU 16           ; A button = drop bomb
START EQU 256
PLTILE EQU 16          ; player sprite tile base (16x16)
BOMBTILE EQU 20        ; bomb sprite tile base (16x16, tiles 20..23)
FLAMTILE EQU 24        ; flame sprite tile base (16x16, tiles 24..27)
LET16  EQU 28          ; 16x16 letters A..Z, 4 tiles each (28..131), VRAM $380
BIGDIG EQU 132         ; 16x16 digits 0..9, 4 tiles each (132..171), VRAM $1080
SQ0_PERIOD EQU $102000 ; APU square 0 (placement/boom blip)
SQ0_VOL    EQU $102002
SQ0_CTRL   EQU $102003
FUSE0 EQU 120          ; bomb fuse frames (~2s @ 60Hz)
FLTTL EQU 30           ; flame time-to-live frames
RANGE EQU 2            ; blast range in cells (fixed v0)

; --- grid ---
GCOLS EQU 13           ; visible columns (cx 0..12)
GROWS EQU 11           ; visible rows (cy 0..10)
TOX   EQU 7            ; tile-X of the playfield origin (56px / 8)
TOY   EQU 3            ; tile-Y of the playfield origin (24px / 8)
FLOOR EQU 0
SOFT  EQU 1
HARD  EQU 2

; --- RAM ---
state    EQU $000100
rng      EQU $000104
winner   EQU $000106
aliveCnt EQU $000108
P0IN     EQU $00010A   ; sampled INPUT0 this frame
P1IN     EQU $00010C   ; sampled INPUT1 this frame
P0IN_PR  EQU $00010E   ; previous-frame INPUT0 (A-button edge detect)
P1IN_PR  EQU $000110   ; previous-frame INPUT1
sfxT     EQU $000112   ; sound-effect countdown (frames)
aimode   EQU $000114   ; 0 = 2 players, 1 = 1 player (P1 driven by the AI)
amx      EQU $000116   ; AI scratch: my cx
amy      EQU $000117   ; AI scratch: my cy
aox      EQU $000118   ; AI scratch: opponent cx
aoy      EQU $000119   ; AI scratch: opponent cy
aip      EQU $00011A   ; AI primary chase dir
ais      EQU $00011B   ; AI secondary chase dir
aidir    EQU $00011C   ; AI dir being tried
acef     EQU $00011D   ; AI escape-check accumulator
acx2     EQU $00011E   ; AI scratch: neighbour cell being probed
acy2     EQU $00011F
; --- DETQ: same-frame chain work queue (ring of bomb-slot indices) ---
DETQ     EQU $000120   ; 8 bytes, bomb-slot indices pending detonation
detHead  EQU $000128   ; u8 dequeue index (mod 8)
detTail  EQU $00012A   ; u8 enqueue index (mod 8)
P0       EQU $000200   ; player 0 slot (16 bytes)
P1       EQU $000210   ; player 1 slot
;   +0 alive u8   +2 px u16   +4 py u16   +7 cx u8   +8 cy u8
;   +10 liveBombs u8   +13 bombCell u8 (own-bomb grace; $FF = none)
; --- BOMBS: 8 slots x 8 bytes, base $280 (slot n at +n*8) ---
;   +0 alive u8   +1 owner u8   +2 cx u8   +3 cy u8   +4 fuse u16   +6 range u8
BOMBS    EQU $000280
; --- FLAMES: 32 slots x 4 bytes, base $300 (purely VISUAL) ---
;   +0 alive u8   +1 cx u8   +2 cy u8   +3 ttl u8
FLAMES   EQU $000300
WORLD    EQU $002000   ; u8 per cell, idx = (cy<<4)+cx  (0 FLOOR, 1 SOFT, 2 HARD)
BOMBAT   EQU $002100   ; u8 per cell, 0 none else (bomb_slot+1)
FIREAT   EQU $002200   ; u8 per cell, 0 none else this-frame fire stamp

  ORG $300000
  DA start
  DA 0
  DA 0
  DA 0

start:
  ; palette: 0 black; 1-2 floor; 3-5 crate; 6-8 pillar (shaded)
  MOV R0, #0
  STB R0, [PAL_INDEX]
  MOV R0, #$0000
  STW R0, [PAL_DATA]    ; 0 black
  MOV R0, #$2108
  STW R0, [PAL_DATA]    ; 1 floor dark
  MOV R0, #$318C
  STW R0, [PAL_DATA]    ; 2 floor grid
  MOV R0, #$11D8
  STW R0, [PAL_DATA]    ; 3 crate base
  MOV R0, #$331F
  STW R0, [PAL_DATA]    ; 4 crate highlight
  MOV R0, #$08CC
  STW R0, [PAL_DATA]    ; 5 crate shadow
  MOV R0, #$4210
  STW R0, [PAL_DATA]    ; 6 pillar base
  MOV R0, #$6B5A
  STW R0, [PAL_DATA]    ; 7 pillar highlight
  MOV R0, #$18C6
  STW R0, [PAL_DATA]    ; 8 pillar shadow
  ; 16x16 cell art -> tiles 4..15 (VRAM $80), 384 bytes (floor/crate/pillar x4)
  MOV R0, #$80
  STB R0, [VRAM_ADDR]
  MOV R0, #0
  STB R0, [VRAM_ADDR+1]
  STB R0, [VRAM_ADDR+2]
  LDA A0, #arttiles
  MOV R1, #384
st_art:
  LDB R2, [A0]
  STB R2, [VRAM_DATA]
  INC A0
  SUB R1, #1
  BNE st_art
  ; player palettes: bank 1 (P0 green) at index 17-19, bank 2 (P1 red) at 33-35
  MOV R0, #17
  STB R0, [PAL_INDEX]
  MOV R0, #$0360         ; P0 body green
  STW R0, [PAL_DATA]
  MOV R0, #$0120         ; P0 outline dark green
  STW R0, [PAL_DATA]
  MOV R0, #$7FFF         ; eyes white
  STW R0, [PAL_DATA]
  MOV R0, #33
  STB R0, [PAL_INDEX]
  MOV R0, #$021F         ; P1 body red-orange
  STW R0, [PAL_DATA]
  MOV R0, #$000A         ; P1 outline dark red
  STW R0, [PAL_DATA]
  MOV R0, #$7FFF         ; eyes white
  STW R0, [PAL_DATA]
  ; player sprite -> tiles 16..19 (VRAM $200), 128 bytes
  MOV R0, #0
  STB R0, [VRAM_ADDR]
  MOV R0, #2
  STB R0, [VRAM_ADDR+1]
  MOV R0, #0
  STB R0, [VRAM_ADDR+2]
  LDA A0, #playertile
  MOV R1, #128
st_pl:
  LDB R2, [A0]
  STB R2, [VRAM_DATA]
  INC A0
  SUB R1, #1
  BNE st_pl
  ; bomb palette: bank 3 (index 49 dark, 50 highlight, 51 fuse spark)
  MOV R0, #49
  STB R0, [PAL_INDEX]
  MOV R0, #$1084         ; dark sphere
  STW R0, [PAL_DATA]
  MOV R0, #$4631         ; highlight
  STW R0, [PAL_DATA]
  MOV R0, #$03FF         ; fuse spark (yellow)
  STW R0, [PAL_DATA]
  ; flame palette: bank 4 (index 65 orange, 66 yellow, 67 red core)
  MOV R0, #65
  STB R0, [PAL_INDEX]
  MOV R0, #$029F         ; orange
  STW R0, [PAL_DATA]
  MOV R0, #$23FF         ; yellow
  STW R0, [PAL_DATA]
  MOV R0, #$009F         ; red core
  STW R0, [PAL_DATA]
  ; bomb sprite -> tiles 20..23 (VRAM 20*32 = $280), 128 bytes
  MOV R0, #$80
  STB R0, [VRAM_ADDR]
  MOV R0, #2
  STB R0, [VRAM_ADDR+1]
  MOV R0, #0
  STB R0, [VRAM_ADDR+2]
  LDA A0, #bombtile
  MOV R1, #128
st_bm:
  LDB R2, [A0]
  STB R2, [VRAM_DATA]
  INC A0
  SUB R1, #1
  BNE st_bm
  ; flame sprite -> tiles 24..27 (VRAM 24*32 = $300), 128 bytes
  MOV R0, #0
  STB R0, [VRAM_ADDR]
  MOV R0, #3
  STB R0, [VRAM_ADDR+1]
  MOV R0, #0
  STB R0, [VRAM_ADDR+2]
  LDA A0, #flametile
  MOV R1, #128
st_fl:
  LDB R2, [A0]
  STB R2, [VRAM_DATA]
  INC A0
  SUB R1, #1
  BNE st_fl
  ; banner palette: bank 5 (index 81 = text white) for 16x16 font
  MOV R0, #81
  STB R0, [PAL_INDEX]
  MOV R0, #$7FFF         ; 1 = white
  STW R0, [PAL_DATA]
  ; 16x16 letter font -> tiles 28.. (VRAM 28*32 = $380), 3328 bytes
  MOV R0, #$80
  STB R0, [VRAM_ADDR]
  MOV R0, #3
  STB R0, [VRAM_ADDR+1]
  MOV R0, #0
  STB R0, [VRAM_ADDR+2]
  LDA A0, #letter16
  MOV R1, #3328
st_l16:
  LDB R2, [A0]
  STB R2, [VRAM_DATA]
  INC A0
  SUB R1, #1
  BNE st_l16
  ; 16x16 digit font -> tiles 132.. (VRAM 132*32 = $1080), 1280 bytes
  MOV R0, #$80
  STB R0, [VRAM_ADDR]
  MOV R0, #$10
  STB R0, [VRAM_ADDR+1]
  MOV R0, #0
  STB R0, [VRAM_ADDR+2]
  LDA A0, #bigdigit
  MOV R1, #1280
st_b16:
  LDB R2, [A0]
  STB R2, [VRAM_DATA]
  INC A0
  SUB R1, #1
  BNE st_b16
  ; enable BG0, seed RNG, show the TITLE screen
  MOV R0, #1
  STW R0, [PPU_CTRL]
  MOV R0, #$ACE1
  STW R0, [rng]
  MOV R0, #0
  STW R0, [state]
  STW R0, [sfxT]
  STW R0, [winner]
  STW R0, [aliveCnt]
  CALL drawtitle

mainloop:
  CALL readpads
  LDW R0, [state]
  CMP R0, #1
  BEQ ml_play
  ; TITLE or OVER: A = 1 player (vs AI), B = 2 players, Start = 1 player
  LDW R0, [P0IN]
  MOV R2, R0
  AND R2, #ABTN          ; A -> 1 player
  BEQ ml_nA
  MOV R2, #1
  STW R2, [aimode]
  BRA ml_begin
ml_nA:
  MOV R2, R0
  AND R2, #32            ; B -> 2 players
  BEQ ml_nB
  MOV R2, #0
  STW R2, [aimode]
  BRA ml_begin
ml_nB:
  AND R0, #START         ; Start -> 1 player (default)
  BEQ ml_wait
  MOV R2, #1
  STW R2, [aimode]
ml_begin:
  CALL newround
  MOV R0, #200           ; round-start chirp
  MOV R1, #8
  CALL sfx
  BRA ml_wait
ml_play:
  CALL clearfire
  CALL tickflames
  CALL tickbombs
  CALL aithink           ; 1-player mode: AI writes P1IN before P1 reads it
  CALL movep0
  CALL movep1
  CALL dropbombs
  CALL deathcheck
  CALL wincheck
  CALL buildoam
ml_wait:
  CALL sfxtick
  WAIT
  BRA mainloop

; ---- sample both controller words (keep previous for edge detect) ----
readpads:
  LDW R0, [P0IN]
  STW R0, [P0IN_PR]
  LDW R0, [P1IN]
  STW R0, [P1IN_PR]
  LDW R0, [INPUT0]
  STW R0, [P0IN]
  LDW R0, [INPUT1]
  STW R0, [P1IN]
  RET

; ---- clear the 176-byte FIREAT grid (rebuilt each frame) ----
clearfire:
  LDA A0, #FIREAT
  MOV R1, #176
cf_lp:
  MOV R2, #0
  STB R2, [A0]
  INC A0
  SUB R1, #1
  BNE cf_lp
  RET

; ---- stampfire(R4=cx, R5=cy): FIREAT[idx]=1 ----
stampfire:
  MOV R2, R5
  SHL R2, #4
  ADD R2, R4
  LDA A0, #FIREAT
  ADD A0, R2
  MOV R2, #1
  STB R2, [A0]
  RET

; ---- spawnflame(R4=cx, R5=cy): alloc a FLAMES slot, ttl=FLTTL ----
spawnflame:
  LDA A0, #FLAMES
  MOV R3, #32           ; slot count
sf_find:
  LDB R0, [A0]
  CMP R0, #0
  BEQ sf_got
  ADD A0, #4
  SUB R3, #1
  BNE sf_find
  RET                  ; pool full: lethality is grid-based, drop the visual
sf_got:
  MOV R0, #1
  STB R0, [A0+#0]
  STB R4, [A0+#1]
  STB R5, [A0+#2]
  MOV R0, #FLTTL
  STB R0, [A0+#3]
  RET

; ---- countflames(R4=cx, R5=cy) -> R6 = # of live flames on that cell ----
countflames:
  MOV R6, #0
  LDA A0, #FLAMES
  MOV R3, #32
cnf_lp:
  LDB R0, [A0]
  CMP R0, #0
  BEQ cnf_next
  LDB R0, [A0+#1]
  CMP R0, R4
  BNE cnf_next
  LDB R0, [A0+#2]
  CMP R0, R5
  BNE cnf_next
  ADD R6, #1
cnf_next:
  ADD A0, #4
  SUB R3, #1
  BNE cnf_lp
  RET

; ---- tick flames: ttl--; on 0 free + repaint FLOOR if last; else restamp FIREAT ----
tickflames:
  LDA A1, #FLAMES
  MOV R7, #32
tf_lp:
  LDB R0, [A1]
  CMP R0, #0
  BEQ tf_next
  LDB R0, [A1+#3]      ; ttl
  SUB R0, #1
  STB R0, [A1+#3]
  CMP R0, #0
  BNE tf_alive
  MOV R0, #0           ; expired: free slot
  STB R0, [A1+#0]
  LDB R4, [A1+#1]
  LDB R5, [A1+#2]
  CALL countflames     ; any live flame still on this cell?
  CMP R6, #0
  BNE tf_next
  CALL paintcell       ; last flame gone -> repaint cell from WORLD
  BRA tf_next
tf_alive:
  LDB R4, [A1+#1]      ; still lethal this frame
  LDB R5, [A1+#2]
  CALL stampfire
tf_next:
  ADD A1, #4
  SUB R7, #1
  BNE tf_lp
  RET

; ---- tick bombs: fuse--; at 0 detq_push(slot); then drain the chain queue ----
tickbombs:
  MOV R7, #0           ; slot index
tb_lp:
  MOV R3, R7
  SHL R3, #3           ; slot*8
  LDA A1, #BOMBS
  ADD A1, R3
  LDB R0, [A1]
  CMP R0, #0
  BEQ tb_next
  LDW R0, [A1+#4]      ; fuse
  SUB R0, #1
  STW R0, [A1+#4]
  CMP R0, #0
  BNE tb_next
  MOV R0, R7
  CALL detq_push       ; queue, don't detonate inline
tb_next:
  ADD R7, #1
  CMP R7, #8
  BLT tb_lp
  ; --- chain drain: detonate every queued bomb (may queue more) ---
tb_drain:
  CALL detq_pop        ; -> R0 slot, R1 = 1 if got one else 0
  CMP R1, #0
  BEQ tb_done
  CALL detonate
  BRA tb_drain
tb_done:
  RET

; ---- detq_push(R0=slot): append slot to the ring (mod 8) ----
detq_push:
  LDB R1, [detTail]
  LDA A0, #DETQ
  ADD A0, R1
  STB R0, [A0]
  ADD R1, #1
  AND R1, #7
  STB R1, [detTail]
  RET

; ---- detq_pop -> R0=slot, R1=1 if a slot was dequeued, 0 if queue empty ----
detq_pop:
  LDB R2, [detHead]
  LDB R3, [detTail]
  CMP R2, R3
  BNE dp_have
  MOV R1, #0           ; empty
  RET
dp_have:
  LDA A0, #DETQ
  ADD A0, R2
  LDB R0, [A0]
  ADD R2, #1
  AND R2, #7
  STB R2, [detHead]
  MOV R1, #1
  RET

; ---- detonate(R0=slot): clear bomb, refund owner, stamp/spawn centre + 4 arms ----
detonate:
  MOV R7, R0           ; keep slot in R7 throughout
  MOV R3, R7
  SHL R3, #3
  LDA A1, #BOMBS
  ADD A1, R3
  MOV R0, #0
  STB R0, [A1+#0]      ; alive = 0
  LDB R4, [A1+#2]      ; cx
  LDB R5, [A1+#3]      ; cy
  ; clear BOMBAT at the bomb cell
  MOV R2, R5
  SHL R2, #4
  ADD R2, R4
  LDA A0, #BOMBAT
  ADD A0, R2
  MOV R0, #0
  STB R0, [A0]
  ; refund owner liveBombs--
  LDB R0, [A1+#1]      ; owner (0 or 1)
  LDA A2, #P0
  CMP R0, #0
  BEQ det_own0
  LDA A2, #P1
det_own0:
  LDB R0, [A2+#10]
  CMP R0, #0
  BEQ det_centre
  SUB R0, #1
  STB R0, [A2+#10]
det_centre:
  ; centre cell: stamp + flame (cx,cy in R4,R5)
  CALL stampfire
  CALL spawnflame
  ; --- four arms; range from bomb slot +6 ---
  ; arm: up (dx=0,dy=-1), down(0,1), left(-1,0), right(1,0)
  MOV R6, #0           ; arm 0 up
det_arm:
  PUSH R4              ; bomb cx
  PUSH R5              ; bomb cy
  PUSH R6              ; current arm dir
  PUSH R7              ; bomb slot (walkarm/paintcell clobber R7)
  CALL walkarm
  POP R7
  POP R6
  POP R5
  POP R4
  ADD R6, #1
  CMP R6, #4
  BLT det_arm
  RET

; ---- walkarm(R6=dir 0u 1d 2l 3r; R4,R5 bomb cell, R7 slot): walk up to range ----
walkarm:
  ; load range for this bomb
  MOV R3, R7
  SHL R3, #3
  LDA A1, #BOMBS
  ADD A1, R3
  LDB R3, [A1+#6]      ; range -> R3 step counter (reuse)
  PUSH R4
  PUSH R5
  MOV R0, R4           ; cur cx in R0
  MOV R1, R5           ; cur cy in R1
wa_step:
  CMP R3, #0
  BNE wa_go
  BRA wa_done
wa_go:
  ; advance one cell in direction R6
  CMP R6, #0
  BNE wa_d1
  SUB R1, #1
  BRA wa_have
wa_d1:
  CMP R6, #1
  BNE wa_d2
  ADD R1, #1
  BRA wa_have
wa_d2:
  CMP R6, #2
  BNE wa_d3
  SUB R0, #1
  BRA wa_have
wa_d3:
  ADD R0, #1
wa_have:
  ; idx = (cy<<4)+cx ; classify WORLD
  PUSH R0
  PUSH R1
  MOV R2, R1
  SHL R2, #4
  ADD R2, R0
  LDA A0, #WORLD
  ADD A0, R2
  LDB R2, [A0]         ; class
  CMP R2, #HARD
  BEQ wa_stop
  CMP R2, #SOFT
  BEQ wa_soft
  ; floor: maybe a bomb sits here -> force-fuse + queue (chain), then continue.
  MOV R4, R0
  MOV R5, R1
  PUSH R3              ; helpers clobber R3 (step counter); preserve it
  CALL chainbomb      ; force-fuse + enqueue any bomb on (R4,R5)
  ; already-fired guard: only stamp/flame once per cell per frame
  MOV R2, R5
  SHL R2, #4
  ADD R2, R4
  LDA A0, #FIREAT
  ADD A0, R2
  LDB R2, [A0]
  CMP R2, #0
  BNE wa_floorcont    ; cell already lit this frame: skip duplicate flame
  CALL stampfire
  CALL spawnflame
wa_floorcont:
  POP R3
  POP R1
  POP R0
  SUB R3, #1
  BRA wa_step
wa_soft:
  ; destroy crate -> FLOOR, repaint, flame, stamp, stop
  POP R1
  POP R0
  MOV R4, R0           ; cx,cy kept in R4,R5 (helpers preserve them)
  MOV R5, R1
  MOV R2, R5
  SHL R2, #4
  ADD R2, R4
  LDA A0, #WORLD
  ADD A0, R2
  MOV R2, #FLOOR
  STB R2, [A0]
  CALL paintcell
  CALL stampfire
  CALL spawnflame
  BRA wa_done
wa_stop:
  POP R1
  POP R0
wa_done:
  POP R5
  POP R4
  RET

; ---- chainbomb(R4=cx, R5=cy): if a bomb sits here, force fuse=0 + queue it ----
; guarded so a bomb reached by two arms is queued only once. Preserves R4,R5.
chainbomb:
  MOV R2, R5
  SHL R2, #4
  ADD R2, R4
  LDA A0, #BOMBAT
  ADD A0, R2
  LDB R0, [A0]         ; bomb_slot+1, or 0
  CMP R0, #0
  BNE cb_have
  RET                  ; no bomb here
cb_have:
  SUB R0, #1           ; R0 = bomb slot
  MOV R3, R0
  SHL R3, #3           ; slot*8
  LDA A1, #BOMBS
  ADD A1, R3
  LDB R1, [A1+#0]      ; alive?
  CMP R1, #0
  BEQ cb_done          ; defensive: stale BOMBAT
  LDW R1, [A1+#4]      ; fuse
  CMP R1, #0
  BEQ cb_done          ; already 0 -> already queued this frame, don't re-push
  MOV R1, #0
  STW R1, [A1+#4]      ; force fuse = 0
  CALL detq_push       ; R0 still = slot
cb_done:
  RET

; ---- drop bombs on A-edge for both players ----
dropbombs:
  LDA A1, #P0
  LDW R0, [P0IN]
  LDW R1, [P0IN_PR]
  MOV R2, #0
  CALL trydrop
  LDA A1, #P1
  LDW R0, [P1IN]
  LDW R1, [P1IN_PR]
  MOV R2, #1
  CALL trydrop
  RET

; ---- trydrop(A1=player, R0=cur in, R1=prev in, R2=owner): drop bomb on A-edge ----
trydrop:
  PUSH R2
  ; edge: A held now AND not held last frame
  AND R0, #ABTN
  BNE td_e1
  BRA td_no
td_e1:
  AND R1, #ABTN
  BEQ td_e2
  BRA td_no
td_e2:
  ; alive?
  LDB R0, [A1+#0]
  CMP R0, #0
  BNE td_e3
  BRA td_no
td_e3:
  ; liveBombs < 1 ?
  LDB R0, [A1+#10]
  CMP R0, #0
  BEQ td_e4
  BRA td_no
td_e4:
  ; cell index, BOMBAT free?
  LDB R4, [A1+#7]      ; cx
  LDB R5, [A1+#8]      ; cy
  MOV R2, R5
  SHL R2, #4
  ADD R2, R4
  LDA A0, #BOMBAT
  ADD A0, R2
  LDB R0, [A0]
  CMP R0, #0
  BEQ td_e5
  BRA td_no
td_e5:
  ; find a free bomb slot
  MOV R3, #0
td_find:
  MOV R2, R3
  SHL R2, #3
  LDA A2, #BOMBS
  ADD A2, R2
  LDB R0, [A2]
  CMP R0, #0
  BEQ td_got
  ADD R3, #1
  CMP R3, #8
  BLT td_find
  BRA td_no            ; no free slot
td_got:
  ; A2 -> bomb slot, R3 = slot index
  MOV R0, #1
  STB R0, [A2+#0]      ; alive
  POP R2               ; owner
  PUSH R2
  STB R2, [A2+#1]      ; owner
  STB R4, [A2+#2]      ; cx
  STB R5, [A2+#3]      ; cy
  MOV R0, #FUSE0
  STW R0, [A2+#4]      ; fuse
  MOV R0, #RANGE
  STB R0, [A2+#6]      ; range
  ; BOMBAT[cell] = slot+1
  MOV R2, R5
  SHL R2, #4
  ADD R2, R4
  LDA A0, #BOMBAT
  ADD A0, R2
  MOV R0, R3
  ADD R0, #1
  STB R0, [A0]
  ; liveBombs++ ; bombCell = cell index (own-bomb grace)
  LDB R0, [A1+#10]
  ADD R0, #1
  STB R0, [A1+#10]
  STB R2, [A1+#13]
td_no:
  POP R2
  RET

; ---- move player 0 (no player-vs-player check) ----
movep0:
  LDB R0, [P0+0]
  CMP R0, #0
  BNE mp0_go
  RET
mp0_go:
  LDA A1, #P0
  LDW R6, [P0IN]
  MOV R7, #0
  CALL domove
  RET

; ---- move player 1 (blocked by P0) ----
movep1:
  LDB R0, [P1+0]
  CMP R0, #0
  BNE mp1_go
  RET
mp1_go:
  LDA A1, #P1
  LDW R6, [P1IN]
  MOV R7, #1
  CALL domove
  RET

; ---- domove(A1=player, R6=input, R7=pvp flag): pixel move w/ collision ----
; px in R4, py in R5 held across collision helpers (which preserve R4-R7).
domove:
  LDW R4, [A1+#2]
  LDW R5, [A1+#4]
  ; --- horizontal ---
  MOV R0, R6
  AND R0, #LEFT
  BEQ dm_tryright
  MOV R0, R4           ; new left edge = px-1
  SUB R0, #1
  MOV R1, R5
  CALL cellsolid
  CMP R2, #0
  BNE dm_lend
  MOV R0, R4
  SUB R0, #1
  MOV R1, R5
  ADD R1, #15
  CALL cellsolid
  CMP R2, #0
  BNE dm_lend
  CMP R7, #0
  BEQ dm_doleft
  MOV R0, R4
  SUB R0, #1
  MOV R1, R5
  CALL pvpblocks
  CMP R2, #0
  BNE dm_lend
dm_doleft:
  SUB R4, #1
dm_lend:
  BRA dm_hend
dm_tryright:
  MOV R0, R6
  AND R0, #RIGHT
  BEQ dm_hend
  MOV R0, R4           ; new right edge = px+1+15 = px+16
  ADD R0, #16
  MOV R1, R5
  CALL cellsolid
  CMP R2, #0
  BNE dm_hend
  MOV R0, R4
  ADD R0, #16
  MOV R1, R5
  ADD R1, #15
  CALL cellsolid
  CMP R2, #0
  BNE dm_hend
  CMP R7, #0
  BEQ dm_doright
  MOV R0, R4
  ADD R0, #1
  MOV R1, R5
  CALL pvpblocks
  CMP R2, #0
  BNE dm_hend
dm_doright:
  ADD R4, #1
dm_hend:
  ; --- vertical ---
  MOV R0, R6
  AND R0, #UP
  BEQ dm_trydown
  MOV R0, R4
  MOV R1, R5           ; new top edge = py-1
  SUB R1, #1
  CALL cellsolid
  CMP R2, #0
  BNE dm_uend
  MOV R0, R4
  ADD R0, #15
  MOV R1, R5
  SUB R1, #1
  CALL cellsolid
  CMP R2, #0
  BNE dm_uend
  CMP R7, #0
  BEQ dm_doup
  MOV R0, R4
  MOV R1, R5
  SUB R1, #1
  CALL pvpblocks
  CMP R2, #0
  BNE dm_uend
dm_doup:
  SUB R5, #1
dm_uend:
  BRA dm_vend
dm_trydown:
  MOV R0, R6
  AND R0, #DOWN
  BEQ dm_vend
  MOV R0, R4
  MOV R1, R5           ; new bottom edge = py+16
  ADD R1, #16
  CALL cellsolid
  CMP R2, #0
  BNE dm_vend
  MOV R0, R4
  ADD R0, #15
  MOV R1, R5
  ADD R1, #16
  CALL cellsolid
  CMP R2, #0
  BNE dm_vend
  CMP R7, #0
  BEQ dm_dodown
  MOV R0, R4
  MOV R1, R5
  ADD R1, #1
  CALL pvpblocks
  CMP R2, #0
  BNE dm_vend
dm_dodown:
  ADD R5, #1
dm_vend:
  ; --- cornering: moving on one axis nudges the other onto the grid (1px/frame),
  ;     so a full-cell player can slide into the 1-cell corridors ---
  MOV R0, R6
  AND R0, #12           ; LEFT|RIGHT pressed -> align py to nearest row
  BEQ dm_alignx
  MOV R0, R5
  SUB R0, #24
  ADD R0, #8
  SHR R0, #4
  SHL R0, #4
  ADD R0, #24           ; nearest row-aligned py
  CMP R0, R5
  BEQ dm_alignx
  BLT dm_pyup
  ADD R5, #1
  BRA dm_alignx
dm_pyup:
  SUB R5, #1
dm_alignx:
  MOV R0, R6
  AND R0, #3            ; UP|DOWN pressed -> align px to nearest column
  BEQ dm_wb
  MOV R0, R4
  SUB R0, #56
  ADD R0, #8
  SHR R0, #4
  SHL R0, #4
  ADD R0, #56           ; nearest column-aligned px
  CMP R0, R4
  BEQ dm_wb
  BLT dm_pxleft
  ADD R4, #1
  BRA dm_wb
dm_pxleft:
  SUB R4, #1
dm_wb:
  STW R4, [A1+#2]
  STW R5, [A1+#4]
  ; cx = (px+8-56)>>4 = (px-48)>>4 ; cy = (py-16)>>4
  MOV R0, R4
  SUB R0, #48
  SHR R0, #4
  STB R0, [A1+#7]
  MOV R0, R5
  SUB R0, #16
  SHR R0, #4
  STB R0, [A1+#8]
  RET

; ---- cellsolid(R0=pixelX, R1=pixelY) -> R2 = WORLD class (0 passable) ----
cellsolid:
  SUB R0, #56
  MOV R2, R0
  AND R2, #$8000
  BEQ cs_okx
  MOV R0, #0
cs_okx:
  SHR R0, #4
  SUB R1, #24
  MOV R2, R1
  AND R2, #$8000
  BEQ cs_oky
  MOV R1, #0
cs_oky:
  SHR R1, #4
  SHL R1, #4
  ADD R1, R0
  LDA A0, #WORLD
  ADD A0, R1
  LDB R2, [A0]
  RET

; ---- pvpblocks(R0=newpx, R1=newpy) -> R2 = 1 if box overlaps P0's box ----
pvpblocks:
  LDA A2, #P0
  LDW R3, [A2+#2]
  ADD R3, #16
  CMP R0, R3
  BGE pvp_no           ; newpx >= ox+16
  LDW R3, [A2+#2]
  MOV R2, R0
  ADD R2, #16
  CMP R3, R2
  BGE pvp_no           ; ox >= newpx+16
  LDW R3, [A2+#4]
  ADD R3, #16
  CMP R1, R3
  BGE pvp_no
  LDW R3, [A2+#4]
  MOV R2, R1
  ADD R2, #16
  CMP R3, R2
  BGE pvp_no
  MOV R2, #1
  RET
pvp_no:
  MOV R2, #0
  RET

; ---- build OAM: two player sprites ----
buildoam:
  MOV R0, #0
  STW R0, [OAM_INDEX]
  ; slot 0,1: players (only while alive)
  LDB R0, [P0+0]
  CMP R0, #0
  BEQ bo_p0off
  LDA A1, #P0
  MOV R6, #$11         ; size16 | palette bank 1
  CALL emitsprite
  BRA bo_p1
bo_p0off:
  CALL emitoff
bo_p1:
  LDB R0, [P1+0]
  CMP R0, #0
  BEQ bo_p1off
  LDA A1, #P1
  MOV R6, #$12         ; size16 | palette bank 2
  CALL emitsprite
  BRA bo_bm0
bo_p1off:
  CALL emitoff
bo_bm0:
  ; slots 2..9: bombs (8)
  MOV R7, #0
bo_bm:
  MOV R3, R7
  SHL R3, #3
  LDA A1, #BOMBS
  ADD A1, R3
  LDB R0, [A1]
  CMP R0, #0
  BEQ bo_bmoff
  LDB R0, [A1+#2]      ; cx -> px = 56 + cx*16
  SHL R0, #4
  ADD R0, #56
  LDB R1, [A1+#3]      ; cy -> py = 24 + cy*16
  SHL R1, #4
  ADD R1, #24
  MOV R5, #BOMBTILE
  MOV R6, #$13         ; size16 | palette bank 3
  CALL emittile
  BRA bo_bmn
bo_bmoff:
  CALL emitoff
bo_bmn:
  ADD R7, #1
  CMP R7, #8
  BLT bo_bm
  ; slots 10..41: flames (32)
  MOV R7, #0
bo_fl:
  MOV R3, R7
  SHL R3, #2
  LDA A1, #FLAMES
  ADD A1, R3
  LDB R0, [A1]
  CMP R0, #0
  BEQ bo_floff
  LDB R0, [A1+#1]      ; cx
  SHL R0, #4
  ADD R0, #56
  LDB R1, [A1+#2]      ; cy
  SHL R1, #4
  ADD R1, #24
  MOV R5, #FLAMTILE
  MOV R6, #$14         ; size16 | palette bank 4
  CALL emittile
  BRA bo_fln
bo_floff:
  CALL emitoff
bo_fln:
  ADD R7, #1
  CMP R7, #32
  BLT bo_fl
  RET

; ---- emittile(R0=px, R1=py, R5=tile, R6=attr-lo): one 16x16 descriptor ----
emittile:
  STB R0, [OAM_DATA]
  MOV R2, R0
  SHR R2, #8
  STB R2, [OAM_DATA]
  STB R1, [OAM_DATA]
  MOV R2, R1
  SHR R2, #8
  STB R2, [OAM_DATA]
  STB R5, [OAM_DATA]
  MOV R2, #0
  STB R2, [OAM_DATA]
  STB R6, [OAM_DATA]
  MOV R2, #$80
  STB R2, [OAM_DATA]   ; attr hi: enable
  RET

; ---- emitoff: write one disabled descriptor (advances OAM_INDEX by 8) ----
emitoff:
  MOV R2, #0
  STB R2, [OAM_DATA]
  STB R2, [OAM_DATA]
  STB R2, [OAM_DATA]
  STB R2, [OAM_DATA]
  STB R2, [OAM_DATA]
  STB R2, [OAM_DATA]
  STB R2, [OAM_DATA]
  STB R2, [OAM_DATA]   ; attr hi 0 -> disabled
  RET

; ---- emitsprite(A1=player, R6=attr-lo): 16x16 player descriptor ----
emitsprite:
  LDW R0, [A1+#2]      ; px
  STB R0, [OAM_DATA]
  MOV R2, R0
  SHR R2, #8
  STB R2, [OAM_DATA]
  LDW R0, [A1+#4]      ; py
  STB R0, [OAM_DATA]
  MOV R2, R0
  SHR R2, #8
  STB R2, [OAM_DATA]
  MOV R0, #PLTILE
  STB R0, [OAM_DATA]
  MOV R0, #0
  STB R0, [OAM_DATA]
  STB R6, [OAM_DATA]   ; attr lo: size16 | bank
  MOV R0, #$80
  STB R0, [OAM_DATA]   ; attr hi: enable
  RET

; ---- death check: a live player on a FIREAT cell dies this frame ----
deathcheck:
  LDA A1, #P0
  CALL dc_one
  LDA A1, #P1
  CALL dc_one
  RET
; dc_one(A1=player): if alive and FIREAT[cell]!=0 -> alive=0
dc_one:
  LDB R0, [A1+#0]
  CMP R0, #0
  BNE dc_alive
  RET
dc_alive:
  LDB R4, [A1+#7]      ; cx
  LDB R5, [A1+#8]      ; cy
  MOV R2, R5
  SHL R2, #4
  ADD R2, R4
  LDA A0, #FIREAT
  ADD A0, R2
  LDB R2, [A0]
  CMP R2, #0
  BNE dc_die
  RET
dc_die:
  MOV R0, #0
  STB R0, [A1+#0]      ; alive = 0
  MOV R0, #300         ; death tone
  MOV R1, #16
  CALL sfx
  RET

; ---- win check: count alive; <=1 -> state=over, set winner ----
wincheck:
  LDB R0, [P0+0]
  LDB R1, [P1+0]
  MOV R2, R0
  ADD R2, R1           ; alive count (0,1,2)
  STW R2, [aliveCnt]
  CMP R2, #2
  BLT wc_end
  RET                  ; both alive: round continues
wc_end:
  ; round over: derive winner. P0 alive -> 1, P1 alive -> 2, none -> 3 draw
  CMP R0, #0
  BEQ wc_notp0
  MOV R3, #1
  BRA wc_set
wc_notp0:
  CMP R1, #0
  BEQ wc_draw
  MOV R3, #2
  BRA wc_set
wc_draw:
  MOV R3, #3
wc_set:
  STW R3, [winner]
  MOV R0, #2
  STW R0, [state]
  CALL drawgameover    ; clears screen + sprites, draws GAME OVER
  RET

; ---- sfx(R0=period, R1=timer frames): blip on SQ0 ----
sfx:
  STW R0, [SQ0_PERIOD]
  MOV R0, #12
  STB R0, [SQ0_VOL]
  MOV R0, #1
  STB R0, [SQ0_CTRL]
  STW R1, [sfxT]
  RET

; ---- advance the sfx timer; silence SQ0 when it expires ----
sfxtick:
  LDW R0, [sfxT]
  CMP R0, #0
  BEQ sfx_idle
  SUB R0, #1
  STW R0, [sfxT]
  CMP R0, #0
  BNE sfx_idle
  MOV R0, #0
  STB R0, [SQ0_CTRL]
sfx_idle:
  RET

; ---- print16(R4=tileX, R5=tileY, A1=glyph string): 16x16 text, 2 cells/glyph ----
; bytes: 0-25 = A-Z, 26 = space, 27-36 = digit 0-9, $FF = end
print16:
p16_loop:
  LDB R2, [A1]
  CMP R2, #$FF
  BEQ p16_done
  CMP R2, #26
  BEQ p16_adv
  CMP R2, #27
  BGE p16_digit
  ; letter: tile = LET16 + index*4
  SHL R2, #2
  ADD R2, #LET16
  BRA p16_emit
p16_digit:
  SUB R2, #27          ; digit 0..9
  SHL R2, #2
  ADD R2, #BIGDIG
p16_emit:
  MOV R6, R2
  MOV R0, R4           ; top-left
  MOV R1, R5
  CALL settile
  MOV R0, R4           ; top-right
  ADD R0, #1
  MOV R1, R5
  MOV R2, R6
  ADD R2, #1
  CALL settile
  MOV R0, R4           ; bottom-left
  MOV R1, R5
  ADD R1, #1
  MOV R2, R6
  ADD R2, #2
  CALL settile
  MOV R0, R4           ; bottom-right
  ADD R0, #1
  MOV R1, R5
  ADD R1, #1
  MOV R2, R6
  ADD R2, #3
  CALL settile
p16_adv:
  ADD R4, #2
  INC A1
  BRA p16_loop
p16_done:
  RET

; ---- clear BG0 map to tile 0 (blank) over the visible field ----
clearbg:
  MOV R5, #0
cbg_y:
  MOV R4, #0
cbg_x:
  MOV R0, R4
  MOV R1, R5
  MOV R2, #0
  CALL settile
  ADD R4, #1
  CMP R4, #40
  BLT cbg_x
  ADD R5, #1
  CMP R5, #28
  BLT cbg_y
  RET

; ---- clearoam: disable all 128 sprites (zero the 1 KiB OAM) ----
clearoam:
  MOV R0, #0
  STW R0, [OAM_INDEX]
  MOV R1, #1024
co_lp:
  MOV R0, #0
  STB R0, [OAM_DATA]
  SUB R1, #1
  BNE co_lp
  RET

; ---- fillpanel: dark (tile 0) backdrop behind the game-over text ----
;   covers tile region x 10..35, y 5..18 (frames all three text lines)
fillpanel:
  MOV R7, #5
fp_y:
  MOV R6, #10
fp_x:
  MOV R0, R6
  MOV R1, R7
  MOV R2, #0
  CALL settile
  ADD R6, #1
  CMP R6, #36
  BLT fp_x
  ADD R7, #1
  CMP R7, #19
  BLT fp_y
  RET

; ---- TITLE screen: clear board, big PALMBLAST + PUSH START ----
; ================= single-player AI: drives P1 as a virtual controller =================
; Writes P1IN each frame in 1-player mode. Priority: flee live blasts/fire, bomb when
; lined up with the opponent (only with an escape), else chase; bomb crates in the way.
aithink:
  LDW R0, [aimode]
  CMP R0, #0
  BNE ait_on
  RET                     ; 2-player: leave P1IN = human INPUT1
ait_on:
  LDB R0, [P1]            ; AI alive?
  CMP R0, #0
  BNE ait_live
  MOV R0, #0
  STW R0, [P1IN]
  RET
ait_live:
  LDB R0, [P1+7]
  STB R0, [amx]
  LDB R0, [P1+8]
  STB R0, [amy]
  LDB R0, [P0+7]
  STB R0, [aox]
  LDB R0, [P0+8]
  STB R0, [aoy]
  LDB R4, [amx]           ; in danger on my own cell? -> flee
  LDB R5, [amy]
  CALL aidanger
  CMP R0, #0
  BEQ ait_safe
  CALL aiflee
  RET
ait_safe:
  LDB R0, [amy]           ; same row as opponent?
  LDB R1, [aoy]
  CMP R0, R1
  BNE ait_ckcol
  LDB R0, [amx]
  LDB R1, [aox]
  SUB R0, R1
  CALL ai_abs
  CMP R0, #RANGE
  BLE ait_wantbomb
ait_ckcol:
  LDB R0, [amx]           ; same column as opponent?
  LDB R1, [aox]
  CMP R0, R1
  BNE ait_chase
  LDB R0, [amy]
  LDB R1, [aoy]
  SUB R0, R1
  CALL ai_abs
  CMP R0, #RANGE
  BLE ait_wantbomb
  BRA ait_chase
ait_wantbomb:
  CALL ai_canescape
  CMP R0, #0
  BEQ ait_chase          ; no diagonal escape -> don't self-trap
  MOV R0, #ABTN
  STW R0, [P1IN]
  RET
ait_chase:
  CALL ai_movetoward
  RET

; ai_abs(R0) -> |R0|
ai_abs:
  CMP R0, #0
  BGE aab_p
  NEG R0
aab_p:
  RET

; aidanger(R4=cx,R5=cy) -> R0 (1 if live fire here, or reachable by a bomb blast)
aidanger:
  MOV R2, R5
  SHL R2, #4
  ADD R2, R4
  LDA A0, #FIREAT
  ADD A0, R2
  LDB R0, [A0]
  CMP R0, #0
  BEQ adg_b
  MOV R0, #1
  RET
adg_b:
  LDA A1, #BOMBS
  MOV R7, #8
adg_lp:
  LDB R0, [A1]
  CMP R0, #0
  BEQ adg_nx
  LDB R2, [A1+#2]       ; bomb cx
  LDB R3, [A1+#3]       ; bomb cy
  CALL ai_inblast
  CMP R0, #0
  BNE adg_dg
adg_nx:
  MOV R6, #8
  ADD A1, R6
  SUB R7, #1
  BNE adg_lp
  MOV R0, #0
  RET
adg_dg:
  MOV R0, #1
  RET

; ai_inblast(R2=bcx,R3=bcy, R4=cx,R5=cy) -> R0 (1 if cell reached by bomb blast;
;   blast stops at the first solid cell). Preserves R4,R5,R7,A1.
ai_inblast:
  CMP R2, R4
  BNE aib_ns
  CMP R3, R5
  BEQ aib_yes
aib_ns:
  CMP R3, R5           ; same row?
  BNE aib_col
  MOV R0, R4
  SUB R0, R2
  CALL ai_abs
  CMP R0, #RANGE
  BGT aib_no
  CMP R4, R2
  BLT aib_rneg
  MOV R6, #1
  BRA aib_rw
aib_rneg:
  MOV R6, #1
  NEG R6
aib_rw:
  MOV R1, R2
aib_rwl:
  ADD R1, R6
  CMP R1, R4
  BEQ aib_yes
  MOV R0, R5
  SHL R0, #4
  ADD R0, R1
  LDA A0, #WORLD
  ADD A0, R0
  LDB R0, [A0]
  CMP R0, #FLOOR
  BNE aib_no
  BRA aib_rwl
aib_no:
  MOV R0, #0
  RET
aib_yes:
  MOV R0, #1
  RET
aib_col:
  CMP R2, R4           ; same column?
  BNE aib_no2
  MOV R0, R5
  SUB R0, R3
  CALL ai_abs
  CMP R0, #RANGE
  BGT aib_no2
  CMP R5, R3
  BLT aib_cneg
  MOV R6, #1
  BRA aib_cw
aib_cneg:
  MOV R6, #1
  NEG R6
aib_cw:
  MOV R1, R3
aib_cwl:
  ADD R1, R6
  CMP R1, R5
  BEQ aib_yes2
  MOV R0, R1
  SHL R0, #4
  ADD R0, R4
  LDA A0, #WORLD
  ADD A0, R0
  LDB R0, [A0]
  CMP R0, #FLOOR
  BNE aib_no2
  BRA aib_cwl
aib_no2:
  MOV R0, #0
  RET
aib_yes2:
  MOV R0, #1
  RET

; ai_cellkind(R4=cx,R5=cy) -> R0 (0 free floor, 1 soft crate, 2 blocked/oob)
ai_cellkind:
  CMP R4, #0
  BLT ack_block
  CMP R4, #GCOLS
  BGE ack_block
  CMP R5, #0
  BLT ack_block
  CMP R5, #GROWS
  BGE ack_block
  MOV R2, R5
  SHL R2, #4
  ADD R2, R4
  LDA A0, #WORLD
  ADD A0, R2
  LDB R0, [A0]
  CMP R0, #SOFT
  BEQ ack_soft
  CMP R0, #FLOOR
  BNE ack_block
  LDA A0, #BOMBAT
  ADD A0, R2
  LDB R0, [A0]
  CMP R0, #0
  BNE ack_block
  MOV R0, #0
  RET
ack_soft:
  MOV R0, #1
  RET
ack_block:
  MOV R0, #2
  RET

; ai_safecell(R4,R5) -> R0 (1 if free floor AND not dangerous)
ai_safecell:
  CALL ai_cellkind
  CMP R0, #0
  BNE asc_no
  CALL aidanger
  CMP R0, #0
  BNE asc_no
  MOV R0, #1
  RET
asc_no:
  MOV R0, #0
  RET

; ai_hasescape -> R0 (1 if any neighbour of my cell is safe to flee to)
ai_hasescape:
  LDB R4, [amx]
  LDB R5, [amy]
  SUB R5, #1
  CALL ai_safecell
  CMP R0, #0
  BNE ahe_y
  LDB R4, [amx]
  LDB R5, [amy]
  ADD R5, #1
  CALL ai_safecell
  CMP R0, #0
  BNE ahe_y
  LDB R4, [amx]
  SUB R4, #1
  LDB R5, [amy]
  CALL ai_safecell
  CMP R0, #0
  BNE ahe_y
  LDB R4, [amx]
  ADD R4, #1
  LDB R5, [amy]
  CALL ai_safecell
  CMP R0, #0
  BNE ahe_y
  MOV R0, #0
  RET
ahe_y:
  MOV R0, #1
  RET

; aiflee: set P1IN to the first safe neighbour (else wander)
aiflee:
  LDB R4, [amx]
  LDB R5, [amy]
  SUB R5, #1
  CALL ai_safecell
  CMP R0, #0
  BEQ afl_d
  MOV R0, #UP
  STW R0, [P1IN]
  RET
afl_d:
  LDB R4, [amx]
  LDB R5, [amy]
  ADD R5, #1
  CALL ai_safecell
  CMP R0, #0
  BEQ afl_l
  MOV R0, #DOWN
  STW R0, [P1IN]
  RET
afl_l:
  LDB R4, [amx]
  SUB R4, #1
  LDB R5, [amy]
  CALL ai_safecell
  CMP R0, #0
  BEQ afl_r
  MOV R0, #LEFT
  STW R0, [P1IN]
  RET
afl_r:
  LDB R4, [amx]
  ADD R4, #1
  LDB R5, [amy]
  CALL ai_safecell
  CMP R0, #0
  BEQ afl_x
  MOV R0, #RIGHT
  STW R0, [P1IN]
  RET
afl_x:
  CALL aiflee2step
  RET

; aiflee2step: no neighbour is safe right now, but step toward a free neighbour that
; itself has a safe neighbour (a 2-step dodge out of the blast). Else stay put.
aiflee2step:
  LDB R4, [amx]
  LDB R5, [amy]
  SUB R5, #1
  CALL ai_leadsafe
  CMP R0, #0
  BEQ a2_d
  MOV R0, #UP
  STW R0, [P1IN]
  RET
a2_d:
  LDB R4, [amx]
  LDB R5, [amy]
  ADD R5, #1
  CALL ai_leadsafe
  CMP R0, #0
  BEQ a2_l
  MOV R0, #DOWN
  STW R0, [P1IN]
  RET
a2_l:
  LDB R4, [amx]
  SUB R4, #1
  LDB R5, [amy]
  CALL ai_leadsafe
  CMP R0, #0
  BEQ a2_r
  MOV R0, #LEFT
  STW R0, [P1IN]
  RET
a2_r:
  LDB R4, [amx]
  ADD R4, #1
  LDB R5, [amy]
  CALL ai_leadsafe
  CMP R0, #0
  BEQ a2_n
  MOV R0, #RIGHT
  STW R0, [P1IN]
  RET
a2_n:
  MOV R0, #0
  STW R0, [P1IN]
  RET

; ai_leadsafe(R4=cx,R5=cy) -> R0 (1 if that cell is free AND has a safe neighbour)
ai_leadsafe:
  CALL ai_cellkind
  CMP R0, #0
  BNE als_no
  STB R4, [acx2]
  STB R5, [acy2]
  LDB R4, [acx2]
  LDB R5, [acy2]
  SUB R5, #1
  CALL ai_safecell
  CMP R0, #0
  BNE als_yes
  LDB R4, [acx2]
  LDB R5, [acy2]
  ADD R5, #1
  CALL ai_safecell
  CMP R0, #0
  BNE als_yes
  LDB R4, [acx2]
  SUB R4, #1
  LDB R5, [acy2]
  CALL ai_safecell
  CMP R0, #0
  BNE als_yes
  LDB R4, [acx2]
  ADD R4, #1
  LDB R5, [acy2]
  CALL ai_safecell
  CMP R0, #0
  BNE als_yes
als_no:
  MOV R0, #0
  RET
als_yes:
  MOV R0, #1
  RET

; ai_wander: move to any SAFE neighbour (free + not in a blast); else stay put.
; Using safe (not just free) cells stops the AI wandering back into its own bomb.
ai_wander:
  LDB R4, [amx]
  ADD R4, #1
  LDB R5, [amy]
  CALL ai_safecell
  CMP R0, #0
  BEQ awn_l
  MOV R0, #RIGHT
  STW R0, [P1IN]
  RET
awn_l:
  LDB R4, [amx]
  SUB R4, #1
  LDB R5, [amy]
  CALL ai_safecell
  CMP R0, #0
  BEQ awn_u
  MOV R0, #LEFT
  STW R0, [P1IN]
  RET
awn_u:
  LDB R4, [amx]
  LDB R5, [amy]
  SUB R5, #1
  CALL ai_safecell
  CMP R0, #0
  BEQ awn_d
  MOV R0, #UP
  STW R0, [P1IN]
  RET
awn_d:
  LDB R4, [amx]
  LDB R5, [amy]
  ADD R5, #1
  CALL ai_safecell
  CMP R0, #0
  BEQ awn_n
  MOV R0, #DOWN
  STW R0, [P1IN]
  RET
awn_n:
  MOV R0, #0
  STW R0, [P1IN]
  RET

; ai_movetoward: chase the opponent on the dominant axis (try other axis, then wander)
ai_movetoward:
  LDB R0, [aox]
  LDB R1, [amx]
  SUB R0, R1            ; dx
  LDB R2, [aoy]
  LDB R3, [amy]
  SUB R2, R3            ; dy
  MOV R4, #0            ; hdir
  CMP R0, #0
  BEQ amt_h0
  BLT amt_hl
  MOV R4, #RIGHT
  BRA amt_h0
amt_hl:
  MOV R4, #LEFT
amt_h0:
  MOV R5, #0            ; vdir
  CMP R2, #0
  BEQ amt_v0
  BLT amt_vu
  MOV R5, #DOWN
  BRA amt_v0
amt_vu:
  MOV R5, #UP
amt_v0:
  CMP R0, #0            ; |dx|
  BGE amt_dxp
  NEG R0
amt_dxp:
  CMP R2, #0            ; |dy|
  BGE amt_dyp
  NEG R2
amt_dyp:
  CMP R0, R2
  BLT amt_vpri
  STB R4, [aip]        ; horizontal dominant
  STB R5, [ais]
  BRA amt_go
amt_vpri:
  STB R5, [aip]        ; vertical dominant
  STB R4, [ais]
amt_go:
  LDB R0, [aip]
  CMP R0, #0
  BEQ amt_sec
  CALL ai_trydir
  CMP R0, #0
  BNE amt_ret
amt_sec:
  LDB R0, [ais]
  CMP R0, #0
  BEQ amt_wan
  CALL ai_trydir
  CMP R0, #0
  BNE amt_ret
amt_wan:
  CALL ai_wander
amt_ret:
  RET

; ai_trydir(R0=dir): move that way if free; bomb a crate there if escapable. R0=1 if acted.
ai_trydir:
  STB R0, [aidir]
  LDB R4, [amx]
  LDB R5, [amy]
  CMP R0, #UP
  BNE atd_nd
  SUB R5, #1
  BRA atd_h
atd_nd:
  CMP R0, #DOWN
  BNE atd_nl
  ADD R5, #1
  BRA atd_h
atd_nl:
  CMP R0, #LEFT
  BNE atd_nr
  SUB R4, #1
  BRA atd_h
atd_nr:
  ADD R4, #1
atd_h:
  CALL ai_cellkind
  CMP R0, #0
  BEQ atd_move         ; free floor -> move
  CMP R0, #1
  BNE atd_bl           ; wall / pillar / bomb -> blocked, go around
  CALL ai_canescape    ; crate -> bomb it only if we can dodge the blast
  CMP R0, #0
  BEQ atd_bl
  MOV R0, #ABTN
  STW R0, [P1IN]
  MOV R0, #1
  RET
atd_move:
  LDB R0, [aidir]
  STW R0, [P1IN]
  MOV R0, #1
  RET
atd_bl:
  MOV R0, #0
  RET

; ai_canescape -> R0 (1 if a bomb at my cell can be dodged: a safe diagonal cell is
;   reachable via a safe orthogonal step; diagonals are off the bomb's blast cross)
ai_canescape:
  MOV R0, #0
  STB R0, [acef]
  ; up-left
  LDB R4, [amx]
  SUB R4, #1
  LDB R5, [amy]
  SUB R5, #1
  CALL ai_safecell
  CMP R0, #0
  BEQ ace_ur
  LDB R4, [amx]
  SUB R4, #1
  LDB R5, [amy]
  CALL ai_safecell
  CMP R0, #0
  BNE ace_s1
  LDB R4, [amx]
  LDB R5, [amy]
  SUB R5, #1
  CALL ai_safecell
  CMP R0, #0
  BEQ ace_ur
ace_s1:
  MOV R0, #1
  STB R0, [acef]
ace_ur:
  ; up-right
  LDB R4, [amx]
  ADD R4, #1
  LDB R5, [amy]
  SUB R5, #1
  CALL ai_safecell
  CMP R0, #0
  BEQ ace_dl
  LDB R4, [amx]
  ADD R4, #1
  LDB R5, [amy]
  CALL ai_safecell
  CMP R0, #0
  BNE ace_s2
  LDB R4, [amx]
  LDB R5, [amy]
  SUB R5, #1
  CALL ai_safecell
  CMP R0, #0
  BEQ ace_dl
ace_s2:
  MOV R0, #1
  STB R0, [acef]
ace_dl:
  ; down-left
  LDB R4, [amx]
  SUB R4, #1
  LDB R5, [amy]
  ADD R5, #1
  CALL ai_safecell
  CMP R0, #0
  BEQ ace_dr
  LDB R4, [amx]
  SUB R4, #1
  LDB R5, [amy]
  CALL ai_safecell
  CMP R0, #0
  BNE ace_s3
  LDB R4, [amx]
  LDB R5, [amy]
  ADD R5, #1
  CALL ai_safecell
  CMP R0, #0
  BEQ ace_dr
ace_s3:
  MOV R0, #1
  STB R0, [acef]
ace_dr:
  ; down-right
  LDB R4, [amx]
  ADD R4, #1
  LDB R5, [amy]
  ADD R5, #1
  CALL ai_safecell
  CMP R0, #0
  BEQ ace_done
  LDB R4, [amx]
  ADD R4, #1
  LDB R5, [amy]
  CALL ai_safecell
  CMP R0, #0
  BNE ace_s4
  LDB R4, [amx]
  LDB R5, [amy]
  ADD R5, #1
  CALL ai_safecell
  CMP R0, #0
  BEQ ace_done
ace_s4:
  MOV R0, #1
  STB R0, [acef]
ace_done:
  LDB R0, [acef]
  RET

drawtitle:
  CALL clearbg
  MOV R4, #11           ; PALMBLAST: 9 glyphs * 2 = 18 wide, centred (40-18)/2
  MOV R5, #8
  LDA A1, #str_title
  CALL print16
  MOV R4, #10           ; "A 1 PLAYER" (vs AI)
  MOV R5, #16
  LDA A1, #str_solo
  CALL print16
  MOV R4, #10           ; "B 2 PLAYER"
  MOV R5, #20
  LDA A1, #str_duo
  CALL print16
  ; little arena vignette: crate, pillar, crate (16x16 cell blocks)
  MOV R4, #16
  MOV R5, #12
  MOV R2, #8            ; crate (tiles 8-11)
  CALL tblock
  MOV R4, #19
  MOV R5, #12
  MOV R2, #12           ; pillar (tiles 12-15)
  CALL tblock
  MOV R4, #22
  MOV R5, #12
  MOV R2, #8            ; crate
  CALL tblock
  RET

; ---- tblock(R4=tileX, R5=tileY, R2=base tile): draw a 2x2 cell cluster ----
tblock:
  MOV R6, R4
  MOV R7, R5
  MOV R0, R6
  MOV R1, R7
  CALL settile          ; base+0 (TL)
  ADD R2, #1
  MOV R0, R6
  ADD R0, #1
  MOV R1, R7
  CALL settile          ; base+1 (TR)
  ADD R2, #1
  MOV R0, R6
  MOV R1, R7
  ADD R1, #1
  CALL settile          ; base+2 (BL)
  ADD R2, #1
  MOV R0, R6
  ADD R0, #1
  MOV R1, R7
  ADD R1, #1
  CALL settile          ; base+3 (BR)
  RET

; ---- GAME OVER overlay (drawn over the frozen board) ----
drawgameover:
  CALL clearbg          ; full-screen clear so the end screen fills cleanly
  CALL clearoam         ; hide the game sprites
  MOV R4, #13           ; GAME OVER: 9 glyphs -> 18 wide
  MOV R5, #6
  LDA A1, #str_over
  CALL print16
  ; result line based on winner
  LDW R0, [winner]
  CMP R0, #1
  BEQ dgo_p1
  CMP R0, #2
  BEQ dgo_p2
  ; draw
  MOV R4, #17
  MOV R5, #11
  LDA A1, #str_draw
  CALL print16
  BRA dgo_push
dgo_p1:
  MOV R4, #15
  MOV R5, #11
  LDA A1, #str_p1win
  CALL print16
  BRA dgo_push
dgo_p2:
  MOV R4, #15
  MOV R5, #11
  LDA A1, #str_p2win
  CALL print16
dgo_push:
  MOV R4, #15
  MOV R5, #16
  LDA A1, #str_push
  CALL print16
  RET

; --- glyph strings (0-25 = A-Z, 26 = space, 27-36 = 0-9, $FF = end) ---
str_title:
  DB 15,0,11,12,1,11,0,18,19,$FF             ; PALMBLAST
str_solo:
  DB 0,26,28,26,15,11,0,24,4,17,$FF          ; A 1 PLAYER
str_duo:
  DB 1,26,29,26,15,11,0,24,4,17,$FF          ; B 2 PLAYER
str_push:
  DB 15,20,18,7,26,18,19,0,17,19,$FF         ; PUSH START
str_over:
  DB 6,0,12,4,26,14,21,4,17,$FF             ; GAME OVER
str_p1win:
  DB 15,28,26,22,8,13,18,$FF                 ; P1 WINS
str_p2win:
  DB 15,29,26,22,8,13,18,$FF                 ; P2 WINS
str_draw:
  DB 3,17,0,22,$FF                           ; DRAW

; ---- (re)start a round: generate + paint the board, place players ----
newround:
  CALL clearbg          ; wipe the whole viewport (clears title/over text outside the arena)
  CALL clearpools
  CALL genworld
  CALL paintboard
  ; P0 at cell (1,1): px = 56 + 1*16 = 72, py = 24 + 1*16 = 40
  MOV R0, #1
  STB R0, [P0+0]
  STB R0, [P0+7]
  STB R0, [P0+8]
  MOV R0, #0
  STB R0, [P0+10]       ; liveBombs
  MOV R0, #$FF
  STB R0, [P0+13]       ; bombCell none
  MOV R0, #72
  STW R0, [P0+2]
  MOV R0, #40
  STW R0, [P0+4]
  ; P1 at cell (11,9): px = 56 + 11*16 = 232, py = 24 + 9*16 = 168
  MOV R0, #1
  STB R0, [P1+0]
  MOV R0, #11
  STB R0, [P1+7]
  MOV R0, #9
  STB R0, [P1+8]
  MOV R0, #0
  STB R0, [P1+10]       ; liveBombs
  MOV R0, #$FF
  STB R0, [P1+13]       ; bombCell none
  MOV R0, #232
  STW R0, [P1+2]
  MOV R0, #168
  STW R0, [P1+4]
  MOV R0, #2
  STW R0, [aliveCnt]
  MOV R0, #0
  STW R0, [winner]
  MOV R0, #1
  STW R0, [state]
  RET

; ---- clear bomb/flame pools + BOMBAT/FIREAT grids ----
clearpools:
  LDA A0, #BOMBS        ; 64 bytes (8 slots x 8)
  MOV R1, #64
cp_b:
  MOV R2, #0
  STB R2, [A0]
  INC A0
  SUB R1, #1
  BNE cp_b
  LDA A0, #FLAMES       ; 128 bytes (32 slots x 4)
  MOV R1, #128
cp_f:
  MOV R2, #0
  STB R2, [A0]
  INC A0
  SUB R1, #1
  BNE cp_f
  LDA A0, #BOMBAT       ; 176 bytes
  MOV R1, #176
cp_ba:
  MOV R2, #0
  STB R2, [A0]
  INC A0
  SUB R1, #1
  BNE cp_ba
  LDA A0, #FIREAT       ; 176 bytes
  MOV R1, #176
cp_fa:
  MOV R2, #0
  STB R2, [A0]
  INC A0
  SUB R1, #1
  BNE cp_fa
  MOV R0, #0            ; reset chain queue
  STB R0, [detHead]
  STB R0, [detTail]
  RET

; ---- generate WORLD[] (R4=cx, R5=cy loop) ----
genworld:
  MOV R5, #0
gw_y:
  MOV R4, #0
gw_x:
  CALL cellclass        ; -> R6 = class for (cx,cy)
  MOV R2, R5
  SHL R2, #4
  ADD R2, R4            ; idx = (cy<<4)+cx
  LDA A0, #WORLD
  ADD A0, R2
  STB R6, [A0]
  ADD R4, #1
  CMP R4, #GCOLS
  BLT gw_x
  ADD R5, #1
  CMP R5, #GROWS
  BLT gw_y
  RET

; ---- cellclass(R4=cx, R5=cy) -> R6 (consumes RNG only for random interior) ----
cellclass:
  CMP R4, #0
  BEQ cc_hard
  CMP R4, #12
  BEQ cc_hard
  CMP R5, #0
  BEQ cc_hard
  CMP R5, #10
  BEQ cc_hard
  ; interior lattice: cx even AND cy even -> HARD pillar
  MOV R6, R4
  AND R6, #1
  BNE cc_notlat
  MOV R6, R5
  AND R6, #1
  BNE cc_notlat
cc_hard:
  MOV R6, #HARD
  RET
cc_notlat:
  CALL ispocket
  CMP R6, #0
  BNE cc_floor
  CALL nextrng
  AND R0, #3
  BEQ cc_floor          ; 25% floor, 75% soft
  MOV R6, #SOFT
  RET
cc_floor:
  MOV R6, #FLOOR
  RET

; ---- ispocket(R4=cx, R5=cy) -> R6 (1 if a spawn pocket, forced FLOOR) ----
ispocket:
  CMP R4, #1
  BNE ip_a
  CMP R5, #1
  BEQ ip_yes
  CMP R5, #2
  BEQ ip_yes
ip_a:
  CMP R4, #2
  BNE ip_b
  CMP R5, #1
  BEQ ip_yes
ip_b:
  CMP R4, #11
  BNE ip_c
  CMP R5, #9
  BEQ ip_yes
  CMP R5, #8
  BEQ ip_yes
ip_c:
  CMP R4, #10
  BNE ip_no
  CMP R5, #9
  BEQ ip_yes
ip_no:
  MOV R6, #0
  RET
ip_yes:
  MOV R6, #1
  RET

; ---- paint the whole board (R4=cx, R5=cy loop) ----
paintboard:
  MOV R5, #0
pb_y:
  MOV R4, #0
pb_x:
  CALL paintcell
  ADD R4, #1
  CMP R4, #GCOLS
  BLT pb_x
  ADD R5, #1
  CMP R5, #GROWS
  BLT pb_y
  RET

; ---- paintcell(R4=cx, R5=cy): paint the 2x2 cluster from WORLD[] ----
paintcell:
  MOV R2, R5
  SHL R2, #4
  ADD R2, R4
  LDA A0, #WORLD
  ADD A0, R2
  LDB R2, [A0]         ; class
  SHL R2, #2
  ADD R2, #4           ; base tile = 4 + class*4 (floor 4, crate 8, pillar 12)
  MOV R6, R4           ; base tileX = TOX + cx*2
  SHL R6, #1
  ADD R6, #TOX
  MOV R7, R5           ; base tileY = TOY + cy*2
  SHL R7, #1
  ADD R7, #TOY
  MOV R0, R6           ; TL = base+0
  MOV R1, R7
  CALL settile
  ADD R2, #1
  MOV R0, R6           ; TR = base+1
  ADD R0, #1
  MOV R1, R7
  CALL settile
  ADD R2, #1
  MOV R0, R6           ; BL = base+2
  MOV R1, R7
  ADD R1, #1
  CALL settile
  ADD R2, #1
  MOV R0, R6           ; BR = base+3
  ADD R0, #1
  MOV R1, R7
  ADD R1, #1
  CALL settile
  RET

; ---- settile(R0=tileX, R1=tileY, R2=tile): one BG0 map entry ----
settile:
  MOV R3, R1
  SHL R3, #6
  ADD R3, R0
  SHL R3, #2            ; (tileY*64 + tileX) * 4
  STB R3, [VRAM_ADDR]
  MOV R0, R3
  SHR R0, #8
  STB R0, [VRAM_ADDR+1]
  MOV R0, #1
  STB R0, [VRAM_ADDR+2] ; bit16 -> BG0 map base $10000
  STB R2, [VRAM_DATA]
  MOV R0, #0
  STB R0, [VRAM_DATA]
  STB R0, [VRAM_DATA]
  STB R0, [VRAM_DATA]
  RET

; ---- next RNG value (xorshift16) -> R0 ----
nextrng:
  LDW R0, [rng]
  MOV R1, R0
  SHL R1, #7
  XOR R0, R1
  MOV R1, R0
  SHR R1, #9
  XOR R0, R1
  MOV R1, R0
  SHL R1, #8
  XOR R0, R1
  STW R0, [rng]
  RET

; --- 16x16 cell art, tiles 4..15 (floor 4-7, crate 8-11, pillar 12-15; TL,TR,BL,BR) ---
arttiles:
  DB $22,$22,$22,$22,$21,$11,$11,$11,$21,$11,$11,$11,$21,$11,$11,$11
  DB $21,$11,$11,$11,$21,$11,$11,$11,$21,$11,$11,$11,$21,$11,$11,$11
  DB $22,$22,$22,$22,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11
  DB $11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11
  DB $21,$11,$11,$11,$21,$11,$11,$11,$21,$11,$11,$11,$21,$11,$11,$11
  DB $21,$11,$11,$11,$21,$11,$11,$11,$21,$11,$11,$11,$21,$11,$11,$11
  DB $11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11
  DB $11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11
  DB $55,$55,$55,$55,$54,$44,$44,$44,$54,$33,$33,$33,$54,$33,$33,$33
  DB $54,$33,$33,$33,$54,$33,$33,$33,$54,$33,$33,$33,$54,$55,$55,$55
  DB $55,$55,$55,$55,$44,$44,$44,$45,$33,$33,$33,$55,$33,$33,$33,$55
  DB $33,$33,$33,$55,$33,$33,$33,$55,$33,$33,$33,$55,$55,$55,$55,$55
  DB $54,$55,$55,$55,$54,$33,$33,$33,$54,$33,$33,$33,$54,$33,$33,$33
  DB $54,$33,$33,$33,$54,$33,$33,$33,$54,$55,$55,$55,$55,$55,$55,$55
  DB $55,$55,$55,$55,$33,$33,$33,$55,$33,$33,$33,$55,$33,$33,$33,$55
  DB $33,$33,$33,$55,$33,$33,$33,$55,$55,$55,$55,$55,$55,$55,$55,$55
  DB $77,$77,$77,$77,$77,$66,$66,$66,$77,$66,$66,$66,$77,$66,$66,$66
  DB $77,$66,$66,$66,$77,$66,$66,$66,$77,$66,$66,$66,$77,$66,$66,$66
  DB $77,$77,$77,$77,$66,$66,$66,$68,$66,$66,$66,$68,$66,$66,$66,$68
  DB $66,$66,$66,$68,$66,$66,$66,$68,$66,$66,$66,$68,$66,$66,$66,$68
  DB $77,$66,$66,$66,$77,$66,$66,$66,$77,$66,$66,$66,$77,$66,$66,$66
  DB $77,$66,$66,$66,$77,$66,$66,$66,$76,$66,$66,$66,$78,$88,$88,$88
  DB $66,$66,$66,$68,$66,$66,$66,$68,$66,$66,$66,$68,$66,$66,$66,$68
  DB $66,$66,$66,$68,$66,$66,$66,$68,$66,$66,$66,$68,$88,$88,$88,$88

; --- 16x16 player sprite, tiles 16..19 (TL,TR,BL,BR; colour 1 body, 2 outline, 3 eyes) ---
playertile:
  DB $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$22,$22,$00,$02,$21,$11
  DB $00,$21,$11,$11,$02,$23,$33,$11,$02,$13,$33,$11,$02,$13,$33,$11
  DB $00,$00,$00,$00,$00,$00,$00,$00,$22,$22,$00,$00,$11,$12,$20,$00
  DB $11,$11,$12,$00,$11,$33,$32,$20,$11,$33,$31,$20,$11,$33,$31,$20
  DB $02,$13,$33,$11,$02,$11,$11,$11,$02,$11,$11,$11,$02,$11,$11,$11
  DB $02,$21,$11,$11,$00,$21,$11,$11,$00,$02,$21,$11,$00,$00,$22,$22
  DB $11,$33,$31,$20,$11,$11,$11,$20,$11,$11,$11,$20,$11,$11,$11,$20
  DB $11,$11,$12,$20,$11,$11,$12,$00,$11,$12,$20,$00,$22,$22,$00,$00

; --- 16x16 bomb sprite, tiles 20..23 (TL,TR,BL,BR; 1 sphere, 2 highlight, 3 fuse) ---
bombtile:
  DB $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$11
  DB $00,$00,$11,$11,$00,$01,$22,$11,$00,$01,$22,$11,$00,$11,$11,$11
  DB $33,$00,$00,$00,$33,$00,$00,$00,$33,$00,$00,$00,$11,$00,$00,$00
  DB $11,$11,$00,$00,$11,$11,$10,$00,$11,$11,$10,$00,$11,$11,$11,$00
  DB $00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00,$01,$11,$11
  DB $00,$01,$11,$11,$00,$00,$11,$11,$00,$00,$00,$11,$00,$00,$00,$00
  DB $11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$10,$00
  DB $11,$11,$10,$00,$11,$11,$00,$00,$11,$00,$00,$00,$00,$00,$00,$00

; --- 16x16 flame sprite, tiles 24..27 (TL,TR,BL,BR; 1 orange, 2 yellow, 3 core) ---
flametile:
  DB $00,$00,$00,$00,$00,$00,$00,$11,$00,$00,$01,$11,$00,$01,$11,$11
  DB $00,$01,$11,$22,$00,$11,$12,$22,$01,$11,$22,$23,$01,$11,$22,$33
  DB $00,$00,$00,$00,$11,$00,$00,$00,$11,$10,$00,$00,$11,$11,$10,$00
  DB $22,$11,$10,$00,$22,$21,$11,$00,$32,$22,$11,$10,$33,$22,$11,$10
  DB $01,$11,$22,$33,$01,$11,$22,$23,$00,$11,$12,$22,$00,$01,$11,$22
  DB $00,$01,$11,$11,$00,$00,$01,$11,$00,$00,$00,$11,$00,$00,$00,$00
  DB $33,$22,$11,$10,$32,$22,$11,$10,$22,$21,$11,$00,$22,$11,$10,$00
  DB $11,$11,$10,$00,$11,$10,$00,$00,$11,$00,$00,$00,$00,$00,$00,$00
; --- 16x16 4bpp score digits, tiles 132..171 (4 tiles/digit: TL,TR,BL,BR) ---
bigdigit:
  DB $00,$00,$00,$00,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$00,$00,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00
  DB $00,$00,$00,$00,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00,$11
  DB $00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00,$00,$00,$11
  DB $00,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00
  DB $11,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00
  DB $00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00,$11
  DB $00,$00,$00,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11
  DB $11,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00
  DB $11,$00,$00,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00
  DB $00,$00,$00,$00,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11
  DB $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$11,$11,$11
  DB $00,$00,$00,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$11,$11,$11,$00
  DB $00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11
  DB $11,$11,$11,$00,$11,$11,$11,$00,$00,$00,$00,$00,$00,$00,$00,$00
  DB $00,$00,$00,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00
  DB $00,$00,$00,$00,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11
  DB $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$11,$11,$11
  DB $00,$00,$00,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$11,$11,$11,$00
  DB $00,$11,$11,$11,$00,$11,$11,$11,$00,$00,$00,$00,$00,$00,$00,$00
  DB $00,$00,$00,$00,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11
  DB $11,$11,$11,$00,$11,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00
  DB $00,$00,$00,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$11
  DB $00,$00,$00,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$11,$11,$11,$00
  DB $00,$11,$11,$11,$00,$11,$11,$11,$00,$00,$00,$00,$00,$00,$00,$00
  DB $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  DB $11,$11,$11,$00,$11,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$00,$00,$00,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$11
  DB $00,$00,$00,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00
  DB $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$11,$11,$11,$00
  DB $00,$11,$11,$11,$00,$11,$11,$11,$00,$00,$00,$00,$00,$00,$00,$00
  DB $00,$00,$00,$00,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11
  DB $11,$11,$11,$00,$11,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00
  DB $00,$00,$00,$00,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$11
  DB $00,$00,$00,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00
  DB $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$11,$11,$11,$00
  DB $00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11
  DB $11,$11,$11,$00,$11,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00
  DB $00,$00,$00,$00,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11
  DB $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$11
  DB $00,$00,$00,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$11,$00,$00,$00
  DB $00,$00,$00,$11,$00,$00,$00,$11,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $11,$00,$00,$00,$11,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  DB $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  DB $00,$00,$00,$00,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$11
  DB $00,$00,$00,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$11,$11,$11,$00
  DB $00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11
  DB $11,$11,$11,$00,$11,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00
  DB $00,$00,$00,$00,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$11
  DB $00,$00,$00,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$11,$11,$11,$00
  DB $00,$11,$11,$11,$00,$11,$11,$11,$00,$00,$00,$00,$00,$00,$00,$00
  DB $00,$00,$00,$00,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11
  DB $11,$11,$11,$00,$11,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00

; --- 16x16 4bpp letters A-Z, tiles 28..131 (4 tiles/letter: TL,TR,BL,BR) ---
letter16:
  DB $00,$00,$00,$00,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00,$11
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$11
  DB $00,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$11,$11,$11,$00
  DB $00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $11,$11,$11,$00,$11,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$00,$00,$00,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$11
  DB $00,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$11,$00,$00,$00
  DB $00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11
  DB $11,$00,$00,$00,$11,$00,$00,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$11,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00
  DB $00,$00,$00,$00,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00,$11
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$00,$00,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00
  DB $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00,$11
  DB $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  DB $00,$00,$00,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00
  DB $00,$00,$00,$00,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$11,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00
  DB $00,$00,$00,$00,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$11
  DB $00,$00,$00,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00
  DB $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$11,$00,$00,$00
  DB $00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11
  DB $11,$00,$00,$00,$11,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  DB $00,$00,$00,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00
  DB $00,$00,$00,$00,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$11
  DB $00,$00,$00,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00
  DB $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$11,$00,$00,$00
  DB $00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $11,$00,$00,$00,$11,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  DB $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  DB $00,$00,$00,$00,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00,$11
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$00,$00,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00
  DB $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00,$11
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00
  DB $00,$00,$00,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$11
  DB $00,$00,$00,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$11,$11,$11,$00
  DB $00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $11,$11,$11,$00,$11,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$00,$00,$00,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11
  DB $00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00,$11
  DB $00,$00,$00,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00
  DB $11,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00
  DB $00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00,$11
  DB $00,$00,$00,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11
  DB $11,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00
  DB $11,$00,$00,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00
  DB $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  DB $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  DB $00,$00,$00,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$00,$00,$00,$00,$00,$00,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00,$11
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$11,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00
  DB $00,$00,$00,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$00
  DB $00,$00,$00,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $11,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00,$00,$00,$00,$00
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$11,$00,$11,$11,$11
  DB $00,$11,$11,$11,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$00,$00,$00,$00,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00
  DB $11,$00,$00,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$00,$00,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  DB $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11
  DB $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  DB $00,$00,$00,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00
  DB $00,$00,$00,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11
  DB $00,$00,$00,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00
  DB $00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $11,$11,$11,$00,$11,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$00,$00,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11
  DB $00,$00,$00,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00
  DB $00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11
  DB $00,$11,$11,$11,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00
  DB $11,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$00,$00,$00,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00,$11
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00,$11
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$11,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00
  DB $00,$00,$00,$00,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$11
  DB $00,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$11,$00,$00,$00
  DB $00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $11,$00,$00,$00,$11,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  DB $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  DB $00,$00,$00,$00,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00,$11
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$11,$00,$11,$11,$11
  DB $00,$11,$11,$11,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00,$11
  DB $00,$11,$11,$00,$00,$11,$11,$00,$11,$00,$00,$00,$11,$00,$00,$00
  DB $11,$00,$00,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00
  DB $00,$00,$00,$00,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$11
  DB $00,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$11,$00,$00,$00
  DB $00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $11,$00,$00,$00,$11,$00,$00,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$00,$00,$00,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00,$11
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$00,$00,$11
  DB $00,$00,$00,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00
  DB $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$11,$00,$00,$00
  DB $00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00,$00,$00,$00,$00,$00
  DB $00,$00,$00,$00,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11
  DB $11,$00,$00,$00,$11,$00,$00,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$11,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00
  DB $00,$00,$00,$00,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11
  DB $00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00,$11
  DB $00,$00,$00,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00
  DB $11,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00
  DB $00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00,$11
  DB $00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00,$11
  DB $11,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00
  DB $11,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00
  DB $00,$00,$00,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$00,$00,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00
  DB $00,$00,$00,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$00,$00,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00,$11
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$11,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00
  DB $00,$00,$00,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$11
  DB $00,$00,$00,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$11,$11,$11,$00
  DB $00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11
  DB $00,$11,$11,$11,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00
  DB $11,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$00,$00,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$00,$00,$11
  DB $00,$00,$00,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$11,$00,$00,$00
  DB $00,$00,$00,$11,$00,$00,$00,$11,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $11,$00,$00,$00,$11,$00,$00,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$00,$00,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00,$11
  DB $00,$00,$00,$00,$00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00
  DB $11,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00
  DB $00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00,$11
  DB $00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00,$11
  DB $11,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00
  DB $11,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00,$11,$00,$00,$00
  DB $00,$00,$00,$00,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11
  DB $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$11
  DB $00,$00,$00,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00
  DB $00,$11,$11,$00,$00,$11,$11,$00,$00,$11,$11,$00,$11,$00,$00,$00
  DB $00,$00,$00,$11,$00,$00,$00,$11,$00,$11,$11,$00,$00,$11,$11,$00
  DB $00,$11,$11,$00,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11
  DB $11,$00,$00,$00,$11,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  DB $00,$00,$00,$00,$11,$11,$11,$00,$11,$11,$11,$00,$11,$11,$11,$00
