"""
Instagram web client for headless profile management.

Provides browser-based authentication and profile updates:
- Session ID bypass (skips 2FA)
- TOTP-based 2FA fallback
- Web API endpoints
- CSRF token management
"""

import os
import datetime
import logging
from typing import Optional, Dict, Any, Union

import requests
import pyotp

logger = logging.getLogger(__name__)

# ============================================================================
# CONSTANTS
# ============================================================================

BASE_URL = "https://www.instagram.com"
API_TIMEOUT = 10

USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
)

ASSETS_FOLDER = "assets"


# ============================================================================
# EXCEPTIONS
# ============================================================================

class InstagramWebAuthError(Exception):
    """Raised when web authentication fails."""
    pass


class InstagramWebUpdateError(Exception):
    """Raised when profile update fails."""
    pass


# ============================================================================
# AUTHENTICATION
# ============================================================================

class InstagramWebAuthenticator:
    """Handles Instagram web-based authentication."""

    def __init__(self, username: str, password: str, totp_seed: Optional[str] = None) -> None:
        """
        Initialize web authenticator.

        Args:
            username: Instagram username
            password: Instagram password
            totp_seed: Optional TOTP seed for 2FA
        
        Raises:
            InstagramWebAuthError: If credentials invalid
        """
        if not username or not password:
            raise InstagramWebAuthError("Username and password required")

        self.username = username
        self.password = password
        self.totp_seed = self._sanitize_totp_seed(totp_seed) if totp_seed else None
        self.session = self._create_session()

    @staticmethod
    def _create_session() -> requests.Session:
        """Creates configured requests session."""
        session = requests.Session()
        session.headers.update({
            "User-Agent": USER_AGENT,
            "X-IG-App-ID": "936619743392459",  # Web App ID
            "X-Requested-With": "XMLHttpRequest",
            "Referer": "https://www.instagram.com/"
        })
        return session

    @staticmethod
    def _sanitize_totp_seed(seed: str) -> str:
        """
        Sanitizes TOTP seed.
        Removes spaces, newlines, converts to uppercase.
        """
        return seed.replace(" ", "").replace("\n", "").strip().upper()

    def _get_csrf_token(self) -> Optional[str]:
        """
        Fetches CSRF token from Instagram main page.
        """
        try:
            resp = self.session.get(BASE_URL, timeout=API_TIMEOUT)
            resp.raise_for_status()
            return self.session.cookies.get("csrftoken")
        except Exception as e:
            logger.warning(f"Failed to get CSRF token: {e}")
            return None

    def _try_session_id_auth(self, session_id: str) -> bool:
        """
        Attempts authentication using session ID.
        Bypasses username/password login and 2FA entirely.

        Args:
            session_id: Existing Instagram sessionid cookie value

        Returns:
            True if session appears valid, False otherwise
        """
        try:
            logger.info("Attempting session ID authentication...")
            self.session.cookies.set("sessionid", session_id)

            csrf = self._get_csrf_token()
            if csrf:
                self.session.headers.update({"X-CSRFToken": csrf})

            logger.info("[OK] Session ID injected (skipping credential login)")
            return True

        except Exception as e:
            logger.warning(f"Session ID auth failed: {e}")
            return False

    def _try_credential_auth(self) -> bool:
        """
        Attempts authentication using username/password.
        Falls back to TOTP 2FA if needed.

        Returns:
            True if successful, False otherwise

        Raises:
            InstagramWebAuthError: If authentication definitely fails
        """
        try:
            csrf = self._get_csrf_token()
            if not csrf:
                raise InstagramWebAuthError("Could not fetch CSRF token")

            self.session.headers.update({"X-CSRFToken": csrf})

            # Build encrypted password
            timestamp = int(datetime.datetime.now().timestamp())
            encrypted_pwd = f"#PWD_INSTAGRAM_BROWSER:0:{timestamp}:{self.password}"

            payload = {
                "username": self.username,
                "enc_password": encrypted_pwd,
                "queryParams": "{}",
                "optIntoOneTap": "false"
            }

            login_url = f"{BASE_URL}/accounts/login/ajax/"
            resp = self.session.post(login_url, data=payload, timeout=API_TIMEOUT)
            resp.raise_for_status()

            data = resp.json()

            # Check for 2FA requirement
            if data.get("error_type") == "two_factor_required":
                logger.info("2FA required, attempting TOTP...")
                return self._handle_2fa(data)

            if not data.get("authenticated"):
                raise InstagramWebAuthError(f"Login failed: {data.get('message', 'Unknown error')}")

            logger.info("[OK] Credential login successful")
            return True

        except Exception as e:
            logger.error(f"Credential auth failed: {e}")
            raise InstagramWebAuthError(f"Login failed: {e}") from e

    def _handle_2fa(self, auth_response: Dict[str, Any]) -> bool:
        """
        Handles 2FA verification using TOTP.

        Args:
            auth_response: Response dict containing 2FA info

        Returns:
            True if 2FA successful, False otherwise
        """
        if not self.totp_seed:
            raise InstagramWebAuthError("2FA required but TOTP seed not provided")

        try:
            two_factor_info = auth_response.get("two_factor_info", {})
            two_factor_id = two_factor_info.get("two_factor_identifier")

            if not two_factor_id:
                raise InstagramWebAuthError("No 2FA identifier in response")

            # Generate TOTP code
            totp = pyotp.TOTP(self.totp_seed)
            code = totp.now()

            # Submit code
            verify_url = f"{BASE_URL}/accounts/login/ajax/two_factor/"
            verify_payload = {
                "username": self.username,
                "verificationCode": code,
                "identifier": two_factor_id,
                "queryParams": "{}"
            }

            resp = self.session.post(verify_url, data=verify_payload, timeout=API_TIMEOUT)
            resp.raise_for_status()

            data = resp.json()

            if not data.get("authenticated"):
                raise InstagramWebAuthError("2FA verification failed")

            logger.info("[OK] 2FA verification successful")
            return True

        except Exception as e:
            logger.error(f"2FA handling failed: {e}")
            raise InstagramWebAuthError(f"2FA failed: {e}") from e

    def authenticate(self) -> requests.Session:
        """
        Authenticates with Instagram.
        Attempts session ID first (bypasses 2FA), falls back to credentials.

        Returns:
            Authenticated requests.Session object.
        """
        # Try session ID first (if provided)
        session_id = os.environ.get("IG_SESSIONID")
        if session_id and self._try_session_id_auth(session_id):
            return self.session

        # Fall back to credentials
        if self._try_credential_auth():
            return self.session

        raise InstagramWebAuthError("All authentication methods failed")


# ============================================================================
# PROFILE PICTURE MANAGER
# ============================================================================

class InstagramWebProfileManager:
    """Manages profile picture updates via web API."""

    def __init__(self, session: requests.Session) -> None:
        """
        Initialize manager.

        Args:
            session: Authenticated requests session
        """
        self.session = session

    def update_profile_picture(self, image_path: str) -> bool:
        """
        Updates profile picture via web API.

        Args:
            image_path: Path to image file.

        Returns:
            True if successful, False otherwise.
        """
        if not os.path.exists(image_path):
            logger.warning(f"Image not found: {image_path}")
            return False

        try:
            # Refresh CSRF before upload
            csrf = self._get_csrf_token()
            if csrf:
                self.session.headers.update({"X-CSRFToken": csrf})

            upload_url = f"{BASE_URL}/accounts/web_change_profile_picture/"

            with open(image_path, "rb") as f:
                files = {"profile_pic": f}
                resp = self.session.post(upload_url, files=files, timeout=API_TIMEOUT)

            if resp.status_code != 200:
                raise InstagramWebUpdateError(f"HTTP {resp.status_code}: {resp.text}")

            logger.info(f"[OK] Profile picture updated: {image_path}")
            return True

        except Exception as e:
            logger.error(f"Upload failed: {e}")
            raise InstagramWebUpdateError(f"Update failed: {e}") from e

    def _get_csrf_token(self) -> Optional[str]:
        """Fetches fresh CSRF token."""
        try:
            resp = self.session.get(BASE_URL, timeout=API_TIMEOUT)
            return self.session.cookies.get("csrftoken")
        except Exception as e:
            logger.warning(f"CSRF refresh failed: {e}")
            return None


# ============================================================================
# PUBLIC API
# ============================================================================

def update_profile_picture_web(mood_name: str) -> bool:
    """
    Updates Instagram profile picture via web API.

    Reads credentials from environment:
    - IG_USERNAME: Instagram username
    - IG_PASSWORD: Instagram password
    - IG_TOTP_SEED: Optional TOTP seed for 2FA
    - IG_SESSIONID: Optional session ID (bypasses login)

    Args:
        mood_name: Mood name (must match image in assets/).

    Returns:
        True if successful, False otherwise.
    """
    try:
        username = os.environ.get("IG_USERNAME")
        password = os.environ.get("IG_PASSWORD")
        totp_seed = os.environ.get("IG_TOTP_SEED")

        if not username or not password:
            raise InstagramWebAuthError("IG credentials not configured")

        # Authenticate
        authenticator = InstagramWebAuthenticator(username, password, totp_seed)
        session = authenticator.authenticate()

        # Update profile picture
        image_path = os.path.join(ASSETS_FOLDER, f"{mood_name}.png")
        manager = InstagramWebProfileManager(session)
        return manager.update_profile_picture(image_path)

    except InstagramWebAuthError as e:
        logger.error(f"Auth error: {e}")
        return False
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        return False
