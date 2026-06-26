; ============================================================================
; STREET BRAWL — a Streets-of-Rage-style beat-'em-up prototype for CastlePalm
;
;   Walk your hero around a sidewalk (8-way, D-pad), throw punches (A), and clear
;   the street of thugs. Enemies chase you, stagger and flash white when hit, and
;   get knocked back; touch one and you lose a chunk of the health bar up top.
;   Clear all six and YOU WIN; run out of health and it's GAME OVER.
;
;   Controls:  D-pad = move    A = punch    Start = begin / restart
;
;   Art lives in assets.bin (built by gen_assets.js) and is INCBIN'd at the end,
;   then copied to VRAM at boot. Build it first:
;       node examples/streetbrawl/gen_assets.js
;       node tools/build-cart.js examples/streetbrawl/streetbrawl.asm streetbrawl.cpc BRAWL
;       node tools/run.js examples/streetbrawl/streetbrawl.asm 90 shot.png --start
; ============================================================================

; ---- MMIO ----
INPUT0     EQU $100000
VRAM_ADDR  EQU $101000
VRAM_DATA  EQU $101004
PAL_INDEX  EQU $101008
PAL_DATA   EQU $10100A
OAM_INDEX  EQU $10100C
OAM_DATA   EQU $10100E
PPU_CTRL   EQU $101018
SQ0_PERIOD EQU $102000
SQ0_VOL    EQU $102002
SQ0_CTRL   EQU $102003

; ---- input bits ----
UP    EQU 1
DOWN  EQU 2
LEFT  EQU 4
RIGHT EQU 8
ABTN  EQU 16
START EQU 256

; ---- tile sheet indices (must match gen_assets.js) ----
BLANK    EQU 0
BRICK    EQU 1
SIDEWALK EQU 2
ROAD     EQU 3
CURB     EQU 4
HP_FULL  EQU 5
HP_EMPTY EQU 6
PL_WALKA EQU 16
PL_WALKB EQU 20
PL_PUNCH EQU 24
EN_WALKA EQU 32
EN_WALKB EQU 36
FONT     EQU 64

; ---- tuning ----
NENEM    EQU 6
ENHP     EQU 3
SPEED    EQU 2          ; player px / frame
ESPD     EQU 1          ; enemy px / frame (slower, so you can juke them)
PUNCHT   EQU 14         ; punch animation length (frames)
PUNCHHIT EQU 9          ; the single frame the fist is "live"
KB       EQU 3          ; enemy knockback px / frame while staggered
HITSTUN  EQU 18         ; enemy stagger frames after a hit
INVULN   EQU 30         ; player i-frames after taking a hit
HITNEAR  EQU 13         ; enemy-vs-player contact distance
HP0      EQU 16         ; starting health (= HP bar cells)
BANDTOP  EQU 96         ; player/enemy vertical play band (py range)
BANDBOT  EQU 190
XMIN     EQU 4
XMAX     EQU 300

; ---- RAM ----
state    EQU $000100    ; 0 title, 1 play, 2 win, 3 over
in_now   EQU $000104
in_prev  EQU $000106
sfxT     EQU $000108
kills    EQU $00010A
p_x      EQU $000110
p_y      EQU $000112
p_face   EQU $000114    ; 0 right, 1 left
p_hp     EQU $000116
p_punch  EQU $000118
p_hurt   EQU $00011A    ; i-frame / blink countdown
p_anim   EQU $00011C
hbx0     EQU $000130    ; punch hitbox (computed each swing)
hbx1     EQU $000132
hby0     EQU $000134
hby1     EQU $000136
ENEMY    EQU $000200    ; NENEM slots x 8 bytes
;   +0 alive  +1 hp  +2 hurt(stagger)  +3 faceRight  +4 px(u16)  +6 py(u16)

; ---- text codes (print maps 0..25 -> letters, 26 -> space, $FF -> end) ----
A EQU 0
B EQU 1
C EQU 2
D EQU 3
E EQU 4
F EQU 5
G EQU 6
H EQU 7
I EQU 8
J EQU 9
K EQU 10
L EQU 11
M EQU 12
N EQU 13
O EQU 14
P EQU 15
Q EQU 16
R EQU 17
S EQU 18
T EQU 19
U EQU 20
V EQU 21
W EQU 22
X EQU 23
Y EQU 24
Z EQU 25
SPC EQU 26
END EQU $FF

  ORG $300000
  DA start
  DA 0
  DA 0
  DA 0

; ============================ boot ============================
start:
  CALL setpal
  CALL copysheet
  MOV R0, #1
  STW R0, [PPU_CTRL]        ; enable BG0
  MOV R0, #0
  STW R0, [in_now]
  STW R0, [in_prev]
  STW R0, [sfxT]
  CALL drawtitle
  MOV R0, #0
  STW R0, [state]

mainloop:
  CALL readpad
  LDW R0, [state]
  CMP R0, #1
  BNE ml_menu
  CALL playframe
  BRA ml_wait
ml_menu:
  CALL menuframe
ml_wait:
  CALL sfxtick
  WAIT
  BRA mainloop

; ---- sample controller, remembering last frame for edge detection ----
readpad:
  LDW R0, [in_now]
  STW R0, [in_prev]
  LDW R0, [INPUT0]
  STW R0, [in_now]
  RET

; ---- title / win / over: Start (edge) begins or restarts ----
menuframe:
  LDW R0, [in_now]
  MOV R1, R0
  AND R1, #START
  BEQ mf_done
  LDW R2, [in_prev]
  AND R2, #START
  BNE mf_done              ; held since last frame -> not an edge
  LDW R0, [state]
  CMP R0, #0
  BNE mf_back
  CALL newgame             ; from title -> start playing
  RET
mf_back:
  CALL drawtitle           ; from win/over -> back to title
  MOV R0, #0
  STW R0, [state]
mf_done:
  RET

; ============================ one play frame ============================
playframe:
  CALL domove
  CALL punchupdate
  CALL doenemies
  LDW R0, [p_hurt]         ; tick i-frames
  CMP R0, #0
  BEQ pf_nh
  SUB R0, #1
  STW R0, [p_hurt]
pf_nh:
  CALL drawhp
  CALL buildoam
  LDW R0, [p_hp]           ; dead?
  CMP R0, #0
  BNE pf_ckwin
  MOV R0, #3
  STW R0, [state]
  CALL clearoam
  CALL drawover
  RET
pf_ckwin:
  LDW R0, [kills]          ; street cleared?
  CMP R0, #NENEM
  BLT pf_done
  MOV R0, #2
  STW R0, [state]
  CALL clearoam
  CALL drawwin
pf_done:
  RET

; ============================ player movement ============================
domove:
  MOV R4, #0               ; "moved" flag
  LDW R6, [in_now]
  LDW R0, [p_x]
  LDW R1, [p_y]
  MOV R2, R6
  AND R2, #LEFT
  BEQ dm_r
  SUB R0, #SPEED
  MOV R4, #1
  MOV R3, #1
  STW R3, [p_face]
dm_r:
  MOV R2, R6
  AND R2, #RIGHT
  BEQ dm_u
  ADD R0, #SPEED
  MOV R4, #1
  MOV R3, #0
  STW R3, [p_face]
dm_u:
  MOV R2, R6
  AND R2, #UP
  BEQ dm_d
  SUB R1, #SPEED
  MOV R4, #1
dm_d:
  MOV R2, R6
  AND R2, #DOWN
  BEQ dm_clx
  ADD R1, #SPEED
  MOV R4, #1
dm_clx:
  CMP R0, #XMIN
  BGE dm_clx2
  MOV R0, #XMIN
dm_clx2:
  CMP R0, #XMAX
  BLE dm_cly
  MOV R0, #XMAX
dm_cly:
  CMP R1, #BANDTOP
  BGE dm_cly2
  MOV R1, #BANDTOP
dm_cly2:
  CMP R1, #BANDBOT
  BLE dm_store
  MOV R1, #BANDBOT
dm_store:
  STW R0, [p_x]
  STW R1, [p_y]
  CMP R4, #0               ; advance walk cycle only while moving
  BEQ dm_done
  LDW R0, [p_anim]
  ADD R0, #1
  STW R0, [p_anim]
dm_done:
  RET

; ============================ punching ============================
punchupdate:
  LDW R0, [in_now]
  MOV R1, R0
  AND R1, #ABTN
  BEQ pu_tick
  LDW R2, [in_prev]
  AND R2, #ABTN
  BNE pu_tick             ; A held since last frame -> not an edge
  LDW R0, [p_punch]
  CMP R0, #0
  BNE pu_tick             ; already mid-swing
  MOV R0, #PUNCHT
  STW R0, [p_punch]
  MOV R0, #180
  CALL sfxblip
pu_tick:
  LDW R0, [p_punch]
  CMP R0, #0
  BEQ pu_done
  SUB R0, #1
  STW R0, [p_punch]
  CMP R0, #PUNCHHIT        ; fist is live for exactly one frame
  BNE pu_done
  CALL checkhit
pu_done:
  RET

; ---- build the fist hitbox in front of the player, damage any thug inside ----
checkhit:
  LDW R0, [p_x]
  LDW R1, [p_face]
  AND R1, #1
  BEQ ch_right
  MOV R4, R0              ; facing left: box covers body + reach to the left
  SUB R4, #14
  MOV R5, R0
  ADD R5, #20
  BRA ch_y
ch_right:
  MOV R4, R0             ; facing right: box covers body + reach to the right
  SUB R4, #4
  MOV R5, R0
  ADD R5, #30
ch_y:
  STW R4, [hbx0]
  STW R5, [hbx1]
  LDW R0, [p_y]
  MOV R4, R0
  SUB R4, #8
  STW R4, [hby0]
  ADD R0, #24
  STW R0, [hby1]
  MOV R7, #0             ; enemy index
ch_lp:
  MOV R3, R7
  SHL R3, #3
  LDA A1, #ENEMY
  ADD A1, R3
  LDB R0, [A1+#0]
  CMP R0, #0
  BEQ ch_next
  LDB R0, [A1+#2]        ; already staggered -> don't double-hit
  CMP R0, #0
  BNE ch_next
  LDW R0, [A1+#4]        ; enemy centre x = ex+8
  ADD R0, #8
  LDW R1, [hbx0]
  CMP R0, R1
  BLT ch_next
  LDW R1, [hbx1]
  CMP R0, R1
  BGT ch_next
  LDW R0, [A1+#6]        ; enemy centre y = ey+8
  ADD R0, #8
  LDW R1, [hby0]
  CMP R0, R1
  BLT ch_next
  LDW R1, [hby1]
  CMP R0, R1
  BGT ch_next
  PUSH R7
  CALL enemyhit
  POP R7
ch_next:
  ADD R7, #1
  CMP R7, #NENEM
  BLT ch_lp
  RET

; ---- enemyhit(A1=slot): -1 hp, stagger, die if drained ----
enemyhit:
  LDB R0, [A1+#1]
  SUB R0, #1
  STB R0, [A1+#1]
  MOV R1, #HITSTUN
  STB R1, [A1+#2]
  PUSH R0
  MOV R0, #120
  CALL sfxblip
  POP R0
  CMP R0, #0
  BNE eh_done
  MOV R1, #0
  STB R1, [A1+#0]         ; dead
  LDW R1, [kills]
  ADD R1, #1
  STW R1, [kills]
  MOV R0, #90
  CALL sfxblip
eh_done:
  RET

; ============================ enemies ============================
doenemies:
  MOV R7, #0
de_lp:
  MOV R3, R7
  SHL R3, #3
  LDA A1, #ENEMY
  ADD A1, R3
  PUSH R7
  CALL eai
  POP R7
  ADD R7, #1
  CMP R7, #NENEM
  BLT de_lp
  RET

; ---- eai(A1=slot): stagger-knockback if hit, else chase + maybe hurt player ----
eai:
  LDB R0, [A1+#0]
  CMP R0, #0
  BNE ea_live
  RET
ea_live:
  LDB R0, [A1+#2]         ; staggered?
  CMP R0, #0
  BEQ ea_chase
  SUB R0, #1
  STB R0, [A1+#2]
  LDW R4, [A1+#4]         ; knock away from player in x
  LDW R6, [p_x]
  CMP R4, R6
  BLT ea_kbl
  ADD R4, #KB
  BRA ea_kbc
ea_kbl:
  SUB R4, #KB
ea_kbc:
  CMP R4, #XMIN
  BGE ea_kbx2
  MOV R4, #XMIN
ea_kbx2:
  CMP R4, #XMAX
  BLE ea_kbs
  MOV R4, #XMAX
ea_kbs:
  STW R4, [A1+#4]
  RET
ea_chase:
  LDW R4, [A1+#4]         ; ex
  LDW R5, [A1+#6]         ; ey
  LDW R6, [p_x]
  CMP R4, R6
  BEQ ea_cy
  BLT ea_cxr
  SUB R4, #ESPD
  MOV R0, #0
  STB R0, [A1+#3]         ; faces left
  BRA ea_cy
ea_cxr:
  ADD R4, #ESPD
  MOV R0, #1
  STB R0, [A1+#3]         ; faces right
ea_cy:
  LDW R6, [p_y]
  CMP R5, R6
  BEQ ea_cstore
  BLT ea_cyd
  SUB R5, #ESPD
  BRA ea_cstore
ea_cyd:
  ADD R5, #ESPD
ea_cstore:
  STW R4, [A1+#4]
  STW R5, [A1+#6]
  ; contact with player? (centres within HITNEAR on both axes)
  LDW R6, [p_x]
  MOV R0, R4
  SUB R0, R6
  CALL absr0
  CMP R0, #HITNEAR
  BGE ea_done
  LDW R6, [p_y]
  MOV R0, R5
  SUB R0, R6
  CALL absr0
  CMP R0, #HITNEAR
  BGE ea_done
  LDW R0, [p_hurt]        ; only if not in i-frames
  CMP R0, #0
  BNE ea_done
  CALL hurtplayer        ; R4 = enemy x (knock direction)
ea_done:
  RET

; ---- hurtplayer(R4=enemy x): -1 health, i-frames, shove player away ----
hurtplayer:
  LDW R0, [p_hp]
  CMP R0, #0
  BEQ hu_if
  SUB R0, #1
  STW R0, [p_hp]
hu_if:
  MOV R0, #INVULN
  STW R0, [p_hurt]
  LDW R0, [p_x]
  CMP R0, R4
  BLT hu_left
  ADD R0, #6
  BRA hu_clx
hu_left:
  SUB R0, #6
hu_clx:
  CMP R0, #XMIN
  BGE hu_clx2
  MOV R0, #XMIN
hu_clx2:
  CMP R0, #XMAX
  BLE hu_store
  MOV R0, #XMAX
hu_store:
  STW R0, [p_x]
  MOV R0, #260
  CALL sfxblip
  RET

; ---- absr0: R0 = |R0| (signed 16) ----
absr0:
  CMP R0, #0
  BGE abr_d
  NEG R0
abr_d:
  RET

; ============================ OAM (sprites) ============================
buildoam:
  MOV R0, #0
  STW R0, [OAM_INDEX]
  CALL emitplayer
  MOV R7, #0
bo_e:
  MOV R3, R7
  SHL R3, #3
  LDA A1, #ENEMY
  ADD A1, R3
  CALL emitenemy
  ADD R7, #1
  CMP R7, #NENEM
  BLT bo_e
  RET

emitplayer:
  LDW R0, [p_hurt]         ; blink during i-frames
  CMP R0, #0
  BEQ ep_draw
  MOV R1, R0
  AND R1, #2
  BEQ ep_draw
  CALL emitoff
  RET
ep_draw:
  LDW R5, [p_punch]
  CMP R5, #0
  BEQ ep_walk
  MOV R5, #PL_PUNCH
  BRA ep_attr
ep_walk:
  LDW R0, [p_anim]
  SHR R0, #3
  AND R0, #1
  BEQ ep_fa
  MOV R5, #PL_WALKB
  BRA ep_attr
ep_fa:
  MOV R5, #PL_WALKA
ep_attr:
  MOV R6, #$11            ; size16 | palette bank 1
  LDW R0, [p_face]
  AND R0, #1
  BEQ ep_emit
  ADD R6, #$40           ; hflip (face left)
ep_emit:
  LDW R0, [p_x]
  LDW R1, [p_y]
  CALL emittile
  RET

emitenemy:
  LDB R0, [A1+#0]
  CMP R0, #0
  BNE ee_on
  CALL emitoff
  RET
ee_on:
  LDW R0, [A1+#4]         ; ex
  LDW R1, [A1+#6]         ; ey
  MOV R5, #EN_WALKA       ; simple two-frame shuffle keyed to x
  MOV R2, R0
  SHR R2, #2
  AND R2, #1
  BEQ ee_tile
  MOV R5, #EN_WALKB
ee_tile:
  MOV R6, #$12           ; size16 | palette bank 2
  LDB R2, [A1+#2]        ; staggered -> flash palette bank 4
  CMP R2, #0
  BEQ ee_face
  MOV R6, #$14
ee_face:
  LDB R2, [A1+#3]        ; faceRight -> hflip (art faces left)
  CMP R2, #0
  BEQ ee_emit
  ADD R6, #$40
ee_emit:
  CALL emittile
  RET

; ---- emittile(R0=px, R1=py, R5=tile, R6=attrLo): one enabled 16x16 descriptor ----
emittile:
  STB R0, [OAM_DATA]
  MOV R2, R0
  SHR R2, #8
  STB R2, [OAM_DATA]
  STB R1, [OAM_DATA]
  MOV R2, R1
  SHR R2, #8
  STB R2, [OAM_DATA]
  STB R5, [OAM_DATA]      ; tile lo
  MOV R2, #0
  STB R2, [OAM_DATA]      ; tile hi
  STB R6, [OAM_DATA]      ; attr lo
  MOV R2, #$80
  STB R2, [OAM_DATA]      ; attr hi: enable
  RET

emitoff:
  MOV R2, #0
  STB R2, [OAM_DATA]
  STB R2, [OAM_DATA]
  STB R2, [OAM_DATA]
  STB R2, [OAM_DATA]
  STB R2, [OAM_DATA]
  STB R2, [OAM_DATA]
  STB R2, [OAM_DATA]
  STB R2, [OAM_DATA]      ; attr hi 0 -> disabled
  RET

; ============================ HUD / background ============================
; ---- HP bar across the top: green cell per remaining point, grey otherwise ----
drawhp:
  MOV R4, #0
hb_lp:
  LDW R0, [p_hp]
  CMP R4, R0
  BLT hb_full
  MOV R2, #HP_EMPTY
  BRA hb_set
hb_full:
  MOV R2, #HP_FULL
hb_set:
  MOV R0, R4
  MOV R1, #0
  MOV R3, #0
  CALL settile
  ADD R4, #1
  CMP R4, #HP0
  BLT hb_lp
  RET

; ---- buildstreet: brick wall up top, a curb line, then sidewalk ----
buildstreet:
  MOV R5, #2
bs_y:
  MOV R4, #0
bs_x:
  MOV R0, R4
  MOV R1, R5
  MOV R2, #SIDEWALK
  CMP R5, #8
  BGT bs_set
  BEQ bs_curb
  MOV R2, #BRICK
  BRA bs_set
bs_curb:
  MOV R2, #CURB
bs_set:
  MOV R3, #0
  CALL settile
  ADD R4, #1
  CMP R4, #40
  BLT bs_x
  ADD R5, #1
  CMP R5, #28
  BLT bs_y
  RET

; ---- settile(R0=tileX, R1=tileY, R2=tile, R3=palette): write one BG0 map cell ----
settile:
  MOV R6, R1
  SHL R6, #8              ; tileY*256
  MOV R7, R0
  SHL R7, #2             ; tileX*4
  ADD R6, R7             ; byte offset within the map (map base $10000)
  STB R6, [VRAM_ADDR]
  MOV R7, R6
  SHR R7, #8
  STB R7, [VRAM_ADDR+1]
  MOV R7, #1
  STB R7, [VRAM_ADDR+2]   ; hi byte: VRAM $10000 + offset
  STB R2, [VRAM_DATA]     ; cell byte0: tile lo
  MOV R7, R2
  SHR R7, #8
  AND R7, #7             ; tile hi 3 bits
  MOV R6, R3
  SHL R6, #3             ; palette in bits 3..6 of byte1
  OR R7, R6
  STB R7, [VRAM_DATA]
  MOV R7, #0
  STB R7, [VRAM_DATA]     ; byte2 (vflip/priority) = 0
  STB R7, [VRAM_DATA]     ; byte3 = 0
  RET

; ---- clearmap: blank the visible map to tile 0 ----
clearmap:
  MOV R5, #0
cm_y:
  MOV R4, #0
cm_x:
  MOV R0, R4
  MOV R1, R5
  MOV R2, #0
  MOV R3, #0
  CALL settile
  ADD R4, #1
  CMP R4, #40
  BLT cm_x
  ADD R5, #1
  CMP R5, #28
  BLT cm_y
  RET

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

; ---- print(R4=tileX, R5=tileY, A1=string): draw text in the font palette ----
print:
pr_lp:
  LDB R2, [A1]
  CMP R2, #$FF
  BEQ pr_done
  CMP R2, #26
  BEQ pr_adv             ; space
  ADD R2, #FONT
  MOV R0, R4
  MOV R1, R5
  MOV R3, #3
  CALL settile
pr_adv:
  ADD R4, #1
  INC A1
  BRA pr_lp
pr_done:
  RET

; ============================ screens ============================
drawtitle:
  CALL clearmap
  LDA A1, #sTITLE1
  MOV R4, #17
  MOV R5, #9
  CALL print
  LDA A1, #sTITLE2
  MOV R4, #17
  MOV R5, #12
  CALL print
  LDA A1, #sSTART
  MOV R4, #15
  MOV R5, #18
  CALL print
  RET

drawwin:
  CALL clearmap
  LDA A1, #sWIN
  MOV R4, #16
  MOV R5, #12
  CALL print
  LDA A1, #sSTART
  MOV R4, #15
  MOV R5, #16
  CALL print
  RET

drawover:
  CALL clearmap
  LDA A1, #sOVER
  MOV R4, #15
  MOV R5, #12
  CALL print
  LDA A1, #sSTART
  MOV R4, #15
  MOV R5, #16
  CALL print
  RET

; ============================ new game ============================
newgame:
  CALL clearmap
  CALL buildstreet
  MOV R0, #152
  STW R0, [p_x]
  MOV R0, #150
  STW R0, [p_y]
  MOV R0, #0
  STW R0, [p_face]
  STW R0, [p_punch]
  STW R0, [p_hurt]
  STW R0, [p_anim]
  STW R0, [kills]
  MOV R0, #HP0
  STW R0, [p_hp]
  LDA A0, #espawn
  MOV R7, #0
ng_e:
  MOV R3, R7
  SHL R3, #3
  LDA A1, #ENEMY
  ADD A1, R3
  MOV R0, #1
  STB R0, [A1+#0]
  MOV R0, #ENHP
  STB R0, [A1+#1]
  MOV R0, #0
  STB R0, [A1+#2]
  STB R0, [A1+#3]
  LDW R0, [A0]
  STW R0, [A1+#4]
  LDW R0, [A0+#2]
  STW R0, [A1+#6]
  ADD A0, #4
  ADD R7, #1
  CMP R7, #NENEM
  BLT ng_e
  MOV R0, #1
  STW R0, [state]
  RET

; ============================ audio ============================
sfxblip:
  STW R0, [SQ0_PERIOD]
  MOV R0, #10
  STB R0, [SQ0_VOL]
  MOV R0, #1
  STB R0, [SQ0_CTRL]
  MOV R0, #6
  STW R0, [sfxT]
  RET

sfxtick:
  LDW R0, [sfxT]
  CMP R0, #0
  BEQ sx_done
  SUB R0, #1
  STW R0, [sfxT]
  CMP R0, #0
  BNE sx_done
  MOV R0, #0
  STB R0, [SQ0_CTRL]
sx_done:
  RET

; ============================ palettes ============================
setpal:
  MOV R0, #0             ; bank 0: background
  STB R0, [PAL_INDEX]
  MOV R0, #$0000
  STW R0, [PAL_DATA]     ; 0 black
  MOV R0, #$10D6
  STW R0, [PAL_DATA]     ; 1 brick dark
  MOV R0, #$215B
  STW R0, [PAL_DATA]     ; 2 brick light
  MOV R0, #$5294
  STW R0, [PAL_DATA]     ; 3 sidewalk
  MOV R0, #$1CE7
  STW R0, [PAL_DATA]     ; 4 road
  MOV R0, #$131C
  STW R0, [PAL_DATA]     ; 5 curb
  MOV R0, #$1B84
  STW R0, [PAL_DATA]     ; 6 hp green
  MOV R0, #$2529
  STW R0, [PAL_DATA]     ; 7 hp empty
  MOV R0, #$318C
  STW R0, [PAL_DATA]     ; 8 mortar
  MOV R0, #16            ; bank 1: player
  STB R0, [PAL_INDEX]
  MOV R0, #$0000
  STW R0, [PAL_DATA]
  MOV R0, #$42DF
  STW R0, [PAL_DATA]     ; 1 skin
  MOV R0, #$7104
  STW R0, [PAL_DATA]     ; 2 shirt
  MOV R0, #$3862
  STW R0, [PAL_DATA]     ; 3 pants
  MOV R0, #$0842
  STW R0, [PAL_DATA]     ; 4 outline
  MOV R0, #$7FFF
  STW R0, [PAL_DATA]     ; 5 white
  MOV R0, #32            ; bank 2: enemy
  STB R0, [PAL_INDEX]
  MOV R0, #$0000
  STW R0, [PAL_DATA]
  MOV R0, #$109E
  STW R0, [PAL_DATA]     ; 1 red
  MOV R0, #$084E
  STW R0, [PAL_DATA]     ; 2 dark red
  MOV R0, #$3A5C
  STW R0, [PAL_DATA]     ; 3 skin
  MOV R0, #$7FFF
  STW R0, [PAL_DATA]     ; 4 white
  MOV R0, #48            ; bank 3: font
  STB R0, [PAL_INDEX]
  MOV R0, #$0000
  STW R0, [PAL_DATA]
  MOV R0, #$7FFF
  STW R0, [PAL_DATA]     ; 1 white
  MOV R0, #64            ; bank 4: enemy hit-flash (all white)
  STB R0, [PAL_INDEX]
  MOV R0, #$0000
  STW R0, [PAL_DATA]
  MOV R0, #$7FFF
  STW R0, [PAL_DATA]
  MOV R0, #$7FFF
  STW R0, [PAL_DATA]
  MOV R0, #$7FFF
  STW R0, [PAL_DATA]
  MOV R0, #$7FFF
  STW R0, [PAL_DATA]
  RET

; ---- copy the whole tile sheet from ROM into VRAM tile region (offset 0) ----
copysheet:
  MOV R0, #0
  STB R0, [VRAM_ADDR]
  STB R0, [VRAM_ADDR+1]
  STB R0, [VRAM_ADDR+2]
  LDA A0, #sheet
  MOV R1, #sheetend-sheet
cs_lp:
  LDB R2, [A0]
  STB R2, [VRAM_DATA]
  INC A0
  SUB R1, #1
  BNE cs_lp
  RET

; ============================ data ============================
espawn:
  DW 40, 110
  DW 280, 120
  DW 70, 170
  DW 250, 160
  DW 150, 100
  DW 300, 180

sTITLE1:
  DB S, T, R, E, E, T, END
sTITLE2:
  DB B, R, A, W, L, END
sSTART:
  DB P, U, S, H, SPC, S, T, A, R, T, END
sWIN:
  DB Y, O, U, SPC, W, I, N, END
sOVER:
  DB G, A, M, E, SPC, O, V, E, R, END

sheet:
  INCBIN "assets.bin"
sheetend:
