; Installer for the Dental Clinic client (the program for the other computers
; on the clinic network), see DentalClinicClient.cs and offline/README.md.
; Built by .github/workflows/offline-windows.yml (job "client"):
;   ISCC.exe setup.iss /DMyAppVersion=<offline build>
; Expects next to this file: DentalClinicClient.exe, the WebView2 dlls,
; x64\WebView2Loader.dll, x86\WebView2Loader.dll, icon.ico and
; MicrosoftEdgeWebview2Setup.exe (the Evergreen bootstrapper).
#ifndef MyAppVersion
  #define MyAppVersion "0"
#endif

#define MyAppName "Dental Clinic"
#define MyAppExeName "DentalClinicClient.exe"
; Fixed: the same id on every build so a new version installs over the old one.
#define MyAppId "{5E0B7C3A-2F64-4D8E-9A51-7C2D0F4B8E63}"

[Setup]
AppId={{#MyAppId}
AppName={#MyAppName}
AppVersion=1.0.{#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher=Dental Clinic
DefaultDirName={autopf}\Dental Clinic Client
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\{#MyAppExeName}
OutputDir=output
OutputBaseFilename=DentalClinicClientSetup-{#MyAppVersion}
SetupIconFile=icon.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ShowLanguageDialog=no
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64compatible
; The app updates itself with /SILENT; it closes first, this is the safety net.
CloseApplications=yes
RestartApplications=no

[Languages]
#if FileExists(AddBackslash(CompilerPath) + "Languages\Arabic.isl")
Name: "arabic"; MessagesFile: "compiler:Languages\Arabic.isl"
#endif
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "اختصار على سطح المكتب"; GroupDescription: "اختصارات:"

[Files]
Source: "DentalClinicClient.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "Microsoft.Web.WebView2.Core.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "Microsoft.Web.WebView2.WinForms.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "x64\WebView2Loader.dll"; DestDir: "{app}\x64"; Flags: ignoreversion
Source: "x86\WebView2Loader.dll"; DestDir: "{app}\x86"; Flags: ignoreversion
Source: "icon.ico"; DestDir: "{app}"; Flags: ignoreversion
Source: "MicrosoftEdgeWebview2Setup.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall; Check: NeedsWebView2

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\icon.ico"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\icon.ico"; Tasks: desktopicon

[Run]
; The browser engine, only when Windows does not have it yet (needs internet once).
Filename: "{tmp}\MicrosoftEdgeWebview2Setup.exe"; Parameters: "/silent /install"; StatusMsg: "تثبيت Microsoft Edge WebView2…"; Flags: waituntilterminated; Check: NeedsWebView2
; Saves the server typed below and trusts its certificate for the whole
; computer (elevated, so Windows asks nothing). On a silent update the saved
; settings stay as they are.
Filename: "{app}\{#MyAppExeName}"; Parameters: "--install-cert --server ""{code:ServerName}"" --ip ""{code:ServerIp}"""; StatusMsg: "تثبيت شهادة العيادة…"; Flags: runhidden waituntilterminated; Check: not WizardSilent
Filename: "{app}\{#MyAppExeName}"; Parameters: "--install-cert"; Flags: runhidden waituntilterminated; Check: WizardSilent
; No skipifsilent: the app reopens after updating itself.
Filename: "{app}\{#MyAppExeName}"; Description: "فتح Dental Clinic"; Flags: nowait postinstall runasoriginaluser

[Code]
var
  ServerPage: TInputQueryWizardPage;

function NeedsWebView2: Boolean;
var
  V: String;
begin
  Result := not (
    (RegQueryStringValue(HKLM, 'SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}', 'pv', V) and (V <> '') and (V <> '0.0.0.0')) or
    (RegQueryStringValue(HKLM, 'SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}', 'pv', V) and (V <> '') and (V <> '0.0.0.0')) or
    (RegQueryStringValue(HKCU, 'Software\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}', 'pv', V) and (V <> '') and (V <> '0.0.0.0')));
end;

procedure InitializeWizard;
begin
  ServerPage := CreateInputQueryPage(wpSelectTasks,
    'خادم العيادة', 'الحاسوب الذي يعمل عليه نظام العيادة (النسخة الأوفلاين)',
    'اترك الاسم clinic.lan إن لم تغيّره في config.txt على الخادم. اكتب عنوان IP للخادم إذا لم يعمل الاسم على هذا الحاسوب (تعرضه لوحة التشغيل)، أو اتركه فارغًا.');
  ServerPage.Add('اسم الخادم:', False);
  ServerPage.Add('عنوان IP للخادم (اختياري):', False);
  ServerPage.Values[0] := 'clinic.lan';
  ServerPage.Values[1] := '';
end;

function ServerName(Param: String): String;
begin
  Result := Trim(ServerPage.Values[0]);
  if Result = '' then Result := 'clinic.lan';
end;

function ServerIp(Param: String): String;
begin
  Result := Trim(ServerPage.Values[1]);
end;
