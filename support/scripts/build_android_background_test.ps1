param([int]$BuildNumber = 67)

$ErrorActionPreference = 'Stop'
$previousWindows = $env:FLUTTER_WINDOWS
$previousTestBuild = $env:LOCALSEND_BACKGROUND_TEST
Push-Location (Join-Path $PSScriptRoot '../../app')
try {
    # Android preparation must finish even on Windows without symlink privileges.
    $env:FLUTTER_WINDOWS = 'false'
    $env:LOCALSEND_BACKGROUND_TEST = 'true'
    fvm flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'Flutter plugin preparation failed; APK build stopped.' }

    $registrant = 'android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java'
    if (!(Test-Path $registrant) -or !(Select-String -Path $registrant -Pattern 'SharedPreferencesPlugin' -Quiet)) {
        throw 'Android plugin registration is missing; APK build stopped.'
    }

    fvm flutter build apk --release --split-per-abi --target-platform android-arm64 --build-number=$BuildNumber --no-pub
    if ($LASTEXITCODE -ne 0) { throw 'Android APK build failed.' }
} finally {
    $env:FLUTTER_WINDOWS = $previousWindows
    $env:LOCALSEND_BACKGROUND_TEST = $previousTestBuild
    Pop-Location
}
