; Build the Flutter release first, then compile with Inno Setup 6.
#ifndef BundleDir
  #define BundleDir SourcePath + "build\windows\x64\runner\Release"
#endif
#define AppExe "comfer_wallpaper.exe"
#if !FileExists(BundleDir + "\" + AppExe)
  #error "Build the Windows release first: flutter build windows --release"
#endif
#if !FileExists(BundleDir + "\flutter_windows.dll") || !FileExists(BundleDir + "\data\app.so") || !FileExists(BundleDir + "\data\icudtl.dat")
  #error "Incomplete Flutter release bundle."
#endif
#if !FileExists(BundleDir + "\msvcp140.dll") || !FileExists(BundleDir + "\msvcp140_1.dll") || !FileExists(BundleDir + "\msvcp140_2.dll") || !FileExists(BundleDir + "\vcruntime140.dll") || !FileExists(BundleDir + "\vcruntime140_1.dll")
  #error "Missing bundled Visual C++ runtime DLLs. Rebuild the Windows release."
#endif
#define AppVersion GetVersionNumbersString(BundleDir + "\" + AppExe)

[Setup]
; Keep the original AppId stable even though the display name has improved.
AppId=ComferWalls
AppName=Comfer Wallpaper
AppVersion={#AppVersion}
AppPublisher=Jeerovan
DefaultDirName={localappdata}\Programs\ComferWallpaper
DefaultGroupName=Comfer Wallpaper
PrivilegesRequired=lowest
DisableProgramGroupPage=yes
OutputDir=Output
OutputBaseFilename=ComferWallpaper-{#AppVersion}-windows-x64-setup
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
SetupIconFile=windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
SetupLogging=yes
SetupMutex=ComferWallpaperSetup
; Use the app's journal-aware shutdown instead of Restart Manager termination.
CloseApplications=no
RestartApplications=no

[Tasks]
Name: "startup"; Description: "Start Comfer Wallpaper when I sign in"; GroupDescription: "Startup:"; Check: IsNewInstallation
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"; Flags: unchecked

[Files]
; Includes Flutter assets, plugins and the app-local Visual C++ runtime once.
Source: "{#BundleDir}\*"; DestDir: "{app}"; Excludes: "*.pdb,*.lib,*.exp"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Comfer Wallpaper"; Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"
Name: "{autodesktop}\Comfer Wallpaper"; Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"; Tasks: desktopicon

[Registry]
; Never overwrite Windows' StartupApproved state. A removed Run entry stays
; removed during upgrades. Delete only our own Run value on uninstall.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "ComferWallpaper"; ValueData: """{app}\{#AppExe}"" --background"; Flags: uninsdeletevalue; Check: RegisterStartup

[Run]
Filename: "{app}\{#AppExe}"; Parameters: "--background"; WorkingDir: "{app}"; Description: "Launch Comfer Wallpaper (look in the system tray or hidden-icons menu)"; Flags: nowait postinstall skipifsilent

[Code]
const
  RunKey = 'Software\Microsoft\Windows\CurrentVersion\Run';
  UninstallKey = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\';
  QuitMessage = $8000 + 73; // WM_APP + 73, shared with the Windows runner.
  SynchronizeAccess = $00100000;
  WaitObject0 = 0;

var
  StartupEnabled: Boolean;

function FindComferWindow(ClassName, WindowName: String): HWND;
  external 'FindWindowW@user32.dll stdcall';
function WindowProcessId(Window: HWND; var ProcessId: Cardinal): Cardinal;
  external 'GetWindowThreadProcessId@user32.dll stdcall';
function OpenProcess(Access: Cardinal; Inherit: Boolean; ProcessId: Cardinal): THandle;
  external 'OpenProcess@kernel32.dll stdcall';
function WaitForSingleObject(Handle: THandle; Milliseconds: Cardinal): Cardinal;
  external 'WaitForSingleObject@kernel32.dll stdcall';
function CloseHandle(Handle: THandle): Boolean;
  external 'CloseHandle@kernel32.dll stdcall';

function IsNewInstallation: Boolean;
begin
  Result := not FileExists(ExpandConstant('{app}\{#AppExe}'));
end;

function RegisterStartup: Boolean;
begin
  Result := StartupEnabled;
end;

function StopComfer: Boolean;
var
  Window: HWND;
  ProcessId: Cardinal;
  Process: THandle;
begin
  Result := True;
  Window := FindComferWindow('FLUTTER_RUNNER_WIN32_WINDOW', 'Comfer Wallpaper');
  if Window = 0 then Exit;
  Result := False;
  ProcessId := 0;
  WindowProcessId(Window, ProcessId);
  if ProcessId = 0 then Exit;
  Process := OpenProcess(SynchronizeAccess, False, ProcessId);
  if Process = 0 then Exit;
  try
    Log('Requesting graceful Comfer shutdown.');
    if PostMessage(Window, QuitMessage, 0, 0) then
      Result := WaitForSingleObject(Process, 15000) = WaitObject0;
    if not Result then Log('Comfer did not exit safely; refusing to modify its files.');
  finally
    CloseHandle(Process);
  end;
end;

function InitializeSetup: Boolean;
begin
  // Do not create a second installation beside an older packaging method.
  Result := not (
    RegKeyExists(HKLM64, UninstallKey + 'ComferWalls_is1') or
    RegKeyExists(HKLM32, UninstallKey + 'ComferWalls_is1') or
    RegKeyExists(HKCU, UninstallKey + 'ComferWallpaper'));
  if not Result then
    SuppressibleMsgBox(
      'An older machine-wide or PowerShell installation exists. Uninstall it first, then run this per-user installer. Your wallpaper and preferences will be preserved.',
      mbError, MB_OK, IDOK);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  // Capture before copying files, otherwise every install looks like an upgrade.
  StartupEnabled := RegValueExists(HKCU, RunKey, 'ComferWallpaper') or
    (IsNewInstallation and WizardIsTaskSelected('startup'));
  if not StopComfer then
    Result := 'Comfer is still running. Quit it from its tray menu and retry. No application files have been replaced.';
end;

function InitializeUninstall: Boolean;
begin
  Result := StopComfer;
  if not Result then
    SuppressibleMsgBox(
      'Comfer is still running. Quit it from its tray menu and retry uninstall.',
      mbError, MB_OK, IDOK);
  // Inno only removes installed files. Never delete application-support data:
  // Windows may still be using the managed wallpaper after uninstall.
end;

