param([switch]$StartHidden)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing

Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class MiniClockNative {
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
}
'@

$script:AppName = 'MiniClock'
$script:SettingsDir = Join-Path $env:APPDATA $script:AppName
$script:SettingsFile = Join-Path $script:SettingsDir 'settings.json'
$script:StartupLink = Join-Path ([Environment]::GetFolderPath('Startup')) 'MiniClock.lnk'
$script:Launcher = Join-Path $PSScriptRoot 'Launch MiniClock.vbs'
$script:Exiting = $false

$script:Defaults = @{
    Left = 80.0; Top = 80.0; Scale = 1.0; Opacity = 0.88
    Use24Hour = $false; ShowSeconds = $true; ShowDate = $false
    Locked = $false; ClickThrough = $false; TextColor = '#FFFFFFFF'
    Shadow = $true
}

function Load-Settings {
    $values = $script:Defaults.Clone()
    if (Test-Path -LiteralPath $script:SettingsFile) {
        try {
            $saved = Get-Content -LiteralPath $script:SettingsFile -Raw | ConvertFrom-Json
            foreach ($key in @($values.Keys)) {
                if ($null -ne $saved.$key) { $values[$key] = $saved.$key }
            }
        } catch {}
    }
    return $values
}

function Save-Settings {
    if (-not (Test-Path -LiteralPath $script:SettingsDir)) {
        New-Item -ItemType Directory -Path $script:SettingsDir -Force | Out-Null
    }
    $script:Settings.Left = [Math]::Round($script:Window.Left, 1)
    $script:Settings.Top = [Math]::Round($script:Window.Top, 1)
    $script:Settings | ConvertTo-Json | Set-Content -LiteralPath $script:SettingsFile -Encoding UTF8
}

function New-MenuItem([string]$Text, [scriptblock]$Action, [switch]$Checked) {
    $item = [System.Windows.Forms.ToolStripMenuItem]::new($Text)
    $item.Checked = $Checked
    if ($Action) { $item.Add_Click($Action) }
    return $item
}

function Set-ClickThrough([bool]$Enabled) {
    $script:Settings.ClickThrough = $Enabled
    $helper = [System.Windows.Interop.WindowInteropHelper]::new($script:Window)
    $style = [MiniClockNative]::GetWindowLong($helper.Handle, -20)
    if ($Enabled) { $style = $style -bor 0x20 } else { $style = $style -band (-bnot 0x20) }
    [void][MiniClockNative]::SetWindowLong($helper.Handle, -20, $style)
    $script:ClickItem.Checked = $Enabled
    Save-Settings
}

function Set-Startup([bool]$Enabled) {
    if ($Enabled) {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($script:StartupLink)
        $shortcut.TargetPath = $script:Launcher
        $shortcut.WorkingDirectory = $PSScriptRoot
        $shortcut.Description = 'Transparent always-on-top desktop clock'
        $shortcut.Save()
    } elseif (Test-Path -LiteralPath $script:StartupLink) {
        Remove-Item -LiteralPath $script:StartupLink -Force
    }
    $script:StartupItem.Checked = Test-Path -LiteralPath $script:StartupLink
}

function Update-Clock {
    $now = Get-Date
    $timeFormat = if ($script:Settings.Use24Hour) {
        if ($script:Settings.ShowSeconds) { 'HH:mm:ss' } else { 'HH:mm' }
    } else {
        if ($script:Settings.ShowSeconds) { 'h:mm:ss tt' } else { 'h:mm tt' }
    }
    $script:TimeText.Text = $now.ToString($timeFormat)
    $script:DateText.Text = $now.ToString('dddd, MMMM d')
    $script:DateText.Visibility = if ($script:Settings.ShowDate) { 'Visible' } else { 'Collapsed' }
}

function Apply-Appearance {
    $scale = [double]$script:Settings.Scale
    $script:TimeText.FontSize = 38 * $scale
    $script:DateText.FontSize = 12 * $scale
    $script:Window.Opacity = [double]$script:Settings.Opacity
    $brush = [System.Windows.Media.BrushConverter]::new().ConvertFromString([string]$script:Settings.TextColor)
    $script:TimeText.Foreground = $brush
    $script:DateText.Foreground = $brush
    $script:Glow.Opacity = if ($script:Settings.Shadow) { 0.72 } else { 0 }
    $script:FormatItem.Checked = [bool]$script:Settings.Use24Hour
    $script:SecondsItem.Checked = [bool]$script:Settings.ShowSeconds
    $script:DateItem.Checked = [bool]$script:Settings.ShowDate
    $script:LockItem.Checked = [bool]$script:Settings.Locked
    Update-Clock
    $script:Window.SizeToContent = 'WidthAndHeight'
}

$script:Settings = Load-Settings

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        ResizeMode="NoResize" ShowInTaskbar="False" Topmost="True"
        SizeToContent="WidthAndHeight" MinWidth="120">
  <Border x:Name="HitArea" Background="#01000000" Padding="12,7" CornerRadius="9">
    <Grid>
      <StackPanel>
        <TextBlock x:Name="TimeText" Text="12:00:00 PM" FontFamily="Segoe UI Semibold"
                   FontWeight="SemiBold" TextAlignment="Center"/>
        <TextBlock x:Name="DateText" Text="Saturday, July 4" FontFamily="Segoe UI"
                   Margin="0,-2,0,0" TextAlignment="Center" Opacity="0.82"/>
      </StackPanel>
    </Grid>
  </Border>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$script:Window = [Windows.Markup.XamlReader]::Load($reader)
$script:TimeText = $script:Window.FindName('TimeText')
$script:DateText = $script:Window.FindName('DateText')
$script:HitArea = $script:Window.FindName('HitArea')
$script:Glow = [System.Windows.Media.Effects.DropShadowEffect]::new()
$script:Glow.BlurRadius = 9
$script:Glow.ShadowDepth = 1
$script:Glow.Color = [System.Windows.Media.Colors]::Black
$script:HitArea.Effect = $script:Glow

$menu = [System.Windows.Forms.ContextMenuStrip]::new()
$showItem = New-MenuItem 'Show clock' { $script:Window.Show(); $script:Window.Activate() }
$script:FormatItem = New-MenuItem '24-hour time' {
    $script:Settings.Use24Hour = -not $script:Settings.Use24Hour
    Apply-Appearance; Save-Settings
}
$script:SecondsItem = New-MenuItem 'Show seconds' {
    $script:Settings.ShowSeconds = -not $script:Settings.ShowSeconds
    Apply-Appearance; Save-Settings
}
$script:DateItem = New-MenuItem 'Show date' {
    $script:Settings.ShowDate = -not $script:Settings.ShowDate
    Apply-Appearance; Save-Settings
}
$script:LockItem = New-MenuItem 'Lock position' {
    $script:Settings.Locked = -not $script:Settings.Locked
    Apply-Appearance; Save-Settings
}
$script:ClickItem = New-MenuItem 'Click-through mode' {
    Set-ClickThrough (-not $script:Settings.ClickThrough)
}
$script:StartupItem = New-MenuItem 'Run when Windows starts' {
    Set-Startup (-not (Test-Path -LiteralPath $script:StartupLink))
}

$sizeMenu = [System.Windows.Forms.ToolStripMenuItem]::new('Size')
foreach ($entry in @(@('Small',0.72), @('Medium',1.0), @('Large',1.35), @('Extra large',1.7))) {
    $label = $entry[0]; $value = [double]$entry[1]
    $item = New-MenuItem $label ({
        $script:Settings.Scale = $value
        Apply-Appearance; Save-Settings
    }.GetNewClosure())
    [void]$sizeMenu.DropDownItems.Add($item)
}

$opacityMenu = [System.Windows.Forms.ToolStripMenuItem]::new('Opacity')
foreach ($entry in @(@('50%',0.5), @('70%',0.7), @('85%',0.85), @('100%',1.0))) {
    $label = $entry[0]; $value = [double]$entry[1]
    $item = New-MenuItem $label ({
        $script:Settings.Opacity = $value
        Apply-Appearance; Save-Settings
    }.GetNewClosure())
    [void]$opacityMenu.DropDownItems.Add($item)
}

$colorMenu = [System.Windows.Forms.ToolStripMenuItem]::new('Color')
foreach ($entry in @(@('White','#FFFFFFFF'), @('Warm','#FFFFD38A'), @('Ice blue','#FF8DDBFF'), @('Mint','#FF8FFFC1'), @('Rose','#FFFFA9C6'))) {
    $label = $entry[0]; $value = $entry[1]
    $item = New-MenuItem $label ({
        $script:Settings.TextColor = $value
        Apply-Appearance; Save-Settings
    }.GetNewClosure())
    [void]$colorMenu.DropDownItems.Add($item)
}

$shadowItem = New-MenuItem 'Text shadow' {
    $script:Settings.Shadow = -not $script:Settings.Shadow
    $shadowItem.Checked = $script:Settings.Shadow
    Apply-Appearance; Save-Settings
}
$shadowItem.Checked = [bool]$script:Settings.Shadow
$resetItem = New-MenuItem 'Reset position' {
    $area = [System.Windows.SystemParameters]::WorkArea
    $script:Window.Left = $area.Right - $script:Window.ActualWidth - 28
    $script:Window.Top = $area.Top + 28
    Save-Settings
}
$hideItem = New-MenuItem 'Hide clock' { $script:Window.Hide() }
$exitItem = New-MenuItem 'Exit MiniClock' {
    $script:Exiting = $true
    Save-Settings
    $script:Tray.Visible = $false
    $script:Window.Close()
    [System.Windows.Application]::Current.Shutdown()
}

foreach ($item in @(
    $showItem, (New-Object System.Windows.Forms.ToolStripSeparator),
    $script:FormatItem, $script:SecondsItem, $script:DateItem,
    $sizeMenu, $opacityMenu, $colorMenu, $shadowItem,
    (New-Object System.Windows.Forms.ToolStripSeparator),
    $script:LockItem, $script:ClickItem, $script:StartupItem, $resetItem,
    (New-Object System.Windows.Forms.ToolStripSeparator), $hideItem, $exitItem
)) { [void]$menu.Items.Add($item) }

$script:Tray = [System.Windows.Forms.NotifyIcon]::new()
$script:Tray.Text = 'MiniClock'
$script:Tray.Icon = [System.Drawing.SystemIcons]::Information
$script:Tray.ContextMenuStrip = $menu
$script:Tray.Visible = $true
$script:Tray.Add_DoubleClick({ $script:Window.Show(); $script:Window.Activate() })

$script:Window.Left = [double]$script:Settings.Left
$script:Window.Top = [double]$script:Settings.Top
$script:Window.Add_MouseLeftButtonDown({
    if (-not $script:Settings.Locked -and $_.ButtonState -eq 'Pressed') {
        try { $script:Window.DragMove() } catch {}
    }
})
$script:Window.Add_MouseRightButtonUp({
    $menu.Show([System.Windows.Forms.Cursor]::Position)
})
$script:Window.Add_MouseWheel({
    if ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control) {
        $delta = if ($_.Delta -gt 0) { 0.05 } else { -0.05 }
        $script:Settings.Opacity = [Math]::Max(0.25, [Math]::Min(1.0, [double]$script:Settings.Opacity + $delta))
        Apply-Appearance; Save-Settings
    }
})
$script:Window.Add_LocationChanged({
    if ($script:Window.IsLoaded) { Save-Settings }
})
$script:Window.Add_Closing({
    if (-not $script:Exiting) {
        $_.Cancel = $true
        $script:Window.Hide()
    }
})
$script:Window.Add_SourceInitialized({
    if ($script:Settings.ClickThrough) { Set-ClickThrough $true }
})

$timer = [System.Windows.Threading.DispatcherTimer]::new()
$timer.Interval = [TimeSpan]::FromMilliseconds(200)
$timer.Add_Tick({ Update-Clock })
$timer.Start()

Apply-Appearance
$script:StartupItem.Checked = Test-Path -LiteralPath $script:StartupLink
$app = [System.Windows.Application]::new()
if ($StartHidden) { $script:Window.Add_ContentRendered({ $script:Window.Hide() }) }
[void]$app.Run($script:Window)

$timer.Stop()
$script:Tray.Dispose()
