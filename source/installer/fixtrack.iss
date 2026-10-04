; ملف تثبيت FixTrack لـ Windows (Inno Setup 6).
; البناء: tool\build_installer.ps1 (بيبني البرنامج وبيجهز ملفات Windows الناقصة وبيعمل الـ Setup).
#define AppName "FixTrack"
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\builds"
#endif

[Setup]
; المعرّف ده لازم يفضل ثابت عشان التحديثات تتسطب فوق النسخة القديمة
AppId={{6F1B5C2E-8B7A-4E19-9D3C-FA7E1D2B4C11}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=FixTrack
DefaultDirName={autopf}\FixTrack
DefaultGroupName=FixTrack
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir={#OutputDir}
OutputBaseFilename=FixTrack-Setup-{#AppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\fixtrack.exe
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=force
RestartApplications=no

[Languages]
Name: "arabic"; MessagesFile: "compiler:Languages\Arabic.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[CustomMessages]
arabic.DesktopIcon=أيقونة على سطح المكتب
arabic.AutoStart=شغّل FixTrack لوحده مع تشغيل الكمبيوتر (مهم لو الجهاز ده هو سيرفر المحل)
arabic.LaunchApp=افتح FixTrack دلوقتي
english.DesktopIcon=Create a desktop shortcut
english.AutoStart=Start FixTrack automatically with Windows (recommended for the shop server)
english.LaunchApp=Launch FixTrack now

[Tasks]
Name: "desktopicon"; Description: "{cm:DesktopIcon}"
Name: "autostart"; Description: "{cm:AutoStart}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\FixTrack"; Filename: "{app}\fixtrack.exe"
Name: "{autodesktop}\FixTrack"; Filename: "{app}\fixtrack.exe"; Tasks: desktopicon
Name: "{commonstartup}\FixTrack"; Filename: "{app}\fixtrack.exe"; Tasks: autostart

[Run]
; الـ Firewall: بنسمح للبرنامج بس (مش بورتات مفتوحة لأي حاجة) عشان الموبايلات تتصل بالسيرفر.
; profile=any لأن شبكة الواي فاي في محلات كتير Windows بيعتبرها "عامة".
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""FixTrack"""; Flags: runhidden waituntilterminated
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall add rule name=""FixTrack"" dir=in action=allow program=""{app}\fixtrack.exe"" enable=yes profile=any"; Flags: runhidden waituntilterminated
Filename: "{app}\fixtrack.exe"; Description: "{cm:LaunchApp}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""FixTrack"""; Flags: runhidden waituntilterminated; RunOnceId: "RemoveFirewallRule"

; بيانات المحل (في AppData) مش بتتمسح مع إلغاء التثبيت، عشان مايضيعش حاجة بالغلط.
