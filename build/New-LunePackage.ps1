<#
.SYNOPSIS
    Packages ClaudeLune as a .rmskin installer for Rainmeter.

.DESCRIPTION
    ClaudeLune by Lunez (luneswan).

    A .rmskin is an ordinary ZIP with a 16-byte footer appended. Rainmeter reads
    the footer to find where the archive ends, so a plain renamed .zip will not
    install.

    The footer layout was confirmed against shipped packages rather than taken
    from documentation:

        offset 0  : Int64, little-endian - length of the ZIP data
        offset 8  : one zero byte
        offset 9  : the ASCII bytes "RMSKIN" followed by a terminating zero

    Verified: a 1,973,152-byte package carries 1,973,136 in the header, which is
    its own length minus the footer.

    VariableFiles in RMSKIN.ini tells Rainmeter to preserve the user's chosen
    theme, layout and scales when they install over an existing copy.

    The build also writes SHA256SUMS.txt beside the package. Anyone who receives a
    copy can check it against the hash published with the release, which is the
    only meaningful integrity check available for a plain-text skin.

.EXAMPLE
    .\New-LunePackage.ps1 -Version 1.0.0

.NOTES
    Copyright (c) Lunez (luneswan). MIT licence - see LICENSE.
#>

[CmdletBinding()]
param(
    [string]$Version = '1.0.0',
    [string]$OutDir  = ''
)

$ErrorActionPreference = 'Stop'

$repo = Split-Path $PSScriptRoot -Parent
if (-not $OutDir) { $OutDir = Join-Path $repo 'dist' }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$staging = Join-Path ([System.IO.Path]::GetTempPath()) ('lunepkg-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path (Join-Path $staging 'Skins') | Out-Null

try {
    Copy-Item -Path (Join-Path $repo 'Skins\ClaudeLune') `
              -Destination (Join-Path $staging 'Skins') -Recurse -Force

    # Stamp the requested version into the manifest and the skin metadata, so the
    # package, the release tag and what the user sees in Rainmeter cannot drift.
    $manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'RMSKIN.ini') -Raw
    $manifest = $manifest -replace '(?m)^Version=.*\r?$', "Version=$Version"
    <#
    Written without a byte order mark, and that is not a detail.

    Set-Content -Encoding UTF8 prepends a BOM on Windows PowerShell. Rainmeter
    then reads the first line as a section header with three stray bytes glued to
    it, finds no [rmskin] section, and refuses the package as invalid - naming the
    packaging tool rather than the encoding.
    #>
    [System.IO.File]::WriteAllText(
        (Join-Path $staging 'RMSKIN.ini'), $manifest, (New-Object System.Text.UTF8Encoding($false)))

    $skinIni = Join-Path $staging 'Skins\ClaudeLune\ClaudeLune.ini'
    $ini = [System.IO.File]::ReadAllText($skinIni)
    $ini = [regex]::Replace($ini, '(?m)^Version=.*\r?$', "Version=$Version")
    [System.IO.File]::WriteAllText($skinIni, $ini, (New-Object System.Text.ASCIIEncoding))

    <#
    LuneLive.inc and LuneResolved.inc are rewritten on every poll. Running the skin
    from a working copy leaves the developer's own account name and renewal date in
    them, and twice during development that state reached a build. Blanking them
    here means a package cannot carry anyone's account data regardless of what the
    working copy happens to hold.
    #>
    $resources = Join-Path $staging 'Skins\ClaudeLune\@Resources'
    $stamp = "; ClaudeLune $Version - Lunez (luneswan). Generated file, edits are overwritten.`r`n"

    $liveKeys = @('AccountName', 'AccountPlan', 'PlanRenews', 'LastUpdated', 'ExtraModel')
    Set-Content -LiteralPath (Join-Path $resources 'LuneLive.inc') -Encoding ASCII -NoNewline -Value (
        $stamp + "; Placeholder. Rewritten on the first poll; carries no account data.`r`n[Variables]`r`n" +
        (($liveKeys | ForEach-Object { "$_=" }) -join "`r`n") +
        "`r`nIsStale=1`r`nScopedAvailable=0`r`n")

    <#
    LuneResolved is generated here rather than blanked, and that is a fix, not a
    shortcut.

    Every layout takes its positions from the resolved geometry. A placeholder
    holding only the menu marks left W, RowH and TrendH undefined, so PanelH could
    not be computed, the window measured zero by zero, and a fresh install showed
    nothing at all until PowerShell had finished its first poll. On a machine where
    PowerShell is blocked it showed nothing ever - and a skin that draws nothing
    looks broken rather than pending.

    Generating it from the staged defaults means the first frame is already
    correct. It carries no account data by construction: the resolved file holds a
    palette, a set of measurements and the menu marks, and nothing else is ever
    written to it.
    #>
    $stagedPoller = Join-Path $resources 'Scripts\Update-LuneUsage.ps1'
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $stagedPoller -ResolveOnly -NoRefresh | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Could not resolve default geometry for the package (exit $LASTEXITCODE)." }

    # Anything the working copy accumulated that is not part of the product.
    Get-ChildItem -Path (Join-Path $staging 'Skins\ClaudeLune') -Recurse -Include '*.bak', '*.tmp', '*.log' -File |
        Remove-Item -Force -ErrorAction SilentlyContinue

    # The licence travels with the package; a skin folder on someone else's disk is
    # the one place the terms actually need to be present.
    Copy-Item -Path (Join-Path $repo 'LICENSE') `
              -Destination (Join-Path $staging 'Skins\ClaudeLune\LICENSE.txt') -Force

    <#
    ---- guard: no account data may leave this machine ------------------------

    This guard used to be worthless, and worse than worthless because it looked
    like protection. It scanned exactly the two files the packager had just
    blanked, three lines earlier, so it could only ever see the blanks it had
    written itself. Injecting a real account name into the working copy and
    building produced a clean package and no complaint at all.

    A guard has to be able to fail. This one walks the entire staged tree, every
    file, and looks for the shapes account data actually takes rather than for two
    filenames someone remembered at the time. It catches a key the blank list has
    drifted away from, a new file nobody thought about, and a stray address or
    identifier anywhere in the payload.
    #>
    <#
    Three things this got wrong on the first attempt, all of which made it cry
    wolf on a perfectly clean tree - and a guard nobody believes gets disabled:

      \s* spans newlines, so "AccountUuid=" followed by a blank value matched the
      first character of the NEXT line and reported it as data. Horizontal
      whitespace only.

      TokensToday=0 is a shipped default, not somebody's identity. A count of
      tokens is not personal; it left the list.

      "AccountName = $account.name" in the poller's own source is code that
      assigns the field, not a field carrying a value. Account keys are looked for
      in .inc data files, which is the only place they can actually land.

    Addresses and identifiers are still hunted everywhere, in every file, because
    those have no business anywhere in a payload.
    #>
    $accountKeys = 'AccountName|AccountPlan|AccountUuid|PlanRenews|LastUpdated|ExtraModel|ExtraModelDesc'
    $suspects = @(
        @{ What = 'a populated account field'; DataOnly = $true
           Pattern = "(?m)^[ \t]*($accountKeys)[ \t]*=[ \t]*\S" },
        @{ What = 'an email address'; DataOnly = $false
           Pattern = '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' },
        @{ What = 'an account identifier'; DataOnly = $false
           Pattern = '\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b' }
    )

    $scanned = Get-ChildItem -LiteralPath $staging -Recurse -File
    $found = @()
    foreach ($file in $scanned) {
        # Read as text whatever the encoding: the generated files are UTF-16 and
        # the rest are ANSI, and a leak must not hide behind either.
        $text = try { [System.IO.File]::ReadAllText($file.FullName) } catch { continue }
        $isData = ($file.Extension -eq '.inc')
        foreach ($suspect in $suspects) {
            if ($suspect.DataOnly -and -not $isData) { continue }
            foreach ($hit in [regex]::Matches($text, $suspect.Pattern)) {
                $found += ('{0}: {1} -> {2}' -f $file.Name, $suspect.What, $hit.Value.Trim())
            }
        }
    }
    if ($found.Count -gt 0) {
        throw ("Refusing to package: the payload carries data that is not yours to ship -`r`n  " +
               (($found | Select-Object -Unique) -join "`r`n  "))
    }
    Write-Host ("guard    : {0} files scanned, nothing personal found" -f $scanned.Count)

    <#
    Entries are added one at a time so their names use forward slashes.

    ZipFile::CreateFromDirectory on .NET Framework, which is what Windows
    PowerShell runs, writes Path.DirectorySeparatorChar into the entry names. On
    Windows that is a backslash, and "Skins\ClaudeLune\ClaudeLune.ini" is not a
    path the ZIP format defines. Rainmeter could not find Skins/ inside the
    archive and rejected the package outright, with a message blaming the
    packaging tool rather than the separator.

    RMSKIN.ini goes in first, which is where the packages Rainmeter ships keep it.
    #>
    $zip = [System.IO.Path]::ChangeExtension($staging, 'zip')
    # Both: FileSystem carries CreateEntryFromFile, and ZipArchive and
    # ZipArchiveMode live in System.IO.Compression itself.
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $payload = @(Get-ChildItem -LiteralPath $staging -Recurse -File)
    $ordered = @($payload | Where-Object { $_.Name -eq 'RMSKIN.ini' }) +
               @($payload | Where-Object { $_.Name -ne 'RMSKIN.ini' })

    <#
    The archive is created with UTF-8 entry names, and Rainmeter will not accept
    it otherwise.

    Passing Encoding.UTF8 sets bit 11 of each entry's general purpose flag, which
    marks the name as UTF-8. Without it the flag is zero, names are read as
    CP437, and Rainmeter rejects the file with "Invalid package - the Skin
    Packager tool must be used", which points at the tool rather than the flag.

    Established by testing, not by reading: a package Rainmeter accepts had 0x0800
    on every entry and ours had 0x0000, and setting it was the single change that
    made the installer open ours.
    #>
    $stream  = [System.IO.File]::Create($zip)
    $archive = New-Object System.IO.Compression.ZipArchive(
        $stream, [System.IO.Compression.ZipArchiveMode]::Create, $false, [System.Text.Encoding]::UTF8)
    try {
        foreach ($file in $ordered) {
            $entry = $file.FullName.Substring($staging.Length).TrimStart('\', '/').Replace('\', '/')
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $archive, $file.FullName, $entry,
                [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
        }
    } finally { $archive.Dispose(); $stream.Dispose() }

    $bytes = [System.IO.File]::ReadAllBytes($zip)
    $out   = Join-Path $OutDir "ClaudeLune_$Version.rmskin"

    $stream = [System.IO.File]::Create($out)
    try {
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Write([BitConverter]::GetBytes([int64]$bytes.Length), 0, 8)
        $stream.WriteByte(0)
        $stream.Write([System.Text.Encoding]::ASCII.GetBytes('RMSKIN'), 0, 6)
        $stream.WriteByte(0)
    } finally { $stream.Dispose() }

    $size = (Get-Item $out).Length
    if ($size -ne $bytes.Length + 16) { throw 'Footer was not written correctly.' }

    $hash = (Get-FileHash -LiteralPath $out -Algorithm SHA256).Hash
    $sums = Join-Path $OutDir 'SHA256SUMS.txt'
    Set-Content -LiteralPath $sums -Encoding ASCII -Value @(
        "ClaudeLune $Version - Lunez (luneswan)",
        'Published at https://github.com/luneswan/claudelune/releases',
        '',
        ("$hash  " + (Split-Path $out -Leaf))
    )

    Write-Host "packaged : $out"
    Write-Host ("size     : {0:N0} bytes  (zip {1:N0} + 16 footer)" -f $size, $bytes.Length)
    Write-Host "sha256   : $hash"
    $out
} finally {
    if (Test-Path -LiteralPath $staging) { [System.IO.Directory]::Delete($staging, $true) }
}
