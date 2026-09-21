[Setup]
AppName=ComferWalls
AppVersion=0.2.0
DefaultDirName={autopf}\ComferWalls
DefaultGroupName=ComferWalls
OutputDir=Output
OutputBaseFilename=ComferWallsSetup
Compression=lzma
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
SetupIconFile=windows\runner\resources\app_icon.ico

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional icons:"

[Files]
Source: "build\windows\x64\runner\Release\comfer_wallpaper.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\ComferWalls"; Filename: "{app}\comfer_wallpaper.exe"
Name: "{autodesktop}\ComferWalls"; Filename: "{app}\comfer_wallpaper.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\comfer_wallpaper.exe"; Description: "Launch ComferWalls"; Flags: nowait postinstall skipifsilent