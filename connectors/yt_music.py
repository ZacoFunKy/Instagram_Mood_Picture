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
from typing import List, Dict, Optional, Any, Tuple
import re

from ytmusicapi import YTMusic

from . import spotify_client


logger = logging.getLogger(__name__)

# ============================================================================
# CONSTANTS
# ============================================================================

BROWSER_AUTH_FILES = [
    "browser_auth_new.json",
    "browser_auth.json",
    "browser_auth_full.json",
]

HISTORY_LIMIT_DEFAULT = 500
ENRICHMENT_LIMIT_DEFAULT = 50

# Time windows for sleep estimation
SLEEP_WINDOW_START = 22  # 10 PM
SLEEP_WINDOW_END = 9     # 9 AM


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
            auth_file_candidates: List of auth file paths to try
        """
        self.auth_files = auth_file_candidates or BROWSER_AUTH_FILES

    def get_client(self) -> Any:
        """
        Gets authenticated YTMusic client.

        Tries multiple auth file candidates.

        Returns:
            YTMusic client instance

        Raises:
            YTMusicAuthError: If no valid auth file found
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
            f"No valid browser auth file found. "
            f"Generate one via: python scripts/create_browser_auth.py"
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

        Standardizes field names and extracts relevant data.

        Args:
            item: Raw YouTube Music history item

        Returns:
            Normalized dict with keys:
            - title: Track title
            - artists: List of artist names
            - videoId: Track ID
            - played: Play timestamp text (e.g., "Yesterday", "Il y a 3h")
        """
        return {
            "title": item.get("title"),
            "artists": [a.get("name") for a in item.get("artists", [])],
            "videoId": item.get("videoId"),
            "played": item.get("played") or item.get("subtitle") or "",
        }

    @staticmethod
    def deduplicate(items: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """
        Removes duplicate items by videoId while preserving order.

        Args:
            items: List of normalized items

        Returns:
            Deduplicated list
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
        """
        Initialize history fetcher.

        Args:
            limit: Maximum items to fetch
        """
        self.limit = limit
        self.authenticator = YTMusicAuthenticator()

    def fetch_full_history(self) -> List[Dict[str, Any]]:
        """
        Fetches complete listening history.

        Returns full history up to limit, deduplicated by videoId.

        Returns:
            List of normalized history items

        Example:
            >>> fetcher = HistoryFetcher(limit=500)
            >>> history = fetcher.fetch_full_history()
            >>> print(f"Fetched {len(history)} tracks")
        """
        try:
            yt = self.authenticator.get_client()
            logger.info("[YTM] Fetching YouTube Music history...")

            # Get history (ytmusicapi returns ~100-200 items)
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
    """Estimates sleep schedule from music activity."""

    @staticmethod
    def estimate_sleep(tracks: List[Dict[str, Any]],
                      calendar_summary: str = "",
                      run_hour: int = 3) -> Dict[str, Any]:
        """
        Estimates sleep schedule based on music activity.

        Logic:
        - Last track played before midnight = approximate bedtime
        - First track played after 6am = approximate wake time
        - Calculates duration from these estimates
        - For weekend/late runs where timestamps are unclear, uses reasonable defaults

        Args:
            tracks: List of enriched track items with 'played' timestamps
            calendar_summary: Calendar events (for wake time context)
            run_hour: Script execution hour (for context)

        Returns:
            Dict with keys:
            - bedtime: Estimated sleep time (HH:MM format)
            - wake_time: Estimated wake time (HH:MM format)
            - sleep_hours: Estimated sleep duration
            - last_track_time: Time of last track played

        Example:
            >>> sleep_info = SleepEstimator.estimate_sleep(tracks)
            >>> print(f"Sleep: {sleep_info['sleep_hours']}h "
            ...       f"({sleep_info['bedtime']} - {sleep_info['wake_time']})")
        """
        if not tracks:
            return SleepEstimator._default_sleep_info_with_fallback(run_hour, calendar_summary)

        # Extract played timestamps and convert to hours
        last_track_hour = None
        for track in reversed(tracks):  # Most recent first
            played_text = track.get("played", "").lower()
            hour = SleepEstimator._extract_hour_from_played(played_text)
            if hour is not None:
                last_track_hour = hour
                break

        if last_track_hour is None:
            # Tracks exist but timestamps unclear (weekend/late runs)
            # Provide reasonable default instead of 0
            return SleepEstimator._default_sleep_info_with_fallback(run_hour, calendar_summary)

        # Estimate bedtime: if last track was late evening, it's likely bedtime
        if last_track_hour >= SLEEP_WINDOW_START:  # >= 10 PM
            estimated_bedtime_hour = last_track_hour + 1  # Round up
            if estimated_bedtime_hour > 23:
                estimated_bedtime_hour = 0  # Midnight
        else:
            estimated_bedtime_hour = 0  # Default: midnight

        # Estimate wake time from calendar or default
        estimated_wake_hour = SleepEstimator._estimate_wake_time(calendar_summary, run_hour)

        # Calculate sleep duration
        if estimated_bedtime_hour <= estimated_wake_hour:
            sleep_hours = estimated_wake_hour - estimated_bedtime_hour
        else:
            sleep_hours = (24 - estimated_bedtime_hour) + estimated_wake_hour

        return {
            "bedtime": f"{estimated_bedtime_hour:02d}:{15:02d}",  # Approx :15
            "wake_time": f"{estimated_wake_hour:02d}:{10:02d}",   # Approx :10
            "sleep_hours": float(sleep_hours),
            "last_track_time": f"{last_track_hour:02d}:00"
        }

    @staticmethod
    def _extract_hour_from_played(played_text: str) -> Optional[int]:
        """
        Extracts hour from played text.

        Handles formats like:
        - "il y a 3 heures" → 3 hours ago
        - "yesterday" → 0 (yesterday evening)
        - "Today" → current hour

        Args:
            played_text: Played timestamp text

        Returns:
            Estimated hour (0-23), or None if unable to extract
        """
        if not played_text:
            return None

        # "il y a X heure(s)" pattern
        match = re.search(r'il y a (\d+) heure', played_text)
        if match:
            hours_ago = int(match.group(1))
            current_hour = datetime.datetime.now().hour
            return (current_hour - hours_ago) % 24

        # "X hours ago" pattern
        match = re.search(r'(\d+)\s*hour', played_text)
        if match:
            hours_ago = int(match.group(1))
            current_hour = datetime.datetime.now().hour
            return (current_hour - hours_ago) % 24

        # Yesterday pattern
        if any(s in played_text for s in ["yesterday", "hier"]):
            return 20  # Assume 8 PM yesterday

        return None

    @staticmethod
    def _estimate_wake_time(calendar_summary: str, run_hour: int) -> int:
        """
        Estimates wake time from calendar OR run_hour.

        Logic improved: Ne pas assumer 9h systématiquement.
        - Si événement matin (6h-12h) → utiliser heure événement - 1h
        - Si pas d'événement ET run_hour tôt (3h-8h) → assumer réveil proche
        - Si weekend/tard → assumer 8h-9h

        Args:
            calendar_summary: Calendar events text
            run_hour: Script execution hour (fallback)

        Returns:
            Estimated wake hour (0-23)
        """
        # Essayer d'extraire du calendrier d'abord
        if calendar_summary:
            # Only look for events in "FOCUS AUJOURD'HUI" section to avoid past/future events
            today_section = ""
            if "--- FOCUS AUJOURD'HUI ---" in calendar_summary:
                parts = calendar_summary.split("--- FOCUS AUJOURD'HUI ---")
                if len(parts) > 1:
                    content = parts[1]
                    # Stop at next section
                    if "--- CONTEXTE SEMAINE ---" in content:
                        today_section = content.split("--- CONTEXTE SEMAINE ---")[0]
                    else:
                        today_section = content
            
            # If we found a section and it's not empty/RIEN
            if today_section and "RIEN" not in today_section and "Busy" not in today_section:
                match = re.search(r'(\d{1,2}):(\d{2})', today_section)
                if match:
                    hour = int(match.group(1))
                    if 6 <= hour <= 12:  # Événement matin
                        return max(6, hour - 1)  # Réveil 1h avant

        # Pas d'événement ou pas matin → utiliser run_hour
        now = datetime.datetime.now()
        is_weekend = now.weekday() in [5, 6]
        
        if is_weekend:
            return 9  # Weekend: réveil naturel plus tard (9h au lieu de 8h)
        elif 3 <= run_hour <= 6:
            # Exécution tôt matin (3h-6h) → proche réveil
            return 7  # Assumer réveil ~7h
        elif run_hour >= 22 or run_hour <= 2:
            # Tard soir/nuit → réveil lendemain matin
            return 8
        else:
            # Par défaut semaine
            return 7

    @staticmethod
    def _default_sleep_info() -> Dict[str, Any]:
        """Returns default sleep info when estimation fails."""
        return {
            "bedtime": "Unknown",
            "wake_time": "Unknown",
            "sleep_hours": 0,
            "last_track_time": "Unknown"
        }

    @staticmethod
    def _default_sleep_info_with_fallback(run_hour: int, calendar_summary: str = "") -> Dict[str, Any]:
        """
        Returns reasonable sleep default for weekend/late runs.
        
        Instead of 0 hours (which triggers TIRED), assumes:
        - Uses calendar events if available (via _estimate_wake_time)
        - Weekend: User got good sleep (9h)
        - Late night: User got reasonable sleep (8h)
        - Bedtime: 00:00 (midnight)
        
        Args:
            run_hour: Current execution hour (for logging context)
            calendar_summary: Calendar events for wake time estimation
            
        Returns:
            Dict with reasonable sleep estimates
        """
        # Use standard wake time estimation (handles Calendar, Weekend, Late Night)
        wake_hour = SleepEstimator._estimate_wake_time(calendar_summary, run_hour)
        
        # Assume midnight bedtime for fallback
        bedtime_hour = 0
        
        # Calculate sleep (Wake - Bedtime)
        sleep_hours = float(wake_hour - bedtime_hour)
        
        return {
            "bedtime": "00:00",
            "wake_time": f"{wake_hour:02d}:00", 
            "sleep_hours": sleep_hours,
            "last_track_time": "Unknown (fallback)"
        }


