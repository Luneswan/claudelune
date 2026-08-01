; ClaudeLune - SMALL layout: a glanceable strip, three bars and the numbers.
; Lunez (luneswan). MIT licence - see LICENSE.txt.
;
; Every position below comes from LuneResolved.inc. Nothing here is a literal,
; which is what makes the Height, Row spacing, Text size and Bar thickness
; settings reflow this layout without editing it.
;
;   BodyY    top of the first row
;   RowH     full row pitch, including the gap that follows it
;   BarDrop  label top -> bar top
;   PadB     bottom padding

[Variables]
; Preference and availability are different reasons to leave a row out, and
; either should also reclaim its height rather than leave a gap behind.
ScopedOn=(#ShowScoped# * #ScopedAvailable#)
RowCount=(2 + #ScopedOn#)
; The last row contributes its content but not its trailing gap; the bottom
; padding takes that place instead.
PanelH=(#BodyY# + (#RowH# * #RowCount#) - #GapM# + #PadB#)

RowTop1=#BodyY#
RowTop2=(#BodyY# + #RowH#)
RowTop3=(#BodyY# + (#RowH# * 2))

[LunePanel]
Meter=Shape
Shape=Rectangle 0,0,#W#,#PanelH#,#CornerRadius# | Fill Color #Bg# | Stroke Color #Stroke# | StrokeWidth #BorderWidth#
DynamicVariables=1

; ================================================================== header ====
[LuneLogo]
Meter=Shape
X=#Pad#
Y=(#HeadY# + #LogoLiftSmall#)
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

[LunePlan]
Meter=String
X=(#Pad# + #LogoOffset#)
Y=#HeadY#
FontFace=#FontFace#
FontSize=#SmallFS#
FontWeight=600
FontColor=#Accent#
Text=#AccountPlan#
AntiAlias=1
DynamicVariables=1
Group=Live
ToolTipText=#AccountName##CRLF#Renews #PlanRenews#

[LuneDot]
Meter=Shape
X=(#W# - #Pad# - 8)
Y=(#HeadY# + 1)
Shape=Ellipse 4,4,4 | Fill Color #DotColor# | StrokeWidth 0
DynamicVariables=1
Group=Live
ToolTipText=#Status##CRLF#Last sample #LastUpdated#
LeftMouseUpAction=[!SetVariable Refreshing 1][!UpdateMeasure MeasureLuneStatusDot][!UpdateMeter LuneDot][!Redraw][!CommandMeasure MeasureLuneForce "Run"]

; =============================================== session -- luneswan -- =======
; Label and value share a line; the bar sits under them at full width. At this
; width the bar would overlap the value if it tried to share the line.
[SessionLabel]
Meter=String
X=#Pad#
Y=#RowTop1#
FontFace=#FontFace#
FontSize=#SmallFS#
FontColor=#Dim#
Text=5-hour
AntiAlias=1
DynamicVariables=1

[SessionValue]
Meter=String
X=(#W# - #Pad#)
Y=#RowTop1#
FontFace=#FontFace#
FontSize=#SmallFS#
FontWeight=600
FontColor=#Text#
StringAlign=Right
Text=#FiveHourShown#%
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
ToolTipText=5-hour: #FiveHourShown#% #UsageWord##CRLF#Resets #FiveHourCountdown#

; ================================================== weekly, all models ========
[WeeklyLabel]
Meter=String
X=#Pad#
Y=#RowTop2#
FontFace=#FontFace#
FontSize=#SmallFS#
FontColor=#Dim#
Text=Weekly
AntiAlias=1
DynamicVariables=1

[WeeklyValue]
Meter=String
X=(#W# - #Pad#)
Y=#RowTop2#
FontFace=#FontFace#
FontSize=#SmallFS#
FontWeight=600
FontColor=#Text#
StringAlign=Right
Text=#SevenDayShown#%
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
ToolTipText=Weekly: #SevenDayShown#% #UsageWord##CRLF#Resets #SevenDayCountdown#

; ============================ scoped model limit, only when the plan has one ==
[ScopedLabel]
Meter=String
X=#Pad#
Y=#RowTop3#
FontFace=#FontFace#
FontSize=#SmallFS#
FontColor=#Dim#
Text=#ThirdLabel#
AntiAlias=1
DynamicVariables=1
Hidden=(1 - #ScopedOn#)
Group=Live

[ScopedValue]
Meter=String
X=(#W# - #Pad#)
Y=#RowTop3#
FontFace=#FontFace#
FontSize=#SmallFS#
FontWeight=600
FontColor=#Text#
StringAlign=Right
Text=#ScopedShown#%
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
ToolTipText=#ThirdLabel#: #ScopedShown#% #UsageWord##CRLF#Resets #ScopedCountdown#
