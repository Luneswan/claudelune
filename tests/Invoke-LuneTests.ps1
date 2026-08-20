<#
.SYNOPSIS
    The ClaudeLune test suite. Run it before releasing anything.

.DESCRIPTION
    ClaudeLune by Lunez (luneswan).

    Every defect this project has shipped was found by making something testable
    and then running it - and every one of them looked fine until that moment. The
    checks below are the ones that have actually caught something:

      geometry   no combination of scale, size and font can overlap text or
                 produce a bar with no length
      typeface   the row pitch follows the font's own metrics; a fixed factor
                 overlapped captions on 63 of 315 installed fonts
      packaging  the leak guard can FAIL - it once scanned only files the
                 packager had already blanked, so it could never fire
      themes     import validates rather than trusts; 999,0,0 used to be accepted
                 and then silently dropped much later
      settings   one write per Apply, comments preserved, nothing truncated
      upgrade    a user's choices survive, new defaults arrive, account fields
                 are never carried across
      wiring     no bang addresses a meter or measure that does not exist, and
                 nothing is published that nothing draws

    Nothing here needs Rainmeter running, a network connection or a signed-in
    account. Everything happens on copies in the temp directory; the installed
    skin and your own settings are never touched.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tests\Invoke-LuneTests.ps1

.EXAMPLE
    # Adds the exhaustive scale sweep - slower, hundreds of extra configurations.
    powershell -NoProfile -ExecutionPolicy Bypass -File tests\Invoke-LuneTests.ps1 -Full

.NOTES
    Copyright (c) Lunez (luneswan). MIT licence - see LICENSE.
#>

[CmdletBinding()]
param(
    # Run the exhaustive geometry sweep as well as the representative one.
    [switch]$Full
)

$ErrorActionPreference = 'Stop'

$RepoRoot   = Split-Path $PSScriptRoot -Parent
$SkinRoot   = Join-Path $RepoRoot 'Skins\ClaudeLune'
$SourceRes  = Join-Path $SkinRoot '@Resources'
$SettingsUi = Join-Path $SourceRes 'Scripts\Show-LuneSettings.ps1'

$script:Passed = 0
$script:Failed = 0

function Start-Group { param([string]$Name) Write-Host ''; Write-Host $Name -ForegroundColor Cyan }

function Assert-Lune {
    param([string]$What, [bool]$Condition, [string]$Detail = '')
    if ($Condition) {
        $script:Passed++
        Write-Host "  PASS  $What"
    } else {
        $script:Failed++
        Write-Host "  FAIL  $What$(if ($Detail) { "  --  $Detail" })" -ForegroundColor Red
    }
}

<#
Loads one function out of a script without running the rest of it.

The settings window and the installer are scripts, not modules - the window builds
a WPF interface on load and the installer starts installing. Lifting a single
function out by text is what makes them testable at all, and it is why those
functions were separated from their click handlers in the first place.
#>
function Import-LuneFunction {
    param([string]$Path, [string]$Name)
    $text  = [System.IO.File]::ReadAllText($Path)
    $start = $text.IndexOf("function $Name")
    if ($start -lt 0) { throw "$Name not found in $(Split-Path $Path -Leaf)" }
    # The closing brace of a function at column zero, which is how every function
    # in this project is written.
    $end = $text.IndexOf("`n}", $start)
    if ($end -lt 0) { throw "could not find the end of $Name" }
    # Returned rather than evaluated here: Invoke-Expression inside a function
    # defines the result in THAT function's scope, where it vanishes on return.
    # The caller evaluates it at script scope, where the tests can see it.
    return $text.Substring($start, $end - $start + 3)
}

# A private copy of @Resources, so a test can write settings without touching the
# working copy or anything installed.
function New-LuneSandbox {
    $sandbox = Join-Path ([System.IO.Path]::GetTempPath()) ('lunetest-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Force -Path $sandbox | Out-Null
    Copy-Item -Path $SourceRes -Destination $sandbox -Recurse -Force
    return (Join-Path $sandbox '@Resources')
}

function Read-LuneKeys {
    param([string]$Path)
    $map = @{}
    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        if ($line -match '^\s*([A-Za-z]\w*)\s*=\s*(.*)$') { $map[$Matches[1]] = $Matches[2].Trim() }
    }
    return $map
}

# Resolves geometry in a sandbox and returns the metrics as numbers.
function Get-LuneGeometry {
    param([string]$Res, [hashtable]$Settings, [string]$Size)

    $config = Join-Path $Res 'LuneSettings.inc'
    $text = [System.IO.File]::ReadAllText($config)
    foreach ($key in $Settings.Keys) {
        $text = [regex]::Replace($text, "(?m)^$key=.*\r?$", "$key=$($Settings[$key])")
    }
    [System.IO.File]::WriteAllText($config, $text, (New-Object System.Text.ASCIIEncoding))

    $poller = Join-Path $Res 'Scripts\Update-LuneUsage.ps1'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $poller -ResolveOnly -NoRefresh -Size $Size 2>&1 | Out-Null

    $metrics = @{}
    foreach ($line in [System.IO.File]::ReadAllLines((Join-Path $Res 'LuneResolved.inc'))) {
        if ($line -match '^(\w+)=(-?[\d.]+)$') { $metrics[$Matches[1]] = [double]$Matches[2] }
    }
    return $metrics
}

<#
The invariants that keep a panel readable.

These are the properties, not the pixel values: a bar must have length, a row must
contain what is drawn inside it, type must stay visible. Whatever the scales are
set to, all of these hold or the layout is broken.
#>
function Test-LuneGeometry {
    param([hashtable]$M, [string]$Case)

    $rowFits = if ($M.ShowDetail -eq 1) { $M.RowH -ge $M.CapDrop + $M.CapH } else { $M.RowH -ge $M.BarDrop + $M.BarH }
    $checks = @(
        @('bar has usable length',        ($M.BarW -ge 90)),
        @('bar fits inside the panel',    ($M.BarW -le $M.W - 8)),
        @('label clears the bar',         ($M.BarDrop -ge $M.LineH)),
        @('bar clears the caption',       ($M.CapDrop -ge $M.BarDrop + $M.BarH)),
        @('row contains its content',     $rowFits),
        @('body clears the header',       ($M.BodyY -ge $M.HeadY + $M.TitleH)),
        @('type stays visible',           ($M.SmallFS -ge 6 -and $M.LabelFS -ge 6 -and $M.TitleFS -ge 7)),
        @('mark stays visible',           ($M.LogoPx -ge 1 -and $M.LogoPx -le 8)),
        @('padding cannot eat the panel', ($M.Pad -ge 2 -and $M.Pad * 2 -lt $M.W)),
        @('trend stays drawable',         ($M.TrendH -ge 12)),
        @('nothing is negative',          ($M.W -gt 0 -and $M.RowH -gt 0 -and $M.PadB -gt 0 -and $M.GapS -gt 0))
    )
    $broken = @($checks | Where-Object { -not $_[1] } | ForEach-Object { $_[0] })
    Assert-Lune $Case ($broken.Count -eq 0) ($broken -join ', ')
}

# ============================================================== the suite ======

Write-Host ''
Write-Host 'ClaudeLune test suite' -ForegroundColor Cyan
Write-Host "repository : $RepoRoot"

$sandboxes = @()

try {
    # ---------------------------------------------------------------- geometry
    Start-Group 'Geometry holds at every scale'
    $res = New-LuneSandbox; $sandboxes += (Split-Path $res -Parent)

    $axes = @('UserScale', 'WidthScale', 'HeightScale', 'FontScale', 'PadScale', 'RowScale', 'BarScale', 'IconScale')
    # Extremes, the neutral case, and values that are not numbers at all - a scale
    # is something a user can type by hand.
    $values = if ($Full) { @('0.50','0.75','1.00','1.25','1.50','1.75','2.00','9.90','abc','') }
              else       { @('0.50','2.00','abc') }
    $sizes = @('Small', 'Normal', 'Wide', 'Large')

    foreach ($size in $sizes) {
        foreach ($axis in $axes) {
            foreach ($value in $values) {
                $metrics = Get-LuneGeometry -Res $res -Settings @{ $axis = $value } -Size $size
                Test-LuneGeometry -M $metrics -Case "$size with $axis=$(if ($value) { $value } else { '(blank)' })"
            }
            # Back to neutral so axes do not accumulate across cases.
            Get-LuneGeometry -Res $res -Settings @{ $axis = '1.00' } -Size $size | Out-Null
        }
    }

    # ---------------------------------------------------------------- typeface
    Start-Group 'Row pitch follows the typeface, not a fixed factor'
    foreach ($font in 'Segoe UI', 'Consolas', 'Georgia', 'DecoType Naskh', 'Sans Serif Collection', 'No Such Font 9000') {
        foreach ($size in 'Normal', 'Large') {
            $metrics = Get-LuneGeometry -Res $res -Settings @{ FontFace = $font } -Size $size
            Test-LuneGeometry -M $metrics -Case "$size in $font (ratio $($metrics.LineRatio))"
        }
    }
    Get-LuneGeometry -Res $res -Settings @{ FontFace = 'Segoe UI' } -Size 'Normal' | Out-Null

    # ----------------------------------------------------------------- themes
    Start-Group 'Theme files validate rather than trust'
    Invoke-Expression (Import-LuneFunction -Path $SettingsUi -Name 'Read-LuneIni')
    Invoke-Expression (Import-LuneFunction -Path $SettingsUi -Name 'ConvertTo-LuneThemeLines')
    Invoke-Expression (Import-LuneFunction -Path $SettingsUi -Name 'Read-LuneThemeFile')

    $themes  = @('Dark','Amoled','Glass','Light','Clay','Matrix','iOS')
    $colours = @('Bg','Text','Dim','Bright','Accent','Stroke','Track','Normal','Warn','Crit','Scoped','Off')
    $themeFile = Join-Path ([System.IO.Path]::GetTempPath()) ('lunetest-' + [Guid]::NewGuid().ToString('N').Substring(0,8) + '.lunetheme')

    $swatches = @(
        [PSCustomObject]@{ Key = 'Bg';     Value = '10,20,30';       Changed = $true;  Cleared = $false }
        [PSCustomObject]@{ Key = 'Accent'; Value = '217,119,87,255'; Changed = $true;  Cleared = $false }
        [PSCustomObject]@{ Key = 'Text';   Value = '1,2,3';          Changed = $false; Cleared = $false }
    )
    $lines = ConvertTo-LuneThemeLines -Theme 'Matrix' -FontFace 'Georgia' -CornerRadius 18 -BorderWidth 3 -Swatches $swatches
    [System.IO.File]::WriteAllLines($themeFile, $lines, (New-Object System.Text.ASCIIEncoding))
    $round = Read-LuneThemeFile -Path $themeFile -KnownThemes $themes -ColourKeys $colours

    Assert-Lune 'round trip keeps the theme'   ($round['Theme'] -eq 'Matrix')
    Assert-Lune 'round trip keeps the font'    ($round['FontFace'] -eq 'Georgia')
    Assert-Lune 'round trip keeps the radius'  ($round['CornerRadius'] -eq 18)
    Assert-Lune 'round trip keeps a colour'    ($round.Colours['Bg'] -eq '10,20,30')
    Assert-Lune 'round trip keeps alpha'       ($round.Colours['Accent'] -eq '217,119,87,255')
    Assert-Lune 'untouched colour exports blank, meaning follow the theme' ($round.Colours['Text'] -eq '')
    Assert-Lune 'a clean file rejects nothing' ($round.Rejected.Count -eq 0) ($round.Rejected -join '; ')

    @'
[Variables]
Theme=NotARealTheme
FontFace=Consolas
CornerRadius=abc
BorderWidth=2
CustomBg=999,0,0
CustomAccent=1,2
CustomText=  40 , 50 , 60
CustomWarn=
'@ | Set-Content $themeFile -Encoding Ascii
    $bad = Read-LuneThemeFile -Path $themeFile -KnownThemes $themes -ColourKeys $colours

    Assert-Lune 'unknown theme refused'             (-not $bad.ContainsKey('Theme'))
    Assert-Lune 'a valid font beside it survives'   ($bad['FontFace'] -eq 'Consolas')
    Assert-Lune 'non-numeric radius refused'        (-not $bad.ContainsKey('CornerRadius'))
    Assert-Lune 'a valid number beside it survives' ($bad['BorderWidth'] -eq 2)
    Assert-Lune 'channel above 255 refused'         (-not $bad.Colours.ContainsKey('Bg'))
    Assert-Lune 'two-channel colour refused'        (-not $bad.Colours.ContainsKey('Accent'))
    Assert-Lune 'spaced colour normalised'          ($bad.Colours['Text'] -eq '40,50,60')
    Assert-Lune 'blank colour means follow the theme' ($bad.Colours['Warn'] -eq '')
    Assert-Lune 'every refusal is reported'         ($bad.Rejected.Count -eq 4) "got $($bad.Rejected.Count)"

    'not a theme file at all' | Set-Content $themeFile -Encoding Ascii
    $junk = Read-LuneThemeFile -Path $themeFile -KnownThemes $themes -ColourKeys $colours
    Assert-Lune 'a file that is not a theme applies nothing and does not throw' ($junk.Applied -eq 0)
    Remove-Item $themeFile -Force -ErrorAction SilentlyContinue

    # --------------------------------------------------------------- settings
    Start-Group 'Settings are written once, without losing the file'
    Invoke-Expression (Import-LuneFunction -Path $SettingsUi -Name 'Set-LuneIniKeys')

    $config   = Join-Path $res 'LuneSettings.inc'
    $before   = (Get-Content $config).Count
    $comments = (Get-Content $config | Where-Object { $_ -match '^\s*;' }).Count

    Set-LuneIniKeys $config @{
        Theme = 'Matrix'; HeightScale = '1.75'; CustomAccent = '10,20,30'; BrandNewKey = 'appended'
    }
    $written = Read-LuneKeys $config

    Assert-Lune 'an existing key is replaced'      ($written['Theme'] -eq 'Matrix')
    Assert-Lune 'a second key is replaced too'     ($written['HeightScale'] -eq '1.75')
    Assert-Lune 'an override is written'           ($written['CustomAccent'] -eq '10,20,30')
    Assert-Lune 'an unknown key is appended'       ($written['BrandNewKey'] -eq 'appended')
    Assert-Lune 'untouched keys survive'           ($written['WarningThreshold'] -eq '75')
    Assert-Lune 'every comment survives'           ((Get-Content $config | Where-Object { $_ -match '^\s*;' }).Count -eq $comments)
    Assert-Lune 'no lines are lost'                ((Get-Content $config).Count -eq $before + 1)
    Assert-Lune 'no temporary file is left behind' (-not (Test-Path "$config.new"))

    # ---------------------------------------------------------------- upgrade
    Start-Group 'An upgrade keeps what the user chose'
    Invoke-Expression (Import-LuneFunction -Path (Join-Path $RepoRoot 'install.ps1') -Name 'Merge-LuneSettings')

    $fresh = New-LuneSandbox; $sandboxes += (Split-Path $fresh -Parent)
    $installed = @'
[Variables]
Theme=Matrix
Size=Large
HeightScale=1.75
FontFace=Georgia
AccountName=Someone Real
'@
    Merge-LuneSettings -OldText $installed -NewPath (Join-Path $fresh 'LuneSettings.inc')
    $merged = Read-LuneKeys (Join-Path $fresh 'LuneSettings.inc')

    Assert-Lune 'the chosen theme survives'               ($merged['Theme'] -eq 'Matrix')
    Assert-Lune 'the chosen scale survives'               ($merged['HeightScale'] -eq '1.75')
    Assert-Lune 'the chosen font survives'                ($merged['FontFace'] -eq 'Georgia')
    Assert-Lune 'a newly added key gets its default'      ($merged['WarningThreshold'] -eq '75')
    Assert-Lune 'account fields are never carried across' ([string]::IsNullOrEmpty($merged['AccountName']))

    # --------------------------------------------------------------- packaging
    Start-Group 'The build refuses to ship anything personal'
    $packager = Join-Path $RepoRoot 'build\New-LunePackage.ps1'
    $outDir   = Join-Path ([System.IO.Path]::GetTempPath()) ('lunepkg-' + [Guid]::NewGuid().ToString('N').Substring(0,8))

    function Invoke-LuneBuild {
        param([string]$Line)
        $target = Join-Path $SourceRes 'LuneSettings.inc'
        $backup = [System.IO.File]::ReadAllText($target)
        try {
            if ($Line) {
                [System.IO.File]::WriteAllText($target, ($backup.TrimEnd() + "`r`n$Line`r`n"), (New-Object System.Text.ASCIIEncoding))
            }
            # A refusal is the expected result for most of these, and a refusal
            # writes to standard error. Under ErrorActionPreference=Stop that
            # would abort the suite at exactly the moment the guard did its job.
            $previous = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            try {
                return (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $packager -Version 0.0.0 -OutDir $outDir 2>&1 | Out-String)
            } finally { $ErrorActionPreference = $previous }
        } finally {
            [System.IO.File]::WriteAllText($target, $backup, (New-Object System.Text.ASCIIEncoding))
        }
    }

    # A guard that cannot fail is not a guard. This one could not, once.
    Assert-Lune 'an account name stops the build' `
        ((Invoke-LuneBuild -Line 'AccountName=Some Real Person') -match 'Refusing to package')
    Assert-Lune 'a renewal date stops the build' `
        ((Invoke-LuneBuild -Line 'PlanRenews=Wed 5th Aug') -match 'Refusing to package')
    Assert-Lune 'an account identifier stops the build' `
        ((Invoke-LuneBuild -Line 'AccountUuid=08cc8ef2-36a0-4498-8482-3213aab30393') -match 'Refusing to package')
    Assert-Lune 'an email address stops the build' `
        ((Invoke-LuneBuild -Line 'Contact=someone@example.com') -match 'Refusing to package')

    $clean = Invoke-LuneBuild -Line ''
    Assert-Lune 'an untouched working copy builds' ($clean -notmatch 'Refusing to package') $clean

    # And the package itself, read back, carries nothing personal.
    $rmskin = Get-ChildItem -Path $outDir -Filter '*.rmskin' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($rmskin) {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $bytes = [System.IO.File]::ReadAllBytes($rmskin.FullName)
        $zipLength = [BitConverter]::ToInt64($bytes, $bytes.Length - 16)
        $zipCopy = Join-Path $outDir 'inspect.zip'
        [System.IO.File]::WriteAllBytes($zipCopy, $bytes[0..($zipLength - 1)])

        <#
        Rainmeter has to be able to open this, and for a long time it could not.

        The suite checked that a package was produced and that its contents were
        clean, and never that it was installable. Windows PowerShell's
        CreateFromDirectory writes Path.DirectorySeparatorChar into entry names,
        so every path in the archive read "Skins\ClaudeLune\..." - which the ZIP
        format does not define. Rainmeter refused the package outright and the
        build reported success every time.
        #>
        $names = @()
        $manifestHead = @()
        $data = ''; $all = ''
        $archive = [System.IO.Compression.ZipFile]::OpenRead($zipCopy)
        foreach ($entry in $archive.Entries) {
            $names += $entry.FullName
            if ($entry.FullName -eq 'RMSKIN.ini') {
                $buffer = New-Object byte[] 3
                $handle = $entry.Open()
                [void]$handle.Read($buffer, 0, 3)
                $handle.Close()
                $manifestHead = $buffer
            }
            $reader = New-Object System.IO.StreamReader($entry.Open())
            $body = $reader.ReadToEnd(); $reader.Close()
            $all += $body + "`r`n"
            if ($entry.Name -like '*.inc') { $data += $body + "`r`n" }
        }
        $archive.Dispose()

        $backslashed = @($names | Where-Object { $_ -like '*\*' })
        Assert-Lune 'archive paths use forward slashes' ($backslashed.Count -eq 0) `
            (($backslashed | Select-Object -First 3) -join ', ')
        Assert-Lune 'RMSKIN.ini sits at the root of the archive' ($names -contains 'RMSKIN.ini')

        # A BOM makes Rainmeter read "[rmskin]" with three stray bytes attached,
        # find no section, and reject the package.
        Assert-Lune 'the manifest carries no byte order mark' `
            (-not ($manifestHead.Count -eq 3 -and $manifestHead[0] -eq 0xEF -and
                   $manifestHead[1] -eq 0xBB -and $manifestHead[2] -eq 0xBF))
        Assert-Lune 'the skin is under Skins/ where Rainmeter looks' `
            ($names -contains 'Skins/ClaudeLune/ClaudeLune.ini')

        <#
        Bit 11 of the general purpose flag marks entry names as UTF-8. Rainmeter
        rejects the package without it, and says the packaging tool is at fault
        rather than the flag. Checked on the first local file header, which is
        where the packager writes RMSKIN.ini.
        #>
        Assert-Lune 'entry names are flagged UTF-8, which Rainmeter requires' `
            (([BitConverter]::ToUInt16($bytes, 6) -band 0x0800) -ne 0) `
            ("flags=0x{0:X4}" -f [BitConverter]::ToUInt16($bytes, 6))

        # The footer is how Rainmeter finds where the archive ends: an Int64 of
        # the ZIP length, a zero byte, then "RMSKIN" and a terminating zero.
        $footer = $bytes[($bytes.Length - 16)..($bytes.Length - 1)]
        Assert-Lune 'the footer records the archive length' `
            ([BitConverter]::ToInt64($footer, 0) -eq ($bytes.Length - 16))
        Assert-Lune 'the footer carries the RMSKIN tag' `
            ((-join ($footer[9..14] | ForEach-Object { [char]$_ })) -eq 'RMSKIN')

        Assert-Lune 'the package carries no populated account field' `
            (-not ($data -match '(?m)^[ \t]*(AccountName|AccountPlan|AccountUuid|PlanRenews)[ \t]*=[ \t]*\S'))
        Assert-Lune 'the package carries no email address' `
            (-not ($all -match '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'))
        Assert-Lune 'the package carries no account identifier' `
            (-not ($all -match '\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b'))
        Assert-Lune 'the package carries the authorship mark' ($all -match 'luneswan')
    } else {
        Assert-Lune 'a package was produced to inspect' $false 'no .rmskin was built'
    }
    Remove-Item $outDir -Recurse -Force -ErrorAction SilentlyContinue

    # ------------------------------------------------------------- the chart
    Start-Group 'The spend-rate chart says what it means'
    $Poller = Join-Path $SourceRes 'Scripts\Update-LuneUsage.ps1'
    Invoke-Expression (Import-LuneFunction -Path $Poller -Name 'Set-LuneColorAlpha')
    Invoke-Expression (Import-LuneFunction -Path $Poller -Name 'Get-LuneSpendRate')

    Assert-Lune 'alpha replaces the fourth channel'  ((Set-LuneColorAlpha '10,132,255,255' 20) -eq '10,132,255,20')
    Assert-Lune 'alpha is added to a three-channel colour' ((Set-LuneColorAlpha '10,132,255' 90) -eq '10,132,255,90')
    Assert-Lune 'alpha is clamped to a byte'         ((Set-LuneColorAlpha '1,2,3,4' 900) -eq '1,2,3,255')
    Assert-Lune 'a colour it cannot parse is returned untouched' ((Set-LuneColorAlpha 'nonsense' 20) -eq 'nonsense')

    <#
    The three states are the whole readability of the chart, so they are asserted
    rather than assumed: an hour with no reading, an hour recorded as idle, and an
    hour with real spend must not draw the same.
    #>
    <#
    Anchored to the middle of a clock hour, not to "now".

    The columns are clock hours, so a fixture built from the current instant
    depends on what minute the suite runs at: two readings a minute apart either
    side of the hour land in different columns, and the newest column then shows
    no rise. This passed all day here and failed on CI at 20:00:20, twenty seconds
    past the hour. Putting both readings inside one hour makes the case identical
    whenever it runs.
    #>
    $hour = 3600000
    $topOfHour = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $topOfHour = $topOfHour - ($topOfHour % $hour)
    $base = $topOfHour + (30 * 60000)   # half past, so the hour has room either side

    # Readings for the two most recent hours only: one idle, then one that climbs.
    $samples = @(
        [PSCustomObject]@{ t = $base - (2 * $hour);    w = 40 },
        [PSCustomObject]@{ t = $base - $hour - 600000; w = 40 },
        [PSCustomObject]@{ t = $base - (20 * 60000);   w = 40 },
        [PSCustomObject]@{ t = $base;                  w = 46 }
    )
    $rate = Get-LuneSpendRate -Samples $samples -Hours 24 -Points 24

    Assert-Lune 'one column per hour asked for'      ($rate.points.Count -eq 24)
    Assert-Lune 'an hour with no reading draws nothing' ($rate.points[0] -eq 0)
    Assert-Lune 'an hour with spend stands well above a stub' ($rate.points[23] -gt 20) "got $($rate.points[23])"
    Assert-Lune 'the total is what was actually spent' ($rate.total -eq 6) "got $($rate.total)"

    # A weekly reset drops the figure. That is not negative spending, and a column
    # cannot be drawn below the axis anyway.
    $reset = Get-LuneSpendRate -Samples @(
        [PSCustomObject]@{ t = $base - (2 * $hour); w = 98 },
        [PSCustomObject]@{ t = $base - $hour;       w = 99 },
        [PSCustomObject]@{ t = $base - 60000;       w = 3  },
        [PSCustomObject]@{ t = $base;               w = 5  }
    ) -Hours 24 -Points 24
    Assert-Lune 'a reset never produces a negative column' (@($reset.points | Where-Object { $_ -lt 0 }).Count -eq 0)
    Assert-Lune 'a reset does not swallow the spend after it' ($reset.points[23] -gt 0)

    Assert-Lune 'too little history is not an error' ((Get-LuneSpendRate -Samples @() -Hours 24 -Points 24).points.Count -eq 24)

    # ------------------------------------------------ generated source is fresh
    Start-Group 'Generated source matches its generator'

    <#
    The chart is forty-eight Shape lines that differ only by an index, written by
    build\New-LuneTrendMeters.ps1. Committing generated output is fine; letting it
    drift from the generator is not, because the next person to run the generator
    silently reverts whatever was hand-patched into the layout in between.
    #>
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
        -File (Join-Path $RepoRoot 'build\New-LuneTrendMeters.ps1') -Check | Out-Null
    Assert-Lune 'the Large layout matches build\New-LuneTrendMeters.ps1' ($LASTEXITCODE -eq 0) `
        'run build\New-LuneTrendMeters.ps1 and commit the result'

    <#
    The twelve palette entries are declared twice - once in the poller, which
    resolves them, and once in the settings window, which offers them as swatches.
    Neither can import the other: Rainmeter launches them as separate processes,
    and each has to stand alone. So they are checked against each other instead. A
    colour added to one and forgotten in the other is a swatch that writes a key
    nothing reads, or a palette entry with no way to set it.
    #>
    $pollerText   = [System.IO.File]::ReadAllText((Join-Path $SourceRes 'Scripts\Update-LuneUsage.ps1'))
    $settingsText = [System.IO.File]::ReadAllText($SettingsUi)

    # Non-greedy to the first line that is nothing but a closing paren. Entries end
    # in ")," so they cannot terminate the match early; anything looser ran on and
    # swallowed the opacity table further down the file.
    $pollerBlock = [regex]::Match($pollerText, '\$palette\s*=\s*@\((?<body>.*?)\r?\n\s*\)', 'Singleline')
    $uiBlock     = [regex]::Match($settingsText, '\$LUNE_COLOURS\s*=\s*@\((?<body>.*?)\r?\n\)', 'Singleline')
    Assert-Lune 'the poller declares a palette' $pollerBlock.Success
    Assert-Lune 'the settings window declares a palette' $uiBlock.Success

    # Poller pairs are (published name, preset suffix); the window's triples are
    # (preset suffix, published name, label). Compared as "suffix>name" either way.
    $pollerPairs = @([regex]::Matches($pollerBlock.Groups['body'].Value, "@\('(?<a>\w+)',\s*'(?<b>\w+)'\)") |
        ForEach-Object { '{0}>{1}' -f $_.Groups['b'].Value, $_.Groups['a'].Value } | Sort-Object)
    $uiPairs = @([regex]::Matches($uiBlock.Groups['body'].Value, "@\('(?<a>\w+)',\s*'(?<b>\w+)',\s*'[^']*'\)") |
        ForEach-Object { '{0}>{1}' -f $_.Groups['a'].Value, $_.Groups['b'].Value } | Sort-Object)

    Assert-Lune 'the poller palette has twelve entries' ($pollerPairs.Count -eq 12) "got $($pollerPairs.Count)"
    Assert-Lune 'the settings palette has twelve entries' ($uiPairs.Count -eq 12) "got $($uiPairs.Count)"
    Assert-Lune 'both palettes name the same colours' (($pollerPairs -join ',') -eq ($uiPairs -join ',')) `
        ("poller: $($pollerPairs -join ' ') / window: $($uiPairs -join ' ')")

    # -------------------------------------------------- nothing personal on disk
    Start-Group 'The working copy carries nothing personal'

    <#
    .gitignore cannot solve this one, which is why it is a test.

    LuneLive.inc and LuneResolved.inc are tracked on purpose - they ship as the
    placeholders a fresh install draws before its first poll - and running the
    skin from a working copy rewrites them with a real account name, plan and
    renewal date. Ignoring them would break the install; committing them publishes
    an account. So the repository is checked instead, on every push, for the shapes
    that data actually takes.

    The packager runs the same guard over the staged tree. This one runs earlier,
    on what is about to be committed.
    #>
    $accountKeys = 'AccountName|AccountPlan|AccountUuid|PlanRenews|ExtraModel|ExtraModelDesc'
    $sep  = [string][char]92
    $skip = @('.git', 'dist', '_private', 'docs', '.github')
    $scanned = @(Get-ChildItem -LiteralPath $RepoRoot -Recurse -File |
        Where-Object {
            $rel  = $_.FullName.Substring($RepoRoot.Length).Trim($sep)
            $head = ($rel -split [regex]::Escape($sep))[0]
            ($skip -notcontains $head) -and ($_.Extension -in '.inc', '.ps1', '.ini', '.md', '.vbs', '.txt', '.yml')
        })

    $leaks = @()
    foreach ($file in $scanned) {
        $text = [System.IO.File]::ReadAllText($file.FullName)
        $rel  = $file.FullName.Substring($RepoRoot.Length).Trim($sep)
        # Account keys only where data lands. In a .ps1 the same text is the code
        # that assigns the field, not a field carrying a value.
        if ($file.Extension -eq '.inc' -and $text -match "(?m)^[ \t]*($accountKeys)[ \t]*=[ \t]*\S") {
            $leaks += "$rel has a populated account field"
        }
        <#
        The suites carry these patterns in their own source, so scanning them for
        the patterns finds the search itself. Excluded by name rather than by
        folder, so anything else dropped into tests\ is still checked.
        #>
        if ($file.Name -notlike 'Invoke-Lune*.ps1') {
            if ($text -match '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}') {
                $leaks += "$rel contains an email address"
            }
            if ($text -match '\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b') {
                $leaks += "$rel contains an account identifier"
            }
        }
    }
    Assert-Lune "$($scanned.Count) working-copy files carry no account data" ($leaks.Count -eq 0) `
        (($leaks | Select-Object -Unique) -join '; ')

    # The two files most likely to catch a real reading must be committed blank.
    foreach ($generated in @('LuneLive.inc', 'LuneResolved.inc')) {
        $text = [System.IO.File]::ReadAllText((Join-Path $SourceRes $generated))
        Assert-Lune "$generated is committed without a reading in it" `
            (-not ($text -match "(?m)^[ \t]*($accountKeys)[ \t]*=[ \t]*\S"))
    }

    $ignore = Get-Content (Join-Path $RepoRoot '.gitignore') -Raw
    Assert-Lune 'the build output is ignored'        ($ignore -match '(?m)^dist/')
    Assert-Lune 'private working notes are ignored'  ($ignore -match '(?m)^/_private/')

    # ------------------------------------------------------ include precedence
    Start-Group 'Nothing included later overwrites a resolved value'

    <#
    Later includes win in Rainmeter, so a file included after LuneResolved.inc must
    not define a key the resolver writes.

    LuneMark.inc carried "LogoPx=2" as a fallback and pinned the brand mark at one
    size for good. Both the icon scale and the overall scale feed LogoPx, the
    resolver computed it correctly every time, and then the mark file replaced it
    on the next line of the load. Two settings looked broken and neither was.

    A fallback belongs in LuneSettings.inc, which is included first.
    #>
    $resolvedKeys = @{}
    foreach ($line in [System.IO.File]::ReadAllLines((Join-Path $SourceRes 'LuneResolved.inc'))) {
        if ($line -match '^([A-Za-z]\w*)=') { $resolvedKeys[$Matches[1]] = $true }
    }
    Assert-Lune 'the resolved file was generated and has keys to protect' ($resolvedKeys.Count -gt 20) `
        "got $($resolvedKeys.Count)"

    $laterIncludes = @()
    $pastResolved  = $false
    foreach ($line in [System.IO.File]::ReadAllLines((Join-Path $SkinRoot 'ClaudeLune.ini'))) {
        if ($line -notmatch '^@Include\d*=(.+)$') { continue }
        $rel = $Matches[1].Trim() -replace '^#@#', ''
        if ($rel -like '*LuneResolved.inc') { $pastResolved = $true; continue }
        if (-not $pastResolved) { continue }
        # The layout include is chosen by name at load time, so check all four.
        if ($rel -match '#Size#') {
            foreach ($size in @('Small', 'Normal', 'Wide', 'Large')) { $laterIncludes += ($rel -replace '#Size#', $size) }
        } else {
            $laterIncludes += $rel
        }
    }
    Assert-Lune 'every include after the resolved file was found' ($laterIncludes.Count -ge 3) `
        "got $($laterIncludes.Count)"

    $shadowed = @()
    foreach ($rel in $laterIncludes) {
        $path = Join-Path $SourceRes $rel
        if (-not (Test-Path -LiteralPath $path)) { $shadowed += "$rel is missing"; continue }
        <#
        Only [Variables] counts. A meter section has keys of its own - Text,
        Shape, Group - and "Text=5-hour limit" inside [SessionLabel] is a label,
        not a redefinition of the Text colour.
        #>
        $inVariables = $false
        foreach ($line in [System.IO.File]::ReadAllLines($path)) {
            $trimmed = $line.Trim()
            if ($trimmed -match '^\[(.+)\]$') { $inVariables = ($Matches[1] -eq 'Variables'); continue }
            if (-not $inVariables) { continue }
            if ($trimmed -match '^([A-Za-z]\w*)=' -and $resolvedKeys.ContainsKey($Matches[1])) {
                $shadowed += "$rel redefines $($Matches[1])"
            }
        }
    }
    Assert-Lune 'no later include redefines a key the resolver writes' ($shadowed.Count -eq 0) `
        (($shadowed | Select-Object -Unique) -join '; ')

    # ------------------------------------------------------------ consistency
    Start-Group 'The skin and the poller agree with each other'
    $poller = [System.IO.File]::ReadAllText((Join-Path $SourceRes 'Scripts\Update-LuneUsage.ps1'))
    $consumers = [System.IO.File]::ReadAllText((Join-Path $SkinRoot 'ClaudeLune.ini'))
    foreach ($layout in Get-ChildItem (Join-Path $SourceRes 'Layouts') -Filter '*.inc') {
        $consumers += [System.IO.File]::ReadAllText($layout.FullName)
    }

    <#
    Publishing a value nothing draws is not merely untidy: the reload is triggered
    by the published content differing from the last poll, so a key that changes
    and is drawn nowhere buys a reload that shows nothing new. One such key once
    reloaded the panel about once a second.
    #>
    $valuesBlock = $poller.Substring($poller.IndexOf('$values = [ordered]@{'), 3200)
    $collected = [regex]::Matches($valuesBlock, '(?m)^\s{8}(\w+)\s*=') | ForEach-Object { $_.Groups[1].Value }

    # The poller collects everything for usage.json, then filters out what the
    # panel does not draw before publishing. Both halves of that split have to
    # stay true, so both are checked.
    $excludedBlock = $poller.Substring($poller.IndexOf('$notDrawn = @('), 400)
    $excluded = [regex]::Matches($excludedBlock, "'(\w+)'") | ForEach-Object { $_.Groups[1].Value }

    $publishedOrphans = @($collected | Where-Object { $excluded -notcontains $_ -and $consumers -notmatch "#$_#" })
    Assert-Lune 'every published value is drawn by something' ($publishedOrphans.Count -eq 0) ("orphans: " + ($publishedOrphans -join ', '))

    # And nothing sits on the exclusion list that the panel actually needs - that
    # would blank a value on screen rather than merely save a reload.
    $wronglyExcluded = @($excluded | Where-Object { $consumers -match "#$_#" })
    Assert-Lune 'nothing the panel draws is excluded from publishing' ($wronglyExcluded.Count -eq 0) ($wronglyExcluded -join ', ')

    # A bang aimed at a meter or measure that does not exist fails silently.
    $meterTargets = [regex]::Matches($consumers, '!UpdateMeter (\w+)') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
    $missingMeters = @($meterTargets | Where-Object { $consumers -notmatch "\[$_\]" })
    Assert-Lune 'every meter a bang updates exists' ($missingMeters.Count -eq 0) ($missingMeters -join ', ')

    $measureTargets = [regex]::Matches($consumers, '!(?:CommandMeasure|UpdateMeasure) (\w+)') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
    $missingMeasures = @($measureTargets | Where-Object { $consumers -notmatch "\[$_\]" })
    Assert-Lune 'every measure a bang addresses exists' ($missingMeasures.Count -eq 0) ($missingMeasures -join ', ')

    # ==========================================================================
    Start-Group 'The token is found wherever Claude Code puts it'

    <#
    The panel spent seventeen days on a stale reading because it knew exactly one
    path to the token and Claude Code stopped writing there. These pin the two
    properties that make that a non-event: a token is recognised by what it looks
    like rather than where it sits, and a directory Claude Code does not use today
    is still searched.
    #>
    # Its own name: $Poller above holds this file's TEXT by now, and PowerShell
    # variable names do not distinguish case.
    $tokenPoller = Join-Path $SourceRes 'Scripts\Update-LuneUsage.ps1'

    . ([ScriptBlock]::Create((Import-LuneFunction -Path $tokenPoller -Name 'Get-LuneCleanToken')))
    . ([ScriptBlock]::Create((Import-LuneFunction -Path $tokenPoller -Name 'Test-LuneToken')))
    . ([ScriptBlock]::Create((Import-LuneFunction -Path $tokenPoller -Name 'Read-LuneTokenDocument')))
    . ([ScriptBlock]::Create((Import-LuneFunction -Path $tokenPoller -Name 'Get-LuneProperty')))

    $shapes = @(
        @{ why = 'the shape shipped today'
           json = '{"claudeAiOauth":{"accessToken":"sk-ant-oat01-AAAAAAAAAAAAAAAAAAAA","expiresAt":9999999999999}}' }
        @{ why = 'the wrapper renamed'
           json = '{"session":{"access_token":"sk-ant-oat01-BBBBBBBBBBBBBBBBBBBB"}}' }
        @{ why = 'a list of accounts'
           json = '{"accounts":[{"auth":{"bearer":"sk-ant-oat01-CCCCCCCCCCCCCCCCCCCC"}}]}' }
        @{ why = 'a field name nobody has used yet'
           json = '{"whatever_they_call_it_next":"sk-ant-oat01-DDDDDDDDDDDDDDDDDDDD"}' }
    )
    foreach ($shape in $shapes) {
        $found = Read-LuneTokenDocument ($shape.json | ConvertFrom-Json)
        Assert-Lune "token read from $($shape.why)" ($null -ne $found -and (Test-LuneToken $found.Token))
    }

    # Signed out is not the same as relocated, and must not read as a token.
    Assert-Lune 'a blank token is not a token' `
        ($null -eq (Read-LuneTokenDocument ('{"claudeAiOauth":{"accessToken":"","expiresAt":0}}' | ConvertFrom-Json)))

    # Every application on the machine has an "accessToken" somewhere. Only
    # Anthropic's prefix counts, or the sweep adopts the first one it trips over.
    Assert-Lune 'another application''s token is ignored' `
        ($null -eq (Read-LuneTokenDocument ('{"accessToken":"ghp_000000000000000000000000000000"}' | ConvertFrom-Json)))

    $expiry = Read-LuneTokenDocument ('{"a":{"token":"sk-ant-oat01-EEEEEEEEEEEEEEEEEEEE","expires_at":123456}}' | ConvertFrom-Json)
    Assert-Lune 'the expiry beside a token is picked up' ($expiry.Expiry -eq 123456)

    <#
    A token copied out of a terminal arrives with whitespace on it. The strict
    prefix check refused those in silence, and a machine whose environment
    variable was set correctly apart from one leading space reported itself
    signed out.
    #>
    $clean = 'sk-ant-oat01-GGGGGGGGGGGGGGGGGGGG'
    foreach ($messy in @(" $clean", "$clean ", "`t$clean`r`n", """$clean""", "'$clean'", " ""$clean"" ")) {
        Assert-Lune "a token with stray characters is still read" ((Get-LuneCleanToken $messy) -eq $clean)
    }
    Assert-Lune 'whitespace alone is not a token' ($null -eq (Get-LuneCleanToken '   '))
    Assert-Lune 'the cleaned token is what gets returned' `
        ((Read-LuneTokenDocument ('{"t":" ' + $clean + ' "}' | ConvertFrom-Json)).Token -eq $clean)

    # The sweep, against a directory Claude Code does not write to today.
    . ([ScriptBlock]::Create((Import-LuneFunction -Path $tokenPoller -Name 'Get-LuneTokenRoots')))
    . ([ScriptBlock]::Create((Import-LuneFunction -Path $tokenPoller -Name 'Read-LuneJson')))
    . ([ScriptBlock]::Create((Import-LuneFunction -Path $tokenPoller -Name 'Find-LuneTokenFile')))

    $planted = Join-Path $env:LOCALAPPDATA 'claude-code'
    $existed = Test-Path -LiteralPath $planted
    $plantedFile = Join-Path $planted 'lune-selftest.json'
    try {
        New-Item -ItemType Directory -Force -Path $planted | Out-Null
        '{"session":{"access_token":"sk-ant-oat01-FFFFFFFFFFFFFFFFFFFF"}}' |
            Set-Content -LiteralPath $plantedFile -Encoding ASCII
        <#
        The sweep returns the first root that answers, and the roots are ordered.
        Asserting it returns THIS file assumed no other root held a token, which
        stopped being true the moment the machine running the tests had a real
        signed-in session. What matters is that a sweep finds a readable token,
        and that a directory Claude Code does not use today is reachable at all.
        #>
        $swept = Find-LuneTokenFile
        Assert-Lune 'a sweep finds a readable token file' `
            ($swept -and (Read-LuneTokenDocument (Read-LuneJson $swept))) "got '$swept'"
        Assert-Lune 'a relocated directory is inside the search' `
            ((Get-LuneTokenRoots) -contains $planted)
    } finally {
        Remove-Item -LiteralPath $plantedFile -Force -ErrorAction SilentlyContinue
        if (-not $existed) { Remove-Item -LiteralPath $planted -Recurse -Force -ErrorAction SilentlyContinue }
    }

    # The advice printed beside a stale reading has to match the reason, or it
    # sends people to do the one thing that cannot help.
    $tokenPollerText = [System.IO.File]::ReadAllText($tokenPoller)
    Assert-Lune 'a signed-out panel says to sign in' ($tokenPollerText -match 'claude /login')
    Assert-Lune 'stale advice is chosen by auth state' ($tokenPollerText -match 'LuneAuthState')

    <#
    Publishing ends in a !Refresh, the refresh reloads the skin, and the reload
    kills this process - so whatever runs after the publish call runs only on the
    polls that happen not to change anything. usage.json was written there and
    spent days behind the panel it claims to record.
    #>
    $publishAt = $tokenPollerText.LastIndexOf('Publish-LuneState -Values $flat')
    $exportAt  = $tokenPollerText.LastIndexOf('$LuneExportPath -Force')
    Assert-Lune 'usage.json is written before the panel is published' `
        ($exportAt -gt 0 -and $publishAt -gt $exportAt) "export at $exportAt, publish at $publishAt"

    # ==========================================================================
    Start-Group 'No drawn text can run off the card'

    <#
    The geometry sweep varies scale factors and checks the resulting numbers. It
    never varies the LENGTH of what gets drawn, so a String meter with no W passed
    every one of its 320 configurations and still spilled off the panel the moment
    a value got longer than the designer assumed. That is how "signed out - run
    claude /login" ended up hanging over the edge of the card.

    Any meter drawing a value the poller supplies has to be bounded, because the
    poller's values are not fixed width: the account name is whatever the account
    is called, and status text changes with the state.
    #>
    foreach ($layout in Get-ChildItem (Join-Path $SourceRes 'Layouts') -Filter '*.inc') {
        $text = [System.IO.File]::ReadAllText($layout.FullName)

        # Split into meter blocks, keep the ones that draw a string.
        $blocks = [regex]::Split($text, '(?m)^(?=\[)') | Where-Object { $_ -match '(?m)^Meter=String' }
        foreach ($block in $blocks) {
            $name = ([regex]::Match($block, '^\[(\w+)\]')).Groups[1].Value
            if (-not $name) { continue }

            # Only the Text= line matters; a variable inside ToolTipText cannot
            # overflow anything.
            $drawn = [regex]::Match($block, '(?m)^Text=(.*)$').Groups[1].Value
            if ($drawn -notmatch '#(AccountName|LastUpdated|Status|ErrorText|ExtraModel|ThirdLabel|AccountPlan)#') { continue }

            # W and H both, not just W: ClipString=1 needs the pair, and setting
            # only W leaves the clip undefined rather than bounded.
            $bounded = ($block -match '(?m)^W=') -and ($block -match '(?m)^H=') -and
                       ($block -match '(?m)^ClipString=1')
            Assert-Lune "$($layout.BaseName)/$name is bounded and clipped" $bounded $drawn
        }
    }

    # And the value the poller puts there stays short enough to be worth clipping.
    Assert-Lune 'the signed-out footer value is two words, not a sentence' `
        ($tokenPollerText -match "'signed out'" -and $tokenPollerText -notmatch "'signed out - run claude /login'")

    # ==========================================================================
    Start-Group 'Signing in is reachable from the panel'

    <#
    Signing in is the one thing the panel cannot do for itself, and on a machine
    with no local history it is the only way to show anything at all. Leaving that
    as prose in a README made it the user's problem to go and find.
    #>
    $iniText = [System.IO.File]::ReadAllText((Join-Path $SkinRoot 'ClaudeLune.ini'))
    Assert-Lune 'the context menu offers signing in' ($iniText -match 'Sign in to Claude Code')
    Assert-Lune 'the sign-in measure exists' ($iniText -match '(?m)^\[MeasureLuneLogin\]')
    Assert-Lune 'the sign-in menu item is wired to it' ($iniText -match 'MeasureLuneLogin "Run"')
    # /k, not /c: the window has to stay up for the browser round trip.
    Assert-Lune 'the sign-in terminal is detached so it outlives the measure' ($iniText -match 'start "Claude Code')
    # auth login is one command; the TUI route made the user type /login themselves.
    Assert-Lune 'sign-in uses the auth login command' ($iniText -match 'auth login')

    # The history file is looked for, not assumed - this machine has no
    # %APPDATA%\Claude at all.
    Assert-Lune 'the usage history is searched for in more than one place' `
        ($tokenPollerText -match 'function Get-LuneHistoryPath')
    Assert-Lune 'the history search is what the reader uses' `
        ($tokenPollerText -match 'Read-LuneJson \(Get-LuneHistoryPath\)')

    # A replayed API response must not outrank a newer local reading.
    Assert-Lune 'the fresher of the two sources wins' `
        ($tokenPollerText -match 'Local history is newer than the replayed response')
    # And the offline rows are actually built, rather than left at zero.
    Assert-Lune 'offline mode fills the session and weekly rows' `
        ($tokenPollerText -match "New-LuneLimitRow -Samples \`$samples -Field 'fh'" -and
         $tokenPollerText -match "New-LuneLimitRow -Samples \`$samples -Field 'sd'")
    <#
    A refused credential must not end the attempt. An environment variable
    outranks the stored session, and when it holds a setup-token the endpoint
    answers 403 - so the panel showed nothing while a working session sat on the
    same disk. Only 401 and 403 fall through: a 429 says nothing about the
    credential and must not burn the next one.
    #>
    Assert-Lune 'a refused credential falls through to the next' `
        ($tokenPollerText -match '\$attempts \+= @\{ Token = \$stored\.Token')
    Assert-Lune 'only 401 and 403 fall through' `
        ($tokenPollerText -match "if \(\`$_\.Exception\.Message -notmatch '\\b40\[13\]\\b'\) \{ throw \}")
    Assert-Lune 'the stored session can be asked for on its own' `
        ($tokenPollerText -match '\[switch\]\$SkipEnvironment')
    <#
    Signing in is what someone does BECAUSE the panel is stuck, and stuck means it
    has been refused enough to be waiting a minute between attempts. If the wait
    survives the sign-in, /login looks like it did nothing.
    #>
    Assert-Lune 'a new sign-in discards the current backoff' `
        ($tokenPollerText -match 'Credentials changed since the last poll')
    Assert-Lune 'and discards the recorded auth verdict with it' `
        ($tokenPollerText -match "authState = ''")
    # ==========================================================================
    Start-Group 'Drawn text fits the space it has'

    <#
    The geometry sweep checks resolved numbers and never renders anything, so a
    label 40px too wide for its row passed all 320 of its configurations. This
    measures the actual strings with the actual font metrics.

    It found 116 collisions across 14 meters on the first run - worst 396px -
    because FontScale and WidthScale move independently and 2.0 type in a 0.5
    panel cannot fit by construction. Fixed by capping type against the width it
    has, and by bounding every drawn string so it truncates rather than overlaps.
    #>
    Add-Type -AssemblyName System.Drawing
    $fitBmp = New-Object System.Drawing.Bitmap 1, 1
    $fitGfx = [System.Drawing.Graphics]::FromImage($fitBmp)

    # Worst-case-but-real values for everything the poller publishes.
    $fitValues = @{
        FiveHourShown = '100'; SevenDayShown = '100'; ScopedShown = '100'
        UsageWord = 'used'; ThirdLabel = 'Claude Sonnet 4.5'
        FiveHourCountdown = '4h 36m'; SevenDayCountdown = '6d 14h'; ScopedCountdown = '6d 14h'
        AccountPlan = 'Max 20x'; AccountName = 'a.very.long.account.name'
        TokensToday = '1.23M'; LastUpdated = '11:59pm (7d 17h ago)'
        ScopedValue = '100% used'; ExtraModel = 'Claude Sonnet 4.5'; SparkRange = '100% in 24h'
    }

    $fitRes = New-LuneSandbox; $sandboxes += (Split-Path $fitRes -Parent)
    $fitFonts  = if ($Full) { @('Segoe UI', 'Consolas', 'Comic Sans MS') } else { @('Segoe UI', 'Consolas') }
    $fitScales = if ($Full) { @('0.5', '1.0', '1.5', '2.0') } else { @('1.0', '2.0') }

    $fitProblems = @()
    $fitChecked  = 0

    foreach ($fitSize in @('Small', 'Normal', 'Wide', 'Large')) {
        $fitLayout = [System.IO.File]::ReadAllText((Join-Path $fitRes ('Layouts\Lune' + $fitSize + '.inc')))
        $fitMeters = @()
        foreach ($blk in [regex]::Split($fitLayout, '(?m)^(?=\[)')) {
            if ($blk -notmatch '(?m)^Meter=String') { continue }
            $nm = ([regex]::Match($blk, '^\[(\w+)\]')).Groups[1].Value
            if (-not $nm) { continue }
            $fitMeters += [PSCustomObject]@{
                Name = $nm
                Text = ([regex]::Match($blk, '(?m)^Text=(.*)$')).Groups[1].Value
                Size = ([regex]::Match($blk, '(?m)^FontSize=#(\w+)#')).Groups[1].Value
                Bold = ($blk -match '(?m)^FontWeight=[6-9]')
                Bound = ([regex]::Match($blk, '(?m)^W=(.*)$')).Groups[1].Value
                Clip  = ($blk -match '(?m)^ClipString=1')
            }
        }

        foreach ($fitFont in $fitFonts) {
            foreach ($fitScale in $fitScales) {
                $geo = Get-LuneGeometry -Res $fitRes -Size $fitSize -Settings @{
                    FontScale = $fitScale; WidthScale = '0.5'; FontFace = $fitFont
                }
                foreach ($m in $fitMeters) {
                    if (-not $m.Text -or -not $m.Size -or -not $geo.ContainsKey($m.Size)) { continue }

                    <#
                    A bound is only a fix if it is smaller than the row. Skipping
                    bounded meters entirely made this check measure nothing at all
                    once everything had been bounded - 233 tests passing on "0
                    measured". So the bound is evaluated and judged too.
                    #>
                    $bound = $null
                    if ($m.Bound -and $m.Clip) {
                        $expr = $m.Bound -replace '#BarW#', ([int]$geo.BarW) -replace '#W#', ([int]$geo.W)
                        try { $bound = [int][double](Invoke-Expression $expr) } catch { $bound = $null }
                        if ($null -eq $bound -or $bound -gt [int]$geo.BarW) {
                            $fitProblems += ('{0}/{1} bound {2} exceeds row {3}' -f $fitSize, $m.Name, $bound, [int]$geo.BarW)
                        }
                    }

                    $txt = $m.Text
                    foreach ($k in $fitValues.Keys) { $txt = $txt -replace ('#' + $k + '#'), $fitValues[$k] }
                    $txt = $txt -replace '#\w+#', ''
                    if (-not $txt) { continue }

                    $style = if ($m.Bold) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }
                    $font = $null
                    try { $font = New-Object System.Drawing.Font($fitFont, [float]$geo[$m.Size], $style) }
                    catch { $font = New-Object System.Drawing.Font('Segoe UI', [float]$geo[$m.Size], $style) }
                    $w = [int][Math]::Ceiling($fitGfx.MeasureString($txt, $font).Width)
                    $font.Dispose()
                    $fitChecked++

                    # What actually lands on the panel: clipped at its bound, or
                    # its full width when nothing bounds it.
                    $drawn = if ($null -ne $bound) { [Math]::Min($w, $bound) } else { $w }
                    if ($drawn -gt [int]$geo.BarW) {
                        $fitProblems += ('{0}/{1} {2} fs={3} {4}px over {5}' -f
                            $fitSize, $m.Name, $fitFont, $fitScale, ($drawn - [int]$geo.BarW), [int]$geo.BarW)
                    }
                }
            }
        }
    }
    $fitGfx.Dispose(); $fitBmp.Dispose()

    <#
    A label and the value beside it share one row. Each can fit on its own and
    still collide, which is what 59 of the original 116 findings were.
    #>
    foreach ($fitSize in @('Small', 'Normal', 'Wide', 'Large')) {
        $lay = [System.IO.File]::ReadAllText((Join-Path $fitRes ('Layouts\Lune' + $fitSize + '.inc')))
        $geo = Get-LuneGeometry -Res $fitRes -Size $fitSize -Settings @{
            FontScale = '2.0'; WidthScale = '0.5'; FontFace = 'Consolas'
        }
        foreach ($pair in @(@('SessionLabel','SessionValue'), @('WeeklyLabel','WeeklyValue'), @('ScopedLabel','ScopedValue'))) {
            $sum = 0; $seen = 0
            foreach ($nm in $pair) {
                $blk = [regex]::Match($lay, '(?s)\[' + $nm + '\].*?(?=\r?\n\[)').Value
                if (-not $blk) { continue }
                $bw = ([regex]::Match($blk, '(?m)^W=(.*)$')).Groups[1].Value
                if (-not $bw) { continue }
                $seen++
                $expr = $bw -replace '#BarW#', ([int]$geo.BarW) -replace '#W#', ([int]$geo.W)
                try { $sum += [int][double](Invoke-Expression $expr) } catch { }
            }
            if ($seen -eq 2) {
                $fitChecked++
                if ($sum -gt [int]$geo.BarW) {
                    $fitProblems += ('{0}/{1}+{2} bounds total {3} over row {4}' -f $fitSize, $pair[0], $pair[1], $sum, [int]$geo.BarW)
                }
            }
        }
    }

    # A check that measures nothing passes for the wrong reason. This one did
    # exactly that once every meter had been bounded: 0 measured, green.
    Assert-Lune 'the text check actually measured something' ($fitChecked -gt 100) "measured $fitChecked"
    Assert-Lune "no drawn string overflows its row ($fitChecked measured)" `
        ($fitProblems.Count -eq 0) (($fitProblems | Select-Object -First 4) -join ' | ')

    # Type is capped against the width it has, not only its own range.
    Assert-Lune 'type is capped by the width available to it' `
        ($tokenPollerText -match '\$labelBudget = switch')
    # A gap in the context menu numbering silently truncates the menu.
    $ini = [System.IO.File]::ReadAllText((Join-Path $SkinRoot 'ClaudeLune.ini'))
    $menu = @([regex]::Matches($ini, '(?m)^ContextTitle(\d*)=') | ForEach-Object {
        if ($_.Groups[1].Value) { [int]$_.Groups[1].Value } else { 1 } } | Sort-Object)
    Assert-Lune 'context menu numbering has no gaps' `
        ($menu.Count -gt 0 -and -not (Compare-Object $menu (1..$menu.Count))) "got $($menu -join ',')"
}
<#
A suite that stops early must not look like a suite that passed.

An exception thrown between groups skipped the summary and left the exit code at
zero, so a run that got two thirds of the way through and died reported success -
which is how a broken harness reaches CI green.
#>
catch {
    Write-Host ''
    Write-Host "SUITE ABORTED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace
    Write-Host "$($script:Passed) passed before the abort" -ForegroundColor Red
    foreach ($sandbox in $sandboxes) {
        Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue
    }
    exit 1
}
finally {
    foreach ($sandbox in $sandboxes) {
        Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ''
if ($script:Failed -eq 0) {
    Write-Host "$($script:Passed) passed, 0 failed" -ForegroundColor Green
    exit 0
} else {
    Write-Host "$($script:Passed) passed, $($script:Failed) FAILED" -ForegroundColor Red
    exit 1
}
