; Just Say It for Windows – installer script (Inno Setup 6)
; Created by Stefano Roman Gunness · MIT License
; https://github.com/stefanoromang/just-say-it

#define AppName "Just Say It"
#define AppVersion "1.9.0"
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
; Per-user install: never asks for an administrator password.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=
UsedUserAreasWarning=no
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
CloseApplications=force
RestartApplications=no

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
; Updates started from inside the app (with /RELAUNCH) restart it when they finish.
Filename: "{app}\{#AppExe}"; Parameters: "--background"; Flags: nowait; Check: ShouldRelaunch

[UninstallRun]
; Only closes this user's copy of the app (no admin rights needed).
Filename: "{sys}\taskkill.exe"; Parameters: "/F /IM {#AppExe} /FI ""USERNAME eq {username}"""; Flags: runhidden; RunOnceId: "KillApp"

[UninstallDelete]
Type: filesandordirs; Name: "{app}"

[Code]
function ShouldRelaunch: Boolean;
begin
  Result := WizardSilent and (Pos('/RELAUNCH', UpperCase(GetCmdTail)) > 0);
end;
