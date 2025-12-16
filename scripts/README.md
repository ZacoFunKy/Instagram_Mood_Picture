# 🛠️ Scripts Directory

Collection of utility scripts for the Mood App project.

## Structure

```
scripts/
├── create_browser_auth.py      # Instagram browser auth setup
├── create_reminders.py         # Reminder creation
├── subscribe_bot.py            # Bot subscription
└── install/                    # Mobile app installation
    ├── install-apk.ps1         # Windows installer
    ├── install-apk.sh          # macOS/Linux installer
    └── README.md               # Installation scripts guide
```

## Installation Scripts

Located in `scripts/install/`

### Quick Install (Windows)
```powershell
.\scripts\install\install-apk.ps1
```

### Quick Install (macOS/Linux)
```bash
./scripts/install/install-apk.sh
```

Features:
- ✅ Check APK exists
- ✅ Verify ADB installed
- ✅ Check for connected devices
- ✅ Install with `-r` flag (no uninstall needed)
- ✅ Auto-launch app

## Python Scripts

### create_browser_auth.py
Setup browser authentication for Instagram.

```bash
python scripts/create_browser_auth.py
```

### create_reminders.py
Create reminders for the bot.

```bash
python scripts/create_reminders.py
```

### subscribe_bot.py
Subscribe to bot notifications.

```bash
python scripts/subscribe_bot.py
```

## Documentation

- [Mobile Installation Guide](../INSTALLATION_GUIDE.md)
- [Project README](../README.md)
