# بيبني نسخة FixTrack كاملة للتوزيع:
#   - ملف تثبيت Windows (Setup.exe)
#   - ملفات APK للأندرويد (الكل + موبايلات حديثة + موبايلات قديمة)
# وبيحطهم في فولدر builds.
# التشغيل من فولدر source:  powershell -ExecutionPolicy Bypass -File tool\build_release.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$version = (Select-String -Path pubspec.yaml -Pattern '^version:\s*([0-9.]+)').Matches[0].Groups[1].Value
$builds = Join-Path (Split-Path -Parent $root) 'builds'
$env:Path = "C:\src\flutter\bin;$env:Path"
if (-not $env:JAVA_HOME) { $env:JAVA_HOME = (Get-ChildItem 'C:\Program Files\Microsoft' -Directory -Filter 'jdk-17*' | Select-Object -First 1).FullName }

Write-Host "== FixTrack $version =="
flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw 'Windows build failed' }

# ملفات Visual C++ اللي بعض الأجهزة مش عليها: بنحطها جنب البرنامج
$release = Join-Path $root 'build\windows\x64\runner\Release'
foreach ($dll in 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') {
  Copy-Item (Join-Path $env:WINDIR "System32\$dll") $release -Force
}

$iscc = @("$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe", "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) { throw 'Inno Setup مش متسطب' }
& $iscc "/DAppVersion=$version" "/DOutputDir=$builds" (Join-Path $root 'installer\fixtrack.iss')
if ($LASTEXITCODE -ne 0) { throw 'Installer build failed' }

flutter build apk --release
if ($LASTEXITCODE -ne 0) { throw 'APK build failed' }
flutter build apk --release --split-per-abi
if ($LASTEXITCODE -ne 0) { throw 'APK split build failed' }

$apkDir = Join-Path $builds "FixTrack-$version-android"
New-Item -ItemType Directory -Force $apkDir | Out-Null
$out = Join-Path $root 'build\app\outputs\flutter-apk'
Copy-Item (Join-Path $out 'app-release.apk') (Join-Path $apkDir "FixTrack-$version-الكل.apk") -Force
Copy-Item (Join-Path $out 'app-arm64-v8a-release.apk') (Join-Path $apkDir "FixTrack-$version-موبايلات-حديثة.apk") -Force
Copy-Item (Join-Path $out 'app-armeabi-v7a-release.apk') (Join-Path $apkDir "FixTrack-$version-موبايلات-قديمة.apk") -Force

Write-Host "== تم: $builds =="
