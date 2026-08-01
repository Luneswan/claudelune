<#
.SYNOPSIS
    ClaudeLune settings window.

.DESCRIPTION
    ClaudeLune by Lunez (luneswan).

    A WPF window styled to match the panel it configures: warm near-black, cream
    text, the brand orange. Rainmeter has no interface toolkit of its own, so
    without this the only way to configure the widget is to edit an .ini by hand.

    Content is grouped into raised cards rather than presented as one long list of
    label/control rows. Hierarchy comes from surface, spacing and type size, not
    from colour alone, so each group reads as a unit at a glance:

        Appearance    theme, size, opacity
        Style         font, corner radius, border weight
        Size          eight independent scale axes - WIDTH AND HEIGHT BOTH
        Behaviour     poll interval, direction, warning and critical thresholds
        Rows          what the panel shows
        Colours       twelve palette overrides, two per line

    Spacing follows an 8pt rhythm: 8 within a group, 16 between rows, 24 between
    cards. One primary action; everything else is visually subordinate.

    Everything writes to LuneSettings.inc and then runs the apply measure, so this
    window and a hand-edited file stay interchangeable. No setting lives anywhere
    else, and the window stays open across an Apply.

    THEME AS RESET
    A theme supplies a whole palette; an override replaces one entry of it.
    Selecting a theme clears every override, so re-applying a theme is how a user
    returns to a known state instead of hunting for the colour they changed.

.NOTES
    WPF requires a single-threaded apartment; launch with powershell.exe -STA. The
    skin launches it through Start-LuneSettings.vbs, which hides the console and
    detaches the process: Apply refreshes the skin, and a RunCommand measure kills
    the process it owns.

    Copyright (c) Lunez (luneswan). MIT licence - see LICENSE.txt.
#>

[CmdletBinding()]
param(
    [string]$SkinConfig = 'ClaudeLune'
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

$LuneResourceDir = Split-Path $PSScriptRoot -Parent
$LuneConfigPath  = Join-Path $LuneResourceDir 'LuneSettings.inc'
$LuneLayoutPath  = Join-Path $LuneResourceDir 'LuneResolved.inc'
$LunePresetsPath = Join-Path $LuneResourceDir 'LunePresets.inc'

# ==================================================================== files ====

function Read-LuneIni {
    param([string]$Path)
    $map = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return $map }
    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        if ($line -match '^\s*([A-Za-z]\w*)\s*=\s*(.*)$') { $map[$Matches[1]] = $Matches[2].Trim() }
    }
    return $map
}

<#
Writes every changed setting in one pass.

This took a key at a time, reading and rewriting the whole file for each one.
Apply writes about twenty-five settings, so pressing it rewrote the file
twenty-five times - twenty-five chances for an antivirus scan, a sync client or a
second copy of this window to catch the file mid-write and leave it truncated. One
read and one write has no such window.

Rewritten in place rather than regenerated, so the comments that make the file
editable by hand survive. A key that is not already present is appended.
#>
function Set-LuneIniKeys {
    param([string]$Path, [hashtable]$Values)

    if (-not $Values -or $Values.Count -eq 0) { return }
    $lines   = [System.IO.File]::ReadAllLines($Path)
    $pending = @{}
    foreach ($key in $Values.Keys) { $pending[$key] = $true }

    $out = foreach ($line in $lines) {
        $replaced = $false
        if ($line -match '^\s*([A-Za-z]\w*)\s*=') {
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

    # Written to a neighbouring file and moved into place, so a failure halfway
    # through cannot leave the user with a half-written settings file.
    $temp = "$Path.new"
    [System.IO.File]::WriteAllLines($temp, $out, (New-Object System.Text.ASCIIEncoding))
    Move-Item -LiteralPath $temp -Destination $Path -Force
}

function Get-LuneRainmeterExe {
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if (-not $base) { continue }
        $exe = Join-Path $base 'Rainmeter\Rainmeter.exe'
        if (Test-Path -LiteralPath $exe) { return $exe }
    }
    return $null
}

$vars      = Read-LuneIni $LuneConfigPath
$resolved  = Read-LuneIni $LuneLayoutPath
$presets   = Read-LuneIni $LunePresetsPath
$rainmeter = Get-LuneRainmeterExe

function Get-LuneSetting {
    param([string]$Key, [string]$Fallback)
    if ($vars.ContainsKey($Key) -and -not [string]::IsNullOrWhiteSpace($vars[$Key])) { return $vars[$Key] }
    return $Fallback
}

$LUNE_THEMES = @('Dark', 'Amoled', 'Glass', 'Light', 'Clay', 'Matrix', 'iOS')
$LUNE_SIZES  = @('Small', 'Normal', 'Wide', 'Large')
$LUNE_FONTS  = @('Segoe UI', 'Inter', 'Consolas', 'Cascadia Code', 'Arial', 'Georgia')

# Override key -> the LuneResolved.inc entry it replaces, and a readable name.
$LUNE_COLOURS = @(
    @('Bg',     'Bg',          'Background'),
    @('Text',   'Text',        'Text'),
    @('Dim',    'Dim',         'Secondary'),
    @('Bright', 'Bright',      'Headings'),
    @('Accent', 'Accent',      'Accent'),
    @('Stroke', 'Stroke',      'Border'),
    @('Track',  'Track',       'Bar track'),
    @('Normal', 'NormalColor', 'Bar normal'),
    @('Warn',   'WarnColor',   'Bar warning'),
    @('Crit',   'CritColor',   'Bar critical'),
    @('Scoped', 'ScopedColor', 'Bar model'),
    @('Off',    'OffColor',    'Offline')
)

# Every scale axis, in the order they appear in the card. Width and Height sit
# next to each other on purpose: they are the pair people reach for first, and
# height used to be missing entirely.
$LUNE_SCALES = @(
    @('UserScale',   'Everything'),
    @('WidthScale',  'Width'),
    @('HeightScale', 'Height'),
    @('FontScale',   'Text size'),
    @('PadScale',    'Padding'),
    @('RowScale',    'Row spacing'),
    @('BarScale',    'Bar thickness'),
    @('IconScale',   'Logo size')
)

# ===================================================================== XAML ====

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="ClaudeLune Settings" Width="560" Height="720"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        ResizeMode="NoResize" WindowStartupLocation="CenterScreen"
        FontFamily="Segoe UI" TextOptions.TextFormattingMode="Display">
  <Window.Resources>
    <SolidColorBrush x:Key="Bg"      Color="#1F1E1D"/>
    <SolidColorBrush x:Key="Card"    Color="#262624"/>
    <SolidColorBrush x:Key="Control" Color="#2E2C29"/>
    <SolidColorBrush x:Key="Line"    Color="#3A3733"/>
    <SolidColorBrush x:Key="Fg"      Color="#F0EEE6"/>
    <SolidColorBrush x:Key="Dim"     Color="#A19A8D"/>
    <SolidColorBrush x:Key="Brand"   Color="#D97757"/>

    <Style x:Key="Section" TargetType="TextBlock">
      <Setter Property="Foreground" Value="{StaticResource Brand}"/>
      <Setter Property="FontSize" Value="11"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
    </Style>
    <Style x:Key="Row" TargetType="TextBlock">
      <Setter Property="Foreground" Value="{StaticResource Fg}"/>
      <Setter Property="FontSize" Value="12.5"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
    </Style>
    <Style x:Key="Val" TargetType="TextBlock">
      <Setter Property="Foreground" Value="{StaticResource Dim}"/>
      <Setter Property="FontSize" Value="11.5"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
      <Setter Property="HorizontalAlignment" Value="Right"/>
    </Style>

    <Style x:Key="Flat" TargetType="Button">
      <Setter Property="Foreground" Value="{StaticResource Fg}"/>
      <Setter Property="Background" Value="{StaticResource Control}"/>
      <Setter Property="BorderBrush" Value="{StaticResource Line}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="12,6"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="HorizontalContentAlignment" Value="Center"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" CornerRadius="8" Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}">
              <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}"
                                VerticalAlignment="Center" Margin="{TemplateBinding Padding}"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="b" Property="Background" Value="#373430"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Primary" TargetType="Button" BasedOn="{StaticResource Flat}">
      <Setter Property="Background" Value="{StaticResource Brand}"/>
      <Setter Property="Foreground" Value="#1F1E1D"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding" Value="24,8"/>
    </Style>

    <Style TargetType="Slider">
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Slider">
            <Grid VerticalAlignment="Center" Height="22" Background="Transparent">
              <Border Height="4" CornerRadius="2" Background="#3A3733" VerticalAlignment="Center"/>
              <Track x:Name="PART_Track">
                <Track.DecreaseRepeatButton>
                  <RepeatButton Command="Slider.DecreaseLarge" BorderThickness="0">
                    <RepeatButton.Template>
                      <ControlTemplate TargetType="RepeatButton">
                        <Border Height="4" CornerRadius="2" Background="{StaticResource Brand}" VerticalAlignment="Center"/>
                      </ControlTemplate>
                    </RepeatButton.Template>
                  </RepeatButton>
                </Track.DecreaseRepeatButton>
                <Track.IncreaseRepeatButton>
                  <RepeatButton Command="Slider.IncreaseLarge" BorderThickness="0">
                    <RepeatButton.Template>
                      <ControlTemplate TargetType="RepeatButton"><Border Background="Transparent"/></ControlTemplate>
                    </RepeatButton.Template>
                  </RepeatButton>
                </Track.IncreaseRepeatButton>
                <Track.Thumb>
                  <Thumb Width="15" Height="15">
                    <Thumb.Template>
                      <ControlTemplate TargetType="Thumb">
                        <Grid>
                          <Ellipse Width="15" Height="15" Fill="#F0EEE6"/>
                          <Ellipse Width="7" Height="7" Fill="{StaticResource Brand}"/>
                        </Grid>
                      </ControlTemplate>
                    </Thumb.Template>
                  </Thumb>
                </Track.Thumb>
              </Track>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Border Background="{StaticResource Bg}" CornerRadius="14" BorderBrush="{StaticResource Line}" BorderThickness="1">
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <Grid x:Name="Header" Grid.Row="0" Margin="24,18,16,0" Background="Transparent">
        <StackPanel Orientation="Horizontal">
          <Canvas Width="24" Height="16" VerticalAlignment="Center" Margin="0,0,11,0">
            <Rectangle Canvas.Left="4"  Canvas.Top="0"  Width="14" Height="6" Fill="#D97757"/>
            <Rectangle Canvas.Left="0"  Canvas.Top="6"  Width="22" Height="4" Fill="#D97757"/>
            <Rectangle Canvas.Left="4"  Canvas.Top="10" Width="2"  Height="4" Fill="#D97757"/>
            <Rectangle Canvas.Left="8"  Canvas.Top="10" Width="2"  Height="4" Fill="#D97757"/>
            <Rectangle Canvas.Left="12" Canvas.Top="10" Width="2"  Height="4" Fill="#D97757"/>
            <Rectangle Canvas.Left="16" Canvas.Top="10" Width="2"  Height="4" Fill="#D97757"/>
            <Rectangle Canvas.Left="6"  Canvas.Top="2"  Width="2"  Height="2" Fill="#1F1E1D"/>
            <Rectangle Canvas.Left="14" Canvas.Top="2"  Width="2"  Height="2" Fill="#1F1E1D"/>
          </Canvas>
          <StackPanel VerticalAlignment="Center">
            <TextBlock Text="ClaudeLune" Foreground="{StaticResource Fg}" FontSize="17" FontWeight="SemiBold"/>
            <TextBlock x:Name="Sub" Foreground="{StaticResource Dim}" FontSize="11" Margin="0,1,0,0"/>
          </StackPanel>
        </StackPanel>
        <Button x:Name="BtnClose" Content="&#x2715;" HorizontalAlignment="Right" VerticalAlignment="Top"
                Width="30" Height="30" Style="{StaticResource Flat}" Padding="0" FontSize="11" ToolTip="Close"/>
      </Grid>

      <ScrollViewer x:Name="Scroll" Grid.Row="1" Margin="16,10,10,0" VerticalScrollBarVisibility="Auto" Padding="0,0,6,0">
        <StackPanel x:Name="Body" Margin="8,0,8,8"/>
      </ScrollViewer>

      <Border Grid.Row="2" Background="#1B1A19" BorderBrush="{StaticResource Line}" BorderThickness="0,1,0,0" Padding="24,14">
        <Grid>
          <TextBlock x:Name="Status" Style="{StaticResource Val}" HorizontalAlignment="Left"
                     TextWrapping="Wrap" MaxWidth="280"/>
          <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
            <Button x:Name="BtnReset" Content="Reset" Style="{StaticResource Flat}" Margin="0,0,10,0"/>
            <Button x:Name="BtnApply" Content="Apply" Style="{StaticResource Primary}"/>
          </StackPanel>
        </Grid>
      </Border>
    </Grid>
  </Border>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$win = [Windows.Markup.XamlReader]::Load($reader)

$body   = $win.FindName('Body')
$status = $win.FindName('Status')
$sub    = $win.FindName('Sub')

$win.FindName('Header').Add_MouseLeftButtonDown({ $win.DragMove() })

<#
Slower scrolling.

WPF moves three "lines" per wheel notch, which on a panel this dense jumps most of
a card at a time and makes it hard to stop where you meant to. A notch is 120
units; a quarter of that is about thirty pixels, which lands roughly one row per
notch and lets a card be read on the way past.

PreviewMouseWheel rather than MouseWheel, and marked handled, so this replaces the
default rather than being added on top of it.
#>
$scroll = $win.FindName('Scroll')
$scroll.Add_PreviewMouseWheel({
    param($sender, $e)
    $e.Handled = $true
    $scroll.ScrollToVerticalOffset($scroll.VerticalOffset - ($e.Delta * 0.25))
}.GetNewClosure())
$win.FindName('BtnClose').Add_Click({ $win.Close() })

# What the current settings actually produced, not what was typed. A scale is
# clamped on the way through, so echoing the number back would sometimes be a lie.
function Update-LuneSubtitle {
    $layout = $(if ($script:resolved.ContainsKey('LayoutName'))   { $script:resolved['LayoutName'] }   else { 'Normal' })
    $width  = $(if ($script:resolved.ContainsKey('EffectiveW'))   { $script:resolved['EffectiveW'] }   else { '?' })
    $rowH   = $(if ($script:resolved.ContainsKey('EffectiveRow')) { $script:resolved['EffectiveRow'] } else { '?' })
    $sub.Text = "$layout layout  -  ${width}px wide  -  ${rowH}px rows"
}
$script:resolved = $resolved
Update-LuneSubtitle

# ============================================================== building UI ====

function ConvertTo-LuneBrush {
    param([string]$Rgb)
    $parts = @($Rgb -split ',' | ForEach-Object { [int]($_.Trim()) })
    if ($parts.Count -lt 3) { return [Windows.Media.Brushes]::Gray }
    return (New-Object Windows.Media.SolidColorBrush(
        [Windows.Media.Color]::FromRgb($parts[0], $parts[1], $parts[2])))
}

# A card, not another row. Grouping by surface is what stops unrelated settings
# reading as one undifferentiated list.
function New-LuneCard {
    param([string]$Title)
    $head = New-Object Windows.Controls.TextBlock
    $head.Text = $Title.ToUpper()
    $head.Style = $win.FindResource('Section')
    $head.Margin = '4,20,0,8'
    [void]$body.Children.Add($head)

    $border = New-Object Windows.Controls.Border
    $border.Background = $win.FindResource('Card')
    $border.CornerRadius = 10
    $border.BorderBrush = $win.FindResource('Line')
    $border.BorderThickness = 1
    $border.Padding = '16,14,16,6'
    $inner = New-Object Windows.Controls.StackPanel
    $border.Child = $inner
    [void]$body.Children.Add($border)
    return $inner
}

function New-LuneRow {
    param($Parent, [string[]]$Widths, [string]$Margin = '0,0,0,10')
    $grid = New-Object Windows.Controls.Grid
    $grid.Margin = $Margin
    foreach ($w in $Widths) {
        $column = New-Object Windows.Controls.ColumnDefinition
        $column.Width = $w
        $grid.ColumnDefinitions.Add($column)
    }
    [void]$Parent.Children.Add($grid)
    return $grid
}

function Add-LuneLabel {
    param($Grid, [string]$Text, [string]$Tip = '')
    $block = New-Object Windows.Controls.TextBlock
    $block.Text = $Text
    $block.Style = $win.FindResource('Row')
    if ($Tip) { $block.ToolTip = $Tip }
    [void]$Grid.Children.Add($block)
}

<#
Chips, not a dropdown.

A templated ComboBox kept its stock light chrome regardless of styling and sat on
the dark surface as a grey slab. Chips also show every option at once, which for
seven themes is more useful than hiding six of them behind a click.
#>
function Add-LuneChips {
    param($Parent, [string]$Label, [string[]]$Options, [string]$Current, $Swatch = $null)
    $grid = New-LuneRow $Parent @('118', '*')
    Add-LuneLabel $grid $Label
    $wrap = New-Object Windows.Controls.WrapPanel
    [Windows.Controls.Grid]::SetColumn($wrap, 1)
    [void]$grid.Children.Add($wrap)

    $onFg  = New-Object Windows.Media.SolidColorBrush([Windows.Media.Color]::FromRgb(31, 30, 29))
    $offFg = $win.FindResource('Fg')
    $onBg  = $win.FindResource('Brand')
    $offBg = $win.FindResource('Control')

    $state = [PSCustomObject]@{ Value = $Current; Buttons = New-Object System.Collections.ArrayList; Sync = $null }
    foreach ($option in $Options) {
        $chip = New-Object Windows.Controls.Button
        $chip.Style = $win.FindResource('Flat')
        $chip.Content = $option
        $chip.Margin = '0,0,6,6'
        $chip.Padding = '11,5'
        $chip.FontSize = 11.5
        $chip.Tag = $option
        if ($Swatch -and $Swatch.ContainsKey($option)) {
            $chip.BorderThickness = '2'
            $chip.BorderBrush = $Swatch[$option]
        }
        [void]$wrap.Children.Add($chip)
        [void]$state.Buttons.Add($chip)
    }

    $sync = {
        foreach ($chip in $state.Buttons) {
            $on = ($chip.Tag -eq $state.Value)
            $chip.Background = $(if ($on) { $onBg } else { $offBg })
            $chip.Foreground = $(if ($on) { $onFg } else { $offFg })
            $chip.FontWeight = $(if ($on) { 'SemiBold' } else { 'Normal' })
        }
    }.GetNewClosure()

    foreach ($chip in $state.Buttons) {
        $chip.Add_Click({ $state.Value = $this.Tag; & $sync }.GetNewClosure())
    }
    # Kept on the state so an import can move the selection and have the chips
    # repaint, rather than leaving the highlight on whatever was chosen before.
    $state.Sync = $sync
    & $sync
    return $state
}

function Add-LuneSlider {
    param($Parent, [string]$Label, [double]$Value, [double]$Min = 0.5, [double]$Max = 2.0,
          [string]$Format = '{0:0.00}x', [double]$Tick = 0.05, [string]$Tip = '')
    $grid = New-LuneRow $Parent @('118', '*', '56') '0,0,0,9'
    Add-LuneLabel $grid $Label $Tip

    $slider = New-Object Windows.Controls.Slider
    $slider.Minimum = $Min
    $slider.Maximum = $Max
    $slider.TickFrequency = $Tick
    $slider.IsSnapToTickEnabled = $true
    $slider.VerticalAlignment = 'Center'
    $slider.Value = [Math]::Max($Min, [Math]::Min($Max, $Value))
    if ($Tip) { $slider.ToolTip = $Tip }
    [Windows.Controls.Grid]::SetColumn($slider, 1)
    [void]$grid.Children.Add($slider)

    $readout = New-Object Windows.Controls.TextBlock
    $readout.Style = $win.FindResource('Val')
    $readout.Text = ($Format -f $slider.Value)
    [Windows.Controls.Grid]::SetColumn($readout, 2)
    [void]$grid.Children.Add($readout)
    # GetNewClosure binds this row's own pair; without it every handler would
    # update whichever readout was created last.
    $slider.Add_ValueChanged({ $readout.Text = ($Format -f $slider.Value) }.GetNewClosure())
    return $slider
}

# A switch reads as a state; a button labelled "Yes" reads as an action.
function Add-LuneToggle {
    param($Parent, [string]$Label, [bool]$On, [string]$Tip = '')
    $grid = New-LuneRow $Parent @('160', '*')
    Add-LuneLabel $grid $Label $Tip

    $onBg  = $win.FindResource('Brand')
    $offBg = $win.FindResource('Line')
    $state = [PSCustomObject]@{ On = $On }

    $track = New-Object Windows.Controls.Border
    $track.Width = 42
    $track.Height = 23
    $track.CornerRadius = 12
    $track.HorizontalAlignment = 'Left'
    $track.Cursor = 'Hand'
    if ($Tip) { $track.ToolTip = $Tip }
    $knob = New-Object Windows.Shapes.Ellipse
    $knob.Width = 17
    $knob.Height = 17
    $knob.Fill = New-Object Windows.Media.SolidColorBrush([Windows.Media.Color]::FromRgb(240, 238, 230))
    $knob.VerticalAlignment = 'Center'
    $knob.Margin = '3,0,3,0'
    $track.Child = $knob
    [Windows.Controls.Grid]::SetColumn($track, 1)
    [void]$grid.Children.Add($track)

    $sync = {
        $track.Background = $(if ($state.On) { $onBg } else { $offBg })
        $knob.HorizontalAlignment = $(if ($state.On) { 'Right' } else { 'Left' })
    }.GetNewClosure()

    $track.Add_MouseLeftButtonUp({ $state.On = -not $state.On; & $sync }.GetNewClosure())
    & $sync
    return $state
}

<#
Two colours per line rather than twelve stacked rows: the palette is the densest
part of this window, and one column made it the longest section by far for no
benefit. The native colour dialog is used rather than a hand-built picker; it is
familiar and already handles custom colours. Alpha carries over from the existing
value, since that dialog has no alpha channel.
#>
function Add-LuneColourPair {
    param($Parent, $Left, $Right)
    $grid = New-LuneRow $Parent @('*', '*')
    $column = 0
    foreach ($entry in @($Left, $Right)) {
        if ($null -eq $entry) { $column++; continue }
        $state = $entry
        $cell = New-Object Windows.Controls.StackPanel
        $cell.Orientation = 'Horizontal'
        [Windows.Controls.Grid]::SetColumn($cell, $column)
        [void]$grid.Children.Add($cell)

        $swatch = New-Object Windows.Controls.Button
        $swatch.Style = $win.FindResource('Flat')
        $swatch.Width = 34
        $swatch.Height = 24
        $swatch.Padding = '0'
        $swatch.Background = ConvertTo-LuneBrush $state.Value
        $swatch.Margin = '0,0,9,0'
        $swatch.ToolTip = 'Click to choose a colour. Right-click to return this one to the theme.'
        [void]$cell.Children.Add($swatch)
        # Held so an import, or a per-colour reset, can repaint this swatch.
        $state | Add-Member -NotePropertyName Swatch -NotePropertyValue $swatch -Force

        $caption = New-Object Windows.Controls.TextBlock
        $caption.Text = $state.Label
        $caption.Style = $win.FindResource('Row')
        $caption.FontSize = 12
        [void]$cell.Children.Add($caption)

        $swatch.Add_Click({
            $dialog = New-Object System.Windows.Forms.ColorDialog
            $dialog.FullOpen = $true
            $parts = @($state.Value -split ',' | ForEach-Object { [int]($_.Trim()) })
            if ($parts.Count -ge 3) { $dialog.Color = [System.Drawing.Color]::FromArgb($parts[0], $parts[1], $parts[2]) }
            if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                $alpha = if ($parts.Count -ge 4) { ",$($parts[3])" } else { '' }
                $state.Value = "$($dialog.Color.R),$($dialog.Color.G),$($dialog.Color.B)$alpha"
                $state.Changed = $true
                $swatch.Background = ConvertTo-LuneBrush $state.Value
            }
            $dialog.Dispose()
        }.GetNewClosure())

        <#
        Right-click returns one colour to the theme.

        Without this the only way back from a single unwanted override was to
        re-apply the theme, which discards the other eleven as well - so fixing one
        mistake cost every deliberate choice beside it.
        #>
        $swatch.Add_MouseRightButtonUp({
            $state.Value   = $state.Preset
            $state.Changed = $true
            $state.Cleared = $true
            $swatch.Background = ConvertTo-LuneBrush $state.Value
        }.GetNewClosure())

        $column++
    }
}

function Add-LuneHint {
    param($Parent, [string]$Text)
    $hint = New-Object Windows.Controls.TextBlock
    $hint.Style = $win.FindResource('Val')
    $hint.HorizontalAlignment = 'Left'
    $hint.TextWrapping = 'Wrap'
    $hint.Margin = '0,2,0,8'
    $hint.Text = $Text
    [void]$Parent.Children.Add($hint)
}

# ==================================================== content -- luneswan -- ===

# Theme chips carry that theme's own background as their border, so the palette is
# visible before it is applied.
$themeSwatch = @{}
foreach ($theme in $LUNE_THEMES) {
    $key = "${theme}Bg"
    if ($presets.ContainsKey($key)) { $themeSwatch[$theme] = ConvertTo-LuneBrush $presets[$key] }
}

$cardAppearance = New-LuneCard 'Appearance'
$chipTheme  = Add-LuneChips  $cardAppearance 'Theme' $LUNE_THEMES (Get-LuneSetting 'Theme' 'Dark') $themeSwatch
$chipSize   = Add-LuneChips  $cardAppearance 'Size'  $LUNE_SIZES  (Get-LuneSetting 'Size' 'Normal')
$sldOpacity = Add-LuneSlider $cardAppearance 'Opacity' ([double](Get-LuneSetting 'Opacity' '240') / 255) 0.2 1.0 '{0:P0}' 0.02

$cardStyle = New-LuneCard 'Style'
$chipFont  = Add-LuneChips  $cardStyle 'Font' $LUNE_FONTS (Get-LuneSetting 'FontFace' 'Segoe UI')
$sldRadius = Add-LuneSlider $cardStyle 'Corner radius' ([double](Get-LuneSetting 'CornerRadius' '12')) 0 24 '{0:0}px' 1
$sldBorder = Add-LuneSlider $cardStyle 'Border'        ([double](Get-LuneSetting 'BorderWidth'  '1'))  0  4 '{0:0}px' 1

$cardSize = New-LuneCard 'Size and spacing'
$sliders = @{}
foreach ($axis in $LUNE_SCALES) {
    $sliders[$axis[0]] = Add-LuneSlider $cardSize $axis[1] ([double](Get-LuneSetting $axis[0] '1.0'))
}
Add-LuneHint $cardSize ('Height moves the header offset, every gap and the trend strip; Row spacing moves ' +
    'only the distance between rows. Every value is clamped, so no combination can overlap text or break the panel.')

$cardBehaviour = New-LuneCard 'Behaviour'
$tglRemaining = Add-LuneToggle $cardBehaviour 'Count what is left' ((Get-LuneSetting 'ShowRemaining' '0') -eq '1') `
    'On: "35% left". Off: "65% used". The number, the bar and the wording all flip together.'
$sldInterval = Add-LuneSlider $cardBehaviour 'Poll every' ([double](Get-LuneSetting 'RefreshInterval' '10')) 5 60 '{0:0}s' 1 `
    'How often the panel asks. The poller has its own adaptive interval on top of this, so a short value costs a process, not a request.'
$sldWarn = Add-LuneSlider $cardBehaviour 'Warning at'  ([double](Get-LuneSetting 'WarningThreshold'  '75')) 40 95 '{0:0}%' 1
$sldCrit = Add-LuneSlider $cardBehaviour 'Critical at' ([double](Get-LuneSetting 'CriticalThreshold' '90')) 50 99 '{0:0}%' 1

$cardRows = New-LuneCard 'Rows'
$tglLogo   = Add-LuneToggle $cardRows 'Show the mark'       ((Get-LuneSetting 'ShowLogo'   '1') -eq '1')
$tglScoped = Add-LuneToggle $cardRows 'Per-model row'       ((Get-LuneSetting 'ShowScoped' '1') -eq '1') `
    'Only appears on plans that actually carry a per-model weekly cap.'
$tglExtra  = Add-LuneToggle $cardRows 'Included-model note' ((Get-LuneSetting 'ShowFable'  '1') -eq '1')

$cardColours = New-LuneCard 'Colours'
$themeNow = Get-LuneSetting 'Theme' 'Dark'
$swatchStates = @()
foreach ($colour in $LUNE_COLOURS) {
    # What is drawn now, override included.
    $current = $(if ($resolved.ContainsKey($colour[1])) { $resolved[$colour[1]] } else { '128,128,128' })
    # What the theme alone would draw, so a single colour can be put back without
    # discarding the other eleven.
    $preset = $(if ($presets.ContainsKey($themeNow + $colour[0])) { $presets[$themeNow + $colour[0]] } else { $current })
    $swatchStates += [PSCustomObject]@{
        Key = $colour[0]; Label = $colour[2]; Value = $current
        Preset = $preset; Changed = $false; Cleared = $false
    }
}
for ($i = 0; $i -lt $swatchStates.Count; $i += 2) {
    $right = $(if ($i + 1 -lt $swatchStates.Count) { $swatchStates[$i + 1] } else { $null })
    Add-LuneColourPair $cardColours $swatchStates[$i] $right
}
Add-LuneHint $cardColours ('These replace single entries of the current theme. Right-click a swatch to put ' +
    'that one back; choosing any theme clears all of them.')

<#
Export and import.

A palette someone has spent time on should be movable - to another machine, to a
backup, to someone else. The file is the same Key=Value text as the settings file,
so it is readable, diffable and editable by hand, and importing is just a filtered
copy of keys this window knows about.
#>
$exportRow = New-LuneRow $cardColours @('*', 'Auto', 'Auto') '0,6,0,10'
$btnExport = New-Object Windows.Controls.Button
$btnExport.Style = $win.FindResource('Flat')
$btnExport.Content = 'Export theme...'
$btnExport.Padding = '12,5'
$btnExport.FontSize = 11.5
$btnExport.Margin = '0,0,8,0'
[Windows.Controls.Grid]::SetColumn($btnExport, 1)
[void]$exportRow.Children.Add($btnExport)

$btnImport = New-Object Windows.Controls.Button
$btnImport.Style = $win.FindResource('Flat')
$btnImport.Content = 'Import...'
$btnImport.Padding = '12,5'
$btnImport.FontSize = 11.5
[Windows.Controls.Grid]::SetColumn($btnImport, 2)
[void]$exportRow.Children.Add($btnImport)

# Everything a look is made of: the base theme, the twelve overrides, and the three
# style values. Not the scales - those are about the size of your screen, not the
# appearance of the panel, and carrying them across machines is usually wrong.
$LUNE_THEME_KEYS = @('Theme', 'FontFace', 'CornerRadius', 'BorderWidth') +
                   ($LUNE_COLOURS | ForEach-Object { "Custom$($_[0])" })

<#
Theme files, as pure functions.

These were written inline inside two click handlers, which meant they could not be
run without a mouse and so were shipped without ever having been executed once.
Everything that decides anything now lives here, takes plain values and returns
plain values, and the handlers below are reduced to choosing a filename.

An import validates rather than trusts: an unknown theme name, an unparseable
number or a malformed colour is dropped and reported, and the rest of the file is
still applied. A theme someone hand-edited badly should cost them that one entry,
not the whole import.
#>
function ConvertTo-LuneThemeLines {
    param([string]$Theme, [string]$FontFace, [int]$CornerRadius, [int]$BorderWidth, $Swatches)

    $lines = @(
        '; ClaudeLune theme',
        '; Lunez (luneswan). Import from the settings window, or copy these keys',
        '; straight into LuneSettings.inc.',
        "; exported $([DateTime]::Now.ToString('yyyy-MM-dd'))",
        '[Variables]',
        "Theme=$Theme",
        "FontFace=$FontFace",
        "CornerRadius=$CornerRadius",
        "BorderWidth=$BorderWidth"
    )
    foreach ($state in $Swatches) {
        # An untouched colour exports blank, which reads as "whatever the theme
        # says" on the machine that imports it.
        $value = $(if ($state.Changed -and -not $state.Cleared) { $state.Value } else { '' })
        $lines += "Custom$($state.Key)=$value"
    }
    return $lines
}

function Read-LuneThemeFile {
    param([string]$Path, [string[]]$KnownThemes, [string[]]$ColourKeys)

    $incoming = Read-LuneIni $Path
    $result = @{ Colours = @{}; Rejected = @(); Applied = 0 }

    if ($incoming.ContainsKey('Theme')) {
        if ($KnownThemes -contains $incoming['Theme']) {
            $result['Theme'] = $incoming['Theme']; $result.Applied++
        } else {
            $result.Rejected += "unknown theme '$($incoming['Theme'])'"
        }
    }
    # Any installed font is legal, so this is carried through as typed; only an
    # empty value is refused.
    if ($incoming.ContainsKey('FontFace') -and $incoming['FontFace']) {
        $result['FontFace'] = $incoming['FontFace']; $result.Applied++
    }
    foreach ($key in @('CornerRadius', 'BorderWidth')) {
        if (-not $incoming.ContainsKey($key)) { continue }
        $parsed = 0.0
        if ([double]::TryParse($incoming[$key], [ref]$parsed)) {
            $result[$key] = $parsed; $result.Applied++
        } else {
            $result.Rejected += "$key is not a number ('$($incoming[$key])')"
        }
    }
    foreach ($colour in $ColourKeys) {
        $key = "Custom$colour"
        if (-not $incoming.ContainsKey($key)) { continue }
        $value = $incoming[$key]
        if ([string]::IsNullOrWhiteSpace($value)) {
            # Blank means "follow the theme", which is a real instruction, not a
            # missing value.
            $result.Colours[$colour] = ''; $result.Applied++
        } elseif ($value -match '^\s*\d{1,3}\s*,\s*\d{1,3}\s*,\s*\d{1,3}(\s*,\s*\d{1,3})?\s*$' -and
                  -not (($value -split ',') | Where-Object { [int]$_.Trim() -gt 255 })) {
            $result.Colours[$colour] = ($value -replace '\s', ''); $result.Applied++
        } else {
            $result.Rejected += "$key is not a colour ('$value')"
        }
    }
    return $result
}

$btnExport.Add_Click({
    $dialog = New-Object System.Windows.Forms.SaveFileDialog
    $dialog.Filter = 'ClaudeLune theme (*.lunetheme)|*.lunetheme|All files (*.*)|*.*'
    $dialog.FileName = "$($chipTheme.Value).lunetheme"
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        try {
            $lines = ConvertTo-LuneThemeLines -Theme $chipTheme.Value -FontFace $chipFont.Value `
                        -CornerRadius ([int]$sldRadius.Value) -BorderWidth ([int]$sldBorder.Value) `
                        -Swatches $swatchStates
            [System.IO.File]::WriteAllLines($dialog.FileName, $lines, (New-Object System.Text.ASCIIEncoding))
            $status.Text = "Exported to $(Split-Path $dialog.FileName -Leaf)."
        } catch {
            $status.Text = "Could not export: $($_.Exception.Message)"
        }
    }
    $dialog.Dispose()
})

$btnImport.Add_Click({
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Filter = 'ClaudeLune theme (*.lunetheme)|*.lunetheme|All files (*.*)|*.*'
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        try {
            $theme = Read-LuneThemeFile -Path $dialog.FileName -KnownThemes $LUNE_THEMES `
                        -ColourKeys ($LUNE_COLOURS | ForEach-Object { $_[0] })

            if ($theme.ContainsKey('Theme'))    { $chipTheme.Value = $theme['Theme']; & $chipTheme.Sync }
            if ($theme.ContainsKey('FontFace')) {
                $chipFont.Value = $theme['FontFace']
                if ($LUNE_FONTS -contains $theme['FontFace']) { & $chipFont.Sync }
            }
            foreach ($pair in @(@('CornerRadius', $sldRadius), @('BorderWidth', $sldBorder))) {
                if ($theme.ContainsKey($pair[0])) {
                    $pair[1].Value = [Math]::Max($pair[1].Minimum, [Math]::Min($pair[1].Maximum, $theme[$pair[0]]))
                }
            }
            foreach ($state in $swatchStates) {
                if (-not $theme.Colours.ContainsKey($state.Key)) { continue }
                $value = $theme.Colours[$state.Key]
                if ($value -eq '') { $state.Value = $state.Preset; $state.Cleared = $true }
                else               { $state.Value = $value;        $state.Cleared = $false }
                $state.Changed = $true
                $state.Swatch.Background = ConvertTo-LuneBrush $state.Value
            }

            # A theme selection normally wipes the overrides on Apply. An import
            # brings both at once and means them together, so the wipe is disarmed.
            $script:themeAtLoad = [string]$chipTheme.Value

            $note = "Imported $($theme.Applied) setting(s) from $(Split-Path $dialog.FileName -Leaf)."
            if ($theme.Rejected.Count -gt 0) { $note += " Skipped: $($theme.Rejected -join '; ')." }
            $status.Text = "$note Press Apply."
        } catch {
            $status.Text = "Could not import: $($_.Exception.Message)"
        }
    }
    $dialog.Dispose()
})

# ==================================================================== apply ====

$script:themeAtLoad = Get-LuneSetting 'Theme' 'Dark'

$win.FindName('BtnApply').Add_Click({
    try {
        # Collected first, written once. See Set-LuneIniKeys for why.
        $write = @{
            Size            = [string]$chipSize.Value
            Opacity         = [string][int][Math]::Round($sldOpacity.Value * 255)
            FontFace        = [string]$chipFont.Value
            CornerRadius    = [string][int]$sldRadius.Value
            BorderWidth     = [string][int]$sldBorder.Value
            ShowRemaining   = $(if ($tglRemaining.On) { '1' } else { '0' })
            ShowLogo        = $(if ($tglLogo.On)      { '1' } else { '0' })
            ShowScoped      = $(if ($tglScoped.On)    { '1' } else { '0' })
            ShowFable       = $(if ($tglExtra.On)     { '1' } else { '0' })
            RefreshInterval = [string][int]$sldInterval.Value
        }
        foreach ($key in @($sliders.Keys)) { $write[$key] = ('{0:0.00}' -f $sliders[$key].Value) }

        # Critical has to sit above warning or the blend inverts and the bar runs
        # backwards through the palette. Nudged rather than refused, so the window
        # never rejects a combination it can fix itself.
        $warn = [int]$sldWarn.Value
        $crit = [int]$sldCrit.Value
        if ($crit -le $warn) { $crit = [Math]::Min(99, $warn + 5); $sldCrit.Value = $crit }
        $write['WarningThreshold']  = [string]$warn
        $write['CriticalThreshold'] = [string]$crit

        # A theme is a whole palette, so selecting one clears every override. That
        # makes re-applying a theme the way back to a known state.
        $themeChanged = ([string]$chipTheme.Value -ne $script:themeAtLoad)
        $write['Theme'] = [string]$chipTheme.Value

        if ($themeChanged) {
            foreach ($colour in $LUNE_COLOURS) { $write["Custom$($colour[0])"] = '' }
            $script:themeAtLoad = [string]$chipTheme.Value
            foreach ($state in $swatchStates) { $state.Changed = $false }
            $status.Text = "$($chipTheme.Value) applied. Colours reset to its palette."
        } else {
            foreach ($state in $swatchStates) {
                if (-not $state.Changed) { continue }
                # A cleared colour writes an empty override, which is what "use the
                # theme" means; writing the preset value instead would pin it and
                # stop it following a later theme change.
                $write["Custom$($state.Key)"] = $(if ($state.Cleared) { '' } else { $state.Value })
            }
            $status.Text = 'Applied.'
        }

        Set-LuneIniKeys $LuneConfigPath $write

        if ($rainmeter) {
            <#
            A deadline, not a plain call.

            Rainmeter.exe given a bang it cannot deliver hangs indefinitely rather
            than failing, and this window would hang with it - Apply would appear
            to lock up. Worse, a stuck sender swallows every later bang from any
            process, so the panel really would stop updating afterwards.
            #>
            $bang = Start-Process -FilePath $rainmeter -WindowStyle Hidden -PassThru `
                -ArgumentList @('!CommandMeasure', 'MeasureLuneApply', 'Run', $SkinConfig)
            if (-not $bang.WaitForExit(5000)) {
                try { $bang.Kill() } catch { }
                $status.Text = 'Saved, but Rainmeter did not respond. Refresh the skin by hand.'
                return
            }
            # The subtitle reports what the panel actually became, so it is read
            # back after the poller has rewritten the file rather than predicted.
            Start-Sleep -Milliseconds 700
            $script:resolved = Read-LuneIni $LuneLayoutPath
            Update-LuneSubtitle
        } else {
            $status.Text = 'Saved. Rainmeter was not found, so refresh the skin by hand.'
        }
    } catch {
        $status.Text = "Could not apply: $($_.Exception.Message)"
    }
})

$win.FindName('BtnReset').Add_Click({
    foreach ($key in @($sliders.Keys)) { $sliders[$key].Value = 1.0 }
    $sldOpacity.Value  = 240 / 255
    $sldRadius.Value   = 12
    $sldBorder.Value   = 1
    $sldInterval.Value = 10
    $sldWarn.Value     = 75
    $sldCrit.Value     = 90
    $status.Text = 'Reset - press Apply to keep it.'
})

# The window has no title bar to close from, so the key that closes every other
# dialog on Windows has to work here too.
$win.Add_KeyDown({
    if ($_.Key -eq [Windows.Input.Key]::Escape) { $win.Close() }
})

[void]$win.ShowDialog()
