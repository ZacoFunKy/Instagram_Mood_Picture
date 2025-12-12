try:
    from instagrapi import Client
except ImportError:
    Client = None
    print("Warning: instagrapi not found. Instagram updates will be skipped.")

import os

def update_profile_picture(mood_name):
    """
    Updates the Instagram profile picture based on the Mood.
    'mood_name' must match an image filename (e.g., 'confident.png').
    """
    username = os.environ.get("IG_USERNAME")
    password = os.environ.get("IG_PASSWORD")
    totp_seed = os.environ.get("IG_TOTP_SEED")
    
    if not username or not password:
        raise ValueError("IG_USERNAME or IG_PASSWORD not set")

    if Client is None:
        print("Instagrapi library not installed. Skipping update.")
        return

    cl = Client()
    
    # [FIX] Force specific device settings (Pixel 7) to bypass "Update Instagram" error
    # and set French locale
    cl.set_device({
        "app_version": "311.0.0.32.118",
        "android_version": 33,
        "android_release": "13",
        "dpi": "420dpi",
        "resolution": "1080x2400",
        "manufacturer": "Google",
        "device": "panther",
        "model": "Pixel 7",
        "cpu": "google",
        "version_code": "469371078"
    })
    cl.set_country("FR")
    cl.set_locale("fr_FR")
    
    # Login with 2FA if needed
    if totp_seed:
        # Sanitize seed: remove spaces, newlines, and ensure uppercase
        clean_seed = totp_seed.replace(" ", "").strip().upper()
        cl.login(username, password, verification_code=cl.totp_generate_code(clean_seed))
    else:
        cl.login(username, password)

    # Image path
    # We assume images are stored in an 'assets' folder
    image_path = f"assets/{mood_name}.png"
    
    if not os.path.exists(image_path):
        print(f"Image for mood '{mood_name}' not found at {image_path}. Skipping update.")
        return

    cl.account_change_picture(image_path)
    print(f"Profile picture updated to {mood_name}.")
