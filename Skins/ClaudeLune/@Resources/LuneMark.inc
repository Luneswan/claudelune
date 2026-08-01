; ClaudeLune - the brand mark, drawn as vector geometry
; Lunez (luneswan). MIT licence - see LICENSE.txt.
;
; No image file and no emoji. Emoji rendered as text pick up whatever fallback
; font Windows happens to substitute, which is why they never looked the same on
; two machines; geometry renders identically everywhere, recolours with the theme
; and stays crisp at any scale.
;
; The mark is pixel art, so rectangles reproduce it exactly - this is not an
; approximation of the artwork, it IS the artwork on an 11 x 7 grid:
;
;      . . # # # # # # # . .      y0   head
;      . . # O # # # O # . .      y1   eyes (O = knocked out)
;      . . # # # # # # # . .      y2
;      # # # # # # # # # # #      y3   arms span the full width
;      # # # # # # # # # # #      y4
;      . . # . # . # . # . .      y5   four legs, three gaps
;      . . # . # . # . # . .      y6
;
; LogoPx is the size of one cell, resolved from the size preset and the icon
; scale, so the whole mark follows a single number. Shapes paint in declaration
; order, which is why the eyes come last and sit on top of the head.

[Variables]
; LogoPx is NOT defined here, and that is the point.
;
; This file is @Include4; LuneResolved.inc, which carries the resolved cell size,
; is @Include2. Later includes win, so a fallback declared here quietly overwrote
; the resolved value on every load and pinned the mark at one size. Neither the
; icon scale nor the overall scale could move it: both feed LogoPx, and LogoPx
; was being replaced after they had been applied.
;
; The fallback lives in LuneSettings.inc instead, which is @Include1, so the
; resolved value still overrides it and the mark still draws before the first
; poll has run.

; --- body, in the brand colour -----------------------------------------------
LogoS1=Rectangle (2*#LogoPx#),0,(7*#LogoPx#),(3*#LogoPx#) | Fill Color #Brand# | StrokeWidth 0
LogoS2=Rectangle 0,(3*#LogoPx#),(11*#LogoPx#),(2*#LogoPx#) | Fill Color #Brand# | StrokeWidth 0
LogoS3=Rectangle (2*#LogoPx#),(5*#LogoPx#),#LogoPx#,(2*#LogoPx#) | Fill Color #Brand# | StrokeWidth 0
LogoS4=Rectangle (4*#LogoPx#),(5*#LogoPx#),#LogoPx#,(2*#LogoPx#) | Fill Color #Brand# | StrokeWidth 0
LogoS5=Rectangle (6*#LogoPx#),(5*#LogoPx#),#LogoPx#,(2*#LogoPx#) | Fill Color #Brand# | StrokeWidth 0
LogoS6=Rectangle (8*#LogoPx#),(5*#LogoPx#),#LogoPx#,(2*#LogoPx#) | Fill Color #Brand# | StrokeWidth 0

; --- eyes, painted over the head ---------------------------------------------
LogoS7=Rectangle (3*#LogoPx#),#LogoPx#,#LogoPx#,#LogoPx# | Fill Color 0,0,0,255 | StrokeWidth 0
LogoS8=Rectangle (7*#LogoPx#),#LogoPx#,#LogoPx#,#LogoPx# | Fill Color 0,0,0,255 | StrokeWidth 0

; --- footprint, for laying out whatever sits beside it -----------------------
LogoW=(11*#LogoPx#)
LogoH=(7*#LogoPx#)
; Horizontal room the mark needs, plus a gap. Titles offset by this so they can
; never sit on top of it - the old fixed 16px was narrower than the mark itself
; (11 * LogoPx = 22px at the default scale), which is why it overlapped. Reads
; zero when the mark is hidden, so the title reclaims the space.
LogoOffset=(#ShowLogo# * ((11*#LogoPx#) + 9))

; Vertical nudge that puts the mark on the same optical baseline as the text
; beside it: half the difference between the line box and the mark, plus a
; fraction of the type size for the ascender. Measured at 3px high before this
; existed, 0px after. Expressed as a fraction of the font size rather than a
; constant, so it holds at every scale.        -- luneswan --
LogoLift=(((#TitleFS# * 1.35) - (7 * #LogoPx#)) / 2 + (#TitleFS# * 0.30))
LogoLiftLabel=(((#LabelFS# * 1.35) - (7 * #LogoPx#)) / 2 + (#LabelFS# * 0.30))
LogoLiftSmall=(((#SmallFS# * 1.35) - (7 * #LogoPx#)) / 2 + (#SmallFS# * 0.30))
