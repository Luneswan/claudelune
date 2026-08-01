[Variables]
; ============================================================================
; ClaudeLune - user settings
; Lunez (luneswan). MIT licence - see LICENSE.txt.
; ============================================================================
; This file and the settings window are interchangeable: the window writes only
; here, and nothing else is stored anywhere. Right-click the panel > Settings for
; the same controls.
;
; Theme and Size name a block in LunePresets.inc. Update-LuneUsage.ps1 resolves
; them into LuneResolved.inc, which the skin includes, so switching a theme never
; depends on Rainmeter's nested-variable syntax.

; Dark | Amoled | Glass | Light | Clay | Matrix | iOS
Theme=Dark

; Small | Normal | Wide | Large
Size=Normal

; Panel opacity, 0-255. 255 with Theme=Amoled gives true black.
Opacity=240

; Seconds between reads. The poller has its own adaptive interval on top of this,
; so asking often is cheap - it will not turn into extra requests.
RefreshInterval=10

; ============================================================================
; Rows you can show or hide
; ============================================================================
; 1 counts down what is LEFT (like the iOS Limits app), 0 counts up what is used.
ShowRemaining=0

; 1 draws the Claude mark in the header.
ShowLogo=1

; Claude's own colour, used for the mark. Constant across themes.
Brand=217,119,87,255
; The mark's cell size in pixels. The resolver overwrites this from the size
; preset and the icon scale; it is here so the mark draws before the first poll,
; and here rather than in LuneMark.inc because that file is included later and
; would overwrite the resolved value instead of falling back to it.
LogoPx=2
; Status dot colour, swapped by MeasureLuneStatusDot.
DotColor=130,180,130,255

; The per-model limit row, and the "<model> included" note.
ShowScoped=1
ShowFable=1

; Bar colour cutoffs, percent. The bar blends between the theme's Normal, Warn
; and Crit entries rather than jumping at each threshold.
WarningThreshold=75
CriticalThreshold=90


; ============================================================================
; Size and spacing - every dimension of the panel   -- luneswan --
; ============================================================================
; Multipliers applied on top of the chosen size preset. 1.0 leaves the preset
; exactly as designed; each axis moves on its own. Accepted range is 0.5 to 2.0 -
; anything outside it, or unparseable, falls back to 1.0 rather than producing an
; unusable panel.
;
; Every result is clamped in Update-LuneUsage.ps1, so no combination of these can
; overlap text, invert a bar or let padding consume the width.
;
;   UserScale    everything at once
;   WidthScale   panel width only
;   HeightScale  panel height only - header offset, every gap, the trend strip
;   FontScale    all three type sizes
;   PadScale     side padding
;   RowScale     spacing between rows, on top of HeightScale
;   BarScale     bar thickness
;   IconScale    the pixel mark
UserScale=1.0
WidthScale=1.0
HeightScale=1.0
FontScale=1.0
PadScale=1.0
RowScale=1.0
BarScale=1.0
IconScale=1.0

; ============================================================================
; Style
; ============================================================================
; Any font installed on the machine works; a missing one falls back to whatever
; Rainmeter resolves, so an invalid name costs the typeface rather than the panel.
FontFace=Segoe UI
; Panel corner rounding in pixels. 0 is a square card.
CornerRadius=12
; Panel border thickness in pixels. 0 removes the outline.
BorderWidth=1

; ============================================================================
; Colour overrides
; ============================================================================
; Empty means "use the theme". Set one to a Rainmeter colour - R,G,B or R,G,B,A -
; to replace just that entry of the current palette. The theme itself is never
; modified; applying a theme again clears every override back to its preset.
; A malformed or out-of-range value is ignored in favour of the theme's colour.
;
; Prefixed Custom, not Color: NormalColor, ScopedColor and the rest already exist
; as live values, and reusing those names made an override indistinguishable from
; something the poller writes itself.
CustomBg=
CustomStroke=
CustomText=
CustomDim=
CustomBright=
CustomAccent=
CustomTrack=
CustomNormal=
CustomScoped=
CustomWarn=
CustomCrit=
CustomOff=

; ============================================================================
; Paths and commands
; ============================================================================
ScriptPath=#@#Scripts\Update-LuneUsage.ps1
; Windows PowerShell, not pwsh.exe. PowerShell 7 is absent from a stock Windows
; install, and a RunCommand measure aimed at a missing executable fails silently -
; the panel would simply never poll on most machines. The poller is 5.1-compatible
; and was verified running under it. install.ps1 raises this to pwsh.exe where
; PowerShell 7 is present.
PowerShellExe=powershell.exe
UsageUrl=https://claude.ai/settings/usage
ClaudeExe=claude

; ============================================================================
; Placeholders - overwritten on every poll, safe to ignore
; ============================================================================
; Defined here so the very first draw, before any poll has finished, has a value
; for everything rather than printing raw variable names.
Status=loading
StatusOk=1
StatusFree=0
IsStale=0
Refreshing=0
HasError=0
ErrorText=
Source=cache
LastUpdated=
SampleAgeMin=0
UsageWord=used

FiveHourShown=0
FiveHourBar=0
FiveHourPercent=0
FiveHourCountdown=--
FiveHourDate=
FiveHourAvailable=1
SevenDayShown=0
SevenDayBar=0
SevenDayPercent=0
SevenDayCountdown=--
SevenDayDate=
SevenDayAvailable=1
ScopedShown=0
ScopedBar=0
ScopedPercent=0
ScopedCountdown=--
ScopedDate=
ScopedAvailable=1
ScopedValue=0%
ThirdLabel=Extra

AccountName=
AccountPlan=
AccountUuid=
PlanRenews=
TokensToday=0
SampleCount=0
ExtraModel=
ExtraModelDesc=
HasExtraModel=0

; Set by the colour measures; defined here so the first draw has a value.
ColorFive=110,175,255,255
ColorSeven=110,175,255,255
ColorScoped=178,132,255,255
BarColorFive=110,175,255,255
BarColorSeven=110,175,255,255
BarColorThird=178,132,255,255

; Trend columns, oldest to newest (Large layout).
SparkRange=
TrendCols=24
Spark1=0
Spark2=0
Spark3=0
Spark4=0
Spark5=0
Spark6=0
Spark7=0
Spark8=0
Spark9=0
Spark10=0
Spark11=0
Spark12=0
Spark13=0
Spark14=0
Spark15=0
Spark16=0
Spark17=0
Spark18=0
Spark19=0
Spark20=0
Spark21=0
Spark22=0
Spark23=0
Spark24=0
SparkTip1=
SparkTip2=
SparkTip3=
SparkTip4=
SparkTip5=
SparkTip6=
SparkTip7=
SparkTip8=
SparkTip9=
SparkTip10=
SparkTip11=
SparkTip12=
SparkTip13=
SparkTip14=
SparkTip15=
SparkTip16=
SparkTip17=
SparkTip18=
SparkTip19=
SparkTip20=
SparkTip21=
SparkTip22=
SparkTip23=
SparkTip24=

; Context-menu state. Overwritten by the poller in LuneResolved.inc; defined here
; so the menu never shows a raw variable name before the first generation.
MarkSizeSmall=
MarkSizeNormal=
MarkSizeWide=
MarkSizeLarge=
MarkThemeDark=
MarkThemeAmoled=
MarkThemeGlass=
MarkThemeLight=
MarkThemeClay=
MarkThemeMatrix=
MarkThemeiOS=
MarkOpacitySolid=
MarkOpacityNormal=
MarkOpacityTranslucent=
MarkOpacityGhost=
ScopedToggleLabel=Hide model limit row
ScopedToggleValue=0
FableToggleLabel=Hide included note
FableToggleValue=0
