"""
Instagram client for profile picture management (Mobile API emulation).

Provides image-based profile picture updates using the native `instagrapi` library.
This mimics the mobile app API, which can be more robust than web endpoints
but carries higher risk of flagging if not configured correctly (fingerprinting).

Features:
- Native instagrapi library support
- TOTP-based 2FA
- Device fingerprinting for anti-detection
- Locale configuration
"""

import os
import logging
from typing import Optional, Any, Dict

# Graceful fallback if instagrapi is not installed
try:
    from instagrapi import Client
except ImportError:
    Client = None # type: ignore
    logging.warning("instagrapi library not installed. Instagram updates will be skipped.")

logger = logging.getLogger(__name__)


# ============================================================================
# CONSTANTS
# ============================================================================

# Pixel 7 device fingerprint (bypass "Update Instagram" error)
DEVICE_CONFIG = {
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
}

COUNTRY_CODE = "FR"
LOCALE = "fr_FR"
ASSETS_FOLDER = "assets"


# ============================================================================
# EXCEPTIONS
# ============================================================================

class InstagramAuthError(Exception):
    """Raised when Instagram authentication fails."""
    pass


class InstagramUpdateError(Exception):
    """Raised when profile picture update fails."""
    pass


# ============================================================================
# AUTHENTICATION
# ============================================================================

class InstagramAuthenticator:
    """Handles Instagram authentication with TOTP support."""

    def __init__(self, username: str, password: str, totp_seed: Optional[str] = None) -> None:
        """
        Initialize authenticator.

        Args:
            username: Instagram username
            password: Instagram password
            totp_seed: Optional TOTP seed for 2FA (with spaces/newlines removed)

        Raises:
            InstagramAuthError: If credentials are invalid
        """
        if not username or not password:
            raise InstagramAuthError("Username and password are required")

        if Client is None:
            raise InstagramAuthError("instagrapi library not installed")

        self.username = username
        self.password = password
        self.totp_seed = self._sanitize_totp_seed(totp_seed) if totp_seed else None
        self.client: Optional[Client] = None # type: ignore

    @staticmethod
    def _sanitize_totp_seed(seed: str) -> str:
        """
        Sanitizes TOTP seed.
        Removes spaces, newlines, and converts to uppercase.
        """
        return seed.replace(" ", "").replace("\n", "").strip().upper()

    def authenticate(self) -> Any:
        """
        Authenticates with Instagram.
        Sets device fingerprint and locale, handles TOTP if needed.

        Returns:
            Authenticated instagrapi Client.

        Raises:
            InstagramAuthError: If login fails.
        """
        try:
            client = Client() # type: ignore

            # Set device fingerprint (bypass "Update Instagram" error)
            client.set_device(DEVICE_CONFIG)
            client.set_country(COUNTRY_CODE)
            client.set_locale(LOCALE)

            # Login with optional TOTP
            if self.totp_seed:
                code = client.totp_generate_code(self.totp_seed)
                client.login(self.username, self.password, verification_code=code)
                logger.info(f"[OK] Authenticated with 2FA: {self.username}")
            else:
                client.login(self.username, self.password)
                logger.info(f"[OK] Authenticated: {self.username}")

            self.client = client
            return client

        except Exception as e:
            logger.error(f"Authentication failed: {e}")
            raise InstagramAuthError(f"Login failed: {e}") from e


# ============================================================================
# PROFILE PICTURE MANAGER
# ============================================================================

class InstagramProfileManager:
    """Manages Instagram profile picture updates."""

    def __init__(self, client: Any) -> None:
        """
        Initialize manager.

        Args:
            client: Authenticated instagrapi Client
        """
        self.client = client

    def update_profile_picture(self, mood_name: str, assets_folder: str = ASSETS_FOLDER) -> bool:
        """
        Updates profile picture based on mood.

        Args:
            mood_name: Mood name matching image filename (e.g., 'confident')
            assets_folder: Path to assets folder containing images

        Returns:
            True if successful, False otherwise.
        """
        image_path = os.path.join(assets_folder, f"{mood_name}.png")

        if not os.path.exists(image_path):
            logger.warning(f"Image for mood '{mood_name}' not found: {image_path}")
            return False

        try:
            self.client.account_change_picture(image_path)
            logger.info(f"[OK] Profile picture updated: {mood_name}")
            return True

        except Exception as e:
            logger.error(f"Failed to update profile picture: {e}")
            raise InstagramUpdateError(f"Update failed: {e}") from e


# ============================================================================
# PUBLIC API
# ============================================================================

def update_profile_picture(mood_name: str) -> bool:
    """
    Updates Instagram profile picture based on mood.

    Reads credentials from environment:
    - IG_USERNAME: Instagram username
    - IG_PASSWORD: Instagram password
    - IG_TOTP_SEED: Optional TOTP seed for 2FA

    Args:
        mood_name: Mood name (must match image file in assets/).

    Returns:
        True if successful, False if skipped (library not installed).
    """
    if Client is None:
        logger.warning("instagrapi not installed. Update skipped.")
        return False

    try:
        username = os.environ.get("IG_USERNAME")
        password = os.environ.get("IG_PASSWORD")
        totp_seed = os.environ.get("IG_TOTP_SEED")

        if not username or not password:
            raise InstagramAuthError("IG_USERNAME or IG_PASSWORD not configured")

        # Authenticate
        authenticator = InstagramAuthenticator(username, password, totp_seed)
        client = authenticator.authenticate()

        # Update profile picture
        manager = InstagramProfileManager(client)
        return manager.update_profile_picture(mood_name)

    except InstagramAuthError as e:
        logger.error(f"Authentication error: {e}")
        return False
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        return False