# ============================================================================
# SPOTIFY ENRICHMENT
# ============================================================================

class SpotifyEnricher:
    """Enriches tracks with Spotify audio features."""

    def __init__(self, max_enrich: int = ENRICHMENT_LIMIT_DEFAULT):
        """
        Initialize enricher.

        Args:
            max_enrich: Maximum tracks to enrich (performance limit)
        """
        self.max_enrich = max_enrich
        self.spotify = spotify_client.get_spotify_client()

    def enrich_tracks(self, tracks: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """
        Enriches tracks with Spotify audio features.

        Limits enrichment to max_enrich to avoid rate limits.
        Tracks without Spotify data get default features.

        Args:
            tracks: List of track items with 'title' and 'artists' keys

        Returns:
            Same tracks with added 'spotify' key containing audio features

        Example:
            >>> enricher = SpotifyEnricher(max_enrich=50)
            >>> enriched = enricher.enrich_tracks(tracks)
            >>> print(enriched[0]['spotify']['energy'])
        """
        if not self.spotify.is_available():
            logger.warning("[WARN] Spotify not available, skipping enrichment")
            return self._add_default_features(tracks)

        logger.info(f"[MUSIC] Enriching up to {self.max_enrich} tracks with Spotify features...")

        enriched = []
        for i, track in enumerate(tracks):
            if i >= self.max_enrich:
                # Stop enrichment at limit, but include remaining tracks
                enriched.extend(tracks[i:])
                break

            title = track.get("title", "")
            artists_list = track.get("artists", [])
            artist = ", ".join(artists_list) if artists_list else ""

            if title and artist:
                features = self.spotify.enrich_track(title, artist)
                track["spotify"] = features
            else:
                track["spotify"] = self.spotify._default_features()

            enriched.append(track)

        logger.info(f"[OK] Enriched {min(self.max_enrich, len(tracks))} tracks")
        return enriched

    @staticmethod
    def _add_default_features(tracks: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """Adds default Spotify features to all tracks."""
        for track in tracks:
            track["spotify"] = {
                "valence": 0.5,
                "energy": 0.5,
                "danceability": 0.5,
                "tempo": 120
            }
        return tracks


# ============================================================================
# PUBLIC API
# ============================================================================

def get_full_history(limit: int = HISTORY_LIMIT_DEFAULT) -> List[Dict[str, Any]]:
    """
    Fetches complete YouTube Music listening history.

    Returns:
        List of normalized history items with keys:
        - title: Track title
        - artists: List of artist names
        - videoId: Track ID
        - played: Play timestamp text

    Raises:
        YTMusicAPIError: If history fetch fails

    Example:
        >>> history = get_full_history(limit=500)
        >>> print(f"Got {len(history)} tracks")
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
    Enriches tracks with Spotify audio features.

    Args:
        tracks: List of track dicts with 'title' and 'artists' keys
        max_enrich: Maximum number of tracks to enrich

    Returns:
        Same tracks with added 'spotify' key

    Example:
        >>> tracks = [{"title": "Shape of You", "artists": ["Ed Sheeran"]}]
        >>> enriched = enrich_with_spotify(tracks)
        >>> print(enriched[0]['spotify']['energy'])
    """
    enricher = SpotifyEnricher(max_enrich=max_enrich)
    return enricher.enrich_tracks(tracks)


def estimate_sleep_schedule(tracks: List[Dict[str, Any]],
                          calendar_summary: str = "",
                          run_hour: int = 3) -> Dict[str, Any]:
    """
    Estimates sleep schedule from music activity.

    Args:
        tracks: List of enriched track items
        calendar_summary: Calendar events for context
        run_hour: Script execution hour

    Returns:
        Dict with bedtime, wake_time, sleep_hours

    Example:
        >>> sleep_info = estimate_sleep_schedule(tracks)
        >>> print(f"Sleep: {sleep_info['sleep_hours']}h")
    """
    estimator = SleepEstimator()
    return estimator.estimate_sleep(tracks, calendar_summary, run_hour)
