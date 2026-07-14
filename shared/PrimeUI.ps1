# PrimeUI.ps1 — shared Prime Investing UI framework for the PCOptimizationServices suite.
# Palette, window bootstrap (elevation/STA/WPF), PC-specs detection, spec chips,
# and the branded checklist window + dry-run scan engine used by every tool.
# Dot-source this BEFORE a tool's lib\Catalog.ps1.

# ---------- brand palette (prime_theme / PrimeStocks App.css) ----------
$Script:P = @{
    Bg      = '#09090E'; Surface = '#111116'; SurfAlt = '#18181F'; Border = '#242430'
    Text    = '#F2F2F7'; Muted   = '#7C7C86'
    Green   = '#00C805'; GreenHi = '#00E808'
    GoldA   = '#FFD60A'; GoldB   = '#FF9500'
    Red     = '#FF453A'
}

# ---------- bootstrap: elevation + STA + WPF assemblies ----------
function Invoke-PrimeBootstrap {
    param([switch]$SelfTest, [string]$ScriptPath)
    $elevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
                ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $elevated -and -not $SelfTest) {
        try {
            Start-Process (Get-Process -Id $PID).Path -Verb RunAs -ArgumentList '-NoProfile', '-File', "`"$ScriptPath`""
            exit
        } catch { Write-Warning 'Elevation declined — continuing; some checks may show REVIEW.' }
    }
    if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
        Write-Warning 'Not STA — relaunching via powershell.exe -STA'
        Start-Process powershell.exe -ArgumentList '-STA', '-NoProfile', '-File', "`"$ScriptPath`""
        exit
    }
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
}

# ---------- PC specs ----------
function Get-ActiveNic {
    Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
        Where-Object Status -eq 'Up' |
        Sort-Object -Property Speed -Descending |
        Select-Object -First 1
}

function Get-PCSpecs {
    $cpu  = Get-CimInstance Win32_Processor | Select-Object -First 1
    $gpu  = Get-CimInstance Win32_VideoController |
                Where-Object { $_.Name -notmatch 'Basic Display|Remote' } | Select-Object -First 1
    $os   = Get-CimInstance Win32_OperatingSystem
    $cs   = Get-CimInstance Win32_ComputerSystem
    $dimm = Get-CimInstance Win32_PhysicalMemory
    $ramGb    = [math]::Round($cs.TotalPhysicalMemory / 1GB)
    $ramSpeed = ($dimm | Measure-Object -Property ConfiguredClockSpeed -Maximum).Maximum
    $disks = Get-CimInstance Win32_DiskDrive | ForEach-Object {
        '{0} ({1} GB)' -f ($_.Model -replace '\s+', ' ').Trim(), [math]::Round($_.Size / 1GB)
    }
    $nic   = Get-ActiveNic
    $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
              ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    [pscustomobject]@{
        CPU      = $cpu.Name.Trim()
        Cores    = '{0}C / {1}T' -f $cpu.NumberOfCores, $cpu.NumberOfLogicalProcessors
        GPU      = $gpu.Name
        RAM      = '{0} GB @ {1} MHz' -f $ramGb, $ramSpeed
        OS       = '{0} (build {1})' -f $os.Caption.Trim(), $os.BuildNumber
        Disks    = $disks -join ' · '
        NIC      = if ($nic) { '{0} ({1})' -f $nic.InterfaceDescription, $nic.LinkSpeed } else { 'none up' }
        Elevated = $admin
    }
}

# ---------- shared XAML fragments ----------
function Get-PrimeResourcesXaml {
    @"
    <Style x:Key="PrimeCheck" TargetType="CheckBox">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="CheckBox">
            <Border x:Name="box" Width="20" Height="20" CornerRadius="6"
                    Background="$($P.Surface)" BorderBrush="$($P.Border)" BorderThickness="1.5">
              <TextBlock x:Name="mark" Text="✓" FontSize="13" FontWeight="Bold"
                         Foreground="$($P.Bg)" HorizontalAlignment="Center" VerticalAlignment="Center"
                         Visibility="Collapsed"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="box" Property="Background" Value="$($P.Green)"/>
                <Setter TargetName="box" Property="BorderBrush" Value="$($P.Green)"/>
                <Setter TargetName="mark" Property="Visibility" Value="Visible"/>
              </Trigger>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="box" Property="BorderBrush" Value="$($P.GreenHi)"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="BtnSec" TargetType="Button">
      <Setter Property="Foreground" Value="$($P.Text)"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="Padding" Value="14,7"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="$($P.SurfAlt)" BorderBrush="$($P.Border)"
                    BorderThickness="1" CornerRadius="10" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="BorderBrush" Value="$($P.Green)"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Opacity" Value="0.4"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="BtnPri" TargetType="Button">
      <Setter Property="Foreground" Value="$($P.Bg)"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Padding" Value="22,9"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="$($P.Green)" CornerRadius="10"
                    Padding="{TemplateBinding Padding}">
              <Border.Effect>
                <DropShadowEffect Color="$($P.Green)" BlurRadius="18" ShadowDepth="0" Opacity="0.45"/>
              </Border.Effect>
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Background" Value="$($P.GreenHi)"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Opacity" Value="0.4"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="RowCard" TargetType="Border">
      <Setter Property="CornerRadius" Value="12"/>
      <Setter Property="BorderBrush" Value="$($P.Border)"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="14,10"/>
      <Setter Property="Margin" Value="0,3"/>
      <Setter Property="Background">
        <Setter.Value>
          <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
            <GradientStop Color="$($P.Surface)" Offset="0"/>
            <GradientStop Color="$($P.SurfAlt)" Offset="1"/>
          </LinearGradientBrush>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Chip" TargetType="Border">
      <Setter Property="Background" Value="$($P.Surface)"/>
      <Setter Property="BorderBrush" Value="$($P.Border)"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="CornerRadius" Value="8"/>
      <Setter Property="Padding" Value="10,5"/>
      <Setter Property="Margin" Value="0,2,8,2"/>
    </Style>
"@
}

function Get-PrimeGlowsXaml {
    @"
    <Ellipse Width="1300" Height="760" HorizontalAlignment="Center" VerticalAlignment="Top"
             Margin="0,-420,0,0" IsHitTestVisible="False">
      <Ellipse.Fill>
        <RadialGradientBrush>
          <GradientStop Color="#2E00C805" Offset="0"/><GradientStop Color="#0000C805" Offset="1"/>
        </RadialGradientBrush>
      </Ellipse.Fill>
    </Ellipse>
    <Ellipse Width="1000" Height="640" HorizontalAlignment="Right" VerticalAlignment="Bottom"
             Margin="0,0,-380,-380" IsHitTestVisible="False">
      <Ellipse.Fill>
        <RadialGradientBrush>
          <GradientStop Color="#21FF9500" Offset="0"/><GradientStop Color="#00FF9500" Offset="1"/>
        </RadialGradientBrush>
      </Ellipse.Fill>
    </Ellipse>
"@
}

function Get-PrimeTopbarXaml {
    @"
      <DockPanel>
        <StackPanel Orientation="Horizontal" DockPanel.Dock="Left">
          <Ellipse Width="11" Height="11" Fill="$($P.Green)" VerticalAlignment="Center">
            <Ellipse.Effect>
              <DropShadowEffect Color="$($P.Green)" BlurRadius="14" ShadowDepth="0" Opacity="0.9"/>
            </Ellipse.Effect>
          </Ellipse>
          <TextBlock VerticalAlignment="Center" Margin="10,0,0,0" FontSize="14" FontWeight="Bold">
            <Run Foreground="$($P.Green)" Text="@"/><Run Foreground="$($P.Text)" Text="humzeeny"/>
          </TextBlock>
        </StackPanel>
        <TextBlock DockPanel.Dock="Right" HorizontalAlignment="Right" VerticalAlignment="Center"
                   FontSize="12" FontWeight="Bold" Text="PRIME INVESTING">
          <TextBlock.Foreground>
            <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
              <GradientStop Color="$($P.GoldA)" Offset="0"/><GradientStop Color="$($P.GoldB)" Offset="1"/>
            </LinearGradientBrush>
          </TextBlock.Foreground>
        </TextBlock>
      </DockPanel>
"@
}

# ---------- spec chips ----------
function Add-PrimeSpecChips {
    param($Panel, $Window, $Specs)
    $pairs = [ordered]@{
        CPU = "$($Specs.CPU)  [$($Specs.Cores)]"; GPU = $Specs.GPU; RAM = $Specs.RAM
        OS = $Specs.OS; Disks = $Specs.Disks; NIC = $Specs.NIC
        Session = if ($Specs.Elevated) { 'Administrator' } else { 'NOT elevated — some checks limited' }
    }
    foreach ($k in $pairs.Keys) {
        $chip = [Windows.Controls.Border]::new()
        $chip.Style = $Window.FindResource('Chip')
        $tb = [Windows.Controls.TextBlock]@{ FontSize = 11.5 }
        $lbl = [Windows.Documents.Run]::new("$k  "); $lbl.FontWeight = 'Bold'; $lbl.Foreground = $P.Muted
        $val = [Windows.Documents.Run]::new([string]$pairs[$k]); $val.Foreground = $P.Text
        if ($k -eq 'Session' -and -not $Specs.Elevated) { $val.Foreground = $P.GoldA }
        $tb.Inlines.Add($lbl); $tb.Inlines.Add($val)
        $chip.Child = $tb
        $Panel.Children.Add($chip) | Out-Null
    }
}

# ---------- status pills ----------
$Script:PillStyles = @{
    APPLIED = @{ Text = '✓ APPLIED'; Fg = $P.GreenHi; Border = $P.Green;  Bg = '#1200C805' }
    PENDING = @{ Text = '→ PENDING'; Fg = $P.GoldA;   Border = $P.GoldB;  Bg = '#14FFD60A' }
    REVIEW  = @{ Text = '◆ REVIEW';  Fg = '#B8B8C4';  Border = $P.Muted;  Bg = '#141419' }
    SKIPPED = @{ Text = 'SKIPPED';   Fg = $P.Muted;   Border = $P.Border; Bg = '#141419' }
    ERROR   = @{ Text = '✕ ERROR';   Fg = $P.Red;     Border = $P.Red;    Bg = '#14FF453A' }
}
function Set-PrimeRowStatus {
    param($Row, [string]$Kind, [string]$Detail)
    $s = $PillStyles[$Kind]
    $Row.PillText.Text = $s.Text
    $Row.PillText.Foreground = $s.Fg
    $Row.PillBorder.BorderBrush = $s.Border
    $Row.PillBorder.Background = $s.Bg
    $Row.Detail.Text = $Detail
}

# ---------- dry-run scan engine ----------
function Invoke-PrimeScan {
    param($Ctx)
    $ui = $Ctx.UI
    $ui.BtnScan.IsEnabled = $false
    $results = [System.Collections.Generic.List[object]]::new()
    $counts = @{ applied = 0; pending = 0; review = 0; skipped = 0; errors = 0 }
    $i = 0
    foreach ($r in $Ctx.Rows) {
        $i++
        $ui.StatusText.Text = "Checking $i of $($Ctx.Rows.Count): $($r.Item.Id)…"
        $Ctx.Window.Dispatcher.Invoke([action]{}, [Windows.Threading.DispatcherPriority]::Background)

        if (-not $r.CheckBox.IsChecked) {
            Set-PrimeRowStatus $r 'SKIPPED' 'unchecked by user'
            $counts.skipped++
            $results.Add([pscustomobject]@{ Id = $r.Item.Id; Name = $r.Item.Name; Status = 'SKIPPED'; Current = '(unchecked by user)'; Target = $r.Item.Target })
            continue
        }
        try {
            $res = & $r.Item.Check
            switch ($res.Compliant) {
                $true   { Set-PrimeRowStatus $r 'APPLIED' $res.Current; $counts.applied++; $st = 'APPLIED' }
                $false  { Set-PrimeRowStatus $r 'PENDING' $res.Current; $counts.pending++; $st = 'PENDING' }
                default { Set-PrimeRowStatus $r 'REVIEW'  $res.Current; $counts.review++;  $st = 'REVIEW' }
            }
            $results.Add([pscustomobject]@{ Id = $r.Item.Id; Name = $r.Item.Name; Status = $st; Current = $res.Current; Target = $r.Item.Target })
        } catch {
            Set-PrimeRowStatus $r 'ERROR' $_.Exception.Message
            $counts.errors++
            $results.Add([pscustomobject]@{ Id = $r.Item.Id; Name = $r.Item.Name; Status = 'ERROR'; Current = $_.Exception.Message; Target = $r.Item.Target })
        }
    }

    foreach ($key in $Ctx.StatRuns.Keys) { $Ctx.StatRuns[$key].Text = [string]$counts[$key] }

    New-Item -ItemType Directory -Force -Path $Ctx.LogDir | Out-Null
    $ts = Get-Date -Format 'yyyyMMdd_HHmmss'
    $mdPath = Join-Path $Ctx.LogDir "DryRun_$ts.md"
    $md = [System.Collections.Generic.List[string]]::new()
    $md.Add("# $($Ctx.ReportTitle) — $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
    $md.Add('')
    $md.Add("**System:** $($Ctx.Specs.CPU) · $($Ctx.Specs.GPU) · $($Ctx.Specs.RAM) · $($Ctx.Specs.OS)")
    $md.Add("**Result:** $($counts.applied) applied · $($counts.pending) pending · $($counts.review) review · $($counts.skipped) skipped · $($counts.errors) errors. Nothing was changed.")
    $md.Add('')
    $md.Add('| Id | Item | Status | Current | Target |')
    $md.Add('|---|---|---|---|---|')
    foreach ($e in $results) {
        $md.Add(('| {0} | {1} | {2} | {3} | {4} |' -f $e.Id, $e.Name,
            $e.Status, ($e.Current -replace '\|', '/'), ($e.Target -replace '\|', '/')))
    }
    Set-Content -Path $mdPath -Value $md -Encoding UTF8
    $results | ConvertTo-Json -Depth 4 | Set-Content -Path (Join-Path $Ctx.LogDir "DryRun_$ts.json") -Encoding UTF8
    $Ctx.LastReport = $mdPath

    $ui.StatusText.Text = "$($counts.applied) applied · $($counts.pending) pending · $($counts.review) review · $($counts.skipped) skipped · $($counts.errors) errors"
    $ui.BtnReport.IsEnabled = $true
    $ui.BtnScan.IsEnabled = $true
}

# ---------- the branded checklist window ----------
function New-PrimeChecklistApp {
    param(
        [string]$Title, [string]$Eyebrow, [string]$HeadingPlain, [string]$HeadingAccent,
        [string]$SubTitle, [string]$FooterNote, $Items, $LevelMeta,
        [string]$LogDir, [string]$ReportTitle
    )

    [xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$Title"
        Width="1180" Height="840" MinWidth="920" MinHeight="600"
        WindowStartupLocation="CenterScreen" Background="$($P.Bg)"
        FontFamily="Segoe UI" TextOptions.TextFormattingMode="Display">
  <Window.Resources>
$(Get-PrimeResourcesXaml)
  </Window.Resources>
  <Grid ClipToBounds="True">
$(Get-PrimeGlowsXaml)
    <Grid Margin="26,20,26,14">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <Grid Grid.Row="0">
$(Get-PrimeTopbarXaml)
      </Grid>

      <StackPanel Grid.Row="1" Margin="0,18,0,10">
        <TextBlock Text="$Eyebrow" FontSize="11" FontWeight="Bold" Foreground="$($P.Green)"/>
        <TextBlock Margin="0,4,0,0" FontSize="30" FontWeight="ExtraBold" Foreground="$($P.Text)">
          <Run Text="$HeadingPlain"/><Run Foreground="$($P.Green)" Text="$HeadingAccent"/>
        </TextBlock>
        <TextBlock Margin="0,4,0,0" FontSize="12.5" Foreground="$($P.Muted)" TextWrapping="Wrap"
                   Text="$SubTitle"/>
      </StackPanel>

      <StackPanel Grid.Row="2" Margin="0,0,0,10">
        <WrapPanel x:Name="SpecsPanel"/>
        <WrapPanel x:Name="StatsPanel" Margin="0,6,0,0"/>
      </StackPanel>

      <Border Grid.Row="3" Background="$($P.Surface)" BorderBrush="$($P.Border)"
              BorderThickness="1" CornerRadius="14" Padding="6">
        <ScrollViewer VerticalScrollBarVisibility="Auto">
          <StackPanel x:Name="ItemsHost" Margin="8,4"/>
        </ScrollViewer>
      </Border>

      <DockPanel Grid.Row="4" Margin="0,12,0,0">
        <StackPanel DockPanel.Dock="Left" Orientation="Horizontal">
          <Button x:Name="BtnAll"    Style="{StaticResource BtnSec}" Content="Select all"      Margin="0,0,8,0"/>
          <Button x:Name="BtnNone"   Style="{StaticResource BtnSec}" Content="Select none"     Margin="0,0,8,0"/>
          <Button x:Name="BtnNoL3"   Style="{StaticResource BtnSec}" Content="Uncheck Level 3" Margin="0,0,8,0"/>
          <Button x:Name="BtnReport" Style="{StaticResource BtnSec}" Content="Open report"     Margin="0,0,8,0" IsEnabled="False"/>
        </StackPanel>
        <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" HorizontalAlignment="Right">
          <TextBlock x:Name="StatusText" Foreground="$($P.Muted)" FontSize="12" VerticalAlignment="Center"
                     Margin="0,0,14,0" TextWrapping="Wrap" MaxWidth="520" Text="Scanning…"/>
          <Button x:Name="BtnScan" Style="{StaticResource BtnPri}" Content="Re-scan"/>
        </StackPanel>
      </DockPanel>

      <DockPanel Grid.Row="5" Margin="0,10,0,0">
        <TextBlock DockPanel.Dock="Left" FontSize="11.5" Foreground="$($P.Muted)">
          <Run Foreground="$($P.Green)" Text="@"/><Run Text="humzeeny"/><Run Text="  ·  Prime Investing"/>
        </TextBlock>
        <TextBlock DockPanel.Dock="Right" HorizontalAlignment="Right" FontSize="11.5"
                   Foreground="$($P.Muted)" Text="$FooterNote"/>
      </DockPanel>
    </Grid>
  </Grid>
</Window>
"@

    $window = [Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new($xaml))
    $ui = @{}
    foreach ($name in 'SpecsPanel','StatsPanel','ItemsHost','BtnAll','BtnNone','BtnNoL3','BtnReport','BtnScan','StatusText') {
        $ui[$name] = $window.FindName($name)
    }

    $specs = Get-PCSpecs
    Add-PrimeSpecChips -Panel $ui.SpecsPanel -Window $window -Specs $specs

    # scan-stat chips
    $statDefs = @(
        @{ Key = 'applied'; Label = 'APPLIED'; Color = $P.Green }
        @{ Key = 'pending'; Label = 'PENDING'; Color = $P.GoldA }
        @{ Key = 'review';  Label = 'REVIEW';  Color = $P.Muted }
        @{ Key = 'skipped'; Label = 'SKIPPED'; Color = $P.Muted }
        @{ Key = 'errors';  Label = 'ERRORS';  Color = $P.Red }
    )
    $statRuns = @{}
    foreach ($sd in $statDefs) {
        $chip = [Windows.Controls.Border]::new()
        $chip.Style = $window.FindResource('Chip')
        $tb = [Windows.Controls.TextBlock]@{ FontSize = 12 }
        $dotRun = [Windows.Documents.Run]::new('● '); $dotRun.Foreground = $sd.Color; $dotRun.FontSize = 10
        $numRun = [Windows.Documents.Run]::new('–');  $numRun.FontWeight = 'Bold'; $numRun.Foreground = $P.Text
        $lblRun = [Windows.Documents.Run]::new("  $($sd.Label)"); $lblRun.Foreground = $P.Muted; $lblRun.FontSize = 10.5
        $tb.Inlines.Add($dotRun); $tb.Inlines.Add($numRun); $tb.Inlines.Add($lblRun)
        $chip.Child = $tb
        $ui.StatsPanel.Children.Add($chip) | Out-Null
        $statRuns[$sd.Key] = $numRun
    }

    # checklist rows
    $rows = [System.Collections.Generic.List[object]]::new()
    $groups = $Items | Group-Object -Property { '{0}|{1}' -f $_.Level, $_.Module }
    foreach ($g in $groups) {
        $meta = $LevelMeta[$g.Group[0].Level]
        $header = [Windows.Controls.TextBlock]::new()
        $header.FontSize = 11; $header.FontWeight = 'Bold'
        $header.Margin = [Windows.Thickness]::new(4, 14, 0, 4)
        $lvlRun = [Windows.Documents.Run]::new("$($meta.Title)   "); $lvlRun.Foreground = $meta.Color
        $modRun = [Windows.Documents.Run]::new("$($g.Group[0].Module.ToUpper())  ·  $($g.Count) ITEMS"); $modRun.Foreground = $P.Muted
        $header.Inlines.Add($lvlRun); $header.Inlines.Add($modRun)
        $ui.ItemsHost.Children.Add($header) | Out-Null

        foreach ($item in $g.Group) {
            $card = [Windows.Controls.Border]::new()
            $card.Style = $window.FindResource('RowCard')
            $grid = [Windows.Controls.Grid]::new()
            foreach ($w in @([Windows.GridLength]::Auto, [Windows.GridLength]::Auto,
                             [Windows.GridLength]::new(1, 'Star'), [Windows.GridLength]::new(340))) {
                $cd = [Windows.Controls.ColumnDefinition]::new(); $cd.Width = $w; $grid.ColumnDefinitions.Add($cd)
            }

            $cb = [Windows.Controls.CheckBox]::new()
            $cb.Style = $window.FindResource('PrimeCheck')
            $cb.IsChecked = [bool]$item.DefaultChecked
            $cb.VerticalAlignment = 'Top'
            $cb.Margin = [Windows.Thickness]::new(0, 2, 12, 0)
            [Windows.Controls.Grid]::SetColumn($cb, 0)

            $pill = [Windows.Controls.Border]@{
                Background = $P.Bg; BorderBrush = $P.Border
                BorderThickness = [Windows.Thickness]::new(1)
                CornerRadius = [Windows.CornerRadius]::new(7)
                Padding = [Windows.Thickness]::new(8, 3, 8, 3)
                Margin = [Windows.Thickness]::new(0, 0, 12, 0)
                VerticalAlignment = 'Top'; MinWidth = 46
            }
            $pillText = [Windows.Controls.TextBlock]@{
                Text = $item.Id; FontFamily = 'Consolas'; FontSize = 11.5; FontWeight = 'Bold'
                Foreground = $P.Green; HorizontalAlignment = 'Center'
            }
            $pill.Child = $pillText
            [Windows.Controls.Grid]::SetColumn($pill, 1)

            $texts = [Windows.Controls.StackPanel]::new()
            $name = [Windows.Controls.TextBlock]@{
                Text = $item.Name; Foreground = $P.Text; FontWeight = 'SemiBold'
                FontSize = 13; TextWrapping = 'Wrap' }
            $desc = [Windows.Controls.TextBlock]@{
                Text = $item.Desc; Foreground = $P.Muted; FontSize = 11; TextWrapping = 'Wrap'
                Margin = [Windows.Thickness]::new(0, 1, 0, 0) }
            $tgt = [Windows.Controls.TextBlock]@{
                Text = "target: $($item.Target)"; FontFamily = 'Consolas'; Foreground = '#55555F'
                FontSize = 10.5; TextWrapping = 'Wrap'; Margin = [Windows.Thickness]::new(0, 2, 0, 0) }
            $texts.Children.Add($name) | Out-Null
            $texts.Children.Add($desc) | Out-Null
            $texts.Children.Add($tgt)  | Out-Null
            [Windows.Controls.Grid]::SetColumn($texts, 2)

            $statusStack = [Windows.Controls.StackPanel]@{ Margin = [Windows.Thickness]::new(14, 0, 0, 0) }
            $stPill = [Windows.Controls.Border]@{
                CornerRadius = [Windows.CornerRadius]::new(8)
                BorderThickness = [Windows.Thickness]::new(1)
                Padding = [Windows.Thickness]::new(9, 2, 9, 3)
                HorizontalAlignment = 'Left'
                Background = '#141419'; BorderBrush = $P.Border
            }
            $stPillText = [Windows.Controls.TextBlock]@{
                Text = '… SCANNING'; FontSize = 10.5; FontWeight = 'Bold'; Foreground = $P.Muted }
            $stPill.Child = $stPillText
            $stDetail = [Windows.Controls.TextBlock]@{
                Text = ''; FontSize = 10.5; Foreground = $P.Muted; TextWrapping = 'Wrap'
                Margin = [Windows.Thickness]::new(1, 4, 0, 0) }
            $statusStack.Children.Add($stPill)   | Out-Null
            $statusStack.Children.Add($stDetail) | Out-Null
            [Windows.Controls.Grid]::SetColumn($statusStack, 3)

            $grid.Children.Add($cb)          | Out-Null
            $grid.Children.Add($pill)        | Out-Null
            $grid.Children.Add($texts)       | Out-Null
            $grid.Children.Add($statusStack) | Out-Null
            $card.Child = $grid
            $ui.ItemsHost.Children.Add($card) | Out-Null

            $rows.Add([pscustomobject]@{
                Item = $item; CheckBox = $cb; PillBorder = $stPill; PillText = $stPillText; Detail = $stDetail })
        }
    }

    $ctx = @{
        Window = $window; UI = $ui; Rows = $rows; Specs = $specs
        StatRuns = $statRuns; LogDir = $LogDir; ReportTitle = $ReportTitle
        LastReport = $null; Scanned = $false
    }

    $ui.BtnAll.Add_Click({  foreach ($r in $ctx.Rows) { $r.CheckBox.IsChecked = $true } }.GetNewClosure())
    $ui.BtnNone.Add_Click({ foreach ($r in $ctx.Rows) { $r.CheckBox.IsChecked = $false } }.GetNewClosure())
    $ui.BtnNoL3.Add_Click({ foreach ($r in $ctx.Rows) { if ($r.Item.Level -eq 3) { $r.CheckBox.IsChecked = $false } } }.GetNewClosure())
    $ui.BtnReport.Add_Click({ if ($ctx.LastReport -and (Test-Path $ctx.LastReport)) { Start-Process $ctx.LastReport } }.GetNewClosure())
    $ui.BtnScan.Add_Click({ Invoke-PrimeScan -Ctx $ctx }.GetNewClosure())
    $window.Add_ContentRendered({
        if (-not $ctx.Scanned) { $ctx.Scanned = $true; Invoke-PrimeScan -Ctx $ctx }
    }.GetNewClosure())

    $ctx
}
