#!/bin/bash
# Clean Reinstall Script for Mood App (macOS/Linux)
# Handles package conflicts by uninstalling old app and cleanly reinstalling

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"

APK_PATH="${1:-$PROJECT_ROOT/mobile/build/app/outputs/flutter-apk/app-release.apk}"

echo "🔧 Mood App Clean Reinstall"
echo "============================="
echo ""

# Check if APK exists
if [ ! -f "$APK_PATH" ]; then
    echo "❌ APK not found at: $APK_PATH"
    echo ""
    echo "Build the APK first:"
    echo "  cd $PROJECT_ROOT/mobile"
    echo "  flutter clean"
    echo "  flutter pub get"
    echo "  flutter build apk --release"
    exit 1
fi

# Check if adb is available
if ! command -v adb &> /dev/null; then
    echo "❌ ADB not found in PATH"
    exit 1
fi

echo "✅ ADB found"
echo ""

# Check for connected devices
DEVICE_COUNT=$(adb devices | grep -c "device$")
if [ "$DEVICE_COUNT" -eq 0 ]; then
    echo "❌ No Android devices found"
    echo "Connect your phone and enable USB debugging"
    exit 1
fi

echo "✅ Device found"
echo ""

# List possible package names to uninstall
PACKAGES=(
    "com.example.mood_predictor_app"
    "com.mood"
    "com.example.mood"
    "com.example.flutter_application"
)

echo "Checking for existing installations..."

for pkg in "${PACKAGES[@]}"; do
    if adb shell pm list packages | grep -q "$pkg"; then
        echo "Found installed: $pkg"
        echo "Uninstalling $pkg..."
        adb uninstall "$pkg" > /dev/null
        echo "✅ Uninstalled $pkg"
    fi
done

echo ""
echo "📦 Installing fresh APK"
echo "  Path: $APK_PATH"
echo "  Size: $(du -h "$APK_PATH" | cut -f1)"
echo ""

# Install fresh copy (without -r flag for clean install)
adb install "$APK_PATH"

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Clean installation successful!"
    echo ""
    echo "Launching app..."
    sleep 2
    adb shell am start -n com.example.mood_predictor_app/.MainActivity 2>/dev/null || true
    echo ""
    echo "✅ App launched!"
else
    echo ""
    echo "❌ Installation failed"
    echo ""
    echo "Try:"
    echo "  1. Manually uninstall 'Mood' from Settings → Apps"
    echo "  2. Run this script again"
    echo "  3. Or: adb install $APK_PATH"
    exit 1
fi
