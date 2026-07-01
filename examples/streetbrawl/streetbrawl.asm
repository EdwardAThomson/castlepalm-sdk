; ============================================================================
; STREET BRAWL — a Streets-of-Rage-style beat-'em-up prototype for CastlePalm
;
;   Walk your hero along a scrolling sidewalk (8-way, D-pad), throw punches (A),
;   and clear the street of thugs. Enemies chase you, stagger and flash white when
;   hit, and get knocked back; touch one and you lose a chunk of the health bar.
;   Three thug types mix in per wave (grunt / fast runner / tanky bruiser), driven
;   by the TYPE* stat tables + the wavedef spawn table. Clear a wave and the street
;   scrolls on; clear three waves and a boss to finish a stage, then an interstitial
;   leads into the next of three stages. Clear the last boss to WIN, or run out of
;   health for GAME OVER. Grab a lead pipe to hit harder and farther (limited
;   swings), and a drumstick to restore health.
;
;   Hits land with a brief hit-stop freeze and a camera shake for punch; a one-channel
;   chiptune riff loops on square-1 (SFX stay on square-0).
;
;   Controls:  D-pad = move    A = punch / swing    Start = begin / restart
;
;   Art lives in assets.bin (built by gen_assets.js) and is INCBIN'd at the end,
;   then copied to VRAM at boot. Build it first, then run the built .cpc (run.js
;   can't read INCBIN from a .asm, but build-cart.js can):
;       node examples/streetbrawl/gen_assets.js
;       node tools/build-cart.js examples/streetbrawl/streetbrawl.asm streetbrawl.cpc BRAWL
;       node tools/run.js streetbrawl.cpc 90 shot.png --start
; ============================================================================

; ---- MMIO ----
INPUT0     EQU $100000
VRAM_ADDR  EQU $101000
VRAM_DATA  EQU $101004
PAL_INDEX  EQU $101008
PAL_DATA   EQU $10100A
OAM_INDEX  EQU $10100C
OAM_DATA   EQU $10100E
BG0_SX     EQU $101010    ; BG0 horizontal scroll (signed 16-bit latch)
PPU_CTRL   EQU $101018
SQ0_PERIOD EQU $102000
SQ0_VOL    EQU $102002
SQ0_CTRL   EQU $102003
SQ1_PERIOD EQU $102004    ; square 1 — reserved for the music loop (SFX use SQ0)
SQ1_VOL    EQU $102006
SQ1_CTRL   EQU $102007

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
WPN_ICON EQU 8
BHP_FULL EQU 9          ; boss health-bar cell
PL_WALKA EQU 16
PL_WALKB EQU 20
PL_PUNCH EQU 24
EN_WALKA EQU 32
EN_WALKB EQU 36
WEAPON   EQU 40         ; pipe pickup / held weapon (16x16)
FOOD     EQU 44         ; food pickup (16x16)
BOSS     EQU 48         ; boss (16x16)
WEAPON_UP EQU 52        ; pipe raised mid-swing (16x16)
FONT     EQU 64
DIGIT    EQU 96         ; DIGIT + (0..9)

; ---- tuning ----
NENEM    EQU 8          ; enemy pool (on-screen slots); waves can fill up to this many
ENHP     EQU 3
SPEED    EQU 2          ; player px / frame
ESPD     EQU 1          ; enemy px / frame (slower, so you can juke them)
PUNCHT   EQU 12         ; bare-fist swing length (frames)
PUNCHHIT EQU 8          ; the single frame the fist/weapon is "live"
FISTDMG  EQU 1          ; damage per bare-fist hit
WPNDMG   EQU 3          ; damage per pipe hit (one-shots a thug)
WPNUSES  EQU 8          ; pipe swings before it breaks
WPNT     EQU 14         ; pipe swing length (long enough to read the wind-up)
WPNREACH EQU 14         ; extra hitbox reach while armed (px)
WPNCOL   EQU 32         ; HUD column where the weapon pips start
FOODHP   EQU 6          ; health restored by a food pickup
PICKR    EQU 14         ; pickup grab radius (centre distance)
KB       EQU 3          ; enemy knockback px / frame while staggered
HITSTUN  EQU 18         ; enemy stagger frames after a hit
INVULN   EQU 30         ; player i-frames after taking a hit
HITNEAR  EQU 13         ; enemy-vs-player contact distance
HP0      EQU 16         ; starting health (= HP bar cells)
BANDTOP  EQU 96         ; player/enemy vertical play band (py range)
BANDBOT  EQU 190
XMIN     EQU 4
PXMAX    EQU 300        ; player reach to the right of the current camera limit
EXMAX    EQU 1500       ; enemy world-x clamp (knockback)
; ---- progression: each level is NORMW thug waves + a boss; clear all NLEVELS to win ----
WAVEN    EQU 3          ; thugs on screen per normal wave (must be <= NENEM)
SEG      EQU 200        ; camera advance per wave (world px)
NLEVELS  EQU 3          ; number of stages
NORMW    EQU 3          ; normal waves per level before the boss (boss = wave NORMW)
BOSSHP   EQU 18         ; boss hit points
BOSSBAR  EQU 18         ; boss HP-bar cells (== BOSSHP, so no scaling math)
INTERT   EQU 150        ; interstitial duration (frames)
CLRPAUSE EQU 110        ; quiet beat after a boss falls, before the next screen
EHOLD0   EQU 80         ; freeze the first wave this long so it doesn't rush you
EHOLD    EQU 30         ; brief freeze on later wave spawns
; ---- enemy types: index into the TYPE* tables in the data section ----
NTYPES   EQU 3          ; 0 grunt, 1 runner, 2 bruiser
GRUNT    EQU 0
RUNNER   EQU 1
BRUISER  EQU 2
NONE     EQU $FF        ; empty slot in a wave descriptor
; ---- combat juice ----
SHAKEP   EQU 10         ; screen-shake frames when the player is hit
SHAKEW   EQU 6          ; screen-shake frames on a kill
SHAKEAMP EQU 3          ; shake amplitude (px)
HITSTOP  EQU 3          ; freeze frames on a pipe hit
HSKILL   EQU 4          ; freeze frames on a kill
; ---- music ----
NOTELEN  EQU 9          ; frames each note is held (tempo)

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
cam      EQU $000140    ; camera world-x (left screen edge)
cammax   EQU $000142    ; current right limit for the camera (grows per wave)
wave     EQU $000144    ; wave index within the current level (boss = NORMW)
p_weapon EQU $000146    ; pipe swings remaining (0 = bare fists)
p_wswing EQU $000148    ; current swing is a pipe swing (latched at swing start)
p_dmg    EQU $00014A    ; damage of the current swing (set in checkhit)
level    EQU $00014C    ; current stage index (0..NLEVELS-1)
bossactive EQU $00014E  ; 1 while a boss is on screen (slot 0 is the boss)
bossmaxhp EQU $000150   ; boss starting HP (for the bar)
interT   EQU $000152    ; interstitial countdown (state 4)
ehold    EQU $000154    ; frames the freshly-spawned wave stays frozen
clrpause EQU $000156    ; quiet beat after a boss dies, before the next screen
gtick    EQU $000158    ; free-running play-frame counter (drives half-speed bruisers)
shakeT   EQU $00015A    ; screen-shake countdown
hitstop  EQU $00015C    ; hit-freeze countdown (whole game pauses)
mIdx     EQU $00015E    ; music: current note index
mT       EQU $000160    ; music: frames left on the current note
eidx     EQU $000162    ; index of the enemy currently being processed (type lookups)
hbx0     EQU $000130    ; punch hitbox (computed each swing)
hbx1     EQU $000132
hby0     EQU $000134
hby1     EQU $000136
ENEMY    EQU $000200    ; NENEM slots x 8 bytes  ($0200..$023F for 8 slots)
;   +0 alive  +1 hp  +2 hurt(stagger)  +3 faceRight  +4 px(u16)  +6 py(u16)
ETYPE    EQU $000248    ; parallel array: 1 type byte per enemy slot (keeps the 8-byte stride)
NPICK    EQU 4          ; max pickups live at once
PICKUP   EQU $000260    ; NPICK slots x 8 bytes
;   +0 type (0 none, 1 pipe, 2 food)  +2 px(u16)  +4 py(u16)

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
  MOV R0, #3
  STW R0, [PPU_CTRL]        ; enable BG0 (scrolling street) + BG1 (fixed HUD overlay)
  MOV R0, #0
  STW R0, [in_now]
  STW R0, [in_prev]
  STW R0, [sfxT]
  STW R0, [gtick]
  STW R0, [shakeT]
  STW R0, [hitstop]
  STW R0, [mIdx]           ; start the music loop from the top
  STW R0, [mT]
  CALL drawtitle
  MOV R0, #0
  STW R0, [state]

mainloop:
  CALL readpad
  LDW R0, [state]
  CMP R0, #1
  BEQ ml_play
  CMP R0, #4
  BEQ ml_inter
  CALL menuframe
  BRA ml_wait
ml_play:
  CALL playframe
  BRA ml_wait
ml_inter:
  CALL interframe
ml_wait:
  CALL sfxtick
  CALL musictick
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
  LDW R0, [hitstop]        ; hit-freeze: hold the whole scene for a few frames
  CMP R0, #0
  BEQ pf_run
  SUB R0, #1
  STW R0, [hitstop]
  RET                      ; OAM persists, so the screen stays frozen on impact
pf_run:
  LDW R0, [gtick]          ; free-running tick (half-speed bruisers key off it)
  ADD R0, #1
  STW R0, [gtick]
  CALL domove
  CALL punchupdate
  CALL doenemies
  CALL dopickups
  LDW R0, [p_hurt]         ; tick i-frames
  CMP R0, #0
  BEQ pf_nh
  SUB R0, #1
  STW R0, [p_hurt]
pf_nh:
  CALL updatecam
  CALL drawhp
  CALL drawweapon
  LDW R0, [bossactive]
  CMP R0, #0
  BEQ pf_nbb
  CALL drawbosshp
pf_nbb:
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
  CALL countalive          ; current wave cleared?
  CMP R0, #0
  BNE pf_done
  LDW R0, [wave]           ; was it the boss wave?
  CMP R0, #NORMW
  BLT pf_adv               ; normal wave -> next wave, same level
  LDW R0, [clrpause]       ; boss cleared -> hold a quiet beat first
  CMP R0, #0
  BNE pf_pausetick
  MOV R0, #CLRPAUSE        ; first frame the boss is down: start the pause
  STW R0, [clrpause]
  RET
pf_pausetick:
  SUB R0, #1
  STW R0, [clrpause]
  CMP R0, #0
  BNE pf_done              ; still pausing on a quiet street
  LDW R0, [level]          ; pause over -> next stage or the win screen
  ADD R0, #1
  CMP R0, #NLEVELS
  BLT pf_inter             ; more stages -> interstitial
  MOV R0, #2               ; final boss down -> WIN
  STW R0, [state]
  CALL clearoam
  CALL drawwin
  RET
pf_inter:
  MOV R0, #4               ; into the interstitial state
  STW R0, [state]
  MOV R0, #INTERT
  STW R0, [interT]
  CALL clearoam
  CALL drawinter
  RET
pf_adv:
  CALL nextwave
pf_done:
  RET

; ---- interframe: hold the interstitial, then load the next stage ----
interframe:
  LDW R0, [interT]
  SUB R0, #1
  STW R0, [interT]
  CMP R0, #0
  BNE if_done
  LDW R0, [level]          ; advance to the next stage
  ADD R0, #1
  CALL loadlevel
  MOV R0, #1
  STW R0, [state]
if_done:
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
  CALL clampxp            ; clamp px to [XMIN, cammax+PXMAX]
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
  LDW R0, [p_weapon]      ; armed? -> pipe swing
  CMP R0, #0
  BEQ pu_fist
  SUB R0, #1
  STW R0, [p_weapon]      ; spend one swing
  MOV R0, #1
  STW R0, [p_wswing]
  MOV R0, #WPNT
  STW R0, [p_punch]
  MOV R0, #150            ; pipe whoosh (lower pitch)
  CALL sfxblip
  BRA pu_tick
pu_fist:
  MOV R0, #0
  STW R0, [p_wswing]
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

; ---- build the strike hitbox in front of the player, damage any thug inside ----
checkhit:
  LDW R0, [p_wswing]     ; pick damage + reach bonus for this swing
  CMP R0, #0
  BEQ ch_fist
  MOV R0, #WPNDMG
  STB R0, [p_dmg]
  MOV R2, #WPNREACH
  BRA ch_box
ch_fist:
  MOV R0, #FISTDMG
  STB R0, [p_dmg]
  MOV R2, #0
ch_box:
  LDW R0, [p_x]
  LDW R1, [p_face]
  AND R1, #1
  BEQ ch_right
  MOV R4, R0              ; facing left: box covers body + reach to the left
  SUB R4, #14
  SUB R4, R2             ; + weapon reach
  MOV R5, R0
  ADD R5, #20
  BRA ch_y
ch_right:
  MOV R4, R0             ; facing right: box covers body + reach to the right
  SUB R4, #4
  MOV R5, R0
  ADD R5, #30
  ADD R5, R2            ; + weapon reach
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

; ---- enemyhit(A1=slot): -p_dmg hp, stagger, die if drained ----
enemyhit:
  LDB R0, [A1+#1]
  LDB R1, [p_dmg]
  SUB R0, R1
  CMP R0, #0             ; clamp at 0 (pipe damage can exceed hp)
  BGE eh_set
  MOV R0, #0
eh_set:
  STB R0, [A1+#1]
  MOV R1, #HITSTUN
  STB R1, [A1+#2]
  LDW R1, [p_wswing]     ; pipe hits land with a brief freeze; fists don't
  CMP R1, #0
  BEQ eh_snd
  MOV R1, #HITSTOP
  STW R1, [hitstop]
eh_snd:
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
  MOV R1, #HSKILL        ; a kill freezes a touch longer and kicks the camera
  STW R1, [hitstop]
  MOV R1, #SHAKEW
  STW R1, [shakeT]
  MOV R0, #90
  CALL sfxblip
eh_done:
  RET

; ============================ enemies ============================
doenemies:
  LDW R0, [ehold]         ; tick the post-spawn grace timer
  CMP R0, #0
  BEQ de_go
  SUB R0, #1
  STW R0, [ehold]
de_go:
  MOV R7, #0
de_lp:
  MOV R3, R7
  SHL R3, #3
  LDA A1, #ENEMY
  ADD A1, R3
  STW R7, [eidx]           ; eai/curspd/curdmg look up ETYPE[eidx]
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
  LDW R0, [ehold]         ; freshly spawned -> hold still (grace period)
  CMP R0, #0
  BEQ ea_run
  RET
ea_run:
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
  CMP R4, #EXMAX
  BLE ea_kbs
  MOV R4, #EXMAX
ea_kbs:
  STW R4, [A1+#4]
  RET
ea_chase:
  LDW R4, [A1+#4]         ; ex
  LDW R5, [A1+#6]         ; ey
  CALL curspd            ; R0 = this enemy's speed (0 on a bruiser's rest frame)
  MOV R3, R0             ; hold speed in R3 across the move
  LDW R6, [p_x]
  CMP R4, R6
  BEQ ea_cy
  BLT ea_cxr
  SUB R4, R3
  MOV R0, #0
  STB R0, [A1+#3]         ; faces left
  BRA ea_cy
ea_cxr:
  ADD R4, R3
  MOV R0, #1
  STB R0, [A1+#3]         ; faces right
ea_cy:
  LDW R6, [p_y]
  CMP R5, R6
  BEQ ea_cstore
  BLT ea_cyd
  SUB R5, R3
  BRA ea_cstore
ea_cyd:
  ADD R5, R3
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
  CALL curdmg            ; R0 = this enemy type's contact damage
  MOV R2, R0
  CALL hurtplayer        ; R4 = enemy x (knock direction), R2 = damage
ea_done:
  RET

; ---- hurtplayer(R4=enemy x, R2=damage): lose health, i-frames, shake, shove away ----
hurtplayer:
  LDW R0, [p_hp]
  CMP R0, #0
  BEQ hu_if
  SUB R0, R2
  CMP R0, #0             ; clamp at 0 (a bruiser can deal 2)
  BGE hu_hp
  MOV R0, #0
hu_hp:
  STW R0, [p_hp]
hu_if:
  MOV R0, #INVULN
  STW R0, [p_hurt]
  MOV R0, #SHAKEP        ; jolt the screen
  STW R0, [shakeT]
  LDW R0, [p_x]
  CMP R0, R4
  BLT hu_left
  ADD R0, #6
  BRA hu_clx
hu_left:
  SUB R0, #6
hu_clx:
  CALL clampxp            ; clamp px to [XMIN, cammax+PXMAX]
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

; ---- curtype -> R0 = ETYPE[eidx]. Scratches A0; preserves R1-R7, A1. ----
curtype:
  LDW R0, [eidx]
  LDA A0, #ETYPE
  ADD A0, R0
  LDB R0, [A0]
  RET

; ---- curspd -> R0 = movement speed for the current enemy. Bruisers move every
;      other frame (half speed), keyed off gtick. Scratches R1,R2,A0. ----
curspd:
  CALL curtype
  MOV R1, R0             ; keep type
  LDA A0, #TYPESPD
  ADD A0, R0
  LDB R0, [A0]           ; base speed
  CMP R1, #BRUISER
  BNE cspd_d
  LDW R2, [gtick]
  AND R2, #1
  BEQ cspd_d
  MOV R0, #0            ; bruiser rests this frame
cspd_d:
  RET

; ---- curdmg -> R0 = contact damage for the current enemy. Scratches A0. ----
curdmg:
  CALL curtype
  LDA A0, #TYPEDMG
  ADD A0, R0
  LDB R0, [A0]
  RET

; ---- clampxp: R0 = clamp(R0, XMIN, cammax+PXMAX); scratches R2 ----
clampxp:
  CMP R0, #XMIN
  BGE cxp_hi
  MOV R0, #XMIN
cxp_hi:
  LDW R2, [cammax]
  ADD R2, #PXMAX
  CMP R0, R2
  BLE cxp_d
  MOV R0, R2
cxp_d:
  RET

; ---- updatecam: centre the camera on the player, clamped to the wave's limit ----
updatecam:
  LDW R0, [p_x]
  SUB R0, #152            ; player at screen centre (320/2 - 8)
  CMP R0, #0
  BGE uc_lo
  MOV R0, #0
uc_lo:
  LDW R1, [cammax]
  CMP R0, R1
  BLE uc_set
  MOV R0, R1
uc_set:
  LDW R1, [shakeT]         ; add a decaying horizontal jitter while shaking
  CMP R1, #0
  BEQ uc_write
  SUB R1, #1
  STW R1, [shakeT]
  MOV R2, R1
  AND R2, #1
  BEQ uc_sneg
  ADD R0, #SHAKEAMP
  BRA uc_clamp
uc_sneg:
  SUB R0, #SHAKEAMP
uc_clamp:
  CMP R0, #0              ; cam is treated as unsigned by the sprite math -> keep >= 0
  BGE uc_write
  MOV R0, #0
uc_write:
  STW R0, [cam]
  STW R0, [BG0_SX]        ; scroll BG0 to match (street wraps, so it stays seamless)
  RET

; ============================ OAM (sprites) ============================
buildoam:
  MOV R0, #0
  STW R0, [OAM_INDEX]
  CALL emitplayer
  CALL emitweapon          ; held pipe (off when unarmed)
  MOV R7, #0
bo_e:
  MOV R3, R7
  SHL R3, #3
  LDA A1, #ENEMY
  ADD A1, R3
  STW R7, [eidx]           ; emitenemy reads ETYPE[eidx] to pick a palette
  CALL emitenemy
  ADD R7, #1
  CMP R7, #NENEM
  BLT bo_e
  MOV R7, #0
bo_p:
  MOV R3, R7
  SHL R3, #3
  LDA A1, #PICKUP
  ADD A1, R3
  CALL emitpickup
  ADD R7, #1
  CMP R7, #NPICK
  BLT bo_p
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
  LDW R3, [cam]
  SUB R0, R3              ; world x -> screen x
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
  LDW R4, [A1+#4]         ; world ex (kept for the anim key + culling)
  LDW R3, [cam]
  MOV R0, R4
  SUB R0, R3              ; screen x
  CMP R0, #320            ; off the right edge?
  BGE ee_cull
  MOV R3, R0
  ADD R3, #16
  CMP R3, #0             ; fully off the left edge (screen x <= -16)?
  BLT ee_cull
  LDW R1, [A1+#6]         ; ey (no vertical scroll)
  LDW R2, [bossactive]    ; during a boss wave the lone live thug is the boss
  CMP R2, #0
  BNE ee_boss
  MOV R5, #EN_WALKA       ; simple two-frame shuffle keyed to world x
  MOV R2, R4
  SHR R2, #2
  AND R2, #1
  BEQ ee_tile
  MOV R5, #EN_WALKB
ee_tile:
  PUSH R0                ; save screen x across the type lookup
  CALL curtype          ; R0 = enemy type
  LDA A0, #TYPEBANK
  ADD A0, R0
  LDB R0, [A0]          ; palette bank for this type
  MOV R6, #$10          ; size16
  OR R6, R0             ; | palette bank  (grunt=2, runner=7, bruiser=8)
  POP R0                ; restore screen x
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
ee_cull:
  CALL emitoff           ; still consume one OAM slot, just disabled
  RET
ee_boss:
  MOV R5, #BOSS
  MOV R6, #$16           ; size16 | palette bank 6
  LDB R2, [A1+#2]        ; staggered -> white flash (bank 4)
  CMP R2, #0
  BEQ ee_bface
  MOV R6, #$14
ee_bface:
  LDB R2, [A1+#3]        ; faceRight -> hflip (boss art faces left)
  CMP R2, #0
  BEQ ee_bemit
  ADD R6, #$40
ee_bemit:
  CALL emittile
  RET

; ---- emitweapon: the pipe in the player's hand; animates through a swing ----
;   not swinging -> held at the side; wind-up -> raised diagonally above the head;
;   strike (at/after the live frame) -> thrust out front.
emitweapon:
  LDW R0, [p_weapon]
  CMP R0, #0
  BNE ew_on
  CALL emitoff
  RET
ew_on:
  MOV R5, #WEAPON        ; defaults: held pose
  MOV R2, #8             ; x offset from the player
  MOV R4, #0             ; raise (subtracted from py)
  LDW R0, [p_punch]      ; mid-swing?
  CMP R0, #0
  BEQ ew_face
  LDW R1, [p_wswing]
  CMP R1, #0
  BEQ ew_face            ; a bare-fist swing -> just hold the pipe
  CMP R0, #PUNCHHIT
  BLE ew_strike          ; at/after the live frame -> thrust forward
  MOV R5, #WEAPON_UP     ; wind-up: raised on the diagonal
  MOV R2, #2
  MOV R4, #10
  BRA ew_face
ew_strike:
  MOV R5, #WEAPON
  MOV R2, #18
  MOV R4, #0
ew_face:
  LDW R0, [p_x]
  LDW R1, [p_face]
  AND R1, #1
  BEQ ew_right
  SUB R0, R2             ; facing left: mirror the offset + hflip
  MOV R6, #$55           ; size16 | bank5 | hflip
  BRA ew_xpos
ew_right:
  ADD R0, R2
  MOV R6, #$15           ; size16 | bank5
ew_xpos:
  LDW R3, [cam]
  SUB R0, R3
  LDW R1, [p_y]
  SUB R1, R4             ; raise up during the wind-up
  CALL emittile
  RET

; ---- emitpickup(A1=slot): a pipe/food item on the ground, camera-offset + culled ----
emitpickup:
  LDB R0, [A1+#0]        ; type
  CMP R0, #0
  BNE epk_on
  CALL emitoff
  RET
epk_on:
  CMP R0, #1
  BNE epk_food
  MOV R5, #WEAPON
  BRA epk_pos
epk_food:
  MOV R5, #FOOD
epk_pos:
  LDW R4, [A1+#2]        ; world x
  LDW R3, [cam]
  MOV R0, R4
  SUB R0, R3             ; screen x
  CMP R0, #320
  BGE epk_cull
  MOV R3, R0
  ADD R3, #16
  CMP R3, #0
  BLT epk_cull
  LDW R1, [A1+#4]        ; y
  MOV R6, #$15           ; size16 | bank5
  CALL emittile
  RET
epk_cull:
  CALL emitoff
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
  CALL hpcell
  ADD R4, #1
  CMP R4, #HP0
  BLT hb_lp
  RET

; ---- hpcell(R0=col, R2=tile): a HUD cell on BG1 row 0, palette 0 (HP / weapon) ----
hpcell:
  MOV R1, #0
  MOV R3, #0
  ; fall through to hudtile
; ---- hudtile(R0=col, R1=row, R2=tile, R3=pal): one BG1 (HUD) map cell ----
hudtile:
  MOV R6, R0
  SHL R6, #2             ; col*4 = low byte of the offset
  STB R6, [VRAM_ADDR]
  MOV R6, R1
  ADD R6, #$40           ; row + $40 -> BG1 map base $14000 mid byte
  STB R6, [VRAM_ADDR+1]
  MOV R7, #1
  STB R7, [VRAM_ADDR+2]
  STB R2, [VRAM_DATA]     ; tile lo
  MOV R7, R2
  SHR R7, #8
  AND R7, #7            ; tile hi 3 bits
  MOV R6, R3
  SHL R6, #3            ; palette in bits 3..6
  OR R7, R6
  STB R7, [VRAM_DATA]
  MOV R7, #0
  STB R7, [VRAM_DATA]
  STB R7, [VRAM_DATA]
  RET

; ---- drawbosshp: a red bar (row 1) of one cell per boss HP point remaining ----
drawbosshp:
  LDA A1, #ENEMY
  LDB R5, [A1+#1]         ; boss current HP
  MOV R4, #0
bh_lp:
  CMP R4, R5
  BLT bh_full
  MOV R2, #HP_EMPTY
  BRA bh_set
bh_full:
  MOV R2, #BHP_FULL
bh_set:
  MOV R0, R4
  ADD R0, #11            ; bar runs cols 11..28
  MOV R1, #1             ; HUD row 1
  MOV R3, #0
  CALL hudtile
  ADD R4, #1
  CMP R4, #BOSSBAR
  BLT bh_lp
  RET

; ---- huddigit(R0=value 0..9, R4=col): one digit on BG1 row 0 in white (palette 3) ----
huddigit:
  MOV R2, R0
  ADD R2, #DIGIT
  MOV R0, R4
  MOV R1, #0
  MOV R3, #3
  CALL hudtile
  RET

; ---- hudprint(A1=string, R4=col): draw text on BG1 row 0 in white (palette 3) ----
hudprint:
hl_lp:
  LDB R2, [A1]
  CMP R2, #$FF
  BEQ hl_done
  CMP R2, #26
  BEQ hl_adv
  ADD R2, #FONT
  MOV R0, R4
  MOV R1, #0
  MOV R3, #3
  CALL hudtile
hl_adv:
  ADD R4, #1
  INC A1
  BRA hl_lp
hl_done:
  RET

; ---- drawlevelhud: "STAGE n" in the middle of the HUD strip ----
drawlevelhud:
  LDA A1, #sSTAGE
  MOV R4, #17
  CALL hudprint
  LDW R0, [level]
  ADD R0, #1             ; show 1-based
  MOV R4, #23
  CALL huddigit
  RET

; ---- clearhp: blank both HUD rows (HP bar + weapon widget + boss bar) ----
clearhp:
  MOV R5, #0             ; row
clh_row:
  MOV R4, #0             ; col
clh_lp:
  MOV R0, R4
  MOV R1, R5
  MOV R2, #0
  MOV R3, #0
  CALL hudtile
  ADD R4, #1
  CMP R4, #40
  BLT clh_lp
  ADD R5, #1
  CMP R5, #2
  BLT clh_row
  RET

; ---- drawweapon: HUD pipe icon + a green pip per swing remaining (blank if unarmed) ----
drawweapon:
  LDW R0, [p_weapon]
  CMP R0, #0
  BNE dw_armed
  MOV R4, #31              ; unarmed: clear icon + pip cells
dw_clr:
  MOV R0, R4
  MOV R2, #0
  CALL hpcell
  ADD R4, #1
  CMP R4, #40
  BLT dw_clr
  RET
dw_armed:
  MOV R0, #31              ; the "armed" pipe icon
  MOV R2, #WPN_ICON
  CALL hpcell
  MOV R4, #0
dw_lp:
  LDW R0, [p_weapon]
  CMP R4, R0
  BLT dw_full
  MOV R2, #HP_EMPTY
  BRA dw_set
dw_full:
  MOV R2, #HP_FULL
dw_set:
  MOV R0, R4
  ADD R0, #WPNCOL          ; pips at cols 32..39
  CALL hpcell
  ADD R4, #1
  CMP R4, #WPNUSES
  BLT dw_lp
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
  CMP R4, #64             ; fill the whole 64-wide map so the wrap stays seamless
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
; ---- menureset: unscroll BG0 and clear the HUD before drawing a menu screen ----
menureset:
  MOV R0, #0
  STW R0, [cam]
  STW R0, [BG0_SX]
  CALL clearhp
  RET

drawtitle:
  CALL menureset
  MOV R0, #0
  CALL setlevelpal         ; title always wears stage-1 colours
  CALL clearmap
  CALL drawtitlebg         ; brick wall + sidewalk backdrop
  LDA A1, #sTITLE1
  MOV R4, #17
  MOV R5, #9
  CALL print
  LDA A1, #sTITLE2
  MOV R4, #17
  MOV R5, #12
  CALL print
  LDA A1, #sTAG
  MOV R4, #14
  MOV R5, #15
  CALL print
  LDA A1, #sSTART
  MOV R4, #15
  MOV R5, #19
  CALL print
  CALL titlesprites        ; hero vs. thugs + boss lineup
  RET

; ---- drawtitlebg: a brick wall band up top and a sidewalk band along the bottom ----
drawtitlebg:
  MOV R5, #2              ; brick wall rows 2..6
tbg_w:
  MOV R4, #0
tbg_wx:
  MOV R0, R4
  MOV R1, R5
  MOV R2, #BRICK
  MOV R3, #0
  CALL settile
  ADD R4, #1
  CMP R4, #40
  BLT tbg_wx
  ADD R5, #1
  CMP R5, #7
  BLT tbg_w
  MOV R4, #0             ; curb row 7
tbg_c:
  MOV R0, R4
  MOV R1, #7
  MOV R2, #CURB
  MOV R3, #0
  CALL settile
  ADD R4, #1
  CMP R4, #40
  BLT tbg_c
  MOV R5, #8            ; sidewalk fills everything below the curb (matches the game)
tbg_s:
  MOV R4, #0
tbg_sx:
  MOV R0, R4
  MOV R1, R5
  MOV R2, #SIDEWALK
  MOV R3, #0
  CALL settile
  ADD R4, #1
  CMP R4, #40
  BLT tbg_sx
  ADD R5, #1
  CMP R5, #28
  BLT tbg_s
  RET

; ---- titlesprites: a static cast lineup standing on the bottom sidewalk ----
titlesprites:
  MOV R0, #0
  STW R0, [OAM_INDEX]
  MOV R0, #56            ; hero, facing right
  MOV R1, #160
  MOV R5, #PL_WALKA
  MOV R6, #$11
  CALL emittile
  MOV R0, #96            ; a pipe on the ground
  MOV R1, #172
  MOV R5, #WEAPON
  MOV R6, #$15
  CALL emittile
  MOV R0, #128           ; food on the ground
  MOV R1, #172
  MOV R5, #FOOD
  MOV R6, #$15
  CALL emittile
  MOV R0, #180           ; thug (art already faces left, toward the hero)
  MOV R1, #160
  MOV R5, #EN_WALKA
  MOV R6, #$12
  CALL emittile
  MOV R0, #212           ; second thug
  MOV R1, #160
  MOV R5, #EN_WALKB
  MOV R6, #$12
  CALL emittile
  MOV R0, #246           ; the boss
  MOV R1, #156
  MOV R5, #BOSS
  MOV R6, #$16
  CALL emittile
  RET

drawwin:
  CALL menureset
  CALL clearmap
  CALL drawtitlebg
  LDA A1, #sWIN
  MOV R4, #16
  MOV R5, #9
  CALL print
  LDA A1, #sSTART
  MOV R4, #15
  MOV R5, #19
  CALL print
  CALL winsprites
  RET

; ---- winsprites: hero stands tall with the pipe raised; the gang lies beaten ----
winsprites:
  MOV R0, #0
  STW R0, [OAM_INDEX]
  MOV R0, #60            ; hero, on the left, standing
  MOV R1, #158
  MOV R5, #PL_WALKA
  MOV R6, #$11
  CALL emittile
  MOV R0, #70            ; pipe raised in victory
  MOV R1, #148
  MOV R5, #WEAPON_UP
  MOV R6, #$15
  CALL emittile
  MOV R0, #140           ; beaten thug (vflip = flat on its back)
  MOV R1, #176
  MOV R5, #EN_WALKA
  MOV R6, #$92
  CALL emittile
  MOV R0, #178
  MOV R1, #176
  MOV R5, #EN_WALKB
  MOV R6, #$92
  CALL emittile
  MOV R0, #216           ; beaten boss
  MOV R1, #174
  MOV R5, #BOSS
  MOV R6, #$96
  CALL emittile
  RET

drawover:
  CALL menureset
  CALL clearmap
  CALL drawtitlebg
  LDA A1, #sOVER
  MOV R4, #15
  MOV R5, #9
  CALL print
  LDA A1, #sSTART
  MOV R4, #15
  MOV R5, #19
  CALL print
  CALL oversprites
  RET

; ---- oversprites: the hero is down; the gang stands over him ----
oversprites:
  MOV R0, #0
  STW R0, [OAM_INDEX]
  MOV R0, #150           ; downed hero (vflip), centre
  MOV R1, #176
  MOV R5, #PL_WALKA
  MOV R6, #$91
  CALL emittile
  MOV R0, #100           ; thug standing over him, facing right
  MOV R1, #158
  MOV R5, #EN_WALKA
  MOV R6, #$52
  CALL emittile
  MOV R0, #208           ; thug on the right
  MOV R1, #158
  MOV R5, #EN_WALKB
  MOV R6, #$12
  CALL emittile
  MOV R0, #240           ; the boss looms
  MOV R1, #154
  MOV R5, #BOSS
  MOV R6, #$16
  CALL emittile
  RET

; ---- drawinter: "STAGE n / GET READY" shown between stages ----
drawinter:
  CALL menureset
  CALL clearmap
  LDA A1, #sSTAGE
  MOV R4, #16
  MOV R5, #10
  CALL print
  LDW R0, [level]          ; upcoming stage (level is the one just cleared), 1-based
  ADD R0, #2
  MOV R4, #22
  MOV R5, #10
  CALL printdigit
  LDA A1, #sREADY
  MOV R4, #15
  MOV R5, #14
  CALL print
  RET

; ---- printdigit(R0=value, R4=col, R5=row): one digit on BG0 in white ----
printdigit:
  MOV R2, R0
  ADD R2, #DIGIT
  MOV R0, R4
  MOV R1, R5
  MOV R3, #3
  CALL settile
  RET

; ============================ new game ============================
newgame:
  MOV R0, #0
  STW R0, [kills]
  STW R0, [level]
  CALL loadlevel           ; build stage 0 (R0 = 0)
  MOV R0, #HP0
  STW R0, [p_hp]           ; full health for a fresh game
  MOV R0, #1
  STW R0, [state]
  RET

; ---- loadlevel(R0=level): recolour + paint the stage, reset camera/player, wave 0 ----
loadlevel:
  STW R0, [level]
  CALL setlevelpal         ; (R0 still = level)
  CALL clearmap
  CALL buildstreet
  MOV R0, #0
  STW R0, [cam]
  STW R0, [cammax]
  STW R0, [BG0_SX]
  STW R0, [wave]
  STW R0, [bossactive]
  STW R0, [clrpause]
  STW R0, [shakeT]         ; clear any leftover juice timers
  STW R0, [hitstop]
  STW R0, [p_face]
  STW R0, [p_punch]
  STW R0, [p_hurt]
  STW R0, [p_anim]
  STW R0, [p_weapon]       ; pipe does not carry between stages
  STW R0, [p_wswing]
  MOV R0, #80
  STW R0, [p_x]            ; start at the left of the new street
  MOV R0, #150
  STW R0, [p_y]
  CALL clearpickups
  CALL clearoam            ; wipe any title-screen lineup sprites
  CALL clearhp
  CALL drawlevelhud
  CALL spawnwave           ; first wave of this stage
  MOV R0, #1               ; a pipe to open the stage with
  MOV R1, #240
  MOV R2, #130
  CALL addpickup
  RET

; ---- setlevelpal(R0=level): per-stage brick / sidewalk / enemy-body colours ----
setlevelpal:
  MOV R3, R0
  SHL R3, #3              ; level * 8 bytes (4 words each)
  LDA A0, #levelpal
  ADD A0, R3
  MOV R0, #1             ; BG bank 0 entries 1,2,3
  STB R0, [PAL_INDEX]
  LDW R0, [A0]
  STW R0, [PAL_DATA]     ; 1 brick dark
  LDW R0, [A0+#2]
  STW R0, [PAL_DATA]     ; 2 brick light
  LDW R0, [A0+#4]
  STW R0, [PAL_DATA]     ; 3 sidewalk
  MOV R0, #33           ; enemy bank 2 entry 1
  STB R0, [PAL_INDEX]
  LDW R0, [A0+#6]
  STW R0, [PAL_DATA]     ; enemy body colour
  RET

; ---- addpickup(R0=type, R1=x, R2=y): drop into the first free pickup slot ----
addpickup:
  PUSH R7
  MOV R7, #0
ap_lp:
  MOV R3, R7
  SHL R3, #3
  LDA A1, #PICKUP
  ADD A1, R3
  LDB R4, [A1+#0]
  CMP R4, #0
  BEQ ap_free
  ADD R7, #1
  CMP R7, #NPICK
  BLT ap_lp
  POP R7                   ; no room -> drop it silently
  RET
ap_free:
  STB R0, [A1+#0]
  STW R1, [A1+#2]
  STW R2, [A1+#4]
  POP R7
  RET

; ---- clearpickups: empty every pickup slot ----
clearpickups:
  MOV R7, #0
cpk_lp:
  MOV R3, R7
  SHL R3, #3
  LDA A1, #PICKUP
  ADD A1, R3
  MOV R0, #0
  STB R0, [A1+#0]
  ADD R7, #1
  CMP R7, #NPICK
  BLT cpk_lp
  RET

; ---- dopickups: grab any pickup the player is standing on ----
dopickups:
  MOV R7, #0
dp_lp:
  MOV R3, R7
  SHL R3, #3
  LDA A1, #PICKUP
  ADD A1, R3
  LDB R0, [A1+#0]
  CMP R0, #0
  BEQ dp_next
  LDW R1, [A1+#2]          ; |px - p_x| < PICKR ?
  LDW R2, [p_x]
  MOV R0, R1
  SUB R0, R2
  CALL absr0
  CMP R0, #PICKR
  BGE dp_next
  LDW R1, [A1+#4]          ; |py - p_y| < PICKR ?
  LDW R2, [p_y]
  MOV R0, R1
  SUB R0, R2
  CALL absr0
  CMP R0, #PICKR
  BGE dp_next
  LDB R0, [A1+#0]          ; collect: dispatch on type
  CMP R0, #1
  BNE dp_food
  MOV R0, #WPNUSES         ; pipe -> arm (refills durability)
  STW R0, [p_weapon]
  MOV R0, #200
  CALL sfxblip
  BRA dp_take
dp_food:
  LDW R0, [p_hp]           ; food -> heal, capped at full
  ADD R0, #FOODHP
  CMP R0, #HP0
  BLE dp_heal
  MOV R0, #HP0
dp_heal:
  STW R0, [p_hp]
  MOV R0, #70
  CALL sfxblip
dp_take:
  MOV R0, #0
  STB R0, [A1+#0]          ; remove the pickup
dp_next:
  ADD R7, #1
  CMP R7, #NPICK
  BGE dp_end
  BRA dp_lp               ; long branch back (loop body exceeds short-branch range)
dp_end:
  RET

; ---- countalive: R0 = number of live thugs ----
countalive:
  MOV R7, #0
  MOV R6, #0
ca_lp:
  MOV R3, R7
  SHL R3, #3
  LDA A1, #ENEMY
  ADD A1, R3
  LDB R0, [A1+#0]
  CMP R0, #0
  BEQ ca_n
  ADD R6, #1
ca_n:
  ADD R7, #1
  CMP R7, #NENEM
  BLT ca_lp
  MOV R0, R6
  RET

; ---- nextwave: bump the wave, push the camera limit on by SEG, spawn the group ----
nextwave:
  LDW R0, [wave]
  ADD R0, #1
  STW R0, [wave]
  LDW R0, [cammax]
  ADD R0, #SEG
  STW R0, [cammax]
  CALL spawnwave
  MOV R0, #2               ; reward: a drumstick in the new stretch of street
  LDW R1, [cammax]
  ADD R1, #120
  MOV R2, #120
  CALL addpickup
  LDW R0, [wave]           ; on even waves, also drop a fresh pipe
  AND R0, #1
  BNE nw_done
  MOV R0, #1
  LDW R1, [cammax]
  ADD R1, #230
  MOV R2, #170
  CALL addpickup
nw_done:
  RET

; ---- spawnwave: boss wave -> spawnboss; else read the (level,wave) descriptor from
;      wavedef and spawn one typed thug per non-empty slot, spread across the street ----
spawnwave:
  LDW R0, [wave]
  CMP R0, #NORMW
  BLT sw_normal
  BRA spawnboss          ; boss wave (BRA: spawnboss is out of short-branch range)
sw_normal:
  MOV R0, #EHOLD          ; brief grace before they advance...
  LDW R1, [wave]
  CMP R1, #0
  BNE sw_hold
  MOV R0, #EHOLD0         ; ...longer for a stage's opening wave
sw_hold:
  STW R0, [ehold]
  MOV R0, #0
  STW R0, [bossactive]
  ; descriptor base A0 = wavedef + (level*NORMW + wave) * NENEM
  LDW R0, [level]
  MOV R1, R0
  SHL R1, #1
  ADD R1, R0             ; level * 3   (NORMW = 3)
  LDW R0, [wave]
  ADD R1, R0             ; + wave  -> descriptor row index
  SHL R1, #3             ; * 8 bytes/row  (NENEM = 8 type bytes per row)
  LDA A0, #wavedef
  ADD A0, R1
  MOV R7, #0
sw_lp:
  LDB R0, [A0+R7]        ; type for slot R7 (NONE = empty)
  CMP R0, #NONE
  BEQ sw_dead
  LDA A2, #ETYPE         ; ETYPE[R7] = type
  ADD A2, R7
  STB R0, [A2]
  LDA A2, #TYPEHP        ; hp = TYPEHP[type]
  ADD A2, R0
  LDB R1, [A2]
  MOV R3, R7             ; slot pointer
  SHL R3, #3
  LDA A1, #ENEMY
  ADD A1, R3
  MOV R0, #1
  STB R0, [A1+#0]        ; alive
  STB R1, [A1+#1]        ; hp
  MOV R0, #0
  STB R0, [A1+#2]        ; hurt
  STB R0, [A1+#3]        ; face
  LDW R0, [cammax]        ; x = cammax + 160 + i*48 (staggered off the right edge)
  ADD R0, #160
  MOV R2, R7
  SHL R2, #5            ; i*32
  MOV R3, R7
  SHL R3, #4           ; i*16
  ADD R2, R3           ; i*48
  ADD R0, R2
  STW R0, [A1+#4]
  MOV R0, R7            ; y = 96 + (i&3)*24  (four rows down the band)
  AND R0, #3
  MOV R2, R0
  SHL R2, #4           ; row*16
  SHL R0, #3           ; row*8
  ADD R2, R0           ; row*24
  MOV R0, R2
  ADD R0, #96
  STW R0, [A1+#6]
  BRA sw_next
sw_dead:
  MOV R3, R7
  SHL R3, #3
  LDA A1, #ENEMY
  ADD A1, R3
  MOV R0, #0
  STB R0, [A1+#0]
sw_next:
  ADD R7, #1
  CMP R7, #NENEM
  BGE sw_ret            ; forward exit + BRA back keeps the loop in short-branch range
  BRA sw_lp
sw_ret:
  RET

; ---- spawnboss: one boss in slot 0, all other slots idle, boss bar armed ----
spawnboss:
  LDA A1, #ENEMY
  MOV R0, #1
  STB R0, [A1+#0]
  MOV R0, #BOSSHP
  STB R0, [A1+#1]
  LDA A2, #ETYPE          ; boss uses the grunt profile (steady speed, 1 contact dmg)
  MOV R0, #GRUNT
  STB R0, [A2]
  MOV R0, #0
  STB R0, [A1+#2]
  STB R0, [A1+#3]
  LDW R0, [cammax]         ; boss waits ahead of the camera limit
  ADD R0, #200
  STW R0, [A1+#4]
  MOV R0, #140
  STW R0, [A1+#6]
  MOV R7, #1              ; every other slot stays empty
sb_lp:
  MOV R3, R7
  SHL R3, #3
  LDA A1, #ENEMY
  ADD A1, R3
  MOV R0, #0
  STB R0, [A1+#0]
  ADD R7, #1
  CMP R7, #NENEM
  BLT sb_lp
  MOV R0, #1
  STW R0, [bossactive]
  MOV R0, #BOSSHP
  STW R0, [bossmaxhp]
  MOV R0, #EHOLD          ; let the boss make an entrance before it charges
  STW R0, [ehold]
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

; ---- musictick: a one-channel (SQ1) looping riff. Each note holds NOTELEN frames;
;      song[] is a word list of periods (0 = rest, $FFFF = loop to the top). ----
musictick:
  LDW R0, [mT]
  CMP R0, #0
  BEQ mt_next
  SUB R0, #1
  STW R0, [mT]
  RET
mt_next:
  LDW R0, [mIdx]         ; period = song[mIdx]
  LDA A0, #song
  MOV R1, R0
  SHL R1, #1
  ADD A0, R1
  LDW R2, [A0]
  MOV R1, #$FFFF        ; end marker -> loop back to note 0
  CMP R2, R1
  BNE mt_play
  MOV R0, #0
  STW R0, [mIdx]
  LDA A0, #song
  LDW R2, [A0]
mt_play:
  CMP R2, #0            ; 0 = rest -> silence the channel
  BEQ mt_rest
  STW R2, [SQ1_PERIOD]
  MOV R0, #5
  STB R0, [SQ1_VOL]
  MOV R0, #1
  STB R0, [SQ1_CTRL]
  BRA mt_adv
mt_rest:
  MOV R0, #0
  STB R0, [SQ1_CTRL]
mt_adv:
  MOV R0, #NOTELEN
  STW R0, [mT]
  LDW R0, [mIdx]
  ADD R0, #1
  STW R0, [mIdx]
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
  MOV R0, #80            ; bank 5: pickups (pipe + food)
  STB R0, [PAL_INDEX]
  MOV R0, #$0000
  STW R0, [PAL_DATA]
  MOV R0, #$5AD6
  STW R0, [PAL_DATA]     ; 1 pipe light grey
  MOV R0, #$294A
  STW R0, [PAL_DATA]     ; 2 pipe dark grey
  MOV R0, #$1152
  STW R0, [PAL_DATA]     ; 3 meat brown
  MOV R0, #$4B5C
  STW R0, [PAL_DATA]     ; 4 bone / tan
  MOV R0, #$139E
  STW R0, [PAL_DATA]     ; 5 yellow
  MOV R0, #96            ; bank 6: boss
  STB R0, [PAL_INDEX]
  MOV R0, #$0000
  STW R0, [PAL_DATA]
  MOV R0, #$6C1C
  STW R0, [PAL_DATA]     ; 1 boss body (purple)
  MOV R0, #$2008
  STW R0, [PAL_DATA]     ; 2 dark
  MOV R0, #$3A5C
  STW R0, [PAL_DATA]     ; 3 skin
  MOV R0, #$7FFF
  STW R0, [PAL_DATA]     ; 4 white (eyes / flash)
  MOV R0, #112           ; bank 7: runner (fast, fragile) — teal jacket
  STB R0, [PAL_INDEX]
  MOV R0, #$0000
  STW R0, [PAL_DATA]
  MOV R0, #$5F20
  STW R0, [PAL_DATA]     ; 1 body (bright teal)
  MOV R0, #$2980
  STW R0, [PAL_DATA]     ; 2 dark teal
  MOV R0, #$3A5C
  STW R0, [PAL_DATA]     ; 3 skin
  MOV R0, #$7FFF
  STW R0, [PAL_DATA]     ; 4 white
  MOV R0, #128           ; bank 8: bruiser (slow, tanky) — heavy brown
  STB R0, [PAL_INDEX]
  MOV R0, #$0000
  STW R0, [PAL_DATA]
  MOV R0, #$1952
  STW R0, [PAL_DATA]     ; 1 body (brown)
  MOV R0, #$0A0C
  STW R0, [PAL_DATA]     ; 2 dark brown
  MOV R0, #$3A5C
  STW R0, [PAL_DATA]     ; 3 skin
  MOV R0, #$7FFF
  STW R0, [PAL_DATA]     ; 4 white
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
; per-stage palette: brick dark, brick light, sidewalk, enemy body (RGB555)
levelpal:
  DW $10D6, $215B, $5294, $109E   ; stage 1: red brick, red thugs
  DW $3042, $40C4, $418C, $609C   ; stage 2: night blue, magenta thugs
  DW $1142, $1A04, $3254, $0A1E   ; stage 3: industrial green, orange thugs

; ---- enemy type stats, indexed by type (GRUNT, RUNNER, BRUISER) ----
TYPEHP:                          ; hit points
  DB 3, 2, 6
TYPESPD:                         ; chase speed (px/frame; bruiser also rests alt frames)
  DB 1, 2, 1
TYPEDMG:                         ; contact damage
  DB 1, 1, 2
TYPEBANK:                        ; sprite palette bank
  DB 2, 7, 8

; ---- wave descriptors: NLEVELS*NORMW rows, NENEM type bytes each (NONE = empty).
;      Row index = level*NORMW + wave. Difficulty ramps across the stages. ----
wavedef:
  ; stage 1
  DB GRUNT,   GRUNT,   NONE,    NONE,    NONE,    NONE,    NONE,    NONE
  DB GRUNT,   GRUNT,   RUNNER,  NONE,    NONE,    NONE,    NONE,    NONE
  DB GRUNT,   GRUNT,   GRUNT,   RUNNER,  NONE,    NONE,    NONE,    NONE
  ; stage 2
  DB GRUNT,   RUNNER,  RUNNER,  NONE,    NONE,    NONE,    NONE,    NONE
  DB GRUNT,   GRUNT,   BRUISER, NONE,    NONE,    NONE,    NONE,    NONE
  DB RUNNER,  RUNNER,  GRUNT,   BRUISER, NONE,    NONE,    NONE,    NONE
  ; stage 3
  DB GRUNT,   GRUNT,   BRUISER, BRUISER, NONE,    NONE,    NONE,    NONE
  DB RUNNER,  RUNNER,  RUNNER,  GRUNT,   NONE,    NONE,    NONE,    NONE
  DB GRUNT,   RUNNER,  BRUISER, GRUNT,   RUNNER,  BRUISER, NONE,    NONE

; ---- song: SQ1 periods, 0 = rest, $FFFF = loop. A driving minor-key riff. ----
song:
  DW 109, 109, 0,   73,  92,  0,   73,  55
  DW 61,  61,  0,   73,  92,  73,  109, 0
  DW $FFFF

sTITLE1:
  DB S, T, R, E, E, T, END
sTITLE2:
  DB B, R, A, W, L, END
sTAG:
  DB G, R, A, B, SPC, T, H, E, SPC, P, I, P, E, END
sSTART:
  DB P, U, S, H, SPC, S, T, A, R, T, END
sSTAGE:
  DB S, T, A, G, E, SPC, END
sREADY:
  DB G, E, T, SPC, R, E, A, D, Y, END
sWIN:
  DB Y, O, U, SPC, W, I, N, END
sOVER:
  DB G, A, M, E, SPC, O, V, E, R, END

sheet:
  INCBIN "assets.bin"
sheetend:
