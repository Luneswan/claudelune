<#
.SYNOPSIS
    ClaudeLune - reads the account's live Claude Code limits and publishes them
    to the running Rainmeter panel.

.DESCRIPTION
    ClaudeLune by Lunez (luneswan).

    One process does three jobs, in this order:

      1. RESOLVE   the chosen theme, size and scale factors into LuneResolved.inc,
                   which is the single place any layout reads its geometry from.
      2. READ      the usage endpoint with the OAuth token Claude Code already
                   holds, falling back to the desktop app's local history.
      3. PUBLISH   the figures into LuneLive.inc and refresh the skin only when
                   the shape of the panel actually changed.

    Sources, all local and all readable without asking anyone to sign in:

      The OAuth token, searched for rather than assumed. In order: the
      CLAUDE_CODE_OAUTH_TOKEN or ANTHROPIC_AUTH_TOKEN environment variable, the
      file that answered last time, then

              %USERPROFILE%\.claude\.credentials.json
              %USERPROFILE%\.config\claude\.credentials.json
              %CLAUDE_CONFIG_DIR%\.credentials.json
              %APPDATA%\Claude, %LOCALAPPDATA%\Claude, and the rest

          then the Windows credential store, then a bounded sweep of those
          directories for any JSON holding one. Claude Code has moved this file
          before and will again; the sweep is what makes that a non-event.
          Read only. Nothing is ever written back, so this cannot invalidate the
          session it borrows.

      %USERPROFILE%\.claude.json
          oauthAccount { displayName, organizationType, organizationRateLimitTier,
                         subscriptionCreatedAt, organizationUuid }
          additionalModelOptionsCache { value, label, description }

      %APPDATA%\Claude\plan-usage-history.json
          { "version": 2, "samples": [ { "t": <epoch ms>, "org": "<uuid>",
                                         "u": { "fh": 1, "sd": 76 } } ] }
          fh = five-hour utilisation %, sd = seven-day utilisation %. Samples are
          tagged by organisation, so filtering by the signed-in org makes the
          panel follow an account switch by itself.

      %APPDATA%\Claude\buddy-tokens.json
          { "tokens-today": { "date": "2026-07-28", "tokens": 224250 } }

.EXAMPLE
    .\Update-LuneUsage.ps1 -Verbose

.EXAMPLE
    .\Update-LuneUsage.ps1 -ResolveOnly -Theme Amoled -Size Large

.NOTES
    Copyright (c) Lunez (luneswan). MIT licence - see LICENSE.txt.
    Written for Windows PowerShell 5.1, which is the version every Windows machine
    ships with. Nothing here requires PowerShell 7.
#>

[CmdletBinding()]
param(
    # Skin CONFIG NAME to push into - the folder under Skins, not the .ini path.
    # !SetVariable rejects "ClaudeLune\ClaudeLune.ini" as "not active"; only
    # !ActivateConfig takes the config-plus-file form.
    [string]$SkinConfig = 'ClaudeLune',

    # Preset switches; names must match a block in LunePresets.inc.
    [string]$Theme,
    [string]$Size,
    [string]$Opacity,

    # Regenerate LuneResolved.inc and exit without reading usage.
    [Alias('PresetOnly')]
    [switch]$ResolveOnly,

    <#
    Write the files but never refresh the skin.

    "-SkinConfig ''" used to mean this. It does not survive powershell.exe -File,
    which drops an empty argument and then rejects the call for a missing value, so
    every run meant to be silent failed outright and left the previous output in
    place - a test harness reading stale files and reporting success on them. An
    explicit switch cannot be swallowed.
    #>
    [switch]$NoRefresh,

    <#
    A user-initiated refresh. Ignores both the throttle window and the
    reuse-within-interval short circuit, so pressing "Refresh now" always issues a
    real request. Without this the button did nothing at all during a backoff -
    which is exactly when someone reaches for it - and looked broken.

    The single-flight lock still applies: forcing is not permission to stack
    concurrent requests, only to skip the wait.
    #>
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

# ---------------------------------------------------------------- identity ----
# Stamped into every generated file and into the exported JSON, so a copy of the
# output can always be traced back to the build it came from.
$LuneProduct = 'ClaudeLune'
$LuneAuthor  = 'Lunez'
$LuneHandle  = 'luneswan'
$LuneVersion = '1.3.0'
$LuneStamp   = "; $LuneProduct $LuneVersion - $LuneAuthor ($LuneHandle). Generated file, edits are overwritten."

# ------------------------------------------------------------------- paths ----

$LuneResourceDir = Split-Path $PSScriptRoot -Parent
$LunePresetsPath = Join-Path $LuneResourceDir 'LunePresets.inc'
$LuneConfigPath  = Join-Path $LuneResourceDir 'LuneSettings.inc'
$LuneLayoutPath  = Join-Path $LuneResourceDir 'LuneResolved.inc'
$LuneLivePath    = Join-Path $LuneResourceDir 'LuneLive.inc'

$LuneHistoryPath = Join-Path $env:APPDATA     'Claude\plan-usage-history.json'
$LuneAccountPath = Join-Path $env:USERPROFILE '.claude.json'
$LuneTokensPath  = Join-Path $env:APPDATA     'Claude\buddy-tokens.json'
$LuneStateDir    = Join-Path $env:APPDATA     'ClaudeLune'
$LuneExportPath  = Join-Path $LuneStateDir    'usage.json'
$LuneTrendPath   = Join-Path $LuneStateDir    'weekly-history.json'

if (-not (Test-Path -LiteralPath $LuneStateDir)) {
    New-Item -ItemType Directory -Path $LuneStateDir -Force | Out-Null
}

# ============================================================= -- luneswan -- ==
# SECTION 1  Small helpers
# ==============================================================================

function Get-LuneProperty {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $null }
    return $prop.Value
}

<#
Reads JSON, allowing for the fact that something else may be writing it.

The Claude desktop app rewrites its history file every few minutes, and a read
that lands mid-write returns a truncated document that will not parse. Treating
that as "no data" is wrong twice over: the data exists, and the panel reacts by
blanking the seven-day trend for a cycle - observed live, with the trend reporting
a range of 0-0% while the file on disk held a full week sweeping 4% to 100%.

Two quick retries cover a write that takes a few milliseconds, which is what these
files take. A file that is genuinely missing or genuinely corrupt still returns
nothing, promptly.
#>
function Read-LuneJson {
    # Quiet is for the token sweep, which reads a few hundred unrelated JSON files
    # on purpose. Most of them not parsing is the expected result, not news.
    param([string]$Path, [int]$Attempts = 3, [switch]$Quiet)

    if (-not (Test-Path -LiteralPath $Path)) { return $null }

    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        $failure = $null
        try {
            $text = Get-Content -LiteralPath $Path -Raw
            <#
            An empty read is a failure that does not throw, and that is the whole
            problem. A file caught mid-rewrite reads back as an empty string,
            ConvertFrom-Json turns that into nothing at all without complaint, and
            the caller sees "no data" rather than "try again".

            Measured: the skin's own poll reported 0 samples while an identical
            command run by hand seconds later read 1,929 from the same file, and
            the seven-day trend went flat because of it. Retrying only on a thrown
            error never helped, because nothing was ever thrown.
            #>
            if (-not [string]::IsNullOrWhiteSpace($text)) {
                $parsed = $text | ConvertFrom-Json
                if ($null -ne $parsed) { return $parsed }
            }
            $failure = 'the file read back empty'
        } catch {
            $failure = $_.Exception.Message
        }

        if ($attempt -eq $Attempts) {
            if (-not $Quiet) {
                Write-Verbose "Unreadable JSON at ${Path} after $Attempts attempts: $failure"
            }
            return $null
        }
        Start-Sleep -Milliseconds 120
    }
}

<#
Writes JSON by renaming a temporary file over the target, never in place.

Set-Content truncates the file and then rewrites it, which leaves a window where
the file on disk is empty or half a document. Two pollers overlap routinely - the
scheduled tick and the poll a refresh starts - and the stress test reproduces the
result: eight writers against one store, and the JSON came back unparseable.

A rename on NTFS is atomic, so a reader sees either the whole old file or the
whole new one. Readers already retry and refuse to write after a failed read;
this closes the other half, where the damage was being written in the first place.

The temporary name carries the process id, so two writers cannot collide on it.
#>
function Write-LuneJsonFile {
    param([string]$Path, [string]$Json, [int]$Attempts = 3)

    $temp = '{0}.{1}.tmp' -f $Path, $PID
    try {
        [System.IO.File]::WriteAllText($temp, $Json, (New-Object System.Text.UTF8Encoding($false)))
        for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
            try {
                Move-Item -LiteralPath $temp -Destination $Path -Force
                return $true
            } catch {
                # The destination can be held open for a moment by a reader.
                if ($attempt -eq $Attempts) { throw }
                Start-Sleep -Milliseconds 80
            }
        }
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
    }
    return $false
}

function Get-LuneDaySuffix {
    param([int]$Day)
    switch ($Day) {
        { $_ -in 1, 21, 31 } { 'st'; break }
        { $_ -in 2, 22 }     { 'nd'; break }
        { $_ -in 3, 23 }     { 'rd'; break }
        default              { 'th' }
    }
}

function Format-LuneStamp {
    param([DateTime]$Local, [switch]$DateOnly)
    $base = '{0} {1}{2} {3}' -f $Local.ToString('ddd'), $Local.Day,
                                (Get-LuneDaySuffix -Day $Local.Day), $Local.ToString('MMM')
    if ($DateOnly) { return $base }
    return '{0}, {1}' -f $base, $Local.ToString('h:mmtt').ToLower()
}

function Format-LuneCountdown {
    param([TimeSpan]$Span)
    if ($Span.TotalSeconds -le 0) { return 'now' }
    $days = [Math]::Floor($Span.TotalDays)
    if ($days -gt 0)       { return '{0}d {1}h' -f $days, $Span.Hours }
    if ($Span.Hours -gt 0) { return '{0}h {1}m' -f $Span.Hours, $Span.Minutes }
    return '{0}m' -f $Span.Minutes
}

function ConvertFrom-LuneEpoch {
    param([double]$Milliseconds)
    return [DateTime]::new(1970, 1, 1, 0, 0, 0, [DateTimeKind]::Utc).AddMilliseconds($Milliseconds)
}

function ConvertTo-LuneEpoch {
    param([DateTime]$Value)
    return [DateTimeOffset]::new([DateTime]::SpecifyKind($Value, [DateTimeKind]::Utc)).ToUnixTimeMilliseconds()
}

# The API returns resets_at as an ISO string with an offset, but PowerShell's JSON
# reader may already have turned it into a DateTime. Accept either.
function ConvertTo-LuneUtc {
    param($Value)
    if (-not $Value) { return $null }
    try {
        if ($Value -is [DateTime])       { return $Value.ToUniversalTime() }
        if ($Value -is [DateTimeOffset]) { return $Value.UtcDateTime }
        return [DateTimeOffset]::Parse([string]$Value, $null,
            [System.Globalization.DateTimeStyles]::AssumeUniversal).UtcDateTime
    } catch {
        Write-Verbose "Unparseable reset time '$Value': $($_.Exception.Message)"
        return $null
    }
}

# ==============================================================================
# SECTION 2  Reading and writing .inc files
# ==============================================================================

<#
Each file is parsed at most once per run and kept.

The settings file used to be read three separate times and the preset file twice,
for values that cannot change while the process is alive.
#>
$script:LuneIncCache = @{}

# Where the token came from, and why there wasn't one. Set during the fetch, read
# when the status line is written: 'ok' until something says otherwise, then
# 'signedout' (a credentials store exists but holds nothing usable) or 'missing'
# (no store at all).
$script:LuneAuthState = 'ok'
$script:LuneTokenPath = $null

function Read-LuneInc {
    param([string]$Path, [switch]$Fresh)

    if (-not $Fresh -and $script:LuneIncCache.ContainsKey($Path)) {
        return $script:LuneIncCache[$Path]
    }
    $map = @{}
    if (Test-Path -LiteralPath $Path) {
        foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
            if ($line -match '^\s*([A-Za-z0-9_]+)\s*=\s*(.*?)\s*$') { $map[$Matches[1]] = $Matches[2] }
        }
    }
    $script:LuneIncCache[$Path] = $map
    return $map
}

<#
Writes several keys in one pass.

Rewriting in place keeps the comments that make the file editable by hand; a
regenerated file would lose every explanation in it. Taking a hashtable rather
than one key at a time means switching theme, size and opacity together costs one
read and one write instead of three of each.
#>
function Set-LuneIncValue {
    param([string]$Path, [hashtable]$Values)

    if (-not $Values -or $Values.Count -eq 0) { return }
    if (-not (Test-Path -LiteralPath $Path))  { return }

    $lines   = [System.IO.File]::ReadAllLines($Path)
    $pending = @{}
    foreach ($key in $Values.Keys) { $pending[$key] = $true }

    $out = foreach ($line in $lines) {
        $replaced = $false
        if ($line -match '^\s*([A-Za-z0-9_]+)\s*=') {
            $key = $Matches[1]
            if ($pending.ContainsKey($key)) {
                "$key=$($Values[$key])"
                [void]$pending.Remove($key)
                $replaced = $true
            }
        }
        if (-not $replaced) { $line }
    }
    $out = @($out)
    foreach ($key in @($pending.Keys)) { $out += "$key=$($Values[$key])" }

    [System.IO.File]::WriteAllLines($Path, $out, (New-Object System.Text.ASCIIEncoding))
    # The cached copy is now behind the file it came from.
    [void]$script:LuneIncCache.Remove($Path)
}

# Rainmeter's INI parser tolerates ANSI and UTF-16 LE. A UTF-8 BOM is read as part
# of the first key name, which silently breaks whatever that key drives.
function Write-LuneIncFile {
    param([string]$Path, [string[]]$Lines)
    [System.IO.File]::WriteAllLines($Path, $Lines, (New-Object System.Text.UnicodeEncoding($false, $true)))
}

# ============================================================= -- luneswan -- ==
# SECTION 3  Geometry - the one place the panel's proportions are decided
# ==============================================================================

<#
Geometry for all four layouts. Layouts read these variables instead of carrying
literals, so one scale change reflows every size.

Vertical rhythm per row:
    label (LineH) + GapS + bar (BarH) + GapS + caption (CapH, Detail=1 only) + GapM

Every result is clamped. No combination of scales can produce a negative bar,
invisible type, or padding wider than the panel.
#>
function Get-LuneScale {
    param([hashtable]$Config, [string]$Key, [double]$Fallback = 1.0)
    $raw = $Config[$Key]
    if ([string]::IsNullOrWhiteSpace($raw)) { return $Fallback }
    $parsed = 0.0
    if (-not [double]::TryParse($raw, [ref]$parsed)) { return $Fallback }
    if ($parsed -lt 0.5) { return 0.5 }
    if ($parsed -gt 2.0) { return 2.0 }
    return $parsed
}

function Get-LuneClamped {
    param([double]$Value, [int]$Minimum, [int]$Maximum)
    $rounded = [int][Math]::Round($Value)
    if ($rounded -lt $Minimum) { return $Minimum }
    if ($rounded -gt $Maximum) { return $Maximum }
    return $rounded
}

<#
Line height from the font's own metrics rather than a constant. 1.45 was used
first; of the 315 families installed here 63 exceed it (DecoType Naskh 2.10, Sans
Serif Collection 2.65), and captions overlapped on all of them.

Clamped, because a corrupt face can report something absurd, and cached, because
one resolve calls this six times for the same font.
#>
$script:LuneLineRatio = $null

function Get-LuneLineRatio {
    param([string]$FontFace)

    if ($null -ne $script:LuneLineRatio) { return $script:LuneLineRatio }

    $ratio = 1.45
    if ($FontFace) {
        try {
            Add-Type -AssemblyName System.Drawing -ErrorAction Stop
            $family = New-Object System.Drawing.FontFamily($FontFace)
            try {
                $style = [System.Drawing.FontStyle]::Regular
                if (-not $family.IsStyleAvailable($style)) { $style = [System.Drawing.FontStyle]::Bold }
                $spacing = $family.GetLineSpacing($style)
                $em      = $family.GetEmHeight($style)
                if ($em -gt 0) { $ratio = [double]$spacing / [double]$em }
            } finally { $family.Dispose() }
        } catch {
            # An unknown font name is not an error: Rainmeter falls back to a
            # default face, and so does this.
            Write-Verbose "Could not measure '$FontFace'; using the default line ratio."
        }
    }

    if ($ratio -lt 1.15) { $ratio = 1.15 }
    if ($ratio -gt 3.00) { $ratio = 3.00 }
    $script:LuneLineRatio = $ratio
    return $ratio
}

function Get-LuneLineHeight {
    param([int]$FontSize, [double]$Ratio = 1.45)
    return [int][Math]::Ceiling($FontSize * $Ratio)
}

<#
An override replaces one entry of the theme's palette. Re-applying a theme clears
them, which is what makes picking a theme a way back to a known state.

Must be "R,G,B" or "R,G,B,A". Anything else falls back to the theme, so a typo
costs one colour rather than the panel.

Named Custom*, not Color*: NormalColor and the rest already exist as live values.
#>
function Get-LunePaletteColor {
    param([hashtable]$Config, [string]$Key, [string]$Preset)

    $override = $Config["Custom$Key"]
    if ([string]::IsNullOrWhiteSpace($override)) { return $Preset }
    if ($override -notmatch '^\s*\d{1,3}\s*,\s*\d{1,3}\s*,\s*\d{1,3}(\s*,\s*\d{1,3})?\s*$') {
        Write-Verbose "Ignoring malformed override Custom$Key='$override'."
        return $Preset
    }
    foreach ($channel in ($override -split ',')) {
        if ([int]$channel.Trim() -gt 255) {
            Write-Verbose "Ignoring out-of-range override Custom$Key='$override'."
            return $Preset
        }
    }
    return ($override -replace '\s', '')
}

# A Rainmeter colour with its alpha replaced. Used to derive the chart's own tones
# from whatever the accent resolved to, so they follow a theme AND an override
# instead of being a fourteenth thing to keep in step by hand.
function Set-LuneColorAlpha {
    param([string]$Color, [int]$Alpha)

    $parts = @(($Color -split ',') | ForEach-Object { $_.Trim() })
    if ($parts.Count -lt 3) { return $Color }
    return ('{0},{1},{2},{3}' -f $parts[0], $parts[1], $parts[2], [Math]::Max(0, [Math]::Min(255, $Alpha)))
}

# Resolves the chosen theme and size into LuneResolved.inc under generic names, so
# no layout file has to know which preset is active.
function Write-LuneResolvedLayout {

    $config  = Read-LuneInc $LuneConfigPath
    $presets = Read-LuneInc $LunePresetsPath

    $switches = @{}
    if ($Theme)   { $switches['Theme']   = $Theme }
    if ($Size)    { $switches['Size']    = $Size }
    if ($Opacity) { $switches['Opacity'] = $Opacity }
    if ($switches.Count -gt 0) {
        Set-LuneIncValue -Path $LuneConfigPath -Values $switches
        foreach ($key in $switches.Keys) { $config[$key] = $switches[$key] }
    }

    $theme   = $config['Theme'];   if (-not $theme)   { $theme   = 'Dark' }
    $size    = $config['Size'];    if (-not $size)    { $size    = 'Normal' }
    $opacity = $config['Opacity']; if (-not $opacity) { $opacity = '240' }

    if (-not $presets.ContainsKey("${theme}Bg")) { Write-Verbose "Unknown theme '$theme'; using Dark."; $theme = 'Dark' }
    if (-not $presets.ContainsKey("${size}W"))   { Write-Verbose "Unknown size '$size'; using Normal.";  $size  = 'Normal' }

    # ---- scale axes ----------------------------------------------------------
    $kAll    = Get-LuneScale $config 'UserScale'
    $kWidth  = Get-LuneScale $config 'WidthScale'
    $kHeight = Get-LuneScale $config 'HeightScale'
    $kFont   = Get-LuneScale $config 'FontScale'
    $kPad    = Get-LuneScale $config 'PadScale'
    $kIcon   = Get-LuneScale $config 'IconScale'
    $kRow    = Get-LuneScale $config 'RowScale'
    $kBar    = Get-LuneScale $config 'BarScale'

    # ---- horizontal ----------------------------------------------------------
    $width = Get-LuneClamped ([int]$presets["${size}W"]   * $kAll * $kWidth) 170 1400
    $pad   = Get-LuneClamped ([int]$presets["${size}Pad"] * $kAll * $kPad)     4   60

    # Padding loses to the bar. Someone winding padding up should get a narrower
    # bar, never a bar with no length, and never one that inverts.
    $minimumBar = 90
    if (($width - 2 * $pad) -lt $minimumBar) {
        $pad = [Math]::Max(2, [int](($width - $minimumBar) / 2))
    }
    $barWidth = $width - (2 * $pad)

    # ---- type ----------------------------------------------------------------
    $titleFS = Get-LuneClamped ([int]$presets["${size}Title"]  * $kAll * $kFont) 7 34
    $labelFS = Get-LuneClamped ([int]$presets["${size}Label"]  * $kAll * $kFont) 6 30
    $smallFS = Get-LuneClamped ([int]$presets["${size}Small"]  * $kAll * $kFont) 6 26

    <#
    Type is also capped by the width it has to fit into, not only by its own range.

    FontScale and WidthScale move independently, so 2.0 type in a 0.5 panel was a
    supported combination that could not possibly fit: measured, the weekly row
    ran 396px past a 304px card. The absolute clamps never saw it, because
    individually both values were legal.

    The budgets are the character counts each layout's widest row actually draws -
    "Weekly - all models" beside "100% used" is 28 - and 0.75 is a per-character
    advance wide enough to cover the fonts people pick, monospace included. At
    default scales these caps sit above what the presets ask for and change
    nothing; they only bite when a combination would otherwise overflow.

    Clipping still backs this up. This keeps the panel legible; clipping keeps it
    correct.
    #>
    $labelBudget = switch ($size) { 'Small' { 18 } 'Wide' { 16 } default { 28 } }
    $smallBudget = switch ($size) { 'Small' { 20 } 'Wide' { 18 } default { 26 } }
    $titleBudget = 14

    $labelFS = [Math]::Min($labelFS, [Math]::Max(6, [int]($barWidth / ($labelBudget * 0.75))))
    $smallFS = [Math]::Min($smallFS, [Math]::Max(6, [int]($barWidth / ($smallBudget * 0.75))))
    $titleFS = [Math]::Min($titleFS, [Math]::Max(7, [int]($barWidth / ($titleBudget * 0.75))))
    $logoPx  = Get-LuneClamped ([int]$presets["${size}LogoPx"] * $kAll * $kIcon) 1  8

    # The row pitch follows the chosen typeface, not an assumption about it.
    $lineRatio = Get-LuneLineRatio $config['FontFace']
    $titleH = Get-LuneLineHeight $titleFS $lineRatio
    $lineH  = Get-LuneLineHeight $labelFS $lineRatio
    $capH   = Get-LuneLineHeight $smallFS $lineRatio

    # ---- vertical rhythm -----------------------------------------------------
    $barH    = Get-LuneClamped ([int]$presets["${size}Bar"] * $kAll * $kBar) 2 26
    $gapBase = [int]$presets["${size}Gap"]

    $gapS  = Get-LuneClamped (4 * $kAll * $kHeight)                 1 22
    $gapM  = Get-LuneClamped ($gapBase * $kAll * $kHeight * $kRow)   2 64
    $gapL  = Get-LuneClamped ($gapBase * 1.35 * $kAll * $kHeight)    3 80
    $headY = Get-LuneClamped ($pad * 0.85 * $kAll * $kHeight)        4 64
    $padB  = Get-LuneClamped ($pad * 0.80 * $kAll * $kHeight)        4 64

    $showDetail = [int]$presets["${size}Detail"]

    $barDrop = $lineH + $gapS                       # label top -> bar top
    $capDrop = $barDrop + $barH + $gapS             # label top -> caption top
    $rowH    = if ($showDetail -eq 1) { $capDrop + $capH + $gapM } else { $barDrop + $barH + $gapM }

    $bodyY = $headY + $titleH + $gapL               # header block -> first row
    $footH = $capH + $gapS

    # The trend strip scales with height like everything else, and keeps a floor
    # below which twenty-four columns stop being distinguishable at all.
    $trendH = Get-LuneClamped (26 * $kAll * $kHeight) 12 90

    # The wide layout puts three cells on one band; its gutter tracks padding so
    # the cells never touch at a small width.
    $cellGap = Get-LuneClamped ($pad * 0.9 * $kAll) 6 40

    # Reported so the settings window can show what a scale actually produced,
    # rather than echoing the number the user typed.
    $sampleHeight = $bodyY + ($rowH * 3) + $padB

    <#
    A theme choice clears the colour overrides whichever route chose it. The settings
    window already did; the right-click menu wrote Theme alone, so on a customised
    panel it appeared to do nothing.

    Decided here so every route agrees, including a hand-edited file. AppliedTheme in
    the generated file records what was last drawn.
    #>
    $palette = @(
        @('Bg',          'Bg'),
        @('Stroke',      'Stroke'),
        @('Text',        'Text'),
        @('Dim',         'Dim'),
        @('Bright',      'Bright'),
        @('Accent',      'Accent'),
        @('Track',       'Track'),
        @('NormalColor', 'Normal'),
        @('ScopedColor', 'Scoped'),
        @('WarnColor',   'Warn'),
        @('CritColor',   'Crit'),
        @('OffColor',    'Off')
    )

    $lastApplied = (Read-LuneInc $LuneLayoutPath)['AppliedTheme']
    if ($lastApplied -and $lastApplied -ne $theme) {
        $cleared = @{}
        foreach ($entry in $palette) { $cleared["Custom$($entry[1])"] = '' }
        Set-LuneIncValue -Path $LuneConfigPath -Values $cleared
        foreach ($key in $cleared.Keys) { $config[$key] = '' }
        Write-Verbose "Theme changed from $lastApplied to $theme; colour overrides cleared."
    }

    $lines = @(
        $LuneStamp,
        "; theme=$theme size=$size opacity=$opacity width=$width",
        '[Variables]',
        "AppliedTheme=$theme"
    )

    $resolved = @{}
    foreach ($entry in $palette) {
        $value = Get-LunePaletteColor $config $entry[1] $presets[$theme + $entry[1]]
        # Opacity rides on the background, so it is appended after any override.
        if ($entry[0] -eq 'Bg') { $value = "$value,$opacity" }
        $resolved[$entry[0]] = $value
        $lines += ('{0}={1}' -f $entry[0], $value)
    }

    # The trend chart's two extra tones, derived rather than declared: the gradient
    # a filled column fades into, and the trough drawn under every column.
    $lines += ('AccentSoft={0}'  -f (Set-LuneColorAlpha $resolved['Accent'] 105))
    # Faint on purpose. At anything stronger the troughs stopped reading as the
    # space a column could fill and started reading as columns already full,
    # which on a black theme made an idle day look like a saturated one.
    $lines += ('AccentGhost={0}' -f (Set-LuneColorAlpha $resolved['Accent'] 20))

    $lines += @(
        '; ---- geometry, derived from the size preset and the scale axes -------',
        "W=$width",
        "Pad=$pad",
        "BarW=$barWidth",
        "BarH=$barH",
        "TitleFS=$titleFS",
        "LabelFS=$labelFS",
        "SmallFS=$smallFS",
        "TitleH=$titleH",
        "LineH=$lineH",
        "CapH=$capH",
        "GapS=$gapS",
        "GapM=$gapM",
        "GapL=$gapL",
        "HeadY=$headY",
        "BodyY=$bodyY",
        "BarDrop=$barDrop",
        "CapDrop=$capDrop",
        "RowH=$rowH",
        "FootH=$footH",
        "PadB=$padB",
        "TrendH=$trendH",
        "CellGap=$cellGap",
        "LogoPx=$logoPx",
        ('LineRatio={0:0.000}' -f $lineRatio),
        "ShowDetail=$showDetail",
        ('ShowAccount=' + $presets["${size}Account"]),
        ('ShowTrend='   + $presets["${size}Trend"]),
        "LayoutName=$size",
        "EffectiveW=$width",
        "EffectiveH=$sampleHeight",
        "EffectiveRow=$rowH"
    )

    # ---- context menu state --------------------------------------------------
    # The menu is built from these so each entry shows whether it is the active
    # choice, and so the row toggles read as one action instead of a show/hide
    # pair. Regenerated here because this runs on every preset change.
    $marked   = [char]0x25CF   # filled circle - current
    $unmarked = [char]0x25CB   # hollow circle - available

    foreach ($name in @('Small', 'Normal', 'Wide', 'Large')) {
        $lines += ('MarkSize{0}={1}' -f $name, $(if ($size -eq $name) { $marked } else { $unmarked }))
    }
    foreach ($name in @('Dark', 'Amoled', 'Glass', 'Light', 'Clay', 'Matrix', 'iOS')) {
        $lines += ('MarkTheme{0}={1}' -f $name, $(if ($theme -eq $name) { $marked } else { $unmarked }))
    }
    foreach ($pair in @(@('Solid', '255'), @('Normal', '240'), @('Translucent', '170'), @('Ghost', '110'))) {
        $lines += ('MarkOpacity{0}={1}' -f $pair[0], $(if ("$opacity" -eq $pair[1]) { $marked } else { $unmarked }))
    }

    <#
    Toggle entries state what the click will do, and carry the value to write.

    They are named after whatever the account actually has rather than after
    "Scoped" and "Fable" literally: the first controls the per-model limit row,
    whose model the API names itself, and the second controls the "<model>
    included" note shown to plans that grant an extra model without a separate cap.
    Fixed names meant the menu offered to hide a Scoped row on an account whose
    scoped limit was something else entirely.
    #>
    $live       = Read-LuneInc $LuneLivePath -Fresh
    $scopedName = $live['ThirdLabel']; if (-not $scopedName) { $scopedName = 'model' }
    $extraName  = $live['ExtraModel']; if (-not $extraName)  { $extraName  = 'extra model' }

    $scopedOn = ($config['ShowScoped'] -ne '0')
    $extraOn  = ($config['ShowFable']  -ne '0')
    $lines += ('ScopedToggleLabel=' + $(if ($scopedOn) { "Hide $scopedName limit row" } else { "Show $scopedName limit row" }))
    $lines += ('ScopedToggleValue=' + $(if ($scopedOn) { '0' } else { '1' }))
    $lines += ('FableToggleLabel='  + $(if ($extraOn)  { "Hide '$extraName included' note" } else { "Show '$extraName included' note" }))
    $lines += ('FableToggleValue='  + $(if ($extraOn)  { '0' } else { '1' }))

    Write-LuneIncFile -Path $LuneLayoutPath -Lines $lines
    Write-Verbose "LuneResolved.inc written: theme=$theme size=$size w=$width rowH=$rowH gapM=$gapM"
}

# ==============================================================================
# SECTION 4  Account
# ==============================================================================

<#
Plan label and renewal date, both derived from Claude Code's own state file.
organizationType is like "claude_max"; organizationRateLimitTier is like
"default_claude_max_5x", whose trailing multiplier is the useful part.
#>
function Get-LuneAccount {
    $blank = [PSCustomObject]@{
        name = ''; plan = ''; uuid = ''; org = ''
        renews = ''; extraModel = ''; extraDesc = ''; hasExtra = 0
    }
    $document = Read-LuneJson $LuneAccountPath
    $account  = Get-LuneProperty $document 'oauthAccount'
    if (-not $account) { return $blank }

    $name = Get-LuneProperty $account 'displayName'
    if (-not $name) { $name = Get-LuneProperty $account 'emailAddress' }

    $type = [string](Get-LuneProperty $account 'organizationType')            # claude_max / claude_pro / ...
    $tier = [string](Get-LuneProperty $account 'organizationRateLimitTier')   # default_claude_max_5x / ...

    <#
    Known plans get their marketing name. Anything else is humanised rather than
    dropped, so a plan introduced after this ships still reads correctly: the
    vendor prefix goes, separators become spaces, the rest is titled. A future
    "claude_startup" shows as "Startup" with no code change.

    Every branch breaks. switch -Regex does not stop at the first match: it runs
    every branch whose pattern matches and collects all their outputs, so
    "enterprise_pro" matched both Enterprise and Pro and the label rendered as the
    string "System.Object[]" on screen. Order plus break gives first-match-wins.
    #>
    $plan = switch -Regex ($type) {
        'enterprise' { 'Enterprise'; break }
        'team'       { 'Team';       break }
        'max'        { 'Max';        break }
        'pro'        { 'Pro';        break }
        'free'       { 'Free';       break }
        default {
            $words = (($type -replace '^claude[_-]?', '') -replace '[_-]+', ' ').Trim()
            if ($words) { (Get-Culture).TextInfo.ToTitleCase($words) } else { '' }
            break
        }
    }
    # Only decorate a plan that has a name. Appending the multiplier to an empty
    # label produced a header reading " 5x" with nothing in front of it.
    if ($plan -and $tier -match '(\d+x)$') { $plan = "$plan $($Matches[1])" }

    # Subscriptions renew on the anniversary of their start date. Clamped to the
    # month length, so a 31st anniversary still lands in a 30-day month.
    $renews  = ''
    $created = Get-LuneProperty $account 'subscriptionCreatedAt'
    if ($created) {
        try {
            $start = [DateTime]$created
            $now   = [DateTime]::Now
            for ($i = 0; $i -le 1; $i++) {
                $probe = $now.AddMonths($i)
                $day   = [Math]::Min($start.Day, [DateTime]::DaysInMonth($probe.Year, $probe.Month))
                $next  = [DateTime]::new($probe.Year, $probe.Month, $day, $start.Hour, $start.Minute, 0)
                if ($next -gt $now) { $renews = Format-LuneStamp -Local $next -DateOnly; break }
            }
        } catch { Write-Verbose "Could not derive renewal date: $($_.Exception.Message)" }
    }

    # Present only on plans that grant an extra model (Max has one; Pro does not).
    $extraModel = ''; $extraDesc = ''; $hasExtra = 0
    $options = Get-LuneProperty $document 'additionalModelOptionsCache'
    if ($options) {
        $extraModel = [string](Get-LuneProperty $options 'label')
        $extraDesc  = [string](Get-LuneProperty $options 'description')
        if ($extraModel) { $hasExtra = 1 }
    }

    return [PSCustomObject]@{
        name       = [string]$name
        plan       = $plan
        uuid       = [string](Get-LuneProperty $account 'accountUuid')
        org        = [string](Get-LuneProperty $account 'organizationUuid')
        renews     = $renews
        extraModel = $extraModel
        extraDesc  = $extraDesc
        hasExtra   = $hasExtra
    }
}

# ============================================================= -- luneswan -- ==
# SECTION 5  Finding the token
# ==============================================================================

<#
Where Claude Code keeps its token is not a fixed address, and this panel used to
assume it was.

It read %USERPROFILE%\.claude\.credentials.json and nothing else. When Claude
Code stopped writing the token there, the panel had no way to tell that apart
from a lapsed session: it found an empty field, served the cached reading, and
kept doing that for seventeen days without ever saying why.

So the token is searched for. Explicit environment variable first, then the file
that answered last time, then the known locations, then the Windows credential
store, then a bounded sweep of the directories Claude Code uses. Whatever answers
is written into the cache as tokenPath, so the sweep happens once and every later
poll goes straight to it.

Everything here reads. Nothing writes to any file Claude Code owns.
#>

<#
Returns the token, cleaned, or nothing if it is not one.

Anthropic's OAuth tokens carry the sk-ant- prefix, and requiring it is what keeps
the sweep from adopting some unrelated application's "accessToken" field.

Trimmed first, because a token that arrives with a space on the front is a token.
Copying one out of a terminal picks up leading whitespace easily, and the strict
check refused it in silence: the panel reported "signed out" at a machine whose
environment variable was set correctly apart from one character.
#>
function Get-LuneCleanToken {
    param($Value)
    if ($Value -isnot [string]) { return $null }
    $trimmed = $Value.Trim().Trim('"').Trim("'").Trim()
    if ($trimmed -like 'sk-ant-*') { return $trimmed }
    return $null
}

function Test-LuneToken {
    param($Value)
    return ($null -ne (Get-LuneCleanToken $Value))
}

<#
Pulls a token out of a parsed credentials document, whatever shape it is in.

Deliberately not a list of known field names. The first version of this checked
claudeAiOauth.accessToken and three spellings beside it, which is the same bet
that broke the panel in the first place, just hedged a little wider - a document
nesting the token under "session" walked straight past it.

So the document is walked instead, and a value is a token because it looks like
one. The expiry is whichever timestamp-shaped sibling sits next to it.
#>
function Read-LuneTokenDocument {
    param($Document, [int]$Depth = 0)

    if ($null -eq $Document -or $Depth -gt 6) { return $null }

    if ($Document -is [System.Collections.IEnumerable] -and $Document -isnot [string]) {
        foreach ($item in $Document) {
            $found = Read-LuneTokenDocument -Document $item -Depth ($Depth + 1)
            if ($found) { return $found }
        }
        return $null
    }

    if ($null -eq $Document.PSObject -or -not $Document.PSObject.Properties) { return $null }
    $properties = @($Document.PSObject.Properties)

    foreach ($property in $properties) {
        $clean = Get-LuneCleanToken $property.Value
        if (-not $clean) { continue }

        # A sibling that names an expiry and holds a number. Milliseconds or
        # seconds, either spelling: ConvertFrom-LuneEpoch sorts out the units.
        $expiry = $null
        foreach ($sibling in $properties) {
            if ($sibling.Name -notmatch 'expir') { continue }
            $value = $sibling.Value
            if ($value -is [string]) { $value = $value -as [double] }
            if ($value) { $expiry = $value; break }
        }
        return @{ Token = $clean; Expiry = $expiry }
    }

    foreach ($property in $properties) {
        $value = $property.Value
        if ($null -eq $value -or $value -is [string] -or $value -is [ValueType]) { continue }
        $found = Read-LuneTokenDocument -Document $value -Depth ($Depth + 1)
        if ($found) { return $found }
    }
    return $null
}

# Directories Claude Code stores configuration in, on this machine, right now.
function Get-LuneTokenRoots {
    $roots = @(
        $env:CLAUDE_CONFIG_DIR
        (Join-Path $env:USERPROFILE '.claude')
        (Join-Path $env:USERPROFILE '.config\claude')
        (Join-Path $env:USERPROFILE '.local\share\claude')
        (Join-Path $env:APPDATA    'Claude')
        (Join-Path $env:APPDATA    'claude-code')
        (Join-Path $env:APPDATA    'Anthropic')
        (Join-Path $env:LOCALAPPDATA 'Claude')
        (Join-Path $env:LOCALAPPDATA 'claude-code')
        (Join-Path $env:LOCALAPPDATA 'Anthropic')
    )
    return @($roots | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique)
}

# The filenames worth trying before resorting to a sweep.
function Get-LuneTokenFiles {
    $files = @()
    foreach ($root in (Get-LuneTokenRoots)) {
        foreach ($name in '.credentials.json', 'credentials.json', '.auth.json', 'auth.json') {
            $path = Join-Path $root $name
            if (Test-Path -LiteralPath $path) { $files += $path }
        }
    }
    return @($files | Select-Object -Unique)
}

<#
The Windows credential store, in case the token moves out of the filesystem
altogether - which is where a Windows application would put it next.

Compiled on demand rather than at load, because this only runs during a sweep and
Add-Type costs more than the rest of a poll put together. Any failure here is a
source that did not answer, not an error: the sweep carries on to the next one.
#>
function Get-LuneTokenFromCredentialStore {
    try {
        if (-not ('Lune.Cred' -as [type])) {
            # Types are written out in full rather than pulled in with
            # -UsingNamespace: Add-Type compiles with warnings as errors, and an
            # already-imported namespace is one of the warnings.
            Add-Type -Namespace 'Lune' -Name 'Cred' -ErrorAction Stop -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("advapi32.dll",
    CharSet = System.Runtime.InteropServices.CharSet.Unicode, SetLastError = true)]
private static extern bool CredEnumerateW(string filter, int flag, out int count, out System.IntPtr creds);

[System.Runtime.InteropServices.DllImport("advapi32.dll")]
private static extern void CredFree(System.IntPtr buffer);

[System.Runtime.InteropServices.StructLayout(
    System.Runtime.InteropServices.LayoutKind.Sequential)]
private struct CREDENTIAL {
    public int Flags; public int Type; public System.IntPtr TargetName; public System.IntPtr Comment;
    public long LastWritten; public int CredentialBlobSize; public System.IntPtr CredentialBlob;
    public int Persist; public int AttributeCount; public System.IntPtr Attributes;
    public System.IntPtr TargetAlias; public System.IntPtr UserName;
}

public static string[] Blobs(string match) {
    var found = new System.Collections.Generic.List<string>();
    int count; System.IntPtr handle;
    if (!CredEnumerateW(null, 0, out count, out handle)) { return found.ToArray(); }
    try {
        for (int i = 0; i < count; i++) {
            var entry = (CREDENTIAL)System.Runtime.InteropServices.Marshal.PtrToStructure(
                System.Runtime.InteropServices.Marshal.ReadIntPtr(handle, i * System.IntPtr.Size),
                typeof(CREDENTIAL));
            var target = System.Runtime.InteropServices.Marshal.PtrToStringUni(entry.TargetName);
            if (target == null) { continue; }
            if (target.IndexOf(match, System.StringComparison.OrdinalIgnoreCase) < 0) { continue; }
            if (entry.CredentialBlobSize <= 0) { continue; }
            var bytes = new byte[entry.CredentialBlobSize];
            System.Runtime.InteropServices.Marshal.Copy(
                entry.CredentialBlob, bytes, 0, entry.CredentialBlobSize);
            found.Add(System.Convert.ToBase64String(bytes));
        }
    } finally { CredFree(handle); }
    return found.ToArray();
}
'@
        }
    } catch {
        Write-Verbose "Credential store unavailable: $($_.Exception.Message)"
        return $null
    }

    try {
        foreach ($blob in [Lune.Cred]::Blobs('claude')) {
            $bytes = [Convert]::FromBase64String($blob)
            # The blob may be a bare token or a JSON document, stored as UTF-8 or
            # UTF-16. Matching the token itself covers all four without guessing.
            foreach ($encoding in ([Text.Encoding]::UTF8), ([Text.Encoding]::Unicode)) {
                $match = [regex]::Match($encoding.GetString($bytes), 'sk-ant-[A-Za-z0-9_\-]{20,}')
                if ($match.Success) { return $match.Value }
            }
        }
    } catch {
        Write-Verbose "Credential store read failed: $($_.Exception.Message)"
    }
    return $null
}

<#
Last resort: read every JSON file in Claude Code's directories and take the first
that holds a token.

Newest first, because a token that has just moved is in a file that has just been
written. Depth and file count are capped so this stays a sweep of a few
directories rather than a walk of the profile - it runs at most once every ten
minutes, and only when nothing else answered.
#>
function Find-LuneTokenFile {
    $examined = 0
    foreach ($root in (Get-LuneTokenRoots)) {
        $candidates = @()
        try {
            $candidates = @(Get-ChildItem -LiteralPath $root -Filter '*.json' -File -Recurse `
                                -Depth 2 -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Length -gt 0 -and $_.Length -lt 262144 } |
                Sort-Object LastWriteTimeUtc -Descending)
        } catch { }

        foreach ($file in $candidates) {
            if ($examined -ge 400) {
                Write-Verbose 'Token sweep hit its file cap; stopping.'
                return $null
            }
            $examined++
            if (Read-LuneTokenDocument (Read-LuneJson $file.FullName -Attempts 1 -Quiet)) {
                Write-Verbose "Token sweep found $($file.FullName) after $examined files."
                return $file.FullName
            }
        }
    }
    Write-Verbose "Token sweep found nothing in $examined files."
    return $null
}

<#
Resolves a token from the cheapest source that has one.

Returns the token, where it came from, and whether any credentials file was seen
at all - the caller needs that last part to tell "Claude Code is signed out" from
"Claude Code is not installed", which are different problems with different
answers.
#>
function Resolve-LuneToken {
    # SkipEnvironment asks for the stored session specifically, for the case where
    # an environment variable answered first and the endpoint refused it.
    param($Cache, [switch]$SkipEnvironment)

    <#
    An explicitly supplied token wins outright: it is the only source that cannot
    be moved out from under this panel.

    Note that a token from `claude setup-token` does NOT work here, measured: the
    usage endpoint returns 403 to it, where a token from a real sign-in succeeds.
    The setup-token scopes cover inference, not the session this reads. Honoured
    anyway, because a future token that does carry the scope should be usable
    without a code change.
    #>
    <#
    Every token that could work, best-first, rather than the first one found.

    An environment variable set by hand outranks the stored session, which is
    right when it is the only credential and wrong when it is a `setup-token`:
    that authenticates and is then refused by this endpoint, so preferring it
    blindly hid a perfectly good signed-in session behind a 403. Measured on a
    machine where the CLI worked and the panel did not.

    The caller tries them in order and stops at the first that is not refused.
    #>
    foreach ($name in @(if ($SkipEnvironment) { @() } else { 'CLAUDE_CODE_OAUTH_TOKEN', 'ANTHROPIC_AUTH_TOKEN' })) {
        <#
        The user's own setting outranks what this process inherited.

        Rainmeter starts once and keeps its environment for days. Clearing the
        variable therefore does not reach it: the process still holds the value it
        inherited, and preferring that shadowed a session the user had just signed
        into - the file on disk was current and the panel was quoting a variable
        that no longer existed. Measured directly after a successful login.

        A process-scope value is only trusted when the user has not set one and
        there is no stored session, which is the case it exists for: launching
        Rainmeter from a script that sets it deliberately.
        #>
        $value = $null
        try { $value = [Environment]::GetEnvironmentVariable($name, 'User') } catch { }
        if (-not (Get-LuneCleanToken $value)) {
            $inherited = [Environment]::GetEnvironmentVariable($name)
            if ((Get-LuneCleanToken $inherited) -and -not (Get-LuneTokenFiles)) {
                $value = $inherited
            } else {
                $value = $null
            }
        }
        $clean = Get-LuneCleanToken $value
        if ($clean) {
            return @{ Token = $clean; Expiry = $null; Source = "env:$name"; SawStore = $true }
        }
    }

    $paths = @()
    $remembered = if ($Cache) { Get-LuneProperty $Cache 'tokenPath' } else { $null }
    if ($remembered) { $paths += $remembered }
    $paths += Get-LuneTokenFiles

    $sawStore = $false
    foreach ($path in ($paths | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $sawStore = $true
        $found = Read-LuneTokenDocument (Read-LuneJson $path)
        if ($found) {
            return @{ Token = $found.Token; Expiry = $found.Expiry; Source = $path; SawStore = $true }
        }
    }

    return @{ Token = $null; Expiry = $null; Source = $null; SawStore = $sawStore }
}

# ============================================================= -- luneswan -- ==
# SECTION 5b  The usage endpoint
# ==============================================================================

<#
Reads the usage endpoint with the OAuth token Claude Code maintains. Read only,
never written back, so this cannot invalidate the session it borrows.

Primary source. The desktop app's local history is fallback only: it reported the
session at 42% while the API said 63%, and it carries no per-model limits.

Response shape:
    { kind: "session" | "weekly_all" | "weekly_scoped",
      percent: 63, severity: "normal|warning|critical",
      resets_at: "2026-07-28T18:00:00+03:00",
      scope: { model: { display_name: "<model>" } } }
#>
function Get-LuneUsageReport {

    <#
    Self-tuning poll interval: a fixed one is either too slow (the figure visibly
    lags) or too fast (429, and then the panel sits frozen on an old number). The
    engine asks every FloorSec, walks its wait back towards that floor on every
    success, and only doubles it when the server itself refuses, so a throttle
    costs one skipped call rather than a dead panel.

    The ceiling is 60s, not 300s. Doubling into a five-minute ceiling meant a
    couple of refusals left the panel showing a stale reading behind a red dot for
    minutes at a stretch - observed at 300s with 205s still to run, which is
    indistinguishable from the widget being broken. A minute is long enough to stop
    piling onto a rate limit and short enough that nobody watches it.
    #>
    $cachePath  = Join-Path $LuneStateDir 'api-cache.json'
    $floorSec   = 10
    $ceilingSec = 60

    $cached = $null; $cachedAt = $null; $blockedUntil = $null
    $interval = $floorSec
    if (Test-Path -LiteralPath $cachePath) {
        $cached = Read-LuneJson $cachePath
        $at = Get-LuneProperty $cached 'fetchedAt'
        if ($at) { $cachedAt = ConvertFrom-LuneEpoch ([double]$at) }
        $blocked = Get-LuneProperty $cached 'blockedUntil'
        if ($blocked) { $blockedUntil = ConvertFrom-LuneEpoch ([double]$blocked) }
        $stored = Get-LuneProperty $cached 'interval'
        if ($stored) { $interval = [int]$stored }
    }
    if ($interval -lt $floorSec)   { $interval = $floorSec }
    if ($interval -gt $ceilingSec) { $interval = $ceilingSec }

    # Published for the caller. The freshness thresholds are meant to widen under
    # backoff, but they were reading a local of this function from the main body,
    # where it evaluated to nothing - so they never widened at all.
    $script:LuneInterval = $interval

    $payload = if ($cached) { Get-LuneProperty $cached 'payload' } else { $null }

    # Reports the payload along with when it was really fetched, so the caller can
    # date the figures honestly instead of stamping them with "now".
    function Complete-LuneFetch {
        param($Payload, $At, [bool]$Stale)
        $script:LuneFetchedAt = $At
        $script:LuneStale     = $Stale
        return $Payload
    }

    <#
    Merges a few fields into the cache without touching the rest of it.

    Where the token was found has to outlive the poll that found it, or the sweep
    runs again every time the token goes briefly unreadable. It is bookkeeping,
    not data: a write that fails costs one repeated sweep.
    #>
    function Update-LuneCacheFields {
        param([hashtable]$Fields)
        try {
            $record = Read-LuneJson $cachePath
            if (-not $record) { $record = [PSCustomObject]@{} }
            foreach ($key in $Fields.Keys) {
                $record | Add-Member -NotePropertyName $key -NotePropertyValue $Fields[$key] -Force
            }
            Write-LuneJsonFile -Path $cachePath -Json ($record | ConvertTo-Json -Depth 12) | Out-Null
        } catch {
            Write-Verbose "Could not update the cache: $($_.Exception.Message)"
        }
    }

    function Save-LuneCache {
        param($Payload, $At, [int]$Interval, $BlockedUntil)
        $record = [ordered]@{
            fetchedAt = ConvertTo-LuneEpoch $At
            interval  = $Interval
            payload   = $Payload
        }
        if ($BlockedUntil) { $record['blockedUntil'] = ConvertTo-LuneEpoch $BlockedUntil }
        # Carried across a rewrite, so a good fetch does not cost the panel the
        # location it worked hard to find.
        $keepPath = if ($script:LuneTokenPath) { $script:LuneTokenPath }
                    else { Get-LuneProperty $cached 'tokenPath' }
        if ($keepPath) { $record['tokenPath'] = $keepPath }
        <#
        A cache that cannot be written is a lost optimisation, not a failure.

        With $ErrorActionPreference at Stop, a denied write threw out of the whole
        script: the poll was abandoned and the panel got no update at all, over a
        file that only exists to make the next start faster. Verified by denying
        write access to the state directory - the script exited 1.

        Anti-virus locks, roaming-profile problems and tightened ACLs all produce
        this, and none of them are reasons to stop reporting usage.
        #>
        try {
            Write-LuneJsonFile -Path $cachePath -Json (
                ([PSCustomObject]$record) | ConvertTo-Json -Depth 12) | Out-Null
        } catch {
            Write-Verbose "Could not write the cache ($($_.Exception.Message)); continuing without it."
        }
    }

    <#
    Credentials are checked here, after the cache is in hand, not before it.

    Closing Claude or rebooting leaves the token missing or expired, and the checks
    used to return empty at that point - discarding a perfectly good reading and
    blanking the panel until Claude was opened again. The last known figures are
    shown instead, dated by when they were actually fetched, and replaced the
    moment a real call succeeds.
    #>
    # Carried over from the poll that established it, so a throttled cycle still
    # names the reason. Cleared the moment a call succeeds.
    $remembered = if ($cached) { Get-LuneProperty $cached 'authState' } else { $null }
    if ($remembered) { $script:LuneAuthState = $remembered }

    <#
    A sign-in that just happened must not wait out a backoff it did not earn.

    Signing in is what someone does BECAUSE the panel is stuck, and the panel is
    stuck precisely when it has been refused enough to be waiting a minute between
    attempts, with a recorded auth state saying it is signed out. So the moment the
    credential files change, the wait and the verdict are both discarded and this
    poll goes to the network. Otherwise /login appears to do nothing for up to a
    minute, which is exactly long enough to conclude it did not work.
    #>
    $credStamp = ''
    foreach ($file in (Get-LuneTokenFiles)) {
        try { $credStamp += (Get-Item -LiteralPath $file).LastWriteTimeUtc.Ticks.ToString() + ';' } catch { }
    }
    $lastStamp = if ($cached) { Get-LuneProperty $cached 'credStamp' } else { $null }
    if ($credStamp -ne $lastStamp) {
        if ($lastStamp) {
            Write-Verbose 'Credentials changed since the last poll; ignoring the current backoff.'
            $Force = $true
            $script:LuneAuthState = 'ok'
            Update-LuneCacheFields -Fields @{ credStamp = $credStamp; authState = '' }
        } else {
            Update-LuneCacheFields -Fields @{ credStamp = $credStamp }
        }
    }

    $resolved = Resolve-LuneToken -Cache $cached
    $token    = $resolved.Token
    if ($token) { Write-Verbose "Token from $($resolved.Source)." }

    if ($token -and $resolved.Expiry) {
        if ((ConvertFrom-LuneEpoch ([double]$resolved.Expiry)) -lt [DateTime]::UtcNow) {
            Write-Verbose 'OAuth token expired.'
            $token = $null
        }
    }

    <#
    Nothing in the usual places. Sweep for the file before giving up, because the
    usual places are exactly what changes.

    Throttled to once every ten minutes and skipped entirely while a token is
    working, so the common path never pays for it. A hit is remembered as
    tokenPath and read directly from then on.
    #>
    if (-not $token) {
        $lastSweep = if ($cached) { Get-LuneProperty $cached 'tokenSweepAt' } else { $null }
        $sweepDue  = (-not $lastSweep) -or
                     ((ConvertFrom-LuneEpoch ([double]$lastSweep)) -lt [DateTime]::UtcNow.AddMinutes(-10))

        if ($sweepDue) {
            $fields = @{ tokenSweepAt = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() }

            $swept = Find-LuneTokenFile
            if ($swept) {
                $found = Read-LuneTokenDocument (Read-LuneJson $swept)
                if ($found) {
                    $token = $found.Token
                    $resolved.Expiry = $found.Expiry
                    $resolved.SawStore = $true
                    $script:LuneTokenPath = $swept
                    $fields['tokenPath'] = $swept
                    Write-Verbose "Token relocated to $swept."
                }
            }

            if (-not $token) {
                $stored = Get-LuneTokenFromCredentialStore
                if ($stored) {
                    $token = $stored
                    $resolved.SawStore = $true
                    Write-Verbose 'Token found in the Windows credential store.'
                }
            }

            Update-LuneCacheFields -Fields $fields
        }
    }

    if (-not $token) {
        <#
        Ask Claude Code to renew its own credentials, rather than renewing them
        here.

        Refreshing the OAuth token means posting the refresh token and writing the
        result back into .credentials.json; getting that wrong costs the user their
        sign-in. The official client already does it correctly on startup, so a
        cheap invocation is enough to get a fresh token on disk, and this script
        keeps its promise of only ever reading that file.

        Throttled through the cache so a dead token cannot spawn a process on every
        poll - one attempt every five minutes, and every half hour once an attempt
        has failed. A signed-out CLI cannot be renewed by asking it again, and at
        five-minute spacing that was a process launched forever for nothing.
        #>
        $lastAttempt = Get-LuneProperty $cached 'lastRenew'
        $spacing     = if (Get-LuneProperty $cached 'renewFailed') { 30 } else { 5 }
        $due = (-not $lastAttempt) -or
               ((ConvertFrom-LuneEpoch ([double]$lastAttempt)) -lt [DateTime]::UtcNow.AddMinutes(-$spacing))

        if ($due -and (Get-Command claude -ErrorAction SilentlyContinue)) {
            <#
            A minimal authenticated call. "claude --version" does not touch the
            credentials, but any command that actually signs in does: this one moved
            expiry forward by eight hours in testing. The prompt is a single
            character on the cheapest model, and only runs once the token is already
            unusable, so the cost is negligible against a panel that would otherwise
            stay frozen until Claude was reopened.
            #>
            Write-Verbose 'Token unusable; asking Claude Code to renew it.'
            try {
                $renew = Start-Process -FilePath 'cmd.exe' -PassThru -WindowStyle Hidden `
                    -ArgumentList '/c claude -p "." --model claude-haiku-4-5-20251001 >nul 2>&1'
                if (-not $renew.WaitForExit(25000)) { try { $renew.Kill() } catch { } }
            } catch { }

            # Only records when renewal was last attempted, to space out retries.
            # Losing it costs an extra attempt, not the poll.
            Update-LuneCacheFields -Fields @{
                lastRenew = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
            }

            # Give it a moment, then look again - anywhere, not just where the token
            # used to live, since a renewal is as free to relocate it as anything
            # else. If it worked, this poll is live.
            Start-Sleep -Milliseconds 2500
            $again = Resolve-LuneToken -Cache $cached
            if ($again.Token -and
                (-not $again.Expiry -or (ConvertFrom-LuneEpoch ([double]$again.Expiry)) -gt [DateTime]::UtcNow)) {
                Write-Verbose "Renewed; token from $($again.Source)."
                $token = $again.Token
            }
            Update-LuneCacheFields -Fields @{ renewFailed = [bool](-not $token) }
        }
    }

    if (-not $token) {
        <#
        Told apart deliberately. A signed-out CLI and a missing one need different
        instructions, and the panel used to give the same useless one for both:
        "run any claude command", which does nothing at all when the answer is
        "Not logged in".
        #>
        $script:LuneAuthState = if ($resolved.SawStore) { 'signedout' } else { 'missing' }
        Write-Verbose "No usable token ($script:LuneAuthState); serving the last stored reading."
        return (Complete-LuneFetch -Payload $payload -At $cachedAt -Stale $true)
    }

    # Both short circuits are skipped for a user-initiated refresh. Someone
    # pressing the button has already decided the number on screen is not enough.
    if (-not $Force -and $blockedUntil -and [DateTime]::UtcNow -lt $blockedUntil -and $payload) {
        Write-Verbose ("Throttled; next attempt in {0}s." -f [int]($blockedUntil - [DateTime]::UtcNow).TotalSeconds)
        return (Complete-LuneFetch -Payload $payload -At $cachedAt -Stale $true)
    }

    if (-not $Force -and $cachedAt -and $payload) {
        $age = ([DateTime]::UtcNow - $cachedAt).TotalSeconds
        if ($age -lt $interval) {
            Write-Verbose ("Reusing API response from {0}s ago (interval {1}s)." -f [int]$age, $interval)
            return (Complete-LuneFetch -Payload $payload -At $cachedAt -Stale $false)
        }
    }
    if ($Force) {
        # Back to the floor, so a forced call does not inherit a long wait it just
        # bypassed and immediately re-enter backoff on the next scheduled tick.
        $interval = $floorSec
        $script:LuneInterval = $interval
        Write-Verbose 'Forced refresh: throttle window and cache reuse bypassed.'
    }

    <#
    Only one poll at a time, machine-wide.

    Nothing stops a second copy of the panel from running - two on one desktop is a
    reasonable thing to want - but each was polling on its own schedule against the
    same token, so the account saw double the request rate and both copies got
    refused. Measured: two instances sitting at 94s and 300s of backoff at the same
    moment, one of them with over three minutes still to wait.

    A copy that cannot take the lock is not made to wait for it. It serves the
    cache, which the holder is about to refresh anyway, and tries again on its next
    tick. Requests stay at one poller's worth however many panels are open.
    #>
    $fetchLock = New-Object System.Threading.Mutex($false, 'Local\ClaudeLuneUsageFetch')
    $holdsLock = $false
    # A scheduled tick never waits - it has another one along shortly. A forced
    # refresh waits briefly, because returning the cache to someone who just
    # pressed the button is indistinguishable from the button not working.
    $lockWait = if ($Force) { 4000 } else { 0 }
    try { $holdsLock = $fetchLock.WaitOne($lockWait) } catch { $holdsLock = $false }
    if (-not $holdsLock) {
        Write-Verbose 'Another panel is fetching; using the shared cache.'
        if ($payload) { return (Complete-LuneFetch -Payload $payload -At $cachedAt -Stale $false) }
        return (Complete-LuneFetch -Payload $null -At $null -Stale $true)
    }

    <#
    A refused credential is not the end of the attempt: try the next one.

    An environment variable outranks the stored session, which is right until the
    variable holds a `claude setup-token` token. That authenticates and is then
    refused here, because its scopes cover inference rather than this endpoint - so
    the panel sat on 403 while a working signed-in session was on the same disk.
    Only 401 and 403 fall through; a 429 or a timeout says nothing about the
    credential and must not burn the next one.
    #>
    $attempts = @(@{ Token = $token; Source = $resolved.Source })
    if ($resolved.Source -like 'env:*') {
        $stored = Resolve-LuneToken -Cache $cached -SkipEnvironment
        if ($stored.Token -and $stored.Token -ne $token) {
            $attempts += @{ Token = $stored.Token; Source = $stored.Source }
        }
    }

    try {
        $response = $null
        $refusal  = $null
        foreach ($attempt in $attempts) {
            try {
                $response = Invoke-RestMethod -Uri 'https://api.anthropic.com/api/oauth/usage' `
                    -Headers @{ Authorization = "Bearer $($attempt.Token)"; 'anthropic-beta' = 'oauth-2025-04-20' } `
                    -TimeoutSec 15
                $token   = $attempt.Token
                $refusal = $null
                if ($attempt.Source -ne $resolved.Source) {
                    Write-Verbose "$($resolved.Source) was refused; $($attempt.Source) worked."
                    $resolved.Source = $attempt.Source
                }
                break
            } catch {
                $refusal = $_
                if ($_.Exception.Message -notmatch '\b40[13]\b') { throw }
                Write-Verbose "$($attempt.Source) refused: $($_.Exception.Message)"
            }
        }
        if ($refusal) { throw $refusal }

        # Success: walk the interval back down towards the floor rather than
        # snapping to it, so a rate limit that is genuinely near 10s settles instead
        # of oscillating between throttled and not.
        $next = [Math]::Max($floorSec, [int]($interval * 0.6))
        $now  = [DateTime]::UtcNow
        Save-LuneCache -Payload $response -At $now -Interval $next -BlockedUntil $null
        # A call that worked settles every auth question this panel can have.
        $script:LuneAuthState = 'ok'
        $script:LuneInterval  = $next
        Write-Verbose ("Fetched live; next interval {0}s." -f $next)

        return (Complete-LuneFetch -Payload $response -At $now -Stale $false)
    } catch {
        $message = $_.Exception.Message
        Write-Verbose "Usage API failed: $message"

        <#
        401 and 403 are different answers and need different advice.

        401 is "this is not a token". 403 is "this is a token, and it is not
        allowed here" - which is what a `claude setup-token` token gets, because
        its scopes cover inference rather than the session this endpoint reads.
        Reported as a generic outage, that leaves someone staring at a stale panel
        having done everything the instructions asked. Measured against both: a
        made-up token returns 401, a setup-token returns 403.
        #>
        <#
        Recorded, not just set, because a refusal is followed by backoff: the next
        several polls return the cache before reaching this call at all, and a
        reason that only exists on the poll that earned it makes the panel alternate
        between naming the problem and shrugging at it.
        #>
        if ($message -match '\b40[13]\b') {
            $script:LuneAuthState = $(if ($message -match '\b403\b') { 'forbidden' } else { 'signedout' })
            Update-LuneCacheFields -Fields @{ authState = $script:LuneAuthState }
        }

        <#
        A refusal doubles the wait and is recorded, so the next few polls skip the
        call instead of piling on. The previous response is still shown - it beats
        the desktop cache, which has no per-model limits at all - but it is flagged
        stale and dated by when it was actually fetched. Passing a replayed response
        off as live was the original defect: the panel sat on a twenty-minute-old
        number with "live" written beside it.
        #>
        if ($message -match '429') {
            $next = [Math]::Min($ceilingSec, [Math]::Max($floorSec * 2, $interval * 2))

            # If the server says how long to wait, that beats guessing. Blind
            # doubling overshoots a limit that has already almost expired and
            # undershoots one that has not.
            $retryAfter = $null
            try {
                $headers = $_.Exception.Response.Headers
                if ($headers) {
                    $value = $headers['Retry-After']
                    if ($value) { $retryAfter = [int]$value }
                }
            } catch { }
            if ($retryAfter -and $retryAfter -gt 0) {
                $next = [Math]::Min($ceilingSec, [Math]::Max($floorSec, $retryAfter))
                Write-Verbose ("Server asked for {0}s." -f $retryAfter)
            }
            if ($payload -and $cachedAt) {
                Save-LuneCache -Payload $payload -At $cachedAt -Interval $next `
                               -BlockedUntil ([DateTime]::UtcNow.AddSeconds($next))
            }
            $script:LuneInterval = $next
            Write-Verbose ("Throttled; interval raised to {0}s." -f $next)
        }

        if ($payload) { return (Complete-LuneFetch -Payload $payload -At $cachedAt -Stale $true) }
        return (Complete-LuneFetch -Payload $null -At $null -Stale $true)
    }
    finally {
        # Released whichever way the fetch ended. A lock abandoned on a timeout or a
        # thrown request would lock every panel out of polling until logout.
        try { $fetchLock.ReleaseMutex() } catch { }
        try { $fetchLock.Dispose() } catch { }
    }
}

# Turns one limits[] entry into the shape the layouts already consume.
function ConvertTo-LuneLimitRow {
    param($Limit)

    if (-not $Limit) {
        return [PSCustomObject]@{ percent = 0; countdown = 'not tracked'; date = ''; available = 0; label = '' }
    }

    $percent = [double](Get-LuneProperty $Limit 'percent')
    if ($percent -lt 0)   { $percent = 0 }
    if ($percent -gt 100) { $percent = 100 }
    $percent = [Math]::Round($percent, 1)
    if ($percent -eq [Math]::Floor($percent)) { $percent = [int]$percent }

    $countdown = '--'
    $date      = ''
    $resetUtc  = ConvertTo-LuneUtc -Value (Get-LuneProperty $Limit 'resets_at')
    if ($resetUtc) {
        # Reported by the API, so no "est." - these are exact.
        $countdown = Format-LuneCountdown -Span ($resetUtc - [DateTime]::UtcNow)
        $date      = Format-LuneStamp -Local $resetUtc.ToLocalTime()
    }

    $label = ''
    $scope = Get-LuneProperty $Limit 'scope'
    if ($scope) {
        $model = Get-LuneProperty $scope 'model'
        if ($model) { $label = [string](Get-LuneProperty $model 'display_name') }
    }

    return [PSCustomObject]@{
        percent   = $percent
        countdown = $countdown
        date      = $date
        available = 1
        label     = $label
    }
}

# ==============================================================================
# SECTION 6  Desktop history - the standby source, and the trend
# ==============================================================================

<#
Where the desktop app keeps its usage history, if it keeps one at all.

$LuneHistoryPath is the documented location and stays the first candidate, but it
is not the only one: this machine has %APPDATA%\Claude Code and
%LOCALAPPDATA%\Claude and no %APPDATA%\Claude whatsoever. Same reasoning as the
token search - the address is Anthropic's to change, so it is looked for rather
than assumed.

Returns the documented path when none exists, so the caller still names a
sensible location.
#>
function Get-LuneHistoryPath {
    $candidates = @(
        $LuneHistoryPath
        (Join-Path $env:APPDATA      'Claude Code\plan-usage-history.json')
        (Join-Path $env:LOCALAPPDATA 'Claude\plan-usage-history.json')
        (Join-Path $env:LOCALAPPDATA 'Claude-Data\plan-usage-history.json')
        (Join-Path $env:USERPROFILE  '.claude\plan-usage-history.json')
    )
    foreach ($path in $candidates) {
        if ($path -and (Test-Path -LiteralPath $path)) { return $path }
    }
    return $LuneHistoryPath
}

function Get-LuneHistorySamples {
    param([string]$Org)
    $document = Read-LuneJson (Get-LuneHistoryPath)
    $samples  = Get-LuneProperty $document 'samples'
    if (-not $samples) { return @() }

    if ($Org) {
        $mine = @($samples | Where-Object { $_.org -eq $Org })
        if ($mine.Count -gt 0) { $samples = $mine }
    }
    return @($samples | Sort-Object t)
}

<#
Utilisation only climbs inside a window, so a fall between consecutive samples
marks a reset. The most recent fall dates the current window; the next reset is one
window length later. Returns $null when no rollover is on record, in which case the
panel says so rather than inventing a time.
#>
function Get-LuneEstimatedReset {
    param($Samples, [string]$Field, [double]$WindowHours)

    $startMs = $null
    for ($i = $Samples.Count - 1; $i -gt 0; $i--) {
        $now      = [double](Get-LuneProperty $Samples[$i].u   $Field)
        $previous = [double](Get-LuneProperty $Samples[$i-1].u $Field)
        if ($now -lt ($previous - 0.5)) { $startMs = [double]$Samples[$i].t; break }
    }
    if ($null -eq $startMs) { return $null }

    $reset = (ConvertFrom-LuneEpoch $startMs).AddHours($WindowHours)
    while ($reset -lt [DateTime]::UtcNow) { $reset = $reset.AddHours($WindowHours) }
    return $reset
}

function New-LuneLimitRow {
    param($Samples, [string]$Field, [double]$WindowHours)

    if (-not $Samples -or $Samples.Count -eq 0) {
        return [PSCustomObject]@{ percent = 0; countdown = 'no data'; date = ''; available = 0 }
    }

    $raw = [double](Get-LuneProperty $Samples[-1].u $Field)
    if ($raw -lt 0)   { $raw = 0 }
    if ($raw -gt 100) { $raw = 100 }
    $percent = [Math]::Round($raw, 1)
    if ($percent -eq [Math]::Floor($percent)) { $percent = [int]$percent }

    $countdown = 'est. --'
    $date      = ''
    $reset = Get-LuneEstimatedReset -Samples $Samples -Field $Field -WindowHours $WindowHours
    if ($reset) {
        # "est." because this is inferred from an observed rollover, not reported.
        $countdown = 'est. ' + (Format-LuneCountdown -Span ($reset - [DateTime]::UtcNow))
        $date      = Format-LuneStamp -Local $reset.ToLocalTime()
    }
    return [PSCustomObject]@{ percent = $percent; countdown = $countdown; date = $date; available = 1 }
}

<#
A bucket that does not exist on this plan must stay empty in BOTH modes.

Flipping it blindly turned "0% used" into "100% left" and drew a full bar for a
limit that was never there - the same falsehood as the old full-red bar, wearing
the opposite label.
#>
function Get-LuneDisplayValue {
    param($Row, [bool]$Remaining)
    if ($Row.available -lt 1) { return @{ shown = 0; bar = 0 } }
    if ($Remaining) { return @{ shown = [int](100 - $Row.percent); bar = 100 - $Row.percent } }
    return @{ shown = $Row.percent; bar = $Row.percent }
}

function Get-LuneRgba {
    param([hashtable]$Presets, [string]$Theme, [string]$Key, [string]$Fallback)
    $value = $Presets[$Theme + $Key]
    if (-not $value) { $value = $Fallback }
    $channels = @($value -split ',' | ForEach-Object { [double]($_.Trim()) })
    while ($channels.Count -lt 4) { $channels += 255 }
    return $channels
}

<#
Bar colour is mixed here rather than switched in the skin.

The skin used three fixed steps, so a bar stayed flat blue up to 74% and then
jumped to amber; the colour never tracked the fill. Blending across the active
theme's own Normal / Warn / Crit entries keeps that behaviour tied to whatever
palette is loaded, so every theme gets a bar that shifts as it fills without
defining anything extra.
#>
function Get-LuneBarColor {
    param($Row, $Normal, $Warn, $Crit, [double]$WarnAt, [double]$CritAt)

    if ($Row.available -lt 1) { return '' }   # the skin keeps its own "off" colour
    $used = [double]$Row.percent
    if ($used -le 0) { $used = 0 }

    if     ($used -ge $CritAt) { $from = $Crit;   $to = $Crit; $t = 0 }
    elseif ($used -ge $WarnAt) { $from = $Warn;   $to = $Crit; $t = ($used - $WarnAt) / ($CritAt - $WarnAt) }
    else                       { $from = $Normal; $to = $Warn; $t = $used / $WarnAt }

    $mixed = 0..3 | ForEach-Object { [int][Math]::Round($from[$_] + (($to[$_] - $from[$_]) * $t)) }
    return ($mixed -join ',')
}

<#
Our own record of the weekly figure, so the chart plots the same number the bar
draws.

The desktop app's history is a different measurement, and a Rainmeter-launched
process cannot read %APPDATA%\Claude on this machine: the skin's poll saw zero
samples where the same command by hand read 1,929.

One sample per five minutes, pruned to eight days.
#>
function Add-LuneWeeklySample {
    param([double]$Percent, [string]$Path)

    $now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $samples = @()

    <#
    One writer at a time, and the whole read-modify-write inside the lock.

    Writing atomically stopped the file being torn in half, but it did not make
    two pollers safe. Move-Item replaces the destination, and for an instant the
    path does not exist: a reader landing there gets Test-Path false, concludes
    the store is new rather than unreadable, and writes a single sample over the
    lot. That is the same collapse the empty-read guard was built for, arriving
    through the one door it does not watch.

    Caught by CI, which runs on a slower machine than this one - the window is too
    narrow to hit reliably here, and the suite had passed locally every time.

    Local\ rather than Global\: every poller runs in the same session, and the
    global namespace needs a privilege a normal user does not have.
    #>
    $lock = New-Object System.Threading.Mutex($false, 'Local\ClaudeLuneWeeklyStore')
    $held = $false
    try {
        try { $held = $lock.WaitOne(4000) }
        catch [System.Threading.AbandonedMutexException] {
            # The previous holder died mid-write. We own it now, and the file is
            # whatever it left behind, which the read below judges on its merits.
            $held = $true
        }
        if (-not $held) {
            Write-Verbose 'Weekly history is busy; recording nothing this cycle.'
            return @()
        }
        return Update-LuneWeeklyStore -Percent $Percent -Path $Path -Now $now
    } finally {
        if ($held) { $lock.ReleaseMutex() }
        $lock.Dispose()
    }
}

# The body of Add-LuneWeeklySample, called with the store lock held.
function Update-LuneWeeklyStore {
    param([double]$Percent, [string]$Path, [double]$Now)

    $now = $Now
    $samples = @()
    $existing = Read-LuneJson $Path

    <#
    A read that failed must never cause a write. This is the whole ballgame.

    Two pollers overlap - the scheduled tick and the one OnRefreshAction starts -
    and one can catch the file while the other is rewriting it. The read then
    returns nothing, and the old code treated that as "no history yet", appended a
    single sample and saved it. One unlucky moment destroyed a week of readings,
    which is exactly what happened: a store holding 932 samples across 142 hours
    was replaced by one sample, twice, and the ladder collapsed back to flat.

    If the file exists but will not parse, this cycle records nothing and leaves
    what is on disk alone. The next poll picks it up.
    #>
    if ($null -eq $existing -and (Test-Path -LiteralPath $Path)) {
        Write-Verbose 'Weekly history could not be read this cycle; leaving it untouched.'
        return @()
    }

    if ($existing -and $existing.samples) {
        <#
        Sorted on the way in, and that is not a nicety.

        Everything below takes the newest sample positionally, and the caller
        measures the history's span from the first and last entries. Given an
        unordered file both read the wrong end: the span came out as twelve hours
        across a store holding a hundred and forty-two, so the chart drew two
        blocks of a week's worth of data and called it flat.
        #>
        $samples = @($existing.samples | Where-Object { $null -ne $_.t } | Sort-Object { [double]$_.t })
    }

    # One sample per five minutes. Polling every ten seconds would otherwise fill
    # the file with a thousand identical readings a day.
    $last = $samples | Select-Object -Last 1
    if ($last -and ($now - [double]$last.t) -lt 300000) {
        if ([double]$last.w -eq $Percent) { return $samples }
        $samples = @($samples | Select-Object -SkipLast 1)
    }

    $samples += [PSCustomObject]@{ t = $now; w = $Percent }
    $cutoff = $now - (8 * 86400000)
    $samples = @($samples | Where-Object { [double]$_.t -ge $cutoff } | Sort-Object { [double]$_.t })
    Write-Verbose ("Weekly history: {0} samples spanning {1:0.0}h." -f $samples.Count,
        $(if ($samples.Count -gt 1) { ([double]$samples[-1].t - [double]$samples[0].t) / 3600000 } else { 0 }))

    try {
        Write-LuneJsonFile -Path $Path -Json (
            [PSCustomObject]@{ samples = $samples } | ConvertTo-Json -Depth 4 -Compress) | Out-Null
    } catch {
        Write-Verbose "Could not record the weekly sample: $($_.Exception.Message)"
    }
    return $samples
}

<#
How fast the weekly allowance is being spent, hour by hour, across today.

The chart used to plot the cumulative weekly percentage. That number only ever
climbs and then resets, so the shape it draws is a ramp - and across a quiet
stretch it is a flat line, which is what it had become. It also said nothing
useful: the bar directly above it already shows the level.

The rate is the interesting figure. Each column is how many percentage points of
the weekly allowance were consumed in that hour, so a heavy session stands up as a
tall block and an idle night is empty. A reset mid-window shows as no spend rather
than a negative one.
#>
function Get-LuneSpendRate {
    param($Samples, [int]$Hours = 24, [int]$Points = 24)

    $ordered = @($Samples | Where-Object { $_ -and $null -ne $_.t } | Sort-Object { [double]$_.t })
    $step    = ($Hours * 3600000) / $Points

    <#
    Columns are clock hours, so a hovered column can name an hour of the day.

    They used to be anchored to the newest reading itself, which put the
    boundaries at whatever minute the poll happened to land on: a column covering
    12:32 to 13:32 is not an hour anyone can name. Anchoring to the top of that
    reading's hour makes the last column the current hour and every one before it
    a whole hour on the clock.
    #>
    $newest = [DateTimeOffset]::FromUnixTimeMilliseconds([long]$ordered[-1].t).ToLocalTime()
    $anchor = [DateTimeOffset]::new($newest.Year, $newest.Month, $newest.Day, $newest.Hour, 0, 0, $newest.Offset)
    $from   = [double]$anchor.ToUnixTimeMilliseconds() - (($Points - 1) * $step)

    $labels = @(0..($Points - 1) | ForEach-Object {
        [DateTimeOffset]::FromUnixTimeMilliseconds([long]($from + ($_ * $step))).ToLocalTime().ToString('HH:00')
    })

    $empty = [PSCustomObject]@{
        points = @(0) * $Points; spend = @(0) * $Points; labels = $labels
        peak = 0; total = 0; covered = 0
    }
    if ($ordered.Count -lt 2) { return $empty }

    # First and last reading inside each bucket; the difference is what was spent.
    $first = New-Object 'double[]' $Points
    $last  = New-Object 'double[]' $Points
    $seen  = New-Object 'bool[]'   $Points

    foreach ($sample in $ordered) {
        $t = [double]$sample.t
        if ($t -lt $from) { continue }
        $index = [int][Math]::Floor(($t - $from) / $step)
        if ($index -lt 0) { $index = 0 } elseif ($index -ge $Points) { $index = $Points - 1 }
        $value = [double]$sample.w
        if (-not $seen[$index]) { $first[$index] = $value; $seen[$index] = $true }
        $last[$index] = $value
    }

    # Carry across empty buckets so an idle hour reads as no spend, not as a gap
    # that swallows the next hour's climb.
    $spend = New-Object 'double[]' $Points
    $previous = $null
    for ($i = 0; $i -lt $Points; $i++) {
        if (-not $seen[$i]) { $spend[$i] = 0; continue }
        $start = $(if ($null -ne $previous) { [Math]::Min($first[$i], $previous) } else { $first[$i] })
        $delta = $last[$i] - $start
        # A weekly reset drops the figure. That is not negative spending.
        if ($delta -lt 0) { $delta = $last[$i] }
        $spend[$i] = $delta
        $previous = $last[$i]
    }

    $peak = ($spend | Measure-Object -Maximum).Maximum
    $covered = @($seen | Where-Object { $_ }).Count

    <#
    Scaled against the busiest hour on screen, with a floor under it. Dividing by
    the peak alone turns a single half-point hour into a full-height tower and
    makes a quiet day look like a busy one; a floor of two points keeps a genuinely
    quiet day looking quiet.
    #>
    $scale = [Math]::Max($peak, 2)
    <#
    Three states, not two, and the difference is the whole readability of the
    chart on a young install.

    An hour we have no reading for and an hour you spent nothing in are not the
    same fact, and drawing both as bare troughs made thirteen hours of history
    look like a day of doing nothing. An idle hour now gets a small stub, so the
    recorded stretch has a visible leading edge and the gap before it reads as
    what it is: history we do not have yet.
    #>
    # Named $heights, not $points. PowerShell variable names are case-insensitive,
    # so a local $points IS the [int]$Points parameter, and assigning an array to
    # it throws "cannot convert Object[] to Int32" from a line that looks fine.
    $heights = @()
    for ($i = 0; $i -lt $Points; $i++) {
        if (-not $seen[$i])      { $heights += 0; continue }   # no reading for this hour
        if ($spend[$i] -le 0)    { $heights += 4; continue }   # recorded, and idle
        $height = [int](10 + ($spend[$i] / $scale) * 90)
        if ($height -gt 100) { $height = 100 }
        $heights += $height
    }

    return [PSCustomObject]@{
        points  = $heights
        # What each column is worth, for the per-hour tooltips. The heights above
        # are scaled against the busiest hour and cannot be read back as a figure.
        spend   = @(0..($Points - 1) | ForEach-Object {
            if ($seen[$_]) { [Math]::Round($spend[$_], 1) } else { $null }
        })
        labels  = $labels
        peak    = [Math]::Round($peak, 1)
        total   = [Math]::Round((($spend | Measure-Object -Sum).Sum), 1)
        covered = $covered
    }
}

function Get-LuneTokensToday {
    $document = Read-LuneJson $LuneTokensPath
    $today    = Get-LuneProperty $document 'tokens-today'
    if (-not $today) { return '' }
    $count = [double](Get-LuneProperty $today 'tokens')
    if ($count -ge 1000000) { return ('{0:0.0}M' -f ($count / 1000000)) }
    if ($count -ge 1000)    { return ('{0:0.0}k' -f ($count / 1000)) }
    return [string][int]$count
}

# ============================================================= -- luneswan -- ==
# SECTION 7  Publishing to the skin
# ==============================================================================

<#
Writes the live values to LuneLive.inc, which the skin @Includes, then refreshes.

Rainmeter's command-line bang interface proved unreliable for this: the executable
honours only one bang per invocation, and firing dozens of separate invocations
dropped values unpredictably. Rewriting an included file and refreshing is the same
mechanism that already drives theme and size switching, which works every time.

The refresh is issued ONLY when the content actually changed. That is what stops a
loop: the skin's OnRefreshAction runs this script again, the regenerated file is
identical, no second refresh is issued, and it settles.
#>

<#
Only a refresh gets a value onto the panel. Rainmeter parses @Include files once,
at load; DynamicVariables=1 re-evaluates a reference, not the value. Rewriting
LuneLive.inc on its own changes nothing on screen.

Do not gate the refresh on structural changes only. That was tried and it froze
the percentages until the plan itself changed. The content comparison below is
what stops a loop: after a refresh OnRefreshAction runs this again, the file comes
out identical, and no second refresh is issued.
#>

# A floor between reloads. The equality check already stops the loop; this caps the
# damage if some future change makes the file differ on every single run.
$script:LuneRefreshFloorSec = 5


function Publish-LuneState {
    param([hashtable]$Values)

    # The data file is always written; only the refresh is optional. Treating an
    # empty SkinConfig as "write nothing" made -SkinConfig "" silently useless for
    # testing.
    $lines = @($LuneStamp, '[Variables]')
    foreach ($key in ($Values.Keys | Sort-Object)) {
        # Rainmeter reads to end of line, so a blank value is legal; only '#' and
        # newlines would break parsing, and none of these values carry them.
        $lines += ('{0}={1}' -f $key, ([string]$Values[$key] -replace '#', ''))
    }
    $new = ($lines -join "`r`n")

    $old = ''
    if (Test-Path -LiteralPath $LuneLivePath) { $old = [System.IO.File]::ReadAllText($LuneLivePath) }

    if ($new -eq $old) {
        Write-Verbose 'Data unchanged; no refresh issued.'
        return
    }

    Write-LuneIncFile -Path $LuneLivePath -Lines $lines
    Write-Verbose 'LuneLive.inc updated.'

    if ($NoRefresh -or -not $SkinConfig) {
        Write-Verbose 'Refresh suppressed.'
        return
    }

    # Something changed, so the panel is out of date until it reloads. See the note
    # above for why there is no cleverer option than reloading.
    $marker = Join-Path $LuneStateDir 'last-refresh'
    if (Test-Path -LiteralPath $marker) {
        try {
            $since = ([DateTime]::UtcNow - (Get-Item -LiteralPath $marker).LastWriteTimeUtc).TotalSeconds
            if ($since -lt $script:LuneRefreshFloorSec) {
                Write-Verbose ("Refreshed {0:0.0}s ago; leaving this one to the next poll." -f $since)
                return
            }
        } catch { }
    }

    $exe = Join-Path $env:ProgramFiles 'Rainmeter\Rainmeter.exe'
    if (-not (Test-Path -LiteralPath $exe)) { Write-Verbose 'Rainmeter.exe not found.'; return }

    <#
    Marker first, refresh second. The refresh reloads the skin, which tears down the
    RunCommand measure that owns this process, so nothing after it runs. Written
    afterwards it was never written at all: every poll saw a stale timestamp and the
    skin reloaded about once a second.
    #>
    try { Set-Content -LiteralPath $marker -Value ([DateTime]::UtcNow.ToString('o')) -Encoding ASCII } catch { }

    # Fire and forget: a bang invocation that cannot reach the main instance has
    # been observed to hang, and a stuck child process would pile up every cycle.
    try {
        $bang = Start-Process -FilePath $exe -ArgumentList @('!Refresh', $SkinConfig) -PassThru -WindowStyle Hidden
        if (-not $bang.WaitForExit(5000)) {
            Write-Verbose 'Refresh call did not exit; killing it.'
            try { $bang.Kill() } catch { }
        }
        Write-Verbose 'Refresh issued.'
    } catch { Write-Verbose "Refresh failed: $($_.Exception.Message)" }
}

# ==============================================================================
# SECTION 8  Main
# ==============================================================================

try {
    Write-LuneResolvedLayout
    if ($ResolveOnly) { return }

    $config  = Read-LuneInc $LuneConfigPath
    $presets = Read-LuneInc $LunePresetsPath

    $account = Get-LuneAccount
    $samples = Get-LuneHistorySamples -Org $account.org

    # The API is authoritative; the desktop cache is only the standby for when the
    # token has expired. Which one is in use is reported to the panel so a fallback
    # figure is never mistaken for a live one.
    $api        = Get-LuneUsageReport
    $interval   = if ($script:LuneInterval) { [int]$script:LuneInterval } else { 10 }
    $source     = 'cache'
    $scopedName = 'Extra'

    <#
    Rows come from the API's limits[] array, so the panel is plan-agnostic:

        session       -> row 1
        weekly_all    -> row 2
        weekly_scoped -> row 3, only when the plan has a per-model cap

    The desktop cache is never substituted for these. It disagreed with the API by 20
    points and has no per-model limits.
    #>
    <#
    Whichever source actually has the newer reading wins.

    A replayed API response used to beat the desktop app's local history no matter
    how old it was, because the API is the better source when both are current.
    That is not the same claim. Measured on a machine whose token had stopped
    working: the panel replayed a six-DAY-old API response while a file on the same
    disk held a reading from six hours earlier, and it kept doing that indefinitely
    because nothing ever compared the two.

    Only when the API reading is already flagged stale, so a live response is never
    displaced by a local file that happens to have been written a second later.
    #>
    if ($api -and $script:LuneStale -and $samples.Count -gt 0 -and $script:LuneFetchedAt) {
        $localAt = [DateTimeOffset]::FromUnixTimeMilliseconds([long]$samples[-1].t).UtcDateTime
        if ($localAt -gt $script:LuneFetchedAt) {
            Write-Verbose ("Local history is newer than the replayed response ({0:0}h); using it." -f
                ($localAt - $script:LuneFetchedAt).TotalHours)
            $api = $null
        }
    }

    if ($api) {
        # "live" only when this really is a fresh reading. A response replayed
        # because the endpoint threw 429 is reported as "cached" and dated by its
        # own fetch time, so a frozen number can never wear a live label.
        $source = if ($script:LuneStale) { 'cached' } else { 'live' }
        $limits = @(Get-LuneProperty $api 'limits')

        $session = ConvertTo-LuneLimitRow ($limits | Where-Object { $_.kind -eq 'session' }       | Select-Object -First 1)
        $weekly  = ConvertTo-LuneLimitRow ($limits | Where-Object { $_.kind -eq 'weekly_all' }    | Select-Object -First 1)
        $scoped  = ConvertTo-LuneLimitRow ($limits | Where-Object { $_.kind -eq 'weekly_scoped' } | Select-Object -First 1)
        if ($scoped.label) { $scopedName = $scoped.label }
    } else {
        $source  = 'offline'
        $blank   = [PSCustomObject]@{ percent = 0; countdown = 'connecting'; date = ''; available = 0; label = '' }
        $session = $blank; $weekly = $blank; $scoped = $blank

        <#
        Built from the local history, which is the whole point of having it.

        These two rows were left blank here while the file on disk held exactly the
        numbers they wanted: fh IS the five-hour window and sd IS the seven-day one.
        So the fallback did not fall back to anything - it drew 0% and "connecting"
        for both, which is why the panel preferred a week-old API response to a
        six-hour-old file and looked broken either way.

        The reset times are estimated from an observed rollover rather than
        reported, and New-LuneLimitRow labels them "est." to say so.
        #>
        if ($samples.Count -gt 0) {
            $session = New-LuneLimitRow -Samples $samples -Field 'fh' -WindowHours 5
            $weekly  = New-LuneLimitRow -Samples $samples -Field 'sd' -WindowHours 168
        }

        # Cache mode: the local history has no per-model bucket, so the third row
        # only appears if the app ever starts recording one.
        $known     = @('fh', 'sd')
        $extraKeys = @()
        if ($samples.Count -gt 0) {
            $extraKeys = @($samples[-1].u.PSObject.Properties.Name | Where-Object { $known -notcontains $_ })
        }
        if ($extraKeys.Count -gt 0) {
            $scoped = New-LuneLimitRow -Samples $samples -Field $extraKeys[0] -WindowHours 168
        }
    }

    $status = if ($api) { 'ok' } else { 'error' }
    # Kept short: this line sits under the footer in red, and a sentence there reads
    # as a fault rather than a status.
    $errorText = if ($api) { '' } else { 'no connection - run any claude command' }
    $staleNote = ''

    <#
    The Free plan is a state, not a failure.

    Claude Code is a Pro and Max benefit, so a Free account has no Claude Code
    session for this panel to read and the usage endpoint returns nothing to plot.
    Reported as a generic connection error, that looks like the widget is broken and
    sends the user hunting for a fault that does not exist. It says what is actually
    true instead, and drops the red state, because nothing is wrong.
    #>
    if (-not $api -and $account.plan -match '^Free\b') {
        $status    = 'free'
        $errorText = 'Claude Code needs Pro or Max'
    }

    <#
    Freshness is measured against the clock the DISPLAYED numbers came from.

    The percentages are the API's, fetched moments ago, but the age used to be taken
    from the desktop app's sample file - a separate, laggy record that only advances
    while that app is running. The panel therefore reported figures as "3m ago" when
    they were seconds old, dimmed its status dot, and read as frozen while it was in
    fact perfectly live. Live data is timed from the fetch; only the offline
    fallback is timed from the stored sample.
    #>
    $ageText = ''
    $ageMin  = 0
    $isStale = 0
    $stamp   = $null

    if ($api -and $script:LuneFetchedAt) {
        # UTC on the way in, because that is what the cache records.
        $stamp = ([DateTime]::SpecifyKind($script:LuneFetchedAt, [DateTimeKind]::Utc)).ToLocalTime()
    } elseif ($samples.Count -gt 0) {
        $stamp = (ConvertFrom-LuneEpoch ([double]$samples[-1].t)).ToLocalTime()
    }

    if ($stamp) {
        $ageSec = [int]([DateTime]::Now - $stamp).TotalSeconds
        $ageMin = [int]($ageSec / 60)

        <#
        Staleness is judged on the age of the reading, not on whether the last
        transport attempt happened to be refused. A poll that gets throttled two
        seconds after a good fetch still leaves a current figure on screen, and
        flagging that as stale put a red "reconnecting" line under a number that was
        zero minutes old.

        Both thresholds scale with the poll interval rather than sitting at a
        constant, so a reading taken exactly as designed during a backoff is not
        labelled stale for doing the right thing.
        #>
        $staleAfter = [Math]::Max(120, ($interval * 2) + 30)
        $liveWithin = [Math]::Max(90,   $interval + 15)

        $isStale = $(if ($ageSec -gt $staleAfter) { 1 } else { 0 })

        # Days, once it has been that long. A laptop shut for a weekend came back
        # reporting "3720m ago", which is a number nobody converts in their head.
        $ageWord = if ($ageSec -lt $liveWithin) { 'live' }
                   elseif ($ageMin -lt 60)      { "${ageMin}m ago" }
                   elseif ($ageMin -lt 1440)    { '{0}h {1}m ago' -f [int]($ageMin / 60), ($ageMin % 60) }
                   else { '{0}d {1}h ago' -f [int]($ageMin / 1440), [int](($ageMin % 1440) / 60) }

        $ageText = '{0} ({1})' -f $stamp.ToString('h:mmtt').ToLower(), $ageWord
    }

    <#
    A stale panel is waiting, not broken, and it has to say so.

    Close Claude Code or shut the laptop for three days and the figures on screen
    are simply the last ones taken. The old wording - "reconnecting - reading is
    4320m old" - read like a fault and gave the age in a unit nobody converts.
    This says which of the two it is, how old the reading is in units people use,
    and what makes it current again.

    The word is "stale" because that is what the README calls it.
    #>
    if ($isStale -eq 1 -and $status -eq 'ok') {
        $status    = 'stale'
        <#
        The instruction has to match the reason, or it is worse than none.

        "Run any claude command" is right when the token has simply lapsed and
        wrong when the CLI is signed out - running a command there prints "Not
        logged in" and changes nothing, which is how a panel sat on a
        seventeen-day-old reading telling its owner to do the one thing that could
        not help.
        #>
        $fix = switch ($script:LuneAuthState) {
            'signedout' { 'Claude Code is signed out - run: claude /login' }
            'missing'   { 'Claude Code was not found - install it and sign in' }
            'forbidden' { 'the token is not allowed to read usage - sign in with: claude /login' }
            default     { 'Run any claude command to refresh it' }
        }
        $staleNote = "showing the last reading, $ageWord. $fix"

        <#
        And on the panel itself, not only in the tooltip.

        A signed-out panel draws its last reading: old percentages, a bar that
        resets "now", a flat chart. It looks broken, because from the outside it
        is indistinguishable from broken - the one thing that would explain it was
        hidden behind a hover.

        Two words, not a sentence. This lands in the footer, which is sized for a
        timestamp; the first attempt put "signed out - run claude /login" there and
        it ran off the side of the card. The instruction lives in the tooltip and
        the dot; the footer only has to say which of the two states this is.
        #>
        $ageText = switch ($script:LuneAuthState) {
            'signedout' { 'signed out' }
            'missing'   { 'not installed' }
            'forbidden' { 'no access' }
            default     { $ageText }
        }
    }

    # The iOS-style presentation counts down what is LEFT rather than up what is
    # used, so the number, the bar length and the wording must flip together -
    # "98% left" beside a 98%-full bar of *used* would be a lie.
    $remaining = ($config['ShowRemaining'] -eq '1')
    $usageWord = if ($remaining) { 'left' } else { 'used' }

    $themeKey = $config['Theme']
    if (-not $themeKey) { $themeKey = 'Dark' }

    $colourNormal = Get-LuneRgba $presets $themeKey 'Normal' '110,175,255,255'
    $colourWarn   = Get-LuneRgba $presets $themeKey 'Warn'   '255,178,72,255'
    $colourCrit   = Get-LuneRgba $presets $themeKey 'Crit'   '255,94,94,255'

    $warnAt = [double]($config['WarningThreshold']);   if ($warnAt -le 0)       { $warnAt = 75 }
    $critAt = [double]($config['CriticalThreshold']);  if ($critAt -le $warnAt) { $critAt = 90 }

    $sessionShown = Get-LuneDisplayValue $session $remaining
    $weeklyShown  = Get-LuneDisplayValue $weekly  $remaining
    $scopedShown  = Get-LuneDisplayValue $scoped  $remaining

    <#
    ONLY PUBLISH WHAT THE PANEL DRAWS.

    Every key here is compared against the last poll to decide whether the skin
    needs reloading, so a key that changes constantly and is drawn nowhere forces
    a reload that shows nothing new. The adaptive poll interval was published here
    for a while; it moves on almost every poll, so the comparison never settled and
    the panel reloaded about once a second, forever - each reload killing the
    poller that issued it and starting another.

    Before adding a key, check that a layout or a measure actually reads it.
    #>
    $values = [ordered]@{
        Status            = $(
            $detail = $(if ($errorText) { $errorText } elseif ($staleNote) { $staleNote } else { '' })
            if ($detail) { '{0} - {1}' -f $status, $detail } else { $status }
        )
        # The dot goes amber/red on staleness too, not just on outright failure.
        StatusOk          = $(if ($status -eq 'ok' -and $isStale -eq 0) { 1 } else { 0 })
        # A third state between healthy and faulty. StatusOk alone is a boolean, so
        # anything that is not "ok" turned the indicator red - including a Free
        # account, where there is nothing to show and no fault to report.
        StatusFree        = $(if ($status -eq 'free') { 1 } else { 0 })
        IsStale           = $isStale
        SampleAgeMin      = $ageMin
        UsageWord         = $usageWord
        FiveHourShown     = $sessionShown.shown
        SevenDayShown     = $weeklyShown.shown
        ScopedShown       = $scopedShown.shown
        FiveHourBar       = $sessionShown.bar
        SevenDayBar       = $weeklyShown.bar
        ScopedBar         = $scopedShown.bar
        FiveHourPercent   = $session.percent
        FiveHourCountdown = $session.countdown
        FiveHourDate      = $session.date
        FiveHourAvailable = $session.available
        SevenDayPercent   = $weekly.percent
        SevenDayCountdown = $weekly.countdown
        SevenDayDate      = $weekly.date
        SevenDayAvailable = $weekly.available
        ScopedPercent     = $scoped.percent
        ScopedCountdown   = $scoped.countdown
        ScopedDate        = $scoped.date
        ScopedAvailable   = $scoped.available
        ThirdLabel        = $scopedName
        BarColorFive      = Get-LuneBarColor $session $colourNormal $colourWarn $colourCrit $warnAt $critAt
        BarColorSeven     = Get-LuneBarColor $weekly  $colourNormal $colourWarn $colourCrit $warnAt $critAt
        BarColorThird     = Get-LuneBarColor $scoped  $colourNormal $colourWarn $colourCrit $warnAt $critAt
        Source            = $source
        LastUpdated       = $ageText
        <#
        The fault, when there is one, is folded into Status rather than published
        beside it.

        Rainmeter cannot leave a tooltip line out, so a tooltip built as
        "#Status#, #ErrorText#, last sample" printed an empty line down the middle
        whenever nothing was wrong, which is nearly always. Status now carries the
        detail and the tooltip is two lines.

        usage.json keeps ErrorText as its own field; it is read by people rather
        than by a meter, and has room for the distinction.
        #>
        ErrorText         = $(if ($errorText) { $errorText } else { $staleNote })
        # Lets the layouts hide the warning row and reclaim its height instead of
        # reserving space that is empty almost all the time - at the small size that
        # reserved strip was printing over the last bar.
        HasError          = $(if ($errorText -or $staleNote) { 1 } else { 0 })
        AccountName       = $account.name
        AccountPlan       = $account.plan
        AccountUuid       = $account.uuid
        PlanRenews        = $account.renews
        ExtraModel        = $account.extraModel
        ExtraModelDesc    = $account.extraDesc
        HasExtraModel     = $account.hasExtra
        TokensToday       = Get-LuneTokensToday
        SampleCount       = $samples.Count
    }

    <#
    The chart is the day's spend rate, not the week's level.

    The bar above already shows how much of the weekly allowance is gone. Plotting
    the same number underneath it drew a ramp that flattened to a solid line
    whenever usage was steady - which is what it had become on screen. Each column
    here is the share of the weekly allowance consumed in that hour, so a heavy
    session stands up and an idle night is empty.

    Twenty-four columns, one per hour, over the last day.
    #>
    $weeklySamples = @()
    if ($weekly.available -ge 1) {
        $weeklySamples = Add-LuneWeeklySample -Percent ([double]$weekly.percent) -Path $LuneTrendPath
    }
    <#
    An empty return means the store could not be read, not that it is empty, and
    the caption has to be able to tell those two apart.

    Saying "no spend in the last 24h" when the history simply would not open sent
    the reader looking for a usage explanation for what is a file problem. The
    states are now distinct: nothing recorded yet, a store that exists but will
    not parse, and a genuinely quiet day.
    #>
    $storeState = 'ok'
    if ($weeklySamples.Count -eq 0) {
        $stored = Read-LuneJson $LuneTrendPath
        if ($stored -and $stored.samples) {
            $weeklySamples = @($stored.samples | Where-Object { $null -ne $_.t } | Sort-Object { [double]$_.t })
        } elseif (Test-Path -LiteralPath $LuneTrendPath) {
            $storeState = 'unreadable'
        } else {
            $storeState = 'new'
        }
    }

    $columns = 24
    $rate = Get-LuneSpendRate -Samples $weeklySamples -Hours 24 -Points $columns
    Write-Verbose ("Spend rate: {0} samples in ({1}), total={2} peak={3} covered={4}/{5}." -f
        @($weeklySamples).Count, $storeState, $rate.total, $rate.peak, $rate.covered, $columns)
    <#
    One key per column and no spares. The layout draws exactly $columns columns,
    so a published Spark25 had no meter to reach and only widened every file it
    travelled through.

    Each column also gets its own tooltip line naming the hour it covers, because
    a chart of unlabelled blocks cannot tell you which one was ten this morning.
    Rainmeter has no per-shape tooltip, so each column is its own meter and this
    is the text it shows.
    #>
    for ($i = 0; $i -lt $columns; $i++) {
        $values["Spark$($i+1)"] = $(if ($i -lt $rate.points.Count) { $rate.points[$i] } else { 0 })

        $hour = $(if ($i -lt $rate.labels.Count) { $rate.labels[$i] } else { '' })
        $spent = $(if ($i -lt $rate.spend.Count) { $rate.spend[$i] } else { $null })
        $values["SparkTip$($i+1)"] = $(
            if ($null -eq $spent)  { "$hour - no reading on record" }
            elseif ($spent -le 0)  { "$hour - nothing spent" }
            else                   { '{0} - {1}% of the weekly allowance' -f $hour, $spent }
        )
    }

    $values['TrendCols']    = $columns
    $values['TrendPeak']    = $rate.peak
    $values['TrendCovered'] = $rate.covered
    <#
    A label, not a sentence.

    "21% today, peak 5%/h" ran most of the way across the panel and read as prose.
    This sits right-aligned opposite the word "Spend rate" and says the one figure
    that belongs beside a 24-hour chart; the peak and the hour-by-hour detail are
    in the tooltip, where there is room for them.

    A quiet day still reports its zero. Blanking it, or saying "no spend", made a
    working chart look like a broken one.
    #>
    $values['SparkRange'] = $(
        if     ($storeState -eq 'unreadable')                            { 'unavailable' }
        elseif ($storeState -eq 'new' -or @($weeklySamples).Count -lt 2) { 'collecting' }
        else                                                             { '{0}% in 24h' -f $rate.total }
    )

    <#
    Publish only what the panel draws. The refresh fires when the published content
    differs, so a key that changes and is drawn nowhere buys a reload for nothing.
    AccountUuid also has no business on disk; the packager treats it as a leak.

    usage.json still gets everything.
    #>
    # IsStale is drawn: the status dot reads it to go amber rather than red when
    # the panel is waiting on Claude Code instead of failing.
    $notDrawn = @(
        'SampleAgeMin', 'Source', 'HasError',
        'FiveHourPercent', 'SevenDayPercent', 'ScopedPercent',
        'AccountUuid', 'ExtraModelDesc',
        # Folded into Status above; kept in usage.json, drawn nowhere.
        'ErrorText'
    )
    $flat = @{}
    foreach ($key in $values.Keys) {
        if ($notDrawn -contains $key) { continue }
        $flat[$key] = $values[$key]
    }

    <#
    Durable copy, handy for debugging and for any other consumer.

    Written BEFORE the panel is published, which looks backwards for a file the
    panel does not read. Publishing ends in a !Refresh, the refresh reloads the
    skin, and the reload tears down the RunCommand measure that owns this process -
    so anything after it does not run. This write was after it, and only landed on
    the polls that happened not to change anything. The file sat days behind the
    panel while claiming to be the durable record of it, and running the script by
    hand with -NoRefresh - which issues no bang - wrote it correctly every time,
    which is what kept it hidden.

    A failure here must still not reach the caller. It is a convenience file, and
    throwing would turn a completed update into an error state and a red dot.

    Verified by denying write access to the state directory: the panel updated and
    then the script still exited 1 on this line.
    #>
    try {
        $export = [ordered]@{
            product   = $LuneProduct
            version   = $LuneVersion
            author    = "$LuneAuthor ($LuneHandle)"
            writtenAt = [DateTime]::Now.ToString('s')
        }
        foreach ($key in $values.Keys) { $export[$key] = $values[$key] }

        $json = [PSCustomObject]$export | ConvertTo-Json -Depth 4
        $temp = "$LuneExportPath.tmp"
        [System.IO.File]::WriteAllText($temp, $json, (New-Object System.Text.UnicodeEncoding($false, $true)))
        Move-Item -LiteralPath $temp -Destination $LuneExportPath -Force
    } catch {
        Write-Verbose "Could not write $LuneExportPath ($($_.Exception.Message)); publishing anyway."
    }

    Write-Verbose ('session={0}% weekly={1}% scoped={2}% plan={3} source={4} samples={5}' -f
        $session.percent, $weekly.percent, $scoped.percent, $account.plan, $source, $samples.Count)

    # Last, because it may not return: the refresh it issues reloads the skin and
    # kills this process.
    Publish-LuneState -Values $flat
} catch {
    Write-Warning $_.Exception.Message
    Publish-LuneState -Values @{ Status = 'error'; StatusOk = 0; ErrorText = $_.Exception.Message }
    exit 1
}
