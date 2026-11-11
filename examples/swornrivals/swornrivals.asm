; ============================================================================
; SWORN RIVALS — a 1v1 versus fighter for CastlePalm
;
;   Two fighters from the Street Brawl character creator duel in the courtyard of
;   the Palmgate. Before each round both players secretly swear an oath with a face
;   button (A No Guard, B Fists Only, X Sky Striker, Y Stand Fast). Keeping it fills
;   the Oath meter; breaking it hands the whole meter to the rival. A full meter
;   powers the Oath Surge super.
;
;   Controls:  Left/Right walk (away = block)  Down crouch  Up jump
;              A light punch  X heavy punch  B light kick  Y heavy kick
;              Fwd/Back + X up close  throw (both throwing at once: a tech, nobody falls)
;              Down, Down-fwd, Fwd + punch    Seal Bolt (projectile; X is the fast one)
;              Fwd, Down, Down-fwd + punch    Palm Rise
;              Down, Down-back, Back + punch  Gate Rush
;              Down, Down-fwd, Fwd + kick     Oath Surge (full meter)
;   Light attacks chain into light attacks and most normals cancel into specials on
;   contact; a run of hits is a combo (counted on screen, damage scales from hit 3).
;   Taking damage fast builds stun: past DIZMAX the fighter is dizzy until it wears off.
;   1P Arcade: a ladder of four CPU rivals. 2P Versus: player 2 on INPUT1.
;
;   Art: examples/swornrivals/gen_art.js draws the courtyard, HUD, fonts and every body in 17
;   poses. Fighter frames are not resident: each frame the cart DMAs the current
;   pose of each fighter into a 64-tile VRAM slot (4 KB a frame).
;       node examples/swornrivals/gen_art.js
;       node tools/build-cart.js examples/swornrivals/swornrivals.asm swornrivals.cpc "SWORN RIVALS"
;
;   Layers: BG0 = sky + far palace (cam/2 parallax). BG1 = the courtyard, HUD in map
;   rows 0-2. The hblank handler paints the per-line sky into palette entry 0 and
;   holds BG1 unscrolled for lines 0-23 (the HUD), like Street Brawl.
; ============================================================================

; ---- MMIO ----
INPUT0     EQU $100000
INPUT1     EQU $100002
VRAM_ADDR  EQU $101000
VRAM_DATA  EQU $101004
PAL_INDEX  EQU $101008
PAL_DATA   EQU $10100A
OAM_INDEX  EQU $10100C
OAM_DATA   EQU $10100E
BG0_SX     EQU $101010
BG1_SX     EQU $101014
PPU_CTRL   EQU $101018
PPU_LINE   EQU $10101A
IRQ_ENABLE EQU $100012
FRAMECTR   EQU $100014
SAVECOMMIT EQU $100016
DMA_SRC    EQU $100020
DMA_DST    EQU $100024
DMA_LEN    EQU $100028
DMA_MODE   EQU $10002A
DMA_FILL   EQU $10002C
DMA_CTRL   EQU $10002E
SQ0_PERIOD EQU $102000
SQ0_VOL    EQU $102002
SQ0_CTRL   EQU $102003
SQ1_PERIOD EQU $102004
SQ1_VOL    EQU $102006
SQ1_CTRL   EQU $102007
NOISE_PER  EQU $102008
NOISE_VOL  EQU $10200A
NOISE_CTRL EQU $10200B

; ---- save RAM ----
SV_MAG   EQU $200000      ; u16 marker
SV_P1    EQU $200002      ; 6 bytes: P1 creator picks
SV_P2    EQU $200008      ; 6 bytes: P2 creator picks
SV_BEST  EQU $20000E      ; u16 rivals beaten in the best arcade run
SVMAGIC  EQU $DC01

; ---- input bits ----
UP    EQU 1
DOWN  EQU 2
LEFT  EQU 4
RIGHT EQU 8
ABTN  EQU 16
BBTN  EQU 32
XBTN  EQU 64
YBTN  EQU 128
START EQU 256

