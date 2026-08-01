<#
.SYNOPSIS
    Stress test for ClaudeLune: hostile inputs, concurrency, and long runs.

.DESCRIPTION
    ClaudeLune by Lunez (luneswan).

    Invoke-LuneTests.ps1 checks that the parts behave when they are used
    correctly. This checks what happens when they are not: a history file that is
    truncated, empty, corrupt or enormous; timestamps from the future; two
    pollers writing at once; hundreds of consecutive runs; every size and theme
    switched in a loop.

    Every failure mode listed here has happened to this project at least once.

    Nothing here needs Rainmeter running or a network connection. It works on
    copies in the temp directory and never touches the installed skin, the live
    settings, or the real history store.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tests\Invoke-LuneStress.ps1

.EXAMPLE
    # Longer soak: more poll cycles and more samples.
    powershell -NoProfile -ExecutionPolicy Bypass -File tests\Invoke-LuneStress.ps1 -Cycles 500

.NOTES
    Copyright (c) Lunez (luneswan). MIT licence - see LICENSE.
#>

[CmdletBinding()]
param(
    # Poll cycles for the soak, and samples for the large-store test.
    [ValidateRange(10, 5000)]
    [int]$Cycles = 200
)

$ErrorActionPreference = 'Stop'

$RepoRoot  = Split-Path $PSScriptRoot -Parent
$SourceRes = Join-Path $RepoRoot 'Skins\ClaudeLune\@Resources'
$Poller    = Join-Path $SourceRes 'Scripts\Update-LuneUsage.ps1'

$script:Passed = 0
$script:Failed = 0

function Start-Group { param([string]$Name) Write-Host ''; Write-Host $Name -ForegroundColor Cyan }

function Assert-Lune {
    param([string]$What, [bool]$Condition, [string]$Detail = '')
    if ($Condition) {
        $script:Passed++
        Write-Host "  PASS  $What" -ForegroundColor DarkGray
    } else {
        $script:Failed++
        $line = "  FAIL  $What"
        if ($Detail) { $line += "  --  $Detail" }
        Write-Host $line -ForegroundColor Red
    }
}

# Pulls one function out of a script by name, brace-counting to its end, and
# returns the text for the caller to run at its own scope. Returning the text
# rather than defining it here matters: Invoke-Expression inside a function
# defines into that function's scope, and the definition vanishes on return.
function Import-LuneFunction {
    param([string]$Path, [string]$Name)

    $lines = Get-Content -LiteralPath $Path
    $start = ($lines | Select-String -Pattern "^function $Name\b" | Select-Object -First 1).LineNumber - 1
    if ($start -lt 0) { throw "Could not find function $Name in $Path." }

    $depth = 0
    for ($i = $start; $i -lt $lines.Count; $i++) {
        $depth += ([regex]::Matches($lines[$i], '\{')).Count - ([regex]::Matches($lines[$i], '\}')).Count
        if ($i -gt $start -and $depth -le 0) { return ($lines[$start..$i] -join "`n") }
    }
    throw "Function $Name in $Path never closes."
}

function New-LuneStoreFile {
    param([string]$Path, [string]$Content)
    [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false)))
}

function Get-LuneStoreCount {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return -1 }
    $text = [System.IO.File]::ReadAllText($Path)
    if ([string]::IsNullOrWhiteSpace($text)) { return -1 }
    try { return @(($text | ConvertFrom-Json).samples).Count } catch { return -1 }
}

$work = Join-Path ([System.IO.Path]::GetTempPath()) ("LuneStress_" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $work -Force | Out-Null

try {
    Invoke-Expression (Import-LuneFunction -Path $Poller -Name 'Read-LuneJson')
    Invoke-Expression (Import-LuneFunction -Path $Poller -Name 'Write-LuneJsonFile')
    Invoke-Expression (Import-LuneFunction -Path $Poller -Name 'Update-LuneWeeklyStore')
    Invoke-Expression (Import-LuneFunction -Path $Poller -Name 'Add-LuneWeeklySample')
    Invoke-Expression (Import-LuneFunction -Path $Poller -Name 'Get-LuneSpendRate')

    $store = Join-Path $work 'weekly-history.json'
    $hour  = 3600000
    $now   = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()

    # ------------------------------------------------------ hostile store files
    Start-Group 'A damaged history file never makes things worse'

    $good = @(0..99 | ForEach-Object {
        [PSCustomObject]@{ t = ($now - (100 - $_) * 300000); w = [int]($_ / 4) }
    })
    $goodJson = ([PSCustomObject]@{ samples = $good } | ConvertTo-Json -Depth 4 -Compress)

    # An empty file is the shape a mid-rewrite read returns, and the one that once
    # cost a week of readings: it parsed to nothing without throwing, the caller
    # read that as "no history", and wrote a single sample over the lot.
    New-LuneStoreFile $store ''
    $result = Add-LuneWeeklySample -Percent 25 -Path $store
    Assert-Lune 'an empty store records nothing this cycle' (@($result).Count -eq 0) "got $(@($result).Count)"

    New-LuneStoreFile $store '{"samples":[{"t":1,'
    $result = Add-LuneWeeklySample -Percent 25 -Path $store
    Assert-Lune 'a truncated store records nothing this cycle' (@($result).Count -eq 0) "got $(@($result).Count)"
    Assert-Lune 'a truncated store is left on disk untouched' `
        ([System.IO.File]::ReadAllText($store) -eq '{"samples":[{"t":1,')

    New-LuneStoreFile $store 'not json at all'
    $result = Add-LuneWeeklySample -Percent 25 -Path $store
    Assert-Lune 'a store full of junk records nothing this cycle' (@($result).Count -eq 0)

    New-LuneStoreFile $store '{"samples":[]}'
    $result = Add-LuneWeeklySample -Percent 25 -Path $store
    Assert-Lune 'an empty sample list is a real answer and takes the reading' (@($result).Count -eq 1)

    New-LuneStoreFile $store '{"samples":[{"w":50},{"t":null,"w":50}]}'
    $result = Add-LuneWeeklySample -Percent 25 -Path $store
    Assert-Lune 'samples with no timestamp are dropped, not carried' (@($result).Count -eq 1) "got $(@($result).Count)"

    New-LuneStoreFile $store $goodJson
    $result = Add-LuneWeeklySample -Percent 99 -Path $store
    Assert-Lune 'a healthy store grows rather than being replaced' (@($result).Count -eq 101) "got $(@($result).Count)"
    Assert-Lune 'and what is written back parses' ((Get-LuneStoreCount $store) -eq 101)

    # ------------------------------------------------------------ hostile times
    Start-Group 'Clocks that lie do not break the chart'

    $future = Get-LuneSpendRate -Samples @(
        [PSCustomObject]@{ t = $now + (48 * $hour); w = 10 },
        [PSCustomObject]@{ t = $now + (49 * $hour); w = 30 }
    ) -Hours 24 -Points 24
    Assert-Lune 'timestamps in the future still produce 24 columns' ($future.points.Count -eq 24)
    Assert-Lune 'and none of them are out of range' `
        (@($future.points | Where-Object { $_ -lt 0 -or $_ -gt 100 }).Count -eq 0)

    $ancient = Get-LuneSpendRate -Samples @(
        [PSCustomObject]@{ t = 0; w = 10 },
        [PSCustomObject]@{ t = 1000; w = 20 }
    ) -Hours 24 -Points 24
    Assert-Lune 'epoch-zero timestamps do not throw' ($ancient.points.Count -eq 24)

    $identical = Get-LuneSpendRate -Samples @(
        [PSCustomObject]@{ t = $now; w = 40 },
        [PSCustomObject]@{ t = $now; w = 40 },
        [PSCustomObject]@{ t = $now; w = 40 }
    ) -Hours 24 -Points 24
    Assert-Lune 'samples sharing one timestamp do not throw' ($identical.points.Count -eq 24)

    $backwards = Get-LuneSpendRate -Samples @(
        [PSCustomObject]@{ t = $now;             w = 60 },
        [PSCustomObject]@{ t = $now - $hour;     w = 40 },
        [PSCustomObject]@{ t = $now - 2 * $hour; w = 20 }
    ) -Hours 24 -Points 24
    Assert-Lune 'a store written out of order is sorted before use' ($backwards.total -eq 40) "got $($backwards.total)"

    $silly = Get-LuneSpendRate -Samples @(
        [PSCustomObject]@{ t = $now - $hour; w = -50 },
        [PSCustomObject]@{ t = $now;         w = 5000 }
    ) -Hours 24 -Points 24
    Assert-Lune 'percentages outside 0-100 cannot push a column off the chart' `
        (@($silly.points | Where-Object { $_ -lt 0 -or $_ -gt 100 }).Count -eq 0)

    # -------------------------------------------------------------- large store
    Start-Group 'A large history stays fast and stays pruned'

    $many = @(0..($Cycles - 1) | ForEach-Object {
        [PSCustomObject]@{ t = ($now - (($Cycles - $_) * 60000)); w = ($_ % 100) }
    })

    <#
    A generous ceiling, on purpose. This is here to catch an accidental O(n^2) -
    the kind of change that turns a second into a minute - not to measure the
    machine. A tight bound on a shared CI runner fails for reasons that have
    nothing to do with the code, and a suite that cries wolf gets ignored.
    #>
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $rate = Get-LuneSpendRate -Samples $many -Hours 24 -Points 24
    $watch.Stop()
    Assert-Lune "$Cycles samples chart without pathological slowness" ($watch.ElapsedMilliseconds -lt 20000) `
        "took $($watch.ElapsedMilliseconds)ms"
    Assert-Lune 'and still produce 24 columns' ($rate.points.Count -eq 24)

    # Eight days is the retention window. Anything older must not accumulate.
    $stale = @(
        [PSCustomObject]@{ t = ($now - (30 * 86400000)); w = 5 },
        [PSCustomObject]@{ t = ($now - (20 * 86400000)); w = 6 },
        [PSCustomObject]@{ t = ($now - (9 * 86400000));  w = 7 },
        [PSCustomObject]@{ t = ($now - 600000);          w = 8 }
    )
    New-LuneStoreFile $store ([PSCustomObject]@{ samples = $stale } | ConvertTo-Json -Depth 4 -Compress)
    $pruned = Add-LuneWeeklySample -Percent 9 -Path $store
    Assert-Lune 'samples older than the retention window are pruned' (@($pruned).Count -eq 2) `
        "got $(@($pruned).Count)"

    # -------------------------------------------------------------- concurrency
    Start-Group 'Two pollers at once do not destroy the store'

    <#
    The scheduled tick and the poll a refresh starts can overlap, and one can
    catch the file while the other is rewriting it. This runs eight writers at
    once against one store, then checks the store is still readable and has not
    collapsed to a single sample, which is what used to happen.
    #>
    New-LuneStoreFile $store $goodJson
    $jobs = 1..8 | ForEach-Object {
        Start-Job -ScriptBlock {
            param($PollerPath, $StorePath, $Percent)
            $lines = Get-Content -LiteralPath $PollerPath
            foreach ($name in @('Read-LuneJson', 'Write-LuneJsonFile', 'Update-LuneWeeklyStore', 'Add-LuneWeeklySample')) {
                $start = ($lines | Select-String -Pattern "^function $name\b" | Select-Object -First 1).LineNumber - 1
                $depth = 0
                for ($i = $start; $i -lt $lines.Count; $i++) {
                    $depth += ([regex]::Matches($lines[$i], '\{')).Count - ([regex]::Matches($lines[$i], '\}')).Count
                    if ($i -gt $start -and $depth -le 0) { Invoke-Expression ($lines[$start..$i] -join "`n"); break }
                }
            }
            1..12 | ForEach-Object { Add-LuneWeeklySample -Percent $Percent -Path $StorePath | Out-Null }
        } -ArgumentList $Poller, $store, ($_ * 7)
    }
    $jobs | Wait-Job -Timeout 180 | Out-Null
    $jobs | Remove-Job -Force

    $surviving = Get-LuneStoreCount $store
    Assert-Lune 'the store is still valid JSON after concurrent writers' ($surviving -ge 0) 'unreadable'
    Assert-Lune 'and was not collapsed to a handful of samples' ($surviving -ge 100) "got $surviving"

    # ---------------------------------------------------------------- long soak
    Start-Group "A long run stays stable ($Cycles cycles)"

    New-LuneStoreFile $store $goodJson
    $errors = 0
    for ($i = 0; $i -lt $Cycles; $i++) {
        try {
            Add-LuneWeeklySample -Percent ($i % 100) -Path $store | Out-Null
            $rate = Get-LuneSpendRate -Samples (Read-LuneJson $store).samples -Hours 24 -Points 24
            if ($rate.points.Count -ne 24) { $errors++ }
            if (@($rate.points | Where-Object { $_ -lt 0 -or $_ -gt 100 }).Count -gt 0) { $errors++ }
        } catch { $errors++ }
    }
    Assert-Lune 'no cycle threw or produced an impossible column' ($errors -eq 0) "$errors bad cycles"
    Assert-Lune 'the store is still readable at the end' ((Get-LuneStoreCount $store) -gt 0)

    # A sample within five minutes of the last replaces it rather than adding to
    # it, so a fast poll cannot make the file grow without bound.
    $finalCount = Get-LuneStoreCount $store
    Assert-Lune "$Cycles cycles did not inflate the store" ($finalCount -lt ($Cycles + 200)) `
        "$finalCount samples on file"

    # ------------------------------------------------------ every size and theme
    Start-Group 'Every size and theme resolves, repeatedly'

    <#
    Switching size and theme in a loop is what a person actually does with a new
    skin, and it is how the panel was found collapsing to nothing: the layout
    changed while the resolved geometry still described the previous size, so the
    height could not be computed and the window measured zero by zero.
    #>
    $skinCopy = Join-Path $work 'Skin'
    Copy-Item (Join-Path $RepoRoot 'Skins\ClaudeLune') $skinCopy -Recurse -Force
    $copyRes    = Join-Path $skinCopy '@Resources'
    $copyPoller = Join-Path $copyRes 'Scripts\Update-LuneUsage.ps1'
    $copyCfg    = Join-Path $copyRes 'LuneSettings.inc'
    $copyOut    = Join-Path $copyRes 'LuneResolved.inc'

    $required = @('W', 'Pad', 'BarW', 'BarH', 'RowH', 'BodyY', 'HeadY', 'CapH', 'GapS', 'GapM',
                  'GapL', 'PadB', 'TrendH', 'TitleFS', 'LabelFS', 'SmallFS', 'Bg', 'Accent',
                  'AccentSoft', 'AccentGhost', 'Track', 'Stroke')

    function Read-LuneResolved {
        param([string]$Path)
        $map = @{}
        foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
            if ($line -match '^([A-Za-z]\w*)=(.*)$') { $map[$Matches[1]] = $Matches[2] }
        }
        return $map
    }

    $themes  = @('Dark', 'Amoled', 'Glass', 'Light', 'Clay', 'Matrix', 'iOS')
    $layouts = @('Small', 'Normal', 'Wide', 'Large')
    $bad = @()
    foreach ($size in $layouts) {
        foreach ($theme in $themes) {
            $text = [System.IO.File]::ReadAllText($copyCfg)
            $text = $text -replace '(?m)^Size=.*$', "Size=$size"
            $text = $text -replace '(?m)^Theme=.*$', "Theme=$theme"
            [System.IO.File]::WriteAllText($copyCfg, $text, (New-Object System.Text.UTF8Encoding($false)))

            & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
                -File $copyPoller -ResolveOnly -NoRefresh | Out-Null
            if ($LASTEXITCODE -ne 0) { $bad += "$size/$theme exit $LASTEXITCODE"; continue }

            $resolved = Read-LuneResolved $copyOut
            $missing = @($required | Where-Object { -not $resolved.ContainsKey($_) -or $resolved[$_] -eq '' })
            if ($missing.Count -gt 0) { $bad += "$size/$theme missing $($missing -join ',')" }
            if ($resolved['LayoutName'] -ne $size) { $bad += "$size/$theme resolved as $($resolved['LayoutName'])" }
        }
    }
    Assert-Lune 'all 28 size and theme combinations resolve completely' ($bad.Count -eq 0) ($bad -join '; ')

    # ------------------------------------------------------------- odd settings
    Start-Group 'A settings file edited badly still produces a usable panel'

    $nonsense = @{
        'UserScale'    = 'banana'
        'WidthScale'   = '-4'
        'HeightScale'  = '99999'
        'FontScale'    = ''
        'PadScale'     = '0'
        'RowScale'     = '1e400'
        'BarScale'     = '..'
        'IconScale'    = '2,5'
        'CornerRadius' = '-30'
        'BorderWidth'  = 'thick'
        'Opacity'      = '900'
        'FontFace'     = 'ThisFontIsNotInstalledAnywhere'
        'CustomAccent' = '999,0,0'
        'CustomBg'     = 'rgb(1,2,3)'
    }
    $text = [System.IO.File]::ReadAllText($copyCfg)
    foreach ($key in $nonsense.Keys) {
        if ($text -match "(?m)^$key=") { $text = $text -replace "(?m)^$key=.*$", "$key=$($nonsense[$key])" }
        else { $text += "`r`n$key=$($nonsense[$key])" }
    }
    [System.IO.File]::WriteAllText($copyCfg, $text, (New-Object System.Text.UTF8Encoding($false)))

    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
        -File $copyPoller -ResolveOnly -NoRefresh | Out-Null
    Assert-Lune 'a settings file full of nonsense does not fail the poller' ($LASTEXITCODE -eq 0) `
        "exit $LASTEXITCODE"

    $resolved = Read-LuneResolved $copyOut
    $stillMissing = @($required | Where-Object { -not $resolved.ContainsKey($_) -or $resolved[$_] -eq '' })
    Assert-Lune 'and every geometry key is still present' ($stillMissing.Count -eq 0) ($stillMissing -join ',')
    Assert-Lune 'the panel keeps a usable width' ([int]$resolved['W'] -ge 120 -and [int]$resolved['W'] -le 2000) `
        "W=$($resolved['W'])"
    Assert-Lune 'the bar keeps a usable length' ([int]$resolved['BarW'] -ge 20) "BarW=$($resolved['BarW'])"
    Assert-Lune 'rows do not collapse onto each other' ([int]$resolved['RowH'] -gt [int]$resolved['BarH']) `
        "RowH=$($resolved['RowH']) BarH=$($resolved['BarH'])"
    Assert-Lune 'an out-of-range colour override is refused' ($resolved['Accent'] -notlike '999*') `
        "Accent=$($resolved['Accent'])"
    Assert-Lune 'a colour in the wrong notation is refused too' ($resolved['Bg'] -notlike 'rgb*') `
        "Bg=$($resolved['Bg'])"

    # Generated files must stay in an encoding Rainmeter can read. A UTF-8 BOM
    # makes it read the first section header with the BOM attached, find no keys
    # and no meters, and deactivate the skin.
    $head = [System.IO.File]::ReadAllBytes($copyOut)[0..2]
    Assert-Lune 'the generated file carries no UTF-8 BOM' `
        (-not ($head[0] -eq 0xEF -and $head[1] -eq 0xBB -and $head[2] -eq 0xBF))
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($script:Failed -gt 0) {
    Write-Host "$script:Passed passed, $script:Failed FAILED" -ForegroundColor Red
    exit 1
}
Write-Host "$script:Passed passed, 0 failed" -ForegroundColor Green
exit 0
