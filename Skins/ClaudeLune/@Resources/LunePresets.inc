; ClaudeLune - theme palettes and size presets
; Lunez (luneswan). MIT licence - see LICENSE.txt.
;
; Selected by Theme and Size in LuneSettings.inc. Update-LuneUsage.ps1 resolves
; the pair into LuneResolved.inc under generic names, so no layout file ever has
; to know which preset is active, and adding a theme is one block with the same
; twelve suffixes.

[Variables]

; ============================================================ THEMES ==========
; Suffixes: Bg Stroke Text Dim Bright Accent Track Normal Scoped Warn Crit Off

; Dark - the default. Charcoal panel, cool blue accent.
DarkBg=22,23,28
DarkStroke=255,255,255,18
DarkText=228,229,235,255
DarkDim=132,136,150,255
DarkBright=255,255,255,255
DarkAccent=120,170,255,255
DarkTrack=255,255,255,32
DarkNormal=110,175,255,255
DarkScoped=178,132,255,255
DarkWarn=255,178,72,255
DarkCrit=255,94,94,255
DarkOff=255,255,255,26

; Amoled - true black, for OLED panels. Set Opacity=255 to get real black.
AmoledBg=0,0,0
AmoledStroke=255,255,255,22
AmoledText=236,236,240,255
AmoledDim=120,120,130,255
AmoledBright=255,255,255,255
AmoledAccent=0,224,255,255
AmoledTrack=255,255,255,30
AmoledNormal=0,224,255,255
AmoledScoped=190,120,255,255
AmoledWarn=255,190,60,255
AmoledCrit=255,72,88,255
AmoledOff=255,255,255,20

; Glass - low-opacity panel meant to sit over a wallpaper.
GlassBg=30,32,42
GlassStroke=255,255,255,40
GlassText=255,255,255,255
GlassDim=214,218,232,190
GlassBright=255,255,255,255
GlassAccent=150,200,255,255
GlassTrack=255,255,255,55
GlassNormal=150,200,255,235
GlassScoped=200,160,255,235
GlassWarn=255,200,110,235
GlassCrit=255,130,130,235
GlassOff=255,255,255,30

; Light - for pale wallpapers.
LightBg=248,248,250
LightStroke=0,0,0,26
LightText=32,34,42,255
LightDim=118,122,136,255
LightBright=12,14,20,255
LightAccent=40,110,230,255
LightTrack=0,0,0,34
LightNormal=48,120,240,255
LightScoped=140,80,230,255
LightWarn=214,132,20,255
LightCrit=214,52,60,255
LightOff=0,0,0,22

; Clay - warm neutral, the closest to Claude's own palette.
ClayBg=32,28,26
ClayStroke=255,240,230,20
ClayText=238,230,224,255
ClayDim=158,146,138,255
ClayBright=255,250,246,255
ClayAccent=217,119,87,255
ClayTrack=255,240,230,34
ClayNormal=217,119,87,255
ClayScoped=196,154,108,255
ClayWarn=224,164,72,255
ClayCrit=226,88,74,255
ClayOff=255,240,230,24

; Matrix - single-hue green.
MatrixBg=8,14,10
MatrixStroke=0,255,120,30
MatrixText=190,255,214,255
MatrixDim=88,150,110,255
MatrixBright=225,255,236,255
MatrixAccent=0,255,140,255
MatrixTrack=0,255,120,40
MatrixNormal=0,230,130,255
MatrixScoped=120,255,190,255
MatrixWarn=220,255,90,255
MatrixCrit=255,110,90,255
MatrixOff=0,255,120,22

; iOS - the look of the Limits app: near-black card, iOS blue bars.
iOSBg=28,28,30
iOSStroke=255,255,255,10
iOSText=255,255,255,255
iOSDim=142,142,147,255
iOSBright=255,255,255,255
iOSAccent=10,132,255,255
iOSTrack=120,120,128,90
iOSNormal=10,132,255,255
iOSScoped=191,90,242,255
iOSWarn=255,159,10,255
iOSCrit=255,69,58,255
iOSOff=120,120,128,60

; ============================================================= SIZES ==========
; -- luneswan --
; A preset states intent, not pixel positions. Row pitch, header offset and panel
; height are all DERIVED in Update-LuneUsage.ps1 from the type size, the bar
; thickness and Gap, then written to LuneResolved.inc. That is what lets the
; Height and Row spacing settings move the whole panel; while these presets
; carried literal row positions, nothing in the settings window could reach them.
;
;   W        panel width in pixels
;   Pad      side padding; the header offset and bottom padding follow it
;   Bar      bar thickness
;   Gap      vertical breathing room between rows - the base every gap scales from
;   Title    header font size
;   Label    row label font size
;   Small    caption font size
;   Detail   1 draws a "resets ..." caption under each bar
;   Account  1 draws the account footer line
;   WideRow  1 selects the single-band arrangement
;   Trend    1 draws the seven-day trend strip
;   LogoPx   one cell of the pixel mark, in pixels

; Small - three bars and the numbers, nothing else.
SmallW=200
SmallPad=12
SmallBar=6
SmallGap=8
SmallTitle=10
SmallLabel=9
SmallSmall=8
SmallDetail=0
SmallAccount=0
SmallWideRow=0
SmallTrend=0
SmallLogoPx=2

; Normal - the default. Countdown under each bar.
NormalW=272
NormalPad=15
NormalBar=7
NormalGap=12
NormalTitle=12
NormalLabel=10
NormalSmall=9
NormalDetail=1
NormalAccount=0
NormalWideRow=0
NormalTrend=0
NormalLogoPx=2

; Wide - short and long, label and bar on one line.
WideW=420
WidePad=16
WideBar=8
WideGap=10
WideTitle=12
WideLabel=10
WideSmall=9
WideDetail=0
WideAccount=0
WideWideRow=1
WideTrend=0
WideLogoPx=2

; Large - everything, including reset stamps, the trend and the account line.
LargeW=340
LargePad=18
LargeBar=9
LargeGap=14
LargeTitle=14
LargeLabel=12
LargeSmall=10
LargeDetail=1
LargeAccount=1
LargeWideRow=0
LargeTrend=1
LargeLogoPx=3
