#!/bin/bash
# Quick install script for Mood app
# Usage: ./scripts/install/install-apk.sh [path-to-apk]

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"

APK_PATH="${1:-$PROJECT_ROOT/mobile/build/app/outputs/flutter-apk/app-release.apk}"

if [ ! -f "$APK_PATH" ]; then
    echo "❌ APK not found at: $APK_PATH"
    echo ""
    echo "Build the APK first:"
    echo "  cd $PROJECT_ROOT/mobile"
    echo "  flutter build apk --release"
    exit 1
fi

echo "📦 Mood App Installer"
echo "===================="
echo ""
echo "APK Path: $APK_PATH"
echo "APK Size: $(du -h "$APK_PATH" | cut -f1)"
echo ""

# Check if adb is available
if ! command -v adb &> /dev/null; then
    echo "❌ ADB not found in PATH"
    echo ""
    echo "Install Android SDK Platform Tools:"
    echo "  Windows: Download from https://developer.android.com/tools/releases/platform-tools"
    echo "  macOS: brew install android-platform-tools"
    echo "  Linux: sudo apt-get install android-tools-adb"
    exit 1
fi

# Check for connected devices
DEVICE_COUNT=$(adb devices | grep -c "device$")
if [ "$DEVICE_COUNT" -eq 0 ]; then
    echo "❌ No Android devices found"
    echo ""
    echo "Connect your Android phone and enable USB debugging:"
    echo "  1. Connect via USB cable"
    echo "  2. Go to Settings → Developer Options → USB Debugging"
    echo "  3. Tap 'Allow' on the prompt"
    echo "  4. Run this script again"
    exit 1
fi

echo "✅ Device found"
echo ""
echo "Installing APK..."
echo ""

# Install with -r flag to replace existing app
adb install -r "$APK_PATH"

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Installation successful!"
    echo ""
    echo "Next steps:"
    echo "  1. Find 'Mood' app on your phone"
    echo "  2. Launch the app"
    echo "  3. Allow permissions when prompted"
    echo ""
    echo "Launching app..."
    adb shell am start -n com.example.mood_predictor_app/.MainActivity 2>/dev/null || echo "  Manual launch: adb shell am start -n <package-name>/<activity>"
else
    echo ""
    echo "❌ Installation failed"
    echo ""
    echo "Troubleshooting:"
    echo "  • Make sure USB Debugging is enabled"
    echo "  • Try: adb kill-server && adb start-server"
    echo "  • Or manually install: adb install -r '$APK_PATH'"
    exit 1
fi
