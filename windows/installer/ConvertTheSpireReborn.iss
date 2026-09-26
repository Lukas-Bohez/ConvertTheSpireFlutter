; Convert the Spire Reborn - Windows installer (Inno Setup 6).
;
; Builds ConvertTheSpireReborn-Setup.exe: one file with the whole app in it,
; so installing needs no network. It installs for the current user only, into
; %LOCALAPPDATA%\Programs\ConvertTheSpireReborn (the folder install.ps1 used,
; so those installs are upgraded in place), without administrator rights, and
; adds a Start menu entry and an entry in Settings > Apps to uninstall it.
;
; The app updates itself by downloading the next Setup.exe and running it
; with /VERYSILENT /SUPPRESSMSGBOXES /NORESTART: Setup closes the running app,
; replaces the files and starts the app again.
;
; Build (the release workflow does this):
;   ISCC.exe /DAppVersion=15.2.0 /DSourceDir=<Release folder> ^
;            /DOutputDir=<folder> windows\installer\ConvertTheSpireReborn.iss

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\build\installer"
#endif

#define AppName "Convert the Spire Reborn"
#define AppExe "convert_the_spire_reborn.exe"

[Setup]
; Never change AppId: it is how Setup recognises an installed copy to update.
AppId={{6B2F3E6A-3C1D-4E8B-9A57-2F0C7D51A9E4}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=Lukas Bohez
AppCopyright=Copyright (C) 2026 Lukas Bohez. Licensed under the GNU GPL v3.
; Version resource of Setup.exe itself. Code signing (docs/signing/signpath.md)
; checks product name and version, and they must match the app's own.
VersionInfoVersion={#AppVersion}
VersionInfoTextVersion={#AppVersion}
VersionInfoProductName=Convert The Spire Reborn
VersionInfoProductVersion={#AppVersion}
VersionInfoProductTextVersion={#AppVersion}
VersionInfoCompany=Lukas Bohez
VersionInfoCopyright=Copyright (C) 2026 Lukas Bohez. Licensed under the GNU GPL v3.
VersionInfoDescription=Convert The Spire Reborn Setup
AppPublisherURL=https://github.com/Lukas-Bohez/ConvertTheSpireFlutter
AppSupportURL=https://github.com/Lukas-Bohez/ConvertTheSpireFlutter/issues
AppUpdatesURL=https://github.com/Lukas-Bohez/ConvertTheSpireFlutter/releases/latest
DefaultDirName={localappdata}\Programs\ConvertTheSpireReborn
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
DisableDirPage=yes
DisableReadyPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=ConvertTheSpireReborn-Setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; Close a running copy (also when updating silently) instead of asking.
CloseApplications=force
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[InstallDelete]
; A new version replaces the old one completely: no DLL or asset from an older
; build may stay behind (issue #12 was a leftover DLL that Defender flagged).
Type: filesandordirs; Name: "{app}\data"
Type: filesandordirs; Name: "{app}\dll"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
; After a normal install: the usual "Launch" checkbox on the last page.
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
; After a silent install (the app updating itself): start the app again.
; /NOLAUNCH=1 skips that (the release workflow's install test).
Filename: "{app}\{#AppExe}"; Flags: nowait; Check: RelaunchAfterSilentInstall

[Registry]
; The app registers itself for "Open with" at every start
; (windows/runner/open_requests.cpp). Remove that again on uninstall.
Root: HKCU; Subkey: "Software\Classes\ConvertTheSpireReborn.Media"; Flags: dontcreatekey uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\ConvertTheSpireReborn.Torrent"; Flags: dontcreatekey uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\ConvertTheSpireReborn.Magnet"; Flags: dontcreatekey uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Applications\{#AppExe}"; Flags: dontcreatekey uninsdeletekey
Root: HKCU; Subkey: "Software\ConvertTheSpireReborn"; Flags: dontcreatekey uninsdeletekey
Root: HKCU; Subkey: "Software\RegisteredApplications"; ValueType: none; ValueName: "{#AppName}"; Flags: dontcreatekey uninsdeletevalue

[Code]
function RelaunchAfterSilentInstall: Boolean;
begin
  Result := WizardSilent and (ExpandConstant('{param:NOLAUNCH|0}') = '0');
end;

// Setup closes a running copy through the Restart Manager (CloseApplications),
// but the uninstaller does not: a copy left running keeps its files locked
// and they would stay behind. Close it first.
function InitializeUninstall(): Boolean;
var
  ResultCode: Integer;
begin
  if Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM {#AppExe}', '', SW_HIDE,
    ewWaitUntilTerminated, ResultCode) then
    Log('Closed the running app (taskkill exit ' + IntToStr(ResultCode) + ')')
  else
    Log('Could not run taskkill: ' + SysErrorMessage(ResultCode));
  Sleep(1000);
  Result := True;
end;
