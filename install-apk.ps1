# Mood App Quick Installer (Windows)
# Usage: .\install-apk.ps1 [path-to-apk]
# Or: .\install-apk.ps1  (uses default path)

param(
    [string]$ApkPath = "mobile\build\app\outputs\flutter-apk\app-release.apk"
)

Write-Host "📦 Mood App Installer (Windows)" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

# Check if APK exists
if (-not (Test-Path $ApkPath)) {
    Write-Host "❌ APK not found at: $ApkPath" -ForegroundColor Red
    Write-Host ""
    Write-Host "Build the APK first:" -ForegroundColor Yellow
    Write-Host "  cd mobile" -ForegroundColor Gray
    Write-Host "  flutter build apk --release" -ForegroundColor Gray
    exit 1
}

$ApkSize = (Get-Item $ApkPath).Length / 1MB
Write-Host "✅ APK Found"
Write-Host "  Path: $ApkPath" -ForegroundColor Green
Write-Host "  Size: $([Math]::Round($ApkSize, 2)) MB"
Write-Host ""

# Check if adb is available
$adbPath = which adb 2>$null
if (-not $adbPath) {
    # Try common Android SDK locations
    $possiblePaths = @(
        "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
        "C:\Android\Sdk\platform-tools\adb.exe",
        "C:\Program Files\Android\Sdk\platform-tools\adb.exe"
    )
    
    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            $adbPath = $path
            break
        }
    }
}

if (-not $adbPath) {
    Write-Host "❌ ADB not found in PATH" -ForegroundColor Red
    Write-Host ""
    Write-Host "Install Android SDK Platform Tools:" -ForegroundColor Yellow
    Write-Host "  1. Download from: https://developer.android.com/tools/releases/platform-tools" -ForegroundColor Gray
    Write-Host "  2. Extract and add to PATH, or" -ForegroundColor Gray
    Write-Host "  3. Update `$adbPath in this script" -ForegroundColor Gray
    exit 1
}

Write-Host "✅ ADB found at: $adbPath"
Write-Host ""

# Check for connected devices
Write-Host "Checking for connected devices..." -ForegroundColor Yellow
$devices = & $adbPath devices | Select-Object -Skip 1 | Where-Object { $_ -match "device$" } | Measure-Object
if ($devices.Count -eq 0) {
    Write-Host "❌ No Android devices found" -ForegroundColor Red
    Write-Host ""
    Write-Host "Connect your Android phone:" -ForegroundColor Yellow
    Write-Host "  1. Connect via USB cable" -ForegroundColor Gray
    Write-Host "  2. Go to Settings → Developer Options → USB Debugging" -ForegroundColor Gray
    Write-Host "  3. Tap 'Allow' on the prompt" -ForegroundColor Gray
    Write-Host "  4. Run this script again" -ForegroundColor Gray
    exit 1
}

Write-Host "✅ Device found ($($devices.Count))"
Write-Host ""
Write-Host "Installing APK..." -ForegroundColor Cyan
Write-Host ""

# Install with -r flag to replace existing app
& $adbPath install -r $ApkPath

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "✅ Installation successful!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "  1. Find 'Mood' app on your phone" -ForegroundColor Gray
    Write-Host "  2. Launch the app" -ForegroundColor Gray
    Write-Host "  3. Allow permissions when prompted" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Launching app..." -ForegroundColor Yellow
    Start-Sleep -Seconds 2
    & $adbPath shell am start -n com.example.mood_predictor_app/.MainActivity 2>$null
} else {
    Write-Host ""
    Write-Host "❌ Installation failed" -ForegroundColor Red
    Write-Host ""
    Write-Host "Troubleshooting:" -ForegroundColor Yellow
    Write-Host "  • Make sure USB Debugging is enabled" -ForegroundColor Gray
    Write-Host "  • Try: adb kill-server ; adb start-server" -ForegroundColor Gray
    Write-Host "  • Or manually: adb install -r '$ApkPath'" -ForegroundColor Gray
    exit 1
}
