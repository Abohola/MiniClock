param([switch]$StartHidden, [switch]$OpenSettings, [switch]$OpenTools)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing

Add-Type @'
using System;
using System.IO;
using System.Media;
using System.Runtime.InteropServices;
using System.Threading;
public static class MiniClockNative {
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
}
public static class MiniClockSounds {
    private static readonly int[][] Melodies = new int[][] {
        new int[] { 880, 1175, 1568 },
        new int[] { 784, 784, 1047, 1047 },
        new int[] { 523, 659, 784, 1047 },
        new int[] { 392, 523, 659, 784, 1047 },
        new int[] { 1047, 1319, 1568, 2093 },
        new int[] { 660, 880, 660, 880, 1100 },
        new int[] { 330, 440, 554, 659, 880 },
        new int[] { 988, 740, 988, 740, 1175, 988 }
    };
    public static void Play(int index) {
        ThreadPool.QueueUserWorkItem(_ => {
            int[] notes = Melodies[Math.Max(0, Math.Min(index, Melodies.Length - 1))];
            foreach (int note in notes) {
                using (MemoryStream wave = CreateTone(note, index == 7 ? 180 : 260)) {
                    using (SoundPlayer player = new SoundPlayer(wave)) { player.PlaySync(); }
                }
                Thread.Sleep(index == 5 || index == 7 ? 70 : 110);
            }
        });
    }
    private static MemoryStream CreateTone(int frequency, int milliseconds) {
        const int sampleRate = 22050;
        int samples = sampleRate * milliseconds / 1000;
        MemoryStream stream = new MemoryStream();
        BinaryWriter writer = new BinaryWriter(stream);
        int dataLength = samples * 2;
        writer.Write(new char[] {'R','I','F','F'});
        writer.Write(36 + dataLength);
        writer.Write(new char[] {'W','A','V','E','f','m','t',' '});
        writer.Write(16); writer.Write((short)1); writer.Write((short)1);
        writer.Write(sampleRate); writer.Write(sampleRate * 2);
        writer.Write((short)2); writer.Write((short)16);
        writer.Write(new char[] {'d','a','t','a'}); writer.Write(dataLength);
        for (int i = 0; i < samples; i++) {
            double envelope = Math.Min(1.0, i / (sampleRate * .025)) *
                              Math.Min(1.0, (samples - i) / (sampleRate * .06));
            short value = (short)(Math.Sin(2 * Math.PI * frequency * i / sampleRate) * 9000 * envelope);
            writer.Write(value);
        }
        writer.Flush(); stream.Position = 0; return stream;
    }
}
'@

$script:AppName = 'MiniClock'
$script:AppVersion = [Version]'1.5.0'
$script:LatestReleaseApi = 'https://api.github.com/repos/Abohola/MiniClock/releases/latest'
$script:SettingsDir = Join-Path $env:APPDATA $script:AppName
$script:SettingsFile = Join-Path $script:SettingsDir 'settings.json'
$script:StartupLink = Join-Path ([Environment]::GetFolderPath('Startup')) 'MiniClock.lnk'
$script:Launcher = Join-Path $PSScriptRoot 'Launch MiniClock.vbs'
$script:Exiting = $false
$script:SettingsWindow = $null
$script:ToolsWindow = $null
$script:AlarmPopup = $null
$script:TimerRunning = $false
$script:TimerPausedSeconds = 0.0
$script:TimerEnd = $null
$script:Stopwatch = [System.Diagnostics.Stopwatch]::new()
$script:AlarmNames = @('Crystal', 'Digital', 'Gentle', 'Sunrise', 'Chime', 'Pulse', 'Retro', 'Urgent')

$script:ColorChoices = @(
    @('White', '#FFFFFFFF'), @('Warm', '#FFFFD38A'),
    @('Ice blue', '#FF8DDBFF'), @('Mint', '#FF8FFFC1'),
    @('Rose', '#FFFFA9C6'), @('Black', '#FF000000'),
    @('Silver', '#FFC9D1D9'), @('Slate', '#FF7D8A99'),
    @('Sky', '#FF45BFFF'), @('Ocean', '#FF168AAD'),
    @('Indigo', '#FF818CF8'), @('Violet', '#FFC084FC'),
    @('Magenta', '#FFFF5FD2'), @('Coral', '#FFFF7B72'),
    @('Orange', '#FFFF9F43'), @('Lemon', '#FFFFE66D'),
    @('Lime', '#FFB8F25B')
)

$script:Defaults = @{
    Left = 80.0; Top = 80.0; Scale = 1.0; Opacity = 0.88
    Use24Hour = $false; ShowSeconds = $true; ShowDate = $false
    Locked = $false; ClickThrough = $false; TextColor = '#FFFFFFFF'
    Shadow = $true; Theme = 'Glass'; AlarmSound = 'Crystal'
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

function Stop-MiniClock {
    $script:Exiting = $true
    Save-Settings
    if ($script:Tray) { $script:Tray.Visible = $false }
    $script:Window.Close()
    [System.Windows.Application]::Current.Shutdown()
}

function Check-ForUpdates {
    try {
        $release = Invoke-RestMethod -Uri $script:LatestReleaseApi -Headers @{ 'User-Agent' = 'MiniClock-Windows' }
        $latest = [Version]([string]$release.tag_name).TrimStart('v')
        if ($latest -le $script:AppVersion) {
            [void][System.Windows.Forms.MessageBox]::Show(
                "MiniClock $($script:AppVersion) is already the latest version.",
                'MiniClock Update', 'OK', 'Information'
            )
            return
        }
        $answer = [System.Windows.Forms.MessageBox]::Show(
            "MiniClock $latest is available.`n`nDownload and install it now?",
            'MiniClock Update', 'YesNo', 'Information'
        )
        if ($answer -ne 'Yes') { return }
        $asset = $release.assets | Where-Object { $_.name -eq 'MiniClockSetup.exe' } | Select-Object -First 1
        if (-not $asset) { throw 'The release does not contain MiniClockSetup.exe.' }
        $download = Join-Path $env:TEMP "MiniClockSetup-$latest.exe"
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $download -UseBasicParsing
        Start-Process -FilePath $download
        Stop-MiniClock
    } catch {
        [void][System.Windows.Forms.MessageBox]::Show(
            "MiniClock could not check for updates.`n`n$($_.Exception.Message)",
            'MiniClock Update', 'OK', 'Error'
        )
    }
}

function Uninstall-MiniClock {
    $uninstaller = Join-Path $PSScriptRoot 'unins000.exe'
    if (-not (Test-Path -LiteralPath $uninstaller)) {
        [void][System.Windows.Forms.MessageBox]::Show(
            'This is a portable copy. Exit MiniClock, then delete its folder to remove it.',
            'Uninstall MiniClock', 'OK', 'Information'
        )
        return
    }
    $answer = [System.Windows.Forms.MessageBox]::Show(
        'Remove MiniClock and its saved settings from this Windows account?',
        'Uninstall MiniClock', 'YesNo', 'Warning'
    )
    if ($answer -eq 'Yes') {
        Start-Process -FilePath $uninstaller
        Stop-MiniClock
    }
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
    $converter = [System.Windows.Media.BrushConverter]::new()
    $theme = [string]$script:Settings.Theme
    $background = '#01000000'
    $border = '#00FFFFFF'
    $textColor = [string]$script:Settings.TextColor
    $font = 'Segoe UI Semibold'
    $corner = 9
    $borderWidth = 0
    switch ($theme) {
        'Glass' {
            $background = '#B8233550'; $border = '#90BFEAFF'; $textColor = '#FFF4FBFF'
            $corner = 13; $borderWidth = 1
        }
        'Midnight Neon' {
            $background = '#DC070B1C'; $border = '#B12EDCFF'; $textColor = '#FF79E8FF'
            $corner = 10; $borderWidth = 1
        }
        'Warm Ember' {
            $background = '#D82B1114'; $border = '#AFFF9A62'; $textColor = '#FFFFD2A1'
            $corner = 12; $borderWidth = 1
        }
        'Matrix' {
            $background = '#E208120C'; $border = '#9B38FF7A'; $textColor = '#FF55FF88'
            $font = 'Cascadia Mono'; $corner = 4; $borderWidth = 1
        }
        'Minimal' {
            $background = '#01000000'; $border = '#00FFFFFF'; $textColor = '#FFFFFFFF'
        }
    }
    $brush = $converter.ConvertFromString($textColor)
    $script:TimeText.Foreground = $brush
    $script:DateText.Foreground = $brush
    $script:TimeText.FontFamily = [System.Windows.Media.FontFamily]::new($font)
    $script:DateText.FontFamily = [System.Windows.Media.FontFamily]::new($font)
    $script:HitArea.Background = $converter.ConvertFromString($background)
    $script:HitArea.BorderBrush = $converter.ConvertFromString($border)
    $script:HitArea.BorderThickness = [System.Windows.Thickness]::new($borderWidth)
    $script:HitArea.CornerRadius = [System.Windows.CornerRadius]::new($corner)
    $script:Glow.Opacity = if ($script:Settings.Shadow) { 0.72 } else { 0 }
    if ($theme -eq 'Midnight Neon') {
        $script:Glow.Color = [System.Windows.Media.ColorConverter]::ConvertFromString('#402EDCFF')
        $script:Glow.BlurRadius = 14
    } elseif ($theme -eq 'Warm Ember') {
        $script:Glow.Color = [System.Windows.Media.ColorConverter]::ConvertFromString('#55FF6B35')
        $script:Glow.BlurRadius = 12
    } else {
        $script:Glow.Color = [System.Windows.Media.Colors]::Black
        $script:Glow.BlurRadius = 9
    }
    if ($script:ThemeItems) {
        foreach ($key in @($script:ThemeItems.Keys)) {
            $script:ThemeItems[$key].Checked = ($key -eq $theme)
        }
    }
    $script:FormatItem.Checked = [bool]$script:Settings.Use24Hour
    $script:SecondsItem.Checked = [bool]$script:Settings.ShowSeconds
    $script:DateItem.Checked = [bool]$script:Settings.ShowDate
    $script:LockItem.Checked = [bool]$script:Settings.Locked
    Update-Clock
    $script:Window.SizeToContent = 'WidthAndHeight'
}

function Show-SettingsWindow {
    if ($script:SettingsWindow) {
        $script:SettingsWindow.Show()
        $script:SettingsWindow.Activate()
        return
    }
    [xml]$settingsXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="MiniClock Settings" Width="470" Height="650" WindowStyle="None"
        AllowsTransparency="True" WindowStartupLocation="CenterScreen" ResizeMode="NoResize"
        Background="Transparent" Foreground="#FFF4F8FF" FontFamily="Segoe UI" Topmost="True">
  <Window.Resources>
    <Style TargetType="TextBlock">
      <Setter Property="Foreground" Value="#FFF4F8FF"/><Setter Property="Margin" Value="0,7,0,4"/>
    </Style>
    <Style TargetType="ComboBox">
      <Setter Property="Height" Value="38"/><Setter Property="Margin" Value="0,0,0,5"/>
      <Setter Property="Foreground" Value="#FF0B1526"/><Setter Property="Background" Value="#FFF1F8FF"/>
      <Setter Property="BorderBrush" Value="#AA8CE8FF"/><Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="8,4"/><Setter Property="FontSize" Value="13"/>
    </Style>
    <Style TargetType="CheckBox">
      <Setter Property="Foreground" Value="#FFE8F5FF"/><Setter Property="FontSize" Value="13"/>
      <Setter Property="Margin" Value="0,8,22,8"/><Setter Property="VerticalContentAlignment" Value="Center"/>
    </Style>
    <Style TargetType="Slider">
      <Setter Property="Foreground" Value="#FF64D9FF"/><Setter Property="Margin" Value="4,2,4,4"/>
    </Style>
    <Style TargetType="Button">
      <Setter Property="Foreground" Value="White"/><Setter Property="Background" Value="#FF294A6A"/>
      <Setter Property="BorderBrush" Value="#886FDCFF"/><Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="16,9"/><Setter Property="Margin" Value="7,0,0,0"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Template">
        <Setter.Value><ControlTemplate TargetType="Button">
          <Border x:Name="ButtonSurface" CornerRadius="12" Background="{TemplateBinding Background}"
                  BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}"
                  Padding="{TemplateBinding Padding}">
            <Border.Effect><DropShadowEffect Color="#FF000000" BlurRadius="9" ShadowDepth="3" Opacity=".42"/></Border.Effect>
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="ButtonSurface" Property="Background" Value="#FF37698E"/></Trigger>
            <Trigger Property="IsPressed" Value="True"><Setter TargetName="ButtonSurface" Property="Opacity" Value=".75"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate></Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <Border CornerRadius="30" BorderThickness="1" BorderBrush="#B094E9FF" Padding="1">
    <Border.Background>
      <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
        <GradientStop Color="#F21A2942" Offset="0"/><GradientStop Color="#F00D1627" Offset=".55"/>
        <GradientStop Color="#F21D2744" Offset="1"/>
      </LinearGradientBrush>
    </Border.Background>
    <Border.Effect><DropShadowEffect Color="#FF000000" BlurRadius="38" ShadowDepth="10" Opacity=".7"/></Border.Effect>
    <Grid ClipToBounds="True">
      <Border Width="300" Height="105" CornerRadius="50" Background="#2842DFFF"
              HorizontalAlignment="Right" VerticalAlignment="Top" Margin="0,-28,-100,0">
        <Border.RenderTransform><SkewTransform AngleX="-22"/></Border.RenderTransform>
      </Border>
      <Ellipse Width="220" Height="220" Fill="#164DE9D2" HorizontalAlignment="Left"
               VerticalAlignment="Bottom" Margin="-105,0,0,-115"/>
      <Grid Margin="28,18,28,24">
        <Grid.RowDefinitions>
          <RowDefinition Height="64"/><RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/><RowDefinition Height="*"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <Grid x:Name="SettingsDragBar" Grid.Row="0">
          <StackPanel>
            <TextBlock Text="MiniClock" FontSize="26" FontWeight="SemiBold" Margin="0"/>
            <TextBlock x:Name="VersionText" Foreground="#FF9EC4E2" FontSize="12" Margin="0,1,0,0"/>
          </StackPanel>
          <Button x:Name="HeaderCloseButton" Content="X" Width="38" Height="34" Padding="0"
                  HorizontalAlignment="Right" VerticalAlignment="Top" FontSize="20"/>
        </Grid>
        <StackPanel Grid.Row="1">
          <TextBlock Text="THEME" Foreground="#FF9EC4E2" FontSize="11" FontWeight="SemiBold"/>
          <ComboBox x:Name="ThemeBox"/>
        </StackPanel>
        <StackPanel Grid.Row="2">
          <TextBlock Text="CUSTOM CLOCK COLOR" Foreground="#FF9EC4E2" FontSize="11" FontWeight="SemiBold"/>
          <ComboBox x:Name="ColorBox"/>
        </StackPanel>
        <Grid Grid.Row="3" Margin="0,8,0,0">
          <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition/></Grid.ColumnDefinitions>
          <StackPanel Grid.Column="0">
            <TextBlock Text="SIZE" Foreground="#FF9EC4E2" FontSize="11" FontWeight="SemiBold"/>
            <Slider x:Name="SizeSlider" Minimum="0.6" Maximum="2" TickFrequency="0.05" IsSnapToTickEnabled="True"/>
          </StackPanel>
          <StackPanel Grid.Column="1" Margin="22,0,0,0">
            <TextBlock Text="OPACITY" Foreground="#FF9EC4E2" FontSize="11" FontWeight="SemiBold"/>
            <Slider x:Name="OpacitySlider" Minimum="0.25" Maximum="1" TickFrequency="0.05" IsSnapToTickEnabled="True"/>
          </StackPanel>
        </Grid>
        <Border Grid.Row="4" Background="#481A304A" BorderBrush="#554FAFD0" BorderThickness="1"
                CornerRadius="16" Padding="14,7" Margin="0,16,0,0">
          <WrapPanel>
            <CheckBox x:Name="SecondsCheck" Content="Show seconds"/>
            <CheckBox x:Name="DateCheck" Content="Show date"/>
            <CheckBox x:Name="FormatCheck" Content="24-hour time"/>
            <CheckBox x:Name="ShadowCheck" Content="Text shadow"/>
            <CheckBox x:Name="LockCheck" Content="Lock position"/>
            <CheckBox x:Name="ClickCheck" Content="Click-through"/>
            <CheckBox x:Name="StartupCheck" Content="Run at startup"/>
          </WrapPanel>
        </Border>
        <Border Grid.Row="5" Background="#661C3553" BorderBrush="#556FDFFF" BorderThickness="1"
                CornerRadius="14" Padding="14" Margin="0,14,0,0">
          <TextBlock Text="Changes apply instantly. Close Settings whenever you like - MiniClock keeps running in the background."
                     TextWrapping="Wrap" Foreground="#FFD7EEFF" Margin="0" LineHeight="19"/>
        </Border>
        <StackPanel Grid.Row="8" Orientation="Horizontal" HorizontalAlignment="Right">
          <Button x:Name="ResetButton" Content="Reset position"/>
          <Button x:Name="CloseButton" Content="Close" IsDefault="True" Background="#FF2876A2"/>
        </StackPanel>
      </Grid>
    </Grid>
  </Border>
</Window>
'@
    $reader = New-Object System.Xml.XmlNodeReader $settingsXaml
    $window = [Windows.Markup.XamlReader]::Load($reader)
    $script:SettingsWindow = $window
    $themeBox = $window.FindName('ThemeBox')
    $colorBox = $window.FindName('ColorBox')
    foreach ($name in @('Glass', 'Midnight Neon', 'Warm Ember', 'Minimal', 'Matrix')) {
        $item = [System.Windows.Controls.ComboBoxItem]::new()
        $item.Content = $name; $item.Tag = $name
        [void]$themeBox.Items.Add($item)
        if ($script:Settings.Theme -eq $name) { $themeBox.SelectedItem = $item }
    }
    foreach ($choice in $script:ColorChoices) {
        $item = [System.Windows.Controls.ComboBoxItem]::new()
        $item.Content = $choice[0]; $item.Tag = $choice[1]
        [void]$colorBox.Items.Add($item)
        if ($script:Settings.TextColor -eq $choice[1]) { $colorBox.SelectedItem = $item }
    }
    $window.FindName('VersionText').Text = "Version $($script:AppVersion)  |  runs in the background"
    $sizeSlider = $window.FindName('SizeSlider'); $sizeSlider.Value = [double]$script:Settings.Scale
    $opacitySlider = $window.FindName('OpacitySlider'); $opacitySlider.Value = [double]$script:Settings.Opacity
    $secondsCheck = $window.FindName('SecondsCheck'); $secondsCheck.IsChecked = [bool]$script:Settings.ShowSeconds
    $dateCheck = $window.FindName('DateCheck'); $dateCheck.IsChecked = [bool]$script:Settings.ShowDate
    $formatCheck = $window.FindName('FormatCheck'); $formatCheck.IsChecked = [bool]$script:Settings.Use24Hour
    $shadowCheck = $window.FindName('ShadowCheck'); $shadowCheck.IsChecked = [bool]$script:Settings.Shadow
    $lockCheck = $window.FindName('LockCheck'); $lockCheck.IsChecked = [bool]$script:Settings.Locked
    $clickCheck = $window.FindName('ClickCheck'); $clickCheck.IsChecked = [bool]$script:Settings.ClickThrough
    $startupCheck = $window.FindName('StartupCheck'); $startupCheck.IsChecked = Test-Path -LiteralPath $script:StartupLink

    $window.FindName('SettingsDragBar').Add_MouseLeftButtonDown({ try { $window.DragMove() } catch {} }.GetNewClosure())
    $window.FindName('HeaderCloseButton').Add_Click({ $window.Close() }.GetNewClosure())
    $themeBox.Add_SelectionChanged({
        if ($themeBox.SelectedItem) { $script:Settings.Theme = [string]$themeBox.SelectedItem.Tag; Apply-Appearance; Save-Settings }
    }.GetNewClosure())
    $colorBox.Add_SelectionChanged({
        if ($colorBox.SelectedItem) { $script:Settings.TextColor = [string]$colorBox.SelectedItem.Tag; $script:Settings.Theme = 'Custom'; Apply-Appearance; Save-Settings }
    }.GetNewClosure())
    $sizeSlider.Add_ValueChanged({ $script:Settings.Scale = $sizeSlider.Value; Apply-Appearance; Save-Settings }.GetNewClosure())
    $opacitySlider.Add_ValueChanged({ $script:Settings.Opacity = $opacitySlider.Value; Apply-Appearance; Save-Settings }.GetNewClosure())
    $secondsCheck.Add_Click({ $script:Settings.ShowSeconds = $secondsCheck.IsChecked; Apply-Appearance; Save-Settings }.GetNewClosure())
    $dateCheck.Add_Click({ $script:Settings.ShowDate = $dateCheck.IsChecked; Apply-Appearance; Save-Settings }.GetNewClosure())
    $formatCheck.Add_Click({ $script:Settings.Use24Hour = $formatCheck.IsChecked; Apply-Appearance; Save-Settings }.GetNewClosure())
    $shadowCheck.Add_Click({ $script:Settings.Shadow = $shadowCheck.IsChecked; Apply-Appearance; Save-Settings }.GetNewClosure())
    $lockCheck.Add_Click({ $script:Settings.Locked = $lockCheck.IsChecked; Apply-Appearance; Save-Settings }.GetNewClosure())
    $clickCheck.Add_Click({ Set-ClickThrough ([bool]$clickCheck.IsChecked) }.GetNewClosure())
    $startupCheck.Add_Click({ Set-Startup ([bool]$startupCheck.IsChecked) }.GetNewClosure())
    $window.FindName('ResetButton').Add_Click({
        $area = [System.Windows.SystemParameters]::WorkArea
        $script:Window.Left = $area.Right - $script:Window.ActualWidth - 28
        $script:Window.Top = $area.Top + 28
        Save-Settings
    }.GetNewClosure())
    $window.FindName('CloseButton').Add_Click({ $window.Close() }.GetNewClosure())
    $window.Add_Closed({ $script:SettingsWindow = $null })
    $window.Show()
    $window.Activate()
}

function Show-AlarmPopup([string]$Title, [string]$Message) {
    if ($script:AlarmPopup) { $script:AlarmPopup.Close() }
    [xml]$popupXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="370" Height="145" WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" ShowInTaskbar="False" Topmost="True" ResizeMode="NoResize">
  <Border CornerRadius="22" BorderThickness="1" BorderBrush="#AA9BE7FF" Padding="18"
          Background="#F0182944">
    <Border.Effect><DropShadowEffect Color="#FF38C9FF" BlurRadius="24" ShadowDepth="2" Opacity=".48"/></Border.Effect>
    <Grid>
      <Grid.ColumnDefinitions><ColumnDefinition Width="54"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <Border Width="44" Height="44" CornerRadius="15" Background="#FF244D70" VerticalAlignment="Top">
        <TextBlock Text="⏱" FontSize="25" HorizontalAlignment="Center" VerticalAlignment="Center"/>
      </Border>
      <StackPanel Grid.Column="1" Margin="12,0,8,0">
        <TextBlock x:Name="PopupTitle" Foreground="White" FontSize="17" FontWeight="SemiBold"/>
        <TextBlock x:Name="PopupMessage" Foreground="#FFBFD8EC" FontSize="13" Margin="0,5,0,0" TextWrapping="Wrap"/>
      </StackPanel>
      <Button x:Name="DismissButton" Grid.Column="2" Content="×" Width="30" Height="30"
              FontSize="18" Foreground="White" Background="#334A6D8D" BorderThickness="0"/>
    </Grid>
  </Border>
</Window>
'@
    $reader = New-Object System.Xml.XmlNodeReader $popupXaml
    $popup = [Windows.Markup.XamlReader]::Load($reader)
    $script:AlarmPopup = $popup
    $popup.FindName('PopupTitle').Text = $Title
    $popup.FindName('PopupMessage').Text = $Message
    $popup.FindName('DismissButton').Add_Click({ $popup.Close() }.GetNewClosure())
    $popup.Add_Closed({ $script:AlarmPopup = $null })
    $area = [System.Windows.SystemParameters]::WorkArea
    $popup.Left = $area.Right - 390
    $popup.Top = $area.Bottom - 165
    $popup.Show()
    $popup.Activate()
    $dismissTimer = [System.Windows.Threading.DispatcherTimer]::new()
    $dismissTimer.Interval = [TimeSpan]::FromSeconds(10)
    $dismissTimer.Add_Tick({
        $dismissTimer.Stop()
        if ($popup.IsVisible) { $popup.Close() }
    }.GetNewClosure())
    $dismissTimer.Start()
}

function Play-SelectedAlarm {
    $index = [Array]::IndexOf($script:AlarmNames, [string]$script:Settings.AlarmSound)
    if ($index -lt 0) { $index = 0 }
    [MiniClockSounds]::Play($index)
}

function Update-TimeTools {
    $remaining = $script:TimerPausedSeconds
    if ($script:TimerRunning -and $script:TimerEnd) {
        $remaining = ($script:TimerEnd - [DateTime]::Now).TotalSeconds
        if ($remaining -le 0) {
            $remaining = 0
            $script:TimerRunning = $false
            $script:TimerEnd = $null
            $script:TimerPausedSeconds = 0
            Play-SelectedAlarm
            Show-AlarmPopup 'Timer complete' 'Your MiniClock countdown has finished.'
        }
    }
    if ($script:ToolsControls) {
        $safe = [Math]::Max(0, $remaining)
        $span = [TimeSpan]::FromSeconds($safe)
        $script:ToolsControls.TimerDisplay.Text = '{0:00}:{1:00}:{2:00}' -f [Math]::Floor($span.TotalHours), $span.Minutes, $span.Seconds
        $script:ToolsControls.TimerStart.Content = if ($script:TimerRunning) { 'Pause' } elseif ($safe -gt 0) { 'Resume' } else { 'Start timer' }
        $elapsed = $script:Stopwatch.Elapsed
        $script:ToolsControls.StopwatchDisplay.Text = '{0:00}:{1:00}:{2:00}.{3:0}' -f [Math]::Floor($elapsed.TotalHours), $elapsed.Minutes, $elapsed.Seconds, [Math]::Floor($elapsed.Milliseconds / 100)
        $script:ToolsControls.StopwatchStart.Content = if ($script:Stopwatch.IsRunning) { 'Pause' } else { 'Start' }
    }
}

function Show-TimeTools {
    if ($script:ToolsWindow) {
        $script:ToolsWindow.Show()
        $script:ToolsWindow.Activate()
        return
    }
    [xml]$toolsXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="500" Height="590" WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" ResizeMode="NoResize" WindowStartupLocation="CenterScreen"
        Topmost="True" ShowInTaskbar="True" FontFamily="Segoe UI">
  <Window.Resources>
    <Style x:Key="ClayButton" TargetType="Button">
      <Setter Property="Foreground" Value="White"/><Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Background" Value="#FF315475"/><Setter Property="BorderBrush" Value="#886FD8FF"/>
      <Setter Property="BorderThickness" Value="1"/><Setter Property="Padding" Value="18,10"/>
      <Setter Property="Margin" Value="5"/>
      <Setter Property="Template">
        <Setter.Value><ControlTemplate TargetType="Button">
          <Border x:Name="B" CornerRadius="14" Background="{TemplateBinding Background}"
                  BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}"
                  Padding="{TemplateBinding Padding}">
            <Border.Effect><DropShadowEffect Color="#FF000000" BlurRadius="8" ShadowDepth="3" Opacity=".35"/></Border.Effect>
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="Background" Value="#FF3D6B91"/></Trigger>
            <Trigger Property="IsPressed" Value="True"><Setter TargetName="B" Property="RenderTransform"><Setter.Value><ScaleTransform ScaleX=".97" ScaleY=".97"/></Setter.Value></Setter></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate></Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="TextBox">
      <Setter Property="Background" Value="#66101A29"/><Setter Property="Foreground" Value="White"/>
      <Setter Property="BorderBrush" Value="#775ACBEE"/><Setter Property="BorderThickness" Value="1"/>
      <Setter Property="FontSize" Value="22"/><Setter Property="TextAlignment" Value="Center"/>
      <Setter Property="Padding" Value="8"/><Setter Property="Margin" Value="5"/>
    </Style>
  </Window.Resources>
  <Border CornerRadius="28" BorderThickness="1" BorderBrush="#AA95E9FF" Background="#F0162339" Padding="1">
    <Border.Effect><DropShadowEffect Color="#FF000000" BlurRadius="35" ShadowDepth="8" Opacity=".65"/></Border.Effect>
    <Grid ClipToBounds="True">
      <Border Width="260" Height="90" Background="#2247DFFF" CornerRadius="40"
              HorizontalAlignment="Right" VerticalAlignment="Top" Margin="0,-18,-80,0">
        <Border.RenderTransform><SkewTransform AngleX="-18"/></Border.RenderTransform>
      </Border>
      <Grid Margin="22,16">
        <Grid.RowDefinitions><RowDefinition Height="54"/><RowDefinition Height="48"/><RowDefinition Height="*"/></Grid.RowDefinitions>
        <Grid x:Name="DragBar" Grid.Row="0">
          <TextBlock Text="MiniClock Time Tools" Foreground="White" FontSize="21" FontWeight="SemiBold" VerticalAlignment="Center"/>
          <Button x:Name="CloseTools" Content="×" Width="38" Height="34" HorizontalAlignment="Right"
                  Foreground="White" Background="#443D5A76" BorderThickness="0" FontSize="20"/>
        </Grid>
        <Grid Grid.Row="1">
          <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition/></Grid.ColumnDefinitions>
          <Button x:Name="TimerTab" Grid.Column="0" Content="COUNTDOWN TIMER" Style="{StaticResource ClayButton}" Padding="8"/>
          <Button x:Name="StopwatchTab" Grid.Column="1" Content="STOPWATCH" Style="{StaticResource ClayButton}" Padding="8"/>
        </Grid>
        <Grid Grid.Row="2">
          <Grid x:Name="TimerPanel">
            <StackPanel VerticalAlignment="Center">
              <TextBlock x:Name="TimerDisplay" Text="00:00:00" Foreground="#FFF5FBFF" FontFamily="Cascadia Mono"
                         FontSize="56" FontWeight="Light" HorizontalAlignment="Center" Margin="0,10"/>
              <TextBlock Text="SET HOURS · MINUTES · SECONDS" Foreground="#FF8FA9C2" FontSize="11" HorizontalAlignment="Center"/>
              <Grid Margin="40,5">
                <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="24"/><ColumnDefinition/><ColumnDefinition Width="24"/><ColumnDefinition/></Grid.ColumnDefinitions>
                <TextBox x:Name="HoursBox" Grid.Column="0" Text="0"/>
                <TextBlock Grid.Column="1" Text=":" Foreground="White" FontSize="25" VerticalAlignment="Center" HorizontalAlignment="Center"/>
                <TextBox x:Name="MinutesBox" Grid.Column="2" Text="5"/>
                <TextBlock Grid.Column="3" Text=":" Foreground="White" FontSize="25" VerticalAlignment="Center" HorizontalAlignment="Center"/>
                <TextBox x:Name="SecondsBox" Grid.Column="4" Text="0"/>
              </Grid>
              <TextBlock Text="ALARM SOUND" Foreground="#FF8FA9C2" FontSize="11" Margin="45,10,45,2"/>
              <Grid Margin="40,0">
                <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="105"/></Grid.ColumnDefinitions>
                <ComboBox x:Name="SoundBox" Height="36" Margin="5" FontSize="14"/>
                <Button x:Name="TestSound" Grid.Column="1" Content="Preview" Style="{StaticResource ClayButton}" Padding="8"/>
              </Grid>
              <StackPanel Orientation="Horizontal" HorizontalAlignment="Center" Margin="0,8">
                <Button x:Name="TimerStart" Content="Start timer" Style="{StaticResource ClayButton}" MinWidth="135"/>
                <Button x:Name="TimerReset" Content="Reset" Style="{StaticResource ClayButton}" MinWidth="95"/>
              </StackPanel>
            </StackPanel>
          </Grid>
          <Grid x:Name="StopwatchPanel" Visibility="Collapsed">
            <StackPanel VerticalAlignment="Center">
              <TextBlock x:Name="StopwatchDisplay" Text="00:00:00.0" Foreground="#FFF5FBFF" FontFamily="Cascadia Mono"
                         FontSize="53" FontWeight="Light" HorizontalAlignment="Center" Margin="0,18"/>
              <StackPanel Orientation="Horizontal" HorizontalAlignment="Center">
                <Button x:Name="StopwatchStart" Content="Start" Style="{StaticResource ClayButton}" MinWidth="120"/>
                <Button x:Name="LapButton" Content="Lap" Style="{StaticResource ClayButton}" MinWidth="90"/>
                <Button x:Name="StopwatchReset" Content="Reset" Style="{StaticResource ClayButton}" MinWidth="90"/>
              </StackPanel>
              <Border Background="#55101A29" BorderBrush="#555ACBEE" BorderThickness="1" CornerRadius="14" Margin="35,15" Padding="8">
                <ListBox x:Name="LapList" Height="175" Background="Transparent" Foreground="#FFD9ECFA" BorderThickness="0"/>
              </Border>
            </StackPanel>
          </Grid>
        </Grid>
      </Grid>
    </Grid>
  </Border>
</Window>
'@
    $reader = New-Object System.Xml.XmlNodeReader $toolsXaml
    $window = [Windows.Markup.XamlReader]::Load($reader)
    $script:ToolsWindow = $window
    $names = @('TimerPanel','StopwatchPanel','TimerDisplay','StopwatchDisplay','TimerStart','StopwatchStart',
        'HoursBox','MinutesBox','SecondsBox','SoundBox','LapList')
    $script:ToolsControls = @{}
    foreach ($name in $names) { $script:ToolsControls[$name] = $window.FindName($name) }
    $soundBox = $script:ToolsControls.SoundBox
    foreach ($sound in $script:AlarmNames) { [void]$soundBox.Items.Add($sound) }
    $soundBox.SelectedItem = [string]$script:Settings.AlarmSound
    if ($soundBox.SelectedIndex -lt 0) { $soundBox.SelectedIndex = 0 }
    $window.FindName('DragBar').Add_MouseLeftButtonDown({ try { $window.DragMove() } catch {} }.GetNewClosure())
    $window.FindName('CloseTools').Add_Click({ $window.Close() }.GetNewClosure())
    $window.FindName('TimerTab').Add_Click({
        $script:ToolsControls.TimerPanel.Visibility = 'Visible'; $script:ToolsControls.StopwatchPanel.Visibility = 'Collapsed'
    })
    $window.FindName('StopwatchTab').Add_Click({
        $script:ToolsControls.TimerPanel.Visibility = 'Collapsed'; $script:ToolsControls.StopwatchPanel.Visibility = 'Visible'
    })
    $soundBox.Add_SelectionChanged({
        if ($soundBox.SelectedItem) { $script:Settings.AlarmSound = [string]$soundBox.SelectedItem; Save-Settings }
    }.GetNewClosure())
    $window.FindName('TestSound').Add_Click({ Play-SelectedAlarm })
    $script:ToolsControls.TimerStart.Add_Click({
        if ($script:TimerRunning) {
            $script:TimerPausedSeconds = [Math]::Max(0, ($script:TimerEnd - [DateTime]::Now).TotalSeconds)
            $script:TimerRunning = $false; $script:TimerEnd = $null
        } else {
            $seconds = $script:TimerPausedSeconds
            if ($seconds -le 0) {
                $hours = $script:ToolsControls.HoursBox.Text -as [int]
                $minutes = $script:ToolsControls.MinutesBox.Text -as [int]
                $secs = $script:ToolsControls.SecondsBox.Text -as [int]
                $seconds = [Math]::Max(0, ($hours * 3600) + ($minutes * 60) + $secs)
            }
            if ($seconds -gt 0) {
                $script:TimerPausedSeconds = $seconds
                $script:TimerEnd = [DateTime]::Now.AddSeconds($seconds)
                $script:TimerRunning = $true
            }
        }
        Update-TimeTools
    })
    $window.FindName('TimerReset').Add_Click({
        $script:TimerRunning = $false; $script:TimerEnd = $null; $script:TimerPausedSeconds = 0
        Update-TimeTools
    })
    $script:ToolsControls.StopwatchStart.Add_Click({
        if ($script:Stopwatch.IsRunning) { $script:Stopwatch.Stop() } else { $script:Stopwatch.Start() }
        Update-TimeTools
    })
    $window.FindName('StopwatchReset').Add_Click({
        $script:Stopwatch.Reset(); $script:ToolsControls.LapList.Items.Clear(); Update-TimeTools
    })
    $window.FindName('LapButton').Add_Click({
        $lap = $script:Stopwatch.Elapsed
        $number = $script:ToolsControls.LapList.Items.Count + 1
        [void]$script:ToolsControls.LapList.Items.Insert(0, ('Lap {0:00}     {1:00}:{2:00}:{3:00}.{4:0}' -f $number, [Math]::Floor($lap.TotalHours), $lap.Minutes, $lap.Seconds, [Math]::Floor($lap.Milliseconds / 100)))
    })
    $window.Add_Closed({ $script:ToolsWindow = $null; $script:ToolsControls = $null })
    Update-TimeTools
    $window.Show()
    $window.Activate()
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
$toolsItem = New-MenuItem 'Timer && stopwatch...' { Show-TimeTools }
$settingsItem = New-MenuItem 'Settings...' { Show-SettingsWindow }
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

$themeMenu = [System.Windows.Forms.ToolStripMenuItem]::new('Theme')
$script:ThemeItems = @{}
foreach ($themeName in @('Glass', 'Midnight Neon', 'Warm Ember', 'Minimal', 'Matrix')) {
    $value = $themeName
    $item = New-MenuItem $themeName ({
        $script:Settings.Theme = $value
        Apply-Appearance; Save-Settings
    }.GetNewClosure())
    $script:ThemeItems[$themeName] = $item
    [void]$themeMenu.DropDownItems.Add($item)
}

$colorMenu = [System.Windows.Forms.ToolStripMenuItem]::new('Color')
foreach ($entry in $script:ColorChoices) {
    $label = $entry[0]; $value = $entry[1]
    $item = New-MenuItem $label ({
        $script:Settings.TextColor = $value
        $script:Settings.Theme = 'Custom'
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
$updateItem = New-MenuItem 'Check for updates...' { Check-ForUpdates }
$uninstallItem = New-MenuItem 'Uninstall MiniClock...' { Uninstall-MiniClock }
$exitItem = New-MenuItem 'Exit MiniClock' { Stop-MiniClock }

foreach ($item in @(
    $showItem, $toolsItem, $settingsItem, (New-Object System.Windows.Forms.ToolStripSeparator),
    $script:FormatItem, $script:SecondsItem, $script:DateItem,
    $themeMenu, $sizeMenu, $opacityMenu, $colorMenu, $shadowItem,
    (New-Object System.Windows.Forms.ToolStripSeparator),
    $script:LockItem, $script:ClickItem, $script:StartupItem, $resetItem,
    (New-Object System.Windows.Forms.ToolStripSeparator), $updateItem, $uninstallItem,
    (New-Object System.Windows.Forms.ToolStripSeparator), $hideItem, $exitItem
)) { [void]$menu.Items.Add($item) }

$script:Tray = [System.Windows.Forms.NotifyIcon]::new()
$script:Tray.Text = 'MiniClock'
$iconPath = Join-Path $PSScriptRoot 'assets\MiniClock.ico'
$script:Tray.Icon = if (Test-Path -LiteralPath $iconPath) {
    [System.Drawing.Icon]::new($iconPath)
} else {
    [System.Drawing.SystemIcons]::Information
}
$script:Tray.ContextMenuStrip = $menu
$script:Tray.Visible = $true
$script:Tray.Add_DoubleClick({ $script:Window.Show(); $script:Window.Activate() })

$script:Window.Left = [double]$script:Settings.Left
$script:Window.Top = [double]$script:Settings.Top
$script:Window.Add_MouseLeftButtonDown({
    if ($_.ClickCount -ge 2) {
        Show-TimeTools
        $_.Handled = $true
        return
    }
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
$timer.Add_Tick({ Update-Clock; Update-TimeTools })
$timer.Start()

Apply-Appearance
$script:StartupItem.Checked = Test-Path -LiteralPath $script:StartupLink
$app = [System.Windows.Application]::new()
if ($OpenTools) {
    $script:Window.Add_ContentRendered({ Show-TimeTools })
} elseif ($OpenSettings) {
    $script:Window.Add_ContentRendered({ Show-SettingsWindow })
} elseif ($StartHidden) {
    $script:Window.Add_ContentRendered({ $script:Window.Hide() })
}
[void]$app.Run($script:Window)

$timer.Stop()
$script:Tray.Dispose()
