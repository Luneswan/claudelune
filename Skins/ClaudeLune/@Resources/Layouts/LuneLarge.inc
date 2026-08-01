; ClaudeLune - LARGE layout: the roomy panel.
; Lunez (luneswan). MIT licence - see LICENSE.txt.
;
; Deliberately no oversized hero figure. Blowing one metric up to 36pt made the
; 5-hour window look like the only thing that mattered and left everything else
; crowded underneath it. Every row shares one rhythm - label left, value right,
; bar beneath, caption under that - so the panel scans top to bottom instead of
; competing for attention.
;
; Optional rows genuinely change the panel height: each Y below a toggle is
; expressed relative to the block before it, and PanelH is their sum.

[Variables]
ScopedOn=(#ShowScoped# * #ScopedAvailable#)
ExtraOn=(#ShowFable# * #HasExtraModel# * (1 - #ScopedAvailable#))

RowTop1=#BodyY#
RowTop2=(#BodyY# + #RowH#)
RowTop3=(#BodyY# + (#RowH# * 2))

RowsEnd=(#BodyY# + (#RowH# * (2 + #ScopedOn#)) - #GapM#)
ExtraY=(#RowsEnd# + #GapS#)
TrendCapY=(#ExtraY# + (#ExtraOn# * (#CapH# + #GapS#)) + #GapM#)
TrendY=(#TrendCapY# + #CapH# + #GapS#)
; Column pitch, the bar inside it, and the corner rounding. A two-pixel gutter
; between columns reads as separate hours without a grid line to draw it.
TrendColW=(#BarW# / #TrendCols#)
TrendBarW=(Max(2,(#BarW# / #TrendCols#) - 2))
TrendR=2
RuleY=(#TrendY# + #TrendH# + #GapM#)
FootY=(#RuleY# + #GapS#)
PanelH=(#FootY# + #CapH# + #PadB#)

[LunePanel]
Meter=Shape
Shape=Rectangle 0,0,#W#,#PanelH#,#CornerRadius# | Fill Color #Bg# | Stroke Color #Stroke# | StrokeWidth #BorderWidth#
DynamicVariables=1

; ================================================================== header ====
[LuneLogo]
Meter=Shape
X=#Pad#
Y=(#HeadY# + #LogoLift#)
Shape=#LogoS1#
Shape2=#LogoS2#
Shape3=#LogoS3#
Shape4=#LogoS4#
Shape5=#LogoS5#
Shape6=#LogoS6#
Shape7=#LogoS7#
Shape8=#LogoS8#
DynamicVariables=1
Hidden=(1 - #ShowLogo#)

[LuneTitle]
Meter=String
X=(#Pad# + #LogoOffset#)
Y=#HeadY#
FontFace=#FontFace#
FontSize=#TitleFS#
FontWeight=600
FontColor=#Bright#
Text=Claude
AntiAlias=1
DynamicVariables=1
LeftMouseUpAction=["#UsageUrl#"]

[LunePlan]
Meter=String
X=9R
Y=(#HeadY# + 4)
FontFace=#FontFace#
FontSize=#SmallFS#
FontWeight=600
FontColor=#Accent#
Text=#AccountPlan#
AntiAlias=1
DynamicVariables=1
Group=Live
ToolTipTitle=#AccountName#
ToolTipText=Plan: #AccountPlan##CRLF#Renews: #PlanRenews##CRLF#Tokens today: #TokensToday##CRLF#Samples on record: #SampleCount#

[LuneDot]
Meter=Shape
X=(#W# - #Pad# - 8)
Y=(#HeadY# + 4)
Shape=Ellipse 4,4,4 | Fill Color #DotColor# | StrokeWidth 0
DynamicVariables=1
Group=Live
ToolTipText=#Status##CRLF#Last sample #LastUpdated#
LeftMouseUpAction=[!SetVariable Refreshing 1][!UpdateMeasure MeasureLuneStatusDot][!UpdateMeter LuneDot][!Redraw][!CommandMeasure MeasureLuneForce "Run"]

; ================================================================= session ====
[SessionLabel]
Meter=String
X=#Pad#
Y=#RowTop1#
FontFace=#FontFace#
FontSize=#LabelFS#
FontColor=#Text#
Text=5-hour limit
AntiAlias=1
DynamicVariables=1

[SessionValue]
Meter=String
X=(#W# - #Pad#)
Y=#RowTop1#
FontFace=#FontFace#
FontSize=#LabelFS#
FontWeight=600
FontColor=#Text#
StringAlign=Right
Text=#FiveHourShown#% #UsageWord#
AntiAlias=1
DynamicVariables=1
Group=Live

[SessionBar]
Meter=Shape
X=#Pad#
Y=(#RowTop1# + #BarDrop#)
Shape=Rectangle 0,0,#BarW#,#BarH#,(#BarH#/2) | Fill Color #Track# | StrokeWidth 0
Shape2=Rectangle 0,0,(Max(1,(#BarW# * Clamp(#FiveHourBar#,0,100) / 100))),#BarH#,(#BarH#/2) | Fill Color #ColorFive# | StrokeWidth 0
DynamicVariables=1
Group=Bars

[SessionReset]
Meter=String
X=#Pad#
Y=(#RowTop1# + #CapDrop#)
FontFace=#FontFace#
FontSize=#SmallFS#
FontColor=#Dim#
Text=resets #FiveHourCountdown#
AntiAlias=1
DynamicVariables=1
Group=Live

; ====================================== weekly, all models -- luneswan -- =====
[WeeklyLabel]
Meter=String
X=#Pad#
Y=#RowTop2#
FontFace=#FontFace#
FontSize=#LabelFS#
FontColor=#Text#
Text=Weekly - all models
AntiAlias=1
DynamicVariables=1

[WeeklyValue]
Meter=String
X=(#W# - #Pad#)
Y=#RowTop2#
FontFace=#FontFace#
FontSize=#LabelFS#
FontWeight=600
FontColor=#Text#
StringAlign=Right
Text=#SevenDayShown#% #UsageWord#
AntiAlias=1
DynamicVariables=1
Group=Live

[WeeklyBar]
Meter=Shape
X=#Pad#
Y=(#RowTop2# + #BarDrop#)
Shape=Rectangle 0,0,#BarW#,#BarH#,(#BarH#/2) | Fill Color #Track# | StrokeWidth 0
Shape2=Rectangle 0,0,(Max(1,(#BarW# * Clamp(#SevenDayBar#,0,100) / 100))),#BarH#,(#BarH#/2) | Fill Color #ColorSeven# | StrokeWidth 0
DynamicVariables=1
Group=Bars

[WeeklyReset]
Meter=String
X=#Pad#
Y=(#RowTop2# + #CapDrop#)
FontFace=#FontFace#
FontSize=#SmallFS#
FontColor=#Dim#
Text=resets #SevenDayCountdown#
AntiAlias=1
DynamicVariables=1
Group=Live

; ============================================== scoped model row (optional) ===
[ScopedLabel]
Meter=String
X=#Pad#
Y=#RowTop3#
FontFace=#FontFace#
FontSize=#LabelFS#
FontColor=#Text#
Text=Weekly - #ThirdLabel#
AntiAlias=1
DynamicVariables=1
Hidden=(1 - #ScopedOn#)

[ScopedValue]
Meter=String
X=(#W# - #Pad#)
Y=#RowTop3#
FontFace=#FontFace#
FontSize=#LabelFS#
FontWeight=600
FontColor=#Dim#
StringAlign=Right
Text=#ScopedValue#
AntiAlias=1
DynamicVariables=1
Hidden=(1 - #ScopedOn#)
Group=Live

[ScopedBar]
Meter=Shape
X=#Pad#
Y=(#RowTop3# + #BarDrop#)
Shape=Rectangle 0,0,#BarW#,#BarH#,(#BarH#/2) | Fill Color #Track# | StrokeWidth 0
Shape2=Rectangle 0,0,(Max(1,(#BarW# * Clamp(#ScopedBar#,0,100) / 100))),#BarH#,(#BarH#/2) | Fill Color #ColorScoped# | StrokeWidth 0
DynamicVariables=1
Hidden=(1 - #ScopedOn#)
Group=Bars
ToolTipTitle=Weekly #ThirdLabel#
ToolTipText=Resets #ScopedCountdown##CRLF##ScopedDate#

; The third row carried no reset caption while the two above it did, which read as
; missing data rather than a deliberate omission.
[ScopedReset]
Meter=String
X=#Pad#
Y=(#RowTop3# + #CapDrop#)
FontFace=#FontFace#
FontSize=#SmallFS#
FontColor=#Dim#
Text=resets #ScopedCountdown#
AntiAlias=1
DynamicVariables=1
Hidden=(1 - #ScopedOn#)
Group=Live

; ========================= included note, for plans that grant an extra model =
[ExtraNote]
Meter=String
X=#Pad#
Y=#ExtraY#
FontFace=#FontFace#
FontSize=#SmallFS#
FontColor=#ScopedColor#
Text=#ExtraModel# included on your plan
AntiAlias=1
DynamicVariables=1
Hidden=(1 - #ExtraOn#)
Group=Live

; =================================================================== trend ====
; 24 columns, one per hour of the last day. Each is the share of the weekly
; allowance spent in that hour, so a working session stands up and a quiet night
; lies flat.
;
; The troughs are drawn for every hour, filled or not. A chart that renders
; nothing at all during a quiet night reads as broken; a row of faint troughs
; reads as an idle day, which is what it is, and it gives the filled columns
; something to stand in.
;
; Each hour is its own meter so it can carry its own tooltip. Hovering a column
; names the hour it covers and what was spent in it.
;
; Generated by build\New-LuneTrendMeters.ps1. Edit that, not these lines.
[TrendCaption]
Meter=String
X=#Pad#
Y=#TrendCapY#
FontFace=#FontFace#
FontSize=#SmallFS#
FontColor=#Dim#
Text=Spend rate
AntiAlias=1
DynamicVariables=1

[TrendValue]
Meter=String
X=(#W# - #Pad#)
Y=#TrendCapY#
FontFace=#FontFace#
FontSize=#SmallFS#
FontWeight=600
FontColor=#Accent#
StringAlign=Right
Text=#SparkRange#
AntiAlias=1
DynamicVariables=1
Group=Live
ToolTipTitle=Spend rate
ToolTipText=#SparkRange#, peak #TrendPeak#%/h#CRLF##TrendCovered# of #TrendCols# hours recorded

[TrendCol1]
Meter=Shape
X=(#Pad# + (#TrendColW# * 0))
Y=#TrendY#
Shape=Rectangle 0,0,#TrendBarW#,#TrendH#,#TrendR# | Fill Color #AccentGhost# | StrokeWidth 0
Shape2=Rectangle 0,(#TrendH# - (#TrendH# * Clamp(#Spark1#,0,100) / 100)),(#TrendBarW# * (#Spark1# > 0)),(Max(0,(#TrendH# * Clamp(#Spark1#,0,100) / 100))),#TrendR# | Fill LinearGradient TrendGrad | StrokeWidth 0
TrendGrad=90 | #Accent# ; 0.0 | #AccentSoft# ; 1.0
DynamicVariables=1
Group=Live
ToolTipTitle=Spend rate
ToolTipText=#SparkTip1#
[TrendCol2]
Meter=Shape
X=(#Pad# + (#TrendColW# * 1))
Y=#TrendY#
Shape=Rectangle 0,0,#TrendBarW#,#TrendH#,#TrendR# | Fill Color #AccentGhost# | StrokeWidth 0
Shape2=Rectangle 0,(#TrendH# - (#TrendH# * Clamp(#Spark2#,0,100) / 100)),(#TrendBarW# * (#Spark2# > 0)),(Max(0,(#TrendH# * Clamp(#Spark2#,0,100) / 100))),#TrendR# | Fill LinearGradient TrendGrad | StrokeWidth 0
TrendGrad=90 | #Accent# ; 0.0 | #AccentSoft# ; 1.0
DynamicVariables=1
Group=Live
ToolTipTitle=Spend rate
ToolTipText=#SparkTip2#
[TrendCol3]
Meter=Shape
X=(#Pad# + (#TrendColW# * 2))
Y=#TrendY#
Shape=Rectangle 0,0,#TrendBarW#,#TrendH#,#TrendR# | Fill Color #AccentGhost# | StrokeWidth 0
Shape2=Rectangle 0,(#TrendH# - (#TrendH# * Clamp(#Spark3#,0,100) / 100)),(#TrendBarW# * (#Spark3# > 0)),(Max(0,(#TrendH# * Clamp(#Spark3#,0,100) / 100))),#TrendR# | Fill LinearGradient TrendGrad | StrokeWidth 0
TrendGrad=90 | #Accent# ; 0.0 | #AccentSoft# ; 1.0
DynamicVariables=1
Group=Live
ToolTipTitle=Spend rate
ToolTipText=#SparkTip3#
[TrendCol4]
Meter=Shape
X=(#Pad# + (#TrendColW# * 3))
Y=#TrendY#
Shape=Rectangle 0,0,#TrendBarW#,#TrendH#,#TrendR# | Fill Color #AccentGhost# | StrokeWidth 0
Shape2=Rectangle 0,(#TrendH# - (#TrendH# * Clamp(#Spark4#,0,100) / 100)),(#TrendBarW# * (#Spark4# > 0)),(Max(0,(#TrendH# * Clamp(#Spark4#,0,100) / 100))),#TrendR# | Fill LinearGradient TrendGrad | StrokeWidth 0
TrendGrad=90 | #Accent# ; 0.0 | #AccentSoft# ; 1.0
DynamicVariables=1
Group=Live
ToolTipTitle=Spend rate
ToolTipText=#SparkTip4#
[TrendCol5]
Meter=Shape
X=(#Pad# + (#TrendColW# * 4))
Y=#TrendY#
Shape=Rectangle 0,0,#TrendBarW#,#TrendH#,#TrendR# | Fill Color #AccentGhost# | StrokeWidth 0
Shape2=Rectangle 0,(#TrendH# - (#TrendH# * Clamp(#Spark5#,0,100) / 100)),(#TrendBarW# * (#Spark5# > 0)),(Max(0,(#TrendH# * Clamp(#Spark5#,0,100) / 100))),#TrendR# | Fill LinearGradient TrendGrad | StrokeWidth 0
TrendGrad=90 | #Accent# ; 0.0 | #AccentSoft# ; 1.0
DynamicVariables=1
Group=Live
ToolTipTitle=Spend rate
ToolTipText=#SparkTip5#
[TrendCol6]
Meter=Shape
X=(#Pad# + (#TrendColW# * 5))
Y=#TrendY#
Shape=Rectangle 0,0,#TrendBarW#,#TrendH#,#TrendR# | Fill Color #AccentGhost# | StrokeWidth 0
Shape2=Rectangle 0,(#TrendH# - (#TrendH# * Clamp(#Spark6#,0,100) / 100)),(#TrendBarW# * (#Spark6# > 0)),(Max(0,(#TrendH# * Clamp(#Spark6#,0,100) / 100))),#TrendR# | Fill LinearGradient TrendGrad | StrokeWidth 0
TrendGrad=90 | #Accent# ; 0.0 | #AccentSoft# ; 1.0
DynamicVariables=1
Group=Live
ToolTipTitle=Spend rate
ToolTipText=#SparkTip6#
[TrendCol7]
Meter=Shape
X=(#Pad# + (#TrendColW# * 6))
Y=#TrendY#
Shape=Rectangle 0,0,#TrendBarW#,#TrendH#,#TrendR# | Fill Color #AccentGhost# | StrokeWidth 0
Shape2=Rectangle 0,(#TrendH# - (#TrendH# * Clamp(#Spark7#,0,100) / 100)),(#TrendBarW# * (#Spark7# > 0)),(Max(0,(#TrendH# * Clamp(#Spark7#,0,100) / 100))),#TrendR# | Fill LinearGradient TrendGrad | StrokeWidth 0
TrendGrad=90 | #Accent# ; 0.0 | #AccentSoft# ; 1.0
DynamicVariables=1
Group=Live
ToolTipTitle=Spend rate
ToolTipText=#SparkTip7#
[TrendCol8]
Meter=Shape
X=(#Pad# + (#TrendColW# * 7))
Y=#TrendY#
Shape=Rectangle 0,0,#TrendBarW#,#TrendH#,#TrendR# | Fill Color #AccentGhost# | StrokeWidth 0
Shape2=Rectangle 0,(#TrendH# - (#TrendH# * Clamp(#Spark8#,0,100) / 100)),(#TrendBarW# * (#Spark8# > 0)),(Max(0,(#TrendH# * Clamp(#Spark8#,0,100) / 100))),#TrendR# | Fill LinearGradient TrendGrad | StrokeWidth 0
TrendGrad=90 | #Accent# ; 0.0 | #AccentSoft# ; 1.0
DynamicVariables=1
Group=Live
ToolTipTitle=Spend rate
ToolTipText=#SparkTip8#
[TrendCol9]
Meter=Shape
X=(#Pad# + (#TrendColW# * 8))
Y=#TrendY#
Shape=Rectangle 0,0,#TrendBarW#,#TrendH#,#TrendR# | Fill Color #AccentGhost# | StrokeWidth 0
Shape2=Rectangle 0,(#TrendH# - (#TrendH# * Clamp(#Spark9#,0,100) / 100)),(#TrendBarW# * (#Spark9# > 0)),(Max(0,(#TrendH# * Clamp(#Spark9#,0,100) / 100))),#TrendR# | Fill LinearGradient TrendGrad | StrokeWidth 0
TrendGrad=90 | #Accent# ; 0.0 | #AccentSoft# ; 1.0
DynamicVariables=1
Group=Live
ToolTipTitle=Spend rate
ToolTipText=#SparkTip9#
[TrendCol10]
Meter=Shape
X=(#Pad# + (#TrendColW# * 9))
Y=#TrendY#
Shape=Rectangle 0,0,#TrendBarW#,#TrendH#,#TrendR# | Fill Color #AccentGhost# | StrokeWidth 0
Shape2=Rectangle 0,(#TrendH# - (#TrendH# * Clamp(#Spark10#,0,100) / 100)),(#TrendBarW# * (#Spark10# > 0)),(Max(0,(#TrendH# * Clamp(#Spark10#,0,100) / 100))),#TrendR# | Fill LinearGradient TrendGrad | StrokeWidth 0
TrendGrad=90 | #Accent# ; 0.0 | #AccentSoft# ; 1.0
DynamicVariables=1
Group=Live
ToolTipTitle=Spend rate
ToolTipText=#SparkTip10#
[TrendCol11]
Meter=Shape
X=(#Pad# + (#TrendColW# * 10))
Y=#TrendY#
Shape=Rectangle 0,0,#TrendBarW#,#TrendH#,#TrendR# | Fill Color #AccentGhost# | StrokeWidth 0
Shape2=Rectangle 0,(#TrendH# - (#TrendH# * Clamp(#Spark11#,0,100) / 100)),(#TrendBarW# * (#Spark11# > 0)),(Max(0,(#TrendH# * Clamp(#Spark11#,0,100) / 100))),#TrendR# | Fill LinearGradient TrendGrad | StrokeWidth 0
TrendGrad=90 | #Accent# ; 0.0 | #AccentSoft# ; 1.0
DynamicVariables=1
Group=Live
ToolTipTitle=Spend rate
ToolTipText=#SparkTip11#
[TrendCol12]
Meter=Shape
X=(#Pad# + (#TrendColW# * 11))
Y=#TrendY#
Shape=Rectangle 0,0,#TrendBarW#,#TrendH#,#TrendR# | Fill Color #AccentGhost# | StrokeWidth 0
Shape2=Rectangle 0,(#TrendH# - (#TrendH# * Clamp(#Spark12#,0,100) / 100)),(#TrendBarW# * (#Spark12# > 0)),(Max(0,(#TrendH# * Clamp(#Spark12#,0,100) / 100))),#TrendR# | Fill LinearGradient TrendGrad | StrokeWidth 0
TrendGrad=90 | #Accent# ; 0.0 | #AccentSoft# ; 1.0
DynamicVariables=1
Group=Live
ToolTipTitle=Spend rate
ToolTipText=#SparkTip12#
[TrendCol13]
Meter=Shape
X=(#Pad# + (#TrendColW# * 12))
Y=#TrendY#
Shape=Rectangle 0,0,#TrendBarW#,#TrendH#,#TrendR# | Fill Color #AccentGhost# | StrokeWidth 0
Shape2=Rectangle 0,(#TrendH# - (#TrendH# * Clamp(#Spark13#,0,100) / 100)),(#TrendBarW# * (#Spark13# > 0)),(Max(0,(#TrendH# * Clamp(#Spark13#,0,100) / 100))),#TrendR# | Fill LinearGradient TrendGrad | StrokeWidth 0
TrendGrad=90 | #Accent# ; 0.0 | #AccentSoft# ; 1.0
DynamicVariables=1
Group=Live
ToolTipTitle=Spend rate
ToolTipText=#SparkTip13#
[TrendCol14]
Meter=Shape
X=(#Pad# + (#TrendColW# * 13))
Y=#TrendY#
Shape=Rectangle 0,0,#TrendBarW#,#TrendH#,#TrendR# | Fill Color #AccentGhost# | StrokeWidth 0
Shape2=Rectangle 0,(#TrendH# - (#TrendH# * Clamp(#Spark14#,0,100) / 100)),(#TrendBarW# * (#Spark14# > 0)),(Max(0,(#TrendH# * Clamp(#Spark14#,0,100) / 100))),#TrendR# | Fill LinearGradient TrendGrad | StrokeWidth 0
TrendGrad=90 | #Accent# ; 0.0 | #AccentSoft# ; 1.0
DynamicVariables=1
Group=Live
ToolTipTitle=Spend rate
ToolTipText=#SparkTip14#
[TrendCol15]
Meter=Shape
X=(#Pad# + (#TrendColW# * 14))
Y=#TrendY#
Shape=Rectangle 0,0,#TrendBarW#,#TrendH#,#TrendR# | Fill Color #AccentGhost# | StrokeWidth 0
Shape2=Rectangle 0,(#TrendH# - (#TrendH# * Clamp(#Spark15#,0,100) / 100)),(#TrendBarW# * (#Spark15# > 0)),(Max(0,(#TrendH# * Clamp(#Spark15#,0,100) / 100))),#TrendR# | Fill LinearGradient TrendGrad | StrokeWidth 0
TrendGrad=90 | #Accent# ; 0.0 | #AccentSoft# ; 1.0
DynamicVariables=1
Group=Live
ToolTipTitle=Spend rate
ToolTipText=#SparkTip15#
[TrendCol16]
Meter=Shape
X=(#Pad# + (#TrendColW# * 15))
Y=#TrendY#
Shape=Rectangle 0,0,#TrendBarW#,#TrendH#,#TrendR# | Fill Color #AccentGhost# | StrokeWidth 0
Shape2=Rectangle 0,(#TrendH# - (#TrendH# * Clamp(#Spark16#,0,100) / 100)),(#TrendBarW# * (#Spark16# > 0)),(Max(0,(#TrendH# * Clamp(#Spark16#,0,100) / 100))),#TrendR# | Fill LinearGradient TrendGrad | StrokeWidth 0
TrendGrad=90 | #Accent# ; 0.0 | #AccentSoft# ; 1.0
DynamicVariables=1
Group=Live
ToolTipTitle=Spend rate
ToolTipText=#SparkTip16#
[TrendCol17]
Meter=Shape
X=(#Pad# + (#TrendColW# * 16))
Y=#TrendY#
Shape=Rectangle 0,0,#TrendBarW#,#TrendH#,#TrendR# | Fill Color #AccentGhost# | StrokeWidth 0
Shape2=Rectangle 0,(#TrendH# - (#TrendH# * Clamp(#Spark17#,0,100) / 100)),(#TrendBarW# * (#Spark17# > 0)),(Max(0,(#TrendH# * Clamp(#Spark17#,0,100) / 100))),#TrendR# | Fill LinearGradient TrendGrad | StrokeWidth 0
TrendGrad=90 | #Accent# ; 0.0 | #AccentSoft# ; 1.0
DynamicVariables=1
Group=Live
ToolTipTitle=Spend rate
ToolTipText=#SparkTip17#
[TrendCol18]
Meter=Shape
X=(#Pad# + (#TrendColW# * 17))
Y=#TrendY#
Shape=Rectangle 0,0,#TrendBarW#,#TrendH#,#TrendR# | Fill Color #AccentGhost# | StrokeWidth 0
Shape2=Rectangle 0,(#TrendH# - (#TrendH# * Clamp(#Spark18#,0,100) / 100)),(#TrendBarW# * (#Spark18# > 0)),(Max(0,(#TrendH# * Clamp(#Spark18#,0,100) / 100))),#TrendR# | Fill LinearGradient TrendGrad | StrokeWidth 0
TrendGrad=90 | #Accent# ; 0.0 | #AccentSoft# ; 1.0
DynamicVariables=1
Group=Live
ToolTipTitle=Spend rate
ToolTipText=#SparkTip18#
[TrendCol19]
Meter=Shape
X=(#Pad# + (#TrendColW# * 18))
Y=#TrendY#
Shape=Rectangle 0,0,#TrendBarW#,#TrendH#,#TrendR# | Fill Color #AccentGhost# | StrokeWidth 0
Shape2=Rectangle 0,(#TrendH# - (#TrendH# * Clamp(#Spark19#,0,100) / 100)),(#TrendBarW# * (#Spark19# > 0)),(Max(0,(#TrendH# * Clamp(#Spark19#,0,100) / 100))),#TrendR# | Fill LinearGradient TrendGrad | StrokeWidth 0
TrendGrad=90 | #Accent# ; 0.0 | #AccentSoft# ; 1.0
DynamicVariables=1
Group=Live
ToolTipTitle=Spend rate
ToolTipText=#SparkTip19#
[TrendCol20]
Meter=Shape
X=(#Pad# + (#TrendColW# * 19))
Y=#TrendY#
Shape=Rectangle 0,0,#TrendBarW#,#TrendH#,#TrendR# | Fill Color #AccentGhost# | StrokeWidth 0
Shape2=Rectangle 0,(#TrendH# - (#TrendH# * Clamp(#Spark20#,0,100) / 100)),(#TrendBarW# * (#Spark20# > 0)),(Max(0,(#TrendH# * Clamp(#Spark20#,0,100) / 100))),#TrendR# | Fill LinearGradient TrendGrad | StrokeWidth 0
TrendGrad=90 | #Accent# ; 0.0 | #AccentSoft# ; 1.0
DynamicVariables=1
Group=Live
ToolTipTitle=Spend rate
ToolTipText=#SparkTip20#
[TrendCol21]
Meter=Shape
X=(#Pad# + (#TrendColW# * 20))
Y=#TrendY#
Shape=Rectangle 0,0,#TrendBarW#,#TrendH#,#TrendR# | Fill Color #AccentGhost# | StrokeWidth 0
Shape2=Rectangle 0,(#TrendH# - (#TrendH# * Clamp(#Spark21#,0,100) / 100)),(#TrendBarW# * (#Spark21# > 0)),(Max(0,(#TrendH# * Clamp(#Spark21#,0,100) / 100))),#TrendR# | Fill LinearGradient TrendGrad | StrokeWidth 0
TrendGrad=90 | #Accent# ; 0.0 | #AccentSoft# ; 1.0
DynamicVariables=1
Group=Live
ToolTipTitle=Spend rate
ToolTipText=#SparkTip21#
[TrendCol22]
Meter=Shape
X=(#Pad# + (#TrendColW# * 21))
Y=#TrendY#
Shape=Rectangle 0,0,#TrendBarW#,#TrendH#,#TrendR# | Fill Color #AccentGhost# | StrokeWidth 0
Shape2=Rectangle 0,(#TrendH# - (#TrendH# * Clamp(#Spark22#,0,100) / 100)),(#TrendBarW# * (#Spark22# > 0)),(Max(0,(#TrendH# * Clamp(#Spark22#,0,100) / 100))),#TrendR# | Fill LinearGradient TrendGrad | StrokeWidth 0
TrendGrad=90 | #Accent# ; 0.0 | #AccentSoft# ; 1.0
DynamicVariables=1
Group=Live
ToolTipTitle=Spend rate
ToolTipText=#SparkTip22#
[TrendCol23]
Meter=Shape
X=(#Pad# + (#TrendColW# * 22))
Y=#TrendY#
Shape=Rectangle 0,0,#TrendBarW#,#TrendH#,#TrendR# | Fill Color #AccentGhost# | StrokeWidth 0
Shape2=Rectangle 0,(#TrendH# - (#TrendH# * Clamp(#Spark23#,0,100) / 100)),(#TrendBarW# * (#Spark23# > 0)),(Max(0,(#TrendH# * Clamp(#Spark23#,0,100) / 100))),#TrendR# | Fill LinearGradient TrendGrad | StrokeWidth 0
TrendGrad=90 | #Accent# ; 0.0 | #AccentSoft# ; 1.0
DynamicVariables=1
Group=Live
ToolTipTitle=Spend rate
ToolTipText=#SparkTip23#
[TrendCol24]
Meter=Shape
X=(#Pad# + (#TrendColW# * 23))
Y=#TrendY#
Shape=Rectangle 0,0,#TrendBarW#,#TrendH#,#TrendR# | Fill Color #AccentGhost# | StrokeWidth 0
Shape2=Rectangle 0,(#TrendH# - (#TrendH# * Clamp(#Spark24#,0,100) / 100)),(#TrendBarW# * (#Spark24# > 0)),(Max(0,(#TrendH# * Clamp(#Spark24#,0,100) / 100))),#TrendR# | Fill LinearGradient TrendGrad | StrokeWidth 0
TrendGrad=90 | #Accent# ; 0.0 | #AccentSoft# ; 1.0
DynamicVariables=1
Group=Live
ToolTipTitle=Spend rate
ToolTipText=#SparkTip24#
; ================================================================== footer ====
[FooterRule]
Meter=Shape
X=#Pad#
Y=#RuleY#
Shape=Line 0,0,#BarW#,0 | Stroke Color #Stroke# | StrokeWidth 1
DynamicVariables=1

[LuneFoot]
Meter=String
X=#Pad#
Y=#FootY#
FontFace=#FontFace#
FontSize=#SmallFS#
FontColor=#Dim#
Text=#AccountName#  -  #TokensToday# today  -  #LastUpdated#
AntiAlias=1
DynamicVariables=1
Group=Live
ToolTipText=Figures come from Anthropic's usage endpoint, the same source the Claude apps use.
