# PrimePCTuner.ps1 — the suite hub (PrimePCTuner)
# Main page: your PC's specs + which tool do you want to run?
#   · FPS Optimizer     — deep gaming optimization (52 checks, 3 risk levels)
#   · Startup Optimizer — clean logon/startup junk on everyday PCs
#
# Usage:  .\PrimePCTuner.ps1            (self-elevates; tools launch elevated from here)
#         .\PrimePCTuner.ps1 -SelfTest  (build UI headless + exit)

param([switch]$SelfTest)
$ErrorActionPreference = 'Stop'

# $PSScriptRoot is empty when this script is running compiled (ps2exe) — there's no real
# .ps1 file on disk at runtime, so fall back to the exe's own folder.
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }

. (Join-Path $ScriptDir 'shared\PrimeUI.ps1')
Invoke-PrimeBootstrap -SelfTest:$SelfTest -ScriptPath $PSCommandPath

$Tools = @(
    @{
        Key   = 'fps';     Name = 'FPS Optimizer';     Tag = 'FOR GAMING RIGS';   TagColor = $P.Green
        Desc  = 'Deep gaming optimization: telemetry & background-contention elimination, service debloat, NIC tuning, and aggressive security trade-offs. 52 checks across 3 risk levels.'
        Meta  = 'v0.3 · 52 checks · dry run'
        Path  = Join-Path $ScriptDir 'FPSOptimization\Start-FPSOptimization.ps1'
    }
    @{
        Key   = 'startup'; Name = 'Startup Optimizer'; Tag = 'FOR EVERYDAY PCs'; TagColor = $P.GoldA
        Desc  = 'The toned-down cleaner: lists every app, logon task, and Windows extra (Widgets, Copilot, Edge preload) that launches itself at logon — uncheck the keepers, clear the rest.'
        Meta  = 'v0.1 · dynamic scan · dry run'
        Path  = Join-Path $ScriptDir 'StartupOptimization\Start-StartupOptimization.ps1'
    }
)

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="PrimePCTuner by @Humzeeny"
        Width="880" Height="640" MinWidth="760" MinHeight="560"
        WindowStartupLocation="CenterScreen" Background="$($P.Bg)"
        FontFamily="Segoe UI" TextOptions.TextFormattingMode="Display">
  <Window.Resources>
$(Get-PrimeResourcesXaml)
  </Window.Resources>
  <Grid ClipToBounds="True">
$(Get-PrimeGlowsXaml)
    <Grid Margin="30,22,30,16">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <Grid Grid.Row="0">
$(Get-PrimeTopbarXaml)
      </Grid>

      <StackPanel Grid.Row="1" Margin="0,22,0,12">
        <TextBlock Text="P R I M E P C T U N E R" FontSize="11"
                   FontWeight="Bold" Foreground="$($P.Green)"/>
        <TextBlock Margin="0,4,0,0" FontSize="34" FontWeight="ExtraBold" Foreground="$($P.Text)">
          <Run Text="Prime"/><Run Foreground="$($P.Green)" Text="PCTuner"/>
        </TextBlock>
        <TextBlock Margin="0,4,0,0" FontSize="13" Foreground="$($P.Muted)" TextWrapping="Wrap"
                   Text="Your system, detected below. Pick the tool that fits this PC — every tool shows you each change as a checkbox before anything happens."/>
      </StackPanel>

      <WrapPanel Grid.Row="2" x:Name="SpecsPanel" Margin="0,0,0,14"/>

      <StackPanel Grid.Row="3" x:Name="CardsHost" VerticalAlignment="Top"/>

      <DockPanel Grid.Row="4" Margin="0,12,0,0">
        <TextBlock DockPanel.Dock="Left" FontSize="11.5" Foreground="$($P.Muted)">
          <Run Foreground="$($P.Green)" Text="@"/><Run Text="Humzeeny"/>
        </TextBlock>
        <TextBlock DockPanel.Dock="Right" HorizontalAlignment="Right" FontSize="11.5"
                   Foreground="$($P.Muted)" Text="PrimePCTuner hub v0.1"/>
      </DockPanel>
    </Grid>
  </Grid>
</Window>
"@

$window = [Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new($xaml))
$specsPanel = $window.FindName('SpecsPanel')
$cardsHost  = $window.FindName('CardsHost')

$specs = Get-PCSpecs
Add-PrimeSpecChips -Panel $specsPanel -Window $window -Specs $specs

# Resolve a real PowerShell host to launch the tool scripts with — never re-invoke our own
# process path here, since that breaks once this hub is compiled to PcOptimizer.exe (a
# standalone binary that only knows how to run its own embedded script, not -File args).
$PSExe = $null
foreach ($cand in 'pwsh.exe', 'powershell.exe') {
    $cmd = Get-Command $cand -ErrorAction SilentlyContinue
    if ($cmd) { $PSExe = $cmd.Source; break }
}
if (-not $PSExe) {
    [Windows.MessageBox]::Show('No PowerShell host (pwsh or powershell.exe) found on this PC — cannot launch tools.', 'PrimePCTuner', 'OK', 'Error') | Out-Null
}

foreach ($tool in $Tools) {
    $card = [Windows.Controls.Border]::new()
    $card.Style = $window.FindResource('RowCard')
    $card.Padding = [Windows.Thickness]::new(22, 18, 22, 18)
    $card.Margin = [Windows.Thickness]::new(0, 6, 0, 6)

    $grid = [Windows.Controls.Grid]::new()
    foreach ($w in @([Windows.GridLength]::new(1, 'Star'), [Windows.GridLength]::Auto)) {
        $cd = [Windows.Controls.ColumnDefinition]::new(); $cd.Width = $w; $grid.ColumnDefinitions.Add($cd)
    }

    $texts = [Windows.Controls.StackPanel]::new()
    $titleLine = [Windows.Controls.TextBlock]::new()
    $nameRun = [Windows.Documents.Run]::new($tool.Name)
    $nameRun.FontSize = 19; $nameRun.FontWeight = 'Bold'; $nameRun.Foreground = $P.Text
    $tagRun = [Windows.Documents.Run]::new("   $($tool.Tag)")
    $tagRun.FontSize = 10.5; $tagRun.FontWeight = 'Bold'; $tagRun.Foreground = $tool.TagColor
    $titleLine.Inlines.Add($nameRun); $titleLine.Inlines.Add($tagRun)
    $desc = [Windows.Controls.TextBlock]@{
        Text = $tool.Desc; Foreground = $P.Muted; FontSize = 12; TextWrapping = 'Wrap'
        Margin = [Windows.Thickness]::new(0, 5, 16, 0) }
    $meta = [Windows.Controls.TextBlock]@{
        Text = $tool.Meta; FontFamily = 'Consolas'; Foreground = '#55555F'; FontSize = 10.5
        Margin = [Windows.Thickness]::new(0, 6, 0, 0) }
    $texts.Children.Add($titleLine) | Out-Null
    $texts.Children.Add($desc)      | Out-Null
    $texts.Children.Add($meta)      | Out-Null
    [Windows.Controls.Grid]::SetColumn($texts, 0)

    $btn = [Windows.Controls.Button]::new()
    $btn.Style = $window.FindResource('BtnPri')
    $btn.Content = 'Launch  →'
    $btn.VerticalAlignment = 'Center'
    $toolPath = $tool.Path
    $btn.Add_Click({
        if ($PSExe) { Start-Process $PSExe -ArgumentList '-NoProfile', '-File', "`"$toolPath`"" }
    }.GetNewClosure())
    [Windows.Controls.Grid]::SetColumn($btn, 1)

    $grid.Children.Add($texts) | Out-Null
    $grid.Children.Add($btn)   | Out-Null
    $card.Child = $grid
    $cardsHost.Children.Add($card) | Out-Null
}

if ($SelfTest) {
    Write-Host "SELFTEST OK — hub window built, $($Tools.Count) tool cards, specs: $($specs.CPU) / $($specs.GPU)"
    exit 0
}
$window.ShowDialog() | Out-Null
