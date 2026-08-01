<#
.SYNOPSIS
    Mirrors the working copy into the installed skin folder, for testing.

.DESCRIPTION
    ClaudeLune by Lunez (luneswan).

    Two rules make this safe, and both were learned the hard way:

    1. MIRROR, DO NOT MERGE.
       A plain copy leaves deleted files behind forever. The original README
       survived a rename, a re-licence and eight releases that way, because every
       deploy copied over it and nothing ever removed it.

    2. NEVER OVERWRITE GENERATED STATE.
       LuneSettings.inc holds the user's choices, and LuneLive.inc /
       LuneResolved.inc are rewritten on every poll. The repo ships all three as
       placeholders, so mirroring pushed a blank panel over a working one - the
       header read "?px wide" until the next poll repaired it.

    Only the CONTENT of those three is left alone; everything else, including
    deletions, propagates.

.EXAMPLE
    .\Publish-LuneSkin.ps1

.EXAMPLE
    .\Publish-LuneSkin.ps1 -Refresh

.NOTES
    Copyright (c) Lunez (luneswan). MIT licence - see LICENSE.
#>

[CmdletBinding()]
param(
    # Where the skin is installed. Resolved from Rainmeter's own configuration when
    # not given, because Documents is redirected to OneDrive on many machines.
    [string]$Destination,

    # Refresh the skin once the copy is done.
    [switch]$Refresh
)

$ErrorActionPreference = 'Stop'

function Get-LuneSkinRoot {
    $ini = Join-Path $env:APPDATA 'Rainmeter\Rainmeter.ini'
    if (Test-Path -LiteralPath $ini) {
        $hit = Select-String -Path $ini -Pattern '^\s*SkinPath\s*=\s*(.+)$' | Select-Object -First 1
        if ($hit) {
            $candidate = $hit.Matches[0].Groups[1].Value.Trim()
            if ($candidate -and (Test-Path -LiteralPath $candidate)) { return $candidate }
        }
    }
    return (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Rainmeter\Skins')
}

$repo   = Split-Path $PSScriptRoot -Parent
$source = Join-Path $repo 'Skins\ClaudeLune'
if (-not $Destination) { $Destination = Join-Path (Get-LuneSkinRoot) 'ClaudeLune' }

if (-not (Test-Path -LiteralPath $source)) { throw "No skin at $source." }

# /MIR mirrors, so deletions propagate. /XF keeps the three files whose content
# belongs to the installed copy rather than to the repo.
$preserved = @('LuneSettings.inc', 'LuneLive.inc', 'LuneResolved.inc')

Write-Host "source      : $source"
Write-Host "destination : $Destination"
Write-Host ('preserving  : ' + ($preserved -join ', '))

$robocopyArgs = @($source, $Destination, '/MIR', '/NFL', '/NDL', '/NJH', '/NJS', '/NP', '/R:1', '/W:1', '/XF') + $preserved
& robocopy.exe @robocopyArgs | Out-Null

# Robocopy uses exit codes as a bit field: 0-7 are success, 8 and above are real
# failures. Treating any non-zero code as an error fails every successful copy.
$code = $LASTEXITCODE
if ($code -ge 8) { throw "robocopy failed with exit code $code." }

# A fresh install has none of these files at all, so seed them once. After that
# they belong to the installed copy and the mirror leaves them alone.
foreach ($name in $preserved) {
    $target = Join-Path $Destination "@Resources\$name"
    if (-not (Test-Path -LiteralPath $target)) {
        Copy-Item -LiteralPath (Join-Path $source "@Resources\$name") -Destination $target -Force
        Write-Host "seeded      : $name"
    }
}

Write-Host "robocopy    : exit $code (0-7 is success)" -ForegroundColor Green

if ($Refresh) {
    $exe = Join-Path $env:ProgramFiles 'Rainmeter\Rainmeter.exe'
    if (Test-Path -LiteralPath $exe) {
        <#
        Never wait on a bang without a deadline.

        Rainmeter.exe invoked with a bang it cannot deliver does not fail - it
        hangs, indefinitely, and every later bang from any process is swallowed
        too. Observed with a malformed bang group: two stuck senders sat there for
        two hours and made a perfectly healthy skin look frozen to everything that
        tried to refresh it afterwards.
        #>
        $bang = Start-Process -FilePath $exe -ArgumentList @('!Refresh', 'ClaudeLune') -PassThru -WindowStyle Hidden
        if ($bang.WaitForExit(5000)) {
            Write-Host 'refreshed   : ClaudeLune'
        } else {
            try { $bang.Kill() } catch { }
            Write-Warning 'The refresh call did not return and was killed; refresh the skin by hand.'
        }
    } else {
        Write-Warning 'Rainmeter.exe not found; refresh the skin by hand.'
    }
}

# Robocopy's bit field is not a shell exit code. Leaving it in place means a
# perfectly good deploy hands its caller a non-zero status.
exit 0