; ---- tiles (must match T in examples/swornrivals/gen_art.js) ----
HP_FULL   EQU 1
HP_HALF   EQU 2
HP_EMPTY  EQU 3
MT_FULL   EQU 4
MT_EMPTY  EQU 5
MT_READY  EQU 6
SEAL_OK   EQU 7
SEAL_BROKE EQU 8
SEAL_NONE EQU 9
PIP_ON    EQU 10
PIP_OFF   EQU 11
HP_HALFR  EQU 12          ; half cell, full side on the right (P1's bar)
PANEL     EQU 22          ; SOLID swatch of the stone bank's darkest colour
PB_STONE  EQU 2
SOLID     EQU 16
P1SLOT    EQU 128
P2SLOT    EQU 192
BIG       EQU 256
TITLE     EQU 512
SPARK     EQU 688
BSPARK    EQU 696
SHADOW    EQU 704
BOLT      EQU 720
STARS     EQU 728
PORT      EQU 736
; ---- palette banks ----
PB_HUD    EQU 0
PB_FONT   EQU 3
PB_FLASH  EQU 4
PB_SPARK  EQU 5
PB_P2     EQU 8
PB_P1     EQU 9
PB_BIG    EQU 12
PB_TITLE  EQU 13
PB_STATUE EQU 14
PB_SHADOW EQU 15
SZ16      EQU $10
SZ32      EQU $20
SZ64      EQU $30
; ---- poses (index into a body's frames; must match POSES in the art tool) ----
PO_GUARD  EQU 0
PO_WALK1  EQU 1
PO_WALK2  EQU 2
PO_CROUCH EQU 3
PO_JUMP   EQU 4
PO_PUNCH  EQU 5
PO_KICK   EQU 6
PO_CPUNCH EQU 7
PO_LOWKICK EQU 8
PO_AIRPUNCH EQU 9
PO_AIRKICK EQU 10
PO_BLOCK  EQU 11
PO_CBLOCK EQU 12
PO_HURT   EQU 13
PO_DOWN   EQU 14
PO_RISE   EQU 15
PO_WIN    EQU 16
PO_HPUNCH EQU 17
PO_HKICK  EQU 18
PO_GRAB   EQU 19
PO_FIRE   EQU 20
PO_DIZZY  EQU 21
NPOSE     EQU 22
BODYSZ    EQU 45056       ; NPOSE * 2048 bytes per body
STAGEREC  EQU 632         ; bytes per stage record (224-word sky, 12-word bank 1, 80 words of courtyard banks)
NBODY     EQU 8

; ---- tuning ----
GROUNDY   EQU 196         ; feet line on screen
SPRY      EQU 134         ; GROUNDY - 62: 64x64 sprite top for a grounded fighter
XMINW     EQU 24          ; arena clamp (world x)
XMAXW     EQU 488
MAXSEP    EQU 272         ; fighters never further apart (both stay on screen)
BODYW     EQU 24          ; body push distance
CAMMAX    EQU 192
HP0       EQU 128
MTRMAX    EQU 32
JUMPV     EQU $FB00       ; -5.0 px/f launch (8.8)
RISEV     EQU $FB80       ; Palm Rise lift
KNOCKV    EQU $FD00       ; knockdown arc
GRAV      EQU $0040
JUMPVX    EQU 2
BACKSTEP  EQU 16          ; Stand Fast breaks after this many back-walk frames in a row
DOWNT     EQU 40          ; frames on the floor after a knockdown
MOTIONW   EQU 16          ; motion input window (frames)
ROUNDSECS EQU 60
OATHT     EQU 480         ; oath screen clock
HUDLINES  EQU 24
DIZMAX    EQU 40          ; stun points that make a fighter dizzy
DIZT      EQU 110         ; dizzy frames (mashing shortens it)
THROWR    EQU 40          ; throw range (centre to centre)
CXLWIN    EQU 6           ; recovery frames that can still be cancelled
BOLTY     EQU 34          ; Seal Bolt height above the floor
; ---- fighter states ----
ST_IDLE   EQU 0
ST_CROUCH EQU 1
ST_JUMP   EQU 2
ST_ATK    EQU 3
ST_BLOCK  EQU 4
ST_HURT   EQU 5
ST_DOWN   EQU 6
ST_KO     EQU 7
ST_WIN    EQU 8
ST_DIZZY  EQU 9
; ---- attacks (ATKTAB rows) ----
AK_PUNCH  EQU 0
AK_KICK   EQU 1
AK_CPUNCH EQU 2
AK_SWEEP  EQU 3
AK_APUNCH EQU 4
AK_AKICK  EQU 5
AK_RUSH   EQU 6
AK_RISE   EQU 7
AK_SURGE  EQU 8
AK_HPUNCH EQU 9
AK_HKICK  EQU 10
AK_CHPUNCH EQU 11
AK_CLK    EQU 12
AK_AHPUNCH EQU 13
AK_AHKICK EQU 14
AK_BOLTL  EQU 15
AK_BOLTH  EQU 16
AK_THROW  EQU 17
AK_BTHROW EQU 18
AK_NEEDLEL EQU 19         ; character specials (CHSPEC picks which a fighter has)
AK_NEEDLEH EQU 20
AK_EMBERL EQU 21
AK_EMBERH EQU 22
AK_RAM    EQU 23
AK_LARK   EQU 24
AK_WHEEL  EQU 25
AK_CRUSH  EQU 26
AK_BELL   EQU 27
; ATKTAB record fields
AT_S      EQU 0           ; startup
AT_A      EQU 1           ; active
AT_R      EQU 2           ; recovery
AT_DMG    EQU 3
AT_HS     EQU 4           ; hitstun
AT_BS     EQU 5           ; blockstun
AT_X0     EQU 6           ; box x start (from centre, facing right)
AT_X1     EQU 7           ; box x end
AT_Y0     EQU 8           ; box bottom (px above feet)
AT_Y1     EQU 9           ; box top
AT_KIND   EQU 10          ; 0 mid, 1 low, 2 overhead
AT_FL     EQU 11          ; flags
AT_P0     EQU 12          ; pose: startup, active, recovery
AT_P1     EQU 13
AT_DASH   EQU 14          ; px/f forward while active
AT_P2     EQU 15
AF_KD     EQU 1           ; knockdown
AF_KICK   EQU 2           ; a kick (breaks Fists Only)
AF_MULTI  EQU 4           ; re-hits every 8 active frames
AF_INV    EQU 8           ; invulnerable during startup
AF_RISE   EQU 16          ; lifts off at the first active frame
AF_GROUND EQU 32          ; a ground attack (breaks Sky Striker)
AF_AIR    EQU 64          ; stays active until landing
AT_FL2    EQU 16          ; more flags (rows are 32 bytes)
AT_ALT    EQU 17          ; multi-hit attacks alternate AT_P1 with this pose
F2_CHAIN  EQU 1           ; a light normal: chains into light normals on contact
F2_CXL    EQU 2           ; cancels into a special on contact
F2_SPEC   EQU 4           ; a special: chip damage when blocked
F2_PROJ   EQU 8           ; fires a Seal Bolt (AT_DASH = speed) instead of hitting
F2_THROW  EQU 16          ; a throw: unblockable, needs a grounded rival in range
F2_BACK   EQU 32          ; a back throw: the rival lands behind
; ---- oaths ----
OA_NONE   EQU 0
OA_GUARD  EQU 1           ; No Guard
OA_FISTS  EQU 2           ; Fists Only
OA_SKY    EQU 3           ; Sky Striker
OA_STAND  EQU 4           ; Stand Fast
; ---- game states ----
G_TITLE   EQU 0
G_CREATE  EQU 1
G_OATH    EQU 2
G_INTRO   EQU 3
G_FIGHT   EQU 4
G_KO      EQU 5
G_MATCH   EQU 6
G_CHAMP   EQU 7
G_SELECT  EQU 8
G_VS      EQU 9
G_BONUSEND EQU 10
CARTBODY  EQU 8           ; the bonus-stage cart streams as body 8 (BODYTAB / NAMETAB)
BONUSSECS EQU 30
NRIVAL    EQU 4
; ---- creator layout (as Street Brawl) ----
CP_HAIR  EQU 36
CP_TOP   EQU 68
CP_LEGS  EQU 128
CP_SHOES EQU 188
CP_OL    EQU 220
CP_TRIM  EQU 222
CROWS    EQU 6
CROW0    EQU 6
CROWEND  EQU 18
CROWPY   EQU 48
CLAB     EQU 15
CARL     EQU 22
CARR     EQU 30
CURX     EQU 108

; ---- fighter record (128 bytes; A2 = self, A3 = rival) ----
FX     EQU 0              ; world x (centre), px
FXF    EQU 2              ; x sub-pixel accumulator (0..255)
FY     EQU 4              ; height, 8.8, 0 = ground, negative = up
FVY    EQU 6
FVX    EQU 8              ; px/f while airborne
FST    EQU 10
FT     EQU 12
FFACE  EQU 14             ; 0 right, 1 left
FHP    EQU 16
FMTR   EQU 18
FOATH  EQU 20
FOBRK  EQU 22             ; 1 once the oath is broken
FATK   EQU 24
FHIT   EQU 26             ; current attack already connected
FPAD   EQU 28
FPADP  EQU 30
FEDGE  EQU 32
FDIR   EQU 34             ; last relative direction code
FBUF   EQU 36             ; 8 x (code word, stamp word)
FBUFI  EQU 68
FPOSE  EQU 70
FBODY  EQU 72
FBANK  EQU 74
FSLOT  EQU 76             ; VRAM tile of the frame slot
FBACK  EQU 78
FPUSH  EQU 80
FPUSHV EQU 82
FWINS  EQU 84
FFLASH EQU 86
FANIM  EQU 88
FSPD   EQU 90             ; walk speed 8.8
FDMGB  EQU 92
FARMR  EQU 94
FREACH EQU 96
FCPU   EQU 98
FAI    EQU 100
FTHINK EQU 102
FAIPAD EQU 104
FAIATK EQU 106            ; CPU's chosen attack + 1 (0 = none)
FID    EQU 108            ; 0 = P1, 1 = P2
FCRCH  EQU 110
FAIHOLD EQU 112
FPJT   EQU 114            ; Seal Bolt: frames alive (0 = none)
FPJX   EQU 116            ; world x
FPJV   EQU 118            ; px/f, signed
FPJA   EQU 120            ; attack row that fired it
FDIZ   EQU 122            ; stun points
FCMB   EQU 124            ; hits in this fighter's current combo
FAICX  EQU 126            ; CPU: follow-up already decided for this attack
F1     EQU $000200
F2     EQU $000280

; ---- RAM ----
gstate   EQU $000100
mode     EQU $000102      ; 0 arcade, 1 versus, 2 training, 3 attract demo
in0      EQU $000104
in0p     EQU $000106
in1      EQU $000108
in1p     EQU $00010A
e0       EQU $00010C      ; newly pressed this frame
e1       EQU $00010E
sfxT     EQU $000110
mIdx     EQU $000112
mT       EQU $000114
wframe   EQU $000116
rng      EQU $000118
timer    EQU $00011A
tsub     EQU $00011C
round    EQU $00011E
rival    EQU $000120
cam      EQU $000122
freeze   EQU $000124
gT       EQU $000126      ; per-screen timer
csel     EQU $000128
cwho     EQU $00012A
cedge    EQU $00012C
tick     EQU $00012E
sprpri   EQU $000130
svrem    EQU $000132
sel      EQU $000134
brkT     EQU $000136
brkWho   EQU $000138
brkOath  EQU $00013A
sparkT   EQU $00013C
sparkX   EQU $00013E
sparkY   EQU $000140
sparkK   EQU $000142
best     EQU $000144
winner   EQU $000146      ; round/match winner: 1 P1, 2 P2, 0 draw
kokind   EQU $000148      ; 0 KO, 1 time
sw1      EQU $00014A      ; oath sworn flags
sw2      EQU $00014C
noiseT   EQU $00014E
show     EQU $000150      ; bit0 draw F1, bit1 draw F2
surgeT   EQU $000152
tmpx     EQU $000154
picks    EQU $000160      ; P1 picks (6) then P2 picks (6)
tpick    EQU $000170      ; scratch copy for applypicks
cmbT     EQU $000180      ; combo banner frames, P1 then P2 (words)
cmbN     EQU $000184      ; combo banner hit count, P1 then P2
techT    EQU $000188      ; "TECH" banner frames
cmbstr   EQU $00018A      ; "nn HITS" built at runtime (8 bytes)
latch    EQU $000192      ; presses made during hit freeze, P1 then P2 (words)
selp1    EQU $000196      ; select cursors (fighter index), P1 then P2
selp2    EQU $000198
selok1   EQU $00019A      ; select confirmed, P1 then P2 (must follow selp1/selp2)
selok2   EQU $00019C
selT     EQU $00019E      ; beat after both confirm
bonus    EQU $0001A0      ; 1 while the bonus stage runs
bonusnx  EQU $0001A2      ; the next arcade match is the bonus stage
score    EQU $0001A4
numstr   EQU $0001A6      ; decimal digits built at runtime (6 bytes)
rpick    EQU $0001AC      ; the rival's picks (6 bytes)
dmode    EQU $0001B2      ; training: dummy 0 stand, 1 crouch, 2 jump, 3 guard, 4 CPU
stT      EQU $0001B4      ; training: frames Start has been held
lastdmg  EQU $0001B6      ; training: damage of the last combo on the dummy
freeT    EQU $0001B8      ; training: frames the dummy has been free
ilast    EQU $0001BA      ; training: last recorded direction
sfxP     EQU $0001DC      ; sound sequence: byte offset into SFXDATA (0 = none)
slowT    EQU $0001DE      ; KO slow motion frames left
lbuf     EQU $0001E0      ; one line of an ending (32 bytes)
ihist    EQU $0001C0      ; training: P1 input history, newest first (8 words: dir | buttons)
istr     EQU $0001D0      ; training: one history line (12 bytes)
SX_RISE  EQU 1
SX_BOLT  EQU 2
SX_RUSH  EQU 3
SX_SMASH EQU 4
SX_SUPER EQU 5
SX_KO    EQU 6
SX_BLOCK EQU 7
SX_THROW EQU 8
recbuf   EQU $001000      ; training: the recorded dummy pads, relative to facing (240 words)
recN     EQU $001200      ; training: frames recorded
recP     EQU $001202      ; training: playback position
dpick    EQU $001204      ; attract demo: P1's picks (6 bytes)
demoT    EQU $00120A      ; attract demo: frames shown
idleT    EQU $00120C      ; title: frames without a press
SKYTAB   EQU $000400
CHARPAL  EQU $000600

  ORG $300000
  DA start
  DA 0
  DA hblank
  DA 0

; ============================ boot ============================
start:
  CALL loadart
  MOV R0, #3
  STW R0, [PPU_CTRL]
  MOV R0, #0
  STW R0, [in0]
  STW R0, [in1]
  STW R0, [sfxT]
  STW R0, [noiseT]
  STW R0, [mIdx]
  STW R0, [mT]
  STW R0, [freeze]
  STW R0, [mode]
  MOV R0, #$1D2B
  STW R0, [rng]
  CALL initfighters
  CALL loadsave
  CALL inittitle
  MOV R0, #2
  STB R0, [IRQ_ENABLE]
  EI

mainloop:
  CALL readpads
  LDW R0, [mode]
  CMP R0, #3
  BNE ml_go
  CALL demotick
ml_go:
  LDW R0, [gstate]
  MOV R1, R0
  SHL R1, #1
  ADD R1, R0              ; * 3 (DA entries)
  LDA A0, #GSTAB
  ADD A0, R1
  LDADDR A0, [A0]
  CALL [A0]
  CALL streamframes
  LDW R0, [cam]
  SHR R0, #1
  STW R0, [BG0_SX]
  CALL sfxtick
  CALL musictick
  LDW R0, [FRAMECTR]      ; hblank IRQs also wake WAIT: sleep until the frame counter moves
  STW R0, [wframe]
ml_sleep:
  WAIT
  LDW R0, [FRAMECTR]
  LDW R1, [wframe]
  CMP R0, R1
  BEQ ml_sleep
  BRA mainloop

GSTAB:
  DA titleframe, creatorframe, oathframe, introframe, fightframe, koframe, matchframe, champframe
  DA selectframe, vsframe, bonusendframe

; ---- hblank: sets up the NEXT line: sky colour, and BG1 scroll (0 over the HUD) ----
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
  STW R1, [BG1_SX]
  BRA hb_sky
hb_cam:
  CMP R0, #HUDLINES
  BNE hb_sky
  LDW R1, [cam]
  STW R1, [BG1_SX]
hb_sky:
  SHL R0, #1
  LDA A0, #SKYTAB
  ADD A0, R0
  LDW R1, [A0]
  MOV R0, #0
  STB R0, [PAL_INDEX]
  STW R1, [PAL_DATA]
  POPA A0
  POP R1
  POP R0
  IRET

; ---- pads: held words and newly-pressed edges for both controllers ----
readpads:
  LDW R0, [in0]
  STW R0, [in0p]
  LDW R1, [INPUT0]
  STW R1, [in0]
  NOT R0
  AND R0, R1
  STW R0, [e0]
  LDW R0, [in1]
  STW R0, [in1p]
  LDW R1, [INPUT1]
  STW R1, [in1]
  NOT R0
  AND R0, R1
  STW R0, [e1]
  RET

; ---- either pad's edge word (menus accept both controllers) ----
anyedge:
  LDW R0, [e0]
  LDW R1, [e1]
  OR R0, R1
  RET

; ---- nextrng -> R0 (xorshift16) ----
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

; ---- both(A0=routine): run it as (A2=F1, A3=F2) then (A2=F2, A3=F1) ----
both:
  PUSHA A0
  LDA A2, #F1
  LDA A3, #F2
  CALL [A0]
  POPA A0
  LDA A2, #F2
  LDA A3, #F1
  CALL [A0]
  RET

; ============================ fighters: setup ============================
initfighters:
  LDA A2, #F1
  MOV R0, #0
  STW R0, [A2+#FID]
  MOV R0, #PB_P1
  STW R0, [A2+#FBANK]
  MOV R0, #P1SLOT
  STW R0, [A2+#FSLOT]
  LDA A2, #F2
  MOV R0, #1
  STW R0, [A2+#FID]
  MOV R0, #PB_P2
  STW R0, [A2+#FBANK]
  MOV R0, #P2SLOT
  STW R0, [A2+#FSLOT]
  RET

; ---- resetfighter(A2, R0=world x, R1=face): fresh for a round ----
resetfighter:
  STW R0, [A2+#FX]
  STW R1, [A2+#FFACE]
  MOV R0, #0
  STW R0, [A2+#FXF]
  STW R0, [A2+#FY]
  STW R0, [A2+#FVY]
  STW R0, [A2+#FVX]
  STW R0, [A2+#FST]
  STW R0, [A2+#FT]
  STW R0, [A2+#FMTR]
  STW R0, [A2+#FOATH]
  STW R0, [A2+#FOBRK]
  STW R0, [A2+#FHIT]
  STW R0, [A2+#FBACK]
  STW R0, [A2+#FPUSH]
  STW R0, [A2+#FFLASH]
  STW R0, [A2+#FANIM]
  STW R0, [A2+#FCRCH]
  STW R0, [A2+#FAIPAD]
  STW R0, [A2+#FAIATK]
  STW R0, [A2+#FAIHOLD]
  STW R0, [A2+#FPAD]
  STW R0, [A2+#FPADP]
  STW R0, [A2+#FDIR]
  STW R0, [A2+#FPOSE]
  STW R0, [A2+#FPJT]
  STW R0, [A2+#FDIZ]
  STW R0, [A2+#FCMB]
  STW R0, [A2+#FAICX]
  MOV R0, #20
  STW R0, [A2+#FTHINK]
  MOV R0, #HP0
  STW R0, [A2+#FHP]
  RET

; ---- resetround: both fighters at their marks, camera centred, clock full ----
resetround:
  LDA A2, #F1
  MOV R0, #196
  MOV R1, #0
  CALL resetfighter
  LDA A2, #F2
  MOV R0, #316
  MOV R1, #1
  CALL resetfighter
  MOV R0, #96
  STW R0, [cam]
  MOV R0, #ROUNDSECS
  STW R0, [timer]
  MOV R0, #0
  STW R0, [tsub]
  STW R0, [tick]
  STW R0, [freeze]
  STW R0, [brkT]
  STW R0, [sparkT]
  STW R0, [surgeT]
  STW R0, [techT]
  STW R0, [cmbT]
  STW R0, [cmbT+2]
  STW R0, [latch]
  STW R0, [latch+2]
  MOV R0, #3
  STW R0, [show]
  RET

; ---- applypicks(A0=6 picks, A1=fighter): body + build stats + palette bank ----
applypicks:
  PUSHA A2
  MOVA A2, A1
  LDA A1, #tpick
  MOV R2, #6
ak_cp:
  LDB R0, [A0]
  STB R0, [A1]
  INC A0
  INC A1
  SUB R2, #1
  BNE ak_cp
  LDB R0, [tpick]
  STW R0, [A2+#FBODY]
  LDA A0, #BODYBUILD
  ADD A0, R0
  LDB R0, [A0]
  SHL R0, #3               ; 8 bytes per build row
  LDA A0, #BUILDTAB
  ADD A0, R0
  LDW R0, [A0]
  STW R0, [A2+#FSPD]
  LDB R0, [A0+#2]
  STW R0, [A2+#FDMGB]
  LDB R0, [A0+#3]
  STW R0, [A2+#FARMR]
  LDB R0, [A0+#4]
  STW R0, [A2+#FREACH]
  LDA A1, #CHARPAL
  LDA A0, #charpal+CP_OL
  MOV R2, #1
  CALL cpwords             ; outline
  LDB R0, [tpick+1]
  MOV R1, #6
  MULU R0, R1
  LDA A0, #charpal
  ADD A0, R0
  MOV R2, #3
  CALL cpwords             ; skin
  LDB R0, [tpick+2]
  MOV R1, #4
  MULU R0, R1
  LDA A0, #charpal+CP_HAIR
  ADD A0, R0
  MOV R2, #2
  CALL cpwords             ; hair
  LDB R0, [tpick+3]
  MOV R1, #6
  MULU R0, R1
  LDA A0, #charpal+CP_TOP
  ADD A0, R0
  MOV R2, #3
  CALL cpwords             ; top
  LDB R0, [tpick+4]
  MOV R1, #6
  MULU R0, R1
  LDA A0, #charpal+CP_LEGS
  ADD A0, R0
  MOV R2, #3
  CALL cpwords             ; legs
  LDB R0, [tpick+5]
  MOV R1, #4
  MULU R0, R1
  LDA A0, #charpal+CP_SHOES
  ADD A0, R0
  MOV R2, #2
  CALL cpwords             ; shoes
  LDA A0, #charpal+CP_TRIM
  MOV R2, #1
  CALL cpwords             ; trim
  LDW R0, [A2+#FBANK]
  SHL R0, #5
  ADD R0, #2               ; palette byte offset of entry 1
  LDA A0, #CHARPAL
  MOV R1, #30
  CALL dmapal
  POPA A2
  RET

cpwords:
  LDW R0, [A0]
  STW R0, [A1]
  ADD A0, #2
  ADD A1, #2
  SUB R2, #1
  BNE cpwords
  RET

; ---- applyplayers: P1 (and P2 in versus) from the saved picks ----
applyp1:
  LDA A0, #picks
  LDA A1, #F1
  CALL applypicks
  RET
applyp2:
  LDA A0, #picks+6
  LDA A1, #F2
  CALL applypicks
  RET

; ---- setuprival: F2 becomes the current ladder rival ----
setuprival:
  LDW R0, [rival]
  SHL R0, #3
  LDA A0, #RIVTAB
  ADD A0, R0
  PUSHA A0
  LDA A1, #rpick           ; copy, so a mirror match can swap colours
  MOV R2, #6
sr_cp:
  LDB R0, [A0]
  STB R0, [A1]
  INC A0
  INC A1
  SUB R2, #1
  BNE sr_cp
  LDA A0, #picks           ; the player in the rival's exact colours? rival takes its alt
  LDA A1, #rpick
  MOV R2, #6
sr_eq:
  LDB R0, [A0]
  LDB R1, [A1]
  CMP R0, R1
  BNE sr_ap
  INC A0
  INC A1
  SUB R2, #1
  BNE sr_eq
  LDB R0, [rpick]
  MOV R3, R0
  SHL R3, #3
  ADD R3, R0
  ADD R3, R0
  ADD R3, #5
  LDA A0, #CHARCOL
  ADD A0, R3
  LDA A1, #rpick+1
  MOV R2, #5
sr_alt:
  LDB R0, [A0]
  STB R0, [A1]
  INC A0
  INC A1
  SUB R2, #1
  BNE sr_alt
sr_ap:
  LDA A0, #rpick
  LDA A1, #F2
  CALL applypicks
  POPA A0
  LDA A2, #F2
  LDB R0, [A0+#6]
  STW R0, [A2+#FAI]
  MOV R0, #1
  STW R0, [A2+#FCPU]
  LDW R0, [A2+#FBODY]      ; the rival's home stage
  CALL homestage
  RET

; ============================ character select ============================
; ---- initselect(R0 = 1 fresh, 0 back from tailoring): portraits, previews ----
initselect:
  CMP R0, #0
  BEQ is_keep
  MOV R0, #0
  STW R0, [selok1]
  STW R0, [selok2]
is_keep:
  MOV R0, #G_SELECT
  STW R0, [gstate]
  MOV R0, #0
  STW R0, [cam]
  STW R0, [gT]
  STW R0, [selT]
  STW R0, [bonus]
  LDB R0, [picks]
  STW R0, [selp1]
  LDB R0, [picks+6]
  STW R0, [selp2]
  CALL copymaps
  CALL clearhud
  MOV R4, #9
  MOV R5, #3
  MOV R6, #31
  MOV R7, #23
  CALL panel
  CALL applyp1
  CALL applyp2
  LDA A2, #F1
  MOV R0, #36
  MOV R1, #0
  CALL resetfighter
  LDA A2, #F2
  MOV R0, #284
  MOV R1, #1
  CALL resetfighter
  MOV R0, #1
  LDW R1, [mode]
  CMP R1, #0
  BEQ is_sh
  MOV R0, #3
is_sh:
  STW R0, [show]
  RET

selectframe:
  LDW R0, [gT]
  ADD R0, #1
  STW R0, [gT]
  LDW R0, [selok1]         ; training: the dummy is picked once P1 is done
  PUSH R0
  MOV R4, #0
  CALL selside
  POP R0
  LDW R1, [mode]
  CMP R1, #0
  BEQ sf_chk
  CMP R1, #2
  BNE sf_s2
  CMP R0, #0
  BEQ sf_chk
sf_s2:
  MOV R4, #1
  CALL selside
sf_chk:
  LDW R0, [selok1]
  CMP R0, #0
  BEQ sf_draw
  LDW R0, [mode]
  CMP R0, #0
  BEQ sf_beat
  LDW R0, [selok2]
  CMP R0, #0
  BEQ sf_draw
sf_beat:
  LDW R0, [selT]           ; a short beat on the win poses, then the match
  ADD R0, #1
  STW R0, [selT]
  CMP R0, #40
  BLT sf_draw
  CALL mirrorfix
  CALL savepicks
  CALL newmatch
  RET
sf_draw:
  LDA A2, #F1
  LDW R0, [selok1]
  CALL selpose
  LDA A2, #F2
  LDW R0, [selok2]
  CALL selpose
  CALL oambegin
  MOV R0, #6
  STW R0, [sprpri]
  MOV R1, #6
  LDA A1, #sCHOOSE
  CALL cbig
  MOV R4, #0
sf_port:
  PUSH R4
  MOV R0, R4               ; x = 84 + col * 40, y = 36 + row * 40
  AND R0, #3
  MOV R1, R0
  SHL R0, #5
  SHL R1, #3
  ADD R0, R1
  ADD R0, #84
  MOV R1, R4
  SHR R1, #2
  MOV R2, R1
  SHL R1, #5
  SHL R2, #3
  ADD R1, R2
  ADD R1, #36
  MOV R6, #PB_STATUE       ; stone, unless a cursor is on it
  LDW R2, [mode]
  CMP R2, #0
  BEQ sf_p1c
  LDW R2, [selp2]
  CMP R2, R4
  BNE sf_p1c
  MOV R6, #PB_P2
  PUSH R0
  PUSH R1
  ADD R0, #33
  ADD R1, #12
  LDW R2, [selok2]
  LDA A1, #sTWO
  CALL sellabel
  POP R1
  POP R0
sf_p1c:
  LDW R2, [selp1]
  CMP R2, R4
  BNE sf_pe
  MOV R6, #PB_P1
  PUSH R0
  PUSH R1
  SUB R0, #9
  ADD R1, #12
  LDW R2, [selok1]
  LDA A1, #sONE
  CALL sellabel
  POP R1
  POP R0
  MOV R6, #PB_P1
sf_pe:
  OR R6, #SZ32
  MOV R5, R4
  SHL R5, #4
  ADD R5, #PORT
  CALL emittile
  POP R4
  ADD R4, #1
  CMP R4, #NBODY
  BGE sf_pdone
  JMP sf_port
sf_pdone:
  LDW R0, [mode]
  CMP R0, #0
  BNE sf_two
  LDW R0, [selp1]          ; 1P: name, title and specials of the fighter under the cursor
  CALL fdata
  PUSHA A0
  MOV R1, #114
  CALL cbig
  POPA A0
  LDADDR A1, [A0]
  MOV R1, #134
  CALL ctext
  LDW R0, [selp1]
  MOV R1, #146
  CALL movelist
  BRA sf_hint
sf_two:
  LDW R0, [selp1]          ; versus: both names
  CALL fdata
  MOV R0, #76
  MOV R1, #114
  CALL btext
  LDW R0, [selp2]
  CALL fdata
  CALL strlen
  SHL R0, #4
  NEG R0
  ADD R0, #244
  MOV R1, #134
  CALL btext
sf_hint:
  LDW R0, [mode]
  CMP R0, #2
  BNE sf_h
  MOV R1, #200
  LDA A1, #sTSEL1
  LDW R0, [selok1]
  CMP R0, #0
  BEQ sf_th
  LDA A1, #sTSEL2
sf_th:
  CALL ctext
sf_h:
  MOV R1, #212
  LDA A1, #sSELHINT
  CALL ctext
  CALL drawfighters
  RET

; ---- sellabel(R0, R1, A1 = "1"/"2", R2 = confirmed): blinks until confirmed ----
sellabel:
  CMP R2, #0
  BNE sl1_on
  LDW R2, [gT]
  AND R2, #16
  BNE sl1_off
sl1_on:
  PUSH R6
  CALL stext
  POP R6
sl1_off:
  RET

; ---- selpose(A2, R0 = confirmed): win pose once picked ----
selpose:
  MOV R1, #PO_GUARD
  CMP R0, #0
  BEQ sp1_set
  MOV R1, #PO_WIN
sp1_set:
  STW R1, [A2+#FPOSE]
  RET

; ---- fdata(R0 = fighter) -> A1 = name, A0 = its EPITAB entry ----
fdata:
  MOV R1, R0
  SHL R1, #1
  ADD R1, R0
  LDA A0, #NAMETAB
  ADD A0, R1
  LDADDR A1, [A0]
  LDA A0, #EPITAB
  ADD A0, R1
  RET

; ---- movelist(R0 = fighter, R1 = y): three centred special lines ----
movelist:
  MOV R2, R0
  SHL R2, #3
  ADD R2, R0               ; * 9 (three DA entries)
  LDA A0, #MOVETAB
  ADD A0, R2
  MOV R4, #3
ml1_lp:
  PUSH R1
  PUSH R4
  PUSHA A0
  LDADDR A1, [A0]
  CALL ctext
  POPA A0
  POP R4
  POP R1
  ADD A0, #3
  ADD R1, #10
  SUB R4, #1
  BNE ml1_lp
  RET

; ---- selside(R4 = 0 P1 / 1 P2): move, pick (A main, B alt, Start as is), Y tailor ----
selside:
  MOV R0, R4
  SHL R0, #1
  LDA A1, #selp1
  ADD A1, R0
  LDW R0, [A1+#4]
  CMP R0, #0
  BEQ ss1_live
  RET
ss1_live:
  LDW R1, [e0]
  CMP R4, #0
  BEQ ss1_pad
  LDW R2, [mode]           ; training: pad 1 also picks the dummy
  CMP R2, #2
  BEQ ss1_pad
  LDW R1, [e1]
ss1_pad:
  LDW R0, [A1]
  MOV R2, R1
  AND R2, #LEFT
  BEQ ss1_r
  MOV R3, R0
  AND R3, #4
  SUB R0, #1
  AND R0, #3
  OR R0, R3
  BRA ss1_mv
ss1_r:
  MOV R2, R1
  AND R2, #RIGHT
  BEQ ss1_ud
  MOV R3, R0
  AND R3, #4
  ADD R0, #1
  AND R0, #3
  OR R0, R3
  BRA ss1_mv
ss1_ud:
  MOV R2, R1
  AND R2, #UP+DOWN
  BEQ ss1_btn
  XOR R0, #4
ss1_mv:
  STW R0, [A1]
  MOV R2, #0
  CALL selset
  MOV R0, #200
  CALL sfxblip
  RET
ss1_btn:
  MOV R2, R1
  AND R2, #YBTN
  BEQ ss1_a
  STW R4, [cwho]           ; tailor this fighter's colours in the creator
  CALL initcreator
  RET
ss1_a:
  MOV R2, R1
  AND R2, #ABTN
  BEQ ss1_b
  MOV R2, #0
  BRA ss1_pick
ss1_b:
  MOV R2, R1
  AND R2, #BBTN
  BEQ ss1_st
  MOV R2, #1
ss1_pick:
  LDW R0, [A1]
  PUSHA A1
  CALL selset
  POPA A1
  BRA ss1_ok
ss1_st:
  AND R1, #START
  BEQ ss1_ret
ss1_ok:
  MOV R0, #1
  STW R0, [A1+#4]
  MOV R0, #120
  CALL sfxblip
ss1_ret:
  RET

; ---- selset(R4 = side, R0 = fighter, R2 = 0 main / 1 alt colours): picks + fighter ----
selset:
  MOV R3, R4               ; picks + side * 6
  SHL R3, #1
  MOV R5, R3
  SHL R5, #1
  ADD R3, R5
  LDA A0, #picks
  ADD A0, R3
  PUSHA A0
  STB R0, [A0]
  INC A0
  MOV R3, R0               ; CHARCOL + fighter * 10 (+5 for alt)
  SHL R3, #3
  ADD R3, R0
  ADD R3, R0
  CMP R2, #0
  BEQ ss2_m
  ADD R3, #5
ss2_m:
  LDA A1, #CHARCOL
  ADD A1, R3
  MOV R2, #5
ss2_cp:
  LDB R0, [A1]
  STB R0, [A0]
  INC A0
  INC A1
  SUB R2, #1
  BNE ss2_cp
  POPA A0
  LDA A1, #F1
  CMP R4, #0
  BEQ ss2_ap
  LDA A1, #F2
ss2_ap:
  PUSH R4
  CALL applypicks
  POP R4
  RET

; ---- mirrorfix: versus with identical fighters -> P2 takes the other colours ----
mirrorfix:
  LDW R0, [mode]
  CMP R0, #0
  BEQ mx_ret
  LDA A0, #picks
  LDA A1, #picks+6
  MOV R2, #6
mx_lp:
  LDB R0, [A0]
  LDB R1, [A1]
  CMP R0, R1
  BNE mx_ret
  INC A0
  INC A1
  SUB R2, #1
  BNE mx_lp
  LDB R0, [picks]          ; P1 in the alt colours? then P2 gets main
  MOV R3, R0
  SHL R3, #3
  ADD R3, R0
  ADD R3, R0
  ADD R3, #5
  LDA A1, #CHARCOL
  ADD A1, R3
  LDA A0, #picks+1
  MOV R2, #1
  MOV R4, #5
mx_alt:
  LDB R1, [A0]
  LDB R3, [A1]
  CMP R1, R3
  BEQ mx_n
  MOV R2, #0
mx_n:
  INC A0
  INC A1
  SUB R4, #1
  BNE mx_alt
  XOR R2, #1
  MOV R4, #1
  LDB R0, [picks]
  CALL selset
mx_ret:
  RET

; ============================ VS screen ============================
initvs:
  MOV R0, #G_VS
  STW R0, [gstate]
  MOV R0, #0
  STW R0, [gT]
  STW R0, [cam]
  CALL copymaps
  CALL clearhud
  MOV R4, #0
  MOV R5, #3
  MOV R6, #40
  MOV R7, #17
  CALL panel
  LDA A2, #F1
  MOV R0, #52
  MOV R1, #0
  CALL resetfighter
  LDA A2, #F2
  MOV R0, #268
  MOV R1, #1
  CALL resetfighter
  MOV R0, #3
  STW R0, [show]
  MOV R0, #90
  CALL sfxblip
  RET

vsframe:
  LDW R0, [gT]
  ADD R0, #1
  STW R0, [gT]
  CMP R0, #180
  BGE vs_go
  CMP R0, #20
  BLT vs_draw
  CALL anyedge
  AND R0, #START
  BEQ vs_draw
vs_go:
  CALL copymaps
  CALL clearhud
  CALL initoath
  RET
vs_draw:
  CALL idleposes
  CALL oambegin
  MOV R0, #6
  STW R0, [sprpri]
  LDA A2, #F1              ; P1: name, title, specials on the left
  LDW R0, [A2+#FBODY]
  CALL fdata
  PUSHA A0
  MOV R0, #16
  MOV R1, #28
  CALL btext
  POPA A0
  LDADDR A1, [A0]
  MOV R0, #16
  MOV R1, #48
  CALL stext
  LDA A2, #F2              ; P2 on the right, right-aligned
  LDW R0, [A2+#FBODY]
  CALL fdata
  PUSHA A0
  PUSHA A1
  CALL strlen
  POPA A1
  SHL R0, #4
  NEG R0
  ADD R0, #304
  MOV R1, #28
  CALL btext
  POPA A0
  LDADDR A1, [A0]
  PUSHA A1
  CALL strlen
  POPA A1
  SHL R0, #3
  NEG R0
  ADD R0, #304
  MOV R1, #48
  CALL stext
  MOV R0, #128             ; VS from the title letters (V = 7, S = 0)
  MOV R1, #66
  MOV R5, #TITLE+112
  MOV R6, #SZ32
  OR R6, #PB_TITLE
  CALL emittile
  MOV R0, #160
  MOV R1, #66
  MOV R5, #TITLE
  CALL emittile
  LDA A2, #F1
  LDW R0, [A2+#FBODY]
  MOV R1, #104
  MOV R4, #8
  CALL vsmoves
  LDA A2, #F2
  LDW R0, [A2+#FBODY]
  MOV R1, #104
  MOV R4, #168
  CALL vsmoves
  CALL drawfighters
  RET

; ---- vsmoves(R0 = fighter, R1 = y, R4 = x): its three special lines ----
vsmoves:
  CMP R0, #NBODY
  BGE vm_ret
  MOV R2, R0
  SHL R2, #3
  ADD R2, R0
  LDA A0, #MOVETAB
  ADD A0, R2
  MOV R3, #3
vm_lp:
  PUSH R1
  PUSH R3
  PUSH R4
  PUSHA A0
  LDADDR A1, [A0]
  MOV R0, R4
  CALL stext
  POPA A0
  POP R4
  POP R3
  POP R1
  ADD A0, #3
  ADD R1, #10
  SUB R3, #1
  BNE vm_lp
vm_ret:
  RET

; ============================ bonus stage ============================
initbonus:
  MOV R0, #1
  STW R0, [bonus]
  STW R0, [round]
  CALL applyp1
  LDA A2, #F1
  MOV R0, #0
  STW R0, [A2+#FCPU]
  LDA A2, #F2
  STW R0, [A2+#FCPU]
  STW R0, [A2+#FSPD]
  STW R0, [A2+#FDMGB]
  STW R0, [A2+#FARMR]
  STW R0, [A2+#FREACH]
  MOV R0, #CARTBODY
  STW R0, [A2+#FBODY]
  LDA A0, #cartdata+2      ; the cart's colours into P2's bank
  MOV R0, #PB_P2
  SHL R0, #5
  ADD R0, #2
  MOV R1, #30
  CALL dmapal
  MOV R0, #0
  CALL setstage
  CALL copymaps
  CALL clearhud
  CALL resetround
  MOV R0, #BONUSSECS
  STW R0, [timer]
  CALL initintro
  RET

; ---- bonusstep: the cart stays put, shows its damage, and ends the stage ----
bonusstep:
  LDA A2, #F2
  MOV R0, #316
  STW R0, [A2+#FX]
  MOV R0, #0
  STW R0, [A2+#FY]
  STW R0, [A2+#FVY]
  STW R0, [A2+#FVX]
  STW R0, [A2+#FPUSH]
  STW R0, [A2+#FDIZ]
  LDW R0, [A2+#FST]
  CMP R0, #ST_DOWN
  BLT bn_st
  MOV R0, #ST_IDLE
  STW R0, [A2+#FST]
bn_st:
  LDW R1, [A2+#FHP]
  MOV R0, #0
  CMP R1, #86
  BGE bn_p
  MOV R0, #1
  CMP R1, #43
  BGE bn_p
  MOV R0, #2
bn_p:
  STW R0, [A2+#FPOSE]
  CMP R1, #0
  BEQ bn_end
  LDW R0, [timer]
  CMP R0, #0
  BEQ bn_end
  JMP ff_draw
bn_end:
  MOV R0, #G_BONUSEND
  STW R0, [gstate]
  MOV R0, #0
  STW R0, [gT]
  MOV R0, #HP0             ; score: 50 a point of damage, 200 a second left if wrecked
  SUB R0, R1
  MOV R2, #50
  MULU R0, R2
  LDW R1, [A2+#FHP]
  CMP R1, #0
  BNE bn_sc
  LDW R2, [timer]
  MOV R3, #200
  MULU R2, R3
  ADD R0, R2
bn_sc:
  STW R0, [score]
  LDA A2, #F1
  MOV R0, #ST_WIN
  STW R0, [A2+#FST]
  MOV R0, #PO_WIN
  STW R0, [A2+#FPOSE]
  MOV R0, #80
  CALL sfxblip
  RET

bonusendframe:
  LDW R0, [gT]
  ADD R0, #1
  STW R0, [gT]
  CMP R0, #300
  BGE be_go
  CMP R0, #60
  BLT be_draw
  CALL anyedge
  AND R0, #START
  BEQ be_draw
be_go:
  CALL startmatch          ; on to the next rival
  RET
be_draw:
  CALL oambegin
  LDA A2, #F2
  LDW R0, [A2+#FHP]
  LDA A1, #sTIME
  CMP R0, #0
  BNE be_t
  LDA A1, #sWRECKED
be_t:
  MOV R1, #48
  CALL cbig
  LDW R0, [score]
  CALL utoa
  MOV R0, #96
  MOV R1, #72
  LDA A1, #sBONUSPTS
  CALL btext
  ADD R0, #16
  LDA A1, #numstr
  CALL btext
  CALL drawfighters
  CALL drawhud
  RET

; ---- utoa(R0) -> numstr: decimal, no leading zeros ----
utoa:
  LDA A1, #numstr
  LDA A0, #POW10
  MOV R3, #0               ; a digit written yet?
ua_p:
  LDW R1, [A0]
  CMP R1, #1
  BEQ ua_last
  MOV R2, #0
ua_d:
  CMP R0, R1
  BLT ua_out
  SUB R0, R1
  ADD R2, #1
  BRA ua_d
ua_out:
  ADD R3, R2
  CMP R3, #0
  BEQ ua_skip
  ADD R2, #48
  STB R2, [A1]
  INC A1
ua_skip:
  ADD A0, #2
  BRA ua_p
ua_last:
  ADD R0, #48
  STB R0, [A1]
  MOV R0, #0
  STB R0, [A1+#1]
  RET
POW10:
  DW 10000, 1000, 100, 10, 1

; ============================ attract demo ============================
; ---- initdemo: two random characters, CPU against CPU, on the second one's stage ----
initdemo:
  MOV R0, #0
  STW R0, [idleT]
  STW R0, [demoT]
  STW R0, [bonus]
  MOV R0, #3
  STW R0, [mode]
  CALL nextrng
  AND R0, #7
  PUSH R0
  LDA A0, #dpick
  CALL mkpick
  CALL nextrng
  AND R0, #7
  POP R1
  CMP R0, R1
  BNE id_d
  ADD R0, #3
  AND R0, #7
id_d:
  LDA A0, #rpick
  CALL mkpick
  LDA A0, #dpick
  LDA A1, #F1
  CALL applypicks
  LDA A0, #rpick
  LDA A1, #F2
  CALL applypicks
  LDA A2, #F1
  CALL democpu
  LDA A2, #F2
  CALL democpu
  LDW R0, [A2+#FBODY]
  CALL homestage
  MOV R0, #1
  STW R0, [round]
  CALL resetround
  JMP initintro
democpu:
  MOV R0, #1
  STW R0, [A2+#FCPU]
  MOV R0, #2
  STW R0, [A2+#FAI]
  MOV R0, #0
  STW R0, [A2+#FWINS]
  RET

; ---- mkpick(A0 = 6-byte picks, R0 = fighter): that fighter in its main colours ----
mkpick:
  STB R0, [A0]
  INC A0
  MOV R1, R0
  SHL R1, #3
  ADD R1, R0
  ADD R1, R0
  LDA A1, #CHARCOL
  ADD A1, R1
  MOV R2, #5
mk_cp:
  LDB R0, [A1]
  STB R0, [A0]
  INC A0
  INC A1
  SUB R2, #1
  BNE mk_cp
  RET

; ---- demotick: any press, or 30 seconds, ends the demo ----
demotick:
  LDW R0, [demoT]
  ADD R0, #1
  STW R0, [demoT]
  CMP R0, #1800
  BGE dt_end
  CALL anyedge
  CMP R0, #0
  BEQ dt_ret
dt_end:
  JMP demoend
dt_ret:
  RET
demoend:
  MOV R0, #0
  STW R0, [mode]
  CALL inittitle
  RET

; ============================ training ============================
; ---- inittrain: endless round on the courtyard, P1 vs the dummy ----
inittrain:
  MOV R0, #0
  STW R0, [dmode]
  STW R0, [stT]
  STW R0, [lastdmg]
  STW R0, [freeT]
  LDA A0, #ihist
  MOV R2, #8
it_cl:
  STW R0, [A0]
  ADD A0, #2
  SUB R2, #1
  BNE it_cl
  MOV R0, #5
  STW R0, [ilast]
  LDA A2, #F2              ; the dummy's home stage
  LDW R0, [A2+#FBODY]
  CALL homestage
  CALL resetround
  CALL trainsetdummy
  CALL copymaps
  CALL hudstatic
  MOV R0, #G_FIGHT
  STW R0, [gstate]
  RET

; ---- trainsetdummy: CPU control only in dummy mode 4 ----
trainsetdummy:
  LDA A2, #F2
  MOV R0, #0
  LDW R1, [dmode]
  CMP R1, #4
  BNE tsd_s
  MOV R0, #1
tsd_s:
  STW R0, [A2+#FCPU]
  MOV R0, #2
  STW R0, [A2+#FAI]
  MOV R0, #0
  STW R0, [A2+#FAIPAD]
  RET

; ---- dummypad(A2 = dummy, A3 = player) -> R1 = the dummy's pad ----
dummypad:
  LDW R0, [dmode]
  CMP R0, #5
  BLT dp_std
  BEQ dp_rec
  MOV R1, #0               ; play: loop the recording
  LDW R2, [recN]
  CMP R2, #0
  BEQ dp_out
  LDW R0, [recP]
  MOV R3, R0
  SHL R3, #1
  LDA A0, #recbuf
  ADD A0, R3
  LDW R1, [A0]
  ADD R0, #1
  CMP R0, R2
  BLT dp_pp
  MOV R0, #0
dp_pp:
  STW R0, [recP]
  CALL flippad
dp_out:
  RET
dp_rec:
  LDW R1, [in0]            ; record: pad 1 drives the dummy (stored relative to its facing)
  CALL flippad
  LDW R0, [recN]
  MOV R3, R0
  SHL R3, #1
  LDA A0, #recbuf
  ADD A0, R3
  STW R1, [A0]
  ADD R0, #1
  STW R0, [recN]
  CMP R0, #240
  BLT dp_rc
  MOV R0, #6               ; four seconds: play it back
  STW R0, [dmode]
  MOV R0, #0
  STW R0, [recP]
dp_rc:
  LDW R1, [in0]
  RET
dp_std:
  MOV R1, #0
  CMP R0, #1
  BNE dp_j
  MOV R1, #DOWN
  RET
dp_j:
  CMP R0, #2
  BNE dp_g
  MOV R1, #UP
  RET
dp_g:
  CMP R0, #3
  BNE dp_r
  LDW R0, [A3+#FST]        ; guard only while the player threatens (so it never walks off)
  CMP R0, #ST_ATK
  BEQ dp_th
  LDW R0, [A3+#FPJT]
  CMP R0, #0
  BEQ dp_r
dp_th:
  CALL dirbits
  MOV R1, R7
  LDW R0, [A3+#FY]         ; a jump-in: stand to guard
  CMP R0, #0
  BLT dp_r
  LDW R0, [A3+#FST]
  CMP R0, #ST_ATK
  BNE dp_lo
  LDW R0, [A3+#FATK]       ; an overhead: stand; anything else: crouch
  SHL R0, #5
  LDA A0, #ATKTAB
  ADD A0, R0
  LDB R0, [A0+#AT_KIND]
  CMP R0, #2
  BEQ dp_r
dp_lo:
  OR R1, #DOWN
dp_r:
  RET

; ---- flippad(A2, R1 = pad): world <-> relative to facing (swaps left/right when facing left) ----
flippad:
  LDW R0, [A2+#FFACE]
  CMP R0, #0
  BEQ fp_r
  MOV R0, R1
  AND R0, #LEFT+RIGHT
  BEQ fp_r
  CMP R0, #LEFT+RIGHT
  BEQ fp_r
  XOR R1, #LEFT+RIGHT
fp_r:
  RET

; ---- trainstep: full meter, Start cycles the dummy (hold to quit), refills, input log ----
trainstep:
  LDA A2, #F1
  MOV R0, #MTRMAX
  STW R0, [A2+#FMTR]
  LDW R0, [e0]
  AND R0, #START
  BEQ ts_hold
  LDW R0, [dmode]
  ADD R0, #1
  CMP R0, #7
  BLT ts_dm
  MOV R0, #0
ts_dm:
  STW R0, [dmode]
  MOV R1, #0               ; record starts afresh; play starts from the top
  STW R1, [recP]
  CMP R0, #5
  BNE ts_nr
  STW R1, [recN]
ts_nr:
  CALL trainsetdummy
  MOV R0, #200
  CALL sfxblip
ts_hold:
  LDW R0, [in0]
  AND R0, #START
  BEQ ts_h0
  LDW R0, [stT]
  ADD R0, #1
  STW R0, [stT]
  CMP R0, #60
  BLT ts_hp
  JMP inittitle
ts_h0:
  MOV R0, #0
  STW R0, [stT]
ts_hp:
  LDA A2, #F2              ; damage of the combo in progress / the last one
  LDW R0, [A2+#FHP]
  MOV R1, #HP0
  SUB R1, R0
  CMP R1, #0
  BEQ ts_nd
  STW R1, [lastdmg]
ts_nd:
  LDW R0, [A2+#FST]        ; free (idle, crouch, jump, attack) for 40 frames: refill
  CMP R0, #ST_BLOCK
  BLT ts_free
  MOV R0, #0
  STW R0, [freeT]
  BRA ts_in
ts_free:
  LDW R0, [freeT]
  ADD R0, #1
  STW R0, [freeT]
  CMP R0, #40
  BLT ts_in
  MOV R0, #HP0
  STW R0, [A2+#FHP]
  LDA A2, #F1
  STW R0, [A2+#FHP]
ts_in:
  LDA A2, #F1              ; input history: numpad direction (relative) | new buttons
  CALL dirbits
  LDW R1, [in0]
  MOV R2, #5
  MOV R0, R1
  AND R0, #UP
  BEQ ti_nu
  ADD R2, #3
ti_nu:
  MOV R0, R1
  AND R0, #DOWN
  BEQ ti_nd
  SUB R2, #3
ti_nd:
  MOV R0, R1
  AND R0, R6
  BEQ ti_nf
  ADD R2, #1
ti_nf:
  MOV R0, R1
  AND R0, R7
  BEQ ti_nb
  SUB R2, #1
ti_nb:
  LDW R0, [e0]
  AND R0, #ABTN+BBTN+XBTN+YBTN
  CMP R0, #0
  BNE ti_push
  LDW R1, [ilast]
  CMP R2, R1
  BEQ ti_done
ti_push:
  OR R0, R2
  STW R2, [ilast]
  LDW R1, [ihist+12]
  STW R1, [ihist+14]
  LDW R1, [ihist+10]
  STW R1, [ihist+12]
  LDW R1, [ihist+8]
  STW R1, [ihist+10]
  LDW R1, [ihist+6]
  STW R1, [ihist+8]
  LDW R1, [ihist+4]
  STW R1, [ihist+6]
  LDW R1, [ihist+2]
  STW R1, [ihist+4]
  LDW R1, [ihist]
  STW R1, [ihist+2]
  STW R0, [ihist]
ti_done:
  RET

; ---- trainhud: dummy mode, combo damage, input history, hint ----
trainhud:
  MOV R0, #200
  MOV R1, #30
  LDA A1, #sDUMMY
  CALL stext
  LDW R1, [dmode]
  MOV R0, R1
  SHL R1, #1
  ADD R1, R0
  LDA A0, #DMNAME
  ADD A0, R1
  LDADDR A1, [A0]
  MOV R0, #256
  MOV R1, #30
  CALL stext
  MOV R0, #200
  MOV R1, #42
  LDA A1, #sDMG
  CALL stext
  LDW R0, [lastdmg]
  CALL utoa
  MOV R0, #256
  MOV R1, #42
  LDA A1, #numstr
  CALL stext
  MOV R1, #212
  LDA A1, #sTHINT
  CALL ctext
  MOV R4, #0
th_lp:
  MOV R0, R4
  SHL R0, #1
  LDA A0, #ihist
  ADD A0, R0
  LDW R2, [A0]
  CMP R2, #0
  BEQ th_next
  LDA A1, #istr
  MOV R0, R2
  AND R0, #15
  SHL R0, #1
  LDA A0, #DIRTXT
  ADD A0, R0
  LDB R0, [A0]
  STB R0, [A1]
  INC A0
  INC A1
  LDB R0, [A0]
  STB R0, [A1]
  INC A1
  MOV R3, #ABTN
  LDA A0, #BTNTXT
th_b:
  MOV R0, R2
  AND R0, R3
  BEQ th_bn
  MOV R0, #32
  STB R0, [A1]
  INC A1
  LDB R0, [A0]
  STB R0, [A1]
  INC A1
th_bn:
  INC A0
  SHL R3, #1
  CMP R3, #START
  BLT th_b
  MOV R0, #0
  STB R0, [A1]
  MOV R0, R4               ; y = 30 + i * 10
  SHL R0, #1
  MOV R1, R0
  SHL R1, #2
  ADD R1, R0
  ADD R1, #30
  MOV R0, #8
  PUSH R4
  LDA A1, #istr
  CALL stext
  POP R4
th_next:
  ADD R4, #1
  CMP R4, #8
  BGE th_ret
  JMP th_lp
th_ret:
  RET
DIRTXT:
  DB 32, 32, 'D', 'B', 'D', 32, 'D', 'F', 'B', 32, 45, 32, 'F', 32, 'U', 'B', 'U', 32, 'U', 'F'
BTNTXT:
  DB 'A', 'B', 'X', 'Y'
DMNAME:
  DA sDSTAND, sDCROUCH, sDJUMP, sDGUARD, sDCPU, sDREC, sDPLAY

; ============================ title ============================
inittitle:
  MOV R0, #G_TITLE
  STW R0, [gstate]
  MOV R0, #0
  STW R0, [idleT]
  STW R0, [sel]
  STW R0, [gT]
  CALL setstage
  CALL copymaps
  CALL clearhud
  CALL resetround
  CALL applyp1
  CALL applyp2
  LDA A2, #F1
  MOV R0, #0
  STW R0, [A2+#FCPU]
  LDA A2, #F2
  STW R0, [A2+#FCPU]
  MOV R0, #3
  STW R0, [show]
  RET

titleframe:
  LDW R0, [gT]
  ADD R0, #1
  STW R0, [gT]
  CALL anyedge
  CMP R0, #0               ; 15 idle seconds start the attract demo
  BEQ tf_idle
  MOV R1, #0
  STW R1, [idleT]
  BRA tf_in
tf_idle:
  LDW R1, [idleT]
  ADD R1, #1
  STW R1, [idleT]
  CMP R1, #900
  BLT tf_in
  JMP initdemo
tf_in:
  MOV R1, R0
  AND R1, #UP+DOWN
  BEQ tf_st
  LDW R1, [sel]
  MOV R2, R0
  AND R2, #DOWN
  BEQ tf_up
  ADD R1, #1
  CMP R1, #3
  BLT tf_set
  MOV R1, #0
  BRA tf_set
tf_up:
  SUB R1, #1
  CMP R1, #0
  BGE tf_set
  MOV R1, #2
tf_set:
  STW R1, [sel]
  PUSH R0
  MOV R0, #200
  CALL sfxblip
  POP R0
tf_st:
  AND R0, #START
  BEQ tf_draw
  LDW R0, [sel]
  STW R0, [mode]
  MOV R0, #120
  CALL sfxblip
  MOV R0, #1
  CALL initselect
  RET
tf_draw:
  LDW R0, [gT]
  CMP R0, #1
  BNE tf_np
  MOV R4, #4               ; first frame: a dark plaque behind the menu
  MOV R5, #9
  MOV R6, #36
  MOV R7, #18
  CALL panel
tf_np:
  CALL oambegin
  MOV R0, #6
  STW R0, [sprpri]
  MOV R4, #0               ; title letters, 32x32: SWORN over RIVALS
tf_lt:
  MOV R0, R4
  SHL R0, #5
  MOV R1, #4
  ADD R0, #80
  CMP R4, #5
  BLT tf_lp
  SUB R0, #176             ; second line: x = 64 + (i - 5) * 32
  MOV R1, #36
tf_lp:
  MOV R5, R4
  SHL R5, #4
  ADD R5, #TITLE
  MOV R6, #SZ32
  OR R6, #PB_TITLE
  PUSH R4
  CALL emittile
  POP R4
  ADD R4, #1
  CMP R4, #11
  BLT tf_lt
  MOV R1, #78
  LDA A1, #sTAG
  CALL ctext
  MOV R0, #124
  MOV R1, #96
  LDA A1, #sARCADE
  CALL stext
  MOV R0, #124
  MOV R1, #108
  LDA A1, #sVERSUS
  CALL stext
  MOV R0, #124
  MOV R1, #120
  LDA A1, #sTRAIN
  CALL stext
  LDW R1, [sel]
  SHL R1, #2
  MOV R0, R1
  SHL R1, #1
  ADD R1, R0               ; * 12
  ADD R1, #96
  MOV R0, #110
  MOV R5, #62              ; '>'
  MOV R6, #PB_FONT
  CALL emittile
  LDW R0, [gT]
  AND R0, #32
  BNE tf_nst
  MOV R1, #134
  LDA A1, #sSTART
  CALL ctext
tf_nst:
  LDA A2, #F1
  MOV R0, #PO_GUARD
  STW R0, [A2+#FPOSE]
  LDA A2, #F2
  STW R0, [A2+#FPOSE]
  CALL drawfighters
  RET

; ============================ character creator ============================
initcreator:
  MOV R0, #G_CREATE
  STW R0, [gstate]
  MOV R0, #0
  STW R0, [cam]
  STW R0, [csel]
  STW R0, [gT]
  CALL copymaps
  CALL clearhud
  MOV R5, #3
  MOV R6, #21
  CALL clearrows
  LDW R0, [cwho]
  CMP R0, #0
  BNE ic_p2
  LDA A1, #sCREATE1
  MOV R0, #1
  BRA ic_hdr
ic_p2:
  LDA A1, #sCREATE2
  MOV R0, #2
ic_hdr:
  STW R0, [show]
  MOV R4, #9
  MOV R5, #3
  CALL print
  LDA A1, #sLABELS
  MOV R5, #CROW0
ic_lab:
  MOV R4, #CLAB
  CALL print
  INC A1
  ADD R5, #2
  CMP R5, #CROWEND
  BLT ic_lab
  MOV R5, #CROW0
ic_arr:
  MOV R0, #CARL
  MOV R1, R5
  MOV R2, #60              ; '<'
  MOV R3, #PB_FONT
  CALL settile
  MOV R0, #CARR
  MOV R1, R5
  MOV R2, #62              ; '>'
  MOV R3, #PB_FONT
  CALL settile
  ADD R5, #2
  CMP R5, #CROWEND
  BLT ic_arr
  LDA A1, #SWTAB
  MOV R5, #CROW0+2
ic_sw:
  LDB R2, [A1]
  ADD R2, #SOLID-1
  LDB R4, [A1+#1]
  INC A1
  INC A1
  MOV R0, #CARL+2
ic_swc:
  PUSH R0
  PUSH R2
  MOV R1, R5
  CALL curbank
  CALL settile
  POP R2
  POP R0
  ADD R0, #1
  ADD R2, #1
  SUB R4, #1
  BNE ic_swc
  ADD R5, #2
  CMP R5, #CROWEND
  BLT ic_sw
  CALL drawbodyname
  LDA A1, #sSTARTD
  MOV R4, #15
  MOV R5, #20
  CALL print
  CALL curfighter
  MOV R0, #56
  STW R0, [A2+#FX]
  MOV R0, #0
  STW R0, [A2+#FFACE]
  STW R0, [A2+#FY]
  STW R0, [A2+#FT]
  RET

; ---- curbank -> R3: the creating player's palette bank (preserves R0-R2) ----
curbank:
  MOV R3, #PB_P1
  LDW R6, [cwho]
  CMP R6, #0
  BEQ cb_d
  MOV R3, #PB_P2
cb_d:
  RET

; ---- curfighter -> A2 = the creating player's fighter; curpicks -> A0 = their picks ----
curfighter:
  LDA A2, #F1
  LDW R0, [cwho]
  CMP R0, #0
  BEQ cfi_d
  LDA A2, #F2
cfi_d:
  RET
curpicks:
  LDA A0, #picks
  LDW R0, [cwho]
  CMP R0, #0
  BEQ cpk_d
  LDA A0, #picks+6
cpk_d:
  RET

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
  CALL curpicks
  LDB R0, [A0]
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

creatorframe:
  LDW R1, [e0]
  LDW R0, [cwho]
  CMP R0, #0
  BEQ cf_pad
  LDW R0, [mode]           ; training: pad 1 tailors the dummy too
  CMP R0, #2
  BEQ cf_pad
  LDW R1, [e1]
cf_pad:
  STW R1, [cedge]
  MOV R0, R1
  AND R0, #START
  BEQ cf_up
  CALL savepicks           ; tailored: back to the select screen, confirmed
  MOV R0, #120
  CALL sfxblip
  LDW R0, [cwho]
  SHL R0, #1
  LDA A0, #selok1
  ADD A0, R0
  MOV R0, #1
  STW R0, [A0]
  MOV R0, #0
  CALL initselect
  RET
cf_up:
  LDW R1, [cedge]
  MOV R0, R1
  AND R0, #UP
  BEQ cf_dn
  LDW R0, [csel]
  CMP R0, #0
  BNE cf_up1
  MOV R0, #CROWS
cf_up1:
  SUB R0, #1
  STW R0, [csel]
  MOV R0, #200
  CALL sfxblip
cf_dn:
  LDW R1, [cedge]
  MOV R0, R1
  AND R0, #DOWN
  BEQ cf_lr
  LDW R0, [csel]
  ADD R0, #1
  CMP R0, #CROWS
  BLT cf_dn1
  MOV R0, #0
cf_dn1:
  STW R0, [csel]
  MOV R0, #200
  CALL sfxblip
cf_lr:
  LDW R1, [cedge]
  MOV R0, R1
  AND R0, #RIGHT
  BEQ cf_left
  MOV R2, #1
  CALL cstep
cf_left:
  LDW R1, [cedge]
  MOV R0, R1
  AND R0, #LEFT
  BEQ cf_a
  MOV R2, #0
  CALL cstep
cf_a:
  CALL curfighter
  LDW R1, [cedge]
  MOV R0, R1
  AND R0, #ABTN+BBTN
  BEQ cf_anim
  MOV R2, #PO_PUNCH
  AND R1, #BBTN
  BEQ cf_ak
  MOV R2, #PO_KICK
cf_ak:
  STW R2, [A2+#FATK]       ; (reused here as the test pose)
  MOV R0, #14
  STW R0, [A2+#FT]
  MOV R0, #180
  CALL sfxblip
cf_anim:
  LDW R0, [A2+#FANIM]
  ADD R0, #1
  STW R0, [A2+#FANIM]
  LDW R0, [A2+#FT]
  CMP R0, #0
  BEQ cf_walk
  SUB R0, #1
  STW R0, [A2+#FT]
  LDW R0, [A2+#FATK]
  BRA cf_pose
cf_walk:
  CALL walkpose
cf_pose:
  STW R0, [A2+#FPOSE]
  CALL oambegin
  LDW R1, [csel]
  SHL R1, #4
  ADD R1, #CROWPY
  MOV R0, #CURX
  LDW R2, [A2+#FANIM]
  AND R2, #16
  BEQ cf_cur
  ADD R0, #2
cf_cur:
  MOV R5, #62
  MOV R6, #PB_FONT
  MOV R2, #6
  STW R2, [sprpri]
  CALL emittile
  CALL drawfighters
  RET

; ---- walkpose(A2) -> R0: the 4-step walk cycle from FANIM ----
walkpose:
  LDW R0, [A2+#FANIM]
  SHR R0, #3
  AND R0, #3
  LDA A0, #WALKP
  ADD A0, R0
  LDB R0, [A0]
  RET

cstep:
  CALL curpicks
  LDW R3, [csel]
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
  CALL curpicks
  PUSHA A0
  CALL curfighter
  MOVA A1, A2
  POPA A0
  CALL applypicks
  MOV R0, #160
  CALL sfxblip
  LDW R3, [csel]
  CMP R3, #0
  BNE cs_done
  CALL drawbodyname
cs_done:
  RET

; ============================ match / round flow ============================
newmatch:
  MOV R0, #0
  STW R0, [rival]
  STW R0, [bonusnx]
  ; fall through
startmatch:
  LDW R0, [bonusnx]        ; arcade: the bonus stage comes between rivals 2 and 3
  CMP R0, #0
  BEQ sm_norm
  MOV R0, #0
  STW R0, [bonusnx]
  JMP initbonus
sm_norm:
  MOV R0, #0
  STW R0, [bonus]
  CALL applyp1
  LDA A2, #F1
  MOV R0, #0
  STW R0, [A2+#FCPU]
  STW R0, [A2+#FWINS]
  LDA A2, #F2
  STW R0, [A2+#FWINS]
  LDW R0, [mode]
  CMP R0, #0
  BNE sm_vs
  CALL setuprival
  BRA sm_go
sm_vs:
  CALL applyp2
  LDA A2, #F2
  MOV R0, #0
  STW R0, [A2+#FCPU]
  LDW R0, [A2+#FBODY]      ; versus is fought on P2's home stage
  CALL homestage
  LDW R0, [mode]
  CMP R0, #2
  BNE sm_go
  JMP inittrain
sm_go:
  MOV R0, #1
  STW R0, [round]
  JMP initvs

; ---- initoath: fresh round, then the secret oath screen ----
initoath:
  CALL resetround
  CALL hudstatic
  MOV R0, #G_OATH
  STW R0, [gstate]
  MOV R0, #OATHT
  STW R0, [gT]
  MOV R0, #0
  STW R0, [sw1]
  STW R0, [sw2]
  LDA A2, #F2
  LDW R0, [A2+#FCPU]
  CMP R0, #0
  BEQ io_done
  LDW R0, [rival]          ; the CPU swears straight away
  SHL R0, #3
  LDA A0, #RIVTAB+7
  ADD A0, R0
  LDB R0, [A0]
  CMP R0, #0
  BNE io_set
  CALL nextrng             ; 0 in the table = a random oath (never Sky Striker)
  AND R0, #3
  LDA A0, #RANDOATH
  ADD A0, R0
  LDB R0, [A0]
io_set:
  STW R0, [A2+#FOATH]
  MOV R0, #1
  STW R0, [sw2]
io_done:
  RET

; ---- swear(R1=edge word, A2=fighter) -> R0 = 1 if this press swore an oath ----
swear:
  MOV R0, #OA_GUARD
  MOV R2, R1
  AND R2, #ABTN
  BNE sw_set
  MOV R0, #OA_FISTS
  MOV R2, R1
  AND R2, #BBTN
  BNE sw_set
  MOV R0, #OA_SKY
  MOV R2, R1
  AND R2, #XBTN
  BNE sw_set
  MOV R0, #OA_STAND
  MOV R2, R1
  AND R2, #YBTN
  BNE sw_set
  MOV R0, #OA_NONE
  MOV R2, R1
  AND R2, #START
  BNE sw_set
  MOV R0, #0
  RET
sw_set:
  STW R0, [A2+#FOATH]
  MOV R0, #150
  CALL sfxblip
  MOV R0, #1
  RET

oathframe:
  LDW R0, [sw1]
  CMP R0, #0
  BNE of_p2
  LDA A2, #F1
  LDW R1, [e0]
  CALL swear
  STW R0, [sw1]
of_p2:
  LDW R0, [sw2]
  CMP R0, #0
  BNE of_clk
  LDA A2, #F2
  LDW R1, [e1]
  CALL swear
  STW R0, [sw2]
of_clk:
  LDW R0, [gT]
  SUB R0, #1
  STW R0, [gT]
  CMP R0, #0
  BGT of_ck
  MOV R0, #1               ; clock ran out: no oath for whoever hasn't sworn
  STW R0, [sw1]
  STW R0, [sw2]
of_ck:
  LDW R0, [sw1]
  LDW R1, [sw2]
  AND R0, R1
  BEQ of_draw
  LDW R0, [gT]             ; both sworn: a short beat, then the round intro
  CMP R0, #30
  BLE of_beat
  MOV R0, #30
  STW R0, [gT]
of_beat:
  CMP R0, #0
  BGT of_draw
  CALL initintro
  RET
of_draw:
  LDW R0, [gT]
  CMP R0, #OATHT-1
  BNE of_np
  MOV R4, #1               ; first frame: a dark plaque behind the oath list
  MOV R5, #7
  MOV R6, #39
  MOV R7, #16
  CALL panel
of_np:
  CALL oambegin
  MOV R1, #32
  LDA A1, #sSWEAR
  CALL cbig
  MOV R0, #96
  MOV R1, #58
  LDA A1, #sOA1
  CALL stext
  MOV R0, #96
  MOV R1, #70
  LDA A1, #sOA2
  CALL stext
  MOV R0, #96
  MOV R1, #82
  LDA A1, #sOA3
  CALL stext
  MOV R0, #96
  MOV R1, #94
  LDA A1, #sOA4
  CALL stext
  MOV R1, #106
  LDA A1, #sNOOATH
  CALL ctext
  MOV R0, #16
  MOV R1, #120
  LDA A1, #sP1
  CALL stext
  ADD R0, #8
  LDA A1, #sWAIT
  LDW R2, [sw1]
  CMP R2, #0
  BEQ of_s1
  LDA A1, #sSWORN
of_s1:
  CALL stext
  MOV R0, #224
  MOV R1, #120
  LDA A1, #sP2
  CALL stext
  ADD R0, #8
  LDA A1, #sWAIT
  LDW R2, [sw2]
  CMP R2, #0
  BEQ of_s2
  LDA A1, #sSWORN
of_s2:
  CALL stext
  LDW R0, [gT]             ; seconds left
  MOV R1, #0
  MOV R2, #60
  DIVU R0, R2
  MOV R2, R0
  ADD R2, #48
  MOV R5, R2
  MOV R0, #156
  MOV R1, #120
  MOV R6, #PB_FONT
  CALL emittile
  CALL idleposes
  CALL drawfighters
  CALL drawhud
  RET

; ---- idleposes: both fighters in guard (screens where nobody fights) ----
idleposes:
  LDA A2, #F1
  MOV R0, #PO_GUARD
  STW R0, [A2+#FPOSE]
  LDA A2, #F2
  STW R0, [A2+#FPOSE]
  RET

initintro:
  CALL copymaps            ; lift the oath plaque
  CALL hudstatic           ; (copymaps also blanked the HUD rows)
  MOV R0, #G_INTRO
  STW R0, [gstate]
  MOV R0, #0
  STW R0, [gT]
  RET

introframe:
  LDW R0, [gT]
  ADD R0, #1
  STW R0, [gT]
  CMP R0, #110
  BLT inf_draw
  MOV R0, #G_FIGHT
  STW R0, [gstate]
  RET
inf_draw:
  CALL oambegin
  LDW R0, [bonus]
  CMP R0, #0
  BEQ inf_nb
  MOV R1, #64
  LDA A1, #sBONUS1
  CALL cbig
  MOV R1, #88
  LDA A1, #sBONUS2
  CALL cbig
  BRA inf_f
inf_nb:
  LDW R0, [gT]
  CMP R0, #64
  BGE inf_fight
  LDW R0, [round]          ; "ROUND n": the digit goes into the string's last slot
  ADD R0, #48
  STB R0, [rstr+6]
  MOV R0, #0
  STB R0, [rstr+7]
  LDA A1, #sROUND
  LDA A0, #rstr
  MOV R2, #6
ii_cp:
  LDB R0, [A1]
  STB R0, [A0]
  INC A1
  INC A0
  SUB R2, #1
  BNE ii_cp
  MOV R1, #72
  LDA A1, #rstr
  CALL cbig
  BRA inf_f
inf_fight:
  CMP R0, #66
  BNE inf_ft
  MOV R0, #100
  CALL sfxblip
inf_ft:
  MOV R1, #72
  LDA A1, #sFIGHT
  CALL cbig
inf_f:
  CALL idleposes
  CALL drawfighters
  CALL drawhud
  RET

; ============================ the fight ============================
fightframe:
  LDW R0, [freeze]
  CMP R0, #0
  BEQ ff_run
  SUB R0, #1
  STW R0, [freeze]
  CALL freezepads
  BRA ff_draw
ff_run:
  LDW R0, [tick]
  ADD R0, #1
  STW R0, [tick]
  CALL clocktick
  LDA A0, #fighterstep
  CALL both
  CALL separate
  LDA A0, #attackcheck
  CALL both
  LDA A0, #projcheck
  CALL both
  LDA A0, #faceup
  CALL both
  CALL updatecam
  LDW R0, [bonus]
  CMP R0, #0
  BEQ ff_nb
  JMP bonusstep
ff_nb:
  LDW R0, [mode]           ; training: no KO, no clock
  CMP R0, #2
  BNE ff_nt
  CALL trainstep
  LDW R0, [gstate]
  CMP R0, #G_FIGHT
  BEQ ff_draw
  RET
ff_nt:
  LDA A2, #F1              ; a KO ends the round
  LDW R0, [A2+#FST]
  CMP R0, #ST_KO
  BEQ ff_ko
  LDA A2, #F2
  LDW R0, [A2+#FST]
  CMP R0, #ST_KO
  BEQ ff_ko
  LDW R0, [timer]
  CMP R0, #0
  BNE ff_draw
  MOV R0, #1               ; time over
  STW R0, [kokind]
  CALL initko
  RET
ff_ko:
  MOV R0, #0
  STW R0, [kokind]
  CALL initko
  RET
ff_draw:
  CALL oambegin
  CALL drawbreak
  CALL drawcombo
  CALL drawspark
  CALL drawbolts
  CALL drawfighters
  CALL drawhud
  LDW R0, [mode]
  CMP R0, #2
  BNE ff_dm
  CALL trainhud
  BRA ff_dr
ff_dm:
  CMP R0, #3
  BNE ff_dr
  LDW R0, [tick]           ; demo: blink the invitation
  AND R0, #32
  BNE ff_dr
  MOV R1, #212
  LDA A1, #sDEMO
  CALL ctext
ff_dr:
  RET

; ---- clocktick: one second = 60 fight frames; kept oaths trickle meter ----
clocktick:
  LDW R0, [mode]           ; training has no clock
  CMP R0, #2
  BEQ ct_done
  LDW R0, [tsub]
  ADD R0, #1
  STW R0, [tsub]
  CMP R0, #60
  BLT ct_done
  MOV R0, #0
  STW R0, [tsub]
  LDW R0, [timer]
  CMP R0, #0
  BEQ ct_done
  SUB R0, #1
  STW R0, [timer]
  LDA A0, #F1
  MOV R0, #1
  CALL keptgain
  LDA A0, #F2
  MOV R0, #1
  CALL keptgain
ct_done:
  RET

; ---- keptgain(A0=fighter, R0=amount): meter += amount if its oath stands ----
keptgain:
  LDW R1, [A0+#FOATH]
  CMP R1, #0
  BEQ kg_done
  LDW R1, [A0+#FOBRK]
  CMP R1, #0
  BNE kg_done
  ; fall through
; ---- addmeter(A0, R0): meter += R0, capped ----
addmeter:
  LDW R1, [A0+#FMTR]
  ADD R1, R0
  CMP R1, #MTRMAX
  BLE am_set
  MOV R1, #MTRMAX
am_set:
  STW R1, [A0+#FMTR]
kg_done:
  RET

; ---- fighterstep(A2, A3): pad, motion buffer, control, physics ----
fighterstep:
  CALL padsync
  CALL motionrec
  CALL control
  CALL physics
  CALL stundecay
  CALL projstep
  RET

; ---- freezepads: keep players' presses and motions made during a hit freeze ----
freezepads:
  LDA A2, #F1
  LDA A3, #F2
  LDW R1, [in0]
  LDA A0, #latch
  CALL fzone
  LDA A2, #F2
  LDA A3, #F1
  LDW R1, [in1]
  LDA A0, #latch+2
  CALL fzone
  RET
fzone:
  LDW R0, [A2+#FCPU]
  CMP R0, #0
  BNE fz_ret
  LDW R0, [A2+#FPADP]
  NOT R0
  AND R0, R1
  LDW R2, [A0]
  OR R2, R0
  STW R2, [A0]
  STW R1, [A2+#FPADP]
  STW R1, [A2+#FPAD]
  CALL motionrec
fz_ret:
  RET

; ---- padsync: this frame's pad for A2 (controller or CPU) and its edges ----
padsync:
  LDW R0, [A2+#FCPU]
  CMP R0, #0
  BEQ ps_human
  CALL cputhink
  LDW R1, [A2+#FAIPAD]
  BRA ps_set
ps_human:
  LDW R1, [in0]
  LDW R0, [A2+#FID]
  CMP R0, #0
  BNE ps_p2h
  LDW R0, [mode]           ; training record: pad 1 belongs to the dummy
  CMP R0, #2
  BNE ps_set
  LDW R0, [dmode]
  CMP R0, #5
  BNE ps_set
  MOV R1, #0
  BRA ps_set
ps_p2h:
  MOV R1, #0               ; the bonus cart never moves
  LDW R0, [bonus]
  CMP R0, #0
  BNE ps_set
  LDW R0, [mode]
  CMP R0, #2
  BNE ps_p2
  CALL dummypad
  BRA ps_set
ps_p2:
  LDW R1, [in1]
ps_set:
  STW R1, [A2+#FPAD]
  LDW R0, [A2+#FPADP]
  NOT R0
  AND R0, R1
  LDW R2, [A2+#FID]        ; plus anything pressed during a hit freeze
  SHL R2, #1
  LDA A0, #latch
  ADD A0, R2
  LDW R3, [A0]
  OR R0, R3
  MOV R3, #0
  STW R3, [A0]
  STW R0, [A2+#FEDGE]
  STW R1, [A2+#FPADP]
  RET

; ---- dirbits(A2) -> R6 = forward bit, R7 = back bit, R5 = world sign of forward ----
dirbits:
  LDW R0, [A2+#FFACE]
  CMP R0, #0
  BNE db_left
  MOV R6, #RIGHT
  MOV R7, #LEFT
  MOV R5, #1
  RET
db_left:
  MOV R6, #LEFT
  MOV R7, #RIGHT
  MOV R5, #-1
  RET

; ---- motionrec: log relative direction changes (1 D, 2 DF, 3 F, 4 B, 5 DB, 0 other) ----
motionrec:
  CALL dirbits
  LDW R1, [A2+#FPAD]
  MOV R0, #0
  MOV R2, R1
  AND R2, #DOWN
  BEQ mr_nd
  MOV R0, #2
  MOV R2, R1
  AND R2, R6
  BNE mr_code
  MOV R0, #5
  MOV R2, R1
  AND R2, R7
  BNE mr_code
  MOV R0, #1
  BRA mr_code
mr_nd:
  MOV R2, R1
  AND R2, R6
  BEQ mr_nf
  MOV R0, #3
  BRA mr_code
mr_nf:
  MOV R2, R1
  AND R2, R7
  BEQ mr_code
  MOV R0, #4
mr_code:
  LDW R1, [A2+#FDIR]
  CMP R0, R1
  BEQ mr_done
  STW R0, [A2+#FDIR]
  LDW R1, [A2+#FBUFI]      ; ring slot = FBUF + i*4
  MOV R2, R1
  SHL R2, #2
  MOVA A0, A2
  ADD A0, #FBUF
  ADD A0, R2
  STW R0, [A0]
  LDW R0, [tick]
  STW R0, [A0+#2]
  ADD R1, #1
  AND R1, #7
  STW R1, [A2+#FBUFI]
mr_done:
  RET

; ---- motion(A1=pattern of 3 codes, newest first) -> R0 = 1 if found in the window ----
motion:
  LDW R3, [A2+#FBUFI]
  MOV R4, #0               ; pattern position
  MOV R7, #8               ; entries to scan
mo_lp:
  SUB R3, #1
  AND R3, #7
  MOV R2, R3
  SHL R2, #2
  MOVA A0, A2
  ADD A0, #FBUF
  ADD A0, R2
  LDW R0, [tick]
  LDW R1, [A0+#2]
  SUB R0, R1
  CMP R0, #MOTIONW
  BGT mo_fail
  LDW R0, [A0]
  MOVA A0, A1
  ADD A0, R4
  LDB R1, [A0]
  CMP R0, R1
  BNE mo_next
  ADD R4, #1
  CMP R4, #3
  BEQ mo_ok
mo_next:
  SUB R7, #1
  BNE mo_lp
mo_fail:
  MOV R0, #0
  RET
mo_ok:
  MOV R0, #1
  RET

; ---- getreq -> R0 = requested attack + 1 (0 = none) ----
getreq:
  LDW R0, [A2+#FCPU]
  CMP R0, #0
  BEQ gr_human
  LDW R0, [A2+#FAIATK]
  MOV R1, #0
  STW R1, [A2+#FAIATK]
  RET
gr_human:
  LDW R1, [A2+#FEDGE]
  MOV R0, R1
  AND R0, #ABTN+XBTN
  BEQ gr_k
  JMP punchreq
gr_k:
  MOV R0, R1
  AND R0, #BBTN+YBTN
  BEQ gr_none
  JMP kickreq
gr_none:
  MOV R0, #0
  RET

; ---- punchreq(R1 = edges) -> R0 = attack + 1: specials, throw, then the normals ----
punchreq:
  MOV R0, R1
  AND R0, #XBTN
  PUSH R0                  ; heavy?
  LDA A1, #MO_DP
  CALL motion
  CMP R0, #0
  BEQ pr_q
  POP R4
  PUSH R4
  MOV R2, #2               ; DP+P
  CALL slotreq
  CMP R0, #0
  BNE pr_got
pr_q:
  LDA A1, #MO_QCF
  CALL motion
  CMP R0, #0
  BEQ pr_b
  POP R4
  PUSH R4
  MOV R2, #0               ; QCF+P
  CALL slotreq
  CMP R0, #0
  BNE pr_got
pr_b:
  LDA A1, #MO_QCB
  CALL motion
  CMP R0, #0
  BEQ pr_n
  POP R4
  PUSH R4
  MOV R2, #4               ; QCB+P
  CALL slotreq
  CMP R0, #0
  BEQ pr_n
pr_got:
  POP R4
  RET
pr_n:
  POP R4
  LDW R1, [A2+#FPAD]
  AND R1, #DOWN
  BEQ pr_st
  MOV R0, #AK_CPUNCH+1
  CMP R4, #0
  BEQ pr_r
  MOV R0, #AK_CHPUNCH+1
  RET
pr_st:
  CMP R4, #0
  BEQ pr_lp
  CALL dirbits             ; forward or back + X up close: a throw
  LDW R1, [A2+#FPAD]
  MOV R0, R6
  OR R0, R7
  AND R0, R1
  BEQ pr_hp
  AND R1, R7
  PUSH R1
  MOV R3, #THROWR
  CALL throwable
  POP R1
  CMP R0, #0
  BEQ pr_hp
  MOV R0, #AK_THROW+1
  CMP R1, #0
  BEQ pr_r
  MOV R0, #AK_BTHROW+1
  RET
pr_hp:
  MOV R0, #AK_HPUNCH+1
  RET
pr_lp:
  MOV R0, #AK_PUNCH+1
  RET
pr_r:
  RET

; ---- kickreq(R1 = edges) -> R0 = attack + 1 ----
kickreq:
  MOV R0, R1
  AND R0, #YBTN
  PUSH R0                  ; heavy?
  LDW R0, [A2+#FMTR]
  CMP R0, #MTRMAX
  BLT kr_s
  LDA A1, #MO_QCF
  CALL motion
  CMP R0, #0
  BEQ kr_s
  POP R0
  MOV R0, #AK_SURGE+1
  RET
kr_s:
  LDA A1, #MO_DP
  CALL motion
  CMP R0, #0
  BEQ kr_q
  POP R4
  PUSH R4
  MOV R2, #8               ; DP+K
  CALL slotreq
  CMP R0, #0
  BNE kr_got
kr_q:
  LDA A1, #MO_QCB
  CALL motion
  CMP R0, #0
  BEQ kr_n
  POP R4
  PUSH R4
  MOV R2, #6               ; QCB+K
  CALL slotreq
  CMP R0, #0
  BEQ kr_n
kr_got:
  POP R4
  RET
kr_n:
  POP R4
  LDW R1, [A2+#FPAD]
  AND R1, #DOWN
  BEQ kr_st
  MOV R0, #AK_CLK+1
  CMP R4, #0
  BEQ kr_r
  MOV R0, #AK_SWEEP+1
kr_r:
  RET
kr_st:
  MOV R0, #AK_KICK+1
  CMP R4, #0
  BEQ kr_r
  MOV R0, #AK_HKICK+1
  RET

; ---- slotreq(A2, R2 = slot * 2, R4 = heavy) -> R0 = this fighter's special + 1, or 0 ----
slotreq:
  LDW R0, [A2+#FBODY]
  MOV R1, R0
  SHL R0, #3
  ADD R0, R1
  ADD R0, R1               ; body * 10
  ADD R0, R2
  CMP R4, #0
  BEQ sq_l
  ADD R0, #1
sq_l:
  LDA A0, #CHSPEC
  ADD A0, R0
  LDB R0, [A0]
  CMP R0, #$FF
  BEQ sq_no
  MOV R1, R0               ; one bolt on screen at a time
  SHL R1, #5
  LDA A0, #ATKTAB
  ADD A0, R1
  LDB R1, [A0+#AT_FL2]
  AND R1, #F2_PROJ
  BEQ sq_ok
  LDW R1, [A2+#FPJT]
  CMP R1, #0
  BNE sq_no
sq_ok:
  ADD R0, #1
  RET
sq_no:
  MOV R0, #0
  RET

; ---- throwable(A2, A3, R3 = range) -> R0 = 1 if A3 can be thrown from here ----
throwable:
  LDW R0, [A2+#FY]
  CMP R0, #0
  BNE tw_no
  LDW R0, [A3+#FY]
  CMP R0, #0
  BNE tw_no
  LDW R0, [A3+#FST]
  CMP R0, #ST_ATK          ; idle, crouching or attacking
  BLE tw_rng
  CMP R0, #ST_DIZZY
  BNE tw_no
tw_rng:
  CALL cpudist
  CMP R0, R3
  BGT tw_no
  MOV R0, #1
  RET
tw_no:
  MOV R0, #0
  RET

; ---- control: state machine for A2 (A3 = rival) ----
control:
  LDW R0, [A2+#FST]
  CMP R0, #ST_CROUCH
  BLE ctl_ground
  CMP R0, #ST_JUMP
  BEQ ctl_air
  CMP R0, #ST_ATK
  BNE ctl_n1
  JMP atkstep
ctl_n1:
  CMP R0, #ST_HURT
  BLE ctl_stun             ; BLOCK or HURT
  CMP R0, #ST_DOWN
  BNE ctl_n2
  JMP downstep
ctl_n2:
  CMP R0, #ST_DIZZY
  BNE ctl_n3
  JMP dizzystep
ctl_n3:
  RET                      ; KO / WIN: nothing
ctl_stun:
  LDW R0, [A2+#FT]
  SUB R0, #1
  STW R0, [A2+#FT]
  BGT ctl_ret
  JMP standup
ctl_ret:
  RET
ctl_air:
  CALL getreq              ; any request in the air becomes the matching air attack
  CMP R0, #0
  BEQ ctl_ret
  SUB R0, #1
  LDA A0, #AIRMAP
  ADD A0, R0
  LDB R0, [A0]
  JMP startatk
ctl_ground:
  CALL getreq
  CMP R0, #0
  BEQ ctl_move
  SUB R0, #1
  JMP startatk
ctl_move:
  CALL dirbits
  LDW R1, [A2+#FPAD]
  MOV R0, R1
  AND R0, #UP
  BEQ ctl_nojump
  JMP dojump
ctl_nojump:
  MOV R0, R1
  AND R0, #DOWN
  BEQ ctl_stand
  MOV R0, #ST_CROUCH
  STW R0, [A2+#FST]
  MOV R0, #1
  STW R0, [A2+#FCRCH]
  MOV R0, #0
  STW R0, [A2+#FBACK]
  MOV R0, #PO_CROUCH
  MOV R2, R1
  AND R2, R7
  BEQ ctl_cp
  CALL threat              ; holding down-back against an attack: show the low guard
  CMP R2, #0
  BEQ ctl_cp
  MOV R0, #PO_CBLOCK
ctl_cp:
  STW R0, [A2+#FPOSE]
  RET
ctl_stand:
  MOV R0, #ST_IDLE
  STW R0, [A2+#FST]
  MOV R0, #0
  STW R0, [A2+#FCRCH]
  MOV R0, R1
  AND R0, R7
  BEQ ctl_fwd
  CALL threat              ; back held while the rival attacks: guard, don't walk
  CMP R2, #0
  BEQ ctl_back
  MOV R0, #0
  STW R0, [A2+#FBACK]
  MOV R0, #PO_BLOCK
  STW R0, [A2+#FPOSE]
  RET
ctl_back:
  NEG R5
  CALL walk
  LDW R0, [A2+#FBACK]
  ADD R0, #1
  STW R0, [A2+#FBACK]
  CMP R0, #BACKSTEP
  BLT ctl_ret2
  MOV R0, #OA_STAND
  CALL breakself
ctl_ret2:
  RET
ctl_fwd:
  MOV R0, #0
  STW R0, [A2+#FBACK]
  MOV R0, R1
  AND R0, R6
  BEQ ctl_idle
  CALL walk
  RET
ctl_idle:
  MOV R0, #PO_GUARD
  STW R0, [A2+#FPOSE]
  RET

; ---- threat(A2, A3) -> R2 = 1 if the rival is attacking or its bolt is close (keeps R1, R5-R7) ----
threat:
  LDW R2, [A3+#FST]
  CMP R2, #ST_ATK
  BEQ th_yes
  LDW R2, [A3+#FPJT]
  CMP R2, #0
  BEQ th_no
  LDW R2, [A3+#FPJX]
  LDW R3, [A2+#FX]
  SUB R2, R3
  CMP R2, #0
  BGE th_a
  NEG R2
th_a:
  CMP R2, #80
  BGT th_no
th_yes:
  MOV R2, #1
  RET
th_no:
  MOV R2, #0
  RET

; ---- walk(A2, R5 = world direction +1/-1): move by FSPD (8.8), animate ----
walk:
  LDW R0, [A2+#FXF]
  LDW R1, [A2+#FSPD]
  ADD R0, R1
  MOV R1, R0
  SHR R1, #8               ; whole pixels this frame
  AND R0, #$FF
  STW R0, [A2+#FXF]
  CMP R5, #0
  BGT wk_add
  NEG R1
wk_add:
  LDW R0, [A2+#FX]
  ADD R0, R1
  STW R0, [A2+#FX]
  LDW R0, [A2+#FANIM]
  ADD R0, #1
  STW R0, [A2+#FANIM]
  CALL walkpose
  STW R0, [A2+#FPOSE]
  RET

; ---- dojump(A2, R1 = pad, R5/R6/R7 from dirbits) ----
dojump:
  MOV R0, #JUMPV
  STW R0, [A2+#FVY]
  MOV R0, #0
  STW R0, [A2+#FVX]
  STW R0, [A2+#FCRCH]
  STW R0, [A2+#FBACK]
  MOV R0, R1
  AND R0, R6
  BEQ dj_nf
  MOV R0, R5               ; forward jump
  SHL R0, #1
  STW R0, [A2+#FVX]
  BRA dj_set
dj_nf:
  MOV R0, R1
  AND R0, R7
  BEQ dj_set
  MOV R0, R5               ; back jump: breaks Stand Fast
  SHL R0, #1
  NEG R0
  STW R0, [A2+#FVX]
  MOV R0, #OA_STAND
  CALL breakself
dj_set:
  MOV R0, #ST_JUMP
  STW R0, [A2+#FST]
  MOV R0, #PO_JUMP
  STW R0, [A2+#FPOSE]
  MOV R0, #240
  CALL sfxblip
  RET

; ---- atkrec(A2) -> A0 = this fighter's ATKTAB row ----
atkrec:
  LDW R0, [A2+#FATK]
  SHL R0, #5
  LDA A0, #ATKTAB
  ADD A0, R0
  RET

; ---- startatk(A2, R0 = attack) ----
startatk:
  STW R0, [A2+#FATK]
  MOV R0, #ST_ATK
  STW R0, [A2+#FST]
  MOV R0, #0
  STW R0, [A2+#FT]
  STW R0, [A2+#FHIT]
  STW R0, [A2+#FBACK]
  STW R0, [A2+#FAICX]
  CALL atkrec
  LDB R0, [A0+#AT_P0]
  STW R0, [A2+#FPOSE]
  LDB R0, [A0+#AT_FL]
  AND R0, #AF_KICK
  BEQ sa_nk
  MOV R0, #OA_FISTS
  CALL breakself
  CALL atkrec
sa_nk:
  LDW R0, [A2+#FATK]
  CMP R0, #AK_SURGE
  BNE sa_snd
  MOV R0, #0               ; the super spends the whole meter and freezes the scene
  STW R0, [A2+#FMTR]
  MOV R0, #20
  STW R0, [freeze]
  MOV R0, #60
  STW R0, [surgeT]
  LDW R0, [A2+#FID]
  STW R0, [brkWho]
  MOV R0, #SX_SUPER
  CALL sfxplay
  RET
sa_snd:
  LDW R0, [A2+#FATK]       ; specials shout, normals swish
  LDA A0, #ATKSFX
  ADD A0, R0
  LDB R0, [A0]
  CMP R0, #0
  BEQ sa_bl
  CALL sfxplay
  RET
sa_bl:
  MOV R0, #180
  CALL sfxblip
  RET

; ---- atkstep: advance the attack timeline (startup, active, recovery) ----
atkstep:
  CALL atkrec
  LDW R0, [A2+#FHIT]       ; connected (hit or block): chain or cancel?
  CMP R0, #0
  BEQ as_go
  LDB R5, [A0+#AT_FL2]
  MOV R0, R5
  AND R0, #F2_CHAIN+F2_CXL
  BEQ as_go
  LDB R1, [A0+#AT_S]       ; only until a few frames into recovery
  LDB R2, [A0+#AT_A]
  ADD R1, R2
  ADD R1, #CXLWIN
  LDW R0, [A2+#FT]
  CMP R0, R1
  BGE as_go
  PUSH R5
  CALL getreq
  POP R5
  CMP R0, #0
  BEQ as_go0
  SUB R0, #1
  MOV R4, R0
  SHL R4, #5
  LDA A0, #ATKTAB
  ADD A0, R4
  LDB R1, [A0+#AT_FL2]
  MOV R2, R5
  AND R2, #F2_CXL
  BEQ as_ch
  MOV R2, R1
  AND R2, #F2_SPEC
  BNE as_cx
as_ch:
  AND R5, #F2_CHAIN
  BEQ as_go0
  AND R1, #F2_CHAIN
  BEQ as_go0
as_cx:
  JMP startatk
as_go0:
  CALL atkrec
as_go:
  LDW R4, [A2+#FT]
  ADD R4, #1
  STW R4, [A2+#FT]
  LDB R1, [A0+#AT_S]
  CMP R4, R1
  BGE as_act
  LDB R0, [A0+#AT_P0]
  STW R0, [A2+#FPOSE]
  RET
as_act:
  LDB R2, [A0+#AT_A]
  ADD R2, R1               ; R2 = end of active
  CMP R4, R2
  BLT as_live
  LDB R0, [A0+#AT_FL]      ; air attacks stay live until they land
  AND R0, #AF_AIR
  BNE as_air
  JMP as_rec
as_air:
  LDW R0, [A2+#FY]
  CMP R0, #0
  BGE as_rec
  SUB R2, #1
  STW R2, [A2+#FT]
  MOV R4, R2
as_live:
  LDB R0, [A0+#AT_P1]
  STW R0, [A2+#FPOSE]
  CMP R4, R1               ; first active frame: fire a bolt, or Palm Rise lifts off
  BNE as_dash
  LDB R0, [A0+#AT_FL2]
  AND R0, #F2_PROJ
  BEQ as_rz
  JMP firebolt
as_rz:
  LDB R0, [A0+#AT_FL]
  AND R0, #AF_RISE
  BEQ as_dash
  MOV R0, #RISEV
  STW R0, [A2+#FVY]
as_dash:
  LDB R0, [A0+#AT_FL]      ; multi-hit: re-arm every 8 active frames
  AND R0, #AF_MULTI
  BEQ as_dmv
  MOV R0, R4
  SUB R0, R1
  AND R0, #7
  BNE as_alt
  MOV R0, #0
  STW R0, [A2+#FHIT]
as_alt:
  MOV R0, R4               ; alternate the active pose with AT_ALT
  AND R0, #4
  LDB R0, [A0+#AT_P1]
  BEQ as_altp
  LDB R0, [A0+#AT_ALT]
as_altp:
  STW R0, [A2+#FPOSE]
as_dmv:
  LDB R0, [A0+#AT_DASH]
  CMP R0, #0
  BEQ as_ret
  PUSH R0
  CALL dirbits
  POP R0
  CMP R5, #0
  BGT as_dadd
  NEG R0
as_dadd:
  LDW R1, [A2+#FX]
  ADD R1, R0
  STW R1, [A2+#FX]
as_ret:
  RET
as_rec:
  LDB R3, [A0+#AT_R]
  ADD R3, R2
  CMP R4, R3
  BGE as_end
  LDB R0, [A0+#AT_P2]
  STW R0, [A2+#FPOSE]
  RET
as_end:
  LDW R0, [A2+#FY]         ; still in the air (Palm Rise): keep recovering
  CMP R0, #0
  BLT as_hold
  MOV R0, #ST_IDLE
  STW R0, [A2+#FST]
  MOV R0, #PO_GUARD
  STW R0, [A2+#FPOSE]
  RET
as_hold:
  SUB R4, #1
  STW R4, [A2+#FT]
  RET

; ---- downstep: on the floor after a knockdown, then stand ----
downstep:
  LDW R0, [A2+#FY]
  CMP R0, #0
  BLT ds_ret
  LDW R0, [A2+#FT]
  ADD R0, #1
  STW R0, [A2+#FT]
  CMP R0, #DOWNT
  BLT ds_ret
  JMP standup
ds_ret:
  RET

; ---- standup: stun over -> idle, or dizzy if the stun points ran over ----
standup:
  LDW R0, [A2+#FDIZ]
  CMP R0, #DIZMAX
  BGE su_dz
  MOV R0, #ST_IDLE
  STW R0, [A2+#FST]
  MOV R0, #PO_GUARD
  STW R0, [A2+#FPOSE]
  RET
su_dz:
  MOV R0, #0
  STW R0, [A2+#FDIZ]
  STW R0, [A2+#FCRCH]
  MOV R0, #ST_DIZZY
  STW R0, [A2+#FST]
  MOV R0, #DIZT
  STW R0, [A2+#FT]
  MOV R0, #PO_DIZZY
  STW R0, [A2+#FPOSE]
  MOV R0, #500
  CALL sfxblip
  RET

; ---- dizzystep: wobble until it wears off; every new press shakes it off faster ----
dizzystep:
  LDW R0, [A2+#FEDGE]
  LDW R1, [A2+#FT]
  SUB R1, #1
  CMP R0, #0
  BEQ dz_t
  SUB R1, #3
dz_t:
  STW R1, [A2+#FT]
  CMP R1, #0
  BGT dz_ret
  MOV R0, #ST_IDLE
  STW R0, [A2+#FST]
  MOV R0, #PO_GUARD
  STW R0, [A2+#FPOSE]
dz_ret:
  RET

; ---- stundecay: stun points drain while the fighter is free ----
stundecay:
  LDW R0, [A2+#FST]
  CMP R0, #ST_ATK
  BGT sd_ret
  LDW R0, [tick]
  AND R0, #3
  BNE sd_ret
  LDW R0, [A2+#FDIZ]
  CMP R0, #0
  BEQ sd_ret
  CMP R0, #DIZMAX
  BGE sd_ret
  SUB R0, #1
  STW R0, [A2+#FDIZ]
sd_ret:
  RET

; ---- physics: gravity + landing, pushback, flash, clamp ----
physics:
  LDW R0, [A2+#FY]
  LDW R1, [A2+#FVY]
  CMP R0, #0
  BLT ph_air
  CMP R1, #0
  BGE ph_push
ph_air:
  ADD R1, #GRAV
  STW R1, [A2+#FVY]
  ADD R0, R1
  STW R0, [A2+#FY]
  LDW R2, [A2+#FX]
  LDW R3, [A2+#FVX]
  ADD R2, R3
  STW R2, [A2+#FX]
  CMP R0, #0
  BLT ph_push
  MOV R0, #0               ; landed
  STW R0, [A2+#FY]
  STW R0, [A2+#FVY]
  STW R0, [A2+#FVX]
  LDW R0, [A2+#FST]
  CMP R0, #ST_JUMP
  BEQ ph_toidle
  CMP R0, #ST_ATK
  BNE ph_ndown
  CALL atkrec
  LDB R0, [A0+#AT_FL]
  AND R0, #AF_AIR
  BEQ ph_push
ph_toidle:
  MOV R0, #ST_IDLE
  STW R0, [A2+#FST]
  MOV R0, #PO_GUARD
  STW R0, [A2+#FPOSE]
  BRA ph_push
ph_ndown:
  CMP R0, #ST_DOWN
  BLT ph_push
  CMP R0, #ST_KO
  BGT ph_push
  MOV R0, #0               ; DOWN / KO hit the floor
  STW R0, [A2+#FT]
  MOV R0, #PO_DOWN
  STW R0, [A2+#FPOSE]
  MOV R0, #40
  CALL noisehit
ph_push:
  LDW R0, [A2+#FPUSH]
  CMP R0, #0
  BEQ ph_fl
  SUB R0, #1
  STW R0, [A2+#FPUSH]
  LDW R0, [A2+#FX]
  LDW R1, [A2+#FPUSHV]
  ADD R0, R1
  STW R0, [A2+#FX]
ph_fl:
  LDW R0, [A2+#FFLASH]
  CMP R0, #0
  BEQ ph_cl
  SUB R0, #1
  STW R0, [A2+#FFLASH]
ph_cl:
  ; fall through
; ---- clampx(A2): keep the fighter inside the arena ----
clampx:
  LDW R0, [A2+#FX]
  CMP R0, #XMINW
  BGE cx_hi
  MOV R0, #XMINW
cx_hi:
  CMP R0, #XMAXW
  BLE cx_set
  MOV R0, #XMAXW
cx_set:
  STW R0, [A2+#FX]
  RET

; ---- faceup(A2, A3): grounded, free fighters turn to face the rival ----
faceup:
  LDW R0, [A2+#FST]
  CMP R0, #ST_CROUCH
  BGT fu_ret
  LDW R0, [A2+#FY]
  CMP R0, #0
  BNE fu_ret
  LDW R0, [A2+#FX]
  LDW R1, [A3+#FX]
  CMP R1, R0
  BEQ fu_ret
  MOV R2, #0
  BGT fu_set
  MOV R2, #1
fu_set:
  STW R2, [A2+#FFACE]
fu_ret:
  RET

; ---- separate: max separation, then push overlapping bodies apart ----
separate:
  LDA A2, #F1
  LDA A3, #F2
  LDW R0, [A2+#FX]
  LDW R1, [A3+#FX]
  MOV R2, R1
  SUB R2, R0               ; d = x2 - x1
  MOV R3, R2
  CMP R3, #0
  BGE sp_abs
  NEG R3
sp_abs:
  CMP R3, #MAXSEP
  BLE sp_body
  SUB R3, #MAXSEP          ; too far apart: pull both in
  MOV R4, R3
  SHR R4, #1
  SUB R3, R4               ; R3 = rest, R4 = half
  CMP R2, #0
  BLT sp_far2
  ADD R0, R4
  SUB R1, R3
  BRA sp_farset
sp_far2:
  SUB R0, R4
  ADD R1, R3
sp_farset:
  STW R0, [A2+#FX]
  STW R1, [A3+#FX]
sp_rt:
  RET
sp_body:
  CMP R3, #BODYW
  BGE sp_rt
  LDW R4, [A2+#FY]         ; one of them high in the air: they may cross
  CMP R4, #$D800           ; -40 px
  BLT sp_rt
  LDW R4, [A3+#FY]
  CMP R4, #$D800
  BLT sp_rt
  MOV R4, #BODYW
  SUB R4, R3
  ADD R4, #1
  SHR R4, #1               ; each moves half the overlap
  CMP R2, #0
  BGT sp_lr
  BLT sp_rl
  LDW R5, [A2+#FFACE]      ; exactly level: split by facing
  CMP R5, #0
  BEQ sp_lr
sp_rl:
  ADD R0, R4               ; F1 is on the right
  SUB R1, R4
  BRA sp_set
sp_lr:
  SUB R0, R4               ; F1 is on the left
  ADD R1, R4
sp_set:
  STW R0, [A2+#FX]
  STW R1, [A3+#FX]
  CALL clampx
  LDA A2, #F2
  CALL clampx
  LDA A2, #F1              ; a fighter pinned at the wall: the other takes the push
  LDW R0, [A2+#FX]
  LDW R1, [A3+#FX]
  MOV R2, R1
  SUB R2, R0
  CMP R2, #0
  BGE sp_abs2
  NEG R2
sp_abs2:
  CMP R2, #BODYW-1
  BGE sp_ret
  CMP R0, R1
  BLT sp_wl
  ; F1 on the right
  CMP R0, #XMAXW
  BNE sp_w2
  MOV R1, R0
  SUB R1, #BODYW
  STW R1, [A3+#FX]
  RET
sp_w2:
  CMP R1, #XMINW
  BNE sp_ret
  MOV R0, R1
  ADD R0, #BODYW
  STW R0, [A2+#FX]
  RET
sp_wl:
  CMP R0, #XMINW
  BNE sp_w3
  MOV R1, R0
  ADD R1, #BODYW
  STW R1, [A3+#FX]
  RET
sp_w3:
  CMP R1, #XMAXW
  BNE sp_ret
  MOV R0, R1
  SUB R0, #BODYW
  STW R0, [A2+#FX]
sp_ret:
  RET

; ---- updatecam: centre on the fighters' midpoint ----
updatecam:
  LDA A2, #F1
  LDA A3, #F2
  LDW R0, [A2+#FX]
  LDW R1, [A3+#FX]
  ADD R0, R1
  SHR R0, #1
  SUB R0, #160
  CMP R0, #0
  BGE uc_hi
  MOV R0, #0
uc_hi:
  CMP R0, #CAMMAX
  BLE uc_set
  MOV R0, #CAMMAX
uc_set:
  STW R0, [cam]
  RET

; ============================ hits ============================
; ---- attackcheck(A2 attacker, A3 defender): does a live attack box touch the rival? ----
attackcheck:
  LDW R0, [A2+#FST]
  CMP R0, #ST_ATK
  BEQ ac_go
  RET
ac_go:
  LDW R0, [A2+#FHIT]
  CMP R0, #0
  BEQ ac_go2
  RET
ac_go2:
  CALL atkrec
  LDB R0, [A0+#AT_FL2]     ; bolts hit on their own; throws have their own check
  AND R0, #F2_PROJ+F2_THROW
  BEQ ac_go2b
  AND R0, #F2_THROW
  BEQ ac_r
  JMP throwcheck
ac_r:
  RET
ac_go2b:
  LDW R4, [A2+#FT]
  LDB R1, [A0+#AT_S]
  CMP R4, R1
  BGE ac_go3
  RET
ac_go3:
  LDB R2, [A0+#AT_A]
  ADD R2, R1
  CMP R4, R2
  BLT ac_live
  RET
ac_live:
  LDW R0, [A3+#FST]        ; defender invulnerable?
  CMP R0, #ST_DOWN
  BLT ac_vuln0
  CMP R0, #ST_KO
  BGT ac_vuln0
  RET
ac_vuln0:
  CMP R0, #ST_ATK
  BNE ac_vuln
  PUSHA A0
  PUSHA A2
  MOVA A2, A3
  CALL atkrec
  POPA A2
  LDB R1, [A0+#AT_FL]
  LDB R2, [A0+#AT_S]
  POPA A0
  AND R1, #AF_INV
  BEQ ac_vuln
  LDW R3, [A3+#FT]
  CMP R3, R2
  BGE ac_vuln
  RET
ac_vuln:
  ; horizontal: box [x0, x1] vs defender [ox-12, ox+12]
  LDB R4, [A0+#AT_X0]
  LDB R5, [A0+#AT_X1]
  LDW R0, [A2+#FREACH]
  ADD R5, R0
  LDW R0, [A2+#FX]
  LDW R1, [A2+#FFACE]
  CMP R1, #0
  BNE ac_fl
  MOV R6, R0
  ADD R6, R4               ; x0
  MOV R7, R0
  ADD R7, R5               ; x1
  BRA ac_hz
ac_fl:
  MOV R6, R0
  SUB R6, R5
  MOV R7, R0
  SUB R7, R4
ac_hz:
  LDW R0, [A3+#FX]
  MOV R1, R0
  ADD R1, #12
  CMP R6, R1
  BLE ac_hz2
  RET
ac_hz2:
  SUB R0, #12
  CMP R7, R0
  BGE ac_vt
  RET
ac_vt:
  ; vertical: attacker height + [y0, y1] vs defender [hd, hd + body]
  LDW R0, [A2+#FY]
  SAR R0, #8
  NEG R0                   ; ha
  LDB R4, [A0+#AT_Y0]
  ADD R4, R0
  LDB R5, [A0+#AT_Y1]
  ADD R5, R0
  STW R5, [tmpx]
  LDW R0, [A3+#FY]
  SAR R0, #8
  NEG R0                   ; hd
  MOV R1, #56
  LDW R2, [A3+#FCRCH]
  CMP R2, #0
  BEQ ac_nc
  MOV R1, #36
ac_nc:
  LDW R2, [A3+#FY]
  CMP R2, #0
  BGE ac_ng
  MOV R1, #48
ac_ng:
  ADD R1, R0               ; defender top
  CMP R4, R1
  BLE ac_vt2
  RET
ac_vt2:
  LDW R5, [tmpx]
  CMP R5, R0
  BGE ac_conn
  RET
ac_conn:
  MOV R0, #1
  STW R0, [A2+#FHIT]
  ; spark on the defender's near side, at the box's middle height
  LDW R0, [A3+#FX]
  LDW R1, [A2+#FFACE]
  CMP R1, #0
  BNE ac_spl
  SUB R0, #8
  BRA ac_spy
ac_spl:
  ADD R0, #8
ac_spy:
  STW R0, [sparkX]
  LDW R5, [tmpx]
  ADD R4, R5
  SHR R4, #1
  MOV R0, #GROUNDY
  SUB R0, R4
  STW R0, [sparkY]
  MOV R0, #10
  STW R0, [sparkT]
  CALL tryblock
  CMP R0, #0
  BEQ ac_hit
  JMP blocked
ac_hit:
  JMP hitland

; ---- tryblock -> R0 = 1 if the defender (A3) guards this attack (A0 row) ----
tryblock:
  LDW R1, [A3+#FST]
  CMP R1, #ST_CROUCH
  BLE tb_st
  CMP R1, #ST_BLOCK
  BEQ tb_st
  BRA tb_no
tb_st:
  LDW R1, [A3+#FY]
  CMP R1, #0
  BNE tb_no
  PUSHA A2
  MOVA A2, A3
  CALL dirbits
  POPA A2
  LDW R1, [A3+#FPAD]
  MOV R2, R1
  AND R2, R7
  BEQ tb_no                ; not holding back
  LDB R2, [A0+#AT_KIND]
  CMP R2, #1
  BNE tb_noth
  AND R1, #DOWN            ; low: must crouch
  BEQ tb_no
  BRA tb_yes
tb_noth:
  CMP R2, #2
  BNE tb_yes
  AND R1, #DOWN            ; overhead: must stand
  BNE tb_no
tb_yes:
  MOV R0, #1
  RET
tb_no:
  MOV R0, #0
  RET

; ---- blocked: blockstun + pushback; No Guard / Sky Striker oaths ----
blocked:
  LDB R0, [A0+#AT_BS]
  STW R0, [A3+#FT]
  MOV R0, #ST_BLOCK
  STW R0, [A3+#FST]
  LDW R1, [A3+#FPAD]
  AND R1, #DOWN
  MOV R0, #PO_BLOCK
  MOV R2, #0
  BEQ bk_p
  MOV R0, #PO_CBLOCK
  MOV R2, #1
bk_p:
  STW R0, [A3+#FPOSE]
  STW R2, [A3+#FCRCH]
  MOV R0, #4
  CALL pushapart
  MOV R0, #1
  STW R0, [sparkK]
  MOV R0, #3
  STW R0, [freeze]
  PUSHA A0
  MOV R0, #SX_BLOCK
  CALL sfxplay
  POPA A0
  PUSHA A0                 ; No Guard: the defender just blocked
  PUSHA A2
  PUSHA A3
  MOVA A0, A2
  MOVA A2, A3              ; A2 = defender
  MOVA A3, A0              ; A3 = attacker
  MOV R0, #OA_GUARD
  CALL breakself
  POPA A3
  POPA A2
  POPA A0
  CALL skycheck
  LDB R0, [A0+#AT_FL2]     ; specials chip a quarter of their damage through a guard
  AND R0, #F2_SPEC
  BEQ bk_ret
  LDB R0, [A0+#AT_DMG]
  SHR R0, #2
  CMP R0, #1
  BGE bk_c
  MOV R0, #1
bk_c:
  LDW R1, [A3+#FHP]
  SUB R1, R0
  CMP R1, #0
  BGT bk_hp
  LDW R2, [mode]           ; training never KOs
  CMP R2, #2
  BNE bk_ko
  MOV R1, #1
  BRA bk_hp
bk_ko:
  MOV R1, #0
  STW R1, [A3+#FHP]
  MOV R0, #ST_KO           ; chipped out
  JMP hl_fall
bk_hp:
  STW R1, [A3+#FHP]
bk_ret:
  RET

; ---- skycheck(A2, A0 = the row that connected): a ground attack -> Sky Striker breaks ----
skycheck:
  LDB R0, [A0+#AT_FL]
  AND R0, #AF_GROUND
  BEQ sk_ret
  MOV R0, #OA_SKY
  CALL breakself
sk_ret:
  RET

; ---- pushapart(R0 = frames): defender slides away 2 px/f; pinned -> attacker slides ----
pushapart:
  STW R0, [A3+#FPUSH]
  STW R0, [A2+#FPUSH]
  MOV R1, #2
  LDW R2, [A2+#FX]
  LDW R3, [A3+#FX]
  CMP R3, R2
  BGE pa_r
  NEG R1
pa_r:
  STW R1, [A3+#FPUSHV]
  MOV R2, #0
  CMP R3, #XMINW+2
  BLE pa_wall
  CMP R3, #XMAXW-2
  BGE pa_wall
  BRA pa_set
pa_wall:
  MOV R2, R1
  NEG R2
pa_set:
  STW R2, [A2+#FPUSHV]
  RET

; ---- hitland: damage, stun or knockdown, meter, sparks ----
hitland:
  LDW R0, [A3+#FST]        ; still reeling from the last hit: the combo goes on
  CMP R0, #ST_HURT
  BEQ hl_cmb
  CMP R0, #ST_DIZZY
  BEQ hl_cmb
  MOV R0, #0
  STW R0, [A2+#FCMB]
hl_cmb:
  LDW R0, [A2+#FCMB]
  ADD R0, #1
  STW R0, [A2+#FCMB]
  CMP R0, #2
  BLT hl_dmg
  LDW R1, [A2+#FID]        ; "n HITS" on the attacker's side
  SHL R1, #1
  LDA A1, #cmbN
  ADD A1, R1
  STW R0, [A1]
  LDA A1, #cmbT
  ADD A1, R1
  MOV R1, #80
  STW R1, [A1]
hl_dmg:
  MOV R5, R0               ; R5 = hit number in the combo
  LDB R0, [A0+#AT_DMG]
  LDW R1, [A2+#FDMGB]
  ADD R0, R1
  LDW R1, [A3+#FARMR]
  SUB R0, R1
  CMP R5, #3               ; from the third hit a combo does 3/4 damage
  BLT hl_sc
  MOV R1, R0
  SAR R1, #2
  SUB R0, R1
hl_sc:
  CMP R0, #1
  BGE hl_d
  MOV R0, #1
hl_d:
  LDW R1, [A3+#FST]        ; stun builds with damage (a dizzy fighter starts over)
  MOV R2, #0
  CMP R1, #ST_DIZZY
  BEQ hl_z
  LDW R2, [A3+#FDIZ]
  ADD R2, R0
hl_z:
  STW R2, [A3+#FDIZ]
  LDW R1, [A3+#FHP]
  SUB R1, R0
  CMP R1, #1
  BGE hl_hp
  MOV R1, #0
  LDW R2, [mode]           ; training never KOs
  CMP R2, #2
  BNE hl_hp
  MOV R1, #1
hl_hp:
  STW R1, [A3+#FHP]
  MOV R0, #0
  STW R0, [sparkK]
  STW R0, [A3+#FCRCH]
  MOV R0, #8
  STW R0, [A3+#FFLASH]
  PUSHA A0
  MOVA A0, A2              ; meter: +3 for landing a hit (1 without a standing oath)
  MOV R0, #2
  CALL keptgain
  MOV R0, #1
  CALL addmeter
  MOVA A0, A3              ; +1 for taking one, if the oath stands
  MOV R0, #1
  CALL keptgain
  POPA A0
  LDW R0, [A3+#FHP]
  CMP R0, #0
  BEQ hl_ko
  LDB R0, [A0+#AT_FL]
  AND R0, #AF_KD
  BNE hl_kd
  LDW R0, [A3+#FY]
  CMP R0, #0
  BLT hl_kd
  LDB R0, [A0+#AT_HS]      ; plain hit: hitstun + pushback
  STW R0, [A3+#FT]
  MOV R0, #ST_HURT
  STW R0, [A3+#FST]
  MOV R0, #PO_HURT
  STW R0, [A3+#FPOSE]
  MOV R0, #5
  CALL pushapart
  MOV R0, #4
  STW R0, [freeze]
  LDB R0, [A0+#AT_DMG]     ; heavier hits thump lower
  SHL R0, #1
  ADD R0, #10
  CALL noisehit
  CALL skycheck
  RET
hl_ko:
  MOV R0, #ST_KO
  BRA hl_fall
hl_kd:
  MOV R0, #ST_DOWN
hl_fall:
  STW R0, [A3+#FST]
  MOV R0, #0
  STW R0, [A3+#FT]
  MOV R0, #KNOCKV
  STW R0, [A3+#FVY]
  MOV R1, #2               ; thrown away from the attacker
  LDW R2, [A2+#FX]
  LDW R3, [A3+#FX]
  CMP R3, R2
  BGE hl_kv
  NEG R1
hl_kv:
  STW R1, [A3+#FVX]
  MOV R0, #PO_HURT
  STW R0, [A3+#FPOSE]
  MOV R0, #6
  STW R0, [freeze]
  MOV R0, #16
  CALL noisehit
  CALL skycheck
  RET

; ---- throwcheck(A2 = thrower, A0 = throw row): one try on the first active frame ----
throwcheck:
  LDW R4, [A2+#FT]
  LDB R1, [A0+#AT_S]
  CMP R4, R1
  BEQ tc_go
  RET
tc_go:
  MOV R0, #1
  STW R0, [A2+#FHIT]
  LDB R3, [A0+#AT_X1]
  CALL throwable
  CMP R0, #0
  BNE tc_in
  RET                      ; whiffed: a long recovery
tc_in:
  LDW R0, [A3+#FST]        ; both grabbing at once: a tech, nobody falls
  CMP R0, #ST_ATK
  BNE tc_hit
  PUSHA A0
  PUSHA A2
  MOVA A2, A3
  CALL atkrec
  POPA A2
  LDB R0, [A0+#AT_FL2]
  POPA A0
  AND R0, #F2_THROW
  BEQ tc_hit
  MOV R0, #1
  STW R0, [A3+#FHIT]
  MOV R0, #ST_BLOCK
  STW R0, [A2+#FST]
  STW R0, [A3+#FST]
  MOV R0, #14
  STW R0, [A2+#FT]
  STW R0, [A3+#FT]
  MOV R0, #PO_BLOCK
  STW R0, [A2+#FPOSE]
  STW R0, [A3+#FPOSE]
  MOV R0, #8
  CALL pushapart
  MOV R0, #40
  STW R0, [techT]
  MOV R0, #300
  CALL sfxblip
  RET
tc_hit:
  LDB R0, [A0+#AT_FL2]     ; a back throw: the rival is thrown over to the far side
  AND R0, #F2_BACK
  BEQ tc_fwd
  CALL dirbits
  LDW R0, [A2+#FX]
  CMP R5, #0
  BGT tc_bl
  ADD R0, #20
  BRA tc_bs
tc_bl:
  SUB R0, #20
tc_bs:
  STW R0, [A3+#FX]
tc_fwd:
  LDW R0, [A3+#FX]
  STW R0, [sparkX]
  MOV R0, #GROUNDY-36
  STW R0, [sparkY]
  MOV R0, #10
  STW R0, [sparkT]
  JMP hitland

; ---- firebolt(A2, A0 = row): launch a Seal Bolt (AT_DASH = speed) ----
firebolt:
  LDW R0, [A2+#FPJT]
  CMP R0, #0
  BNE fb_ret
  MOV R0, #1
  STW R0, [A2+#FPJT]
  LDW R0, [A2+#FATK]
  STW R0, [A2+#FPJA]
  LDB R2, [A0+#AT_DASH]
  CALL dirbits
  LDW R0, [A2+#FX]
  CMP R5, #0
  BGT fb_r
  NEG R2
  SUB R0, #24
  BRA fb_s
fb_r:
  ADD R0, #24
fb_s:
  STW R0, [A2+#FPJX]
  STW R2, [A2+#FPJV]
  MOV R0, #120
  CALL sfxblip
fb_ret:
  RET

; ---- projstep(A2): the bolt flies until it leaves the screen ----
projstep:
  LDW R0, [A2+#FPJT]
  CMP R0, #0
  BEQ pj_ret
  ADD R0, #1
  STW R0, [A2+#FPJT]
  LDW R0, [A2+#FPJX]
  LDW R1, [A2+#FPJV]
  ADD R0, R1
  STW R0, [A2+#FPJX]
  LDW R1, [cam]
  SUB R0, R1
  CMP R0, #-16
  BLT pj_gone
  CMP R0, #336
  BLE pj_ret
pj_gone:
  MOV R0, #0
  STW R0, [A2+#FPJT]
pj_ret:
  RET

; ---- projcheck(A2 = owner, A3 = target): bolts clash, or hit / are blocked ----
projcheck:
  LDW R0, [A2+#FPJT]
  CMP R0, #0
  BNE pc_live
  RET
pc_live:
  LDW R0, [A3+#FPJT]       ; two bolts meet: both burst
  CMP R0, #0
  BEQ pc_body
  LDW R0, [A2+#FPJX]
  LDW R1, [A3+#FPJX]
  SUB R0, R1
  CMP R0, #0
  BGE pc_a
  NEG R0
pc_a:
  CMP R0, #16
  BGT pc_body
  MOV R0, #0
  STW R0, [A2+#FPJT]
  STW R0, [A3+#FPJT]
  STW R1, [sparkX]
  MOV R0, #GROUNDY-BOLTY
  STW R0, [sparkY]
  MOV R0, #10
  STW R0, [sparkT]
  MOV R0, #1
  STW R0, [sparkK]
  MOV R0, #20
  CALL noisehit
  RET
pc_body:
  LDW R0, [A3+#FST]        ; down or KO: it passes over
  CMP R0, #ST_DOWN
  BEQ pc_r0
  CMP R0, #ST_KO
  BNE pc_inv
pc_r0:
  RET
pc_inv:
  CMP R0, #ST_ATK          ; Palm Rise's invulnerable startup
  BNE pc_v
  PUSHA A2
  MOVA A2, A3
  CALL atkrec
  POPA A2
  LDB R1, [A0+#AT_FL]
  AND R1, #AF_INV
  BEQ pc_v
  LDB R2, [A0+#AT_S]
  LDW R3, [A3+#FT]
  CMP R3, R2
  BLT pc_ret
pc_v:
  LDW R0, [A2+#FPJX]       ; horizontal: bolt +-8 against the body +-12
  LDW R1, [A3+#FX]
  SUB R0, R1
  CMP R0, #0
  BGE pc_b
  NEG R0
pc_b:
  CMP R0, #20
  BGT pc_ret
  LDW R0, [A3+#FY]         ; feet above the bolt's top: jumped it
  SAR R0, #8
  NEG R0
  CMP R0, #BOLTY+8
  BGT pc_ret
  MOV R0, #0
  STW R0, [A2+#FPJT]
  LDW R0, [A2+#FPJX]
  STW R0, [sparkX]
  MOV R0, #GROUNDY-BOLTY
  STW R0, [sparkY]
  MOV R0, #10
  STW R0, [sparkT]
  LDW R0, [A2+#FPJA]
  SHL R0, #5
  LDA A0, #ATKTAB
  ADD A0, R0
  CALL tryblock
  CMP R0, #0
  BEQ pc_hit
  JMP blocked
pc_hit:
  JMP hitland
pc_ret:
  RET

; ---- breakself(A2 = oath-taker, A3 = rival, R0 = oath this action breaks) ----
breakself:
  LDW R1, [A2+#FOATH]
  CMP R1, R0
  BNE bs_ret
  LDW R1, [A2+#FOBRK]
  CMP R1, #0
  BNE bs_ret
  MOV R1, #1
  STW R1, [A2+#FOBRK]
  STW R0, [brkOath]
  LDW R0, [A2+#FID]
  STW R0, [brkWho]
  MOV R0, #120
  STW R0, [brkT]
  LDW R0, [A2+#FMTR]       ; the whole meter goes to the rival
  MOV R1, #0
  STW R1, [A2+#FMTR]
  PUSHA A0
  MOVA A0, A3
  CALL addmeter
  POPA A0
  MOV R0, #400
  CALL sfxblip
  MOV R0, #8
  CALL noisehit
bs_ret:
  RET

; ============================ KO / round end ============================
initko:
  MOV R0, #G_KO
  STW R0, [gstate]
  MOV R0, #0
  STW R0, [gT]
  STW R0, [winner]
  LDA A2, #F1
  LDA A3, #F2
  LDW R0, [A2+#FHP]
  LDW R1, [A3+#FHP]
  CMP R0, R1
  BEQ ik_done              ; a draw: nobody scores
  MOV R2, #1
  BGT ik_w
  MOV R2, #2
  LDA A2, #F2
ik_w:
  STW R2, [winner]
  LDW R0, [A2+#FWINS]
  ADD R0, #1
  STW R0, [A2+#FWINS]
ik_done:
  LDW R0, [kokind]
  CMP R0, #0
  BNE ik_time
  MOV R0, #72              ; a KO plays its fall in slow motion
  STW R0, [slowT]
  MOV R0, #SX_KO
  CALL sfxplay
  RET
ik_time:
  MOV R0, #0
  STW R0, [slowT]
  MOV R0, #90
  CALL sfxblip
  RET

koframe:
  LDW R0, [slowT]          ; slow motion: the scene moves every third frame
  CMP R0, #0
  BEQ kf_run
  SUB R0, #1
  STW R0, [slowT]
  MOV R1, #0
  MOV R2, #3
  DIVU R0, R2
  CMP R1, #0
  BEQ kf_run
  JMP kf_draw
kf_run:
  LDW R0, [gT]
  ADD R0, #1
  STW R0, [gT]
  LDA A0, #kostep
  CALL both
  LDW R0, [gT]
  CMP R0, #60              ; the winner strikes a pose
  BNE kf_wd
  LDW R0, [winner]
  CMP R0, #0
  BEQ kf_wd
  LDA A2, #F1
  CMP R0, #1
  BEQ kf_wp
  LDA A2, #F2
kf_wp:
  MOV R0, #ST_WIN
  STW R0, [A2+#FST]
  MOV R0, #PO_WIN
  STW R0, [A2+#FPOSE]
kf_wd:
  LDW R0, [gT]
  CMP R0, #240
  BGE kf_next
  CMP R0, #90
  BLT kf_draw
  CALL anyedge
  AND R0, #START
  BEQ kf_draw
kf_next:
  LDW R0, [mode]           ; the demo is one round
  CMP R0, #3
  BNE kf_nd
  JMP demoend
kf_nd:
  LDA A2, #F1              ; match over?
  LDW R0, [A2+#FWINS]
  CMP R0, #2
  BGE kf_match
  LDA A2, #F2
  LDW R0, [A2+#FWINS]
  CMP R0, #2
  BGE kf_match
  LDW R0, [round]
  ADD R0, #1
  STW R0, [round]
  CALL initoath
  RET
kf_match:
  CALL initmatch
  RET
kf_draw:
  CALL oambegin
  LDW R0, [gT]
  CMP R0, #80
  BGE kf_reveal
  MOV R1, #64
  LDA A1, #sKO
  LDW R0, [kokind]
  CMP R0, #0
  BEQ kf_big
  LDA A1, #sTIME
kf_big:
  CALL cbig
  BRA kf_f
kf_reveal:
  BNE kf_rv                ; first reveal frame: a plaque behind the verdict
  MOV R4, #6
  MOV R5, #6
  MOV R6, #34
  MOV R7, #14
  CALL panel
kf_rv:
  LDA A2, #F1
  MOV R1, #56
  CALL reveal
  LDA A2, #F2
  MOV R1, #68
  CALL reveal
  LDW R0, [winner]
  LDA A1, #sDRAW
  CMP R0, #0
  BEQ kf_wt
  LDA A1, #sP1WINS
  CMP R0, #1
  BEQ kf_wt
  LDA A1, #sP2WINS
kf_wt:
  MOV R1, #88
  CALL cbig
kf_f:
  CALL drawfighters
  CALL drawhud
  RET

; ---- kostep: let falls finish; the standing fighter drops out of any action ----
kostep:
  LDW R0, [A2+#FST]
  CMP R0, #ST_DOWN
  BEQ ks_phys
  CMP R0, #ST_KO
  BEQ ks_phys
  CMP R0, #ST_WIN
  BEQ ks_phys
  LDW R1, [A2+#FY]
  CMP R1, #0
  BLT ks_phys
  MOV R0, #ST_IDLE
  STW R0, [A2+#FST]
  MOV R0, #PO_GUARD
  STW R0, [A2+#FPOSE]
ks_phys:
  CALL physics
  RET

; ---- reveal(A2, R1 = y): "P1 KEPT NO GUARD" / "P1 BROKE ..." / "P1 SWORE NOTHING" ----
reveal:
  MOV R0, #64
  LDA A1, #sP1
  LDW R2, [A2+#FID]
  CMP R2, #0
  BEQ rv_n
  LDA A1, #sP2
rv_n:
  PUSH R1
  CALL stext
  POP R1
  ADD R0, #8
  LDW R2, [A2+#FOATH]
  CMP R2, #0
  BNE rv_o
  LDA A1, #sNOTHING
  CALL stext
  RET
rv_o:
  LDA A1, #sKEPT
  LDW R3, [A2+#FOBRK]
  CMP R3, #0
  BEQ rv_k
  LDA A1, #sBROKE
rv_k:
  PUSH R1
  CALL stext
  POP R1
  ADD R0, #8
  LDW R2, [A2+#FOATH]
  CALL oathname
  CALL stext
  RET

; ---- oathname(R2 = oath 1..4) -> A1 ----
oathname:
  SUB R2, #1
  MOV R3, R2
  SHL R3, #1
  ADD R3, R2
  LDA A1, #OATHNAMES
  ADD A1, R3
  LDADDR A1, [A1]
  RET

; ---- drawbreak: "P2 BROKE STAND FAST" while the announcement runs ----
drawbreak:
  LDW R0, [surgeT]
  CMP R0, #0
  BEQ db_brk
  SUB R0, #1
  STW R0, [surgeT]
  MOV R1, #40
  LDA A1, #sSURGE
  CALL cbig
  RET
db_brk:
  LDW R0, [brkT]
  CMP R0, #0
  BEQ db_ret
  SUB R0, #1
  STW R0, [brkT]
  AND R0, #8
  BEQ db_ret
  MOV R0, #72
  MOV R1, #40
  LDA A1, #sP1
  LDW R2, [brkWho]
  CMP R2, #0
  BEQ db_who
  LDA A1, #sP2
db_who:
  CALL stext
  ADD R0, #8
  LDA A1, #sBROKE
  CALL stext
  ADD R0, #8
  LDW R2, [brkOath]
  CALL oathname
  CALL stext
db_ret:
  RET

; ============================ match end ============================
initmatch:
  MOV R0, #G_MATCH
  STW R0, [gstate]
  MOV R0, #0
  STW R0, [gT]
  LDW R0, [mode]
  CMP R0, #0
  BNE im_ret
  LDA A2, #F1              ; arcade: a win advances the ladder
  LDW R0, [A2+#FWINS]
  CMP R0, #2
  BLT im_ret
  LDW R0, [rival]
  ADD R0, #1
  STW R0, [rival]
  LDW R1, [best]
  CMP R0, R1
  BLE im_nb
  STW R0, [best]
  CALL savepicks
im_nb:
  LDW R0, [rival]
  CMP R0, #2
  BNE im_nbn
  MOV R1, #1
  STW R1, [bonusnx]
im_nbn:
  CMP R0, #NRIVAL
  BLT im_ret
  MOV R0, #G_CHAMP
  STW R0, [gstate]
im_ret:
  RET

matchframe:
  LDW R0, [gT]
  ADD R0, #1
  STW R0, [gT]
  LDA A0, #kostep
  CALL both
  LDW R0, [gT]
  CMP R0, #40
  BLT mf_draw
  CALL anyedge
  MOV R1, R0
  AND R1, #START
  BEQ mf_b
  LDW R0, [mode]           ; Start: next rival / continue (arcade), rematch (versus)
  CMP R0, #0
  BNE mf_rem
  LDW R0, [rival]
  CALL startmatch
  RET
mf_rem:
  CALL startmatch
  RET
mf_b:
  AND R0, #BBTN
  BEQ mf_draw
  CALL inittitle
  RET
mf_draw:
  CALL oambegin
  LDW R0, [mode]
  CMP R0, #0
  BNE mf_vs
  LDA A2, #F1
  LDW R0, [A2+#FWINS]
  CMP R0, #2
  BLT mf_lose
  MOV R1, #56
  LDA A1, #sYOUWIN
  CALL cbig
  MOV R1, #84
  LDA A1, #sNEXT
  CALL ctext
  BRA mf_q
mf_lose:
  MOV R1, #56
  LDA A1, #sYOULOSE
  CALL cbig
  MOV R1, #84
  LDA A1, #sCONT
  CALL ctext
  BRA mf_q
mf_vs:
  MOV R1, #56
  LDA A1, #sP1DUEL
  LDA A2, #F1
  LDW R0, [A2+#FWINS]
  CMP R0, #2
  BGE mf_vw
  LDA A1, #sP2DUEL
mf_vw:
  CALL cbig
  MOV R1, #84
  LDA A1, #sREMATCH
  CALL ctext
mf_q:
  LDA A2, #F1              ; the winner's line
  LDW R0, [A2+#FWINS]
  CMP R0, #2
  BGE mf_qw
  LDA A2, #F2
mf_qw:
  LDW R0, [A2+#FBODY]
  CMP R0, #NBODY
  BGE mf_qn
  MOV R1, R0
  SHL R1, #1
  ADD R1, R0
  LDA A0, #QUOTETAB
  ADD A0, R1
  LDADDR A1, [A0]
  MOV R1, #120
  CALL ctext
mf_qn:
  MOV R1, #96
  LDA A1, #sQUIT
  CALL ctext
  CALL drawfighters
  CALL drawhud
  RET

champframe:
  LDW R0, [gT]
  ADD R0, #1
  STW R0, [gT]
  LDA A0, #kostep
  CALL both
  LDW R0, [gT]
  CMP R0, #60
  BLT chf_draw
  CALL anyedge
  AND R0, #START
  BEQ chf_draw
  CALL inittitle
  RET
chf_draw:
  LDW R0, [gT]
  CMP R0, #1
  BNE chf_np
  MOV R4, #3               ; first frame: a plaque for the ending
  MOV R5, #10
  MOV R6, #37
  MOV R7, #18
  CALL panel
chf_np:
  CALL oambegin
  MOV R1, #40
  LDA A1, #sCHAMP1
  CALL cbig
  MOV R1, #60
  LDA A1, #sCHAMP2
  CALL cbig
  LDA A2, #F1              ; the champion's own ending
  LDW R0, [A2+#FBODY]
  MOV R1, R0
  SHL R1, #1
  ADD R1, R0
  LDA A0, #ENDTAB
  ADD A0, R1
  LDADDR A1, [A0]
  MOV R1, #88
  CALL endlines
  LDW R0, [gT]
  CMP R0, #60
  BLT chf_ns
  AND R0, #32
  BNE chf_ns
  MOV R1, #212
  LDA A1, #sCHAMP3
  CALL ctext
chf_ns:
  LDA A2, #F1
  MOV R0, #ST_WIN
  STW R0, [A2+#FST]
  MOV R0, #PO_WIN
  STW R0, [A2+#FPOSE]
  CALL drawfighters
  CALL drawhud
  RET

; ---- endlines(A1 = text, lines split by 10; R1 = y): centred lines 12 px apart ----
endlines:
  LDA A0, #lbuf
el_cp:
  LDB R0, [A1]
  INC A1
  CMP R0, #10
  BEQ el_out
  CMP R0, #0
  BEQ el_out
  STB R0, [A0]
  INC A0
  BRA el_cp
el_out:
  PUSH R0
  MOV R2, #0
  STB R2, [A0]
  PUSH R1
  PUSHA A1
  LDA A1, #lbuf
  CALL ctext
  POPA A1
  POP R1
  POP R0
  ADD R1, #12
  CMP R0, #0
  BNE endlines
  RET

; ============================ CPU ============================
; ---- cputhink(A2 = CPU, A3 = player): sets FAIPAD (held directions) and FAIATK ----
cputhink:
  LDW R0, [A2+#FST]
  CMP R0, #ST_DIZZY        ; dizzy: mash (level 0 just waits it out)
  BNE ct_nd
  CALL nextrng
  AND R0, #$F0
  LDW R1, [A2+#FAI]
  CMP R1, #0
  BNE ct_m
  MOV R0, #0
ct_m:
  STW R0, [A2+#FAIPAD]
  RET
ct_nd:
  CMP R0, #ST_ATK          ; a normal just connected: maybe chain or cancel
  BNE ct_nx
  JMP cpufollow
ct_nx:
  CMP R0, #ST_JUMP         ; mid-jump: strike on the way down when close
  BNE ct_gnd
  LDW R0, [A2+#FVY]
  CMP R0, #0
  BLE ct_hold
  CALL cpudist
  CMP R0, #60
  BGT ct_hold
  MOV R0, #AK_AHKICK+1
  CALL cpuhonour
  STW R0, [A2+#FAIATK]
  BRA ct_hold
ct_gnd:
  LDW R0, [A2+#FAI]        ; level 2+: the player's wind-up forces a fresh decision
  CMP R0, #2
  BLT ct_tk
  LDW R0, [A3+#FST]
  CMP R0, #ST_ATK
  BNE ct_tk
  LDW R0, [A3+#FT]
  CMP R0, #1
  BNE ct_tk
  JMP ct_decide
ct_tk:
  LDW R0, [A2+#FTHINK]
  SUB R0, #1
  STW R0, [A2+#FTHINK]
  BLE ct_decide
ct_hold:
  LDW R0, [A2+#FAIHOLD]    ; keep holding the last directions for a while
  CMP R0, #0
  BEQ ct_clear
  SUB R0, #1
  STW R0, [A2+#FAIHOLD]
  LDW R0, [A2+#FAIPAD]
  AND R0, #$FFFE           ; never hold Up (one jump per decision)
  STW R0, [A2+#FAIPAD]
  RET
ct_clear:
  MOV R0, #0
  STW R0, [A2+#FAIPAD]
  RET
ct_decide:
  LDW R0, [A2+#FAI]        ; next decision after the reaction delay
  LDA A0, #AIREACT
  ADD A0, R0
  LDB R0, [A0]
  STW R0, [A2+#FTHINK]
  MOV R0, #0
  STW R0, [A2+#FAIPAD]
  STW R0, [A2+#FAIHOLD]
  CALL dirbits
  CALL nextrng
  AND R0, #15
  MOV R4, R0               ; R4 = roll 0..15
  LDW R0, [A3+#FPJT]       ; a Seal Bolt coming: block it or jump it
  CMP R0, #0
  BEQ ct_nobolt
  LDW R0, [A3+#FPJX]
  LDW R1, [A2+#FX]
  SUB R0, R1
  CMP R0, #0
  BGE ct_bd
  NEG R0
ct_bd:
  CMP R0, #110
  BGT ct_nobolt
  LDW R0, [A2+#FAI]
  CMP R0, #0
  BEQ ct_nobolt
  LDA A0, #AIBLOCK
  ADD A0, R0
  LDB R0, [A0]
  CMP R4, R0
  BGE ct_nobolt
  MOV R0, R4
  AND R0, #1
  BNE ct_bj
  LDW R0, [A2+#FOATH]      ; honouring No Guard: jump it instead
  CMP R0, #OA_GUARD
  BEQ ct_bj
  STW R7, [A2+#FAIPAD]
  MOV R0, #24
  STW R0, [A2+#FAIHOLD]
  RET
ct_bj:
  MOV R0, R6
  OR R0, #UP
  STW R0, [A2+#FAIPAD]
  RET
ct_nobolt:
  LDW R0, [A3+#FST]        ; the player is attacking: maybe guard
  CMP R0, #ST_ATK
  BNE ct_noatk
  CALL cpudist
  CMP R0, #80
  BGT ct_noatk
  LDW R0, [A2+#FAI]
  LDA A0, #AIBLOCK
  ADD A0, R0
  LDB R0, [A0]
  CMP R4, R0
  BGE ct_noatk
  LDW R0, [A2+#FAI]        ; honouring No Guard: never block
  CMP R0, #0
  BEQ ct_blk
  LDW R0, [A2+#FOATH]
  CMP R0, #OA_GUARD
  BEQ ct_noatk
ct_blk:
  MOV R0, R7               ; hold back; crouch for a low (level 2+ reads it)
  PUSHA A2
  MOVA A2, A3
  CALL atkrec
  POPA A2
  LDB R1, [A0+#AT_KIND]
  CMP R1, #1
  BNE ct_bset
  LDW R1, [A2+#FAI]
  CMP R1, #2
  BLT ct_bset
  OR R0, #DOWN
ct_bset:
  STW R0, [A2+#FAIPAD]
  MOV R0, #14
  STW R0, [A2+#FAIHOLD]
  RET
ct_noatk:
  LDW R0, [A3+#FY]         ; anti-air: Palm Rise against a jump-in
  CMP R0, #$F000
  BGE ct_noair
  LDW R0, [A2+#FAI]
  CMP R0, #1
  BLT ct_noair
  CALL cpudist
  CMP R0, #64
  BGT ct_noair
  CMP R4, #10
  BGE ct_noair
  LDW R1, [A2+#FAI]        ; uppercut; level 2+ mixes in its anti-air special
  CMP R1, #2
  BLT ct_aau
  CMP R4, #5
  BGE ct_aau
  MOV R1, #1
  CALL cpuint
  CMP R0, #0
  BNE ct_aa
ct_aau:
  MOV R0, #AK_CHPUNCH+1
ct_aa:
  JMP ct_attack
ct_noair:
  LDW R0, [A2+#FMTR]       ; full meter and close: Oath Surge
  CMP R0, #MTRMAX
  BLT ct_nosup
  CALL cpudist
  CMP R0, #70
  BGT ct_nosup
  MOV R0, #AK_SURGE+1
  BRA ct_attack
ct_nosup:
  CALL cpudist
  CMP R0, #90
  BLE ct_mid
  LDW R1, [A2+#FAI]        ; far: rush in, jump in, or walk in
  CMP R1, #2
  BLT ct_far1
  CMP R4, #3
  BGE ct_far1
  CMP R0, #150
  BGT ct_far1
  MOV R1, #2
  CALL cpuint
  CMP R0, #0
  BEQ ct_far0
  JMP ct_attack
ct_far0:
  CALL cpudist
  LDW R1, [A2+#FAI]
ct_far1:
  CMP R1, #1               ; level 1+: a Seal Bolt from range
  BLT ct_walkin
  CMP R4, #7
  BGE ct_fj
  CMP R0, #120
  BLT ct_fj
  LDW R0, [A2+#FPJT]
  CMP R0, #0
  BNE ct_fj
  MOV R1, #0
  CALL cpuint
  CMP R0, #0
  BEQ ct_fj
  JMP ct_attack
ct_fj:
  CMP R4, #12
  BLT ct_walkin
  MOV R0, R6               ; jump forward
  OR R0, #UP
  STW R0, [A2+#FAIPAD]
  RET
ct_walkin:
  STW R6, [A2+#FAIPAD]
  MOV R0, #20
  STW R0, [A2+#FAIHOLD]
  RET
ct_mid:
  CMP R0, #44
  BLE ct_close
  CMP R4, #6               ; mid range: step in, kicks, sweep, wait, or jump in
  BLT ct_walkin
  CMP R4, #8
  BLT ct_kick
  CMP R4, #9
  BLT ct_hkick
  CMP R4, #12
  BLT ct_sweep
  CMP R4, #14
  BLT ct_wait
  MOV R0, R6
  OR R0, #UP
  STW R0, [A2+#FAIPAD]
  RET
ct_kick:
  MOV R0, #AK_KICK+1
  BRA ct_attack
ct_hkick:
  MOV R1, #4               ; its mix-up special if it has one
  CALL cpuint
  CMP R0, #0
  BNE ct_hk2
  MOV R0, #AK_HKICK+1
ct_hk2:
  BRA ct_attack
ct_sweep:
  MOV R0, #AK_SWEEP+1
  BRA ct_attack
ct_wait:
  RET
ct_close:
  CMP R4, #4               ; close: jab, low kick, throw, heavy punch, kick, back off, or guard
  BLT ct_punch
  CMP R4, #6
  BLT ct_clk
  CMP R4, #8
  BLT ct_throw
  CMP R4, #10
  BLT ct_hp
  CMP R4, #11
  BLT ct_kick
  CMP R4, #13
  BLT ct_backoff
  STW R7, [A2+#FAIPAD]
  MOV R0, #10
  STW R0, [A2+#FAIHOLD]
  RET
ct_punch:
  MOV R0, #AK_PUNCH+1
  BRA ct_attack
ct_clk:
  MOV R0, #AK_CLK+1
  BRA ct_attack
ct_throw:
  LDW R0, [A2+#FAI]        ; level 1+ throws (or command-grabs) when the player is in reach
  CMP R0, #0
  BEQ ct_hp
  MOV R1, #3
  CALL cpuint
  CMP R0, #0
  BEQ ct_nthr
  PUSH R0
  MOV R3, #52
  CALL throwable
  MOV R1, R0
  POP R0
  CMP R1, #0
  BNE ct_atk2
ct_nthr:
  MOV R3, #THROWR
  CALL throwable
  CMP R0, #0
  BEQ ct_hp
  MOV R0, #AK_THROW+1
ct_atk2:
  BRA ct_attack
ct_hp:
  MOV R0, #AK_HPUNCH+1
  BRA ct_attack
ct_backoff:
  LDW R0, [A2+#FAI]        ; honouring Stand Fast: never back off
  CMP R0, #0
  BEQ ct_bo
  LDW R0, [A2+#FOATH]
  CMP R0, #OA_STAND
  BEQ ct_punch
ct_bo:
  STW R7, [A2+#FAIPAD]
  MOV R0, #10
  STW R0, [A2+#FAIHOLD]
  RET
ct_attack:
  CALL cpuhonour
  CMP R0, #0
  BEQ ct_jumpin
  STW R0, [A2+#FAIATK]
  RET
ct_jumpin:
  MOV R0, R6               ; Sky Striker: take it to the air instead
  OR R0, #UP
  STW R0, [A2+#FAIPAD]
  RET

; ---- cpuhonour(R0 = attack + 1) -> R0 = attack + 1 the CPU's oath allows (0 = jump in) ----
cpuhonour:
  LDW R1, [A2+#FAI]
  CMP R1, #0
  BEQ ch_ok                ; level 0 ignores its own oath
  LDW R1, [A2+#FOBRK]
  CMP R1, #0
  BNE ch_ok
  LDW R1, [A2+#FOATH]
  CMP R1, #OA_FISTS
  BNE ch_sky
  SUB R0, #1               ; Fists Only: every kick becomes its punch
  LDA A0, #FISTMAP
  ADD A0, R0
  LDB R0, [A0]
  ADD R0, #1
  RET
ch_sky:
  CMP R1, #OA_SKY
  BNE ch_ok
  CMP R0, #AK_APUNCH+1     ; Sky Striker: only air attacks
  BEQ ch_ok
  CMP R0, #AK_AKICK+1
  BEQ ch_ok
  CMP R0, #AK_AHPUNCH+1
  BEQ ch_ok
  CMP R0, #AK_AHKICK+1
  BEQ ch_ok
  MOV R0, #0
ch_ok:
  RET

; ---- cpufollow: once a normal hits, maybe chain a light or cancel into a special ----
cpufollow:
  LDW R0, [A2+#FHIT]
  CMP R0, #0
  BEQ cw_out0
  LDW R0, [A2+#FAICX]
  CMP R0, #0
  BNE cw_out0
  LDW R0, [A3+#FST]        ; only on a hit (a blocked string stops)
  CMP R0, #ST_HURT
  BNE cw_out0
  MOV R0, #1
  STW R0, [A2+#FAICX]
  LDW R1, [A2+#FAI]
  CMP R1, #0
  BNE cw_lv
cw_out0:
  JMP ct_gnd
cw_lv:
  CALL atkrec
  LDB R5, [A0+#AT_FL2]
  CALL nextrng
  AND R0, #15
  MOV R4, R0
  LDW R1, [A2+#FAI]
  LDA A0, #AICOMBO
  ADD A0, R1
  LDB R1, [A0]
  CMP R4, R1
  BLT cw_go
  JMP ct_gnd
cw_go:
  MOV R0, R5
  AND R0, #F2_CHAIN
  BEQ cw_sp
  CMP R4, #3
  BGE cw_sp
  LDW R0, [A2+#FATK]       ; chain the same light again
  ADD R0, #1
  BRA cw_set
cw_sp:
  MOV R0, R5
  AND R0, #F2_CXL
  BEQ cw_out
  MOV R1, R4               ; its rush, or its bolt when one is free
  AND R1, #1
  BEQ cw_rush
  LDW R1, [A2+#FPJT]
  CMP R1, #0
  BNE cw_rush
  MOV R1, #0
  CALL cpuint
  CMP R0, #0
  BNE cw_set
cw_rush:
  MOV R1, #2
  CALL cpuint
  CMP R0, #0
  BNE cw_set
  JMP ct_gnd
cw_set:
  CALL cpuhonour
  CMP R0, #0
  BEQ cw_out
  STW R0, [A2+#FAIATK]
  RET
cw_out:
  JMP ct_gnd

; ---- cpuint(A2, R1 = 0 ranged, 1 anti-air, 2 rush, 3 grab, 4 mix-up) -> R0 = attack + 1, or 0 ----
cpuint:
  LDW R0, [A2+#FBODY]
  SHL R0, #3
  ADD R0, R1
  LDA A0, #CHAI
  ADD A0, R0
  LDB R0, [A0]
  CMP R0, #$FF
  BEQ ci_no
  ADD R0, #1
  RET
ci_no:
  MOV R0, #0
  RET

; ---- cpudist -> R0 = |x1 - x2| ----
cpudist:
  LDW R0, [A2+#FX]
  LDW R1, [A3+#FX]
  SUB R0, R1
  CMP R0, #0
  BGE cd_ret
  NEG R0
cd_ret:
  RET

; ============================ drawing ============================
; ---- oambegin: clear OAM by DMA fill, rewind the port ----
oambegin:
  MOV R0, #0
  STW R0, [DMA_DST]
  STW R0, [DMA_FILL]
  MOV R0, #1024
  STW R0, [DMA_LEN]
  MOV R0, #$11             ; OAM space, constant fill
  STB R0, [DMA_MODE]
  MOV R0, #1
  STB R0, [DMA_CTRL]
  MOV R0, #0
  STW R0, [OAM_INDEX]
  MOV R0, #6
  STW R0, [sprpri]
  RET

; ---- emittile(R0=x, R1=y, R5=tile, R6=attrLo): one descriptor at [sprpri]; clobbers R2 ----
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
  MOV R2, R5
  SHR R2, #8
  STB R2, [OAM_DATA]
  STB R6, [OAM_DATA]
  LDW R2, [sprpri]
  OR R2, #$80
  STB R2, [OAM_DATA]
  RET

; ---- stext(R0=x, R1=y, A1=string): 8x8 sprite text; R0 ends past the last char ----
stext:
  MOV R6, #PB_FONT
st_lp:
  LDB R5, [A1]
  CMP R5, #0
  BEQ st_done
  CMP R5, #32
  BEQ st_adv
  CALL emittile
st_adv:
  ADD R0, #8
  INC A1
  BRA st_lp
st_done:
  RET

; ---- btext(R0=x, R1=y, A1): 16x16 big-font sprite text ----
btext:
  MOV R6, #SZ16
  OR R6, #PB_BIG
bt_lp:
  LDB R5, [A1]
  CMP R5, #0
  BEQ bt_done
  CMP R5, #32
  BEQ bt_adv
  SUB R5, #32
  SHL R5, #2
  ADD R5, #BIG
  CALL emittile
bt_adv:
  ADD R0, #16
  INC A1
  BRA bt_lp
bt_done:
  RET

; ---- strlen(A1) -> R0 ----
strlen:
  MOVA A0, A1
  MOV R0, #0
sl_lp:
  LDB R2, [A0]
  CMP R2, #0
  BEQ sl_done
  ADD R0, #1
  INC A0
  BRA sl_lp
sl_done:
  RET

; ---- ctext(R1=y, A1) / cbig(R1=y, A1): centred sprite text ----
ctext:
  CALL strlen
  SHL R0, #2
  NEG R0
  ADD R0, #160
  CALL stext
  RET
cbig:
  CALL strlen
  SHL R0, #3
  NEG R0
  ADD R0, #160
  CALL btext
  RET

; ---- drawspark: the last hit / block spark ----
drawspark:
  LDW R0, [sparkT]
  CMP R0, #0
  BEQ dsp_ret
  SUB R0, #1
  STW R0, [sparkT]
  MOV R5, #SPARK
  LDW R1, [sparkK]
  CMP R1, #0
  BEQ dsp_k
  MOV R5, #BSPARK
dsp_k:
  AND R0, #4
  BEQ dsp_f
  ADD R5, #4
dsp_f:
  LDW R0, [sparkX]
  LDW R1, [cam]
  SUB R0, R1
  SUB R0, #8
  LDW R1, [sparkY]
  SUB R1, #8
  MOV R6, #SZ16
  OR R6, #PB_SPARK
  MOV R2, #7
  STW R2, [sprpri]
  CALL emittile
dsp_ret:
  RET

; ---- drawbolts: Seal Bolts in flight, then dizzy stars ----
drawbolts:
  MOV R0, #6
  STW R0, [sprpri]
  LDA A2, #F1
  CALL emitbolt
  LDA A2, #F2
  CALL emitbolt
  LDA A2, #F1
  CALL emitstars
  LDA A2, #F2
  CALL emitstars
  RET
emitbolt:
  LDW R0, [A2+#FPJT]
  CMP R0, #0
  BEQ eb_ret
  MOV R5, #BOLT
  AND R0, #4
  BEQ eb_f
  ADD R5, #4
eb_f:
  MOV R6, #SZ16
  OR R6, #PB_SPARK
  LDW R0, [A2+#FPJV]
  CMP R0, #0
  BGE eb_r
  OR R6, #$40
eb_r:
  LDW R0, [A2+#FPJX]
  LDW R1, [cam]
  SUB R0, R1
  SUB R0, #8
  MOV R1, #GROUNDY-BOLTY-8
  CALL emittile
eb_ret:
  RET
emitstars:
  LDW R0, [A2+#FST]
  CMP R0, #ST_DIZZY
  BNE est_ret
  MOV R5, #STARS
  LDW R0, [A2+#FT]
  AND R0, #8
  BEQ est_f
  ADD R5, #4
est_f:
  MOV R6, #SZ16
  OR R6, #PB_SPARK
  LDW R0, [A2+#FX]
  LDW R1, [cam]
  SUB R0, R1
  SUB R0, #8
  MOV R1, #SPRY-2
  CALL emittile
est_ret:
  RET

; ---- drawcombo: "n HITS" on each side, and "TECH" ----
drawcombo:
  MOV R4, #0
  CALL combo1
  MOV R4, #1
  CALL combo1
  LDW R0, [techT]
  CMP R0, #0
  BEQ dc_ret
  SUB R0, #1
  STW R0, [techT]
  MOV R1, #60
  LDA A1, #sTECH
  CALL cbig
dc_ret:
  RET
combo1:
  MOV R3, R4
  SHL R3, #1
  LDA A0, #cmbT
  ADD A0, R3
  LDW R1, [A0]
  CMP R1, #0
  BEQ c1_ret
  SUB R1, #1
  STW R1, [A0]
  LDA A0, #cmbN
  ADD A0, R3
  LDW R0, [A0]
  LDA A1, #cmbstr
  CMP R0, #10
  BLT c1_one
  MOV R1, #0
c1_t:
  SUB R0, #10
  ADD R1, #1
  CMP R0, #10
  BGE c1_t
  ADD R1, #48
  STB R1, [A1]
  INC A1
c1_one:
  ADD R0, #48
  STB R0, [A1]
  INC A1
  LDA A0, #sHITS
c1_cp:
  LDB R0, [A0]
  STB R0, [A1]
  INC A0
  INC A1
  CMP R0, #0
  BNE c1_cp
  LDA A1, #cmbstr
  MOV R0, #8
  CMP R4, #0
  BEQ c1_x
  CALL strlen
  SHL R0, #4
  NEG R0
  ADD R0, #312
c1_x:
  MOV R1, #52
  LDA A1, #cmbstr
  CALL btext
c1_ret:
  RET

; ---- drawfighters: the attacker first (lower OAM index = on top), then shadows ----
drawfighters:
  MOV R0, #4
  STW R0, [sprpri]
  LDA A2, #F2
  LDW R0, [A2+#FST]
  CMP R0, #ST_ATK
  BNE df_12
  LDA A2, #F1
  LDW R0, [A2+#FST]
  CMP R0, #ST_ATK
  BEQ df_12
  LDA A2, #F2              ; F2 attacking: F2 on top
  CALL emitfighter
  LDA A2, #F1
  CALL emitfighter
  BRA df_sh
df_12:
  LDA A2, #F1
  CALL emitfighter
  LDA A2, #F2
  CALL emitfighter
df_sh:
  MOV R0, #3
  STW R0, [sprpri]
  LDA A2, #F1
  CALL emitshadow
  LDA A2, #F2
  CALL emitshadow
  RET

; ---- visible(A2) -> Z clear if this fighter is shown ----
visible:
  LDW R0, [show]
  LDW R1, [A2+#FID]
  CMP R1, #0
  BEQ vi_p1
  SHR R0, #1
vi_p1:
  AND R0, #1
  RET

emitfighter:
  CALL visible
  BEQ ef_ret
  LDW R0, [A2+#FX]
  LDW R1, [cam]
  SUB R0, R1
  SUB R0, #32
  LDW R1, [A2+#FY]
  SAR R1, #8
  ADD R1, #SPRY
  LDW R5, [A2+#FSLOT]
  LDW R6, [A2+#FBANK]
  LDW R2, [A2+#FFLASH]
  AND R2, #2
  BEQ ef_bank
  MOV R6, #PB_FLASH
ef_bank:
  OR R6, #SZ64
  LDW R2, [A2+#FFACE]
  CMP R2, #0
  BEQ ef_emit
  OR R6, #$40
ef_emit:
  CALL emittile
ef_ret:
  RET

emitshadow:
  CALL visible
  BEQ es_ret
  LDW R0, [A2+#FX]
  LDW R1, [cam]
  SUB R0, R1
  SUB R0, #16
  MOV R1, #GROUNDY-28
  MOV R5, #SHADOW
  MOV R6, #SZ32
  OR R6, #PB_SHADOW
  CALL emittile
es_ret:
  RET

; ---- streamframes: DMA each fighter's current pose into its VRAM slot ----
streamframes:
  LDA A2, #F1
  CALL streamone
  LDA A2, #F2
  CALL streamone
  RET
streamone:
  LDW R0, [A2+#FBODY]
  MOV R1, R0
  SHL R1, #1
  ADD R1, R0
  LDA A0, #BODYTAB
  ADD A0, R1
  LDADDR A0, [A0]
  LDW R0, [A2+#FPOSE]      ; + pose * 2048, in two halves (ADD An takes a signed word)
  SHL R0, #10
  ADD A0, R0
  ADD A0, R0
  LDW R0, [A2+#FSLOT]
  SHL R0, #5
  STW R0, [DMA_DST]
  MOV R0, #2048
  STW R0, [DMA_LEN]
  MOV R0, #0
  STB R0, [DMA_MODE]
  CALL dmago
  RET

; ============================ HUD ============================
; ---- hudstatic: names (row 0) for a new round ----
hudstatic:
  CALL clearhud
  LDA A2, #F1
  MOV R4, #1
  CALL hudname
  LDA A2, #F2
  MOV R4, #34
  CALL hudname
  RET
hudname:
  LDW R0, [A2+#FBODY]
  MOV R1, R0
  SHL R1, #1
  ADD R1, R0
  LDA A0, #NAMETAB
  ADD A0, R1
  LDADDR A1, [A0]
  MOV R5, #0
  CALL print
  RET

; ---- drawhud: bars, meters, seals, pips, clock (BG1 rows 0-2) ----
drawhud:
  LDA A2, #F1
  LDW R4, [A2+#FHP]
  MOV R5, #0               ; cell index
dh_hp1:
  MOV R0, #15              ; bars drain from the outer edge: P1 cell k = 15 - i
  SUB R0, R5
  CALL hpcell
  CMP R2, #HP_HALF
  BNE dh_h1
  MOV R2, #HP_HALFR
dh_h1:
  MOV R0, R5
  ADD R0, #1
  MOV R1, #1
  MOV R3, #PB_HUD
  CALL hudtile
  ADD R5, #1
  CMP R5, #16
  BLT dh_hp1
  LDA A2, #F2
  LDW R4, [A2+#FHP]
  MOV R5, #0
dh_hp2:
  MOV R0, R5
  CALL hpcell
  MOV R0, R5
  ADD R0, #23
  MOV R1, #1
  MOV R3, #PB_HUD
  CALL hudtile
  ADD R5, #1
  CMP R5, #16
  BLT dh_hp2
  LDA A2, #F1
  LDW R4, [A2+#FMTR]
  MOV R5, #0
dh_m1:
  MOV R0, R5
  CALL mtcell
  MOV R0, R5
  ADD R0, #2
  MOV R1, #2
  MOV R3, #PB_HUD
  CALL hudtile
  ADD R5, #1
  CMP R5, #16
  BLT dh_m1
  LDA A2, #F2
  LDW R4, [A2+#FMTR]
  MOV R5, #0
dh_m2:
  MOV R0, R5
  CALL mtcell
  MOV R0, #37
  SUB R0, R5
  MOV R1, #2
  MOV R3, #PB_HUD
  CALL hudtile
  ADD R5, #1
  CMP R5, #16
  BLT dh_m2
  LDA A2, #F1
  CALL sealtile
  MOV R0, #1
  MOV R1, #2
  MOV R3, #PB_HUD
  CALL hudtile
  LDA A2, #F2
  CALL sealtile
  MOV R0, #38
  MOV R1, #2
  MOV R3, #PB_HUD
  CALL hudtile
  LDA A2, #F1              ; round pips
  LDW R4, [A2+#FWINS]
  MOV R5, #15
  CALL pips
  LDA A2, #F2
  LDW R4, [A2+#FWINS]
  MOV R5, #23
  CALL pips
  LDW R0, [timer]          ; the clock
  MOV R1, #0
  MOV R2, #10
  DIVU R0, R2
  PUSH R1
  MOV R2, R0
  ADD R2, #48
  MOV R0, #19
  MOV R1, #1
  MOV R3, #PB_FONT
  CALL hudtile
  POP R2
  ADD R2, #48
  MOV R0, #20
  MOV R1, #1
  MOV R3, #PB_FONT
  CALL hudtile
  RET

; ---- hpcell(R4 = hp, R0 = k: cells from the centre) -> R2 = tile ----
hpcell:
  SHL R0, #3
  MOV R1, R4
  SUB R1, R0
  MOV R2, #HP_FULL
  CMP R1, #8
  BGE hc_ret
  MOV R2, #HP_HALF
  CMP R1, #4
  BGE hc_ret
  MOV R2, #HP_EMPTY
hc_ret:
  RET

; ---- mtcell(R4 = meter, R0 = cell) -> R2 ----
mtcell:
  MOV R2, #MT_READY
  CMP R4, #MTRMAX
  BLT mc_n
  LDW R1, [tick]
  AND R1, #8
  BNE mc_ret
  MOV R2, #MT_FULL
  RET
mc_n:
  SHL R0, #1
  MOV R1, R4
  SUB R1, R0
  MOV R2, #MT_FULL
  CMP R1, #2
  BGE mc_ret
  MOV R2, #MT_EMPTY
mc_ret:
  RET

; ---- sealtile(A2) -> R2 ----
sealtile:
  MOV R2, #SEAL_NONE
  LDW R0, [gstate]
  CMP R0, #G_OATH
  BEQ stl_ret
  LDW R0, [A2+#FOATH]
  CMP R0, #0
  BEQ stl_ret
  MOV R2, #SEAL_OK
  LDW R0, [A2+#FOBRK]
  CMP R0, #0
  BEQ stl_ret
  MOV R2, #SEAL_BROKE
stl_ret:
  RET

; ---- pips(R4 = wins, R5 = column): two round-win pips on row 0 ----
pips:
  MOV R2, #PIP_OFF
  CMP R4, #1
  BLT pp_a
  MOV R2, #PIP_ON
pp_a:
  MOV R0, R5
  MOV R1, #0
  MOV R3, #PB_HUD
  CALL hudtile
  MOV R2, #PIP_OFF
  CMP R4, #2
  BLT pp_b
  MOV R2, #PIP_ON
pp_b:
  MOV R0, R5
  ADD R0, #1
  MOV R1, #0
  MOV R3, #PB_HUD
  CALL hudtile
  RET

; ---- hudtile(R0=col, R1=row, R2=tile, R3=pal): one BG1 map cell; clobbers R6, R7 ----
hudtile:
  MOV R6, R0
  SHL R6, #2
  STB R6, [VRAM_ADDR]
  MOV R6, R1
  ADD R6, #$40
  STB R6, [VRAM_ADDR+1]
  MOV R7, #1
  STB R7, [VRAM_ADDR+2]
  STB R2, [VRAM_DATA]
  MOV R7, R2
  SHR R7, #8
  AND R7, #7
  MOV R6, R3
  SHL R6, #3
  OR R7, R6
  STB R7, [VRAM_DATA]
  MOV R7, #0
  STB R7, [VRAM_DATA]
  STB R7, [VRAM_DATA]
  RET

; ---- clearhud: blank BG1 rows 0-2 ----
clearhud:
  MOV R5, #0
  MOV R6, #3
  CALL clearrows
  RET

; ============================ BG helpers ============================
copymaps:
  MOV R0, #0
  STB R0, [VRAM_ADDR]
  STB R0, [VRAM_ADDR+1]
  MOV R0, #1
  STB R0, [VRAM_ADDR+2]
  LDA A0, #mapdata
  CALL cpmap
  MOV R0, #0
  STB R0, [VRAM_ADDR]
  MOV R0, #$40
  STB R0, [VRAM_ADDR+1]
  MOV R0, #1
  STB R0, [VRAM_ADDR+2]
  CALL cpmap
  RET
cpmap:
  MOV R1, #7168
cpm_lp:
  LDB R2, [A0]
  STB R2, [VRAM_DATA]
  INC A0
  SUB R1, #1
  BNE cpm_lp
  RET

; ---- settile(R0=x, R1=y, R2=tile, R3=palette): one BG1 map cell ----
settile:
  MOV R6, R1
  SHL R6, #8
  MOV R7, R0
  SHL R7, #2
  ADD R6, R7
  STB R6, [VRAM_ADDR]
  MOV R7, R6
  SHR R7, #8
  ADD R7, #$40
  STB R7, [VRAM_ADDR+1]
  MOV R7, #1
  STB R7, [VRAM_ADDR+2]
  STB R2, [VRAM_DATA]
  MOV R7, R2
  SHR R7, #8
  AND R7, #7
  MOV R6, R3
  SHL R6, #3
  OR R7, R6
  STB R7, [VRAM_DATA]
  MOV R7, #0
  STB R7, [VRAM_DATA]
  STB R7, [VRAM_DATA]
  RET

; ---- clearrows(R5=first, R6=end exclusive): blank BG1 cols 0-39 ----
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

; ---- panel(R4=col0, R5=row0, R6=col1, R7=row1; screen cells, end exclusive): dark plaque ----
panel:
  STW R6, [svrem]
  STW R7, [tmpx]
pn_y:
  MOV R3, R4
pn_x:
  PUSH R3
  LDW R0, [cam]
  SHR R0, #3
  ADD R0, R3
  AND R0, #63
  MOV R1, R5
  MOV R2, #PANEL
  MOV R3, #PB_STONE
  CALL settile
  POP R3
  ADD R3, #1
  LDW R6, [svrem]
  CMP R3, R6
  BLT pn_x
  ADD R5, #1
  LDW R7, [tmpx]
  CMP R5, R7
  BLT pn_y
  RET

; ---- print(R4=col, R5=row, A1=string): BG1 text in the font bank ----
print:
  LDB R2, [A1]
  CMP R2, #0
  BEQ pr_done
  CMP R2, #32
  BEQ pr_adv
  MOV R0, R4
  MOV R1, R5
  MOV R3, #PB_FONT
  CALL settile
pr_adv:
  ADD R4, #1
  INC A1
  BRA print
pr_done:
  RET

; ============================ palette / DMA ============================
; ---- homestage(R0 = body): that character's stage ----
homestage:
  LDA A0, #CHSTAGE
  ADD A0, R0
  LDB R0, [A0]
; ---- setstage(R0): sky gradient -> SKYTAB, sky bank 1 ----
setstage:
  MOV R1, #STAGEREC
  MULU R0, R1
  LDA A0, #stages
  ADD A0, R0
  LDA A1, #SKYTAB
  MOV R1, #224
ss_sky:
  LDW R2, [A0]
  STW R2, [A1]
  ADD A0, #2
  ADD A1, #2
  SUB R1, #1
  BNE ss_sky
  MOV R0, #34
  MOV R1, #24
  CALL dmapal
  ADD A0, #24              ; the courtyard, lit for the time of day: bank 2, banks 6-7, banks 10-11
  MOV R0, #64
  MOV R1, #32
  CALL dmapal
  ADD A0, #32
  MOV R0, #192
  MOV R1, #64
  CALL dmapal
  ADD A0, #64
  MOV R0, #320
  MOV R1, #64
  CALL dmapal
  RET

dmapal:
  STW R0, [DMA_DST]
  STW R1, [DMA_LEN]
  MOV R0, #2
  STB R0, [DMA_MODE]
dmago:
  PUSHA A0
  POP R0
  POP R1
  STW R0, [DMA_SRC]
  STB R1, [DMA_SRC+2]
  MOV R0, #1
  STB R0, [DMA_CTRL]
  RET

loadart:
  LDA A0, #tiledata
  MOV R0, #0
  STW R0, [DMA_DST]
  MOV R0, #tiledataend-tiledata
  STW R0, [DMA_LEN]
  MOV R0, #0
  STB R0, [DMA_MODE]
  CALL dmago
  LDA A0, #paldata
  MOV R0, #0
  MOV R1, #512
  CALL dmapal
  MOV R0, #0
  CALL setstage
  RET

; ============================ save ============================
loadsave:
  LDA A1, #picks
  LDA A0, #PICKDEF
  LDW R0, [SV_MAG]
  MOV R1, #SVMAGIC
  CMP R0, R1
  BNE ls_def
  LDA A0, #SV_P1
  LDW R0, [SV_BEST]
  STW R0, [best]
  BRA ls_go
ls_def:
  MOV R0, #0
  STW R0, [best]
ls_go:
  LDA A2, #CHCOUNT
  MOV R4, #12
ls_lp:
  LDB R0, [A0]
  LDB R1, [A2]
  CMP R0, R1
  BLT ls_ok
  MOV R0, #0
ls_ok:
  STB R0, [A1]
  INC A0
  INC A1
  INC A2
  SUB R4, #1
  CMP R4, #6
  BNE ls_nw
  LDA A2, #CHCOUNT         ; P2's picks: same limits
ls_nw:
  CMP R4, #0
  BNE ls_lp
  RET

savepicks:
  LDA A0, #picks
  LDA A1, #SV_P1
  MOV R2, #12
sp_lp:
  LDB R0, [A0]
  STB R0, [A1]
  INC A0
  INC A1
  SUB R2, #1
  BNE sp_lp
  LDW R0, [best]
  STW R0, [SV_BEST]
  MOV R1, #SVMAGIC
  STW R1, [SV_MAG]
  MOV R1, #1
  STB R1, [SAVECOMMIT]
  RET

; ============================ audio ============================
; ---- sfxplay(R0 = sound): a per-frame pitch/volume sequence on square 0 ----
sfxplay:
  LDA A0, #SFXTAB
  SHL R0, #1
  ADD A0, R0
  LDW R0, [A0]
  STW R0, [sfxP]
  MOV R0, #0
  STW R0, [sfxT]
  RET

sfxblip:
  PUSH R0
  MOV R0, #0
  STW R0, [sfxP]
  POP R0
  STW R0, [SQ0_PERIOD]
  MOV R0, #10
  STB R0, [SQ0_VOL]
  MOV R0, #1
  STB R0, [SQ0_CTRL]
  MOV R0, #6
  STW R0, [sfxT]
  RET

noisehit:
  STW R0, [NOISE_PER]
  MOV R0, #12
  STB R0, [NOISE_VOL]
  MOV R0, #1
  STB R0, [NOISE_CTRL]
  MOV R0, #7
  STW R0, [noiseT]
  RET

sfxtick:
  LDW R0, [sfxP]
  CMP R0, #0
  BEQ sx_b
  LDA A0, #SFXDATA
  ADD A0, R0
  LDW R1, [A0]
  CMP R1, #0
  BNE sx_on
  STW R1, [sfxP]
  STB R1, [SQ0_CTRL]
  BRA sx_n
sx_on:
  STW R1, [SQ0_PERIOD]
  LDW R1, [A0+#2]
  STB R1, [SQ0_VOL]
  MOV R1, #1
  STB R1, [SQ0_CTRL]
  ADD R0, #4
  STW R0, [sfxP]
  BRA sx_n
sx_b:
  LDW R0, [sfxT]
  CMP R0, #0
  BEQ sx_n
  SUB R0, #1
  STW R0, [sfxT]
  CMP R0, #0
  BNE sx_n
  STB R0, [SQ0_CTRL]
sx_n:
  LDW R0, [noiseT]
  CMP R0, #0
  BEQ sx_done
  SUB R0, #1
  STW R0, [noiseT]
  CMP R0, #0
  BNE sx_done
  STB R0, [NOISE_CTRL]
sx_done:
  RET

musictick:
  LDW R0, [mT]
  CMP R0, #0
  BEQ mt_next
  SUB R0, #1
  STW R0, [mT]
  RET
mt_next:
  LDW R0, [mIdx]
  LDA A0, #song
  MOV R1, R0
  SHL R1, #1
  ADD A0, R1
  LDW R2, [A0]
  MOV R1, #$FFFF
  CMP R2, R1
  BNE mt_play
  MOV R0, #0
  STW R0, [mIdx]
  LDA A0, #song
  LDW R2, [A0]
mt_play:
  CMP R2, #0
  BEQ mt_rest
  STW R2, [SQ1_PERIOD]
  MOV R0, #4
  STB R0, [SQ1_VOL]
  MOV R0, #1
  STB R0, [SQ1_CTRL]
  BRA mt_adv
mt_rest:
  MOV R0, #0
  STB R0, [SQ1_CTRL]
mt_adv:
  MOV R0, #8
  STW R0, [mT]
  LDW R0, [mIdx]
  ADD R0, #1
  STW R0, [mIdx]
  RET

; ============================ data ============================
; ---- attack table: 32 bytes per attack (AT_* fields, then AT_FL2 and padding) ----
ATKTAB:
  ;  S  A   R  dmg hs  bs  x0  x1  y0  y1 kind flags                    p0         p1          dash p2
  DB 3, 2,  6,  6, 12,  9,  8, 40, 30, 50, 0, AF_GROUND,               PO_GUARD,  PO_PUNCH,   0, PO_PUNCH     ; 0 LP
  DB F2_CHAIN+F2_CXL, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
  DB 5, 3, 10,  9, 15, 11,  8, 48, 16, 40, 0, AF_GROUND+AF_KICK,       PO_GUARD,  PO_KICK,    0, PO_KICK      ; 1 LK
  DB F2_CXL, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
  DB 3, 2,  7,  5, 12,  9,  8, 38, 18, 34, 0, AF_GROUND,               PO_CROUCH, PO_CPUNCH,  0, PO_CPUNCH    ; 2 c.LP
  DB F2_CHAIN+F2_CXL, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
  DB 7, 4, 20, 12, 16, 13,  8, 54,  0, 14, 1, AF_GROUND+AF_KICK+AF_KD, PO_CROUCH, PO_LOWKICK, 0, PO_LOWKICK   ; 3 sweep (c.HK)
  DB 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
  DB 3, 6,  0,  7, 14, 10,  4, 36, 10, 40, 2, AF_AIR,                  PO_JUMP,   PO_AIRPUNCH, 0, PO_JUMP     ; 4 j.LP
  DB 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
  DB 4, 6,  0,  9, 16, 11,  4, 44,  0, 30, 2, AF_AIR+AF_KICK,          PO_JUMP,   PO_AIRKICK, 0, PO_JUMP      ; 5 j.LK
  DB 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
  DB 8, 14, 16, 14, 22, 14, 4, 40, 20, 48, 0, AF_GROUND+AF_KD,         PO_CROUCH, PO_HPUNCH,  5, PO_GUARD     ; 6 Gate Rush
  DB F2_SPEC, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
  DB 3, 10, 22, 16, 24, 14, 0, 30, 30, 80, 0, AF_GROUND+AF_KD+AF_INV+AF_RISE, PO_CROUCH, PO_RISE, 0, PO_JUMP  ; 7 Palm Rise
  DB F2_SPEC, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
  DB 10, 30, 20, 9, 12, 10, 4, 44, 10, 50, 0, AF_GROUND+AF_KICK+AF_MULTI, PO_CROUCH, PO_PUNCH, 3, PO_GUARD  ; 8 Oath Surge
  DB F2_SPEC, PO_KICK, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
  DB 6, 3, 16, 13, 18, 14,  8, 52, 28, 52, 0, AF_GROUND,               PO_GUARD,  PO_HPUNCH,  0, PO_HPUNCH    ; 9 HP
  DB F2_CXL, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
  DB 8, 4, 18, 15, 20, 15,  8, 56, 24, 54, 0, AF_GROUND+AF_KICK,       PO_GUARD,  PO_HKICK,   0, PO_HKICK     ; 10 HK
  DB 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
  DB 5, 4, 16, 12, 18, 14,  0, 32, 24, 72, 0, AF_GROUND,               PO_CROUCH, PO_RISE,    0, PO_CROUCH    ; 11 c.HP uppercut
  DB F2_CXL, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
  DB 4, 3,  8,  5, 12,  9,  8, 46,  0, 14, 1, AF_GROUND+AF_KICK,       PO_CROUCH, PO_LOWKICK, 0, PO_CROUCH    ; 12 c.LK
  DB F2_CHAIN+F2_CXL, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
  DB 4, 6,  0, 11, 17, 12,  4, 40, 10, 44, 2, AF_AIR,                  PO_JUMP,   PO_AIRPUNCH, 0, PO_JUMP     ; 13 j.HP
  DB 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
  DB 5, 6,  0, 13, 19, 13,  4, 48,  0, 32, 2, AF_AIR+AF_KICK,          PO_JUMP,   PO_AIRKICK, 0, PO_JUMP      ; 14 j.HK
  DB 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
  DB 10, 1, 26, 10, 16, 12, 0,  0,  0,  0, 0, AF_GROUND,               PO_GUARD,  PO_FIRE,    3, PO_FIRE      ; 15 Seal Bolt (A)
  DB F2_SPEC+F2_PROJ, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
  DB 10, 1, 26, 10, 16, 12, 0,  0,  0,  0, 0, AF_GROUND,               PO_GUARD,  PO_FIRE,    5, PO_FIRE      ; 16 Seal Bolt (X)
  DB F2_SPEC+F2_PROJ, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
  DB 3, 2, 22, 16,  0,  0,  0, THROWR, 10, 50, 0, AF_GROUND+AF_KD,     PO_GRAB,   PO_GRAB,    0, PO_GUARD     ; 17 throw (x1 = range)
  DB F2_THROW, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
  DB 3, 2, 22, 16,  0,  0,  0, THROWR, 10, 50, 0, AF_GROUND+AF_KD,     PO_GRAB,   PO_GRAB,    0, PO_GUARD     ; 18 back throw
  DB F2_THROW+F2_BACK, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
  DB 8, 1, 22,  7, 14, 10,  0,  0,  0,  0, 0, AF_GROUND,               PO_GUARD,  PO_FIRE,    6, PO_FIRE      ; 19 Needle Bolt (A)
  DB F2_SPEC+F2_PROJ, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
  DB 8, 1, 22,  7, 14, 10,  0,  0,  0,  0, 0, AF_GROUND,               PO_GUARD,  PO_FIRE,    8, PO_FIRE      ; 20 Needle Bolt (X)
  DB F2_SPEC+F2_PROJ, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
  DB 13, 1, 28, 14, 20, 14, 0,  0,  0,  0, 0, AF_GROUND,               PO_GUARD,  PO_FIRE,    2, PO_FIRE      ; 21 Ember Bolt (A)
  DB F2_SPEC+F2_PROJ, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
  DB 13, 1, 28, 14, 20, 14, 0,  0,  0,  0, 0, AF_GROUND,               PO_GUARD,  PO_FIRE,    3, PO_FIRE      ; 22 Ember Bolt (X)
  DB F2_SPEC+F2_PROJ, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
  DB 12, 16, 18, 18, 22, 16, 4, 44, 16, 50, 0, AF_GROUND+AF_KD,         PO_CROUCH, PO_HPUNCH,  4, PO_GUARD     ; 23 Ram Charge
  DB F2_SPEC, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
  DB 4, 10, 22, 15, 24, 14, 0, 32, 24, 78, 0, AF_GROUND+AF_KD+AF_INV+AF_RISE+AF_KICK, PO_CROUCH, PO_HKICK, 0, PO_JUMP  ; 24 Lark Rise
  DB F2_SPEC, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
  DB 7, 24, 16,  6, 14, 10,  0, 44, 20, 48, 0, AF_GROUND+AF_KICK+AF_MULTI, PO_GUARD, PO_HKICK,  4, PO_GUARD     ; 25 Gale Wheel
  DB F2_SPEC, PO_KICK, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
  DB 5, 2, 30, 24,  0,  0,  0, 52, 10, 50, 0, AF_GROUND+AF_KD,         PO_GRAB,   PO_GRAB,    0, PO_GUARD     ; 26 Gate Crusher (command grab, range 52)
  DB F2_THROW, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
  DB 14, 4, 18, 18, 22, 16, 4, 44,  0, 44, 2, AF_GROUND+AF_KD,         PO_RISE,   PO_HPUNCH,  0, PO_CROUCH    ; 27 Bell Smash (overhead)
  DB F2_SPEC, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0

; any request made in the air becomes an air attack (index = requested attack)
AIRMAP:
  DB AK_APUNCH, AK_AKICK, AK_APUNCH, AK_AHKICK, AK_APUNCH, AK_AKICK, AK_AHPUNCH, AK_AHPUNCH, AK_AHKICK
  DB AK_AHPUNCH, AK_AHKICK, AK_AHPUNCH, AK_AKICK, AK_AHPUNCH, AK_AHKICK, AK_APUNCH, AK_AHPUNCH, AK_AHPUNCH, AK_AHPUNCH
  DB AK_APUNCH, AK_AHPUNCH, AK_APUNCH, AK_AHPUNCH, AK_AHPUNCH, AK_AHKICK, AK_AHKICK, AK_AHPUNCH, AK_AHPUNCH

; motion patterns, newest first (1 D, 2 DF, 3 F, 4 B, 5 DB)
MO_QCF:
  DB 3, 2, 1
MO_DP:
  DB 2, 1, 3
MO_QCB:
  DB 4, 5, 1

WALKP:
  DB PO_WALK1, PO_GUARD, PO_WALK2, PO_GUARD

; ---- builds: speed (8.8 word), damage bonus, armour, reach, pad ----
BUILDTAB:
  DB $C0, $01, 0, 0, 0, 0, 0, 0       ; 0 slim
  DB $80, $01, 1, 0, 2, 0, 0, 0       ; 1 athletic
  DB $40, $01, 2, 1, 2, 0, 0, 0       ; 2 stocky
  DB $00, $01, 3, 2, 4, 0, 0, 0       ; 3 heavy
BODYBUILD:                             ; RIO MARA TANK KENJI ZED FOX LIN WOLF
  DB 1, 0, 3, 1, 0, 1, 0, 2

; ---- rivals: picks (body, skin, hair, top, legs, shoes), AI level, oath (0 = random) ----
; ---- sound sequences: DW period, volume per frame; period 0 ends ----
SFXDATA:
  DW 0, 0
sx_rise:
  DW 160, 13, 148, 12, 136, 12, 123, 11, 111, 11, 99, 10
  DW 87, 10, 74, 9, 62, 9, 50, 8
  DW 0, 0
sx_bolt:
  DW 90, 13, 90, 13, 90, 12, 80, 12, 70, 11, 80, 10
  DW 70, 9, 80, 8, 70, 7, 80, 6, 70, 5, 80, 4
  DW 70, 3, 80, 3
  DW 0, 0
sx_rush:
  DW 220, 12, 200, 12, 240, 11, 210, 11, 250, 10, 220, 10
  DW 260, 9, 230, 9, 270, 8, 240, 8, 280, 7, 250, 7
  DW 0, 0
sx_smash:
  DW 60, 14, 82, 13, 104, 13, 127, 12, 149, 11, 171, 11
  DW 193, 10, 216, 9, 238, 9, 260, 8
  DW 0, 0
sx_super:
  DW 120, 13, 120, 13, 95, 13, 95, 13, 80, 13, 80, 13
  DW 60, 13, 60, 13, 120, 13, 120, 13, 95, 13, 95, 13
  DW 80, 13, 80, 13, 60, 13, 60, 13, 120, 13, 120, 13
  DW 95, 13, 95, 13, 80, 13, 80, 13, 60, 13, 60, 13
  DW 0, 0
sx_ko:
  DW 70, 14, 72, 14, 75, 14, 79, 13, 83, 13, 88, 13
  DW 94, 13, 100, 13, 107, 12, 114, 12, 122, 12, 130, 12
  DW 138, 11, 147, 11, 156, 11, 166, 11, 175, 11, 185, 10
  DW 196, 10, 206, 10, 217, 10, 228, 10, 240, 9, 251, 9
  DW 263, 9, 276, 9, 288, 8, 301, 8, 314, 8, 327, 8
  DW 340, 8, 354, 7, 368, 7, 382, 7, 396, 7, 411, 7
  DW 425, 6, 440, 6, 455, 6, 471, 6, 486, 5, 502, 5
  DW 518, 5, 534, 5, 550, 5, 567, 4, 583, 4, 600, 4
  DW 0, 0
sx_block:
  DW 40, 12, 40, 10, 45, 6
  DW 0, 0
sx_throw:
  DW 100, 12, 140, 11, 180, 10, 220, 9, 260, 8
  DW 0, 0
SFXTAB:
  DW 0, sx_rise-SFXDATA, sx_bolt-SFXDATA, sx_rush-SFXDATA, sx_smash-SFXDATA, sx_super-SFXDATA, sx_ko-SFXDATA, sx_block-SFXDATA, sx_throw-SFXDATA
ATKSFX:                    ; sound per attack row (0 = the plain swish)
  DB 0, 0, 0, 0, 0, 0, SX_RUSH, SX_RISE, SX_SUPER, 0, 0, 0, 0, 0, 0, SX_BOLT, SX_BOLT, SX_THROW, SX_THROW, SX_BOLT, SX_BOLT, SX_BOLT, SX_BOLT, SX_RUSH, SX_RISE, SX_RUSH, SX_THROW, SX_SMASH
ENDTAB:                    ; arcade endings by character (lines split by 10)
  DA sEND0, sEND1, sEND2, sEND3, sEND4, sEND5, sEND6, sEND7
sEND0:
  DB 'R', 'I', 'O', 32, 'L', 'E', 'F', 'T', 32, 'T', 'H', 'E', 32, 'P', 'A', 'L', 'M', 'G', 'A', 'T', 'E', 32, 'A', 'T', 32, 'D', 'A', 'W', 'N', 46, 10
  DB 'H', 'E', 32, 'D', 'I', 'D', 32, 'N', 'O', 'T', 32, 'S', 'T', 'A', 'Y', 32, 'T', 'O', 32, 'R', 'U', 'L', 'E', 32, 'I', 'T', 46, 10
  DB 'T', 'H', 'E', 32, 'R', 'O', 'A', 'D', 32, 'W', 'A', 'S', 32, 'A', 'L', 'L', 32, 'H', 'E', 32, 'E', 'V', 'E', 'R', 10
  DB 'W', 'A', 'N', 'T', 'E', 'D', 46, 32, 'I', 'T', 32, 'S', 'T', 'I', 'L', 'L', 32, 'I', 'S', 46, 0
sEND1:
  DB 'M', 'A', 'R', 'A', 32, 'R', 'A', 'N', 32, 'T', 'H', 'E', 32, 'W', 'A', 'L', 'L', 'S', 32, 'A', 'T', 32, 'N', 'O', 'O', 'N', 10
  DB 'A', 'N', 'D', 32, 'R', 'A', 'N', 'G', 32, 'T', 'H', 'E', 32, 'G', 'A', 'T', 'E', 32, 'B', 'E', 'L', 'L', 32, 'T', 'W', 'I', 'C', 'E', 46, 10
  DB 'N', 'O', 'B', 'O', 'D', 'Y', 32, 'S', 'A', 'W', 32, 'H', 'E', 'R', 32, 'D', 'O', 32, 'I', 'T', 46, 10
  DB 'E', 'V', 'E', 'R', 'Y', 'B', 'O', 'D', 'Y', 32, 'H', 'E', 'A', 'R', 'D', 32, 'I', 'T', 46, 0
sEND2:
  DB 'T', 'A', 'N', 'K', 32, 'S', 'T', 'O', 'O', 'D', 32, 'A', 'T', 32, 'T', 'H', 'E', 32, 'G', 'A', 'T', 'E', 32, 'U', 'N', 'T', 'I', 'L', 10
  DB 'T', 'H', 'E', 32, 'L', 'A', 'S', 'T', 32, 'R', 'I', 'V', 'A', 'L', 32, 'W', 'A', 'L', 'K', 'E', 'D', 32, 'A', 'W', 'A', 'Y', 46, 10
  DB 'H', 'E', 32, 'I', 'S', 32, 'S', 'T', 'I', 'L', 'L', 32, 'S', 'T', 'A', 'N', 'D', 'I', 'N', 'G', 32, 'T', 'H', 'E', 'R', 'E', 46, 10
  DB 'T', 'H', 'E', 32, 'G', 'A', 'T', 'E', 32, 'H', 'A', 'S', 32, 'N', 'E', 'V', 'E', 'R', 32, 'B', 'E', 'E', 'N', 32, 'S', 'A', 'F', 'E', 'R', 46, 0
sEND3:
  DB 'K', 'E', 'N', 'J', 'I', 32, 'L', 'I', 'T', 32, 'A', 32, 'L', 'A', 'M', 'P', 32, 'O', 'N', 32, 'T', 'H', 'E', 32, 'W', 'A', 'L', 'L', 10
  DB 'F', 'O', 'R', 32, 'E', 'V', 'E', 'R', 'Y', 32, 'O', 'A', 'T', 'H', 32, 'H', 'E', 32, 'K', 'E', 'P', 'T', 46, 10
  DB 'N', 'O', 'W', 32, 'A', 'T', 32, 'S', 'U', 'N', 'S', 'E', 'T', 32, 'T', 'H', 'E', 32, 'W', 'H', 'O', 'L', 'E', 10
  DB 'P', 'A', 'L', 'M', 'G', 'A', 'T', 'E', 32, 'G', 'L', 'O', 'W', 'S', 46, 0
sEND4:
  DB 'A', 'T', 32, 'M', 'I', 'D', 'N', 'I', 'G', 'H', 'T', 32, 'T', 'H', 'E', 32, 'G', 'A', 'T', 'E', 32, 'K', 'E', 'Y', 'S', 10
  DB 'W', 'E', 'N', 'T', 32, 'M', 'I', 'S', 'S', 'I', 'N', 'G', 46, 32, 'S', 'O', 32, 'D', 'I', 'D', 32, 'Z', 'E', 'D', 46, 10
  DB 'B', 'Y', 32, 'M', 'O', 'R', 'N', 'I', 'N', 'G', 32, 'B', 'O', 'T', 'H', 32, 'W', 'E', 'R', 'E', 32, 'B', 'A', 'C', 'K', 46, 10
  DB 'N', 'O', 'B', 'O', 'D', 'Y', 32, 'A', 'S', 'K', 'E', 'D', 46, 0
sEND5:
  DB 'F', 'O', 'X', 32, 'T', 'H', 'R', 'E', 'W', 32, 'A', 32, 'F', 'E', 'A', 'S', 'T', 32, 'I', 'N', 32, 'T', 'H', 'E', 10
  DB 'C', 'O', 'U', 'R', 'T', 'Y', 'A', 'R', 'D', 32, 'A', 'N', 'D', 32, 'I', 'N', 'V', 'I', 'T', 'E', 'D', 32, 'E', 'V', 'E', 'R', 'Y', 10
  DB 'R', 'I', 'V', 'A', 'L', 32, 'H', 'E', 32, 'H', 'A', 'D', 32, 'B', 'E', 'A', 'T', 'E', 'N', 46, 10
  DB 'T', 'H', 'E', 'Y', 32, 'A', 'L', 'L', 32, 'C', 'A', 'M', 'E', 46, 32, 'O', 'N', 'E', 32, 'L', 'I', 'M', 'P', 'E', 'D', 46, 0
sEND6:
  DB 'L', 'I', 'N', 32, 'W', 'A', 'L', 'K', 'E', 'D', 32, 'D', 'O', 'W', 'N', 32, 'T', 'O', 32, 'T', 'H', 'E', 32, 'S', 'E', 'A', 10
  DB 'A', 'N', 'D', 32, 'S', 'W', 'O', 'R', 'E', 32, 'O', 'N', 'E', 32, 'L', 'A', 'S', 'T', 32, 'O', 'A', 'T', 'H', 10
  DB 'T', 'O', 32, 'T', 'H', 'E', 32, 'T', 'I', 'D', 'E', 46, 32, 'C', 'O', 'M', 'E', 32, 'B', 'A', 'C', 'K', 46, 10
  DB 'I', 'T', 32, 'A', 'L', 'W', 'A', 'Y', 'S', 32, 'D', 'O', 'E', 'S', 46, 0
sEND7:
  DB 'W', 'O', 'L', 'F', 32, 'S', 'E', 'T', 32, 'T', 'H', 'E', 32, 'I', 'R', 'O', 'N', 32, 'S', 'E', 'A', 'L', 32, 'O', 'F', 10
  DB 'T', 'H', 'E', 32, 'P', 'A', 'L', 'M', 'G', 'A', 'T', 'E', 32, 'I', 'N', 'T', 'O', 32, 'T', 'H', 'E', 32, 'W', 'A', 'L', 'L', 46, 10
  DB 'I', 'R', 'O', 'N', 32, 'K', 'E', 'E', 'P', 'S', 32, 'I', 'T', 'S', 32, 'W', 'O', 'R', 'D', 46, 10
  DB 'S', 'O', 32, 'D', 'O', 'E', 'S', 32, 'W', 'O', 'L', 'F', 46, 0
CHSTAGE:                   ; home stage by character (HOME in the art tool)
  DB 4, 1, 0, 2, 5, 6, 7, 3
RIVTAB:
  DB 2, 3, 1, 6, 1, 3, 0, OA_FISTS
  DB 1, 1, 4, 2, 3, 1, 1, OA_STAND
  DB 3, 2, 1, 1, 7, 0, 2, OA_GUARD
  DB 7, 4, 5, 5, 8, 0, 3, 0
RANDOATH:
  DB OA_GUARD, OA_FISTS, OA_STAND, OA_FISTS
AIREACT:
  DB 28, 18, 12, 7
AIBLOCK:                               ; chance (of 16) to guard a nearby attack
  DB 3, 7, 11, 14
AICOMBO:                               ; chance (of 16) to follow up a connected normal
  DB 0, 5, 9, 13
FISTMAP:                               ; Fists Only: each attack's no-kick stand-in
  DB AK_PUNCH, AK_PUNCH, AK_CPUNCH, AK_CHPUNCH, AK_APUNCH, AK_APUNCH, AK_RUSH, AK_RISE, AK_RUSH
  DB AK_HPUNCH, AK_HPUNCH, AK_CHPUNCH, AK_CPUNCH, AK_AHPUNCH, AK_AHPUNCH, AK_BOLTL, AK_BOLTH, AK_THROW, AK_BTHROW
  DB AK_NEEDLEL, AK_NEEDLEH, AK_EMBERL, AK_EMBERH, AK_RAM, AK_CHPUNCH, AK_HPUNCH, AK_CRUSH, AK_BELL

; ---- each fighter's specials: (light, heavy) attack for QCF+P, DP+P, QCB+P, QCB+K, DP+K ($FF none) ----
CHSPEC:
  DB AK_BOLTL, AK_BOLTH, AK_RISE, AK_RISE, AK_RUSH, AK_RUSH, $FF, $FF, $FF, $FF                    ; RIO
  DB AK_NEEDLEL, AK_NEEDLEH, $FF, $FF, $FF, $FF, AK_WHEEL, AK_WHEEL, AK_LARK, AK_LARK              ; MARA
  DB AK_RAM, AK_RAM, AK_BELL, AK_BELL, AK_CRUSH, AK_CRUSH, $FF, $FF, $FF, $FF                      ; TANK
  DB AK_EMBERL, AK_EMBERH, AK_RISE, AK_RISE, $FF, $FF, AK_WHEEL, AK_WHEEL, $FF, $FF                ; KENJI
  DB AK_NEEDLEL, AK_NEEDLEH, $FF, $FF, AK_RUSH, AK_RUSH, AK_WHEEL, AK_WHEEL, $FF, $FF              ; ZED
  DB $FF, $FF, AK_RISE, AK_RISE, AK_RUSH, AK_RUSH, AK_WHEEL, AK_WHEEL, $FF, $FF                    ; FOX
  DB AK_BOLTL, AK_BOLTH, $FF, $FF, $FF, $FF, AK_WHEEL, AK_WHEEL, AK_LARK, AK_LARK                  ; LIN
  DB AK_RAM, AK_RAM, AK_RISE, AK_RISE, AK_CRUSH, AK_CRUSH, $FF, $FF, $FF, $FF                      ; WOLF
; ---- the CPU's picks per fighter: ranged, anti-air, rush, command grab, mix-up ($FF none), 8 bytes ----
CHAI:
  DB AK_BOLTH, AK_RISE, AK_RUSH, $FF, $FF, 0, 0, 0
  DB AK_NEEDLEH, AK_LARK, AK_WHEEL, $FF, $FF, 0, 0, 0
  DB $FF, $FF, AK_RAM, AK_CRUSH, AK_BELL, 0, 0, 0
  DB AK_EMBERH, AK_RISE, AK_WHEEL, $FF, $FF, 0, 0, 0
  DB AK_NEEDLEH, $FF, AK_RUSH, $FF, AK_WHEEL, 0, 0, 0
  DB $FF, AK_RISE, AK_RUSH, $FF, AK_WHEEL, 0, 0, 0
  DB AK_BOLTH, AK_LARK, AK_WHEEL, $FF, $FF, 0, 0, 0
  DB $FF, AK_RISE, AK_RAM, AK_CRUSH, $FF, 0, 0, 0

; ---- creator ----
CHCOUNT:
  DB NBODY, 6, 8, 10, 10, 8
PICKDEF:                               ; P1 defaults, then P2 defaults
  DB 0, 0, 0, 0, 0, 0
  DB 3, 2, 4, 2, 1, 0
SWTAB:
  DB 2, 3, 5, 2, 7, 3, 10, 3, 13, 2
BODYTAB:                               ; ROM address of each body's NPOSE frames (BODYSZ bytes apart)
  DA bodies, bodies+45056, bodies+90112, bodies+135168
  DA bodies+180224, bodies+225280, bodies+270336, bodies+315392
  DA cartdata+32
NAMETAB:
  DA nRIO, nMARA, nTANK, nKENJI, nZED, nFOX, nLIN, nWOLF, cartname
OATHNAMES:
  DA sGUARD, sFISTS, sSKY, sSTAND

; ---- song: SQ1 periods, 0 = rest, $FFFF = loop ----
song:
  DW 122, 0, 122, 91, 0, 81, 91, 0
  DW 122, 0, 122, 136, 0, 122, 109, 0
  DW 122, 0, 122, 91, 0, 81, 72, 0
  DW 81, 0, 91, 109, 0, 122, 0, 0
  DW $FFFF

; ---- strings (ASCII, 0-terminated) ----
sTAG:                ; "SWEAR AN OATH. KEEP YOUR WORD."
  DB 'S', 'W', 'E', 'A', 'R', ' ', 'A', 'N', ' ', 'O', 'A', 'T', 'H', '.', ' ', 'K', 'E', 'E', 'P', ' ', 'Y', 'O', 'U', 'R', ' ', 'W', 'O', 'R', 'D', '.', 0
sARCADE:                ; "1P ARCADE"
  DB '1', 'P', ' ', 'A', 'R', 'C', 'A', 'D', 'E', 0
sVERSUS:                ; "2P VERSUS"
  DB '2', 'P', ' ', 'V', 'E', 'R', 'S', 'U', 'S', 0
sTRAIN:         ; "TRAINING"
  DB 'T', 'R', 'A', 'I', 'N', 'I', 'N', 'G', 0
sTSEL1:         ; "PICK YOUR FIGHTER"
  DB 'P', 'I', 'C', 'K', ' ', 'Y', 'O', 'U', 'R', ' ', 'F', 'I', 'G', 'H', 'T', 'E', 'R', 0
sTSEL2:         ; "NOW PICK THE DUMMY"
  DB 'N', 'O', 'W', ' ', 'P', 'I', 'C', 'K', ' ', 'T', 'H', 'E', ' ', 'D', 'U', 'M', 'M', 'Y', 0
sDUMMY:         ; "DUMMY"
  DB 'D', 'U', 'M', 'M', 'Y', 0
sDMG:           ; "DAMAGE"
  DB 'D', 'A', 'M', 'A', 'G', 'E', 0
sTHINT:         ; "START DUMMY  HOLD START QUIT"
  DB 'S', 'T', 'A', 'R', 'T', ' ', 'D', 'U', 'M', 'M', 'Y', ' ', ' ', 'H', 'O', 'L', 'D', ' ', 'S', 'T', 'A', 'R', 'T', ' ', 'Q', 'U', 'I', 'T', 0
sDSTAND:        ; "STAND"
  DB 'S', 'T', 'A', 'N', 'D', 0
sDCROUCH:       ; "CROUCH"
  DB 'C', 'R', 'O', 'U', 'C', 'H', 0
sDJUMP:         ; "JUMP"
  DB 'J', 'U', 'M', 'P', 0
sDGUARD:        ; "GUARD"
  DB 'G', 'U', 'A', 'R', 'D', 0
sDCPU:          ; "CPU"
  DB 'C', 'P', 'U', 0
sDREC:          ; "RECORD"
  DB 'R', 'E', 'C', 'O', 'R', 'D', 0
sDPLAY:         ; "PLAY"
  DB 'P', 'L', 'A', 'Y', 0
sDEMO:          ; "DEMO   PRESS START"
  DB 'D', 'E', 'M', 'O', 32, 32, 32, 'P', 'R', 'E', 'S', 'S', 32, 'S', 'T', 'A', 'R', 'T', 0
sSTART:                ; "PRESS START"
  DB 'P', 'R', 'E', 'S', 'S', ' ', 'S', 'T', 'A', 'R', 'T', 0
sCREATE1:                ; "P1 CREATE YOUR FIGHTER"
  DB 'P', '1', ' ', 'C', 'R', 'E', 'A', 'T', 'E', ' ', 'Y', 'O', 'U', 'R', ' ', 'F', 'I', 'G', 'H', 'T', 'E', 'R', 0
sCREATE2:                ; "P2 CREATE YOUR FIGHTER"
  DB 'P', '2', ' ', 'C', 'R', 'E', 'A', 'T', 'E', ' ', 'Y', 'O', 'U', 'R', ' ', 'F', 'I', 'G', 'H', 'T', 'E', 'R', 0
sSTARTD:                ; "START  DONE"
  DB 'S', 'T', 'A', 'R', 'T', ' ', ' ', 'D', 'O', 'N', 'E', 0
sSWEAR:                ; "SWEAR AN OATH"
  DB 'S', 'W', 'E', 'A', 'R', ' ', 'A', 'N', ' ', 'O', 'A', 'T', 'H', 0
sOA1:                ; "A  NO GUARD"
  DB 'A', ' ', ' ', 'N', 'O', ' ', 'G', 'U', 'A', 'R', 'D', 0
sOA2:                ; "B  FISTS ONLY"
  DB 'B', ' ', ' ', 'F', 'I', 'S', 'T', 'S', ' ', 'O', 'N', 'L', 'Y', 0
sOA3:                ; "X  SKY STRIKER"
  DB 'X', ' ', ' ', 'S', 'K', 'Y', ' ', 'S', 'T', 'R', 'I', 'K', 'E', 'R', 0
sOA4:                ; "Y  STAND FAST"
  DB 'Y', ' ', ' ', 'S', 'T', 'A', 'N', 'D', ' ', 'F', 'A', 'S', 'T', 0
sNOOATH:                ; "START  NO OATH"
  DB 'S', 'T', 'A', 'R', 'T', ' ', ' ', 'N', 'O', ' ', 'O', 'A', 'T', 'H', 0
sP1:                ; "P1"
  DB 'P', '1', 0
sP2:                ; "P2"
  DB 'P', '2', 0
sWAIT:                ; "..."
  DB '.', '.', '.', 0
sSWORN:                ; "SWORN"
  DB 'S', 'W', 'O', 'R', 'N', 0
sROUND:                ; "ROUND "
  DB 'R', 'O', 'U', 'N', 'D', ' ', 0
sFIGHT:                ; "FIGHT!"
  DB 'F', 'I', 'G', 'H', 'T', '!', 0
sKO:                ; "K.O."
  DB 'K', '.', 'O', '.', 0
sTIME:                ; "TIME"
  DB 'T', 'I', 'M', 'E', 0
sDRAW:                ; "DRAW"
  DB 'D', 'R', 'A', 'W', 0
sP1WINS:                ; "P1 WINS"
  DB 'P', '1', ' ', 'W', 'I', 'N', 'S', 0
sP2WINS:                ; "P2 WINS"
  DB 'P', '2', ' ', 'W', 'I', 'N', 'S', 0
sNOTHING:                ; "SWORE NOTHING"
  DB 'S', 'W', 'O', 'R', 'E', ' ', 'N', 'O', 'T', 'H', 'I', 'N', 'G', 0
sKEPT:                ; "KEPT"
  DB 'K', 'E', 'P', 'T', 0
sBROKE:                ; "BROKE"
  DB 'B', 'R', 'O', 'K', 'E', 0
sGUARD:                ; "NO GUARD"
  DB 'N', 'O', ' ', 'G', 'U', 'A', 'R', 'D', 0
sFISTS:                ; "FISTS ONLY"
  DB 'F', 'I', 'S', 'T', 'S', ' ', 'O', 'N', 'L', 'Y', 0
sSKY:                ; "SKY STRIKER"
  DB 'S', 'K', 'Y', ' ', 'S', 'T', 'R', 'I', 'K', 'E', 'R', 0
sSTAND:                ; "STAND FAST"
  DB 'S', 'T', 'A', 'N', 'D', ' ', 'F', 'A', 'S', 'T', 0
; ---- the roster: main then alternate colours (skin, hair, top, legs, shoes) per fighter ----
CHARCOL:
  DB 0, 0, 0, 0, 0, 1, 2, 8, 1, 1        ; RIO
  DB 1, 4, 2, 3, 1, 0, 7, 8, 5, 6        ; MARA
  DB 3, 1, 6, 1, 3, 2, 5, 1, 6, 2        ; TANK
  DB 2, 1, 1, 7, 0, 0, 0, 7, 1, 4        ; KENJI
  DB 1, 4, 6, 1, 2, 3, 1, 5, 7, 7        ; ZED
  DB 3, 1, 7, 2, 1, 4, 3, 3, 9, 5        ; FOX
  DB 1, 1, 8, 6, 6, 0, 2, 1, 3, 3        ; LIN
  DB 4, 5, 5, 8, 0, 5, 1, 9, 4, 3        ; WOLF
EPITAB:
  DA sEPI0, sEPI1, sEPI2, sEPI3, sEPI4, sEPI5, sEPI6, sEPI7
MOVETAB:                               ; three special lines per fighter
  DA sMV00, sMV01, sMV02
  DA sMV10, sMV11, sMV12
  DA sMV20, sMV21, sMV22
  DA sMV30, sMV31, sMV32
  DA sMV40, sMV41, sMV42
  DA sMV50, sMV51, sMV52
  DA sMV60, sMV61, sMV62
  DA sMV70, sMV71, sMV72
QUOTETAB:
  DA sQ0, sQ1, sQ2, sQ3, sQ4, sQ5, sQ6, sQ7
sEPI0:           ; "THE WANDERER"
  DB 'T', 'H', 'E', ' ', 'W', 'A', 'N', 'D', 'E', 'R', 'E', 'R', 0
sEPI1:           ; "THE SWIFT"
  DB 'T', 'H', 'E', ' ', 'S', 'W', 'I', 'F', 'T', 0
sEPI2:           ; "THE BULWARK"
  DB 'T', 'H', 'E', ' ', 'B', 'U', 'L', 'W', 'A', 'R', 'K', 0
sEPI3:           ; "THE EMBER"
  DB 'T', 'H', 'E', ' ', 'E', 'M', 'B', 'E', 'R', 0
sEPI4:           ; "THE SHADE"
  DB 'T', 'H', 'E', ' ', 'S', 'H', 'A', 'D', 'E', 0
sEPI5:           ; "THE BRAWLER"
  DB 'T', 'H', 'E', ' ', 'B', 'R', 'A', 'W', 'L', 'E', 'R', 0
sEPI6:           ; "THE TIDE"
  DB 'T', 'H', 'E', ' ', 'T', 'I', 'D', 'E', 0
sEPI7:           ; "THE IRON WALL"
  DB 'T', 'H', 'E', ' ', 'I', 'R', 'O', 'N', ' ', 'W', 'A', 'L', 'L', 0
sMV00:           ; "QCF+P SEAL BOLT"
  DB 'Q', 'C', 'F', 43, 'P', ' ', 'S', 'E', 'A', 'L', ' ', 'B', 'O', 'L', 'T', 0
sMV01:           ; "DP+P  PALM RISE"
  DB 'D', 'P', 43, 'P', ' ', ' ', 'P', 'A', 'L', 'M', ' ', 'R', 'I', 'S', 'E', 0
sMV02:           ; "QCB+P GATE RUSH"
  DB 'Q', 'C', 'B', 43, 'P', ' ', 'G', 'A', 'T', 'E', ' ', 'R', 'U', 'S', 'H', 0
sMV10:           ; "QCF+P NEEDLE BOLT"
  DB 'Q', 'C', 'F', 43, 'P', ' ', 'N', 'E', 'E', 'D', 'L', 'E', ' ', 'B', 'O', 'L', 'T', 0
sMV11:           ; "QCB+K GALE WHEEL"
  DB 'Q', 'C', 'B', 43, 'K', ' ', 'G', 'A', 'L', 'E', ' ', 'W', 'H', 'E', 'E', 'L', 0
sMV12:           ; "DP+K  LARK RISE"
  DB 'D', 'P', 43, 'K', ' ', ' ', 'L', 'A', 'R', 'K', ' ', 'R', 'I', 'S', 'E', 0
sMV20:           ; "QCF+P RAM CHARGE"
  DB 'Q', 'C', 'F', 43, 'P', ' ', 'R', 'A', 'M', ' ', 'C', 'H', 'A', 'R', 'G', 'E', 0
sMV21:           ; "DP+P  BELL SMASH"
  DB 'D', 'P', 43, 'P', ' ', ' ', 'B', 'E', 'L', 'L', ' ', 'S', 'M', 'A', 'S', 'H', 0
sMV22:           ; "QCB+P GATE CRUSHER"
  DB 'Q', 'C', 'B', 43, 'P', ' ', 'G', 'A', 'T', 'E', ' ', 'C', 'R', 'U', 'S', 'H', 'E', 'R', 0
sMV30:           ; "QCF+P EMBER BOLT"
  DB 'Q', 'C', 'F', 43, 'P', ' ', 'E', 'M', 'B', 'E', 'R', ' ', 'B', 'O', 'L', 'T', 0
sMV31:           ; "DP+P  PALM RISE"
  DB 'D', 'P', 43, 'P', ' ', ' ', 'P', 'A', 'L', 'M', ' ', 'R', 'I', 'S', 'E', 0
sMV32:           ; "QCB+K GALE WHEEL"
  DB 'Q', 'C', 'B', 43, 'K', ' ', 'G', 'A', 'L', 'E', ' ', 'W', 'H', 'E', 'E', 'L', 0
sMV40:           ; "QCF+P NEEDLE BOLT"
  DB 'Q', 'C', 'F', 43, 'P', ' ', 'N', 'E', 'E', 'D', 'L', 'E', ' ', 'B', 'O', 'L', 'T', 0
sMV41:           ; "QCB+P GATE RUSH"
  DB 'Q', 'C', 'B', 43, 'P', ' ', 'G', 'A', 'T', 'E', ' ', 'R', 'U', 'S', 'H', 0
sMV42:           ; "QCB+K GALE WHEEL"
  DB 'Q', 'C', 'B', 43, 'K', ' ', 'G', 'A', 'L', 'E', ' ', 'W', 'H', 'E', 'E', 'L', 0
sMV50:           ; "DP+P  PALM RISE"
  DB 'D', 'P', 43, 'P', ' ', ' ', 'P', 'A', 'L', 'M', ' ', 'R', 'I', 'S', 'E', 0
sMV51:           ; "QCB+P GATE RUSH"
  DB 'Q', 'C', 'B', 43, 'P', ' ', 'G', 'A', 'T', 'E', ' ', 'R', 'U', 'S', 'H', 0
sMV52:           ; "QCB+K GALE WHEEL"
  DB 'Q', 'C', 'B', 43, 'K', ' ', 'G', 'A', 'L', 'E', ' ', 'W', 'H', 'E', 'E', 'L', 0
sMV60:           ; "QCF+P SEAL BOLT"
  DB 'Q', 'C', 'F', 43, 'P', ' ', 'S', 'E', 'A', 'L', ' ', 'B', 'O', 'L', 'T', 0
sMV61:           ; "QCB+K GALE WHEEL"
  DB 'Q', 'C', 'B', 43, 'K', ' ', 'G', 'A', 'L', 'E', ' ', 'W', 'H', 'E', 'E', 'L', 0
sMV62:           ; "DP+K  LARK RISE"
  DB 'D', 'P', 43, 'K', ' ', ' ', 'L', 'A', 'R', 'K', ' ', 'R', 'I', 'S', 'E', 0
sMV70:           ; "QCF+P RAM CHARGE"
  DB 'Q', 'C', 'F', 43, 'P', ' ', 'R', 'A', 'M', ' ', 'C', 'H', 'A', 'R', 'G', 'E', 0
sMV71:           ; "DP+P  PALM RISE"
  DB 'D', 'P', 43, 'P', ' ', ' ', 'P', 'A', 'L', 'M', ' ', 'R', 'I', 'S', 'E', 0
sMV72:           ; "QCB+P GATE CRUSHER"
  DB 'Q', 'C', 'B', 43, 'P', ' ', 'G', 'A', 'T', 'E', ' ', 'C', 'R', 'U', 'S', 'H', 'E', 'R', 0
sQ0:             ; "THE ROAD IS LONG. YOU WERE ONE STEP."
  DB 'T', 'H', 'E', ' ', 'R', 'O', 'A', 'D', ' ', 'I', 'S', ' ', 'L', 'O', 'N', 'G', '.', ' ', 'Y', 'O', 'U', ' ', 'W', 'E', 'R', 'E', ' ', 'O', 'N', 'E', ' ', 'S', 'T', 'E', 'P', '.', 0
sQ1:             ; "TOO SLOW. I WAS GONE BEFORE YOU SWUNG."
  DB 'T', 'O', 'O', ' ', 'S', 'L', 'O', 'W', '.', ' ', 'I', ' ', 'W', 'A', 'S', ' ', 'G', 'O', 'N', 'E', ' ', 'B', 'E', 'F', 'O', 'R', 'E', ' ', 'Y', 'O', 'U', ' ', 'S', 'W', 'U', 'N', 'G', '.', 0
sQ2:             ; "WALLS DO NOT MOVE. NEITHER DO I."
  DB 'W', 'A', 'L', 'L', 'S', ' ', 'D', 'O', ' ', 'N', 'O', 'T', ' ', 'M', 'O', 'V', 'E', '.', ' ', 'N', 'E', 'I', 'T', 'H', 'E', 'R', ' ', 'D', 'O', ' ', 'I', '.', 0
sQ3:             ; "A SPARK BECOMES A FIRE. REMEMBER THAT."
  DB 'A', ' ', 'S', 'P', 'A', 'R', 'K', ' ', 'B', 'E', 'C', 'O', 'M', 'E', 'S', ' ', 'A', ' ', 'F', 'I', 'R', 'E', '.', ' ', 'R', 'E', 'M', 'E', 'M', 'B', 'E', 'R', ' ', 'T', 'H', 'A', 'T', '.', 0
sQ4:             ; "YOU NEVER SAW WHERE I CAME FROM."
  DB 'Y', 'O', 'U', ' ', 'N', 'E', 'V', 'E', 'R', ' ', 'S', 'A', 'W', ' ', 'W', 'H', 'E', 'R', 'E', ' ', 'I', ' ', 'C', 'A', 'M', 'E', ' ', 'F', 'R', 'O', 'M', '.', 0
sQ5:             ; "GET UP. I WAS JUST WARMING UP."
  DB 'G', 'E', 'T', ' ', 'U', 'P', '.', ' ', 'I', ' ', 'W', 'A', 'S', ' ', 'J', 'U', 'S', 'T', ' ', 'W', 'A', 'R', 'M', 'I', 'N', 'G', ' ', 'U', 'P', '.', 0
sQ6:             ; "THE TIDE COMES BACK. SO WILL I."
  DB 'T', 'H', 'E', ' ', 'T', 'I', 'D', 'E', ' ', 'C', 'O', 'M', 'E', 'S', ' ', 'B', 'A', 'C', 'K', '.', ' ', 'S', 'O', ' ', 'W', 'I', 'L', 'L', ' ', 'I', '.', 0
sQ7:             ; "IRON KEEPS ITS WORD. DID YOU?"
  DB 'I', 'R', 'O', 'N', ' ', 'K', 'E', 'E', 'P', 'S', ' ', 'I', 'T', 'S', ' ', 'W', 'O', 'R', 'D', '.', ' ', 'D', 'I', 'D', ' ', 'Y', 'O', 'U', '?', 0
sCHOOSE:         ; "CHOOSE YOUR FIGHTER"
  DB 'C', 'H', 'O', 'O', 'S', 'E', ' ', 'Y', 'O', 'U', 'R', ' ', 'F', 'I', 'G', 'H', 'T', 'E', 'R', 0
sSELHINT:        ; "A MAIN  B ALT  Y TAILOR"
  DB 'A', ' ', 'M', 'A', 'I', 'N', ' ', ' ', 'B', ' ', 'A', 'L', 'T', ' ', ' ', 'Y', ' ', 'T', 'A', 'I', 'L', 'O', 'R', 0
sBONUS1:         ; "BONUS STAGE"
  DB 'B', 'O', 'N', 'U', 'S', ' ', 'S', 'T', 'A', 'G', 'E', 0
sBONUS2:         ; "WRECK THE CART!"
  DB 'W', 'R', 'E', 'C', 'K', ' ', 'T', 'H', 'E', ' ', 'C', 'A', 'R', 'T', '!', 0
sWRECKED:        ; "WRECKED!"
  DB 'W', 'R', 'E', 'C', 'K', 'E', 'D', '!', 0
sBONUSPTS:       ; "BONUS"
  DB 'B', 'O', 'N', 'U', 'S', 0
cartname:        ; "CART"
  DB 'C', 'A', 'R', 'T', 0
sONE:
  DB '1', 0
sTWO:
  DB '2', 0
sTECH:                ; "TECH"
  DB 'T', 'E', 'C', 'H', 0
sHITS:                ; " HITS"
  DB ' ', 'H', 'I', 'T', 'S', 0
sSURGE:                ; "OATH SURGE!"
  DB 'O', 'A', 'T', 'H', ' ', 'S', 'U', 'R', 'G', 'E', '!', 0
sYOUWIN:                ; "YOU WIN"
  DB 'Y', 'O', 'U', ' ', 'W', 'I', 'N', 0
sYOULOSE:                ; "YOU LOSE"
  DB 'Y', 'O', 'U', ' ', 'L', 'O', 'S', 'E', 0
sNEXT:                ; "START  NEXT RIVAL"
  DB 'S', 'T', 'A', 'R', 'T', ' ', ' ', 'N', 'E', 'X', 'T', ' ', 'R', 'I', 'V', 'A', 'L', 0
sCONT:                ; "START  TRY AGAIN"
  DB 'S', 'T', 'A', 'R', 'T', ' ', ' ', 'T', 'R', 'Y', ' ', 'A', 'G', 'A', 'I', 'N', 0
sP1DUEL:                ; "P1 TAKES IT"
  DB 'P', '1', ' ', 'T', 'A', 'K', 'E', 'S', ' ', 'I', 'T', 0
sP2DUEL:                ; "P2 TAKES IT"
  DB 'P', '2', ' ', 'T', 'A', 'K', 'E', 'S', ' ', 'I', 'T', 0
sREMATCH:                ; "START  REMATCH"
  DB 'S', 'T', 'A', 'R', 'T', ' ', ' ', 'R', 'E', 'M', 'A', 'T', 'C', 'H', 0
sQUIT:                ; "B  TITLE"
  DB 'B', ' ', ' ', 'T', 'I', 'T', 'L', 'E', 0
sCHAMP1:                ; "THE PALMGATE"
  DB 'T', 'H', 'E', ' ', 'P', 'A', 'L', 'M', 'G', 'A', 'T', 'E', 0
sCHAMP2:                ; "IS YOURS"
  DB 'I', 'S', ' ', 'Y', 'O', 'U', 'R', 'S', 0
sCHAMP3:                ; "PRESS START"
  DB 'P', 'R', 'E', 'S', 'S', ' ', 'S', 'T', 'A', 'R', 'T', 0
nRIO:                ; "RIO"
  DB 'R', 'I', 'O', 0
nMARA:                ; "MARA"
  DB 'M', 'A', 'R', 'A', 0
nTANK:                ; "TANK"
  DB 'T', 'A', 'N', 'K', 0
nKENJI:                ; "KENJI"
  DB 'K', 'E', 'N', 'J', 'I', 0
nZED:                ; "ZED"
  DB 'Z', 'E', 'D', 0
nFOX:                ; "FOX"
  DB 'F', 'O', 'X', 0
nLIN:                ; "LIN"
  DB 'L', 'I', 'N', 0
nWOLF:                ; "WOLF"
  DB 'W', 'O', 'L', 'F', 0
sLABELS:          ; BODY SKIN HAIR TOP LEGS SHOES, each 0-terminated
  DB 'B', 'O', 'D', 'Y', 0
  DB 'S', 'K', 'I', 'N', 0
  DB 'H', 'A', 'I', 'R', 0
  DB 'T', 'O', 'P', 0
  DB 'L', 'E', 'G', 'S', 0
  DB 'S', 'H', 'O', 'E', 'S', 0
rstr EQU $000178  ; RAM: "ROUND n" built at runtime

; ---- art (examples/swornrivals/gen_art.js; colour ramps shared with Street Brawl) ----
stages:
  INCBIN "stages.bin"
paldata:
  INCBIN "pal.bin"
mapdata:
  INCBIN "maps.bin"
charpal:
  INCBIN "../streetbrawl/charpal.bin"
bodies:
  INCBIN "bodies.bin"
cartdata:                ; 16-word palette, then 3 cart frames
  INCBIN "cart.bin"
tiledata:
  INCBIN "tiles.bin"
tiledataend:
