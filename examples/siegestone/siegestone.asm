; CastlePalm — SIEGESTONE, a 2-player versus puzzle game.
;
; Two castle wells, 6 x 12 cells of 16x16. Pairs of mason's stones fall into each well;
; four or more touching of one colour clear. Clears load your catapult basket, and B
; looses it: cracked rubble flies into your rival's well. A volley that lands while your
; basket holds stones spills half of it. Rubble takes two separate neighbouring clears
; to break. A wet mortar stone glues its neighbours in place unless a clear touches it
; within MORTART frames.
;
; Modes: A on the title = Solo Ladder (pad 1 vs five CPU rivals; the CPU drives a
; virtual pad 2, PalmBlast's pattern), B = 2 Players (pad 2 = INPUT1).
;
; Each well is one player block (PL0 / PL1) and every well routine takes A3 = the block,
; so both wells share one state machine. Grid cell i = row*8 + col (cols 6,7 and the
; rows above 0 / below 11 hold $FF sentinels, so neighbour and bounds checks need no
; range tests).
;
; Art: examples/siegestone/gen_art.js writes art.bin (INCBIN'd at artbin) and the
; ART-EQU block below. BG0 = wells + castle frame + text (priority 3), BG1 = backdrop
; with an hblank sky gradient on palette entry 0. Banks: 0 well/rubble/mortar,
; 1..4 stones (bank = stone colour), 5 frame, 6 gold text, 7 white text, 8..9 backdrop,
; 11 catapult, 12 clear flash, 13 crowns.

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
FRAMEREG  EQU $100014  ; u16 hardware frame counter
IRQ_EN    EQU $100012  ; IRQ_ENABLE (bit1 hblank)
SCANLINE  EQU $10101A  ; PPU_SCANLINE (line just rendered, read in hblank)
DMA_SRC   EQU $100020
DMA_DST   EQU $100024
DMA_LEN   EQU $100028
DMA_MODE  EQU $10002A
DMA_CTRL  EQU $10002E
SQ0_PERIOD EQU $102000
SQ0_VOL    EQU $102002
SQ0_CTRL   EQU $102003
NOISE_PERIOD EQU $102008
NOISE_VOL  EQU $10200A
NOISE_CTRL EQU $10200B
UP    EQU 1
DOWN  EQU 2
LEFT  EQU 4
RIGHT EQU 8
ABTN  EQU 16           ; turn clockwise
BBTN  EQU 32           ; loose the catapult
XBTN  EQU 64           ; turn counter-clockwise (X or Y)
YBTN  EQU 128
START EQU 256

; --- tuning ---
MORTART EQU 240        ; wet mortar sets after 4 s
FLASHT  EQU 30         ; clear flash frames
FLYTIME EQU 48         ; volley flight frames (ART_ARC has 48 steps)
BASKMAX EQU 36         ; basket cap; a full basket looses itself
PENDMAX EQU 72         ; incoming rubble cap
TIGHTEN EQU 1800       ; every 30 s of a round, gravity tightens by 2 frames
FALLMIN EQU 8

; --- game states ---
ST_TITLE EQU 0
ST_PLAY  EQU 1
ST_PAUSE EQU 2
ST_RDEND EQU 3
ST_INTRO EQU 4
ST_RESULT EQU 5
; --- well states ---
PSPAWN  EQU 0
PFALL   EQU 1
PSETTLE EQU 2
PFLASH  EQU 3
PDEAD   EQU 4

; --- globals ---
state    EQU $000100
mode     EQU $000102   ; 0 = 2 players, 1 = solo ladder
rival    EQU $000104   ; ladder rung 0..4
rng      EQU $000106
P0IN     EQU $000108
P1IN     EQU $00010A
P0PR     EQU $00010C
P1PR     EQU $00010E
sfxT     EQU $000110
roundT   EQU $000112   ; frames since gravity last tightened
fallcur  EQU $000114   ; current gravity interval (frames per row)
stimer   EQU $000116   ; state timer (round end)
txtattr  EQU $00011A   ; BG0 entry bits OR'd into glyphs (text colour bank)
loser    EQU $00011C   ; 1 = P1's well fell, 2 = P2's, 3 = both
resnext  EQU $00011E   ; RESULT screen: 0 -> title, 1 -> rival intro
noiseT   EQU $000120
aidelay  EQU $000122   ; CPU frames between moves
aimask   EQU $000124   ; CPU placement noise (AND mask)
ailoose  EQU $000126   ; CPU looses at this basket
mrate    EQU $000128   ; u8 mortar: 1 pair in N (0 = none)
ncol     EQU $000129   ; u8 stone colours in play (3 or 4)
win0     EQU $00012A   ; u8 rounds won this match
win1     EQU $00012B
nspr     EQU $00012C   ; sprites emitted this frame
fctot    EQU $00012E
aibest   EQU $000130
aicol    EQU $000132
airot    EQU $000134
aiscore  EQU $000136
aerow    EQU $000138
aecol    EQU $00013A
aecode   EQU $00013C
fallbase EQU $00013E

; --- player blocks (A3) ---
PL0      EQU $000400
PL1      EQU $000800
PS_STATE EQU 0         ; u8 well state
PS_TIMER EQU 1         ; u8
PS_PX    EQU 2         ; u8 pivot column
PS_PY    EQU 3         ; u8 pivot row
PS_ROT   EQU 4         ; u8 partner: 0 above, 1 right, 2 below, 3 left
PS_C0    EQU 5         ; u8 pivot code
PS_C1    EQU 6         ; u8 partner code
PS_N0    EQU 7         ; u8 next pair
PS_N1    EQU 8
PS_CHAIN EQU 9
PS_FALLT EQU 10
PS_BASKET EQU 11
PS_PEND  EQU 12        ; incoming rubble waiting to drop
PS_DROPPED EQU 13      ; rubble already dropped this turn
PS_IN    EQU 14        ; u16 pad word this frame
PS_PR    EQU 16        ; u16 last frame
PS_DAS   EQU 18
PS_ID    EQU 19        ; 0 / 1
PS_SEQ   EQU 20        ; u16 pair sequence (both wells start from one seed)
PS_FLY   EQU 23        ; volley in flight (stones)
PS_FLYT  EQU 24        ; flight frames left
PS_CATF  EQU 25        ; catapult swing frames left
PS_AITC  EQU 27        ; CPU target column / turn
PS_AITR  EQU 28
PS_AIT   EQU 29        ; CPU move delay
PS_AION  EQU 30        ; CPU has a plan
PS_ORGX  EQU 32        ; u16 well origin tile x (2 / 26)
PS_SPRX  EQU 34        ; u16 well origin pixel x (16 / 208)
PS_CLRN  EQU 36        ; stones cleared this step
PS_SHOWB EQU 38        ; basket value on screen
G        EQU $48       ; grid cell 0 (row -1 sentinels at $40, row 12 at $A8)
MARK     EQU $100      ; per cell: 1 = clearing, 2 = takes a blow
MTIM     EQU $180      ; per cell: wet mortar frames left
SHAD     EQU $200      ; per cell: look painted on BG0
SCR      EQU $000C00   ; CPU scratch well (112 bytes, same layout from row -1)
LIST     EQU $000D00   ; flood-fill list
VISB     EQU $000D90   ; flood-fill visited flags, index -16..111

; >>> ART-EQU (generated by examples/siegestone/gen_art.js; do not edit by hand) >>>
ART_NT    EQU 1047       ; art tiles 1..1047 (67 well + 736 frame/backdrop + 244 sprite/font)
ART_TBYTES EQU 33504    ; bytes in the tile run (one DMA to VRAM $20)
ART_TILES EQU 0       ; byte offset into artbin
ART_PAL   EQU 33504       ; byte offset into artbin
ART_SKY   EQU 34016       ; byte offset into artbin
ART_MAP0  EQU 34464       ; byte offset into artbin
ART_MAP1  EQU 36704       ; byte offset into artbin
ART_CELLS EQU 38944       ; byte offset into artbin
ART_ARC   EQU 39080       ; byte offset into artbin
A_STONE   EQU 804
A_CATA    EQU 824
A_BOULDER EQU 888
A_PEBBLE  EQU 892
A_CROWN   EQU 896
A_FONT    EQU 904
B_WELL    EQU 0         ; palette banks
B_RED     EQU 1
B_CATA    EQU 11
B_CROWN   EQU 13
T_GOLD    EQU $3000      ; BG0 entry bits: gold title text (bank 6)
T_WHITE   EQU $3800      ; BG0 entry bits: white menu text (bank 7)
; <<< ART-EQU <<<

  ORG $300000
  DA start
  DA 0
  DA hblank             ; hblank: per-line sky colour
  DA 0

start:
  LDA A0, #artPtrs+3    ; whole palette
  MOV R0, #0
  MOV R1, #512
  MOV R2, #2
  CALL dmago
  LDA A0, #artPtrs      ; tile run -> VRAM tile 1
  MOV R0, #32
  MOV R1, #ART_TBYTES
  MOV R2, #0
  CALL dmago
  LDA A0, #artbin+ART_MAP1
  MOV R6, #$40          ; BG1 map $14000
  MOV R7, #0
  CALL loadmap
  MOV R0, #3
  STW R0, [PPU_CTRL]
  MOV R0, #$5EED
  STW R0, [rng]
  MOV R0, #0
  STW R0, [sfxT]
  STW R0, [noiseT]
  STW R0, [mode]
  STW R0, [rival]
  CALL gotitle
  MOV R0, #2
  STB R0, [IRQ_EN]      ; hblank IRQ on (sky gradient)
  EI

mainloop:
  CALL readpads
  CALL nextrng          ; stir the RNG every frame (seeds depend on when you press)
  LDW R0, [state]
  CMP R0, #ST_PLAY
  BNE ml_1
  CALL doplay
  BRA ml_wait
ml_1:
  CMP R0, #ST_TITLE
  BNE ml_2
  CALL dotitle
  BRA ml_wait
ml_2:
  CMP R0, #ST_PAUSE
  BNE ml_3
  CALL dopause
  BRA ml_wait
ml_3:
  CMP R0, #ST_RDEND
  BNE ml_4
  CALL dordend
  BRA ml_wait
ml_4:
  CMP R0, #ST_INTRO
  BNE ml_5
  CALL dointro
  BRA ml_wait
ml_5:
  CALL doresult
ml_wait:
  CALL sfxtick
  CALL waitframe
  BRA mainloop

; ================= front end =================
gotitle:
  MOV R0, #ST_TITLE
  STW R0, [state]
  CALL clearbg
  CALL clearoam
  MOV R0, #T_GOLD
  STW R0, [txtattr]
  MOV R4, #10
  MOV R5, #4
  LDA A1, #str_title
  CALL print16
  MOV R0, #T_WHITE
  STW R0, [txtattr]
  MOV R4, #7
  MOV R5, #14
  LDA A1, #str_solo
  CALL print16
  MOV R4, #7
  MOV R5, #17
  LDA A1, #str_duo
  CALL print16
  ; vignette: four stones under the title, catapults on the field
  MOV R0, #0
  STW R0, [OAM_INDEX]
  MOV R0, #128
  MOV R1, #72
  MOV R3, #1
  CALL spr_stonexy
  MOV R0, #148
  MOV R1, #72
  MOV R3, #2
  CALL spr_stonexy
  MOV R0, #168
  MOV R1, #72
  MOV R3, #3
  CALL spr_stonexy
  MOV R0, #188
  MOV R1, #72
  MOV R3, #4
  CALL spr_stonexy
  MOV R0, #40
  MOV R1, #176
  MOV R5, #A_CATA
  MOV R6, #$20+B_CATA
  CALL emit
  MOV R0, #248
  MOV R1, #176
  MOV R5, #A_CATA
  MOV R6, #$60+B_CATA   ; h-flipped
  CALL emit
  RET

; ---- anyedge -> R0 = buttons newly pressed on either pad ----
anyedge:
  LDW R0, [P0PR]
  NOT R0
  LDW R1, [P0IN]
  AND R0, R1
  LDW R1, [P1PR]
  NOT R1
  LDW R2, [P1IN]
  AND R1, R2
  OR R0, R1
  RET

dotitle:
  CALL anyedge
  MOV R1, R0
  AND R1, #ABTN+START
  BEQ dt_nb
  MOV R0, #1
  STW R0, [mode]
  MOV R0, #0
  STW R0, [rival]
  CALL gointro
  RET
dt_nb:
  AND R0, #BBTN
  BEQ dt_r
  MOV R0, #0
  STW R0, [mode]
  CALL gomatch
dt_r:
  RET

; ---- rival intro card: RIVAL n, the rival's name, PUSH START ----
gointro:
  MOV R0, #ST_INTRO
  STW R0, [state]
  CALL clearbg
  CALL clearoam
  MOV R0, #T_GOLD
  STW R0, [txtattr]
  MOV R4, #13
  MOV R5, #6
  LDA A1, #str_rival
  CALL print16
  LDW R2, [rival]
  ADD R2, #28           ; digit rival+1
  CALL glyph16
  MOV R0, #T_WHITE
  STW R0, [txtattr]
  LDW R0, [rival]
  SHL R0, #5
  LDA A1, #str_names
  ADD A1, R0
  MOV R4, #4
  MOV R5, #11
  CALL print16
  MOV R4, #10
  MOV R5, #18
  LDA A1, #str_push
  CALL print16
  ; the rival's catapult faces you
  MOV R0, #0
  STW R0, [OAM_INDEX]
  MOV R0, #144
  MOV R1, #170
  MOV R5, #A_CATA
  MOV R6, #$60+B_CATA
  CALL emit
  RET

dointro:
  CALL anyedge
  AND R0, #ABTN+START
  BEQ di_r
  CALL gomatch
di_r:
  RET

; ---- result screens (match won / lost / ladder cleared): A or Start continues ----
doresult:
  LDW R0, [stimer]
  CMP R0, #0
  BEQ dr_in
  SUB R0, #1
  STW R0, [stimer]
  RET
dr_in:
  CALL anyedge
  AND R0, #ABTN+START
  BEQ dr_r
  LDW R0, [resnext]
  CMP R0, #0
  BEQ dr_t
  CALL gointro
  RET
dr_t:
  CALL gotitle
dr_r:
  RET

; ---- showresult(A1 = headline, A2 = second line, R0 = resnext) ----
showresult:
  STW R0, [resnext]
  MOV R0, #ST_RESULT
  STW R0, [state]
  MOV R0, #40
  STW R0, [stimer]
  CALL clearbg
  CALL clearoam
  MOV R0, #T_GOLD
  STW R0, [txtattr]
  MOV R4, #4
  MOV R5, #8
  CALL print16
  MOV R0, #T_WHITE
  STW R0, [txtattr]
  MOVA A1, A2
  MOV R4, #4
  MOV R5, #13
  CALL print16
  MOV R4, #10
  MOV R5, #19
  LDA A1, #str_push
  CALL print16
  RET

; ---- start a match: difficulty from the rival table (2P uses its own row) ----
gomatch:
  MOV R0, #0
  STB R0, [win0]
  STB R0, [win1]
  LDA A0, #rivtab+40    ; 2-player row
  LDW R0, [mode]
  CMP R0, #0
  BEQ gm_p
  LDW R0, [rival]
  SHL R0, #3
  LDA A0, #rivtab
  ADD A0, R0
gm_p:
  LDB R0, [A0+#0]
  STW R0, [fallbase]
  LDB R0, [A0+#1]
  STW R0, [aidelay]
  LDB R0, [A0+#2]
  STW R0, [aimask]
  LDB R0, [A0+#3]
  STW R0, [ailoose]
  LDB R0, [A0+#4]
  STB R0, [mrate]
  LDB R0, [A0+#5]
  STB R0, [ncol]
  CALL newround
  RET

; ---- newround: fresh wells, shared pair sequence, castle frame ----
newround:
  MOV R0, #ST_PLAY
  STW R0, [state]
  LDW R0, [fallbase]
  STW R0, [fallcur]
  MOV R0, #0
  STW R0, [roundT]
  CALL clearoam
  CALL clearbg
  LDA A0, #artbin+ART_MAP0
  MOV R6, #0            ; BG0 map $10000
  MOV R7, #6            ; priority 3
  CALL loadmap
  MOV R0, #T_GOLD
  STW R0, [txtattr]
  MOV R4, #16
  MOV R5, #0
  LDA A1, #str_next
  CALL print16
  LDA A3, #PL0
  MOV R7, #0
  CALL initplayer
  LDA A3, #PL1
  MOV R7, #1
  CALL initplayer
  ; both wells get the same pairs: one seed, copied
  CALL nextrng
  OR R0, #1
  STW R0, [PL0+PS_SEQ]
  STW R0, [PL1+PS_SEQ]
  LDA A3, #PL0
  CALL genpiece
  LDA A3, #PL1
  CALL genpiece
  MOV R0, #300
  MOV R1, #10
  CALL sfx
  RET

; ---- initplayer(A3 = block, R7 = id) ----
initplayer:
  MOV R1, #0
ip_z:
  MOV R0, #0
  STB R0, [A3+R1]
  ADD R1, #1
  CMP R1, #$40
  BLT ip_z
ip_s:                   ; grid incl. sentinel rows: all $FF
  MOV R0, #$FF
  STB R0, [A3+R1]
  ADD R1, #1
  CMP R1, #$B0
  BLT ip_s
  MOV R1, #0
ip_c:
  MOV R0, #0
  MOV R2, R1
  ADD R2, #MARK
  STB R0, [A3+R2]
  MOV R2, R1
  ADD R2, #MTIM
  STB R0, [A3+R2]
  MOV R2, R1
  ADD R2, #SHAD
  MOV R0, #$FF
  STB R0, [A3+R2]
  MOV R0, R1
  AND R0, #7
  CMP R0, #6
  BGE ip_cn
  MOV R2, R1
  ADD R2, #G
  MOV R0, #0
  STB R0, [A3+R2]       ; a real cell: empty
ip_cn:
  ADD R1, #1
  CMP R1, #96
  BLT ip_c
  STB R7, [A3+#PS_ID]
  MOV R0, #$FF
  STB R0, [A3+#PS_SHOWB]
  MOV R0, #2
  MOV R1, #16
  CMP R7, #0
  BEQ ip_o
  MOV R0, #26
  MOV R1, #208
ip_o:
  STW R0, [A3+#PS_ORGX]
  STW R1, [A3+#PS_SPRX]
  RET

; ================= play =================
doplay:
  CALL startedge
  CMP R0, #0
  BEQ dp_go
  MOV R0, #ST_PAUSE
  STW R0, [state]
  MOV R0, #T_GOLD
  STW R0, [txtattr]
  MOV R4, #15
  MOV R5, #12
  LDA A1, #str_pause
  CALL print16
  RET
dp_go:
  ; pads -> well inputs (solo: the CPU writes PL1's)
  LDW R0, [PL0+PS_IN]
  STW R0, [PL0+PS_PR]
  LDW R0, [P0IN]
  STW R0, [PL0+PS_IN]
  LDW R0, [mode]
  CMP R0, #0
  BEQ dp_p2
  LDA A3, #PL1
  CALL aidrive
  BRA dp_grav
dp_p2:
  LDW R0, [PL1+PS_IN]
  STW R0, [PL1+PS_PR]
  LDW R0, [P1IN]
  STW R0, [PL1+PS_IN]
dp_grav:
  ; siege fatigue: gravity tightens every TIGHTEN frames
  LDW R0, [roundT]
  ADD R0, #1
  STW R0, [roundT]
  CMP R0, #TIGHTEN
  BLT dp_upd
  MOV R0, #0
  STW R0, [roundT]
  LDW R0, [fallcur]
  CMP R0, #FALLMIN+2
  BLT dp_upd
  SUB R0, #2
  STW R0, [fallcur]
dp_upd:
  LDA A3, #PL0
  CALL pupdate
  CALL mortartick
  CALL tickfly
  LDA A3, #PL1
  CALL pupdate
  CALL mortartick
  CALL tickfly
  CALL deathcheck
  LDA A3, #PL0
  CALL paintwell
  CALL drawbasket
  LDA A3, #PL1
  CALL paintwell
  CALL drawbasket
  CALL buildoam
  RET

dopause:
  CALL startedge
  CMP R0, #0
  BEQ dpa_r
  MOV R0, #ST_PLAY
  STW R0, [state]
  MOV R4, #15
  MOV R5, #12
  LDA A1, #str_blank5
  CALL print16
dpa_r:
  RET

; ---- round end: a well has fallen ----
deathcheck:
  MOV R2, #0
  LDB R0, [PL0+PS_STATE]
  CMP R0, #PDEAD
  BNE dc_1
  OR R2, #1
dc_1:
  LDB R0, [PL1+PS_STATE]
  CMP R0, #PDEAD
  BNE dc_2
  OR R2, #2
dc_2:
  CMP R2, #0
  BNE dc_end
  RET
dc_end:
  STW R2, [loser]
  MOV R0, #ST_RDEND
  STW R0, [state]
  MOV R0, #150
  STW R0, [stimer]
  LDA A3, #PL0          ; paint the final wells, then the verdicts over them
  CALL paintwell
  LDA A3, #PL1
  CALL paintwell
  LDW R2, [loser]
  CMP R2, #1
  BNE dc_n1
  LDB R0, [win1]
  ADD R0, #1
  STB R0, [win1]
dc_n1:
  CMP R2, #2
  BNE dc_n2
  LDB R0, [win0]
  ADD R0, #1
  STB R0, [win0]
dc_n2:
  MOV R0, #T_GOLD
  STW R0, [txtattr]
  MOV R4, #2
  MOV R5, #13
  LDA A1, #str_winner
  LDW R2, [loser]
  AND R2, #1
  BEQ dc_v0
  LDA A1, #str_fallen
dc_v0:
  CALL print16
  MOV R4, #26
  MOV R5, #13
  LDA A1, #str_winner
  LDW R2, [loser]
  AND R2, #2
  BEQ dc_v1
  LDA A1, #str_fallen
dc_v1:
  CALL print16
  CALL buildoam
  MOV R0, #900
  MOV R1, #40
  CALL sfx
  MOV R0, #40
  MOV R1, #30
  CALL noise
  RET

dordend:
  LDW R0, [stimer]
  SUB R0, #1
  STW R0, [stimer]
  BEQ de_go
  CMP R0, #90           ; after a beat, A / Start skips ahead
  BGE de_r
  CALL anyedge
  AND R0, #ABTN+START
  BNE de_go
de_r:
  RET
de_go:
  LDB R0, [win0]
  CMP R0, #2
  BGE de_p1
  LDB R0, [win1]
  CMP R0, #2
  BGE de_p2
  CALL newround
  RET
de_p1:
  LDW R0, [mode]
  CMP R0, #0
  BNE de_climb
  LDA A1, #str_p1wins
  LDA A2, #str_blank5
  MOV R0, #0
  CALL showresult
  RET
de_climb:
  LDW R0, [rival]
  ADD R0, #1
  STW R0, [rival]
  CMP R0, #5
  BGE de_champ
  CALL gointro
  RET
de_champ:
  MOV R0, #0
  STW R0, [rival]
  LDA A1, #str_champ
  LDA A2, #str_allfallen
  MOV R0, #0
  CALL showresult
  RET
de_p2:
  LDW R0, [mode]
  CMP R0, #0
  BNE de_lost
  LDA A1, #str_p2wins
  LDA A2, #str_blank5
  MOV R0, #0
  CALL showresult
  RET
de_lost:
  LDA A1, #str_gameover
  LDA A2, #str_retry
  MOV R0, #1
  CALL showresult
  RET

; ================= one well's turn (A3 = block) =================
pupdate:
  LDB R0, [A3+#PS_STATE]
  CMP R0, #PDEAD
  BNE pu_live
  RET
pu_live:
  LDW R7, [A3+#PS_IN]
  LDW R6, [A3+#PS_PR]
  NOT R6
  AND R6, R7
  AND R6, #BBTN
  BEQ pu_auto
  CALL loose
pu_auto:
  LDB R0, [A3+#PS_BASKET]
  CMP R0, #BASKMAX
  BLT pu_disp
  CALL loose
pu_disp:
  LDB R0, [A3+#PS_STATE]
  CMP R0, #PSPAWN
  BNE pu_1
  BRA pspawn
pu_1:
  CMP R0, #PFALL
  BNE pu_2
  BRA pfall
pu_2:
  CMP R0, #PSETTLE
  BNE pu_3
  BRA psettle
pu_3:
  CMP R0, #PFLASH
  BNE pu_r
  BRA pflash
pu_r:
  RET

; ---- SPAWN: the next pair enters at column 2; a blocked mouth means the well falls ----
pspawn:
  MOV R2, #G+2
  LDB R0, [A3+R2]
  CMP R0, #0
  BNE ps_dead
  MOV R2, #G+10
  LDB R0, [A3+R2]
  CMP R0, #0
  BNE ps_dead
  LDB R0, [A3+#PS_N0]
  STB R0, [A3+#PS_C0]
  LDB R0, [A3+#PS_N1]
  STB R0, [A3+#PS_C1]
  CALL genpiece
  MOV R0, #2
  STB R0, [A3+#PS_PX]
  MOV R0, #1
  STB R0, [A3+#PS_PY]
  MOV R0, #0
  STB R0, [A3+#PS_ROT]
  STB R0, [A3+#PS_FALLT]
  STB R0, [A3+#PS_DROPPED]
  STB R0, [A3+#PS_CHAIN]
  STB R0, [A3+#PS_AION]
  MOV R0, #PFALL
  STB R0, [A3+#PS_STATE]
  LDB R0, [A3+#PS_ID]
  CMP R0, #1
  BNE ps_r
  LDW R0, [mode]
  CMP R0, #1
  BNE ps_r
  CALL aiplan
ps_r:
  RET
ps_dead:
  MOV R0, #PDEAD
  STB R0, [A3+#PS_STATE]
  RET

; ---- genpiece: roll the next pair from this well's sequence ----
genpiece:
  CALL seqrng
  CALL pickcol
  STB R0, [A3+#PS_N0]
  CALL seqrng
  CALL pickcol
  STB R0, [A3+#PS_N1]
  LDB R2, [mrate]
  CMP R2, #0
  BEQ gp_r
  CALL seqrng
  SHR R0, #3
  MOV R1, #0
  DIVU R0, R2
  CMP R1, #0
  BNE gp_r
  MOV R0, #7            ; a wet mortar partner
  STB R0, [A3+#PS_N1]
gp_r:
  RET
pickcol:                ; R0 random -> colour 1..ncol
  SHR R0, #5
  MOV R1, #0
  LDB R2, [ncol]
  DIVU R0, R2
  MOV R0, R1
  ADD R0, #1
  RET
seqrng:                 ; xorshift16 on PS_SEQ -> R0
  LDW R0, [A3+#PS_SEQ]
  MOV R1, R0
  SHL R1, #7
  XOR R0, R1
  MOV R1, R0
  SHR R1, #9
  XOR R0, R1
  MOV R1, R0
  SHL R1, #8
  XOR R0, R1
  STW R0, [A3+#PS_SEQ]
  RET

; ---- FALL: turn, shift (auto-repeat), soft drop, gravity, lock ----
pfall:
  LDW R7, [A3+#PS_IN]
  LDW R6, [A3+#PS_PR]
  NOT R6
  AND R6, R7            ; R6 = newly pressed, R7 = held
  MOV R0, R6
  AND R0, #ABTN
  BEQ pf_na
  MOV R0, #1
  CALL turn
pf_na:
  MOV R0, R6
  AND R0, #XBTN+YBTN
  BEQ pf_ny
  MOV R0, #3
  CALL turn
pf_ny:
  MOV R0, R7
  AND R0, #LEFT+RIGHT
  BNE pf_lr
  MOV R0, #0
  STB R0, [A3+#PS_DAS]
  BRA pf_grav
pf_lr:
  MOV R0, R6
  AND R0, #LEFT+RIGHT
  BEQ pf_held
  MOV R0, #0
  STB R0, [A3+#PS_DAS]
  BRA pf_move
pf_held:
  LDB R0, [A3+#PS_DAS]
  ADD R0, #1
  STB R0, [A3+#PS_DAS]
  CMP R0, #10
  BLT pf_grav
  MOV R0, #7            ; repeat every 3 frames
  STB R0, [A3+#PS_DAS]
pf_move:
  LDB R4, [A3+#PS_PX]
  LDB R5, [A3+#PS_PY]
  LDB R3, [A3+#PS_ROT]
  MOV R0, R7
  AND R0, #LEFT
  BEQ pf_rt
  SUB R4, #1
  BRA pf_try
pf_rt:
  ADD R4, #1
pf_try:
  CALL canplace
  CMP R0, #0
  BEQ pf_grav
  STB R4, [A3+#PS_PX]
pf_grav:
  LDB R0, [A3+#PS_FALLT]
  ADD R0, #1
  STB R0, [A3+#PS_FALLT]
  MOV R1, R7
  AND R1, #DOWN
  BEQ pf_norm
  CMP R0, #2
  BGE pf_step
  RET
pf_norm:
  LDW R1, [fallcur]
  CMP R0, R1
  BGE pf_step
  RET
pf_step:
  MOV R0, #0
  STB R0, [A3+#PS_FALLT]
  LDB R4, [A3+#PS_PX]
  LDB R5, [A3+#PS_PY]
  ADD R5, #1
  LDB R3, [A3+#PS_ROT]
  CALL canplace
  CMP R0, #0
  BEQ lockpiece
  STB R5, [A3+#PS_PY]
  RET

; ---- lockpiece: write the pair into the grid, then let it settle ----
lockpiece:
  LDB R4, [A3+#PS_PX]
  LDB R5, [A3+#PS_PY]
  LDB R3, [A3+#PS_ROT]
  MOV R1, R5
  SHL R1, #3
  ADD R1, R4
  LDB R0, [A3+#PS_C0]
  CALL putcell
  MOV R2, R3
  SHL R2, #1
  LDA A0, #partoff
  LDW R2, [A0+R2]
  ADD R1, R2
  LDB R0, [A3+#PS_C1]
  CALL putcell
  MOV R0, #PSETTLE
  STB R0, [A3+#PS_STATE]
  MOV R0, #0
  STB R0, [A3+#PS_TIMER]
  MOV R0, #60
  MOV R1, #3
  CALL noise
  RET
putcell:                ; R0 code -> cell R1 (R1, R3 preserved)
  MOV R2, R1
  ADD R2, #G
  STB R0, [A3+R2]
  CMP R0, #7
  BNE pc_r
  MOV R2, R1
  ADD R2, #MTIM
  MOV R0, #MORTART
  STB R0, [A3+R2]
pc_r:
  RET

; ---- canplace(R4 = col, R5 = row, R3 = turn) -> R0 = 1 if both cells are free.
;      R3, R4, R5 preserved. Sentinels make off-well cells read as full. ----
canplace:
  MOV R1, R5
  SHL R1, #3
  ADD R1, R4
  ADD R1, #G
  LDB R0, [A3+R1]
  CMP R0, #0
  BNE cp_no
  MOV R2, R3
  SHL R2, #1
  LDA A0, #partoff
  LDW R2, [A0+R2]
  ADD R1, R2
  LDB R0, [A3+R1]
  CMP R0, #0
  BNE cp_no
  MOV R0, #1
  RET
cp_no:
  MOV R0, #0
  RET

; ---- turn(R0 = 1 clockwise, 3 counter-clockwise), with a one-cell kick ----
turn:
  LDB R3, [A3+#PS_ROT]
  ADD R3, R0
  AND R3, #3
  LDB R4, [A3+#PS_PX]
  LDB R5, [A3+#PS_PY]
  CALL canplace
  CMP R0, #0
  BNE tn_ok
  CMP R3, #1            ; partner right blocked: step left
  BNE tn_k3
  SUB R4, #1
  BRA tn_try
tn_k3:
  CMP R3, #3            ; partner left blocked: step right
  BNE tn_k2
  ADD R4, #1
  BRA tn_try
tn_k2:
  CMP R3, #2            ; partner below blocked: lift a row (never into row 0)
  BNE tn_no
  CMP R5, #2
  BLT tn_no
  SUB R5, #1
tn_try:
  CALL canplace
  CMP R0, #0
  BEQ tn_no
tn_ok:
  STB R3, [A3+#PS_ROT]
  STB R4, [A3+#PS_PX]
  STB R5, [A3+#PS_PY]
  MOV R0, #160
  MOV R1, #2
  CALL sfx
tn_no:
  RET

; ---- SETTLE: one gravity step every 3 frames; when still, look for clears ----
psettle:
  LDB R0, [A3+#PS_TIMER]
  ADD R0, #1
  STB R0, [A3+#PS_TIMER]
  CMP R0, #3
  BGE pst_go
  RET
pst_go:
  MOV R0, #0
  STB R0, [A3+#PS_TIMER]
  CALL gravpass
  CMP R0, #0
  BEQ pst_chk
  RET
pst_chk:
  CALL findclears
  CMP R0, #0
  BEQ pst_none
  STB R0, [A3+#PS_CLRN]
  LDB R0, [A3+#PS_CHAIN]
  ADD R0, #1
  STB R0, [A3+#PS_CHAIN]
  CALL addload
  CALL markblows
  MOV R0, #PFLASH
  STB R0, [A3+#PS_STATE]
  MOV R0, #FLASHT
  STB R0, [A3+#PS_TIMER]
  LDB R1, [A3+#PS_CHAIN] ; chime rises with the chain
  AND R1, #7
  SHL R1, #4
  MOV R0, #120
  SUB R0, R1
  MOV R1, #14
  CALL sfx
  RET
pst_none:
  MOV R0, #0
  STB R0, [A3+#PS_CHAIN]
  LDB R0, [A3+#PS_PEND]
  CMP R0, #0
  BEQ pst_sp
  LDB R0, [A3+#PS_DROPPED]
  CMP R0, #0
  BNE pst_sp
  CALL droprubble       ; stays in SETTLE so the rubble falls
  RET
pst_sp:
  MOV R0, #PSPAWN
  STB R0, [A3+#PS_STATE]
  RET

; ---- FLASH: blink the clearing stones, then remove them and land the blows ----
pflash:
  LDB R0, [A3+#PS_TIMER]
  SUB R0, #1
  STB R0, [A3+#PS_TIMER]
  BEQ pfl_go
  RET
pfl_go:
  CALL applyclears
  MOV R0, #PSETTLE
  STB R0, [A3+#PS_STATE]
  MOV R0, #0
  STB R0, [A3+#PS_TIMER]
  RET

; ---- gravpass -> R0 = 1 if anything fell one row. Bottom-up, so stacks fall together.
;      Stones, rubble and wet mortar fall; set mortar and glued stones hold. ----
gravpass:
  MOV R6, #0
  MOV R7, #87           ; row 10 col 7 down to cell 0
gv_lp:
  MOV R2, R7
  ADD R2, #G
  LDB R0, [A3+R2]
  CMP R0, #1
  BLT gv_nx
  CMP R0, #8
  BGE gv_nx
  ADD R2, #8
  LDB R1, [A3+R2]
  CMP R1, #0
  BNE gv_nx
  STB R0, [A3+R2]
  SUB R2, #8
  MOV R1, #0
  STB R1, [A3+R2]
  MOV R6, #1
  CMP R0, #7
  BNE gv_nx
  MOV R2, R7            ; wet mortar keeps its timer
  ADD R2, #MTIM
  LDB R0, [A3+R2]
  ADD R2, #8
  STB R0, [A3+R2]
gv_nx:
  SUB R7, #1
  BPL gv_lp
  MOV R0, R6
  RET

; ---- colourof(R0 = code) -> R0 = colour 1..4 (stones and glued stones), else 0 ----
colourof:
  CMP R0, #17
  BLT co_a
  SUB R0, #16
co_a:
  CMP R0, #5
  BLT co_r
  MOV R0, #0
co_r:
  RET

; ---- groupfill(A2 = grid cell 0, R1 = start, R6 = colour) -> R5 = group size, cells
;      in LIST, marked in VISB. Clobbers R0-R5, A0, A1. ----
groupfill:
  LDA A0, #VISB
  MOV R0, #1
  STB R0, [A0+R1]
  LDA A1, #LIST
  STB R1, [A1]
  MOV R5, #1
  MOV R4, #0
gf_lp:
  CMP R4, R5
  BGE gf_done
  LDA A1, #LIST
  LDB R3, [A1+R4]
  ADD R4, #1
  MOV R1, R3
  SUB R1, #8
  CALL gf_try
  MOV R1, R3
  ADD R1, #8
  CALL gf_try
  MOV R1, R3
  SUB R1, #1
  CALL gf_try
  MOV R1, R3
  ADD R1, #1
  CALL gf_try
  BRA gf_lp
gf_done:
  RET
gf_try:
  LDB R0, [A2+R1]
  CALL colourof
  CMP R0, R6
  BNE gt_r
  LDA A0, #VISB
  LDB R0, [A0+R1]
  CMP R0, #0
  BNE gt_r
  MOV R0, #1
  STB R0, [A0+R1]
  LDA A1, #LIST
  STB R1, [A1+R5]
  ADD R5, #1
gt_r:
  RET

; ---- clearvis: zero the 96 visited flags ----
clearvis:
  LDA A0, #VISB
  MOV R1, #0
  MOV R0, #0
cv_lp:
  STB R0, [A0+R1]
  ADD R1, #1
  CMP R1, #96
  BLT cv_lp
  RET

; ---- findclears -> R0 = stones in groups of 4+ (marked MARK = 1) ----
findclears:
  MOV R1, #0
fc_z:
  MOV R2, R1
  ADD R2, #MARK
  MOV R0, #0
  STB R0, [A3+R2]
  ADD R1, #1
  CMP R1, #96
  BLT fc_z
  CALL clearvis
  MOV R0, #0
  STW R0, [fctot]
  MOV R7, #0
fc_lp:
  LDA A0, #VISB
  LDB R0, [A0+R7]
  CMP R0, #0
  BNE fc_nx
  MOV R2, R7
  ADD R2, #G
  LDB R0, [A3+R2]
  CALL colourof
  CMP R0, #0
  BEQ fc_nx
  MOV R6, R0
  MOV R1, R7
  MOVA A2, A3
  ADD A2, #G
  CALL groupfill
  CMP R5, #4
  BLT fc_nx
  LDW R0, [fctot]
  ADD R0, R5
  STW R0, [fctot]
  MOV R4, #0
fc_mk:
  LDA A1, #LIST
  LDB R1, [A1+R4]
  ADD R1, #MARK
  MOV R0, #1
  STB R0, [A3+R1]
  ADD R4, #1
  CMP R4, R5
  BLT fc_mk
fc_nx:
  ADD R7, #1
  CMP R7, #96
  BLT fc_lp
  LDW R0, [fctot]
  RET

; ---- markblows: rubble / mortar touching a clearing stone takes ONE blow (MARK = 2) ----
markblows:
  MOV R7, #0
mb_lp:
  MOV R2, R7
  ADD R2, #MARK
  LDB R0, [A3+R2]
  CMP R0, #1
  BNE mb_nx
  MOV R1, R7
  SUB R1, #8
  CALL mb_try
  MOV R1, R7
  ADD R1, #8
  CALL mb_try
  MOV R1, R7
  SUB R1, #1
  CALL mb_try
  MOV R1, R7
  ADD R1, #1
  CALL mb_try
mb_nx:
  ADD R7, #1
  CMP R7, #96
  BLT mb_lp
  RET
mb_try:
  MOV R2, R1
  ADD R2, #G
  LDB R0, [A3+R2]
  CMP R0, #5
  BLT mt_r
  CMP R0, #10
  BGE mt_r
  MOV R2, R1
  ADD R2, #MARK
  LDB R0, [A3+R2]
  CMP R0, #0
  BNE mt_r
  MOV R0, #2
  STB R0, [A3+R2]
mt_r:
  RET

; ---- applyclears: cleared stones vanish; blows crack / break rubble and set mortar,
;      and wash out wet mortar (+3 basket each) ----
applyclears:
  MOV R7, #0
ac_lp:
  MOV R2, R7
  ADD R2, #MARK
  LDB R0, [A3+R2]
  CMP R0, #0
  BEQ ac_nx
  MOV R1, #0
  STB R1, [A3+R2]
  MOV R2, R7
  ADD R2, #G
  CMP R0, #1
  BNE ac_blow
  STB R1, [A3+R2]
  BRA ac_nx
ac_blow:
  LDB R0, [A3+R2]
  CMP R0, #5
  BNE ac_b8
  MOV R0, #6            ; rubble cracks
  BRA ac_st
ac_b8:
  CMP R0, #8
  BNE ac_b7
  MOV R0, #9            ; set mortar cracks
  BRA ac_st
ac_b7:
  CMP R0, #7
  BNE ac_b0
  MOV R0, #3            ; wet mortar washed out: +3 basket
  CALL addbasket
  MOV R2, R7
  ADD R2, #G
ac_b0:
  MOV R0, #0            ; cracked rubble / cracked set mortar break
ac_st:
  STB R0, [A3+R2]
ac_nx:
  ADD R7, #1
  CMP R7, #96
  BLT ac_lp
  RET

; ---- mortartick: wet mortar dries; when set, it glues its stone neighbours ----
mortartick:
  LDB R0, [A3+#PS_STATE]
  CMP R0, #PDEAD
  BNE mk_go
  RET
mk_go:
  MOV R7, #0
mk_lp:
  MOV R2, R7
  ADD R2, #G
  LDB R0, [A3+R2]
  CMP R0, #7
  BNE mk_nx
  MOV R2, R7
  ADD R2, #MTIM
  LDB R0, [A3+R2]
  SUB R0, #1
  STB R0, [A3+R2]
  BNE mk_nx
  MOV R2, R7
  ADD R2, #G
  MOV R0, #8
  STB R0, [A3+R2]
  MOV R1, R7
  SUB R1, #8
  CALL glue
  MOV R1, R7
  ADD R1, #8
  CALL glue
  MOV R1, R7
  SUB R1, #1
  CALL glue
  MOV R1, R7
  ADD R1, #1
  CALL glue
  MOV R0, #500
  MOV R1, #6
  CALL sfx
mk_nx:
  ADD R7, #1
  CMP R7, #96
  BLT mk_lp
  RET
glue:
  MOV R2, R1
  ADD R2, #G
  LDB R0, [A3+R2]
  CMP R0, #1
  BLT gl_r
  CMP R0, #5
  BGE gl_r
  ADD R0, #16
  STB R0, [A3+R2]
gl_r:
  RET

; ================= the catapult =================
; ---- addload: basket += (cleared - 2) x chain factor ----
addload:
  LDB R0, [A3+#PS_CLRN]
  SUB R0, #2
  LDB R2, [A3+#PS_CHAIN]
  CMP R2, #6
  BLE al_c
  MOV R2, #6
al_c:
  SUB R2, #1
  LDA A0, #chainf
  LDB R2, [A0+R2]
  MULU R0, R2
addbasket:              ; basket = min(BASKMAX, basket + R0)
  LDB R1, [A3+#PS_BASKET]
  ADD R1, R0
  CMP R1, #BASKMAX
  BLE ab_s
  MOV R1, #BASKMAX
ab_s:
  STB R1, [A3+#PS_BASKET]
  RET

; ---- loose: send the basket (+1/4 if 12 or more). It first knocks down rubble
;      heading for us; the rest flies at the rival. ----
loose:
  LDB R0, [A3+#PS_BASKET]
  CMP R0, #0
  BNE lo_go
  RET
lo_go:
  CMP R0, #12
  BLT lo_nb
  MOV R1, R0
  SHR R1, #2
  ADD R0, R1
lo_nb:
  MOV R1, #0
  STB R1, [A3+#PS_BASKET]
  MOV R1, #24
  STB R1, [A3+#PS_CATF]
  PUSH R0
  MOV R0, #30
  MOV R1, #10
  CALL noise
  POP R0
  LDB R1, [A3+#PS_PEND]
  CMP R1, R0
  BLT lo_part
  SUB R1, R0            ; all of it went to knocking down incoming rubble
  STB R1, [A3+#PS_PEND]
  RET
lo_part:
  SUB R0, R1
  MOV R1, #0
  STB R1, [A3+#PS_PEND]
  LDB R1, [A3+#PS_FLY]
  ADD R1, R0
  CMP R1, #PENDMAX
  BLE lo_f
  MOV R1, #PENDMAX
lo_f:
  STB R1, [A3+#PS_FLY]
  MOV R1, #FLYTIME
  STB R1, [A3+#PS_FLYT]
  RET

; ---- tickfly: swing timer, and land the volley on the rival (spilling their basket) ----
tickfly:
  LDB R0, [A3+#PS_CATF]
  CMP R0, #0
  BEQ tf_c
  SUB R0, #1
  STB R0, [A3+#PS_CATF]
tf_c:
  LDB R0, [A3+#PS_FLYT]
  CMP R0, #0
  BNE tf_go
  RET
tf_go:
  SUB R0, #1
  STB R0, [A3+#PS_FLYT]
  BEQ tf_land
  RET
tf_land:
  CALL rivalof
  LDB R0, [A3+#PS_FLY]
  MOV R1, #0
  STB R1, [A3+#PS_FLY]
  LDB R1, [A0+#PS_PEND]
  ADD R1, R0
  CMP R1, #PENDMAX
  BLE tl_c
  MOV R1, #PENDMAX
tl_c:
  STB R1, [A0+#PS_PEND]
  LDB R1, [A0+#PS_BASKET]
  SHR R1, #1
  STB R1, [A0+#PS_BASKET]
  MOV R0, #90
  MOV R1, #16
  CALL noise
  RET
rivalof:                ; A0 = the other well's block
  LDB R0, [A3+#PS_ID]
  CMP R0, #0
  BNE ro_1
  LDA A0, #PL1
  RET
ro_1:
  LDA A0, #PL0
  RET

; ---- droprubble: up to 18 pending stones of rubble, three rows from the top ----
droprubble:
  MOV R0, #1
  STB R0, [A3+#PS_DROPPED]
  LDB R5, [A3+#PS_PEND]
  CMP R5, #18
  BLE dr_n
  MOV R5, #18
dr_n:
  LDB R0, [A3+#PS_PEND]
  SUB R0, R5
  STB R0, [A3+#PS_PEND]
  CALL nextrng
  MOV R1, #0
  MOV R2, #6
  DIVU R0, R2
  MOV R6, R1            ; first column of a short row
  MOV R4, #0
dr_lp:
  CMP R4, R5
  BGE dr_done
  MOV R0, R4
  MOV R1, #0
  MOV R2, #6
  DIVU R0, R2           ; R0 = row from the bottom of the drop, R1 = slot in the row
  ADD R1, R6
  CMP R1, #6
  BLT dr_c
  SUB R1, #6
dr_c:
  MOV R3, #2
  SUB R3, R0
  SHL R3, #3
  ADD R3, R1
  ADD R3, #G
  LDB R0, [A3+R3]
  CMP R0, #0
  BNE dr_nx
  MOV R0, #5
  STB R0, [A3+R3]
dr_nx:
  ADD R4, #1
  BRA dr_lp
dr_done:
  MOV R0, #120
  MOV R1, #12
  CALL noise
  RET

; ================= CPU rival (drives PL1 through a virtual pad) =================
; ---- aiplan: score every reachable (column, turn) for the new pair ----
aiplan:
  MOV R0, #-30000
  STW R0, [aibest]
  MOV R0, #2
  STB R0, [A3+#PS_AITC]
  MOV R0, #0
  STB R0, [A3+#PS_AITR]
  STW R0, [aicol]
  STW R0, [airot]
ap_lp:
  CALL ai_reach
  CMP R0, #0
  BEQ ap_nx
  CALL ai_eval
  LDW R1, [aibest]
  CMP R0, R1
  BLE ap_nx
  STW R0, [aibest]
  LDW R1, [aicol]
  STB R1, [A3+#PS_AITC]
  LDW R1, [airot]
  STB R1, [A3+#PS_AITR]
ap_nx:
  LDW R0, [aicol]
  ADD R0, #1
  STW R0, [aicol]
  CMP R0, #6
  BLT ap_lp
  MOV R0, #0
  STW R0, [aicol]
  LDW R0, [airot]
  ADD R0, #1
  STW R0, [airot]
  CMP R0, #4
  BLT ap_lp
  MOV R0, #1
  STB R0, [A3+#PS_AION]
  LDW R0, [aidelay]     ; a beat to "read" the new pair
  SHL R0, #1
  STB R0, [A3+#PS_AIT]
  RET

; ---- ai_reach -> R0 = 1 if the pair can turn at column 2 and slide to aicol ----
ai_reach:
  LDW R3, [airot]
  MOV R4, #2
  MOV R5, #1
ar_lp:
  CALL canplace
  CMP R0, #0
  BEQ ar_no
  LDW R1, [aicol]
  CMP R4, R1
  BEQ ar_yes
  BLT ar_inc
  SUB R4, #1
  BRA ar_lp
ar_inc:
  ADD R4, #1
  BRA ar_lp
ar_yes:
  MOV R0, #1
ar_no:
  RET

; ---- ai_eval -> R0 = score of dropping the pair at (aicol, airot) ----
ai_eval:
  MOV R1, #0
ae_cp:                  ; scratch copy of the well, sentinel rows included
  MOV R2, R1
  ADD R2, #$40
  LDB R0, [A3+R2]
  LDA A0, #SCR
  STB R0, [A0+R1]
  ADD R1, #1
  CMP R1, #112
  BLT ae_cp
  MOV R0, #0
  STW R0, [aiscore]
  LDW R3, [airot]
  LDW R4, [aicol]
  MOV R0, R3
  AND R0, #1
  BNE ae_h
  ; vertical: both stones in one column
  STW R4, [aecol]
  CALL landrow          ; R5 = bottom row
  CMP R5, #1
  BGE ae_vok
  BRA ae_bad
ae_vok:
  LDB R0, [A3+#PS_C0]   ; turn 0: pivot at the bottom
  LDB R1, [A3+#PS_C1]
  CMP R3, #0
  BEQ ae_v
  LDB R0, [A3+#PS_C1]
  LDB R1, [A3+#PS_C0]
ae_v:
  STW R1, [aecode]      ; top stone
  STW R5, [aerow]
  CALL ae_put           ; bottom stone (R0)
  LDW R0, [aerow]
  SUB R0, #1
  STW R0, [aerow]
  LDW R0, [aecode]
  CALL ae_put
  CALL ae_score         ; top stone
  LDW R1, [aerow]
  ADD R1, #1
  STW R1, [aerow]
  SHL R1, #3
  ADD R1, R4
  LDA A0, #SCR+8
  LDB R0, [A0+R1]
  STW R0, [aecode]
  CALL ae_score         ; bottom stone
  BRA ae_noise
ae_h:
  ; horizontal: pivot at aicol, partner beside it; each lands on its own
  MOV R0, R4
  ADD R0, #1
  CMP R3, #1
  BEQ ae_hp
  SUB R0, #2
ae_hp:
  PUSH R0               ; partner column
  STW R4, [aecol]
  CALL landrow
  CMP R5, #0
  BLT ae_hbad
  STW R5, [aerow]
  LDB R0, [A3+#PS_C0]
  STW R0, [aecode]
  CALL ae_put
  CALL ae_score
  POP R4
  STW R4, [aecol]
  CALL landrow
  CMP R5, #0
  BLT ae_bad
  STW R5, [aerow]
  LDB R0, [A3+#PS_C1]
  STW R0, [aecode]
  CALL ae_put
  CALL ae_score
  BRA ae_noise
ae_hbad:
  POP R4
  BRA ae_bad
ae_noise:
  CALL nextrng
  LDW R1, [aimask]
  AND R0, R1
  LDW R1, [aiscore]
  ADD R0, R1
  RET
ae_bad:
  MOV R0, #-20000
  RET

; ---- landrow(R4 = column) -> R5 = row a stone dropped there comes to rest (-1 = full) ----
landrow:
  MOV R5, #-1
lr_lp:
  MOV R1, R5
  ADD R1, #1
  SHL R1, #3
  ADD R1, R4
  LDA A0, #SCR+8
  LDB R0, [A0+R1]
  CMP R0, #0
  BNE lr_r
  ADD R5, #1
  BRA lr_lp
lr_r:
  RET

; ---- ae_put(R0 = code) at (aerow, aecol) in the scratch well ----
ae_put:
  LDW R1, [aerow]
  SHL R1, #3
  LDW R2, [aecol]
  ADD R1, R2
  LDA A0, #SCR+8
  STB R0, [A0+R1]
  RET

; ---- ae_score: the stone at (aerow, aecol), code aecode. Group size counts most
;      (a clear is worth a lot), height costs, the spawn column costs more. ----
ae_score:
  PUSH R4
  LDW R0, [aecode]
  CALL colourof
  CMP R0, #0
  BEQ as_h
  MOV R6, R0
  CALL clearvis
  LDW R1, [aerow]
  SHL R1, #3
  LDW R2, [aecol]
  ADD R1, R2
  LDA A2, #SCR+8
  CALL groupfill        ; R5 = group size
  CMP R5, #4
  BLT as_small
  MOV R0, R5
  SHL R0, #3
  ADD R0, #200
  BRA as_add
as_small:
  MOV R0, R5
  MULU R0, R5
  MOV R1, R0
  SHL R0, #2
  ADD R0, R1
  ADD R0, R1            ; n*n*6
as_add:
  LDW R1, [aiscore]
  ADD R1, R0
  STW R1, [aiscore]
as_h:
  LDW R0, [aerow]
  CMP R0, #6
  BGE as_col
  MOV R1, #6
  SUB R1, R0
  MOV R0, R1
  SHL R0, #4
  SHL R1, #2
  ADD R0, R1            ; (6 - row) * 20
  LDW R1, [aiscore]
  SUB R1, R0
  STW R1, [aiscore]
as_col:
  LDW R0, [aecol]
  CMP R0, #2
  BNE as_r
  LDW R0, [aerow]
  CMP R0, #4
  BGE as_r
  LDW R1, [aiscore]
  SUB R1, #150
  STW R1, [aiscore]
as_r:
  POP R4
  RET

; ---- aidrive: one virtual-pad word for PL1 per frame ----
aidrive:
  LDW R0, [A3+#PS_IN]
  STW R0, [A3+#PS_PR]
  MOV R7, #0
  ; loose at the threshold, or straight away when rubble is coming
  LDB R0, [A3+#PS_BASKET]
  CMP R0, #0
  BEQ ad_nl
  LDW R1, [ailoose]
  CMP R0, R1
  BGE ad_l
  LDB R1, [A3+#PS_PEND]
  CMP R1, #0
  BEQ ad_nl
ad_l:
  LDW R1, [A3+#PS_PR]
  AND R1, #BBTN
  BNE ad_nl
  OR R7, #BBTN
ad_nl:
  LDB R0, [A3+#PS_STATE]
  CMP R0, #PFALL
  BNE ad_out
  LDB R0, [A3+#PS_AION]
  CMP R0, #0
  BEQ ad_out
  LDB R0, [A3+#PS_AIT]
  CMP R0, #0
  BEQ ad_act
  SUB R0, #1
  STB R0, [A3+#PS_AIT]
  BRA ad_out
ad_act:
  LDB R0, [A3+#PS_ROT]
  LDB R1, [A3+#PS_AITR]
  CMP R0, R1
  BEQ ad_mv
  LDW R0, [aidelay]
  STB R0, [A3+#PS_AIT]
  OR R7, #ABTN
  BRA ad_out
ad_mv:
  LDB R0, [A3+#PS_PX]
  LDB R1, [A3+#PS_AITC]
  CMP R0, R1
  BEQ ad_drop
  LDW R2, [aidelay]
  STB R2, [A3+#PS_AIT]
  CMP R0, R1
  BLT ad_r
  OR R7, #LEFT
  BRA ad_out
ad_r:
  OR R7, #RIGHT
  BRA ad_out
ad_drop:
  OR R7, #DOWN
ad_out:
  STW R7, [A3+#PS_IN]
  RET

; ================= drawing =================
; ---- paintwell: repaint every cell whose look changed ----
paintwell:
  MOV R7, #0
pw_lp:
  MOV R0, R7
  AND R0, #7
  CMP R0, #6
  BGE pw_nx
  CALL lookfor
  MOV R2, R7
  ADD R2, #SHAD
  LDB R1, [A3+R2]
  CMP R0, R1
  BEQ pw_nx
  STB R0, [A3+R2]
  CALL paintlook
pw_nx:
  ADD R7, #1
  CMP R7, #96
  BLT pw_lp
  RET

; ---- lookfor(R7 = cell) -> R0 = cell look (ART_CELLS index) ----
lookfor:
  MOV R2, R7
  ADD R2, #G
  LDB R0, [A3+R2]
  LDB R1, [A3+#PS_STATE]
  CMP R1, #PFLASH
  BNE lf_n
  MOV R2, R7
  ADD R2, #MARK
  LDB R1, [A3+R2]
  CMP R1, #1
  BNE lf_n
  LDB R1, [A3+#PS_TIMER]
  AND R1, #4
  BEQ lf_n
  MOV R0, #12           ; flash
  RET
lf_n:
  CMP R0, #7
  BNE lf_t
  MOV R2, R7
  ADD R2, #MTIM
  LDB R1, [A3+R2]
  CMP R1, #80
  BGE lf_m1
  MOV R0, #11           ; nearly set
  RET
lf_m1:
  CMP R1, #160
  BGE lf_t
  MOV R0, #10           ; drying
  RET
lf_t:
  CMP R0, #17
  BLT lf_r
  SUB R0, #4            ; glued 17..20 -> looks 13..16
lf_r:
  RET

; ---- paintlook(R0 = look, R7 = cell): the 2x2 BG0 cluster. R7 preserved. ----
paintlook:
  PUSH R7
  SHL R0, #3
  LDA A0, #artbin+ART_CELLS
  ADD A0, R0
  MOV R6, R7
  AND R6, #7
  SHL R6, #1
  LDW R1, [A3+#PS_ORGX]
  ADD R6, R1
  SHR R7, #3
  SHL R7, #1
  ADD R7, #3
  CALL paintquad
  POP R7
  RET

; ---- drawbasket: the basket count over the catapult (gold once it earns the bonus) ----
drawbasket:
  LDB R0, [A3+#PS_BASKET]
  LDB R1, [A3+#PS_SHOWB]
  CMP R0, R1
  BNE db_go
  RET
db_go:
  STB R0, [A3+#PS_SHOWB]
  MOV R1, #T_WHITE
  CMP R0, #12
  BLT db_c
  MOV R1, #T_GOLD
db_c:
  STW R1, [txtattr]
  MOV R4, #15
  LDB R1, [A3+#PS_ID]
  CMP R1, #0
  BEQ db_x
  MOV R4, #21
db_x:
  MOV R5, #18
  MOV R1, #0
  MOV R2, #10
  DIVU R0, R2           ; R0 tens, R1 ones
  PUSH R1
  MOV R2, #26           ; blank tens under 10
  CMP R0, #0
  BEQ db_t
  MOV R2, R0
  ADD R2, #27
db_t:
  CALL glyph16
  POP R2
  ADD R2, #27
  ADD R4, #2
  CALL glyph16
  RET

; ---- buildoam: every sprite, every frame ----
buildoam:
  MOV R0, #0
  STW R0, [OAM_INDEX]
  STW R0, [nspr]
  LDA A3, #PL0
  CALL spr_player
  LDA A3, #PL1
  CALL spr_player
  CALL spr_crowns
bo_pad:
  LDW R0, [nspr]
  CMP R0, #40
  BGE bo_d
  ADD R0, #1
  STW R0, [nspr]
  CALL emitoff
  BRA bo_pad
bo_d:
  RET

spr_player:
  LDB R0, [A3+#PS_STATE]
  CMP R0, #PFALL
  BNE sp_next
  ; the falling pair
  LDB R4, [A3+#PS_PX]
  LDB R5, [A3+#PS_PY]
  LDB R3, [A3+#PS_C0]
  CALL spr_stone
  LDB R3, [A3+#PS_ROT]
  SHL R3, #1
  LDA A0, #partdx
  LDW R0, [A0+R3]
  LDB R4, [A3+#PS_PX]
  ADD R4, R0
  LDA A0, #partdy
  LDW R0, [A0+R3]
  LDB R5, [A3+#PS_PY]
  ADD R5, R0
  LDB R3, [A3+#PS_C1]
  CALL spr_stone
sp_next:
  ; next pair in the niche
  MOV R0, #128
  LDB R1, [A3+#PS_ID]
  CMP R1, #0
  BEQ sp_nx
  MOV R0, #176
sp_nx:
  PUSH R0
  MOV R1, #32
  LDB R3, [A3+#PS_N1]
  CALL spr_stonexy
  POP R0
  MOV R1, #48
  LDB R3, [A3+#PS_N0]
  CALL spr_stonexy
  ; catapult: swing, thrown, then loaded / empty
  MOV R5, #2
  LDB R0, [A3+#PS_CATF]
  CMP R0, #16
  BGE sp_cf
  MOV R5, #3
  CMP R0, #0
  BNE sp_cf
  MOV R5, #1
  LDB R0, [A3+#PS_BASKET]
  CMP R0, #0
  BEQ sp_cf
  MOV R5, #0
sp_cf:
  SHL R5, #4
  ADD R5, #A_CATA
  MOV R0, #122
  MOV R6, #$20+B_CATA
  LDB R1, [A3+#PS_ID]
  CMP R1, #0
  BEQ sp_cx
  MOV R0, #166
  MOV R6, #$60+B_CATA
sp_cx:
  MOV R1, #180
  CALL emit
  ; incoming rubble: a boulder per 6, a pebble per 1, at most 6 icons
  LDB R0, [A3+#PS_PEND]
  MOV R1, #0
  MOV R2, #6
  DIVU R0, R2
  MOV R7, R0            ; boulders
  PUSH R1               ; pebbles
  LDW R4, [A3+#PS_SPRX]
  MOV R3, #0            ; icons drawn
sp_bl:
  CMP R7, #0
  BEQ sp_pb
  CMP R3, #6
  BGE sp_ic
  MOV R0, R4
  MOV R1, #-2
  MOV R5, #A_BOULDER
  MOV R6, #$10+B_WELL
  CALL emit
  ADD R4, #16
  ADD R3, #1
  SUB R7, #1
  BRA sp_bl
sp_pb:
  POP R7
  PUSH R7
sp_pl:
  CMP R7, #0
  BEQ sp_ic
  CMP R3, #6
  BGE sp_ic
  MOV R0, R4
  MOV R1, #-2
  MOV R5, #A_PEBBLE
  MOV R6, #$10+B_WELL
  CALL emit
  ADD R4, #16
  ADD R3, #1
  SUB R7, #1
  BRA sp_pl
sp_ic:
  POP R7
  ; the volley in flight
  LDB R0, [A3+#PS_FLYT]
  CMP R0, #0
  BEQ sp_r
  MOV R1, #FLYTIME
  SUB R1, R0
  SHL R1, #2
  LDA A0, #artbin+ART_ARC
  ADD A0, R1
  LDW R2, [A0+#0]       ; dx
  LDW R1, [A0+#2]       ; dy
  ADD R1, #172
  LDB R3, [A3+#PS_ID]
  CMP R3, #0
  BNE sp_v1
  MOV R0, #132
  ADD R0, R2
  BRA sp_ve
sp_v1:
  MOV R0, #172
  SUB R0, R2
sp_ve:
  MOV R5, #A_BOULDER
  MOV R6, #$10+B_WELL
  CALL emit
sp_r:
  RET

; ---- spr_stone(R4 = col, R5 = row, R3 = code) in this well; spr_stonexy(R0, R1, R3) ----
spr_stone:
  MOV R0, R4
  SHL R0, #4
  LDW R1, [A3+#PS_SPRX]
  ADD R0, R1
  MOV R1, R5
  SHL R1, #4
  ADD R1, #24
spr_stonexy:
  CMP R3, #7
  BNE ss_c
  MOV R5, #A_STONE+16
  MOV R6, #$10+B_WELL
  BRA emit
ss_c:
  MOV R5, R3
  SUB R5, #1
  SHL R5, #2
  ADD R5, #A_STONE
  MOV R6, R3            ; stone bank = colour
  ADD R6, #$10
  BRA emit

; ---- round crowns: two per player in the middle panel ----
spr_crowns:
  MOV R7, #0
sc_lp:
  MOV R0, R7
  AND R0, #1
  SHL R0, #4
  ADD R0, #124
  LDB R3, [win0]
  CMP R7, #2
  BLT sc_p
  ADD R0, #40
  LDB R3, [win1]
sc_p:
  MOV R2, R7
  AND R2, #1
  MOV R5, #A_CROWN
  CMP R3, R2
  BGT sc_lit
  ADD R5, #4            ; dim crown
sc_lit:
  MOV R1, #72
  MOV R6, #$10+B_CROWN
  CALL emit
  ADD R7, #1
  CMP R7, #4
  BLT sc_lp
  RET

; ---- emit(R0 = x, R1 = y, R5 = tile, R6 = attr lo): one enabled sprite ----
emit:
  CALL emittile
  LDW R2, [nspr]
  ADD R2, #1
  STW R2, [nspr]
  RET
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
  MOV R2, #$86
  STB R2, [OAM_DATA]    ; attr hi: enable | priority 6 (over BG0)
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
  STB R2, [OAM_DATA]
  RET

; ---- glyph16(R2 = glyph 0-25 A-Z, 26 blank, 27-36 0-9; R4, R5 = tile x, y): one 16x16
;      glyph in the txtattr colour. R4-R7 preserved. ----
glyph16:
  PUSH R7
  MOV R6, #0
  MOV R7, #0
  CMP R2, #26
  BEQ g16_go
  BLT g16_l
  SUB R2, #1
g16_l:
  SHL R2, #2
  ADD R2, #A_FONT
  LDW R3, [txtattr]
  OR R2, R3
  MOV R6, R2
  MOV R7, #1
g16_go:
  MOV R0, R4
  MOV R1, R5
  MOV R2, R6
  CALL settile
  ADD R6, R7
  MOV R0, R4
  ADD R0, #1
  MOV R1, R5
  MOV R2, R6
  CALL settile
  ADD R6, R7
  MOV R0, R4
  MOV R1, R5
  ADD R1, #1
  MOV R2, R6
  CALL settile
  ADD R6, R7
  MOV R0, R4
  ADD R0, #1
  MOV R1, R5
  ADD R1, #1
  MOV R2, R6
  CALL settile
  POP R7
  RET

; ---- print16(R4 = tile x, R5 = tile y, A1 = glyph string ending $FF) ----
print16:
  LDB R2, [A1]
  CMP R2, #$FF
  BEQ p16_d
  CALL glyph16
  ADD R4, #2
  INC A1
  BRA print16
p16_d:
  RET

; ---- paintquad(A0 = 4 BG0 entries, R6 = tile x, R7 = tile y) ----
paintquad:
  LDW R2, [A0]
  MOV R0, R6
  MOV R1, R7
  CALL settile
  LDW R2, [A0+#2]
  MOV R0, R6
  ADD R0, #1
  MOV R1, R7
  CALL settile
  LDW R2, [A0+#4]
  MOV R0, R6
  MOV R1, R7
  ADD R1, #1
  CALL settile
  LDW R2, [A0+#6]
  MOV R0, R6
  ADD R0, #1
  MOV R1, R7
  ADD R1, #1
  CALL settile
  RET

; ---- settile(R0 = tile x, R1 = tile y, R2 = entry): one BG0 map entry, priority 3 ----
settile:
  MOV R3, R1
  SHL R3, #6
  ADD R3, R0
  SHL R3, #2
  STB R3, [VRAM_ADDR]
  MOV R0, R3
  SHR R0, #8
  STB R0, [VRAM_ADDR+1]
  MOV R0, #1
  STB R0, [VRAM_ADDR+2]
  STB R2, [VRAM_DATA]
  MOV R0, R2
  SHR R0, #8
  STB R0, [VRAM_DATA]
  MOV R0, #6
  STB R0, [VRAM_DATA]
  MOV R0, #0
  STB R0, [VRAM_DATA]
  RET

; ---- clearbg: BG0 to blank over the visible 40 x 28 ----
clearbg:
  MOV R5, #0
cb_y:
  MOV R4, #0
cb_x:
  MOV R0, R4
  MOV R1, R5
  MOV R2, #0
  CALL settile
  ADD R4, #1
  CMP R4, #40
  BLT cb_x
  ADD R5, #1
  CMP R5, #28
  BLT cb_y
  RET

; ---- clearoam: disable all 128 sprites ----
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

; ---- loadmap(A0 = 40x28 u16 entries, R6 = map mid byte base ($00 BG0, $40 BG1),
;      R7 = entry byte 2 (priority bits)) ----
loadmap:
  MOV R5, #0
lm_row:
  MOV R0, #0
  STB R0, [VRAM_ADDR]
  MOV R0, R5
  ADD R0, R6
  STB R0, [VRAM_ADDR+1]
  MOV R0, #1
  STB R0, [VRAM_ADDR+2]
  MOV R1, #40
lm_col:
  LDW R0, [A0]
  STB R0, [VRAM_DATA]
  SHR R0, #8
  STB R0, [VRAM_DATA]
  STB R7, [VRAM_DATA]
  MOV R0, #0
  STB R0, [VRAM_DATA]
  ADD A0, #2
  SUB R1, #1
  BNE lm_col
  ADD R5, #1
  CMP R5, #28
  BLT lm_row
  RET

; ---- dmago(A0 = ROM pointer to a 3-byte source address, R0 = dst, R1 = len, R2 = space) ----
dmago:
  PUSH R0
  LDB R0, [A0+#0]
  STB R0, [DMA_SRC]
  LDB R0, [A0+#1]
  STB R0, [DMA_SRC+1]
  LDB R0, [A0+#2]
  STB R0, [DMA_SRC+2]
  POP R0
  STW R0, [DMA_DST]
  STW R1, [DMA_LEN]
  STB R2, [DMA_MODE]
  MOV R0, #1
  STB R0, [DMA_CTRL]
  RET

; ---- waitframe: WAIT also returns after every hblank IRQ, so wait for FRAME to move ----
waitframe:
  LDW R1, [FRAMEREG]
wf_lp:
  WAIT
  LDW R0, [FRAMEREG]
  CMP R0, R1
  BEQ wf_lp
  RET

; ---- hblank: palette entry 0 for the NEXT line from the sky table ----
hblank:
  PUSH R0
  PUSHA A0
  LDW R0, [SCANLINE]
  ADD R0, #1
  CMP R0, #224
  BLT hb_line
  MOV R0, #0
hb_line:
  SHL R0, #1
  LDA A0, #artbin+ART_SKY
  ADD A0, R0
  MOV R0, #0
  STB R0, [PAL_INDEX]
  LDW R0, [A0]
  STW R0, [PAL_DATA]
  POPA A0
  POP R0
  IRET

readpads:
  LDW R0, [P0IN]
  STW R0, [P0PR]
  LDW R0, [P1IN]
  STW R0, [P1PR]
  LDW R0, [INPUT0]
  STW R0, [P0IN]
  LDW R0, [INPUT1]
  STW R0, [P1IN]
  RET

; ---- startedge -> R0 = 1 if either pad pressed Start this frame ----
startedge:
  CALL anyedge
  AND R0, #START
  BEQ se_r
  MOV R0, #1
se_r:
  RET

; ---- sound: sfx(R0 = period, R1 = frames) on SQ0; noise(R0 = period, R1 = frames) ----
sfx:
  STW R0, [SQ0_PERIOD]
  MOV R0, #10
  STB R0, [SQ0_VOL]
  MOV R0, #1
  STB R0, [SQ0_CTRL]
  STW R1, [sfxT]
  RET
noise:
  STW R0, [NOISE_PERIOD]
  MOV R0, #9
  STB R0, [NOISE_VOL]
  MOV R0, #1
  STB R0, [NOISE_CTRL]
  STW R1, [noiseT]
  RET
sfxtick:
  LDW R0, [sfxT]
  CMP R0, #0
  BEQ st_n
  SUB R0, #1
  STW R0, [sfxT]
  BNE st_n
  MOV R0, #0
  STB R0, [SQ0_CTRL]
st_n:
  LDW R0, [noiseT]
  CMP R0, #0
  BEQ st_r
  SUB R0, #1
  STW R0, [noiseT]
  BNE st_r
  MOV R0, #0
  STB R0, [NOISE_CTRL]
st_r:
  RET

; ---- nextrng (xorshift16) -> R0 ----
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

; ================= tables =================
partoff:                ; partner cell offset by turn: above, right, below, left
  DW $FFF8, 1, 8, $FFFF
partdx:
  DW 0, 1, 0, $FFFF
partdy:
  DW $FFFF, 0, 1, 0
chainf:                 ; basket load factor by chain step
  DB 1, 2, 3, 5, 8, 12
; rival table, 8 bytes each: fall, aidelay, aimask, ailoose, mortar 1-in-N, colours, -, -
rivtab:
  DB 40, 14, 255, 4, 0, 3, 0, 0     ; 1 Squire Pell: slow, careless, three colours
  DB 34, 10, 63, 8, 0, 4, 0, 0      ; 2 Sister Maud
  DB 30, 7, 31, 10, 12, 4, 0, 0     ; 3 Reeve Tamsin: mortar arrives
  DB 24, 5, 15, 14, 10, 4, 0, 0     ; 4 Lord Garrow
  DB 18, 3, 7, 18, 8, 4, 0, 0       ; 5 Iron Margrave
  DB 32, 6, 15, 10, 12, 4, 0, 0     ; 2 players

; --- glyph strings (0-25 = A-Z, 26 = space, 27-36 = 0-9, $FF = end) ---
str_title:
  DB 18,8,4,6,4,18,19,14,13,4,$FF                 ; SIEGESTONE
str_solo:
  DB 0,26,18,14,11,14,26,11,0,3,3,4,17,$FF        ; A SOLO LADDER
str_duo:
  DB 1,26,19,22,14,26,15,11,0,24,4,17,18,$FF      ; B TWO PLAYERS
str_next:
  DB 13,4,23,19,$FF                               ; NEXT
str_pause:
  DB 15,0,20,18,4,$FF                             ; PAUSE
str_blank5:
  DB 26,26,26,26,26,$FF
str_winner:
  DB 22,8,13,13,4,17,$FF                          ; WINNER
str_fallen:
  DB 5,0,11,11,4,13,$FF                           ; FALLEN
str_rival:
  DB 17,8,21,0,11,26,$FF                          ; RIVAL_
str_push:
  DB 15,20,18,7,26,18,19,0,17,19,$FF              ; PUSH START
str_gameover:
  DB 26,26,26,26,6,0,12,4,26,14,21,4,17,$FF       ; GAME OVER (centred in 16)
str_retry:
  DB 26,26,26,26,19,17,24,26,0,6,0,8,13,$FF       ; TRY AGAIN
str_champ:
  DB 26,26,26,26,2,7,0,12,15,8,14,13,$FF          ; CHAMPION
str_allfallen:
  DB 26,11,0,3,3,4,17,26,2,11,4,0,17,4,3,$FF      ; LADDER CLEARED
str_p1wins:
  DB 26,26,15,11,0,24,4,17,26,28,26,22,8,13,18,$FF ; PLAYER 1 WINS
str_p2wins:
  DB 26,26,15,11,0,24,4,17,26,29,26,22,8,13,18,$FF ; PLAYER 2 WINS
; rival names, centred in 16 glyphs, 32-byte slots
str_names:
  DB 26,26,18,16,20,8,17,4,26,15,4,11,11,26,26,26,$FF       ; SQUIRE PELL
  DB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
  DB 26,26,18,8,18,19,4,17,26,12,0,20,3,26,26,26,$FF        ; SISTER MAUD
  DB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
  DB 26,26,17,4,4,21,4,26,19,0,12,18,8,13,26,26,$FF         ; REEVE TAMSIN
  DB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
  DB 26,26,11,14,17,3,26,6,0,17,17,14,22,26,26,26,$FF       ; LORD GARROW
  DB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
  DB 26,8,17,14,13,26,12,0,17,6,17,0,21,4,26,26,$FF         ; IRON MARGRAVE
  DB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

; --- 16-bit art: 24-bit DMA source pointers (dmago reads these) ---
artPtrs:
  DA artbin+ART_TILES
  DA artbin+ART_PAL

; --- the art binary (examples/siegestone/gen_art.js) ---
artbin:
  INCBIN "art.bin"
