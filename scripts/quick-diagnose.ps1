#!/usr/bin/env powershell
<#
.SYNOPSIS
Quick diagnostic for mobile app connectivity issues

.DESCRIPTION
Run this script to diagnose why History/Stats screens show no data

.EXAMPLE
.\scripts\quick-diagnose.ps1
#>

Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host "🔧 Mobile App Quick Diagnostic" -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan

# Check 1: ADB availability
Write-Host "`n📱 Checking for connected Android device..." -ForegroundColor Yellow
$devices = adb devices | Select-String "device" | Where-Object { $_ -notmatch "^List" }
if ($devices) {
    Write-Host "✅ Found connected device(s):" -ForegroundColor Green
    $devices | ForEach-Object { Write-Host "   $_" }
} else {
    Write-Host "❌ No Android device connected!" -ForegroundColor Red
    Write-Host "   Connect device via USB and enable USB debugging"
    exit 1
}

# Check 2: App installed
Write-Host "`n📦 Checking if app is installed..." -ForegroundColor Yellow
$appPackages = @(
    "com.example.mood_predictor_app",
    "com.mood.app",
    "com.mood.predictor"
)

$found = $false
foreach ($pkg in $appPackages) {
    $result = adb shell pm list packages | Select-String $pkg
    if ($result) {
        Write-Host "✅ Found: $pkg" -ForegroundColor Green
        $found = $true
        break
    }
}

if (-not $found) {
    Write-Host "❌ App not installed!" -ForegroundColor Red
    Write-Host "   Run: .\scripts\install\install-apk.ps1"
    exit 1
}

# Check 3: Internet on device
Write-Host "`n🌐 Checking device internet..." -ForegroundColor Yellow
$pingGoogle = adb shell ping -c 1 8.8.8.8 2>&1
if ($pingGoogle -match "1 packets transmitted" -or $pingGoogle -match "bytes from") {
    Write-Host "✅ Device has internet access" -ForegroundColor Green
} else {
    Write-Host "❌ Device has NO internet access!" -ForegroundColor Red
    Write-Host "   Device WiFi/data is not connected"
    exit 1
}

# Check 4: MongoDB connectivity (backend)
Write-Host "`n🏗️  Checking backend MongoDB connectivity..." -ForegroundColor Yellow
$result = python scripts/test_mongodb_connection.py 2>&1
if ($result -match "All tests passed") {
    Write-Host "✅ Backend MongoDB connectivity OK" -ForegroundColor Green
} else {
    Write-Host "❌ Backend MongoDB connectivity FAILED" -ForegroundColor Red
    Write-Host $result
    exit 1
}

# Check 5: Clear app cache
Write-Host "`n🧹 Clearing app cache (this may help)..." -ForegroundColor Yellow
adb shell pm clear com.example.mood_predictor_app 2>&1 | Out-Null
Write-Host "✅ App cache cleared" -ForegroundColor Green

# Check 6: Restart app
Write-Host "`n🔄 Restarting app..." -ForegroundColor Yellow
adb shell am force-stop com.example.mood_predictor_app 2>&1 | Out-Null
Start-Sleep -Seconds 2
adb shell am start -n com.example.mood_predictor_app/.MainActivity 2>&1 | Out-Null
Write-Host "✅ App restarted" -ForegroundColor Green

# Check 7: Real-time logs
Write-Host "`n📋 Displaying real-time app logs (Ctrl+C to stop)..." -ForegroundColor Yellow
Write-Host "Look for: ✅ Connected to MongoDB (success)" -ForegroundColor Cyan
Write-Host "Look for: 🌐 SOCKET/NETWORK ERROR (network problem)" -ForegroundColor Cyan
Write-Host "Look for: ⏱️ TIMEOUT (too slow)" -ForegroundColor Cyan
Write-Host ""

adb logcat --clear
adb logcat | Select-String "flutter"

Write-Host "`n=====================================================" -ForegroundColor Cyan
Write-Host "End of diagnostic" -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan
