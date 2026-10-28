; Just Say It for Windows – installer script (Inno Setup 6)
; Created by Stefano Roman Gunness · MIT License
; https://github.com/stefanoromang/just-say-it

#define AppName "Just Say It"
#define AppVersion "1.3.0"
#define AppPublisher "Stefano Roman Gunness"
#define AppURL "https://github.com/stefanoromang/just-say-it"
#define AppExe "JustSayIt.exe"

[Setup]
AppId={{22064789-62B4-4449-A17E-71247FF9F29B}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}/issues
AppCopyright=© 2026 Stefano Roman Gunness
VersionInfoCompany={#AppPublisher}
VersionInfoCopyright=© 2026 Stefano Roman Gunness
VersionInfoDescription={#AppName} Setup
DefaultDirName={localappdata}\Programs\JustSayIt
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\dist
OutputBaseFilename=JustSayIt-Setup-{#AppVersion}
SetupIconFile=..\JustSayIt\AppIcon.ico
UninstallDisplayIcon={app}\{#AppExe}
LicenseFile=..\..\LICENSE
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.19041
CloseApplications=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Shortcuts:"
Name: "startup"; Description: "Start Just Say It when Windows starts"; GroupDescription: "Startup:"

[Files]
Source: "..\dist\JustSayIt\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"; Comment: "Free, private voice typing – by Stefano Roman Gunness"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "JustSayIt"; ValueData: """{app}\{#AppExe}"" --background"; Flags: uninsdeletevalue; Tasks: startup

[Run]
Filename: "{app}\{#AppExe}"; Description: "Launch Just Say It"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{sys}\taskkill.exe"; Parameters: "/F /IM {#AppExe}"; Flags: runhidden; RunOnceId: "KillApp"

[UninstallDelete]
Type: filesandordirs; Name: "{app}"
