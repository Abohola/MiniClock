#define MyAppName "MiniClock"
#define MyAppVersion "1.1.0"
#define MyAppPublisher "Abohola"
#define MyAppURL "https://github.com/Abohola/MiniClock"

[Setup]
AppId={{BBE4C07E-D27B-49BB-A8F7-9BB4E03D6227}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}/issues
AppUpdatesURL={#MyAppURL}/releases
DefaultDirName={localappdata}\Programs\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=dist
OutputBaseFilename=MiniClockSetup
SetupIconFile=assets\MiniClock.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
SetupLogging=yes
UninstallDisplayName={#MyAppName}
UninstallDisplayIcon={app}\assets\MiniClock.ico
VersionInfoVersion={#MyAppVersion}
VersionInfoDescription=Transparent always-on-top clock for Windows
VersionInfoProductName={#MyAppName}
VersionInfoCompany={#MyAppPublisher}
VersionInfoCopyright=Copyright (c) 2026 {#MyAppPublisher}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked
Name: "startup"; Description: "Start MiniClock when I sign in"; GroupDescription: "Startup:"; Flags: unchecked

[Files]
Source: "MiniClock.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "Launch MiniClock.vbs"; DestDir: "{app}"; Flags: ignoreversion
Source: "Start MiniClock.cmd"; DestDir: "{app}"; Flags: ignoreversion
Source: "README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "assets\MiniClock.ico"; DestDir: "{app}\assets"; Flags: ignoreversion
Source: "assets\MiniClock-logo.png"; DestDir: "{app}\assets"; Flags: ignoreversion

[Icons]
Name: "{group}\MiniClock"; Filename: "{sys}\wscript.exe"; Parameters: """{app}\Launch MiniClock.vbs"""; WorkingDir: "{app}"; IconFilename: "{app}\assets\MiniClock.ico"
Name: "{group}\Uninstall MiniClock"; Filename: "{uninstallexe}"
Name: "{autodesktop}\MiniClock"; Filename: "{sys}\wscript.exe"; Parameters: """{app}\Launch MiniClock.vbs"""; WorkingDir: "{app}"; IconFilename: "{app}\assets\MiniClock.ico"; Tasks: desktopicon
Name: "{userstartup}\MiniClock"; Filename: "{sys}\wscript.exe"; Parameters: """{app}\Launch MiniClock.vbs"""; WorkingDir: "{app}"; IconFilename: "{app}\assets\MiniClock.ico"; Tasks: startup

[Run]
Filename: "{sys}\wscript.exe"; Parameters: """{app}\Launch MiniClock.vbs"""; Description: "Launch MiniClock"; WorkingDir: "{app}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"
