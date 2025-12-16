# Clean Reinstall Script for Mood App
# Handles package conflicts by uninstalling old app and cleanly reinstalling

param(
    [string]$ApkPath = "mobile\build\app\outputs\flutter-apk\app-release.apk"
)

Write-Host "🔧 Mood App Clean Reinstall" -ForegroundColor Cyan
Write-Host "=============================" -ForegroundColor Cyan
Write-Host ""

# Resolve to absolute path if relative
if (-not [System.IO.Path]::IsPathRooted($ApkPath)) {
    $ApkPath = Join-Path (Get-Location) $ApkPath
}

# Check if adb is available
$adbPath = which adb 2>$null
if (-not $adbPath) {
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
    exit 1
}

Write-Host "✅ ADB found at: $adbPath"
Write-Host ""

# Check for connected devices
Write-Host "Checking for connected devices..." -ForegroundColor Yellow
$devices = & $adbPath devices | Select-Object -Skip 1 | Where-Object { $_ -match "device$" } | Measure-Object
if ($devices.Count -eq 0) {
    Write-Host "❌ No Android devices found" -ForegroundColor Red
    Write-Host "Connect your phone and enable USB debugging" -ForegroundColor Yellow
    exit 1
}

Write-Host "✅ Device found"
Write-Host ""

# List possible package names to uninstall
$possiblePackages = @(
    "com.example.mood_predictor_app",
    "com.mood",
    "com.example.mood",
    "com.example.flutter_application"
)

Write-Host "Checking for existing installations..." -ForegroundColor Yellow

foreach ($pkg in $possiblePackages) {
    $installed = & $adbPath shell pm list packages | Select-String $pkg
    if ($installed) {
        Write-Host "Found installed: $pkg" -ForegroundColor Green
        Write-Host "Uninstalling $pkg..." -ForegroundColor Yellow
        & $adbPath uninstall $pkg | Out-Null
        Write-Host "✅ Uninstalled $pkg" -ForegroundColor Green
    }
}

Write-Host ""

if (-not (Test-Path $ApkPath)) {
    Write-Host "❌ APK not found at: $ApkPath" -ForegroundColor Red
    Write-Host ""
    Write-Host "Build the APK first:" -ForegroundColor Yellow
    Write-Host "  cd mobile" -ForegroundColor Gray
    Write-Host "  flutter clean" -ForegroundColor Gray
    Write-Host "  flutter pub get" -ForegroundColor Gray
    Write-Host "  flutter build apk --release" -ForegroundColor Gray
    exit 1
}

$ApkSize = (Get-Item $ApkPath).Length / 1MB
Write-Host "📦 Installing fresh APK" -ForegroundColor Cyan
Write-Host "  Path: $ApkPath" -ForegroundColor Green
Write-Host "  Size: $([Math]::Round($ApkSize, 2)) MB"
Write-Host ""

# Install fresh copy
& $adbPath install $ApkPath

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "✅ Clean installation successful!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Launching app..." -ForegroundColor Yellow
    Start-Sleep -Seconds 2
    & $adbPath shell am start -n com.example.mood_predictor_app/.MainActivity 2>$null
    Write-Host ""
    Write-Host "✅ App launched!" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "❌ Installation failed" -ForegroundColor Red
    Write-Host ""
    Write-Host "Try:" -ForegroundColor Yellow
    Write-Host "  1. Manually uninstall 'Mood' from Settings → Apps" -ForegroundColor Gray
    Write-Host "  2. Run this script again" -ForegroundColor Gray
    Write-Host "  3. Or: & `"$adbPath`" install `"$ApkPath`"" -ForegroundColor Gray
    exit 1
}
