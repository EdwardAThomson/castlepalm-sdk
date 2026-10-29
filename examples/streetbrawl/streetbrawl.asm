; ============================================================================
; STREET BRAWL — a Streets-of-Rage-style beat-'em-up prototype for CastlePalm
;
;   Walk your hero along a scrolling sidewalk (8-way, D-pad), throw punches (A),
;   and clear the street of thugs. Enemies chase you, stagger and flash white when
;   hit, and get knocked back; they square up, wind a punch back (the tell) and swing, and
;   only a landed punch costs health.
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
;   Character creator (after the title): Up/Down pick a row, Left/Right change it,
;   A throws a test punch, Start fights. The pick is kept in save RAM.
;
;   Art: examples/streetbrawl/gen_art.js draws everything (street, skyline, 64x64 shaded
;   fighters, HUD font) and writes the blobs this cart INCBINs: tiles (DMA'd to VRAM),
;   maps (BG0 skyline + BG1 street), the 256-entry palette, per-stage records (a
;   224-line sky gradient + three recoloured banks), the player's selectable bodies
;   and the creator's colour ramps. Build the art first:
;       node examples/streetbrawl/gen_art.js
;       node tools/build-cart.js examples/streetbrawl/streetbrawl.asm streetbrawl.cpc BRAWL
;
;   Layers: BG0 = clouds + skyline, scrolled at cam/4 (parallax). BG1 = the street,
;   with the HUD in map rows 0-1. An hblank handler rewrites palette entry 0 every
;   line (the sky gradient) and holds BG1's scroll at 0 for lines 0-23 (HUD split).
; ============================================================================

; ---- MMIO ----
INPUT0     EQU $100000
VRAM_ADDR  EQU $101000
VRAM_DATA  EQU $101004
PAL_INDEX  EQU $101008
PAL_DATA   EQU $10100A
OAM_INDEX  EQU $10100C
OAM_DATA   EQU $10100E
BG0_SX     EQU $101010    ; BG0 horizontal scroll (signed 16-bit latch): skyline, parallax
BG1_SX     EQU $101014    ; BG1 horizontal scroll: the street (set per line by the hblank handler)
PPU_CTRL   EQU $101018
PPU_LINE   EQU $10101A    ; current scanline (read)
IRQ_ENABLE EQU $100012    ; bit1 = hblank
FRAMECTR   EQU $100014    ; u16 frame counter (read)
DMA_SRC    EQU $100020
DMA_DST    EQU $100024
DMA_LEN    EQU $100028
DMA_MODE   EQU $10002A    ; 0 VRAM, 2 palette
DMA_CTRL   EQU $10002E
SQ0_PERIOD EQU $102000
SQ0_VOL    EQU $102002
SQ0_CTRL   EQU $102003
SQ1_PERIOD EQU $102004    ; square 1 — reserved for the music loop (SFX use SQ0)
SQ1_VOL    EQU $102006
SQ1_CTRL   EQU $102007
SAVECOMMIT EQU $100016    ; poke nonzero once save RAM holds a coherent record; host persists it

; ---- cartridge save RAM ($200000-$207FFF): a per-browser best-kills high score ----
SV_MAG   EQU $200000      ; u16 marker word (SVMAGIC = a valid Street Brawl save)
SV_BEST  EQU $200002      ; u16 best kills across runs
SV_CHAR  EQU $200004      ; 6 bytes: the creator's picks (same order as c_body..)
SVMAGIC  EQU $B501        ; distinctive non-zero marker (fresh save RAM is all zeros)

; ---- input bits ----
UP    EQU 1
DOWN  EQU 2
LEFT  EQU 4
RIGHT EQU 8
ABTN  EQU 16
START EQU 256

; ---- tile indices (must match T in examples/streetbrawl/gen_art.js) ----
HP_FULL  EQU 5          ; 8x8 HUD cells
HP_EMPTY EQU 6
WPN_ICON EQU 8
BHP_FULL EQU 9          ; boss health-bar cell
FONT     EQU 64
DIGIT    EQU 96         ; DIGIT + (0..9)
PL_WALK  EQU 128        ; hero walk cycle: 4 frames of 64x64, 64 tiles apart (faces right)
PL_PUNCH EQU 384
PL_DOWN  EQU 448        ; knocked flat
GR_WALK  EQU 512        ; grunt/runner walk: 2 frames (faces right)
GR_DOWN  EQU 640
BR_WALK  EQU 704        ; bruiser/boss walk: 2 frames (faces right)
BR_DOWN  EQU 832
SHADOW   EQU 896        ; 32x32 ground shadow
WEAPON   EQU 912        ; 16x16 pipe (pickup / held)
WEAPON_UP EQU 916       ; pipe raised mid-swing
FOOD     EQU 920        ; 16x16 drumstick
GR_WIND  EQU 924        ; thug attack: wind-up (the telegraph), then the punch 64 tiles on
GR_PUNCH EQU 988
BR_WIND  EQU 1052
BR_PUNCH EQU 1116
SOLID    EQU 16         ; 15 solid swatch cells: SOLID + k - 1 is filled with colour k
ARROWL   EQU 91         ; font arrows for the creator
ARROWR   EQU 92
; ---- palette banks ----
PB_HUD    EQU 0
PB_FONT   EQU 3
PB_FLASH  EQU 4         ; hit flash (all near-white)
PB_PICK   EQU 5         ; pipe + food
PB_BOSS   EQU 6
PB_PLAYER EQU 9
PB_SHADOW EQU 15
; ---- sprite attr-lo sizes ----
SZ16     EQU $10
SZ32     EQU $20
SZ64     EQU $30
; ---- 64x64 fighter placement: feet sit at (px+8, py+16) ----
FOFFX    EQU 24         ; sprite x = px - cam - FOFFX
FOFFY    EQU 46         ; sprite y = py - FOFFY
PL_BYTES EQU 12288      ; one selectable body: 6 frames x 64 tiles x 32 bytes (PL_WALK..PL_DOWN)
NBODY    EQU 8
PL_DST   EQU 4096       ; PL_WALK * 32: VRAM byte offset of the player's frames
PB9PAL   EQU 290        ; palette byte offset of bank 9 entry 1 (PB_PLAYER*32 + 2)
CP_HAIR  EQU 36         ; byte offsets into charpal: skin ramps (3 words) start at 0
CP_TOP   EQU 68
CP_LEGS  EQU 128
CP_SHOES EQU 188
CP_OL    EQU 220        ; outline word, then the trim word
CP_TRIM  EQU 222
CROWS    EQU 6          ; creator rows: body, skin, hair, top, legs, shoes
CROW0    EQU 6          ; screen row of the first; one row every two
CROWEND  EQU 18         ; CROW0 + CROWS*2
CROWPY   EQU 48         ; CROW0 * 8 (cursor y)
CLAB     EQU 15         ; label column
CARL     EQU 22         ; left arrow column; values from CARL+2, right arrow at CARR
CARR     EQU 30
CURX     EQU 108        ; cursor x: CLAB*8 - 12
PVX      EQU 32         ; creator preview sprite position
PVY      EQU 136
HUDLINES EQU 24         ; lines 0-23 show the HUD (BG1 unscrolled)
LEVELREC EQU 534        ; bytes per stage record in levels.bin

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
ATKT     EQU 58         ; thug attack timer start: wind-up 57..45, punch 44..37, cooldown 36..1
ATKSTRIKE EQU 44        ; the single frame the thug's fist is live
ATKCD    EQU 36         ; cooldown: back to chasing, but no new attack until the timer runs out
ATKRX    EQU 26         ; start an attack when the player is this close in x ...
ATKRY    EQU 6          ; ... and on (nearly) the same row
ATKREACH EQU 32         ; how far in front the punch lands (px between logic boxes)
ATKHY    EQU 10         ; row tolerance for the punch to land
ESTAND   EQU 20         ; thugs close to this x gap, not on top of the player
HP0      EQU 16         ; starting health (= HP bar cells)
BANDTOP  EQU 112        ; player/enemy vertical play band (py range; feet = py+16, on the sidewalk/road)
BANDBOT  EQU 190
XMIN     EQU 16
PXMAX    EQU 288        ; player reach to the right of the current camera limit
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
state    EQU $000100    ; 0 title, 1 play, 2 win, 3 over, 4 interstitial, 5 creator
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
best     EQU $000164    ; best kills across runs (loaded from save RAM at boot)
svrem    EQU $000166    ; scratch: running value during decimal-digit extraction
sprpri   EQU $000168    ; sprite priority for the next emittile (2 = under fighters, 3..7 = depth)
wframe   EQU $00016A    ; frame counter latched by the main loop's wait
c_sel    EQU $00016C    ; creator: selected row (0..CROWS-1)
c_edge   EQU $00016E    ; creator: buttons newly pressed this frame
c_body   EQU $000170    ; creator picks, one byte each: body, skin, hair, top, legs, shoes
CHARPAL  EQU $000600    ; 15 words: the player's bank, assembled from the picks
SKYTAB   EQU $000400    ; 224 RGB555 words: this stage's sky, one per scanline (hblank reads it)
hbx0     EQU $000130    ; punch hitbox (computed each swing)
hbx1     EQU $000132
hby0     EQU $000134
hby1     EQU $000136
ENEMY    EQU $000200    ; NENEM slots x 8 bytes  ($0200..$023F for 8 slots)
;   +0 alive  +1 hp  +2 hurt(stagger)  +3 faceRight  +4 px(u16)  +6 py(u16)
ETYPE    EQU $000248    ; parallel array: 1 type byte per enemy slot (keeps the 8-byte stride)
EATK     EQU $000250    ; parallel array: attack timer per enemy slot (0 = idle, see ATKT)
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
  DA 0                     ; vblank (unused)
  DA hblank                ; per-line sky colour + HUD scroll split
  DA 0

; ============================ boot ============================
start:
  CALL loadart             ; tiles -> VRAM, palette, stage-1 sky
  MOV R0, #3
  STW R0, [PPU_CTRL]        ; enable BG0 (skyline) + BG1 (street + HUD)
  MOV R0, #0
  STW R0, [in_now]
  STW R0, [in_prev]
  STW R0, [sfxT]
  STW R0, [gtick]
  STW R0, [shakeT]
  STW R0, [hitstop]
  STW R0, [mIdx]           ; start the music loop from the top
  STW R0, [mT]
  CALL loadsave            ; restore best-kills from cartridge save RAM (0 if none)
  CALL loadchar            ; and the saved fighter (body tiles + player bank)
  CALL drawtitle
  MOV R0, #0
  STW R0, [state]
  MOV R0, #2
  STB R0, [IRQ_ENABLE]     ; hblank IRQ on
  EI

mainloop:
  CALL readpad
  LDW R0, [state]
  CMP R0, #1
  BEQ ml_play
  CMP R0, #4
  BEQ ml_inter
  CMP R0, #5
  BEQ ml_create
  CALL menuframe
  BRA ml_wait
ml_play:
  CALL playframe
  BRA ml_wait
ml_inter:
  CALL interframe
  BRA ml_wait
ml_create:
  CALL creatorframe
ml_wait:
  CALL sfxtick
  CALL musictick
  LDW R0, [FRAMECTR]       ; hblank IRQs also wake WAIT: sleep until the frame counter moves
  STW R0, [wframe]
ml_sleep:
  WAIT
  LDW R0, [FRAMECTR]
  LDW R1, [wframe]
  CMP R0, R1
  BEQ ml_sleep
  BRA mainloop

; ---- hblank: runs after each visible line; sets up the NEXT line ----
;   palette entry 0 (the backdrop) = SKYTAB[line]; BG1 scroll = 0 for the HUD band
;   (lines 0..HUDLINES-1) and the camera below it. Line 223's call primes line 0.
hblank:
  PUSH R0
  PUSH R1
  PUSHA A0
  LDW R0, [PPU_LINE]
  ADD R0, #1
  CMP R0, #224
  BLT hb_line
  MOV R0, #0
hb_line:
  CMP R0, #0
  BNE hb_cam
  MOV R1, #0
  STW R1, [BG1_SX]         ; HUD band: unscrolled
  BRA hb_sky
hb_cam:
  CMP R0, #HUDLINES
  BNE hb_sky
  LDW R1, [cam]
  STW R1, [BG1_SX]         ; street band: follow the camera
hb_sky:
  SHL R0, #1
  LDA A0, #SKYTAB
  ADD A0, R0
  LDW R1, [A0]
  MOV R0, #0
  STB R0, [PAL_INDEX]
  STW R1, [PAL_DATA]       ; backdrop colour for the next line
  POPA A0
  POP R1
  POP R0
  IRET

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
  CALL drawcreator         ; from title -> pick a fighter
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
  CALL savebest            ; commit a new best-kills if this run beat it
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
  CALL savebest            ; a winning run also records its kills
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
  CALL atkptr             ; a hit cuts a wind-up or punch short (straight to cooldown)
  LDB R1, [A2]
  CMP R1, #ATKCD
  BLE ea_stg
  MOV R1, #ATKCD
  STB R1, [A2]
ea_stg:
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
  CALL atkptr             ; attack timer: wind-up / punch hold the thug still
  LDB R0, [A2]
  CMP R0, #0
  BEQ ea_move
  SUB R0, #1
  STB R0, [A2]
  CMP R0, #ATKCD
  BLE ea_move             ; cooldown: chase again
  CMP R0, #ATKSTRIKE
  BNE ea_hold
  CALL estrike            ; the fist is live this frame
ea_hold:
  RET
ea_move:
  LDW R4, [A1+#4]         ; ex
  LDW R5, [A1+#6]         ; ey
  CALL curspd            ; R0 = this enemy's speed (0 on a bruiser's rest frame)
  MOV R3, R0             ; hold speed in R3 across the move
  LDW R6, [p_x]          ; stand off ESTAND px to whichever side the thug is on
  CMP R4, R6
  BLT ea_tl
  ADD R6, #ESTAND
  BRA ea_tx
ea_tl:
  SUB R6, #ESTAND
ea_tx:
  MOV R0, R4             ; close enough in x -> hold (no 1 px jitter)
  SUB R0, R6
  CALL absr0
  CMP R0, R3
  BLE ea_cy
  CMP R4, R6
  BLT ea_cxr
  SUB R4, R3
  BRA ea_cy
ea_cxr:
  ADD R4, R3
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
  LDW R6, [p_x]           ; face the player
  MOV R0, #0
  CMP R4, R6
  BGE ea_face
  MOV R0, #1
ea_face:
  STB R0, [A1+#3]
  ; in reach and on the row? start an attack (wind-up first, so it can be read)
  CALL atkptr
  LDB R0, [A2]
  CMP R0, #0
  BNE ea_done
  MOV R0, R4
  SUB R0, R6
  CALL absr0
  CMP R0, #ATKRX
  BGT ea_done
  LDW R6, [p_y]
  MOV R0, R5
  SUB R0, R6
  CALL absr0
  CMP R0, #ATKRY
  BGT ea_done
  MOV R0, #ATKT
  STB R0, [A2]
ea_done:
  RET

; ---- atkptr: A2 = &EATK[eidx] (this enemy's attack timer). Scratches R1. ----
atkptr:
  LDW R1, [eidx]
  LDA A2, #EATK
  ADD A2, R1
  RET

; ---- estrike(A1=slot): the punch lands if the player is in front, in reach, on the
;      row and not in i-frames. Damage is the type's TYPEDMG (bruisers hit for 2). ----
estrike:
  LDW R4, [A1+#4]
  LDW R5, [A1+#6]
  LDW R0, [p_y]
  SUB R0, R5
  CALL absr0
  CMP R0, #ATKHY
  BGT ek_miss
  LDW R0, [p_x]           ; d = distance in front of the thug
  SUB R0, R4
  LDB R1, [A1+#3]
  CMP R1, #0
  BNE ek_fwd
  NEG R0                  ; facing left: in front means px < ex
ek_fwd:
  CMP R0, #0
  BLT ek_miss
  CMP R0, #ATKREACH
  BGT ek_miss
  LDW R0, [p_hurt]
  CMP R0, #0
  BNE ek_miss
  CALL curdmg
  MOV R2, R0
  CALL hurtplayer         ; R4 = thug x (knock direction), R2 = damage
ek_miss:
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

; ---- curdmg -> R0 = punch damage for the current enemy. Scratches A0. ----
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
  SHR R0, #2
  STW R0, [BG0_SX]        ; skyline scrolls at a quarter speed (parallax); BG1 follows cam per line
  RET

; ============================ OAM (sprites) ============================
; Fighters are 64x64 sprites whose feet sit at (px+8, py+16), the bottom centre of
; the old 16x16 logic box, so movement and hit tests are unchanged. Depth: sprite
; priority 3..7 by py band (nearer = higher), shadows at 2 (above BG1, below everyone).
; OAM order: held pipe, player, NENEM enemies, NPICK pickups, then 1+NENEM shadows.
buildoam:
  MOV R0, #0
  STW R0, [OAM_INDEX]
  LDW R0, [p_y]
  CALL depthpri
  CALL emitweapon          ; held pipe first so it draws over the hero's hand (off when unarmed)
  CALL emitplayer
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
  MOV R0, #2               ; shadows: lowest sprite priority
  STW R0, [sprpri]
  LDW R0, [p_x]            ; player's shadow
  LDW R1, [p_y]
  CALL emitshadow
  MOV R7, #0
bo_s:
  MOV R3, R7
  SHL R3, #3
  LDA A1, #ENEMY
  ADD A1, R3
  LDB R0, [A1+#0]
  CMP R0, #0
  BNE bo_s_on
  CALL emitoff
  BRA bo_s_next
bo_s_on:
  LDW R0, [A1+#4]
  LDW R1, [A1+#6]
  CALL emitshadow
bo_s_next:
  ADD R7, #1
  CMP R7, #NENEM
  BLT bo_s
  RET

; ---- depthpri(R0=py): sprpri = 3 + (py-BANDTOP)/16, clamped to 3..7 ----
depthpri:
  SUB R0, #BANDTOP
  CMP R0, #0
  BGE dp_pos
  MOV R0, #0
dp_pos:
  SHR R0, #4
  ADD R0, #3
  CMP R0, #7
  BLE dp_set
  MOV R0, #7
dp_set:
  STW R0, [sprpri]
  RET

; ---- emitshadow(R0=world px, R1=py): 32x32 shadow centred under the feet, culled ----
emitshadow:
  LDW R3, [cam]
  SUB R0, R3
  SUB R0, #8               ; 32-wide shadow centred on px+8
  CMP R0, #320
  BGE es_cull
  MOV R3, R0
  ADD R3, #32
  CMP R3, #0
  BLT es_cull
  SUB R1, #12              ; shadow ellipse sits at local y 28 -> feet (py+16)
  MOV R5, #SHADOW
  MOV R6, #SZ32
  OR R6, #PB_SHADOW
  CALL emittile
  RET
es_cull:
  CALL emitoff
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
  LDW R0, [p_anim]         ; 4-frame walk cycle, 8 ticks a frame
  SHR R0, #3
  AND R0, #3
  SHL R0, #6               ; * 64 tiles
  MOV R5, #PL_WALK
  ADD R5, R0
ep_attr:
  MOV R6, #SZ64
  OR R6, #PB_PLAYER
  LDW R0, [p_face]
  AND R0, #1
  BEQ ep_emit
  ADD R6, #$40           ; hflip (face left)
ep_emit:
  LDW R0, [p_x]
  LDW R3, [cam]
  SUB R0, R3              ; world x -> screen x
  SUB R0, #FOFFX
  LDW R1, [p_y]
  SUB R1, #FOFFY
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
  SUB R0, R3              ; screen x of the logic box
  SUB R0, #FOFFX          ; -> 64x64 sprite x
  CMP R0, #320            ; off the right edge?
  BLT ee_inr
  BRA ee_cull
ee_inr:
  MOV R3, R0
  ADD R3, #64
  CMP R3, #0             ; fully off the left edge?
  BGE ee_inl
  BRA ee_cull
ee_inl:
  PUSH R0                ; save screen x across the lookups
  LDW R0, [A1+#6]
  CALL depthpri          ; this enemy's depth
  LDW R2, [bossactive]    ; during a boss wave the lone live thug is the boss
  CMP R2, #0
  BNE ee_boss
  CALL curtype          ; R0 = enemy type
  MOV R1, R0
  SHL R1, #1
  LDA A0, #TYPETILE     ; per-type walk-frame-A tile base
  ADD A0, R1
  LDW R5, [A0]
  LDA A0, #TYPEBANK     ; per-type palette bank
  ADD A0, R0
  LDB R0, [A0]
  MOV R6, #SZ64
  OR R6, R0             ; | palette bank  (grunt=2, runner=7, bruiser=8)
  BRA ee_anim
ee_boss:
  MOV R5, #BR_WALK
  MOV R6, #SZ64
  OR R6, #PB_BOSS
ee_anim:
  POP R0                ; restore screen x
  LDW R2, [eidx]        ; attacking? wind-up / punch frames replace the walk cycle
  LDA A0, #EATK
  ADD A0, R2
  LDB R2, [A0]
  CMP R2, #ATKCD
  BLE ee_walk
  CMP R5, #BR_WALK
  BNE ee_gw
  MOV R5, #BR_WIND
  BRA ee_wp
ee_gw:
  MOV R5, #GR_WIND
ee_wp:
  CMP R2, #ATKSTRIKE
  BGT ee_tile
  ADD R5, #64           ; punch frame lives 64 tiles after the wind-up
  BRA ee_tile
ee_walk:
  MOV R2, R4            ; two-frame walk keyed to world x
  SHR R2, #3
  AND R2, #1
  BEQ ee_tile
  ADD R5, #64           ; frame B lives 64 tiles after frame A
ee_tile:
  LDB R2, [A1+#2]        ; staggered -> hit-flash bank
  CMP R2, #0
  BEQ ee_face
  AND R6, #$F0
  OR R6, #PB_FLASH
ee_face:
  LDB R2, [A1+#3]        ; art faces right; facing left -> hflip
  CMP R2, #0
  BNE ee_emit
  ADD R6, #$40
ee_emit:
  LDW R1, [A1+#6]
  SUB R1, #FOFFY
  CALL emittile
  RET
ee_cull:
  CALL emitoff           ; still consume one OAM slot, just disabled
  RET

; ---- emitweapon: the pipe in the player's hand; animates through a swing ----
;   not swinging -> held at the side; wind-up -> raised diagonally above the head;
;   strike (at/after the live frame) -> thrust out front. Offsets are from px.
emitweapon:
  LDW R0, [p_weapon]
  CMP R0, #0
  BNE ew_on
  CALL emitoff
  RET
ew_on:
  MOV R5, #WEAPON        ; defaults: held pose, at the front hand
  MOV R2, #8             ; x offset from the player
  MOV R4, #14            ; raise (subtracted from py)
  LDW R0, [p_punch]      ; mid-swing?
  CMP R0, #0
  BEQ ew_face
  LDW R1, [p_wswing]
  CMP R1, #0
  BEQ ew_face            ; a bare-fist swing -> just hold the pipe
  CMP R0, #PUNCHHIT
  BLE ew_strike          ; at/after the live frame -> thrust forward
  MOV R5, #WEAPON_UP     ; wind-up: raised on the diagonal, over the shoulder
  MOV R2, #2
  MOV R4, #40
  BRA ew_face
ew_strike:
  MOV R5, #WEAPON        ; strike: thrust out at shoulder height with the fist
  MOV R2, #26
  MOV R4, #28
ew_face:
  LDW R0, [p_x]
  LDW R1, [p_face]
  AND R1, #1
  BEQ ew_right
  SUB R0, R2             ; facing left: mirror the offset + hflip
  MOV R6, #SZ16
  OR R6, #PB_PICK
  OR R6, #$40
  BRA ew_xpos
ew_right:
  ADD R0, R2
  MOV R6, #SZ16
  OR R6, #PB_PICK
ew_xpos:
  LDW R3, [cam]
  SUB R0, R3
  LDW R1, [p_y]
  SUB R1, R4             ; up to hand height (raised further in the wind-up)
  CALL emittile          ; same depth as the player (sprpri still holds it)
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
  PUSH R0
  LDW R0, [A1+#4]
  CALL depthpri
  POP R0
  LDW R1, [A1+#4]        ; y
  MOV R6, #SZ16
  OR R6, #PB_PICK
  CALL emittile
  RET
epk_cull:
  CALL emitoff
  RET

; ---- emittile(R0=px, R1=py, R5=tile, R6=attrLo): one enabled descriptor at [sprpri] ----
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
  MOV R2, R5
  SHR R2, #8
  STB R2, [OAM_DATA]      ; tile hi
  STB R6, [OAM_DATA]      ; attr lo
  LDW R2, [sprpri]
  OR R2, #$80
  STB R2, [OAM_DATA]      ; attr hi: enable | priority
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

; ---- hpcell(R0=col, R2=tile): a HUD cell on BG1 row 1, palette 0 (HP / weapon) ----
hpcell:
  MOV R1, #1
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

; ---- drawbosshp: a red bar (row 2) of one cell per boss HP point remaining ----
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
  MOV R1, #2             ; HUD row 2
  MOV R3, #0
  CALL hudtile
  ADD R4, #1
  CMP R4, #BOSSBAR
  BLT bh_lp
  RET

; ---- huddigit(R0=value 0..9, R4=col): one digit on BG1 row 1 (font palette 3) ----
huddigit:
  MOV R2, R0
  ADD R2, #DIGIT
  MOV R0, R4
  MOV R1, #1
  MOV R3, #3
  CALL hudtile
  RET

; ---- hudprint(A1=string, R4=col): draw text on BG1 row 1 (font palette 3) ----
hudprint:
hl_lp:
  LDB R2, [A1]
  CMP R2, #$FF
  BEQ hl_done
  CMP R2, #26
  BEQ hl_adv
  ADD R2, #FONT
  MOV R0, R4
  MOV R1, #1
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

; ---- clearhp: blank the HUD rows 0-2 (HP bar + weapon widget + boss bar) ----
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
  CMP R5, #3
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

; ---- copymaps: both BG maps from ROM (64x28 cells each). DMA_DST is 16-bit and the
;      maps live at VRAM $10000/$14000, so they go through the VRAM port. ----
copymaps:
  MOV R0, #0
  STB R0, [VRAM_ADDR]
  STB R0, [VRAM_ADDR+1]
  MOV R0, #1
  STB R0, [VRAM_ADDR+2]     ; $10000: BG0 (skyline)
  LDA A0, #mapdata
  CALL cpmap
  MOV R0, #0
  STB R0, [VRAM_ADDR]
  MOV R0, #$40
  STB R0, [VRAM_ADDR+1]
  MOV R0, #1
  STB R0, [VRAM_ADDR+2]     ; $14000: BG1 (street)
  CALL cpmap               ; A0 carries on into the BG1 half
  RET
cpmap:
  MOV R1, #7168             ; 64 x 28 cells x 4 bytes
cpm_lp:
  LDB R2, [A0]
  STB R2, [VRAM_DATA]
  INC A0
  SUB R1, #1
  BNE cpm_lp
  RET

; ---- settile(R0=tileX, R1=tileY, R2=tile, R3=palette): write one BG1 map cell ----
settile:
  MOV R6, R1
  SHL R6, #8              ; tileY*256
  MOV R7, R0
  SHL R7, #2             ; tileX*4
  ADD R6, R7             ; byte offset within the map (map base $10000)
  STB R6, [VRAM_ADDR]
  MOV R7, R6
  SHR R7, #8
  ADD R7, #$40
  STB R7, [VRAM_ADDR+1]
  MOV R7, #1
  STB R7, [VRAM_ADDR+2]   ; VRAM $14000 (BG1) + offset
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

; ---- clearrows(R5=first row, R6=end row, exclusive): blank 40 visible BG1 cells per row ----
clearrows:
  STW R6, [svrem]
cr_y:
  MOV R4, #0
cr_x:
  MOV R0, R4
  MOV R1, R5
  MOV R2, #0
  MOV R3, #0
  CALL settile
  ADD R4, #1
  CMP R4, #40
  BLT cr_x
  ADD R5, #1
  LDW R6, [svrem]
  CMP R5, R6
  BLT cr_y
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

; ============================ save RAM (best-kills) ============================
; ---- loadsave: restore best-kills from cartridge save RAM. Fresh (zeroed) save
;      RAM carries no marker, so best starts at 0. ----
loadsave:
  LDW R0, [SV_MAG]
  MOV R1, #SVMAGIC
  CMP R0, R1
  BNE ld_fresh
  LDW R0, [SV_BEST]
  STW R0, [best]
  RET
ld_fresh:
  MOV R0, #0
  STW R0, [best]
  RET

; ---- savebest: if this run's kills beat the stored best, update it, write a
;      coherent record into save RAM, then poke SAVECOMMIT so the host persists it. ----
savebest:
  LDW R0, [kills]
  LDW R1, [best]
  CMP R0, R1
  BLS sv_done              ; kills <= best -> no new record (unsigned)
  STW R0, [best]
  MOV R1, #SVMAGIC
  STW R1, [SV_MAG]
  STW R0, [SV_BEST]
  MOV R1, #1
  STB R1, [SAVECOMMIT]     ; record complete -> host persists save RAM
sv_done:
  RET

; ---- drawnum3(R0=value 0..999, R4=col, R5=row): three white digits on BG0.
; (on BG1)
;      Uses DIVU (dividend R1:R0 -> quotient R0, remainder R1); settile keeps R4/R5. ----
drawnum3:
  MOV R1, #0               ; high word of the dividend
  MOV R2, #100
  DIVU R0, R2              ; R0 = hundreds, R1 = value % 100
  STW R1, [svrem]
  MOV R2, R0
  ADD R2, #DIGIT
  MOV R0, R4
  MOV R1, R5
  MOV R3, #3
  CALL settile            ; hundreds at (col, row)
  LDW R0, [svrem]
  MOV R1, #0
  MOV R2, #10
  DIVU R0, R2             ; R0 = tens, R1 = ones
  STW R1, [svrem]
  MOV R2, R0
  ADD R2, #DIGIT
  MOV R0, R4
  ADD R0, #1
  MOV R1, R5
  MOV R3, #3
  CALL settile           ; tens at (col+1, row)
  LDW R0, [svrem]
  MOV R2, R0
  ADD R2, #DIGIT
  MOV R0, R4
  ADD R0, #2
  MOV R1, R5
  MOV R3, #3
  CALL settile           ; ones at (col+2, row)
  RET

drawtitle:
  CALL menureset
  MOV R0, #0
  CALL setlevelpal         ; title always wears stage-1 colours (sunset)
  CALL menubg              ; skyline + street along the bottom
  LDA A1, #sTITLE1
  MOV R4, #17
  MOV R5, #4
  CALL print
  LDA A1, #sTITLE2
  MOV R4, #17
  MOV R5, #6
  CALL print
  LDA A1, #sTAG
  MOV R4, #14
  MOV R5, #9
  CALL print
  LDA A1, #sSTART
  MOV R4, #15
  MOV R5, #11
  CALL print
  LDA A1, #sBEST           ; per-browser high score, restored from save RAM
  MOV R4, #16
  MOV R5, #13
  CALL print
  LDW R0, [best]
  MOV R4, #21
  MOV R5, #13
  CALL drawnum3
  CALL titlesprites        ; hero vs. thugs + boss lineup
  RET

; ---- menubg: full maps, then clear the street's upper rows so the skyline shows ----
menubg:
  CALL copymaps
  MOV R5, #2
  MOV R6, #15              ; keep rows 15+ (sidewalk + road)
  CALL clearrows
  RET

; ---- fig(R0=x, R1=y, R5=tile, R6=attrLo): a 64x64 lineup sprite at priority 5 ----
fig:
  MOV R2, #5
  STW R2, [sprpri]
  CALL emittile
  RET

; ---- titlesprites: a static cast lineup standing on the street ----
titlesprites:
  MOV R0, #0
  STW R0, [OAM_INDEX]
  MOV R0, #16            ; hero, facing right
  MOV R1, #128
  MOV R5, #PL_WALK
  MOV R6, #SZ64
  OR R6, #PB_PLAYER
  CALL fig
  MOV R0, #84            ; a pipe on the ground
  MOV R1, #180
  MOV R5, #WEAPON
  MOV R6, #SZ16
  OR R6, #PB_PICK
  CALL fig
  MOV R0, #104           ; food on the ground
  MOV R1, #180
  MOV R5, #FOOD
  MOV R6, #SZ16
  OR R6, #PB_PICK
  CALL fig
  MOV R0, #126           ; grunt, facing the hero
  MOV R1, #130
  MOV R5, #GR_WALK
  MOV R6, #$72           ; size64 | hflip | bank 2
  CALL fig
  MOV R0, #172           ; runner
  MOV R1, #126
  MOV R5, #GR_WALK+64
  MOV R6, #$77
  CALL fig
  MOV R0, #214           ; bruiser
  MOV R1, #130
  MOV R5, #BR_WALK
  MOV R6, #$78
  CALL fig
  MOV R0, #256           ; the boss
  MOV R1, #126
  MOV R5, #BR_WALK+64
  MOV R6, #$76
  CALL fig
  RET

drawwin:
  CALL menureset
  CALL menubg
  LDA A1, #sWIN
  MOV R4, #16
  MOV R5, #5
  CALL print
  LDA A1, #sSTART
  MOV R4, #15
  MOV R5, #9
  CALL print
  CALL winsprites
  RET

; ---- winsprites: hero stands tall with the pipe raised; the gang lies beaten ----
winsprites:
  MOV R0, #0
  STW R0, [OAM_INDEX]
  MOV R0, #76            ; pipe raised in victory (index 0: over the hero)
  MOV R1, #118
  MOV R5, #WEAPON_UP
  MOV R6, #SZ16
  OR R6, #PB_PICK
  CALL fig
  MOV R0, #40            ; hero, standing
  MOV R1, #128
  MOV R5, #PL_WALK
  MOV R6, #SZ64
  OR R6, #PB_PLAYER
  CALL fig
  MOV R0, #120           ; beaten thugs
  MOV R1, #136
  MOV R5, #GR_DOWN
  MOV R6, #$32
  CALL fig
  MOV R0, #170
  MOV R1, #150
  MOV R5, #GR_DOWN
  MOV R6, #$37
  CALL fig
  MOV R0, #236           ; beaten boss
  MOV R1, #140
  MOV R5, #BR_DOWN
  MOV R6, #$36
  CALL fig
  RET

drawover:
  CALL menureset
  CALL menubg
  LDA A1, #sOVER
  MOV R4, #15
  MOV R5, #5
  CALL print
  LDA A1, #sSTART
  MOV R4, #15
  MOV R5, #9
  CALL print
  LDA A1, #sBEST           ; show the (possibly just-updated) best-kills record
  MOV R4, #16
  MOV R5, #11
  CALL print
  LDW R0, [best]
  MOV R4, #21
  MOV R5, #11
  CALL drawnum3
  CALL oversprites
  RET

; ---- oversprites: the hero is down; the gang stands over him ----
oversprites:
  MOV R0, #0
  STW R0, [OAM_INDEX]
  MOV R0, #130           ; downed hero, centre
  MOV R1, #144
  MOV R5, #PL_DOWN
  MOV R6, #SZ64
  OR R6, #PB_PLAYER
  CALL fig
  MOV R0, #70            ; thug standing over him, facing right
  MOV R1, #128
  MOV R5, #GR_WALK
  MOV R6, #$32
  CALL fig
  MOV R0, #196           ; thug on the right, facing left
  MOV R1, #130
  MOV R5, #GR_WALK+64
  MOV R6, #$77
  CALL fig
  MOV R0, #248           ; the boss looms
  MOV R1, #124
  MOV R5, #BR_WALK
  MOV R6, #$76
  CALL fig
  RET

; ---- drawinter: "STAGE n / GET READY" over the next stage's sky ----
drawinter:
  CALL menureset
  LDW R0, [level]          ; preview the upcoming stage's colours
  ADD R0, #1
  CALL setlevelpal
  CALL menubg
  LDA A1, #sSTAGE
  MOV R4, #16
  MOV R5, #6
  CALL print
  LDW R0, [level]          ; upcoming stage (level is the one just cleared), 1-based
  ADD R0, #2
  MOV R4, #22
  MOV R5, #6
  CALL printdigit
  LDA A1, #sREADY
  MOV R4, #15
  MOV R5, #9
  CALL print
  RET

; ---- printdigit(R0=value, R4=col, R5=row): one digit on BG1 in the font palette ----
printdigit:
  MOV R2, R0
  ADD R2, #DIGIT
  MOV R0, R4
  MOV R1, R5
  MOV R3, #3
  CALL settile
  RET

; ============================ character creator ============================
; The player's bank layout is fixed (outline, skin x3, hair x2, top x3, legs x3,
; shoes x2, trim), so every body takes every colour pick. A body is 6 frames DMA'd
; over PL_WALK..PL_DOWN; colours are ramps from charpal copied into the bank.

; ---- applychar: picks -> body tiles in VRAM + the player palette bank ----
applychar:
  LDB R0, [c_body]
  MOV R1, R0
  SHL R1, #1
  ADD R1, R0               ; * 3 (DA entries)
  LDA A0, #BODYTAB
  ADD A0, R1
  LDADDR A0, [A0]
  MOV R0, #PL_DST
  STW R0, [DMA_DST]
  MOV R0, #PL_BYTES
  STW R0, [DMA_LEN]
  MOV R0, #0
  STB R0, [DMA_MODE]       ; VRAM
  CALL dmago
  LDA A1, #CHARPAL
  LDA A0, #charpal+CP_OL
  MOV R2, #1
  CALL cpwords             ; outline
  LDB R0, [c_body+1]
  MOV R1, #6
  MULU R0, R1
  LDA A0, #charpal
  ADD A0, R0
  MOV R2, #3
  CALL cpwords             ; skin ramp
  LDB R0, [c_body+2]
  MOV R1, #4
  MULU R0, R1
  LDA A0, #charpal+CP_HAIR
  ADD A0, R0
  MOV R2, #2
  CALL cpwords             ; hair ramp
  LDB R0, [c_body+3]
  MOV R1, #6
  MULU R0, R1
  LDA A0, #charpal+CP_TOP
  ADD A0, R0
  MOV R2, #3
  CALL cpwords             ; top ramp
  LDB R0, [c_body+4]
  MOV R1, #6
  MULU R0, R1
  LDA A0, #charpal+CP_LEGS
  ADD A0, R0
  MOV R2, #3
  CALL cpwords             ; trousers ramp
  LDB R0, [c_body+5]
  MOV R1, #4
  MULU R0, R1
  LDA A0, #charpal+CP_SHOES
  ADD A0, R0
  MOV R2, #2
  CALL cpwords             ; shoes ramp
  LDA A0, #charpal+CP_TRIM
  MOV R2, #1
  CALL cpwords             ; trim
  LDA A0, #CHARPAL
  MOV R0, #PB9PAL          ; bank 9 entries 1..15
  MOV R1, #30
  CALL dmapal
  RET

; ---- cpwords(A0=src, A1=dst, R2=count): copy words; A1 ends past the last ----
cpwords:
  LDW R0, [A0]
  STW R0, [A1]
  ADD A0, #2
  ADD A1, #2
  SUB R2, #1
  BNE cpwords
  RET

; ---- loadchar: picks from save RAM (any out-of-range pick -> 0), then apply ----
loadchar:
  LDA A0, #SV_CHAR
  LDA A1, #c_body
  LDA A2, #CHCOUNT
  MOV R2, #CROWS
  LDW R0, [SV_MAG]
  MOV R1, #SVMAGIC
  CMP R0, R1
  BEQ lc_lp
  LDA A0, #CHZERO          ; no save yet: the defaults
lc_lp:
  LDB R0, [A0]
  LDB R1, [A2]
  CMP R0, R1
  BLT lc_ok
  MOV R0, #0
lc_ok:
  STB R0, [A1]
  INC A0
  INC A1
  INC A2
  SUB R2, #1
  BNE lc_lp
  CALL applychar
  RET

; ---- savechar: write the picks + a coherent record, then commit ----
savechar:
  LDA A0, #c_body
  LDA A1, #SV_CHAR
  MOV R2, #CROWS
sc_lp:
  LDB R0, [A0]
  STB R0, [A1]
  INC A0
  INC A1
  SUB R2, #1
  BNE sc_lp
  LDW R0, [best]
  STW R0, [SV_BEST]
  MOV R1, #SVMAGIC
  STW R1, [SV_MAG]
  MOV R1, #1
  STB R1, [SAVECOMMIT]
  RET

; ---- drawcreator: sky + road backdrop, labels, arrows, live colour swatches ----
drawcreator:
  CALL menureset
  MOV R0, #0
  CALL setlevelpal
  CALL copymaps
  MOV R5, #2
  MOV R6, #20              ; keep the curb and road (rows 20+)
  CALL clearrows
  CALL clearoam
  LDA A1, #sCREATE
  MOV R4, #11
  MOV R5, #3
  CALL print
  LDA A1, #sLABELS         ; six labels, END-separated
  MOV R5, #CROW0
dc_lab:
  MOV R4, #CLAB
  CALL print
  INC A1                   ; past this label's END
  ADD R5, #2
  CMP R5, #CROWEND
  BLT dc_lab
  MOV R5, #CROW0
dc_arr:
  MOV R0, #CARL
  MOV R1, R5
  MOV R2, #ARROWL
  MOV R3, #PB_FONT
  CALL settile
  MOV R0, #CARR
  MOV R1, R5
  MOV R2, #ARROWR
  MOV R3, #PB_FONT
  CALL settile
  ADD R5, #2
  CMP R5, #CROWEND
  BLT dc_arr
  LDA A1, #SWTAB           ; swatches: (first colour, count) per colour row
  MOV R5, #CROW0+2
dc_sw:
  LDB R2, [A1]
  ADD R2, #SOLID-1
  LDB R4, [A1+#1]
  INC A1
  INC A1
  MOV R0, #CARL+2
dc_swc:
  PUSH R0
  MOV R1, R5
  MOV R3, #PB_PLAYER       ; drawn in the player's own bank, so they track the picks
  PUSH R2
  CALL settile
  POP R2
  POP R0
  ADD R0, #1
  ADD R2, #1
  SUB R4, #1
  BNE dc_swc
  ADD R5, #2
  CMP R5, #CROWEND
  BLT dc_sw
  CALL drawbodyname
  LDA A1, #sSTART
  MOV R4, #15
  MOV R5, #25
  CALL print
  MOV R0, #0
  STW R0, [c_sel]
  STW R0, [p_anim]
  STW R0, [p_punch]
  MOV R0, #5
  STW R0, [state]
  RET

; ---- drawbodyname: blank the body value cells, print the current body's name ----
drawbodyname:
  MOV R4, #CARL+1
dbn_clr:
  MOV R0, R4
  MOV R1, #CROW0
  MOV R2, #0
  MOV R3, #0
  CALL settile
  ADD R4, #1
  CMP R4, #CARR
  BLT dbn_clr
  LDB R0, [c_body]
  MOV R1, R0
  SHL R1, #1
  ADD R1, R0
  LDA A0, #NAMETAB
  ADD A0, R1
  LDADDR A1, [A0]
  MOV R4, #CARL+2
  MOV R5, #CROW0
  CALL print
  RET

; ---- creatorframe: Up/Down row, Left/Right value, A test punch, Start fights ----
creatorframe:
  LDW R0, [in_now]
  LDW R1, [in_prev]
  NOT R1
  AND R1, R0
  STW R1, [c_edge]
  MOV R0, R1
  AND R0, #START
  BEQ cf_up
  CALL savechar
  MOV R0, #120
  CALL sfxblip
  CALL newgame
  RET
cf_up:
  LDW R1, [c_edge]
  MOV R0, R1
  AND R0, #UP
  BEQ cf_dn
  LDW R0, [c_sel]
  CMP R0, #0
  BNE cf_up1
  MOV R0, #CROWS
cf_up1:
  SUB R0, #1
  STW R0, [c_sel]
  MOV R0, #200
  CALL sfxblip
cf_dn:
  LDW R1, [c_edge]
  MOV R0, R1
  AND R0, #DOWN
  BEQ cf_lr
  LDW R0, [c_sel]
  ADD R0, #1
  CMP R0, #CROWS
  BLT cf_dn1
  MOV R0, #0
cf_dn1:
  STW R0, [c_sel]
  MOV R0, #200
  CALL sfxblip
cf_lr:
  LDW R1, [c_edge]
  MOV R0, R1
  AND R0, #RIGHT
  BEQ cf_left
  MOV R2, #1
  CALL cstep
cf_left:
  LDW R1, [c_edge]
  MOV R0, R1
  AND R0, #LEFT
  BEQ cf_a
  MOV R2, #0
  CALL cstep
cf_a:
  LDW R1, [c_edge]
  MOV R0, R1
  AND R0, #ABTN
  BEQ cf_anim
  MOV R0, #PUNCHT
  STW R0, [p_punch]
  MOV R0, #180
  CALL sfxblip
cf_anim:
  LDW R0, [p_anim]
  ADD R0, #1
  STW R0, [p_anim]
  LDW R0, [p_punch]
  CMP R0, #0
  BEQ cf_oam
  SUB R0, #1
  STW R0, [p_punch]
cf_oam:
  MOV R0, #0
  STW R0, [OAM_INDEX]
  LDW R1, [c_sel]          ; cursor: a font arrow left of the selected label
  SHL R1, #4
  ADD R1, #CROWPY
  MOV R0, #CURX
  LDW R2, [p_anim]
  AND R2, #16
  BEQ cf_cur
  ADD R0, #2               ; nudge back and forth
cf_cur:
  MOV R5, #ARROWR
  MOV R6, #PB_FONT         ; 8x8
  CALL fig
  LDW R5, [p_punch]        ; the fighter, walking on the spot
  CMP R5, #0
  BEQ cf_walk
  MOV R5, #PL_PUNCH
  BRA cf_fig
cf_walk:
  LDW R0, [p_anim]
  SHR R0, #3
  AND R0, #3
  SHL R0, #6
  MOV R5, #PL_WALK
  ADD R5, R0
cf_fig:
  MOV R0, #PVX
  MOV R1, #PVY
  MOV R6, #SZ64
  OR R6, #PB_PLAYER
  CALL fig
  MOV R0, #2
  STW R0, [sprpri]
  MOV R0, #PVX+FOFFX
  MOV R1, #PVY+FOFFY
  CALL emitshadow
  RET

; ---- cstep(R2=1 next, 0 previous): change the selected row's pick, with wrap ----
cstep:
  LDW R3, [c_sel]
  LDA A0, #c_body
  ADD A0, R3
  LDA A1, #CHCOUNT
  ADD A1, R3
  LDB R0, [A0]
  LDB R1, [A1]
  CMP R2, #0
  BEQ cs_prev
  ADD R0, #1
  CMP R0, R1
  BLT cs_set
  MOV R0, #0
  BRA cs_set
cs_prev:
  CMP R0, #0
  BNE cs_dec
  MOV R0, R1
cs_dec:
  SUB R0, #1
cs_set:
  STB R0, [A0]
  CALL applychar
  MOV R0, #160
  CALL sfxblip
  LDW R3, [c_sel]
  CMP R3, #0
  BNE cs_done
  CALL drawbodyname
cs_done:
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
  CALL copymaps            ; skyline + street
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

; ---- setlevelpal(R0=level): this stage's sky gradient -> SKYTAB (read by hblank),
;      and its recoloured banks: 1 (sky/skyline), 2 (grunt), 10 (brick). ----
setlevelpal:
  MOV R1, #LEVELREC
  MULU R0, R1              ; R0 = level * record size
  LDA A0, #levels
  ADD A0, R0
  LDA A1, #SKYTAB
  MOV R1, #224
slp_sky:
  LDW R2, [A0]
  STW R2, [A1]
  ADD A0, #2
  ADD A1, #2
  SUB R1, #1
  BNE slp_sky
  MOV R0, #34              ; bank 1 entries 1..13 (palette byte offset 17*2)
  MOV R1, #26
  CALL dmapal
  ADD A0, #26
  MOV R0, #66              ; bank 2 entries 1..15
  MOV R1, #30
  CALL dmapal
  ADD A0, #30
  MOV R0, #322             ; bank 10 entries 1..15
  MOV R1, #30
  CALL dmapal
  RET

; ---- dmapal(A0=src, R0=palette byte offset, R1=length): DMA into the palette ----
dmapal:
  STW R0, [DMA_DST]
  STW R1, [DMA_LEN]
  MOV R0, #2
  STB R0, [DMA_MODE]
  ; fall through to dmago
; ---- dmago(A0=src): store the 24-bit source and start the transfer ----
dmago:
  PUSHA A0                 ; no store-from-An: spill it, read back as two words
  POP R0                   ; source bits 0-15
  POP R1                   ; source bits 16-23 (+ the slot's zero pad byte)
  STW R0, [DMA_SRC]
  STB R1, [DMA_SRC+2]
  MOV R0, #1
  STB R0, [DMA_CTRL]
  RET

; ---- loadart: every tile into VRAM (one DMA), the full palette, stage-1 sky ----
loadart:
  LDA A0, #tiledata
  MOV R0, #0
  STW R0, [DMA_DST]
  MOV R0, #tiledataend-tiledata
  STW R0, [DMA_LEN]
  MOV R0, #0
  STB R0, [DMA_MODE]       ; VRAM
  CALL dmago
  LDA A0, #paldata
  MOV R0, #0
  MOV R1, #512
  CALL dmapal              ; all 256 entries
  MOV R0, #0
  CALL setlevelpal
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
  LDA A2, #EATK          ; EATK[R7] = 0 (not mid-attack)
  ADD A2, R7
  MOV R1, #0
  STB R1, [A2]
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
  MOV R0, R7            ; y = BANDTOP + (i&3)*24  (four rows down the band)
  AND R0, #3
  MOV R2, R0
  SHL R2, #4           ; row*16
  SHL R0, #3           ; row*8
  ADD R2, R0           ; row*24
  MOV R0, R2
  ADD R0, #BANDTOP
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
  LDA A2, #ETYPE          ; boss uses the grunt profile (steady speed, 1 punch dmg)
  MOV R0, #GRUNT
  STB R0, [A2]
  MOV R0, #0
  STB R0, [EATK]          ; the boss sits in slot 0
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
; ============================ data ============================
; ---- enemy type stats, indexed by type (GRUNT, RUNNER, BRUISER) ----
TYPEHP:                          ; hit points
  DB 3, 2, 6
TYPESPD:                         ; chase speed (px/frame; bruiser also rests alt frames)
  DB 1, 2, 1
TYPEDMG:                         ; punch damage
  DB 1, 1, 2
TYPEBANK:                        ; sprite palette bank
  DB 2, 7, 8
TYPETILE:                        ; walk-frame-A tile base (grunt + runner share a rig, recoloured)
  DW GR_WALK, GR_WALK, BR_WALK

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

; ---- character creator tables ----
CHCOUNT:                         ; choices per row: bodies, skins, hair, tops, trousers, shoes
  DB NBODY, 6, 8, 10, 10, 8
CHZERO:                          ; default picks (no save yet)
  DB 0, 0, 0, 0, 0, 0
SWTAB:                           ; per colour row: first bank colour, swatch width
  DB 2, 3, 5, 2, 7, 3, 10, 3, 13, 2
BODYTAB:                         ; ROM address of each body's 6 frames
  DA bodies, bodies+PL_BYTES, bodies+24576, bodies+36864
  DA bodies+49152, bodies+61440, bodies+73728, bodies+86016
NAMETAB:                         ; body names (keep in step with BODIES in the art tool)
  DA nRIO, nMARA, nTANK, nKENJI, nZED, nFOX, nLIN, nWOLF
nRIO:
  DB R, I, O, END
nMARA:
  DB M, A, R, A, END
nTANK:
  DB T, A, N, K, END
nKENJI:
  DB K, E, N, J, I, END
nZED:
  DB Z, E, D, END
nFOX:
  DB F, O, X, END
nLIN:
  DB L, I, N, END
nWOLF:
  DB W, O, L, F, END
sCREATE:
  DB C, R, E, A, T, E, SPC, Y, O, U, R, SPC, F, I, G, H, T, E, R, END
sLABELS:
  DB B, O, D, Y, END
  DB S, K, I, N, END
  DB H, A, I, R, END
  DB T, O, P, END
  DB L, E, G, S, END
  DB S, H, O, E, S, END

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
sBEST:
  DB B, E, S, T, SPC, END

; ---- art (examples/streetbrawl/gen_art.js) ----
levels:                          ; NLEVELS x LEVELREC: 224-word sky, banks 1 (13 words), 2 + 10 (15 each)
  INCBIN "levels.bin"
paldata:                         ; 256 RGB555 entries
  INCBIN "pal.bin"
mapdata:                         ; BG0 then BG1: 64x28 cells x 4 bytes
  INCBIN "maps.bin"
charpal:                         ; creator colour ramps (see CP_* offsets)
  INCBIN "charpal.bin"
bodies:                          ; NBODY x PL_BYTES: the selectable bodies
  INCBIN "bodies.bin"
tiledata:                        ; VRAM tiles from index 0
  INCBIN "tiles.bin"
tiledataend:
