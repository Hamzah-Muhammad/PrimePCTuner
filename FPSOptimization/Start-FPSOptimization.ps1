# Start-FPSOptimization.ps1 — v0.1 DRY-RUN GUI (PCOptimizationServices suite)
# Opens a window, detects PC specs, lists every catalog change as a checkbox
# (all checked by default), and on Start runs a DRY RUN: current state vs target
# for every checked item. NOTHING IS CHANGED in v0.1 — the apply engine is v2.
#
# Usage:  .\Start-FPSOptimization.ps1            (self-elevates)
#         .\Start-FPSOptimization.ps1 -SelfTest  (build UI headless + exit; for CI/sanity)

param([switch]$SelfTest)

$ErrorActionPreference = 'Stop'

# --- elevation (skipped in self-test; dry run is read-only but L3 checks need admin) ---
$IsElevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
              ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsElevated -and -not $SelfTest) {
    try {
        Start-Process (Get-Process -Id $PID).Path -Verb RunAs -ArgumentList '-NoProfile', '-File', "`"$PSCommandPath`""
        exit
    } catch { Write-Warning 'Elevation declined — continuing; some checks will show REVIEW.' }
}

# --- WPF needs STA ---
if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    Write-Warning 'Not STA — relaunching via powershell.exe -STA'
    Start-Process powershell.exe -ArgumentList '-STA', '-NoProfile', '-File', "`"$PSCommandPath`""
    exit
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

. (Join-Path $PSScriptRoot 'lib\Catalog.ps1')

# ---------- palette ----------
$ColOk    = '#4EC9B0'; $ColWould = '#E5A94E'; $ColReview = '#6FB3E0'
$ColSkip  = '#77777F'; $ColErr   = '#E06C75'
$LevelMeta = @{
    1 = @{ Title = 'LEVEL 1 — SAFE';       Color = '#4EC9B0' }
    2 = @{ Title = 'LEVEL 2 — DEBLOAT';    Color = '#E5A94E' }
    3 = @{ Title = 'LEVEL 3 — AGGRESSIVE'; Color = '#E06C75' }
}

# ---------- XAML ----------
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="FPSOptimization — Dry Run v0.1 · PCOptimizationServices"
        Width="1080" Height="780" MinWidth="860" MinHeight="560"
        WindowStartupLocation="CenterScreen" Background="#1E1E24">
  <Grid Margin="16">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <StackPanel Grid.Row="0" Margin="0,0,0,10">
      <TextBlock Text="FPSOptimization" FontSize="22" FontWeight="Bold" Foreground="White"/>
      <TextBlock x:Name="SubTitle" FontSize="13" Foreground="#9A9AA5"
                 Text="DRY RUN — nothing is changed. Uncheck anything you don't want, then press Start to see current state vs target."/>
    </StackPanel>

    <Border Grid.Row="1" Background="#26262E" CornerRadius="8" Padding="10" Margin="0,0,0,10">
      <WrapPanel x:Name="SpecsPanel"/>
    </Border>

    <Border Grid.Row="2" Background="#26262E" CornerRadius="8" Padding="6">
      <ScrollViewer VerticalScrollBarVisibility="Auto">
        <StackPanel x:Name="ItemsHost" Margin="6"/>
      </ScrollViewer>
    </Border>

    <DockPanel Grid.Row="3" Margin="0,12,0,0">
      <StackPanel DockPanel.Dock="Left" Orientation="Horizontal">
        <Button x:Name="BtnAll"    Content="Select all"      Padding="12,6" Margin="0,0,8,0" Background="#3A3A46" Foreground="White" BorderThickness="0"/>
        <Button x:Name="BtnNone"   Content="Select none"     Padding="12,6" Margin="0,0,8,0" Background="#3A3A46" Foreground="White" BorderThickness="0"/>
        <Button x:Name="BtnNoL3"   Content="Uncheck Level 3" Padding="12,6" Margin="0,0,8,0" Background="#3A3A46" Foreground="White" BorderThickness="0"/>
        <Button x:Name="BtnReport" Content="Open last report" Padding="12,6" Margin="0,0,8,0" Background="#3A3A46" Foreground="White" BorderThickness="0" IsEnabled="False"/>
      </StackPanel>
      <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" HorizontalAlignment="Right">
        <TextBlock x:Name="StatusText" Foreground="#9A9AA5" VerticalAlignment="Center" Margin="0,0,12,0"
                   Text="Ready." TextWrapping="Wrap" MaxWidth="520"/>
        <Button x:Name="BtnStart" Content="Start dry run" FontWeight="Bold" Padding="18,8"
                Background="#4E7CE0" Foreground="White" BorderThickness="0"/>
      </StackPanel>
    </DockPanel>
  </Grid>
</Window>
'@

$reader = [System.Xml.XmlNodeReader]::new($xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)
$ui = @{}
foreach ($name in 'SubTitle','SpecsPanel','ItemsHost','BtnAll','BtnNone','BtnNoL3','BtnReport','BtnStart','StatusText') {
    $ui[$name] = $window.FindName($name)
}

# ---------- specs panel ----------
$specs = Get-PCSpecs
$specPairs = [ordered]@{
    CPU = "$($specs.CPU)  [$($specs.Cores)]"; GPU = $specs.GPU; RAM = $specs.RAM
    OS = $specs.OS; Disks = $specs.Disks; NIC = $specs.NIC
    Session = if ($specs.Elevated) { 'Administrator' } else { 'NOT elevated — some checks limited' }
}
foreach ($k in $specPairs.Keys) {
    $chip = [Windows.Controls.Border]@{
        Background = '#31313C'; CornerRadius = [Windows.CornerRadius]::new(6)
        Padding = [Windows.Thickness]::new(8, 4, 8, 4); Margin = [Windows.Thickness]::new(0, 2, 8, 2)
    }
    $tb = [Windows.Controls.TextBlock]@{ FontSize = 12 }
    $bold = [Windows.Documents.Run]::new("$k  "); $bold.FontWeight = 'Bold'; $bold.Foreground = '#B8B8C4'
    $val  = [Windows.Documents.Run]::new([string]$specPairs[$k]); $val.Foreground = 'White'
    if ($k -eq 'Session' -and -not $specs.Elevated) { $val.Foreground = $ColWould }
    $tb.Inlines.Add($bold); $tb.Inlines.Add($val)
    $chip.Child = $tb
    $ui.SpecsPanel.Children.Add($chip) | Out-Null
}

# ---------- build the checklist ----------
$Rows = [System.Collections.Generic.List[object]]::new()

$groups = $OptimizationCatalog | Group-Object -Property { '{0}|{1}' -f $_.Level, $_.Module }
foreach ($g in $groups) {
    $level = $g.Group[0].Level
    $meta = $LevelMeta[$level]

    $header = [Windows.Controls.TextBlock]::new()
    $header.FontSize = 13; $header.FontWeight = 'Bold'
    $lvlRun = [Windows.Documents.Run]::new("$($meta.Title)   "); $lvlRun.Foreground = $meta.Color
    $modRun = [Windows.Documents.Run]::new("$($g.Group[0].Module)  ($($g.Count))"); $modRun.Foreground = 'White'
    $header.Inlines.Add($lvlRun); $header.Inlines.Add($modRun)

    $exp = [Windows.Controls.Expander]@{ IsExpanded = $true; Margin = [Windows.Thickness]::new(0, 2, 0, 6); Foreground = 'White' }
    $exp.Header = $header
    $panel = [Windows.Controls.StackPanel]::new()
    $exp.Content = $panel
    $ui.ItemsHost.Children.Add($exp) | Out-Null

    foreach ($item in $g.Group) {
        $grid = [Windows.Controls.Grid]@{ Margin = [Windows.Thickness]::new(22, 4, 4, 4) }
        foreach ($w in @([Windows.GridLength]::Auto, [Windows.GridLength]::new(1, 'Star'), [Windows.GridLength]::new(360))) {
            $cd = [Windows.Controls.ColumnDefinition]::new(); $cd.Width = $w; $grid.ColumnDefinitions.Add($cd)
        }

        $cb = [Windows.Controls.CheckBox]@{
            IsChecked = $true; VerticalAlignment = 'Top'; Margin = [Windows.Thickness]::new(0, 3, 10, 0)
        }
        [Windows.Controls.Grid]::SetColumn($cb, 0)

        $texts = [Windows.Controls.StackPanel]::new()
        $name = [Windows.Controls.TextBlock]@{
            Text = "$($item.Id)  $($item.Name)"; Foreground = 'White'; FontWeight = 'SemiBold'; TextWrapping = 'Wrap' }
        $desc = [Windows.Controls.TextBlock]@{
            Text = $item.Desc; Foreground = '#9A9AA5'; FontSize = 11.5; TextWrapping = 'Wrap' }
        $tgt = [Windows.Controls.TextBlock]@{
            Text = "target: $($item.Target)"; Foreground = '#6E6E78'; FontSize = 11; TextWrapping = 'Wrap' }
        $texts.Children.Add($name) | Out-Null
        $texts.Children.Add($desc) | Out-Null
        $texts.Children.Add($tgt)  | Out-Null
        [Windows.Controls.Grid]::SetColumn($texts, 1)

        $status = [Windows.Controls.TextBlock]@{
            Text = '— not scanned'; Foreground = $ColSkip; FontSize = 12
            TextWrapping = 'Wrap'; Margin = [Windows.Thickness]::new(12, 2, 0, 0); VerticalAlignment = 'Top' }
        [Windows.Controls.Grid]::SetColumn($status, 2)

        $grid.Children.Add($cb)     | Out-Null
        $grid.Children.Add($texts)  | Out-Null
        $grid.Children.Add($status) | Out-Null
        $panel.Children.Add($grid)  | Out-Null

        $Rows.Add([pscustomobject]@{ Item = $item; CheckBox = $cb; Status = $status })
    }
}

# ---------- buttons ----------
$ui.BtnAll.Add_Click({  foreach ($r in $Rows) { $r.CheckBox.IsChecked = $true } })
$ui.BtnNone.Add_Click({ foreach ($r in $Rows) { $r.CheckBox.IsChecked = $false } })
$ui.BtnNoL3.Add_Click({ foreach ($r in $Rows) { if ($r.Item.Level -eq 3) { $r.CheckBox.IsChecked = $false } } })

$script:LastReport = $null
$ui.BtnReport.Add_Click({ if ($script:LastReport -and (Test-Path $script:LastReport)) { Start-Process $script:LastReport } })

$ui.BtnStart.Add_Click({
    $ui.BtnStart.IsEnabled = $false
    $results = [System.Collections.Generic.List[object]]::new()
    $counts = @{ ok = 0; would = 0; review = 0; skip = 0; err = 0 }
    $i = 0
    foreach ($r in $Rows) {
        $i++
        $ui.StatusText.Text = "Checking $i of $($Rows.Count): $($r.Item.Id)…"
        $window.Dispatcher.Invoke([action]{}, [Windows.Threading.DispatcherPriority]::Background)

        if (-not $r.CheckBox.IsChecked) {
            $r.Status.Text = 'skipped (unchecked)'; $r.Status.Foreground = $ColSkip
            $counts.skip++
            $results.Add([pscustomobject]@{ Id = $r.Item.Id; Name = $r.Item.Name; Status = 'SKIPPED'; Current = '(unchecked by user)'; Target = $r.Item.Target })
            continue
        }
        try {
            $res = & $r.Item.Check
            switch ($res.Compliant) {
                $true   { $r.Status.Text = "OK — $($res.Current)";           $r.Status.Foreground = $ColOk;     $counts.ok++;     $st = 'OK' }
                $false  { $r.Status.Text = "WOULD CHANGE — $($res.Current)"; $r.Status.Foreground = $ColWould;  $counts.would++;  $st = 'WOULD CHANGE' }
                default { $r.Status.Text = "REVIEW — $($res.Current)";       $r.Status.Foreground = $ColReview; $counts.review++; $st = 'REVIEW' }
            }
            $results.Add([pscustomobject]@{ Id = $r.Item.Id; Name = $r.Item.Name; Status = $st; Current = $res.Current; Target = $r.Item.Target })
        } catch {
            $r.Status.Text = "ERROR — $($_.Exception.Message)"; $r.Status.Foreground = $ColErr
            $counts.err++
            $results.Add([pscustomobject]@{ Id = $r.Item.Id; Name = $r.Item.Name; Status = 'ERROR'; Current = $_.Exception.Message; Target = $r.Item.Target })
        }
    }

    # write report
    $logDir = Join-Path $PSScriptRoot 'logs'
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $ts = Get-Date -Format 'yyyyMMdd_HHmmss'
    $mdPath = Join-Path $logDir "DryRun_$ts.md"
    $md = [System.Collections.Generic.List[string]]::new()
    $md.Add("# FPSOptimization dry run — $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
    $md.Add('')
    $md.Add("**System:** $($specs.CPU) · $($specs.GPU) · $($specs.RAM) · $($specs.OS)")
    $md.Add("**Result:** $($counts.ok) OK · $($counts.would) would change · $($counts.review) review · $($counts.skip) skipped · $($counts.err) errors. Nothing was changed.")
    $md.Add('')
    $md.Add('| Id | Item | Status | Current | Target |')
    $md.Add('|---|---|---|---|---|')
    foreach ($e in $results) {
        $md.Add(('| {0} | {1} | {2} | {3} | {4} |' -f $e.Id, $e.Name,
            $e.Status, ($e.Current -replace '\|', '/'), ($e.Target -replace '\|', '/')))
    }
    Set-Content -Path $mdPath -Value $md -Encoding UTF8
    $results | ConvertTo-Json -Depth 4 | Set-Content -Path (Join-Path $logDir "DryRun_$ts.json") -Encoding UTF8
    $script:LastReport = $mdPath

    $ui.StatusText.Text = "Done: $($counts.ok) OK · $($counts.would) would change · $($counts.review) review · $($counts.skip) skipped · $($counts.err) errors — report: logs\DryRun_$ts.md"
    $ui.BtnReport.IsEnabled = $true
    $ui.BtnStart.IsEnabled = $true
})

if ($SelfTest) {
    Write-Host "SELFTEST OK — window built, $($Rows.Count) checklist rows, specs: $($specs.CPU) / $($specs.GPU)"
    exit 0
}

$window.ShowDialog() | Out-Null
