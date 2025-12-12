# Scripts README

This folder contains optional scripts for calendar maintenance.

## Current scripts
- `create_reminders.py`: creates calendar reminders for renewing Instagram session ID and YouTube Music headers.
- `subscribe_bot.py`: subscribes the service account to target calendars listed in `TARGET_CALENDAR_ID`.

## YouTube Music Key Setup (Headers)
To generate the browser auth headers for ytmusicapi:

1. Open `https://music.youtube.com` in your browser and log in.
2. Open DevTools (F12) → Network → filter by `browse`.
3. Refresh the page and click a `browse` request.
4. Copy the Request Headers (or Copy as cURL).
5. Run:
   ```powershell
   python .\scripts\create_browser_auth.py
   ```
6. Paste the copied headers or cURL into the script prompt.
7. The script creates `browser_auth_new.json` at the project root.
8. Verify:
   ```powershell
   python .\scripts\test_full_auth.py
   ```

The project automatically uses `browser_auth_new.json` via `connectors/yt_music.py`.
