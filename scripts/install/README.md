# 📱 Mobile App Installation Scripts

Quick installation scripts for the Mood app to your Android device.

## Quick Start

### Windows
```powershell
# Standard install (replaces existing)
.\scripts\install\install-apk.ps1

# Clean install (uninstalls conflicts, then installs)
.\scripts\install\clean-reinstall.ps1
```

### macOS / Linux
```bash
# Standard install (replaces existing)
chmod +x ./scripts/install/install-apk.sh
./scripts/install/install-apk.sh

# Clean install (uninstalls conflicts, then installs)
chmod +x ./scripts/install/clean-reinstall.sh
./scripts/install/clean-reinstall.sh
```

## Prerequisites

1. **Android Phone** with USB Debugging enabled
2. **ADB (Android Debug Bridge)** installed
3. **APK Built** (use `cd mobile && flutter build apk --release`)

## Files

| File | Platform | Usage |
|------|----------|-------|
| `install-apk.ps1` | Windows | PowerShell script - standard install (replaces existing) |
| `install-apk.sh` | macOS/Linux | Bash script - standard install (replaces existing) |
| `clean-reinstall.ps1` | Windows | PowerShell script - clean install (removes conflicts first) |
| `clean-reinstall.sh` | macOS/Linux | Bash script - clean install (removes conflicts first) |

## When to use which

### Use `install-apk.ps1` / `install-apk.sh`
- App is already installed and working
- Just updating to a new version
- User data should be preserved

### Use `clean-reinstall.ps1` / `clean-reinstall.sh`
- Getting "package conflict" errors
- First time install after development
- App won't start or crashes immediately
- Need to clear all existing app data

## What These Scripts Do

✅ Check if APK exists
✅ Verify ADB is installed
✅ Check for connected Android devices
✅ Install app with `-r` flag (replace without uninstall)
✅ Launch the app after installation
✅ Provide helpful troubleshooting info on failure

## Manual Installation

If scripts don't work, use ADB directly:

```bash
# Install (replaces existing)
adb install -r path/to/app-release.apk

# Launch
adb shell am start -n com.example.mood_predictor_app/.MainActivity
```

## Troubleshooting

### "Device not found"
```bash
adb kill-server
adb start-server
adb devices
```

### "ADB not found"
Download Android SDK Platform Tools:
https://developer.android.com/tools/releases/platform-tools

### "Installation failed"
```bash
# Clear app data first
adb shell pm clear com.example.mood_predictor_app
adb install -r path/to/app-release.apk
```

## Features

The `-r` flag used by these scripts means:
- **No uninstall needed** - replaces existing app
- **User data preserved** - keeps app settings
- **Quick upgrade** - seamless app updates

## See Also

- [Full Installation Guide](../../INSTALLATION_GUIDE.md)
- [Mood App Documentation](../../README.md)
