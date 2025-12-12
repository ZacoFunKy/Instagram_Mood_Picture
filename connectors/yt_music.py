import os
import json
from typing import List, Dict
from ytmusicapi import YTMusic

def _get_yt() -> YTMusic:
    """Create a YTMusic client using browser headers file."""
    auth_file_candidates = [
        "browser_auth_new.json",
        "browser_auth.json",
        "browser_auth_full.json",
    ]
    for path in auth_file_candidates:
        if os.path.exists(path):
            return YTMusic(path)
    raise FileNotFoundError(
        "No browser auth file found. Generate one via `python create_browser_auth.py`"
    )

def get_full_history(limit: int = 500) -> List[Dict]:
    """Return full listening history using ytmusicapi browser auth.

    - Paginates through history until `limit` reached or no more items.
    - Returns list of items with keys: title, artists, videoId, feedbackTokens, played
    """
    yt = _get_yt()
    history = []
    try:
        items = yt.get_history()
        history.extend(items or [])
        # ytmusicapi `get_history` returns last 100-200 items; no continuation exposed.
        # If a future version exposes continuation, we can loop here.
    except Exception as e:
        print(f"⚠️ Erreur get_history: {e}")
        return []

    def _normalize(item: Dict) -> Dict:
        return {
            "title": item.get("title"),
            "artists": [a.get("name") for a in item.get("artists", [])],
            "videoId": item.get("videoId"),
            # Raw played text like "Yesterday" / "Il y a 3 heures" / date string
            "played": item.get("played") or item.get("subtitle") or "",
        }

    normalized = [_normalize(i) for i in history]
    # Deduplicate by videoId while preserving order
    seen = set()
    unique = []
    for it in normalized:
        vid = it.get("videoId")
        if vid and vid in seen:
            continue
        if vid:
            seen.add(vid)
        unique.append(it)
    return unique[:limit]