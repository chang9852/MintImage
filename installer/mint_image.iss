; MintImage Windows 安装脚本（Inno Setup 6）
;
; 用 ISCC.exe 编译，产物是允许自定义安装位置的 Setup.exe。
; 版本号与输入输出目录通过环境变量传入，便于 CI 复用：
;   MINTIMAGE_VERSION      版本号，例如 0.0.25
;   MINTIMAGE_RELEASE_DIR  flutter build windows 的 Release 目录
;   MINTIMAGE_OUTPUT_DIR   安装包输出目录
;
; 中文界面需要额外的 ChineseSimplified.isl（Inno Setup 默认不附带），
; 这里只用官方自带的语言文件，保证在任何机器上都能编译。

#define AppName "MintImage"
#define AppPublisher "com.aiqin"
#define AppExeName "mint_image.exe"

#define AppVersion GetEnv("MINTIMAGE_VERSION")
#if AppVersion == ""
  #define AppVersion "0.0.0"
#endif

#define ReleaseDir GetEnv("MINTIMAGE_RELEASE_DIR")
#if ReleaseDir == ""
  #define ReleaseDir "..\build\windows\x64\runner\Release"
#endif

#define OutputDir GetEnv("MINTIMAGE_OUTPUT_DIR")
#if OutputDir == ""
  #define OutputDir ".."
#endif

[Setup]
AppId={{8F3C1B42-5D7E-4A19-9C6B-2E4F7A0D51C3}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
; 保留「选择目标位置」向导页，安装时可以把程序装到 D 盘等任意目录。
DisableDirPage=no
DisableProgramGroupPage=yes
; 默认按当前用户安装，不需要管理员权限；
; 向导首页仍会让用户选择「为所有用户安装」，此时会自动请求提权。
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=MintImage-Setup-{#AppVersion}
SetupIconFile=..\icon\icon-windows.ico
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\{#AppExeName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

; 卸载只清理安装时写入的文件（Inno 的默认行为）。
; 数据目录（默认在用户的应用数据目录，或用户在设置里指定的位置）
; 与安装目录无关，卸载时一律保留。
