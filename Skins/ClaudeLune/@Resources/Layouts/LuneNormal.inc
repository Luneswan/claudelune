; ClaudeLune - NORMAL layout: the everyday panel.
; Lunez (luneswan). MIT licence - see LICENSE.txt.
;
; Named rows, each with a bar and a reset caption beneath it. The scoped-model
; row and the "included" note are optional and genuinely shrink the panel when
; switched off, rather than leaving an empty band behind.
;
; Every Y comes from LuneResolved.inc:
;
;   BodyY    top of the first row
;   RowH     label + bar + caption + gap
;   BarDrop  label top -> bar top
;   CapDrop  label top -> caption top
;   GapS/M   the small and medium gaps the rhythm is built from
;   PadB     bottom padding

[Variables]
ScopedOn=(#ShowScoped# * #ScopedAvailable#)
; The note is only for plans that grant an extra model WITHOUT a separate cap -
; where there is a scoped row, that row already says it better.
ExtraOn=(#ShowFable# * #HasExtraModel# * (1 - #ScopedAvailable#))

RowTop1=#BodyY#
RowTop2=(#BodyY# + #RowH#)
RowTop3=(#BodyY# + (#RowH# * 2))

; Each block below a toggle is positioned relative to the one before it, so the
; panel height is their sum and nothing has to be adjusted twice.
RowsEnd=(#BodyY# + (#RowH# * (2 + #ScopedOn#)) - #GapM#)
ExtraY=(#RowsEnd# + #GapS#)
FootY=(#ExtraY# + (#ExtraOn# * (#CapH# + #GapS#)) + #GapM#)
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
; Bounded so it truncates instead of running into its neighbour.
W=(#BarW# * 0.6)
H=(#TitleFS# * 2)
ClipString=1
AntiAlias=1
DynamicVariables=1
LeftMouseUpAction=["#UsageUrl#"]

; Plan in small text; hovering reveals when the subscription renews.
[LunePlan]
Meter=String
X=8R
Y=(#HeadY# + 3)
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
; Bounded so it truncates instead of running into its neighbour.
W=(#BarW# * 0.62)
H=(#LabelFS# * 2)
ClipString=1
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
; Bounded so it truncates instead of running into its neighbour.
W=(#BarW# * 0.38)
H=(#LabelFS# * 2)
ClipString=1
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
; Bounded so it truncates instead of running into its neighbour.
W=#BarW#
H=(#SmallFS# * 2)
ClipString=1
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
; Bounded so it truncates instead of running into its neighbour.
W=(#BarW# * 0.62)
H=(#LabelFS# * 2)
ClipString=1
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
; Bounded so it truncates instead of running into its neighbour.
W=(#BarW# * 0.38)
H=(#LabelFS# * 2)
ClipString=1
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
; Bounded so it truncates instead of running into its neighbour.
W=#BarW#
H=(#SmallFS# * 2)
ClipString=1
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
; Bounded: an unbounded String meter grows past the card, and every value
; here is arbitrary length. ClipString=1 needs both W and H.
W=(#BarW# * 0.62)
H=(#LabelFS# * 2)
ClipString=1
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
X=#Pad#
Y=(#RowTop3# + #BarDrop#)
Shape=Rectangle 0,0,#BarW#,#BarH#,(#BarH#/2) | Fill Color #Track# | StrokeWidth 0
Shape2=Rectangle 0,0,(Max(1,(#BarW# * Clamp(#ScopedBar#,0,100) / 100))),#BarH#,(#BarH#/2) | Fill Color #ColorScoped# | StrokeWidth 0
DynamicVariables=1
Hidden=(1 - #ScopedOn#)
Group=Bars
ToolTipTitle=Weekly #ThirdLabel#
ToolTipText=#ScopedCountdown##CRLF#Per-model limits apply only to plans that grant a separate allowance.

[ScopedReset]
Meter=String
X=#Pad#
Y=(#RowTop3# + #CapDrop#)
FontFace=#FontFace#
FontSize=#SmallFS#
FontColor=#Dim#
Text=resets #ScopedCountdown#
; Bounded so it truncates instead of running into its neighbour.
W=#BarW#
H=(#SmallFS# * 2)
ClipString=1
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
Text=#ExtraModel# included
; Bounded: an unbounded String meter grows past the card, and every value
; here is arbitrary length. ClipString=1 needs both W and H.
W=#BarW#
H=(#SmallFS# * 2)
ClipString=1
AntiAlias=1
DynamicVariables=1
Hidden=(1 - #ExtraOn#)
Group=Live

; ================================================================== footer ====
[LuneFoot]
Meter=String
X=#Pad#
Y=#FootY#
FontFace=#FontFace#
FontSize=#SmallFS#
FontColor=#Dim#
Text=#TokensToday# today  -  #LastUpdated#
; Bounded: an unbounded String meter grows past the card, and every value
; here is arbitrary length. ClipString=1 needs both W and H.
W=#BarW#
H=(#SmallFS# * 2)
ClipString=1
AntiAlias=1
DynamicVariables=1
Group=Live
ToolTipText=When this reading was fetched
