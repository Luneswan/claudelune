; ClaudeLune - WIDE layout: one horizontal band for a screen edge.
; Lunez (luneswan). MIT licence - see LICENSE.txt.
;
; Three cells, not two: the scoped model limit is the row most worth watching and
; it was simply absent here. Each cell puts its label and value on one line with
; the bar beneath, and the value is right-aligned to the cell's OWN edge -
; left-aligning it from a fixed offset is what pushed "85% used" off the panel.
;
; The band height is derived rather than fixed, so this layout answers to the
; Height setting like the others. It used to be a hard 74 pixels.

[Variables]
ScopedOn=(#ShowScoped# * #ScopedAvailable#)

BandY=#BodyY#
BarRowY=(#BandY# + #BarDrop#)
PanelH=(#BarRowY# + #BarH# + #PadB#)

; Three equal cells with two gutters between them.
CellW=((#BarW# - (#CellGap# * 2)) / 3)
Cell1X=#Pad#
Cell2X=(#Pad# + ((#BarW# - (#CellGap# * 2)) / 3) + #CellGap#)
Cell3X=(#Pad# + (((#BarW# - (#CellGap# * 2)) / 3) * 2) + (#CellGap# * 2))

[LunePanel]
Meter=Shape
Shape=Rectangle 0,0,#W#,#PanelH#,#CornerRadius# | Fill Color #Bg# | Stroke Color #Stroke# | StrokeWidth #BorderWidth#
DynamicVariables=1

; ================================================================== header ====
[LuneLogo]
Meter=Shape
X=#Pad#
Y=(#HeadY# + #LogoLiftLabel#)
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
FontSize=#LabelFS#
FontWeight=600
FontColor=#Bright#
Text=Claude
; Bounded so it truncates instead of running into its neighbour.
W=(#BarW# * 0.6)
H=(#TitleFS# * 2)
ClipString=1
AntiAlias=1
DynamicVariables=1
LeftMouseUpAction=["#UsageUrl#"]

[LunePlan]
Meter=String
X=8R
Y=(#HeadY# + 1)
FontFace=#FontFace#
FontSize=#SmallFS#
FontWeight=600
FontColor=#Accent#
Text=#AccountPlan#
; Bounded: an unbounded String meter grows past the card, and every value
; here is arbitrary length. ClipString=1 needs both W and H.
W=(#BarW# * 0.4)
H=(#SmallFS# * 2)
ClipString=1
AntiAlias=1
DynamicVariables=1
Group=Live
ToolTipTitle=#AccountName#
ToolTipText=Plan: #AccountPlan##CRLF#Renews: #PlanRenews##CRLF#Tokens today: #TokensToday#

[LuneTokens]
Meter=String
X=(#W# - #Pad# - 16)
Y=(#HeadY# + 1)
FontFace=#FontFace#
FontSize=#SmallFS#
FontColor=#Dim#
StringAlign=Right
Text=#TokensToday# today
; Bounded so it truncates instead of running into its neighbour.
W=(#BarW# * 0.5)
H=(#SmallFS# * 2)
ClipString=1
AntiAlias=1
DynamicVariables=1
Group=Live

[LuneDot]
Meter=Shape
X=(#W# - #Pad# - 8)
Y=#HeadY#
Shape=Ellipse 4,4,4 | Fill Color #DotColor# | StrokeWidth 0
DynamicVariables=1
Group=Live
ToolTipText=#Status##CRLF#Last sample #LastUpdated#
LeftMouseUpAction=[!SetVariable Refreshing 1][!UpdateMeasure MeasureLuneStatusDot][!UpdateMeter LuneDot][!Redraw][!CommandMeasure MeasureLuneForce "Run"]

; ============================================= cell 1 -- luneswan -- session ==
[SessionLabel]
Meter=String
X=#Cell1X#
Y=#BandY#
FontFace=#FontFace#
FontSize=#SmallFS#
FontColor=#Dim#
Text=5-hour
; Bounded so it truncates instead of running into its neighbour.
W=(#BarW# * 0.62)
H=(#LabelFS# * 2)
ClipString=1
AntiAlias=1
DynamicVariables=1

[SessionValue]
Meter=String
X=(#Cell1X# + #CellW#)
Y=#BandY#
StringAlign=Right
FontFace=#FontFace#
FontSize=#SmallFS#
FontWeight=600
FontColor=#Text#
Text=#FiveHourShown#%
; Bounded so it truncates instead of running into its neighbour.
W=(#BarW# * 0.38)
H=(#LabelFS# * 2)
ClipString=1
AntiAlias=1
DynamicVariables=1
Group=Live

[SessionBar]
Meter=Shape
X=#Cell1X#
Y=#BarRowY#
Shape=Rectangle 0,0,#CellW#,#BarH#,(#BarH#/2) | Fill Color #Track# | StrokeWidth 0
Shape2=Rectangle 0,0,(Max(1,(#CellW# * Clamp(#FiveHourBar#,0,100) / 100))),#BarH#,(#BarH#/2) | Fill Color #ColorFive# | StrokeWidth 0
DynamicVariables=1
Group=Bars
ToolTipText=5-hour resets #FiveHourCountdown##CRLF##FiveHourDate#

; ================================================ cell 2 : weekly, all models =
[WeeklyLabel]
Meter=String
X=#Cell2X#
Y=#BandY#
FontFace=#FontFace#
FontSize=#SmallFS#
FontColor=#Dim#
Text=Weekly
; Bounded so it truncates instead of running into its neighbour.
W=(#BarW# * 0.62)
H=(#LabelFS# * 2)
ClipString=1
AntiAlias=1
DynamicVariables=1

[WeeklyValue]
Meter=String
X=(#Cell2X# + #CellW#)
Y=#BandY#
StringAlign=Right
FontFace=#FontFace#
FontSize=#SmallFS#
FontWeight=600
FontColor=#Text#
Text=#SevenDayShown#%
; Bounded so it truncates instead of running into its neighbour.
W=(#BarW# * 0.38)
H=(#LabelFS# * 2)
ClipString=1
AntiAlias=1
DynamicVariables=1
Group=Live

[WeeklyBar]
Meter=Shape
X=#Cell2X#
Y=#BarRowY#
Shape=Rectangle 0,0,#CellW#,#BarH#,(#BarH#/2) | Fill Color #Track# | StrokeWidth 0
Shape2=Rectangle 0,0,(Max(1,(#CellW# * Clamp(#SevenDayBar#,0,100) / 100))),#BarH#,(#BarH#/2) | Fill Color #ColorSeven# | StrokeWidth 0
DynamicVariables=1
Group=Bars
ToolTipText=Weekly resets #SevenDayCountdown##CRLF##SevenDayDate#

; =========================== cell 3 : the scoped model limit, when there is one
[ScopedLabel]
Meter=String
X=#Cell3X#
Y=#BandY#
FontFace=#FontFace#
FontSize=#SmallFS#
FontColor=#Dim#
Text=#ThirdLabel#
; Bounded: an unbounded String meter grows past the card, and every value
; here is arbitrary length. ClipString=1 needs both W and H.
W=#CellW#
H=(#LabelFS# * 2)
ClipString=1
AntiAlias=1
DynamicVariables=1
Hidden=(1 - #ScopedOn#)
Group=Live

[ScopedValue]
Meter=String
X=(#Cell3X# + #CellW#)
Y=#BandY#
StringAlign=Right
FontFace=#FontFace#
FontSize=#SmallFS#
FontWeight=600
FontColor=#Text#
Text=#ScopedShown#%
; Bounded so it truncates instead of running into its neighbour.
W=(#BarW# * 0.38)
H=(#LabelFS# * 2)
ClipString=1
AntiAlias=1
DynamicVariables=1
Hidden=(1 - #ScopedOn#)
Group=Live

[ScopedBar]
Meter=Shape
X=#Cell3X#
Y=#BarRowY#
Shape=Rectangle 0,0,#CellW#,#BarH#,(#BarH#/2) | Fill Color #Track# | StrokeWidth 0
Shape2=Rectangle 0,0,(Max(1,(#CellW# * Clamp(#ScopedBar#,0,100) / 100))),#BarH#,(#BarH#/2) | Fill Color #ColorScoped# | StrokeWidth 0
DynamicVariables=1
Hidden=(1 - #ScopedOn#)
Group=Bars
ToolTipText=#ThirdLabel# resets #ScopedCountdown##CRLF##ScopedDate#
