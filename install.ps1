<#
.SYNOPSIS
    Installs ClaudeLune into Rainmeter.

.DESCRIPTION
    ClaudeLune by Lunez (luneswan).

    Intended to be run straight from the network:

        irm https://raw.githubusercontent.com/luneswan/claudelune/main/install.ps1 | iex

    The skin folder is resolved from Rainmeter's own configuration rather than
    assumed to be Documents\Rainmeter\Skins. That assumption fails on any machine
    where Documents is redirected to OneDrive, which is common, and produces a
    silent half-install that is hard for a user to diagnose.

    Re-running upgrades in place. Every setting lives in LuneSettings.inc and is
    carried across, including any it gained since the installed version.

.NOTES
    Copyright (c) Lunez (luneswan). MIT licence - see LICENSE.
#>

[CmdletBinding()]
param(
    [string]$Branch = 'main',
    [string]$Repo   = 'luneswan/claudelune'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

function Get-LuneRainmeterExe {
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if (-not $base) { continue }
        $exe = Join-Path $base 'Rainmeter\Rainmeter.exe'
        if (Test-Path -LiteralPath $exe) { return $exe }
    }
    return $null
}

function Get-LuneSkinRoot {
    # Rainmeter records the folder it actually uses. Reading it is the only
    # dependable way to locate the skins directory when Documents is redirected.
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

<#
Carries settings across an upgrade, key by key rather than by keeping the whole
file.

Keeping the old file wholesale means a release that adds a setting ships a copy
without it, and the panel falls back to a default the user never chose. Merging
per key keeps what they set and picks up whatever is new.
#>
function Merge-LuneSettings {
    param([string]$OldText, [string]$NewPath)

    $keep = @{}
    foreach ($line in ($OldText -split "`r?`n")) {
        if ($line -match '^\s*([A-Za-z]\w*)\s*=\s*(.*)$') { $keep[$Matches[1]] = $Matches[2].TrimEnd() }
    }
    # Anything the poller rewrites is not a setting; carrying it over would pin a
    # stale reading on screen until the first poll replaced it.
    foreach ($volatile in @('Status', 'LastUpdated', 'AccountName', 'AccountPlan', 'AccountUuid', 'PlanRenews')) {
        [void]$keep.Remove($volatile)
    }
    if ($keep.Count -eq 0) { return }

    $lines = [System.IO.File]::ReadAllLines($NewPath)
    $out = foreach ($line in $lines) {
        if ($line -match '^\s*([A-Za-z]\w*)\s*=' -and $keep.ContainsKey($Matches[1])) {
            "$($Matches[1])=$($keep[$Matches[1]])"
        } else { $line }
    }
    [System.IO.File]::WriteAllLines($NewPath, @($out), (New-Object System.Text.ASCIIEncoding))
}

Write-Host 'ClaudeLune installer' -ForegroundColor Cyan

$rainmeter = Get-LuneRainmeterExe
if (-not $rainmeter) {
    Write-Warning 'Rainmeter not found. Install it from https://www.rainmeter.net/ then run this again.'
    return
}

$skinRoot = Get-LuneSkinRoot
if (-not (Test-Path -LiteralPath $skinRoot)) {
    New-Item -ItemType Directory -Force -Path $skinRoot | Out-Null
}
Write-Host "  skins folder : $skinRoot"

$staging = Join-Path ([System.IO.Path]::GetTempPath()) ('claudelune-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $staging | Out-Null

try {
    $zip = Join-Path $staging 'source.zip'
    $url = "https://github.com/$Repo/archive/refs/heads/$Branch.zip"
    Write-Host "  downloading  : $url"
    Invoke-WebRequest -Uri $url -OutFile $zip -TimeoutSec 120

    Expand-Archive -LiteralPath $zip -DestinationPath $staging -Force

    # Locate the skin by its entry point rather than by a path built from the
    # branch name, which GitHub embeds in the archive's top-level folder.
    $payload = Get-ChildItem -Path $staging -Directory -Recurse |
               Where-Object { $_.Name -eq 'ClaudeLune' -and (Test-Path (Join-Path $_.FullName 'ClaudeLune.ini')) } |
               Select-Object -First 1
    if (-not $payload) { throw 'The downloaded archive did not contain the skin.' }

    $target   = Join-Path $skinRoot 'ClaudeLune'
    $settings = Join-Path $target '@Resources\LuneSettings.inc'

    $previous = $null
    if (Test-Path -LiteralPath $settings) {
        $previous = Get-Content -LiteralPath $settings -Raw
        Write-Host '  existing settings found and will be carried across'
    }

    Copy-Item -Path $payload.FullName -Destination $skinRoot -Recurse -Force

    <#
    Files from before the 1.0.0 rename. Copying does not delete, so without this an
    upgraded install keeps both sets side by side - harmless to Rainmeter, but
    confusing to anyone who opens the folder, and a stale settings file that
    nothing reads is worse than no settings file at all.
    #>
    $legacy = @(
        '@Resources\Variables.inc', '@Resources\Presets.inc', '@Resources\Active.inc',
        '@Resources\Data.inc', '@Resources\Icons.inc',
        '@Resources\Layouts\Small.inc', '@Resources\Layouts\Normal.inc',
        '@Resources\Layouts\Wide.inc', '@Resources\Layouts\Large.inc',
        '@Resources\Scripts\Get-LuneUsage.ps1', '@Resources\Scripts\Show-Settings.ps1',
        '@Resources\Scripts\Launch-Settings.vbs'
    )
    $removed = 0
    foreach ($relative in $legacy) {
        $stale = Join-Path $target $relative
        if (Test-Path -LiteralPath $stale) { Remove-Item -LiteralPath $stale -Force; $removed++ }
    }
    if ($removed -gt 0) { Write-Host "  removed      : $removed file(s) from a previous version" }

    if ($previous) { Merge-LuneSettings -OldText $previous -NewPath $settings }

    # The skin ships pointing at powershell.exe because that is the one every
    # Windows machine has. Where PowerShell 7 is installed it starts faster, so
    # prefer it - but only after the copy, or the shipped default overwrites this.
    if (Get-Command pwsh.exe -ErrorAction SilentlyContinue) {
        $conf = Get-Content -LiteralPath $settings -Raw
        if ($conf -match '(?m)^PowerShellExe=powershell\.exe\s*\r?$') {
            $conf = $conf -replace '(?m)^PowerShellExe=powershell\.exe\s*\r?$', 'PowerShellExe=pwsh.exe'
            Set-Content -LiteralPath $settings -Value $conf -NoNewline
            Write-Host '  PowerShell 7 detected and will be used'
        }
    }

    Write-Host "  installed to : $target" -ForegroundColor Green
    & $rainmeter '!ActivateConfig' 'ClaudeLune' 'ClaudeLune.ini'

    Write-Host ''
    Write-Host 'Done. Right-click the panel for settings, layout, theme and opacity.' -ForegroundColor Cyan
    Write-Host 'If it stays blank, run "claude" once in a terminal to sign in.'
} finally {
    if (Test-Path -LiteralPath $staging) {
        [System.IO.Directory]::Delete($staging, $true)
    }
}
