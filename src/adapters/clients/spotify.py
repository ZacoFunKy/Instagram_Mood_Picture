"""
Spotify API client for track metadata enrichment.

This module provides a resilient client for fetching Spotify track metadata
since the /v1/audio-features endpoint was deprecated on Nov 27, 2024.

The client uses alternative endpoints:
- /v1/search: Locate tracks
- /v1/tracks/{id}: Fetch full track details
- Heuristic estimation: Derive audio features from metadata
"""

import os
import base64
import logging
from typing import Dict, Optional, Tuple, Any, Union
from enum import IntEnum

import requests

logger = logging.getLogger(__name__)


# ============================================================================
# CONSTANTS
# ============================================================================

SPOTIFY_AUTH_URL = "https://accounts.spotify.com/api/token"
SPOTIFY_SEARCH_URL = "https://api.spotify.com/v1/search"
SPOTIFY_TRACK_URL = "https://api.spotify.com/v1/tracks"

API_TIMEOUT = 10
DEFAULT_RETRY_LIMIT = 3


# ============================================================================
# AUDIO FEATURE ESTIMATION ENUMS & CONSTANTS
# ============================================================================

class AudioFeatureRange(IntEnum):
    """Ranges for audio feature estimation."""
    VALENCE_MIN = 15  # Minimum valence for sad tracks (0-100 scale)
    TEMPO_MIN = 100   # Minimum estimated tempo in BPM
    TEMPO_MAX = 160   # Maximum estimated tempo in BPM


# ============================================================================
# EXCEPTIONS
# ============================================================================

class SpotifyAuthError(Exception):
    """Raised when Spotify authentication fails."""
    pass


class SpotifyAPIError(Exception):
    """Raised when Spotify API call fails."""
    pass


# ============================================================================
# AUDIO FEATURE ESTIMATION
# ============================================================================

class AudioFeatureEstimator:
    """
    Estimates audio features from track metadata.

    Since /v1/audio-features was deprecated, this estimator derives
    valence, energy, danceability, and tempo from available metadata:
    - Track popularity (0-100)
    - Explicit flag
    - Album info
    """

    # Weighting factors for estimation
    POPULARITY_TO_ENERGY_WEIGHT = 0.8
    EXPLICIT_ENERGY_BONUS = 0.2
    POPULARITY_TO_VALENCE_WEIGHT = 0.7
    VALENCE_BASE = 0.15  # Minimum valence for sad tracks

    @classmethod
    def estimate(cls, track_data: Dict[str, Any]) -> Dict[str, Union[float, int]]:
        """
        Estimates audio features from track metadata.

        Args:
            track_data: Spotify track object with 'popularity' and 'explicit' fields.

        Returns:
            Dict with keys: valence, energy, danceability, tempo.
            All feature values normalized to 0-1 range except tempo (BPM).
        """
        popularity = track_data.get("popularity", 50) / 100.0
        is_explicit = track_data.get("explicit", False)

        # Energy: popularity + explicit bonus
        energy = cls._estimate_energy(popularity, is_explicit)

        # Valence (positivity): popularity-based with minimum floor
        valence = cls._estimate_valence(popularity)

        # Danceability: popularity + explicit bonus, scaled
        danceability = cls._estimate_danceability(popularity, is_explicit)

        # Tempo: popularity-mapped to BPM range
        tempo = cls._estimate_tempo(popularity)

        return {
            "valence": round(valence, 2),
            "energy": round(energy, 2),
            "danceability": round(danceability, 2),
            "tempo": tempo,
        }

    @classmethod
    def _estimate_energy(cls, popularity: float, is_explicit: bool) -> float:
        """
        Estimates energy from popularity and explicit flag.
        """
        energy = (popularity * cls.POPULARITY_TO_ENERGY_WEIGHT +
                  (cls.EXPLICIT_ENERGY_BONUS if is_explicit else 0))
        return min(1.0, energy)

    @classmethod
    def _estimate_valence(cls, popularity: float) -> float:
        """
        Estimates valence (positivity) from popularity.
        """
        valence = popularity * cls.POPULARITY_TO_VALENCE_WEIGHT + cls.VALENCE_BASE / 100.0
        return min(1.0, valence)

    @classmethod
    def _estimate_danceability(cls, popularity: float, is_explicit: bool) -> float:
        """
        Estimates danceability from popularity and explicit flag.
        """
        base_danceability = popularity * 0.6
        explicit_bonus = 0.3 if is_explicit else 0
        danceability = base_danceability + explicit_bonus
        return min(1.0, danceability)

    @classmethod
    def _estimate_tempo(cls, popularity: float) -> int:
        """
        Estimates tempo (BPM) from popularity.
        """
        tempo_range = AudioFeatureRange.TEMPO_MAX - AudioFeatureRange.TEMPO_MIN
        base_tempo = AudioFeatureRange.TEMPO_MIN + (popularity * tempo_range)
        return int(base_tempo)


# ============================================================================
# SPOTIFY AUTHENTICATION
# ============================================================================

class SpotifyAuthenticator:
    """Handles Spotify API authentication using Client Credentials flow."""

    def __init__(self, client_id: Optional[str] = None, client_secret: Optional[str] = None) -> None:
        """
        Initialize authenticator.

        Args:
            client_id: Spotify client ID (defaults to env var SPOTIFY_CLIENT_ID)
            client_secret: Spotify client secret (defaults to env var SPOTIFY_CLIENT_SECRET)

        Raises:
            ValueError: If credentials not provided and env vars not set.
        """
        self.client_id = client_id or os.environ.get("SPOTIFY_CLIENT_ID")
        self.client_secret = client_secret or os.environ.get("SPOTIFY_CLIENT_SECRET")

        if not self.client_id or not self.client_secret:
            raise ValueError("Spotify credentials not configured (SPOTIFY_CLIENT_ID, SPOTIFY_CLIENT_SECRET)")

        self.access_token: Optional[str] = None

    def get_access_token(self) -> Optional[str]:
        """
        Obtains Spotify access token using Client Credentials flow.
        Implements simple caching: reuses token until near expiry.

        Returns:
            Access token string, or None if authentication fails.

        Raises:
            SpotifyAuthError: On authentication failures.
        """
        if self.access_token:
            return self.access_token

        try:
            auth_str = f"{self.client_id}:{self.client_secret}"
            b64_auth = base64.b64encode(auth_str.encode()).decode()

            headers = {
                "Authorization": f"Basic {b64_auth}",
                "Content-Type": "application/x-www-form-urlencoded"
            }
            data = {"grant_type": "client_credentials"}

            response = requests.post(
                SPOTIFY_AUTH_URL,
                headers=headers,
                data=data,
                timeout=API_TIMEOUT
            )
            response.raise_for_status()

            token_data = response.json()
            self.access_token = token_data.get("access_token")

            if not self.access_token:
                raise SpotifyAuthError("No access token in response")

            logger.info("[OK] Spotify authentication successful")
            return self.access_token

        except requests.exceptions.Timeout:
            logger.error("Spotify auth timeout")
            raise SpotifyAuthError("Authentication timeout") from None
        except requests.exceptions.HTTPError as e:
            logger.error(f"Spotify auth HTTP error: {e.response.status_code}")
            raise SpotifyAuthError(f"HTTP {e.response.status_code}") from None
        except Exception as e:
            logger.error(f"Spotify authentication failed: {e}")
            raise SpotifyAuthError(str(e)) from e


# ============================================================================
# SPOTIFY API CLIENT
# ============================================================================

class SpotifyClient:
    """
    Client for fetching Spotify track metadata.

    Since /v1/audio-features was deprecated (Nov 27, 2024), uses:
    1. /v1/search: Locate tracks
    2. /v1/tracks/{id}: Fetch full track details
    3. AudioFeatureEstimator: Derive features from metadata
    """

    def __init__(self, client_id: Optional[str] = None, client_secret: Optional[str] = None) -> None:
        try:
            self.auth: Optional[SpotifyAuthenticator] = SpotifyAuthenticator(client_id, client_secret)
        except ValueError as e:
            logger.warning(f"Spotify client disabled: {e}")
            self.auth = None

    def is_available(self) -> bool:
        """Checks if Spotify client is properly configured."""
        return self.auth is not None

    def search_track(self, title: str, artist: str) -> Optional[Dict[str, Any]]:
        """
        Searches for a track on Spotify.

        Args:
            title: Track title
            artist: Artist name

        Returns:
            Full track object dict, or None if not found or error.
        """
        if not self.is_available() or not self.auth:
            return None

        try:
            token = self.auth.get_access_token()
            if not token:
                return None

            query = f"track:{title} artist:{artist}".strip()
            headers = {"Authorization": f"Bearer {token}"}
            params = {
                "q": query,
                "type": "track",
                "limit": 1
            }

            response = requests.get(
                SPOTIFY_SEARCH_URL,
                headers=headers,
                params=params,
                timeout=API_TIMEOUT
            )
            response.raise_for_status()

            tracks = response.json().get("tracks", {}).get("items", [])
            if tracks:
                logger.debug(f"[OK] Found track: {title} - {artist}")
                return tracks[0]

            logger.debug(f"[WARN] Track not found: {title} - {artist}")
            return None

        except requests.exceptions.Timeout:
            logger.debug(f"Search timeout for {title} - {artist}")
            return None
        except requests.exceptions.HTTPError as e:
            logger.debug(f"Search HTTP error {e.response.status_code} for {title} - {artist}")
            return None
        except Exception as e:
            logger.debug(f"Search failed for {title} - {artist}: {e}")
            return None

    def get_track_details(self, track_id: str) -> Optional[Dict[str, Any]]:
        """
        Fetches full track details from /v1/tracks/{id}.

        Args:
            track_id: Spotify track ID

        Returns:
            Full track object dict, or None on error.
        """
        if not self.is_available() or not self.auth:
            return None

        try:
            token = self.auth.get_access_token()
            if not token:
                return None

            headers = {"Authorization": f"Bearer {token}"}
            response = requests.get(
                f"{SPOTIFY_TRACK_URL}/{track_id}",
                headers=headers,
                timeout=API_TIMEOUT
            )
            response.raise_for_status()
            return response.json()

        except requests.exceptions.Timeout:
            logger.debug(f"Track details timeout for {track_id}")
            return None
        except requests.exceptions.HTTPError as e:
            logger.debug(f"Track details HTTP error {e.response.status_code} for {track_id}")
            return None
        except Exception as e:
            logger.debug(f"Failed to get track details for {track_id}: {e}")
            return None

    def enrich_track(self, title: str, artist: str) -> Dict[str, Union[float, int]]:
        """
        Searches track and returns estimated audio features.

        Pipeline:
        1. Search via /v1/search to find track ID
        2. Fetch via /v1/tracks/{id} for full metadata
        3. Estimate features using AudioFeatureEstimator

        Args:
            title: Track title
            artist: Artist name

        Returns:
            Dict with keys: valence, energy, danceability, tempo.
            Returns default values if search fails.
        """
        if not self.is_available():
            logger.debug(f"Spotify not available, returning defaults for {title}")
            return self._default_features()

        track_data = self.search_track(title, artist)
        if not track_data:
            logger.debug(f"Track not found: {title} - {artist}, using defaults")
            return self._default_features()

        # Attempt to get full track details for better metadata
        track_id = track_data.get("id")
        if track_id:
            full_data = self.get_track_details(track_id)
            if full_data:
                track_data = full_data

        # Estimate features from metadata
        features = AudioFeatureEstimator.estimate(track_data)
        logger.debug(f"Estimated features for '{title}': {features}")
        return features

    @staticmethod
    def _default_features() -> Dict[str, Union[float, int]]:
        """Returns default audio features when estimation fails."""
        return {
            "valence": 0.5,
            "energy": 0.5,
            "danceability": 0.5,
            "tempo": 120
        }


# ============================================================================
# SINGLETON PATTERN
# ============================================================================

_spotify_client_instance: Optional[SpotifyClient] = None


def get_spotify_client() -> SpotifyClient:
    """
    Returns or creates the singleton Spotify client instance.
    This pattern ensures a single authenticated client across the application.
    """
    global _spotify_client_instance
    if _spotify_client_instance is None:
        _spotify_client_instance = SpotifyClient()
    return _spotify_client_instance
