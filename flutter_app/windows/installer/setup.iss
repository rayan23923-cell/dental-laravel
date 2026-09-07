; Inno Setup script for the Dental Clinic App Windows desktop build.
;
; Build first, then compile:
;   flutter build windows --release --dart-define=API_BASE_URL=https://cdclinics.com/api/v1
;   "C:\Users\<you>\AppData\Local\Programs\Inno Setup 6\ISCC.exe" windows\installer\setup.iss /DMyAppVersion=1.0.1
;
; MyAppVersion must match pubspec.yaml's version (the part before "+") and
; config/desktop_releases.php's 'windows.version' — the running app compares
; against that config value, not this installer, to decide whether to
; self-update (see lib/core/updater/desktop_update_checker.dart).
#ifndef MyAppVersion
  #define MyAppVersion "1.0.1"
#endif

#define MyAppName "العيادة التعليمية"
#define MyAppExeName "dental_clinic_app.exe"
#define MyAppPublisher "كلية طب الأسنان - جامعة تكريت"
; Fixed GUID — do not change between releases, or Setup will treat every
; new version as a separate, side-by-side install instead of an in-place
; upgrade.
#define MyAppId "{8C6F0A2E-5B7C-4B8A-9E3F-2D1A6C4B7E90}"

[Setup]
AppId={{#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\Dental Clinic App
DefaultGroupName={#MyAppName}
UninstallDisplayIcon={app}\{#MyAppExeName}
OutputDir=..\..\build\windows\installer
OutputBaseFilename=DentalClinicSetup-{#MyAppVersion}
SetupIconFile=..\runner\resources\app_icon.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Silent self-updates (see DesktopUpdateChecker.downloadAndInstall) run this
; with /VERYSILENT — nothing below should ever require user interaction.
DisableWelcomePage=yes
; The updater exits our own process right before starting Setup, but this
; is a safety net for a manual re-run while the app happens to be open —
; Setup will close it (and, since it's the one closing it, restart it) via
; the Restart Manager rather than failing on a locked file.
CloseApplications=yes
RestartApplications=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional shortcuts:"

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
; No "skipifsilent" on purpose: a silent self-update should still relaunch
; the app afterwards, same as Telegram Desktop does post-update.
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall
