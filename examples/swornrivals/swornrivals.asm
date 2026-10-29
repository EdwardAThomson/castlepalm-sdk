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
;              A punch  B kick
;              Down, Down-fwd, Fwd + A  Gate Rush      Fwd, Down, Down-fwd + A  Palm Rise
;              Down, Down-fwd, Fwd + B  Oath Surge (full meter)
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
; ---- palette banks ----
PB_HUD    EQU 0
PB_FONT   EQU 3
PB_FLASH  EQU 4
PB_SPARK  EQU 5
PB_P2     EQU 8
PB_P1     EQU 9
PB_BIG    EQU 12
PB_TITLE  EQU 13
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
NPOSE     EQU 17
STAGEREC  EQU 472         ; bytes per stage record (224-word sky + 12-word bank 1)
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
F1     EQU $000200
F2     EQU $000280

; ---- RAM ----
gstate   EQU $000100
mode     EQU $000102      ; 0 arcade, 1 versus
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
  LDA A1, #F2
  CALL applypicks
  POPA A0
  LDA A2, #F2
  LDB R0, [A0+#6]
  STW R0, [A2+#FAI]
  MOV R0, #1
  STW R0, [A2+#FCPU]
  LDW R0, [rival]
  CALL setstage
  RET

; ============================ title ============================
inittitle:
  MOV R0, #G_TITLE
  STW R0, [gstate]
  MOV R0, #0
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
  MOV R1, R0
  AND R1, #UP+DOWN
  BEQ tf_st
  LDW R1, [sel]
  XOR R1, #1
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
  MOV R0, #0
  STW R0, [cwho]
  CALL initcreator
  RET
tf_draw:
  LDW R0, [gT]
  CMP R0, #1
  BNE tf_np
  MOV R4, #4               ; first frame: a dark plaque behind the menu
  MOV R5, #9
  MOV R6, #36
  MOV R7, #17
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
  MOV R1, #124
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
  LDW R1, [e1]
cf_pad:
  STW R1, [cedge]
  MOV R0, R1
  AND R0, #START
  BEQ cf_up
  CALL savepicks
  MOV R0, #120
  CALL sfxblip
  LDW R0, [mode]
  CMP R0, #0
  BEQ cf_go
  LDW R0, [cwho]
  CMP R0, #0
  BNE cf_go
  MOV R0, #1               ; versus: now player 2 builds a fighter
  STW R0, [cwho]
  CALL initcreator
  RET
cf_go:
  CALL newmatch
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
  ; fall through
startmatch:
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
  MOV R0, #2               ; versus is fought at sunset
  CALL setstage
sm_go:
  MOV R0, #1
  STW R0, [round]
  CALL copymaps
  CALL clearhud
  CALL initoath
  RET

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
  LDA A0, #faceup
  CALL both
  CALL updatecam
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
  CALL drawspark
  CALL drawfighters
  CALL drawhud
  RET

; ---- clocktick: one second = 60 fight frames; kept oaths trickle meter ----
clocktick:
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
  BEQ ps_set
  LDW R1, [in1]
ps_set:
  STW R1, [A2+#FPAD]
  LDW R0, [A2+#FPADP]
  NOT R0
  AND R0, R1
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

; ---- motionrec: log relative direction changes (1 D, 2 DF, 3 F, 4 B, 0 other) ----
motionrec:
  CALL dirbits
  LDW R1, [A2+#FPAD]
  MOV R0, #0
  MOV R2, R1
  AND R2, #DOWN
  BEQ mr_nd
  MOV R0, #1
  MOV R2, R1
  AND R2, R6
  BEQ mr_code
  MOV R0, #2
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
  AND R0, #ABTN
  BEQ gr_b
  LDA A1, #MO_DP
  CALL motion
  CMP R0, #0
  BEQ gr_qa
  MOV R0, #AK_RISE+1
  RET
gr_qa:
  LDA A1, #MO_QCF
  CALL motion
  CMP R0, #0
  BEQ gr_pa
  MOV R0, #AK_RUSH+1
  RET
gr_pa:
  MOV R0, #AK_PUNCH+1
  LDW R1, [A2+#FPAD]
  AND R1, #DOWN
  BEQ gr_ret
  MOV R0, #AK_CPUNCH+1
gr_ret:
  RET
gr_b:
  MOV R0, R1
  AND R0, #BBTN
  BEQ gr_ret
  LDW R0, [A2+#FMTR]
  CMP R0, #MTRMAX
  BLT gr_kb
  LDA A1, #MO_QCF
  CALL motion
  CMP R0, #0
  BEQ gr_kb
  MOV R0, #AK_SURGE+1
  RET
gr_kb:
  MOV R0, #AK_KICK+1
  LDW R1, [A2+#FPAD]
  AND R1, #DOWN
  BEQ gr_ret
  MOV R0, #AK_SWEEP+1
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
  RET                      ; KO / WIN: nothing
ctl_stun:
  LDW R0, [A2+#FT]
  SUB R0, #1
  STW R0, [A2+#FT]
  BGT ctl_ret
  MOV R0, #ST_IDLE
  STW R0, [A2+#FST]
  MOV R0, #PO_GUARD
  STW R0, [A2+#FPOSE]
ctl_ret:
  RET
ctl_air:
  CALL getreq
  CMP R0, #0
  BEQ ctl_ret
  MOV R1, #AK_APUNCH+1     ; any button in the air: A -> air punch, B -> air kick
  CMP R0, #AK_KICK+1
  BEQ ctl_ak
  CMP R0, #AK_SWEEP+1
  BEQ ctl_ak
  CMP R0, #AK_SURGE+1
  BEQ ctl_ak
  CMP R0, #AK_AKICK+1
  BEQ ctl_ak
  BRA ctl_as
ctl_ak:
  MOV R1, #AK_AKICK+1
ctl_as:
  MOV R0, R1
  SUB R0, #1
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
  LDW R2, [A3+#FST]        ; holding down-back against an attack: show the low guard
  CMP R2, #ST_ATK
  BNE ctl_cp
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
  LDW R2, [A3+#FST]        ; back held while the rival attacks: guard, don't walk
  CMP R2, #ST_ATK
  BNE ctl_back
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
  SHL R0, #4
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
  MOV R0, #60
  CALL sfxblip
  RET
sa_snd:
  MOV R0, #180
  CALL sfxblip
  RET

; ---- atkstep: advance the attack timeline (startup, active, recovery) ----
atkstep:
  CALL atkrec
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
  BEQ as_rec
  LDW R0, [A2+#FY]
  CMP R0, #0
  BGE as_rec
  SUB R2, #1
  STW R2, [A2+#FT]
  MOV R4, R2
as_live:
  LDB R0, [A0+#AT_P1]
  STW R0, [A2+#FPOSE]
  CMP R4, R1               ; first active frame: Palm Rise lifts off
  BNE as_dash
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
  MOV R0, R4               ; alternate punch / kick frames
  AND R0, #4
  MOV R0, #PO_PUNCH
  BEQ as_altp
  MOV R0, #PO_KICK
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
  MOV R0, #ST_IDLE
  STW R0, [A2+#FST]
  MOV R0, #PO_GUARD
  STW R0, [A2+#FPOSE]
ds_ret:
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
  MOV R0, #300
  CALL sfxblip
  PUSHA A2                 ; No Guard: the defender just blocked
  PUSHA A3
  MOVA A0, A2
  MOVA A2, A3              ; A2 = defender
  MOVA A3, A0              ; A3 = attacker
  MOV R0, #OA_GUARD
  CALL breakself
  POPA A3
  POPA A2
  CALL skycheck
  RET

; ---- skycheck(A2): a ground attack connected -> Sky Striker breaks ----
skycheck:
  CALL atkrec
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
  LDB R0, [A0+#AT_DMG]
  LDW R1, [A2+#FDMGB]
  ADD R0, R1
  LDW R1, [A3+#FARMR]
  SUB R0, R1
  CMP R0, #1
  BGE hl_d
  MOV R0, #1
hl_d:
  LDW R1, [A3+#FHP]
  SUB R1, R0
  CMP R1, #0
  BGE hl_hp
  MOV R1, #0
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
  MOV R0, #24
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
  MOV R0, #90
  CALL sfxblip
  RET

koframe:
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
  CALL oambegin
  MOV R1, #40
  LDA A1, #sCHAMP1
  CALL cbig
  MOV R1, #60
  LDA A1, #sCHAMP2
  CALL cbig
  MOV R1, #88
  LDA A1, #sCHAMP3
  CALL ctext
  LDA A2, #F1
  MOV R0, #ST_WIN
  STW R0, [A2+#FST]
  MOV R0, #PO_WIN
  STW R0, [A2+#FPOSE]
  CALL drawfighters
  CALL drawhud
  RET

; ============================ CPU ============================
; ---- cputhink(A2 = CPU, A3 = player): sets FAIPAD (held directions) and FAIATK ----
cputhink:
  LDW R0, [A2+#FST]        ; mid-jump: strike on the way down when close
  CMP R0, #ST_JUMP
  BNE ct_gnd
  LDW R0, [A2+#FVY]
  CMP R0, #0
  BLE ct_hold
  CALL cpudist
  CMP R0, #60
  BGT ct_hold
  MOV R0, #AK_AKICK+1
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
  CMP R0, #2
  BLT ct_noair
  CALL cpudist
  CMP R0, #64
  BGT ct_noair
  CMP R4, #10
  BGE ct_noair
  MOV R0, #AK_RISE+1
  BRA ct_attack
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
  MOV R0, #AK_RUSH+1
  BRA ct_attack
ct_far1:
  CMP R1, #1
  BLT ct_walkin
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
  CMP R4, #6               ; mid range: step in, kick, sweep, or jump in
  BLT ct_walkin
  CMP R4, #9
  BLT ct_kick
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
ct_sweep:
  MOV R0, #AK_SWEEP+1
  BRA ct_attack
ct_wait:
  RET
ct_close:
  CMP R4, #6               ; close: jab, crouch jab, kick, back off, or guard
  BLT ct_punch
  CMP R4, #8
  BLT ct_cpunch
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
ct_cpunch:
  MOV R0, #AK_CPUNCH+1
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
  CMP R0, #AK_KICK+1       ; Fists Only: kicks become punches
  BEQ ch_p
  CMP R0, #AK_SWEEP+1
  BEQ ch_cp
  CMP R0, #AK_AKICK+1
  BEQ ch_ap
  CMP R0, #AK_SURGE+1
  BEQ ch_r
  RET
ch_p:
  MOV R0, #AK_PUNCH+1
  RET
ch_cp:
  MOV R0, #AK_CPUNCH+1
  RET
ch_ap:
  MOV R0, #AK_APUNCH+1
  RET
ch_r:
  MOV R0, #AK_RUSH+1
  RET
ch_sky:
  CMP R1, #OA_SKY
  BNE ch_ok
  CMP R0, #AK_APUNCH+1     ; Sky Striker: only air attacks
  BEQ ch_ok
  CMP R0, #AK_AKICK+1
  BEQ ch_ok
  MOV R0, #0
ch_ok:
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
sfxblip:
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
; ---- attack table: 16 bytes per attack (AT_* fields) ----
ATKTAB:
  ;  S  A   R  dmg hs  bs  x0  x1  y0  y1 kind flags                    p0         p1          dash p2
  DB 4, 3,  8,  8, 14, 10,  8, 40, 30, 50, 0, AF_GROUND,               PO_GUARD,  PO_PUNCH,   0, PO_PUNCH
  DB 7, 4, 13, 12, 18, 12,  8, 50, 16, 40, 0, AF_GROUND+AF_KICK,       PO_GUARD,  PO_KICK,    0, PO_KICK
  DB 4, 3,  8,  7, 13,  9,  8, 38, 18, 34, 0, AF_GROUND,               PO_CROUCH, PO_CPUNCH,  0, PO_CPUNCH
  DB 6, 4, 14, 10, 16, 12,  8, 50,  0, 14, 1, AF_GROUND+AF_KICK,       PO_CROUCH, PO_LOWKICK, 0, PO_LOWKICK
  DB 3, 6,  0,  9, 16, 12,  4, 36, 10, 40, 2, AF_AIR,                  PO_JUMP,   PO_AIRPUNCH, 0, PO_JUMP
  DB 4, 6,  0, 11, 18, 12,  4, 44,  0, 30, 2, AF_AIR+AF_KICK,          PO_JUMP,   PO_AIRKICK, 0, PO_JUMP
  DB 8, 14, 16, 14, 22, 14, 4, 40, 20, 48, 0, AF_GROUND+AF_KD,         PO_CROUCH, PO_PUNCH,   5, PO_GUARD
  DB 3, 10, 22, 16, 24, 14, 0, 30, 30, 80, 0, AF_GROUND+AF_KD+AF_INV+AF_RISE, PO_CROUCH, PO_RISE, 0, PO_JUMP
  DB 10, 30, 20, 9, 12, 10, 4, 44, 10, 50, 0, AF_GROUND+AF_KICK+AF_MULTI, PO_CROUCH, PO_PUNCH, 3, PO_GUARD

; motion patterns, newest first (1 D, 2 DF, 3 F)
MO_QCF:
  DB 3, 2, 1
MO_DP:
  DB 2, 1, 3

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

; ---- creator ----
CHCOUNT:
  DB NBODY, 6, 8, 10, 10, 8
PICKDEF:                               ; P1 defaults, then P2 defaults
  DB 0, 0, 0, 0, 0, 0
  DB 3, 2, 4, 2, 1, 0
SWTAB:
  DB 2, 3, 5, 2, 7, 3, 10, 3, 13, 2
BODYTAB:                               ; ROM address of each body's NPOSE frames (34816 bytes apart)
  DA bodies, bodies+34816, bodies+69632, bodies+104448
  DA bodies+139264, bodies+174080, bodies+208896, bodies+243712
NAMETAB:
  DA nRIO, nMARA, nTANK, nKENJI, nZED, nFOX, nLIN, nWOLF
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
sSTART:                ; "PRESS START"
  DB 'P', 'R', 'E', 'S', 'S', ' ', 'S', 'T', 'A', 'R', 'T', 0
sCREATE1:                ; "P1 CREATE YOUR FIGHTER"
  DB 'P', '1', ' ', 'C', 'R', 'E', 'A', 'T', 'E', ' ', 'Y', 'O', 'U', 'R', ' ', 'F', 'I', 'G', 'H', 'T', 'E', 'R', 0
sCREATE2:                ; "P2 CREATE YOUR FIGHTER"
  DB 'P', '2', ' ', 'C', 'R', 'E', 'A', 'T', 'E', ' ', 'Y', 'O', 'U', 'R', ' ', 'F', 'I', 'G', 'H', 'T', 'E', 'R', 0
sSTARTD:                ; "START TO FIGHT"
  DB 'S', 'T', 'A', 'R', 'T', ' ', 'T', 'O', ' ', 'F', 'I', 'G', 'H', 'T', 0
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
tiledata:
  INCBIN "tiles.bin"
tiledataend:
