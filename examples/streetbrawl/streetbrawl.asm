; ============================================================================
; STREET BRAWL — a Streets-of-Rage-style beat-'em-up prototype for CastlePalm
;
;   Walk your hero along a scrolling sidewalk (8-way, D-pad), throw punches (A),
;   and clear the street of thugs. Punches that land chain into a combo: jab, jab,
;   then a kick that knocks the thug off his feet. B jumps; A in the air is a flying
;   kick. Walk into a thug to grab him: A knees him (the third knee floors him), B
;   heaves him the way you hold, bowling over anyone he lands on. Floored thugs
;   skid, lie still a moment and get back up; the beaten ones blink away.
;   Each stage ends with its own boss (see "stage bosses"): Brick charges along his
;   row, Viper hops out of reach and whistles up runners, Warden leaps and slams. Enemies chase you, stagger and flash white when
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
;   Controls:  D-pad = move    A = punch / swing / knee    B = jump / throw
;              Start = begin / restart
;   Character creator (after the title): Up/Down pick a row, Left/Right change it,
;   A throws a test punch, B a test kick, Start fights. The pick is kept in save RAM.
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
BBTN  EQU 32
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
PL_KICK  EQU 1180       ; the hero's move frames: a second per-body block (see PLX_BYTES)
PL_JUMP  EQU 1244
PL_JKICK EQU 1308
PL_GRAB  EQU 1372
PL_KNEE  EQU 1436
PL_THROW EQU 1500
GR_HURT  EQU 1564       ; reeling: held in a grab, or getting back up
BR_HURT  EQU 1628
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
PL_BYTES EQU 12288      ; first block of a body: 6 frames x 64 tiles x 32 bytes (PL_WALK..PL_DOWN)
PLX_BYTES EQU 12288     ; second block: 6 move frames (PL_KICK..PL_THROW)
NBODY    EQU 8
PL_DST   EQU 4096       ; PL_WALK * 32: VRAM byte offset of the player's frames
PLX_DST  EQU 37760      ; PL_KICK * 32: VRAM byte offset of the move frames
PB6PAL   EQU 194        ; palette byte offset of bank 6 entry 1 (the boss)
BRW_DST  EQU 22528      ; BR_WALK * 32  (VRAM byte offsets of the big-rig frames, for loadbr)
BRD_DST  EQU 26624      ; BR_DOWN * 32
BRWP_DST EQU 33664      ; BR_WIND * 32 (BR_PUNCH follows)
BRH_DST  EQU 52096      ; BR_HURT * 32
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
; ---- the moveset ----
COMBOWIN EQU 18         ; frames after a landed hit in which the next A chains the combo
PUNCHRX  EQU 36         ; fist hitbox reaches this far in front of px
KICKT    EQU 16         ; combo finisher (kick) length
KICKHIT  EQU 10         ; its live frame
KICKDMG  EQU 2
KICKRX   EQU 8          ; extra reach of the kick
JUMPV    EQU 6          ; take-off speed (px/frame up); gravity takes 1 every other frame
JKDMG    EQU 2          ; flying kick
JKRX     EQU 4          ; its extra reach
JKHIGH   EQU 10         ; above this height thug punches pass under you
GRABRX   EQU 18         ; walk into a thug this close (x, in front) ...
GRABRY   EQU 6          ; ... on this row to grab him
GRABDX   EQU 22         ; held thug sits this far in front
GRABT    EQU 110        ; he struggles free after this long
GRABCOOL EQU 30         ; no re-grab for this long after a release
KNEET    EQU 14
KNEEHIT  EQU 8
KNEEDMG  EQU 1
KNEEMAX  EQU 3          ; the third knee floors him
THROWT   EQU 16
THROWHIT EQU 9
THROWDMG EQU 3          ; to the thrown thug, on landing
BOWLDMG  EQU 2          ; to anyone the thrown body lands on
THROWVX  EQU 4
THROWVZ  EQU 3
THROWZ   EQU 22         ; released at chest height
KDVX     EQU 2          ; knockdown skid
KDVZ     EQU 4
DOWNT    EQU 50         ; lying on the street before getting up
GETUPT   EQU 14         ; last frames of DOWNT show the reeling (getting-up) frame
DIET     EQU 44         ; a beaten thug lies (blinking) this long, then he's gone
KBF      EQU 4          ; a normal hit shoves the thug back only this many frames
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
KB       EQU 1          ; enemy knockback px / frame for the first KBF frames of a stagger
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
BOSSBAR  EQU 18         ; boss HP-bar cells (the bar scales to the boss's health)
; ---- stage bosses (kind = stage): tuning for their special moves ----
BOSSCOOL0 EQU 100       ; frames before a boss's first special
BRICKREV EQU 36         ; Brick revs up (flashing) this long ...
BRICKV   EQU 5          ; ... charges at this speed ...
BRICKRUN EQU 80         ; ... for at most this long ...
BRICKDMG EQU 3          ; ... hurting this much if he runs you over ...
BRICKDAZE EQU 70        ; ... then stands dazed this long after the crash
BRICKCOOL EQU 170
BRICKBACK EQU 50        ; when you're close he first backs off this long (at most) ...
BRICKBACKV EQU 2        ; ... at this speed
VIPHOPX  EQU 3          ; Viper's hop back: px/frame ...
VIPHOPV  EQU 5          ; ... and take-off speed
VIPCOOL  EQU 70
VIPTH1   EQU 16         ; health at which Viper whistles up runners (twice)
VIPTH2   EQU 8
WARDCROUCH EQU 26       ; Warden crouches (flashing) this long ...
WARDLEAP EQU 16         ; ... is in the air this long ...
WARDWAVE EQU 46         ; ... and his landing hurts within this x range ...
WARDDMG  EQU 3
WARDREC  EQU 40         ; ... then gets his breath back
WARDCOOL EQU 160
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
p_jz     EQU $000176    ; height above the street (0 = grounded)
p_jvz    EQU $000178    ; vertical speed while airborne (+ = up)
p_combo  EQU $00017A    ; combo step: 0, 1 jabs; 2 = the next A is the kick
p_chain  EQU $00017C    ; frames left to chain the next hit
p_hitany EQU $00017E    ; the current swing connected
p_atk    EQU $000180    ; current attack: 0 jab, 1 kick, 2 pipe, 3 knee, 4 throw, 5 flying kick
p_grab   EQU $000182    ; held thug's slot + 1 (0 = hands free)
p_gtime  EQU $000184    ; grab time left
p_gknee  EQU $000186    ; knees landed in this grab
p_gcool  EQU $000188    ; re-grab cooldown
p_jkick  EQU $00018A    ; flying kick out (until landing)
p_kd     EQU $00018C    ; scratch: this hit knocks down
b_kind   EQU $000190    ; boss: which one (= stage)
b_mode   EQU $000192    ; 0 normal AI, else the special move's phase
b_tmr    EQU $000194
b_cool   EQU $000196    ; frames until the next special
b_vx     EQU $000198
b_vy     EQU $00019A    ; (Viper: hop speed; Warden: leap dy)
b_frame  EQU $00019C    ; 0 normal frames, 1 wind-up, 2 punch, 3 reeling
b_flash  EQU $00019E    ; nonzero: flash the telegraph this frame (bit 2 used)
b_calls  EQU $0001A0    ; Viper: runners called so far
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
EX       EQU $000300    ; NENEM slots x 16 bytes: knockdown / grab physics (A3 points here)
;   +0 st (0 normal, 1 held, 2 airborne, 3 down)  +1 timer (down)  +2 z(u16, height)
;   +4 vz(s16)  +6 vx(s16)  +8 thrown  +9 hit by this flying kick  +10 damage on landing
;   +11 dying (beaten: blinks out at the end of the down timer)
ST_HELD  EQU 1
ST_AIR   EQU 2
ST_DOWN  EQU 3

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
  CALL jumpupdate
  CALL attackupdate
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
  LDW R0, [p_grab]         ; holding a thug: feet planted
  CMP R0, #0
  BEQ dm_free
  RET
dm_free:
  LDW R7, [p_jz]           ; R7 != 0 while airborne: no stepping up/down the street
  LDW R0, [p_jvz]
  OR R7, R0
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
  CMP R7, #0
  BNE dm_clx
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

; ============================ the moveset ============================
; A on the ground: jab, jab, kick. A landed jab opens a COMBOWIN window for the
; next A; the third hit is the kick, which floors the thug. B jumps; A in the air
; puts out a flying kick until you land. Walk into a thug to grab him: A knees,
; B throws (the way you hold). Knocked-down thugs are run by eair / edown below.

; ---- jumpupdate: rise and fall; gravity takes 1 px/frame every other frame ----
jumpupdate:
  LDW R0, [p_jz]
  LDW R1, [p_jvz]
  MOV R2, R0
  OR R2, R1
  BEQ ju_done              ; on the ground
  ADD R0, R1
  LDW R2, [gtick]
  AND R2, #1
  BEQ ju_g
  SUB R1, #1
ju_g:
  CMP R0, #0
  BGT ju_store
  MOV R0, #0               ; landed
  STW R0, [p_jz]
  STW R0, [p_jvz]
  STW R0, [p_jkick]
  STW R0, [p_combo]
  MOV R0, #380
  CALL sfxblip
  RET
ju_store:
  STW R0, [p_jz]
  STW R1, [p_jvz]
ju_done:
  RET

; ---- attackupdate: read A/B and run the current move ----
attackupdate:
  LDW R0, [in_prev]        ; R5 = buttons newly pressed this frame (kept through)
  NOT R0
  LDW R5, [in_now]
  AND R5, R0
  LDW R0, [p_gcool]
  CMP R0, #0
  BEQ au_gc
  SUB R0, #1
  STW R0, [p_gcool]
au_gc:
  LDW R0, [p_chain]
  CMP R0, #0
  BEQ au_ch
  SUB R0, #1
  STW R0, [p_chain]
au_ch:
  LDW R0, [p_grab]
  CMP R0, #0
  BEQ au_free
  BRA grabupdate
au_free:
  LDW R0, [p_jz]
  LDW R1, [p_jvz]
  OR R0, R1
  BEQ au_ground
  MOV R0, R5               ; airborne: A puts out the flying kick (once a jump)
  AND R0, #ABTN
  BEQ au_air
  LDW R0, [p_jkick]
  CMP R0, #0
  BNE au_air
  MOV R0, #1
  STW R0, [p_jkick]
  MOV R0, #5
  STW R0, [p_atk]
  CALL clearhitf
  MOV R0, #170
  CALL sfxblip
au_air:
  LDW R0, [p_jkick]
  CMP R0, #0
  BEQ au_air2
  CALL checkhit            ; live every frame of the kick; each thug is hit once
au_air2:
  BRA au_tick
au_ground:
  LDW R0, [p_punch]
  CMP R0, #0
  BEQ au_new
  BRA au_tick              ; mid-swing: no new move yet
au_new:
  MOV R0, R5
  AND R0, #BBTN
  BEQ au_grab
  MOV R0, #JUMPV           ; B: jump
  STW R0, [p_jvz]
  MOV R0, #0
  STW R0, [p_combo]
  STW R0, [p_jkick]
  MOV R0, #300
  CALL sfxblip
  RET
au_grab:
  CALL trygrab             ; walking into a thug grabs him
  LDW R0, [p_grab]
  CMP R0, #0
  BEQ au_a
  RET
au_a:
  MOV R0, R5
  AND R0, #ABTN
  BNE au_a2
  BRA au_tick
au_a2:
  LDW R0, [p_weapon]       ; armed? -> pipe swing (no combo, but it hurts)
  CMP R0, #0
  BEQ au_fist
  SUB R0, #1
  STW R0, [p_weapon]       ; spend one swing
  MOV R0, #1
  STW R0, [p_wswing]
  MOV R0, #2
  STW R0, [p_atk]
  MOV R0, #0
  STW R0, [p_hitany]
  MOV R0, #WPNT
  STW R0, [p_punch]
  MOV R0, #150             ; pipe whoosh (lower pitch)
  CALL sfxblip
  BRA au_tick
au_fist:
  MOV R0, #0
  STW R0, [p_wswing]
  STW R0, [p_hitany]
  LDW R0, [p_chain]        ; outside the chain window -> back to the first jab
  CMP R0, #0
  BNE au_chain
  STW R0, [p_combo]
au_chain:
  LDW R0, [p_combo]
  CMP R0, #2
  BLT au_jab
  MOV R0, #1               ; third hit: the kick
  STW R0, [p_atk]
  MOV R0, #KICKT
  STW R0, [p_punch]
  MOV R0, #160
  CALL sfxblip
  BRA au_tick
au_jab:
  MOV R0, #0
  STW R0, [p_atk]
  MOV R0, #PUNCHT
  STW R0, [p_punch]
  MOV R0, #180
  CALL sfxblip
au_tick:
  LDW R0, [p_punch]
  CMP R0, #0
  BEQ au_done
  SUB R0, #1
  STW R0, [p_punch]
  CMP R0, #0
  BEQ au_end
  LDW R2, [p_atk]
  CMP R2, #3               ; knee / throw / flying kick land elsewhere
  BGE au_done
  MOV R1, #PUNCHHIT        ; the single live frame: jab / pipe ...
  CMP R2, #1
  BNE au_live
  MOV R1, #KICKHIT         ; ... or kick
au_live:
  CMP R0, R1
  BNE au_done
  CALL checkhit
  RET
au_end:                    ; swing over: a jab that landed moves the combo on
  LDW R2, [p_atk]
  CMP R2, #0
  BNE au_reset
  LDW R0, [p_hitany]
  CMP R0, #0
  BEQ au_reset
  LDW R0, [p_combo]
  ADD R0, #1
  STW R0, [p_combo]
  MOV R0, #COMBOWIN
  STW R0, [p_chain]
  RET
au_reset:
  MOV R0, #0
  STW R0, [p_combo]
  STW R0, [p_chain]
au_done:
  RET

; ---- slotptrs(R7=slot): A1 = &ENEMY[slot], A3 = &EX[slot]. Scratches R3. ----
slotptrs:
  MOV R3, R7
  SHL R3, #3
  LDA A1, #ENEMY
  ADD A1, R3
  MOV R3, R7
  SHL R3, #4
  LDA A3, #EX
  ADD A3, R3
  RET

; ---- trygrab: walking into a thug on your row, close in front, grabs him.
;      Not the boss, not a thug reeling from a hit. Keeps R5. ----
trygrab:
  LDW R0, [p_gcool]
  CMP R0, #0
  BEQ tg_c
  RET
tg_c:
  LDW R6, [in_now]         ; walking toward the way you face?
  MOV R1, #RIGHT
  LDW R0, [p_face]
  CMP R0, #0
  BEQ tg_dir
  MOV R1, #LEFT
tg_dir:
  AND R6, R1
  BNE tg_go
  RET
tg_go:
  MOV R7, #0
tg_lp:
  CALL slotptrs
  LDB R0, [A1+#0]
  CMP R0, #0
  BEQ tg_next
  CMP R7, #0               ; the boss can't be grabbed (Viper's runners can)
  BNE tg_nb
  LDW R0, [bossactive]
  CMP R0, #0
  BNE tg_next
tg_nb:
  LDB R0, [A3+#0]          ; on his feet ...
  CMP R0, #0
  BNE tg_next
  LDB R0, [A1+#2]          ; ... and not reeling
  CMP R0, #0
  BNE tg_next
  LDW R0, [A1+#6]
  LDW R1, [p_y]
  SUB R0, R1
  CALL absr0
  CMP R0, #GRABRY
  BGT tg_next
  LDW R0, [A1+#4]          ; d = how far in front of you
  LDW R1, [p_x]
  SUB R0, R1
  LDW R1, [p_face]
  CMP R1, #0
  BEQ tg_fw
  NEG R0
tg_fw:
  CMP R0, #0
  BLT tg_next
  CMP R0, #GRABRX
  BLE tg_take
tg_next:
  ADD R7, #1
  CMP R7, #NENEM
  BLT tg_lp
  RET
tg_take:
  MOV R0, #ST_HELD
  STB R0, [A3+#0]
  MOV R0, R7
  ADD R0, #1
  STW R0, [p_grab]
  MOV R0, #GRABT
  STW R0, [p_gtime]
  MOV R0, #0
  STW R0, [p_gknee]
  STW R0, [p_combo]
  STW R0, [p_wswing]
  LDA A2, #EATK            ; his swing is cut off
  ADD A2, R7
  STB R0, [A2]
  MOV R0, #220
  CALL sfxblip
  RET

; ---- grabupdate(R5=new buttons): hold, knee (A), throw (B); he breaks free in time ----
grabupdate:
  LDW R7, [p_grab]
  SUB R7, #1
  CALL slotptrs
  LDB R0, [A1+#0]          ; floored or gone -> hands free
  CMP R0, #0
  BEQ gu_free
  LDB R0, [A3+#0]
  CMP R0, #ST_HELD
  BEQ gu_hold
gu_free:
  MOV R0, #0
  STW R0, [p_grab]
  MOV R0, #GRABCOOL
  STW R0, [p_gcool]
  RET
gu_hold:
  LDW R0, [p_punch]        ; mid-knee / mid-throw?
  CMP R0, #0
  BEQ gu_input
  SUB R0, #1
  STW R0, [p_punch]
  LDW R1, [p_atk]
  CMP R1, #4
  BEQ gu_thr
  CMP R0, #KNEEHIT
  BNE gu_pinj
  CALL kneehit
gu_pinj:
  BRA gu_pin
gu_thr:
  CMP R0, #THROWHIT
  BNE gu_pin
  BRA dothrow
gu_input:
  LDW R0, [p_gtime]        ; he struggles free in the end
  SUB R0, #1
  STW R0, [p_gtime]
  BNE gu_ia
  STB R0, [A3+#0]          ; (R0 = 0) back on his feet
  BRA gu_free
gu_ia:
  MOV R0, R5
  AND R0, #ABTN
  BEQ gu_ib
  MOV R0, #3               ; A: knee
  STW R0, [p_atk]
  MOV R0, #KNEET
  STW R0, [p_punch]
  MOV R0, #200
  CALL sfxblip
  BRA gu_pin
gu_ib:
  MOV R0, R5
  AND R0, #BBTN
  BEQ gu_pin
  LDW R0, [in_now]         ; B: throw the way you hold (or the way you face)
  MOV R1, R0
  AND R1, #LEFT
  BEQ gu_tr
  MOV R1, #1
  STW R1, [p_face]
gu_tr:
  AND R0, #RIGHT
  BEQ gu_tgo
  MOV R1, #0
  STW R1, [p_face]
gu_tgo:
  MOV R0, #4
  STW R0, [p_atk]
  MOV R0, #THROWT
  STW R0, [p_punch]
  MOV R0, #140
  CALL sfxblip
gu_pin:                    ; keep him in front of you, facing you
  LDW R0, [p_x]
  LDW R1, [p_face]
  CMP R1, #0
  BEQ gu_pr
  SUB R0, #GRABDX
  BRA gu_px
gu_pr:
  ADD R0, #GRABDX
gu_px:
  CMP R0, #XMIN
  BGE gu_px2
  MOV R0, #XMIN
gu_px2:
  CMP R0, #EXMAX
  BLE gu_px3
  MOV R0, #EXMAX
gu_px3:
  STW R0, [A1+#4]
  LDW R0, [p_y]
  STW R0, [A1+#6]
  LDW R0, [p_face]         ; faceRight == your facing: he looks at you
  STB R0, [A1+#3]
  RET

; ---- kneehit(A1,A3): a knee to the held thug; the KNEEMAX-th floors him ----
kneehit:
  MOV R0, #KNEEDMG
  STB R0, [p_dmg]
  LDW R0, [p_gknee]
  ADD R0, #1
  STW R0, [p_gknee]
  MOV R1, #0
  CMP R0, #KNEEMAX
  BLT kh_kd
  MOV R1, #1
kh_kd:
  STW R1, [p_kd]
  MOV R0, #2
  STW R0, [hitstop]
  CALL enemyhit
  RET

; ---- dothrow(A1,A3): let go: he flies the way you face and lands hard ----
dothrow:
  MOV R0, #ST_AIR
  STB R0, [A3+#0]
  MOV R0, #1
  STB R0, [A3+#8]          ; thrown: bowls over whoever he lands on
  MOV R0, #THROWDMG
  STB R0, [A3+#10]         ; damage when he hits the street
  MOV R0, #THROWZ
  STW R0, [A3+#2]
  MOV R0, #THROWVZ
  STW R0, [A3+#4]
  MOV R0, #THROWVX
  LDW R1, [p_face]
  CMP R1, #0
  BEQ dt_r
  NEG R0
dt_r:
  STW R0, [A3+#6]
  MOV R0, #0
  STW R0, [p_grab]
  MOV R0, #GRABCOOL
  STW R0, [p_gcool]
  MOV R0, #SHAKEW
  STW R0, [shakeT]
  MOV R0, #110
  CALL sfxblip
  RET

; ---- clearhitf: a new flying kick may hit every thug once ----
clearhitf:
  LDA A0, #EX+9
  MOV R1, #NENEM
  MOV R0, #0
chf_lp:
  STB R0, [A0]
  ADD A0, #16
  SUB R1, #1
  BNE chf_lp
  RET

; ---- exclear(R7=slot): zero the slot's EX record (on his feet, no motion) ----
exclear:
  MOV R3, R7
  SHL R3, #4
  LDA A3, #EX
  ADD A3, R3
  MOV R0, #0
  STW R0, [A3+#0]
  STW R0, [A3+#2]
  STW R0, [A3+#4]
  STW R0, [A3+#6]
  STW R0, [A3+#8]
  STW R0, [A3+#10]
  STB R7, [A3+#12]         ; which slot this is (launch spots the boss by it)
  RET

; ---- checkhit: the strike box in front of you hits every standing thug inside.
;      Damage, reach and knockdown come from the attack (p_atk). ----
checkhit:
  LDW R1, [p_atk]
  MOV R0, #FISTDMG         ; jab
  MOV R2, #0
  MOV R3, #0
  CMP R1, #1
  BNE ch_nk
  MOV R0, #KICKDMG         ; kick: further, and floors him
  MOV R2, #KICKRX
  MOV R3, #1
ch_nk:
  CMP R1, #2
  BNE ch_np
  MOV R0, #WPNDMG          ; pipe
  MOV R2, #WPNREACH
ch_np:
  CMP R1, #5
  BNE ch_set
  MOV R0, #JKDMG           ; flying kick: floors him
  MOV R2, #JKRX
  MOV R3, #1
ch_set:
  STB R0, [p_dmg]
  STW R3, [p_kd]
  LDW R0, [p_x]
  LDW R1, [p_face]
  AND R1, #1
  BEQ ch_right
  MOV R4, R0              ; facing left: box covers body + reach to the left
  SUB R4, #PUNCHRX-16
  SUB R4, R2
  MOV R5, R0
  ADD R5, #20
  BRA ch_y
ch_right:
  MOV R4, R0             ; facing right: box covers body + reach to the right
  SUB R4, #4
  MOV R5, R0
  ADD R5, #PUNCHRX
  ADD R5, R2
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
  CALL slotptrs
  LDB R0, [A1+#0]
  CMP R0, #0
  BEQ ch_next
  LDB R0, [A3+#0]        ; only thugs on their feet ...
  CMP R0, #0
  BNE ch_next
  LDW R0, [A3+#2]        ; ... and not up in the air (a hopping / leaping boss)
  CMP R0, #16
  BGT ch_next
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
  LDW R0, [p_atk]        ; a flying kick hits each thug once
  CMP R0, #5
  BNE ch_hit
  LDB R0, [A3+#9]
  CMP R0, #0
  BNE ch_next
  MOV R0, #1
  STB R0, [A3+#9]
ch_hit:
  MOV R0, #1
  STW R0, [p_hitany]
  PUSH R7
  CALL enemyhit
  POP R7
ch_next:
  ADD R7, #1
  CMP R7, #NENEM
  BGE ch_ret
  BRA ch_lp
ch_ret:
  RET

; ---- enemyhit(A1=slot, A3=EX): -p_dmg hp, stagger; a knockdown hit (p_kd) or
;      the last point of health sends him flying ----
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
  BEQ eh_kill
  LDW R1, [p_kd]
  CMP R1, #0
  BEQ eh_done
  LDW R1, [p_atk]        ; a boss shrugs off the combo kick (it still hurts)
  CMP R1, #1
  BNE eh_kd
  LDB R1, [A3+#12]
  CMP R1, #0
  BNE eh_kd
  LDW R1, [bossactive]
  CMP R1, #0
  BNE eh_done
eh_kd:
  CALL launch            ; floored
  MOV R1, #HITSTOP
  STW R1, [hitstop]
  MOV R0, #100
  CALL sfxblip
eh_done:
  RET
eh_kill:
  CALL launch
  CALL ekill
  RET

; ---- ekill(A1,A3): he's beaten: count it, juice it; he blinks out once he's down ----
ekill:
  MOV R1, #1
  STB R1, [A3+#11]
  LDW R1, [kills]
  ADD R1, #1
  STW R1, [kills]
  MOV R1, #HSKILL        ; a kill freezes a touch longer and kicks the camera
  STW R1, [hitstop]
  MOV R1, #SHAKEW
  STW R1, [shakeT]
  MOV R0, #90
  CALL sfxblip
  RET

; ---- launch(A1,A3): knocked off his feet, away from you ----
launch:
  MOV R0, #ST_AIR
  STB R0, [A3+#0]
  MOV R0, #0
  STW R0, [A3+#2]          ; z
  STB R0, [A3+#8]          ; not thrown
  MOV R0, #KDVZ
  STW R0, [A3+#4]
  MOV R0, #KDVX
  LDW R1, [A1+#4]
  LDW R2, [p_x]
  CMP R1, R2
  BGE ln_r
  NEG R0
ln_r:
  STW R0, [A3+#6]
  MOV R0, #8               ; a short flash as he goes
  STB R0, [A1+#2]
  LDB R0, [A3+#12]         ; a floored boss drops whatever special he was doing
  CMP R0, #0
  BNE ln_done
  LDW R0, [bossactive]
  CMP R0, #0
  BEQ ln_done
  MOV R0, #0
  STW R0, [b_mode]
  STW R0, [b_frame]
  LDW R0, [b_cool]         ; and gives you a moment before the next one
  CMP R0, #60
  BGE ln_done
  MOV R0, #60
  STW R0, [b_cool]
ln_done:
  RET

; ---- eair(A1,A3): a thug in the air: skid, arc, land; a thrown one bowls others over ----
eair:
  LDB R0, [A1+#2]          ; run out the hit flash
  CMP R0, #0
  BEQ ear_f
  SUB R0, #1
  STB R0, [A1+#2]
ear_f:
  LDW R4, [A1+#4]
  LDW R0, [A3+#6]
  ADD R4, R0
  CMP R4, #XMIN
  BGE ear_x1
  MOV R4, #XMIN
ear_x1:
  CMP R4, #EXMAX
  BLE ear_x2
  MOV R4, #EXMAX
ear_x2:
  STW R4, [A1+#4]
  LDW R0, [A3+#2]          ; z += vz, gravity every other frame
  LDW R1, [A3+#4]
  ADD R0, R1
  LDW R2, [gtick]
  AND R2, #1
  BEQ ear_g
  SUB R1, #1
ear_g:
  STW R1, [A3+#4]
  STW R0, [A3+#2]
  LDB R2, [A3+#8]
  CMP R2, #0
  BEQ ear_land
  PUSH R0
  CALL bowl
  POP R0
ear_land:
  CMP R0, #0
  BLE ear_down
  RET
ear_down:
  MOV R0, #0               ; on the street: lie there
  STW R0, [A3+#2]
  STW R0, [A3+#4]
  STB R0, [A3+#8]
  MOV R0, #ST_DOWN
  STB R0, [A3+#0]
  MOV R0, #DOWNT
  STB R0, [A3+#1]
  LDB R0, [A3+#10]         ; a throw hurts on landing
  CMP R0, #0
  BEQ ear_thud
  MOV R1, #0
  STB R1, [A3+#10]
  LDB R1, [A3+#11]
  CMP R1, #0
  BNE ear_thud
  LDB R1, [A1+#1]
  SUB R1, R0
  CMP R1, #0
  BGT ear_hp
  MOV R1, #0
  STB R1, [A1+#1]
  CALL ekill
  BRA ear_thud
ear_hp:
  STB R1, [A1+#1]
ear_thud:
  LDB R0, [A3+#11]         ; beaten: blink out sooner
  CMP R0, #0
  BEQ ear_sfx
  MOV R0, #DIET
  STB R0, [A3+#1]
ear_sfx:
  MOV R0, #4
  STW R0, [shakeT]
  MOV R0, #420             ; thud
  CALL sfxblip
  RET

; ---- edown(A1,A3): count down on the floor; get up (or, beaten, vanish) ----
edown:
  LDB R0, [A3+#1]
  SUB R0, #1
  STB R0, [A3+#1]
  CMP R0, #0
  BEQ ed_up
  RET
ed_up:
  LDB R0, [A3+#11]
  CMP R0, #0
  BEQ ed_rise
  MOV R0, #0               ; gone
  STB R0, [A1+#0]
  STB R0, [A3+#0]
  RET
ed_rise:
  MOV R0, #0               ; back on his feet ...
  STB R0, [A3+#0]
  STB R0, [A1+#2]
  CALL atkptr
  MOV R0, #ATKCD           ; ... and a beat before he can swing again
  STB R0, [A2]
  RET

; ---- bowl(A1,A3 = the thrown thug): floor every standing thug he lands on ----
bowl:
  LDW R0, [A3+#2]          ; only once he's low enough to hit someone
  CMP R0, #30
  BLT bw_go
  RET
bw_go:
  PUSHA A1
  PUSHA A3
  LDW R4, [A1+#4]
  LDW R5, [A1+#6]
  MOV R7, #0
bw_lp:
  CALL slotptrs
  LDB R0, [A1+#0]
  CMP R0, #0
  BEQ bw_next
  LDB R0, [A3+#0]          ; standing thugs only (the thrown one is airborne)
  CMP R0, #0
  BNE bw_next
  LDW R0, [A1+#4]
  SUB R0, R4
  CALL absr0
  CMP R0, #20
  BGT bw_next
  LDW R0, [A1+#6]
  SUB R0, R5
  CALL absr0
  CMP R0, #12
  BGT bw_next
  MOV R0, #BOWLDMG
  STB R0, [p_dmg]
  MOV R0, #1
  STW R0, [p_kd]
  PUSH R4
  PUSH R5
  PUSH R7
  CALL enemyhit
  POP R7
  POP R5
  POP R4
bw_next:
  ADD R7, #1
  CMP R7, #NENEM
  BGE bw_ret
  BRA bw_lp
bw_ret:
  POPA A3
  POPA A1
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
  MOV R3, R7
  SHL R3, #4
  LDA A3, #EX
  ADD A3, R3
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
  BNE ea_on
  RET
ea_on:
  LDB R0, [A3+#0]          ; knocked about? the physics in moves takes over
  CMP R0, #0
  BEQ ea_live
  CMP R0, #ST_HELD
  BNE ea_nh
  LDB R0, [A1+#2]          ; held: the grab pins him; just run out the hit flash
  CMP R0, #0
  BEQ ea_hd
  SUB R0, #1
  STB R0, [A1+#2]
ea_hd:
  RET
ea_nh:
  CMP R0, #ST_AIR
  BNE ea_nair
  BRA eair
ea_nair:
  BRA edown
ea_live:
  LDW R0, [ehold]         ; freshly spawned -> hold still (grace period)
  CMP R0, #0
  BEQ ea_run
  RET
ea_run:
  LDW R0, [bossactive]    ; the boss (slot 0) may be busy with a special move
  CMP R0, #0
  BEQ ea_run2
  LDW R0, [eidx]
  CMP R0, #0
  BNE ea_run2
  CALL bossai
  CMP R0, #0
  BEQ ea_run2
  RET
ea_run2:
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
  CMP R0, #HITSTUN-KBF    ; only a short shove, so the next hit of a combo still reaches
  BGE ea_kb
  RET
ea_kb:
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
  LDW R0, [p_jz]           ; high in a jump: the punch passes underneath
  CMP R0, #JKHIGH
  BLE ek_low
  RET
ek_low:
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
  LDW R0, [p_grab]         ; a hit shakes the held thug loose ...
  CMP R0, #0
  BEQ hu_ng
  SUB R0, #1
  SHL R0, #4
  LDA A0, #EX
  ADD A0, R0
  MOV R0, #0
  STB R0, [A0]
  STW R0, [p_grab]
  MOV R0, #GRABCOOL
  STW R0, [p_gcool]
hu_ng:
  MOV R0, #0               ; ... and knocks you out of any move or combo
  STW R0, [p_combo]
  STW R0, [p_chain]
  LDW R0, [p_jz]
  CMP R0, #0
  BNE hu_air
  MOV R0, #0
  STW R0, [p_punch]
hu_air:
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
  MOV R3, R7
  SHL R3, #4
  LDA A3, #EX
  ADD A3, R3
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
  LDW R0, [p_punch]        ; pick the frame: throw > grab/knee > air > swing > walk
  LDW R1, [p_atk]
  CMP R0, #0
  BEQ ep_nsw
  MOV R5, #PL_THROW
  CMP R1, #4
  BEQ ep_attr
ep_nsw:
  LDW R2, [p_grab]
  CMP R2, #0
  BEQ ep_ngr
  MOV R5, #PL_GRAB
  CMP R0, #0
  BEQ ep_attr
  CMP R1, #3
  BNE ep_attr
  MOV R5, #PL_KNEE
  BRA ep_attr
ep_ngr:
  LDW R2, [p_jz]
  LDW R3, [p_jvz]
  OR R2, R3
  BEQ ep_gnd
  MOV R5, #PL_JUMP
  LDW R2, [p_jkick]
  CMP R2, #0
  BEQ ep_attr
  MOV R5, #PL_JKICK
  BRA ep_attr
ep_gnd:
  CMP R0, #0
  BEQ ep_walk
  MOV R5, #PL_KICK
  CMP R1, #1
  BEQ ep_attr
  MOV R5, #PL_KNEE
  CMP R1, #3
  BEQ ep_attr
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
  LDW R2, [p_jz]           ; lifted by the jump (the shadow stays on the street)
  SUB R1, R2
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
  LDW R2, [bossactive]    ; during a boss wave slot 0 is the boss (Viper's runners aren't)
  CMP R2, #0
  BEQ ee_typed
  LDW R2, [eidx]
  CMP R2, #0
  BEQ ee_boss
ee_typed:
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
  LDB R2, [A3+#0]       ; held / airborne / floored -> reeling or flat frame of this rig
  CMP R2, #0
  BEQ ee_norm
  MOV R3, #GR_HURT
  MOV R4, #GR_DOWN
  CMP R5, #BR_WALK
  BNE ee_rig
  MOV R3, #BR_HURT
  MOV R4, #BR_DOWN
ee_rig:
  MOV R5, R3            ; held: reeling
  CMP R2, #ST_HELD
  BNE ee_nhd
  BRA ee_tile
ee_nhd:
  MOV R5, R4            ; airborne / down: flat ...
  CMP R2, #ST_AIR
  BNE ee_dn
  LDB R2, [A3+#8]       ; ... except a knocked-up thug reels while he rises
  CMP R2, #0
  BNE ee_tile
  LDW R2, [A3+#4]
  CMP R2, #0
  BLE ee_tile
  MOV R5, R3
  BRA ee_tile
ee_dn:
  LDB R2, [A3+#11]      ; beaten: blink out
  CMP R2, #0
  BEQ ee_getup
  LDB R2, [A3+#1]
  AND R2, #4
  BEQ ee_tile
  BRA ee_cull
ee_getup:
  LDB R2, [A3+#1]       ; the last moments on the floor: getting up
  CMP R2, #GETUPT
  BGT ee_tile
  MOV R5, R3
  BRA ee_tile
ee_norm:
  CALL bossframe        ; a boss mid-special picks his own frame
  CMP R2, #0
  BEQ ee_norm2
  BRA ee_tile
ee_norm2:
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
  LDW R2, [A3+#2]        ; airborne height
  SUB R1, R2
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
  LDW R2, [p_jz]
  SUB R1, R2
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
  LDB R0, [A1+#1]         ; cells = ceil(hp * BOSSBAR / max)
  MOV R1, #BOSSBAR
  MULU R0, R1
  LDW R2, [bossmaxhp]
  ADD R0, R2
  SUB R0, #1
  MOV R1, #0
  DIVU R0, R2
  MOV R5, R0
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
  MOV R5, #1
; ---- hudprintr(A1=string, R4=col, R5=row) ----
hudprintr:
hl_lp:
  LDB R2, [A1]
  CMP R2, #$FF
  BEQ hl_done
  CMP R2, #26
  BEQ hl_adv
  ADD R2, #FONT
  MOV R0, R4
  MOV R1, R5
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
  MOV R4, #13
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
  MOV R0, #1               ; the lineup's boss is Brick
  CALL loadbr
  MOV R0, #0
  CALL bosspalk
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
; shoes x2, trim), so every body takes every colour pick. A body is 12 frames: 6 DMA'd
; over PL_WALK..PL_DOWN, 6 over PL_KICK..PL_THROW; colours are ramps from charpal.

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
  MOV R0, #PL_BYTES        ; then the move frames, which follow in ROM
  ADD A0, R0
  MOV R0, #PLX_DST
  STW R0, [DMA_DST]
  MOV R0, #PLX_BYTES
  STW R0, [DMA_LEN]
  MOV R0, #0
  STB R0, [DMA_MODE]
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
  BEQ cf_b
  MOV R0, #0
  STW R0, [p_atk]
  MOV R0, #PUNCHT
  STW R0, [p_punch]
  MOV R0, #180
  CALL sfxblip
cf_b:
  LDW R1, [c_edge]         ; B: a test kick
  MOV R0, R1
  AND R0, #BBTN
  BEQ cf_anim
  MOV R0, #1
  STW R0, [p_atk]
  MOV R0, #KICKT
  STW R0, [p_punch]
  MOV R0, #160
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
  LDW R0, [p_atk]
  CMP R0, #1
  BNE cf_fig
  MOV R5, #PL_KICK
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
  STW R0, [p_jz]           ; feet on the ground, hands free, no combo
  STW R0, [p_jvz]
  STW R0, [p_combo]
  STW R0, [p_chain]
  STW R0, [p_atk]
  STW R0, [p_grab]
  STW R0, [p_gcool]
  STW R0, [p_jkick]
  MOV R0, #80
  STW R0, [p_x]            ; start at the left of the new street
  MOV R0, #150
  STW R0, [p_y]
  CALL clearpickups
  MOV R0, #0               ; the big rig is the bruiser again (a boss may have borrowed it)
  CALL loadbr
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
  MOV R7, #0               ; every slot starts on its feet
sw_clr:
  CALL exclear
  ADD R7, #1
  CMP R7, #NENEM
  BLT sw_clr
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

; ---- spawnboss: this stage's boss in slot 0 (his frames + colours loaded), all other
;      slots idle, boss bar + name armed ----
spawnboss:
  LDW R0, [level]
  STW R0, [b_kind]
  ADD R0, #1               ; rig set 1.. = the bosses
  CALL loadbr
  LDW R0, [b_kind]
  CALL bosspalk
  LDA A1, #ENEMY
  MOV R0, #1
  STB R0, [A1+#0]
  LDW R1, [b_kind]
  LDA A0, #BOSSHPT
  ADD A0, R1
  LDB R0, [A0]
  STB R0, [A1+#1]
  STW R0, [bossmaxhp]
  LDA A0, #BOSSTY          ; his base profile: speed + punch damage
  ADD A0, R1
  LDB R0, [A0]
  STB R0, [ETYPE]
  MOV R0, #0
  STB R0, [EATK]          ; the boss sits in slot 0
  STB R0, [A1+#2]
  STB R0, [A1+#3]
  STW R0, [b_mode]
  STW R0, [b_frame]
  STW R0, [b_flash]
  STW R0, [b_calls]
  MOV R0, #BOSSCOOL0
  STW R0, [b_cool]
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
  MOV R0, #EHOLD          ; let the boss make an entrance before it charges
  STW R0, [ehold]
  LDW R0, [b_kind]         ; his name, left of the bar (DA entries are 3 bytes)
  MOV R1, R0
  SHL R1, #1
  ADD R1, R0
  LDA A0, #BOSSNAME
  ADD A0, R1
  LDADDR A1, [A0]
  MOV R4, #4
  MOV R5, #2
  CALL hudprintr
  RET

; ============================ stage bosses ============================
; One boss per stage (b_kind = level), each with a special move on top of the
; normal chase-and-punch. bossai runs before the normal AI; while it returns R0 != 0
; the boss is busy with the special and the normal AI is skipped.
;   BRICK  (stage 1): revs up (flashing), then charges along his row and crashes,
;                     dazed, at the screen edge. Jump or step off the row.
;   VIPER  (stage 2): quick; hops back out of reach after you close in, and
;                     whistles up two runners at 2/3 and 1/3 health.
;   WARDEN (stage 3): crouches (flashing), leaps to where you stood and slams the
;                     street: the shockwave hurts anyone near who isn't in the air.

; ---- bossai(A1,A3 = slot 0) -> R0 = 1 while a special move runs ----
bossai:
  MOV R0, #0
  STW R0, [b_flash]
  LDW R0, [b_mode]
  CMP R0, #0
  BEQ ba_idle
  LDB R0, [A1+#2]          ; specials shrug off the stagger (the flash still runs)
  CMP R0, #0
  BEQ ba_disp
  SUB R0, #1
  STB R0, [A1+#2]
ba_disp:
  LDW R0, [b_kind]
  CMP R0, #1
  BLT ba_brickj
  BEQ ba_viperj
  BRA wardenai
ba_brickj:
  BRA brickai
ba_viperj:
  BRA viperai
ba_idle:
  MOV R0, #0
  STW R0, [b_frame]
  LDW R0, [b_kind]         ; Viper's whistle doesn't wait for the cooldown
  CMP R0, #1
  BNE ba_cool
  CALL viperbackup
ba_cool:
  LDW R0, [b_cool]
  CMP R0, #0
  BEQ ba_ready
  SUB R0, #1
  STW R0, [b_cool]
ba_no:
  MOV R0, #0
  RET
ba_ready:
  LDW R4, [A1+#4]          ; only once he's on screen
  CALL clampboss
  CMP R0, #0
  BNE ba_no
  CALL atkptr              ; not mid-punch (a stagger doesn't stop him: he shrugs it off)
  LDB R0, [A2]
  CMP R0, #ATKCD
  BGT ba_no
  LDW R0, [A1+#4]          ; R4 = |dx|, R5 = |dy| to the player
  LDW R1, [p_x]
  SUB R0, R1
  CALL absr0
  MOV R4, R0
  LDW R0, [A1+#6]
  LDW R1, [p_y]
  SUB R0, R1
  CALL absr0
  MOV R5, R0
  LDW R0, [b_kind]
  CMP R0, #1
  BLT ba_brick
  BEQ ba_viper
  CMP R4, #180             ; Warden: leap at you from anywhere in range
  BGT ba_no
  MOV R0, #WARDCROUCH
  BRA ba_start
ba_brick:
  MOV R0, #BRICKREV        ; Brick: rev up when you're at range ...
  CMP R4, #60
  BGE ba_start
  MOV R0, #BRICKBACK       ; ... else back off first (mode 4), then rev
  STW R0, [b_tmr]
  MOV R0, #4
  STW R0, [b_mode]
  MOV R0, #1
  RET
ba_viper:
  CMP R5, #10              ; Viper: hop away when you close in
  BGT ba_no2
  CMP R4, #34
  BGT ba_no2
  MOV R0, #VIPHOPV
  STW R0, [b_vy]
  MOV R0, #0
ba_start:
  STW R0, [b_tmr]
  MOV R0, #1
  STW R0, [b_mode]
  CALL atkptr              ; drop any punch in progress
  MOV R0, #0
  STB R0, [A2]
  CALL bossface
  MOV R0, #1
  RET
ba_no2:
  MOV R0, #0
  RET

; ---- bossface: turn the boss toward the player ----
bossface:
  LDW R0, [A1+#4]
  LDW R1, [p_x]
  MOV R2, #0
  CMP R0, R1
  BGE bf_s
  MOV R2, #1
bf_s:
  STB R2, [A1+#3]
  RET

; ---- bossdone(R0 = cooldown): back to the normal AI ----
bossdone:
  STW R0, [b_cool]
  MOV R0, #0
  STW R0, [b_mode]
  STW R0, [b_frame]
  STW R0, [A3+#2]
  MOV R0, #1               ; (this frame is still spent)
  RET

; ---- toward(R0 = speed) -> R0 = +speed if the player is to the right, else -speed ----
toward:
  LDW R1, [A1+#4]
  LDW R2, [p_x]
  CMP R1, R2
  BLT tw_r
  NEG R0
tw_r:
  RET

; ---- clampboss(R4 = x) -> R4 kept inside the camera view (8..296); C set if clamped ----
clampboss:
  LDW R0, [cam]
  ADD R0, #8
  CMP R4, R0
  BGE cb_hi
  MOV R4, R0
  MOV R0, #1
  RET
cb_hi:
  ADD R0, #288
  CMP R4, R0
  BLE cb_ok
  MOV R4, R0
  MOV R0, #1
  RET
cb_ok:
  MOV R0, #0
  RET

; ---- Brick: 1 rev up (flashing wind-up), 2 charge, 3 dazed ----
brickai:
  LDW R0, [b_mode]
  CMP R0, #2
  BNE bk_nc
  BRA bk_charge
bk_nc:
  BLE bk_rev
  CMP R0, #4
  BEQ bk_back
  BRA bk_dazed
bk_back:                   ; backing off to get a run-up
  MOV R0, #0
  STW R0, [b_frame]
  MOV R0, #BRICKBACKV
  CALL toward
  NEG R0
  LDW R4, [A1+#4]
  ADD R4, R0
  CALL clampboss
  STW R4, [A1+#4]
  PUSH R0
  CALL bossface
  POP R0
  CMP R0, #0               ; backed into the screen edge -> rev now
  BNE bk_torev
  LDW R0, [p_x]
  SUB R0, R4
  CALL absr0
  CMP R0, #90
  BGE bk_torev
  LDW R0, [b_tmr]
  SUB R0, #1
  STW R0, [b_tmr]
  BEQ bk_torev
  MOV R0, #1
  RET
bk_torev:
  MOV R0, #1
  STW R0, [b_mode]
  MOV R0, #BRICKREV
  STW R0, [b_tmr]
  MOV R0, #1
  RET
bk_rev:
  MOV R0, #1               ; revving
  STW R0, [b_frame]
  CALL bossface
  LDW R0, [b_tmr]
  STW R0, [b_flash]
  SUB R0, #1
  STW R0, [b_tmr]
  BNE bk_busy
  MOV R0, #BRICKV          ; go!
  CALL toward
  STW R0, [b_vx]
  MOV R0, #2
  STW R0, [b_mode]
  MOV R0, #BRICKRUN
  STW R0, [b_tmr]
  MOV R0, #340
  CALL sfxblip
bk_busy:
  MOV R0, #1
  RET
bk_charge:
  MOV R0, #2
  STW R0, [b_frame]
  LDW R4, [A1+#4]
  LDW R0, [b_vx]
  ADD R4, R0
  CALL clampboss
  STW R4, [A1+#4]
  PUSH R0
  LDW R0, [p_x]            ; run you over?
  SUB R0, R4
  CALL absr0
  CMP R0, #22
  BGT bk_miss
  LDW R0, [p_y]
  LDW R1, [A1+#6]
  SUB R0, R1
  CALL absr0
  CMP R0, #12
  BGT bk_miss
  LDW R0, [p_jz]
  CMP R0, #JKHIGH
  BGT bk_miss
  LDW R0, [p_hurt]
  CMP R0, #0
  BNE bk_miss
  MOV R2, #BRICKDMG
  CALL hurtplayer
bk_miss:
  POP R0
  CMP R0, #0               ; hit the edge of the screen -> crash
  BNE bk_crash
  LDW R0, [b_tmr]
  SUB R0, #1
  STW R0, [b_tmr]
  BNE bk_busy
bk_crash:
  MOV R0, #3
  STW R0, [b_mode]
  MOV R0, #BRICKDAZE
  STW R0, [b_tmr]
  MOV R0, #SHAKEP
  STW R0, [shakeT]
  MOV R0, #460
  CALL sfxblip
  MOV R0, #1
  RET
bk_dazed:
  MOV R0, #3               ; seeing stars: free hits
  STW R0, [b_frame]
  LDW R0, [b_tmr]
  SUB R0, #1
  STW R0, [b_tmr]
  BEQ bk_up
  MOV R0, #1
  RET
bk_up:
  MOV R0, #BRICKCOOL
  BRA bossdone

; ---- Viper: 1 = a hop back, out of reach ----
viperai:
  MOV R0, #1
  STW R0, [b_frame]
  MOV R0, #VIPHOPX         ; away from you
  CALL toward
  NEG R0
  LDW R4, [A1+#4]
  ADD R4, R0
  CALL clampboss
  STW R4, [A1+#4]
  LDW R0, [A3+#2]          ; arc: z += vz, gravity every other frame
  LDW R1, [b_vy]
  ADD R0, R1
  LDW R2, [gtick]
  AND R2, #1
  BEQ vp_g
  SUB R1, #1
  STW R1, [b_vy]
vp_g:
  CMP R0, #0
  BLE vp_land
  STW R0, [A3+#2]
  MOV R0, #1
  RET
vp_land:
  MOV R0, #VIPCOOL
  BRA bossdone

; ---- viperbackup: at 2/3 and 1/3 health Viper whistles up two runners ----
viperbackup:
  LDB R0, [A1+#1]
  LDW R1, [b_calls]
  CMP R1, #0
  BNE vb_2
  CMP R0, #VIPTH1
  BGT vb_no
  BRA vb_call
vb_2:
  CMP R1, #1
  BNE vb_no
  CMP R0, #VIPTH2
  BGT vb_no
vb_call:
  ADD R1, #1
  STW R1, [b_calls]
  PUSHA A1
  PUSHA A3
  LDW R0, [cam]            ; one from each side of the screen
  SUB R0, #24
  CMP R0, #XMIN
  BGE vb_l
  MOV R0, #XMIN
vb_l:
  CALL backup
  LDW R0, [cam]
  ADD R0, #330
  CALL backup
  POPA A3
  POPA A1
  MOV R0, #60              ; whistle
  CALL sfxblip
vb_no:
  RET

; ---- backup(R0 = x): a runner into the first free slot after the boss, on your row ----
backup:
  MOV R6, R0
  MOV R7, #1
bu_lp:
  CALL slotptrs
  LDB R0, [A1+#0]
  CMP R0, #0
  BEQ bu_free
  ADD R7, #1
  CMP R7, #NENEM
  BLT bu_lp
  RET
bu_free:
  CALL exclear
  MOV R0, #1
  STB R0, [A1+#0]
  MOV R0, #2
  STB R0, [A1+#1]          ; runner hp
  MOV R0, #0
  STB R0, [A1+#2]
  STB R0, [A1+#3]
  STW R6, [A1+#4]
  LDW R0, [p_y]
  STW R0, [A1+#6]
  LDA A2, #ETYPE
  ADD A2, R7
  MOV R0, #RUNNER
  STB R0, [A2]
  LDA A2, #EATK
  ADD A2, R7
  MOV R0, #0
  STB R0, [A2]
  RET

; ---- Warden: 1 crouch (flashing), 2 leap at where you stood, 3 recover ----
wardenai:
  LDW R0, [b_mode]
  CMP R0, #2
  BEQ wd_leap
  BLE wd_crouch
  BRA wd_rec
wd_crouch:
  MOV R0, #1               ; crouching
  STW R0, [b_frame]
  CALL bossface
  LDW R0, [b_tmr]
  STW R0, [b_flash]
  SUB R0, #1
  STW R0, [b_tmr]
  BNE wd_busy
  LDW R0, [p_x]            ; take off: cover the gap in WARDLEAP frames
  LDW R1, [A1+#4]
  SUB R0, R1
  SAR R0, #4
  STW R0, [b_vx]
  LDW R0, [p_y]
  LDW R1, [A1+#6]
  SUB R0, R1
  SAR R0, #4
  STW R0, [b_vy]
  MOV R0, #2
  STW R0, [b_mode]
  MOV R0, #WARDLEAP
  STW R0, [b_tmr]
  MOV R0, #320
  CALL sfxblip
wd_busy:
  MOV R0, #1
  RET
wd_leap:
  MOV R0, #1
  STW R0, [b_frame]
  LDW R4, [A1+#4]
  LDW R0, [b_vx]
  ADD R4, R0
  CALL clampboss
  STW R4, [A1+#4]
  LDW R5, [A1+#6]
  LDW R0, [b_vy]
  ADD R5, R0
  CMP R5, #BANDTOP
  BGE wd_y1
  MOV R5, #BANDTOP
wd_y1:
  CMP R5, #BANDBOT
  BLE wd_y2
  MOV R5, #BANDBOT
wd_y2:
  STW R5, [A1+#6]
  LDW R0, [b_tmr]
  SUB R0, #1
  STW R0, [b_tmr]
  BEQ wd_land
  MOV R1, #WARDLEAP        ; z = t * (WARDLEAP - t) / 2, t = frames since take-off
  SUB R1, R0
  MULU R0, R1
  SHR R0, #1
  STW R0, [A3+#2]
  MOV R0, #1
  RET
wd_land:
  MOV R0, #0
  STW R0, [A3+#2]
  MOV R0, #12
  STW R0, [shakeT]
  MOV R0, #500
  CALL sfxblip
  LDW R0, [p_x]            ; the shockwave
  SUB R0, R4
  CALL absr0
  CMP R0, #WARDWAVE
  BGT wd_nohit
  LDW R0, [p_y]
  SUB R0, R5
  CALL absr0
  CMP R0, #20
  BGT wd_nohit
  LDW R0, [p_jz]
  CMP R0, #0
  BNE wd_nohit
  LDW R0, [p_hurt]
  CMP R0, #0
  BNE wd_nohit
  MOV R2, #WARDDMG
  CALL hurtplayer
wd_nohit:
  MOV R0, #3
  STW R0, [b_mode]
  MOV R0, #WARDREC
  STW R0, [b_tmr]
  MOV R0, #1
  RET
wd_rec:
  MOV R0, #0
  STW R0, [b_frame]
  LDW R0, [b_tmr]
  SUB R0, #1
  STW R0, [b_tmr]
  BEQ wd_up
  MOV R0, #1
  RET
wd_up:
  MOV R0, #WARDCOOL
  BRA bossdone

; ---- bossframe(R5/R6 = tile/attr): R2 = 1 if the boss is mid-special, with R5 = his
;      frame and R6 flashing on the telegraph; else R2 = 0 and nothing changed ----
bossframe:
  LDW R2, [bossactive]
  CMP R2, #0
  BEQ bfr_no
  LDW R2, [eidx]
  CMP R2, #0
  BNE bfr_no
  LDW R2, [b_frame]
  CMP R2, #0
  BEQ bfr_no
  MOV R5, #BR_WIND
  CMP R2, #2
  BLT bfr_fl
  MOV R5, #BR_PUNCH
  BEQ bfr_fl
  MOV R5, #BR_HURT
bfr_fl:
  LDW R2, [b_flash]
  AND R2, #4
  BEQ bfr_yes
  AND R6, #$F0
  OR R6, #PB_FLASH
bfr_yes:
  MOV R2, #1
  RET
bfr_no:
  MOV R2, #0
  RET

; ---- loadbr(R0 = set): DMA a six-frame big-rig set (0 bruiser, 1.. the bosses)
;      over BR_WALK x2, BR_DOWN, BR_WIND + BR_PUNCH, BR_HURT ----
loadbr:
  LDA A0, #bossrigs
lb_lp:
  CMP R0, #0
  BEQ lb_go
  MOV R1, #12288
  ADD A0, R1
  SUB R0, #1
  BRA lb_lp
lb_go:
  MOV R0, #BRW_DST
  MOV R1, #4096
  CALL vdma
  MOV R0, #BRD_DST
  MOV R1, #2048
  CALL vdma
  MOV R0, #BRWP_DST
  MOV R1, #4096
  CALL vdma
  MOV R0, #BRH_DST
  MOV R1, #2048
  CALL vdma
  RET

; ---- vdma(A0 = src, R0 = VRAM byte offset, R1 = length): copy, then A0 += length ----
vdma:
  STW R0, [DMA_DST]
  STW R1, [DMA_LEN]
  MOV R0, #0
  STB R0, [DMA_MODE]
  PUSH R1
  CALL dmago
  POP R1
  ADD A0, R1
  RET

; ---- bosspalk(R0 = kind): that boss's colours into bank 6 ----
bosspalk:
  MOV R1, #30
  MULU R0, R1
  LDA A0, #bosspal
  ADD A0, R0
  MOV R0, #PB6PAL
  MOV R1, #30
  CALL dmapal
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

; ---- stage bosses, indexed by kind (= stage) ----
BOSSHPT:                         ; hit points
  DB 28, 24, 34
BOSSTY:                          ; base profile (speed / punch damage): Brick + Warden heavy, Viper quick
  DB BRUISER, RUNNER, BRUISER
BOSSNAME:
  DA bnBRICK, bnVIPER, bnWARDEN
bnBRICK:
  DB B, R, I, C, K, END
bnVIPER:
  DB V, I, P, E, R, END
bnWARDEN:
  DB W, A, R, D, E, N, END

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
BODYTAB:                         ; ROM address of each body's 12 frames (PL_BYTES + PLX_BYTES)
  DA bodies, bodies+24576, bodies+49152, bodies+73728
  DA bodies+98304, bodies+122880, bodies+147456, bodies+172032
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
  DB A, SPC, P, U, N, C, H, SPC, SPC, B, SPC, J, U, M, P, END
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
bodies:                          ; NBODY x (PL_BYTES + PLX_BYTES): the selectable bodies
  INCBIN "bodies.bin"
bossrigs:                        ; 4 x six big-rig frames: bruiser, Brick, Viper, Warden
  INCBIN "bosses.bin"
bosspal:                         ; 3 x 15 RGB555: each boss's bank-6 colours
  INCBIN "bosspal.bin"
tiledata:                        ; VRAM tiles from index 0
  INCBIN "tiles.bin"
tiledataend:
