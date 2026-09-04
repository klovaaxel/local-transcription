; Inno Setup script for the Windows beta installer.
; Built by tool/package/build_windows.ps1, which passes MyAppVersion,
; MyBundleDir and MyOutputDir on the command line.

#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif
#ifndef MyBundleDir
  #define MyBundleDir "..\..\build\windows\x64\runner\Release"
#endif
#ifndef MyOutputDir
  #define MyOutputDir "..\..\dist"
#endif

#define MyAppName "Föreläsning"
#define MyAppPublisher "Axel Karlsson"
#define MyAppExeName "lecture_local.exe"
#define MyAppId "{{9C4B1A2E-7F3D-4E62-9A18-5D0C6B7E3F41}"

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
VersionInfoVersion={#MyAppVersion}

; Per-user install: no admin prompt, which matters for testers on a managed
; school or work laptop where they are not local administrators.
PrivilegesRequired=lowest
DefaultDirName={autopf}\Forelasning
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
UninstallDisplayName={#MyAppName}
UninstallDisplayIcon={app}\{#MyAppExeName}

OutputDir={#MyOutputDir}
OutputBaseFilename=Forelasning-{#MyAppVersion}-windows-x64-setup
Compression=lzma2/max
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
SetupLogging=yes

[Languages]
Name: "swedish"; MessagesFile: "compiler:Languages\Swedish.isl"

[Tasks]
Name: "desktopicon"; Description: "Skapa en genväg på skrivbordet"; GroupDescription: "Genvägar:"

[Files]
; The whole Flutter bundle: lecture_local.exe, the engine DLL, the plugin DLLs
; (sherpa-onnx, llama.cpp, record) and data\ with the Dart snapshot and assets.
Source: "{#MyBundleDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Starta {#MyAppName}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Only what the installer itself may leave behind. Recordings, transcripts and
; the downloaded models live under the user's app data and are deliberately
; kept: uninstalling must not throw away a teacher's lectures.
Type: filesandordirs; Name: "{app}"
