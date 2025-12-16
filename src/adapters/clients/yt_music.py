"""
YouTube Music client for listening history and sleep estimation.

This module provides:
- Access to YouTube Music listening history
- Enrichment with Spotify audio features
- Sleep schedule estimation based on music activity
"""

import os
import datetime
import logging
import re
from typing import List, Dict, Optional, Any, Union

# Handle ZoneInfo for Python < 3.9
try:
    from zoneinfo import ZoneInfo
except ImportError:
    from datetime import timezone, timedelta
    
    class ZoneInfo:  # type: ignore
        """Approximate fallback for ZoneInfo."""
        def __init__(self, key: str): 
            self.key = key
        def utcoffset(self, dt: datetime.datetime) -> timedelta: 
            return timedelta(hours=1)


from ytmusicapi import YTMusic

from . import spotify as spotify_client

logger = logging.getLogger(__name__)


# ============================================================================
# CONSTANTS
# ============================================================================

BROWSER_AUTH_FILES: List[str] = [
    "browser_auth_new.json",
    "browser_auth.json",
    "browser_auth_full.json",
]

HISTORY_LIMIT_DEFAULT: int = 500
ENRICHMENT_LIMIT_DEFAULT: int = 50

# Time windows for sleep estimation
SLEEP_WINDOW_START: int = 22  # 10 PM
SLEEP_WINDOW_END: int = 9     # 9 AM


# ============================================================================
# EXCEPTIONS
# ============================================================================

class YTMusicAuthError(Exception):
    """Raised when YouTube Music authentication fails."""
    pass


class YTMusicAPIError(Exception):
    """Raised when YouTube Music API call fails."""
    pass


# ============================================================================
# AUTHENTICATION
# ============================================================================

class YTMusicAuthenticator:
    """Handles YouTube Music browser authentication."""

    def __init__(self, auth_file_candidates: Optional[List[str]] = None):
        """
        Initialize authenticator.

        Args:
            auth_file_candidates: List of auth file paths to try.
        """
        self.auth_files = auth_file_candidates or BROWSER_AUTH_FILES

    def get_client(self) -> YTMusic:
        """
        Gets authenticated YTMusic client.
        Tries multiple auth file candidates.

        Returns:
            YTMusic client instance.

        Raises:
            YTMusicAuthError: If no valid auth file found.
        """
        for auth_file in self.auth_files:
            if os.path.exists(auth_file):
                try:
                    logger.info(f"[YTM] Using auth file: {auth_file}")
                    return YTMusic(auth_file)
                except Exception as e:
                    logger.warning(f"Failed to authenticate with {auth_file}: {e}")
                    continue

        raise YTMusicAuthError(
            "No valid browser auth file found. "
            "Generate one via: python scripts/create_browser_auth.py"
        )


# ============================================================================
# HISTORY NORMALIZATION
# ============================================================================

class HistoryNormalizer:
    """Normalizes YouTube Music history items."""

    @staticmethod
    def normalize(item: Dict[str, Any]) -> Dict[str, Any]:
        """
        Normalizes a YouTube Music history item.

        Args:
            item: Raw YouTube Music history item.

        Returns:
            Normalized dict with keys: title, artists, videoId, played.
        """
        artists = item.get("artists", [])
        artist_names = [a.get("name") for a in artists] if artists else []
        
        return {
            "title": item.get("title"),
            "artists": artist_names,
            "videoId": item.get("videoId"),
            "played": item.get("played") or item.get("subtitle") or "",
        }

    @staticmethod
    def deduplicate(items: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """
        Removes duplicate items by videoId while preserving order.

        Args:
            items: List of normalized items.

        Returns:
            Deduplicated list.
        """
        seen = set()
        unique = []

        for item in items:
            vid = item.get("videoId")
            if vid and vid in seen:
                continue
            if vid:
                seen.add(vid)
            unique.append(item)

        return unique


# ============================================================================
# HISTORY FETCHING
# ============================================================================

class HistoryFetcher:
    """Fetches YouTube Music listening history."""

    def __init__(self, limit: int = HISTORY_LIMIT_DEFAULT):
        self.limit = limit
        self.authenticator = YTMusicAuthenticator()

    def fetch_full_history(self) -> List[Dict[str, Any]]:
        """
        Fetches complete listening history.

        Returns:
            List of normalized history items.
        """
        try:
            yt = self.authenticator.get_client()
            logger.info("[YTM] Fetching YouTube Music history...")

            # Get history (ytmusicapi returns ~100-200 items per call typically)
            items = yt.get_history()
            if not items:
                logger.warning("[WARN] No history items returned")
                return []

            logger.info(f"[YTM] Got {len(items)} items from history")

            # Normalize items
            normalizer = HistoryNormalizer()
            normalized = [normalizer.normalize(item) for item in items]

            # Deduplicate
            unique = normalizer.deduplicate(normalized)

            # Apply limit
            result = unique[:self.limit]

            logger.info(f"[OK] History fetched: {len(result)} unique tracks (limit: {self.limit})")
            return result

        except Exception as e:
            logger.error(f"[ERROR] Failed to fetch history: {e}")
            raise YTMusicAPIError(f"History fetch failed: {e}") from e


# ============================================================================
# SLEEP ESTIMATION
# ============================================================================

class SleepEstimator:
    """
    Estimates sleep schedule from music activity using 'Longest Gap' logic.
    Refactored to handle timezone drift and late night sessions.
    """

    # Timezone for user (Hardcoded for consistency with User Request)
    USER_TZ = ZoneInfo("Europe/Paris")

    # Parsing Constants
    REGEX_MINUTES = re.compile(r'(\d+)\s*(?:minute|min)')
    REGEX_HOURS = re.compile(r'(\d+)\s*(?:hour|heure|h)')
    REGEX_YESTERDAY = re.compile(r'(?:yesterday|hier)', re.IGNORECASE)

    @staticmethod
    def estimate_sleep(tracks: List[Dict[str, Any]],
                      calendar_summary: str = "",
                      run_hour: int = 3) -> Dict[str, Any]:
        """
        Estimates sleep using the Longest Gap Method.
        Window: Yesterday 18:00 -> Today 13:00.
        """
        now_paris = datetime.datetime.now(SleepEstimator.USER_TZ)
        
        # 1. Parse timestamps
        valid_timestamps: List[datetime.datetime] = []
        for track in tracks:
            played_text = track.get("played", "")
            if isinstance(played_text, str):
                ts = SleepEstimator._parse_timestamp(played_text, now_paris)
                if ts:
                    valid_timestamps.append(ts)
        
        # 2. Define Search Window
        today_date = now_paris.date()
        window_start = datetime.datetime.combine(
            today_date - datetime.timedelta(days=1), 
            datetime.time(18, 0), 
            tzinfo=SleepEstimator.USER_TZ
        )
        window_end = datetime.datetime.combine(
            today_date, 
            datetime.time(13, 0), 
            tzinfo=SleepEstimator.USER_TZ
        )
        
        # 3. Filter & Sort
        window_tracks = sorted([t for t in valid_timestamps if window_start <= t <= window_end])
        
        if not window_tracks:
            return SleepEstimator._default_sleep_info(now_paris)

        # 4. Longest Gap Analysis
        if len(window_tracks) < 2:
             return SleepEstimator._default_sleep_info(now_paris)

        max_gap = datetime.timedelta(0)
        bedtime: Optional[datetime.datetime] = None
        waketime: Optional[datetime.datetime] = None
        found_gap = False
        
        for i in range(len(window_tracks) - 1):
            t1 = window_tracks[i]
            t2 = window_tracks[i+1]
            gap = t2 - t1
            
            # Gap must be significant (> 3.5 hours) to be sleep
            if gap > datetime.timedelta(hours=3, minutes=30):
                if gap > max_gap:
                    max_gap = gap
                    bedtime = t1
                    waketime = t2
                    found_gap = True
        
        # 5. Result Formatting
        if found_gap and bedtime and waketime:
            sleep_current_duration = max_gap.total_seconds() / 3600.0
            
            return {
                "bedtime": bedtime.strftime("%H:%M"),
                "wake_time": waketime.strftime("%H:%M"),
                "sleep_hours": round(sleep_current_duration, 1),
                "last_track_time": bedtime.strftime("%H:%M")
            }
        
        return SleepEstimator._default_sleep_info(now_paris)

    @staticmethod
    def _parse_timestamp(played_text: str, reference_time: datetime.datetime) -> Optional[datetime.datetime]:
        """
        Parses relative time string to absolute datetime.
        """
        if not played_text:
            return None
            
        played_text = played_text.lower()
        delta = datetime.timedelta(0)
        found_delta = False
        
        # Hours
        h_match = SleepEstimator.REGEX_HOURS.search(played_text)
        if h_match:
            delta += datetime.timedelta(hours=int(h_match.group(1)))
            found_delta = True
            
        # Minutes
        m_match = SleepEstimator.REGEX_MINUTES.search(played_text)
        if m_match:
            delta += datetime.timedelta(minutes=int(m_match.group(1)))
            found_delta = True
            
        if found_delta:
            return reference_time - delta
            
        # If "Yesterday" without hours, ambiguous -> Ignore
        if SleepEstimator.REGEX_YESTERDAY.search(played_text):
            # Using 24h ago as naive fallback would hurt precision
            return None
            
        return None

    @staticmethod
    def _default_sleep_info(reference_time: datetime.datetime) -> Dict[str, Any]:
        """Returns neutral default structure."""
        return {
            "bedtime": "00:00",
            "wake_time": "08:00",
            "sleep_hours": 8.0, 
            "last_track_time": "Unknown"
        }


# ============================================================================
# SPOTIFY ENRICHMENT
# ============================================================================

class SpotifyEnricher:
    """Enriches tracks with Spotify audio features."""

    def __init__(self, max_enrich: int = ENRICHMENT_LIMIT_DEFAULT):
        self.max_enrich = max_enrich
        self.spotify = spotify_client.get_spotify_client()

    def enrich_tracks(self, tracks: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """
        Enriches tracks with Spotify audio features.
        """
        if not self.spotify.is_available():
            logger.warning("[WARN] Spotify not available, skipping enrichment")
            return self._add_default_features(tracks)

        logger.info(f"[MUSIC] Enriching up to {self.max_enrich} tracks with Spotify features...")

        enriched = []
        for i, track in enumerate(tracks):
            if i >= self.max_enrich:
                enriched.extend(tracks[i:])
                break

            title = track.get("title", "")
            artists_list = track.get("artists", [])
            artist = ", ".join(artists_list) if artists_list else ""

            if title and artist:
                features = self.spotify.enrich_track(title, artist)
                # Ensure we got a valid dict back
                track["spotify"] = features if isinstance(features, dict) else self.spotify._default_features()
            else:
                track["spotify"] = self.spotify._default_features()

            enriched.append(track)

        logger.info(f"[OK] Enriched {min(self.max_enrich, len(tracks))} tracks")
        return enriched

    @staticmethod
    def _add_default_features(tracks: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """Adds default Spotify features to all tracks."""
        default_feats = {
            "valence": 0.5,
            "energy": 0.5,
            "danceability": 0.5,
            "tempo": 120
        }
        for track in tracks:
            track["spotify"] = default_feats.copy()
        return tracks


# ============================================================================
# PUBLIC API
# ============================================================================

def get_full_history(limit: int = HISTORY_LIMIT_DEFAULT) -> List[Dict[str, Any]]:
    """
    Public API to fetch complete YouTube Music listening history.
    """
    try:
        fetcher = HistoryFetcher(limit=limit)
        return fetcher.fetch_full_history()
    except Exception as e:
        logger.error(f"[ERROR] Failed to get full history: {e}")
        raise


def enrich_with_spotify(tracks: List[Dict[str, Any]],
                       max_enrich: int = ENRICHMENT_LIMIT_DEFAULT) -> List[Dict[str, Any]]:
    """
    Public API to enrich tracks with Spotify audio features.
    """
    enricher = SpotifyEnricher(max_enrich=max_enrich)
    return enricher.enrich_tracks(tracks)


def estimate_sleep_schedule(tracks: List[Dict[str, Any]],
                          calendar_summary: str = "",
                          run_hour: int = 3) -> Dict[str, Any]:
    """
    Public API to estimate sleep schedule from music activity.
    """
    estimator = SleepEstimator()
    return estimator.estimate_sleep(tracks, calendar_summary, run_hour)
