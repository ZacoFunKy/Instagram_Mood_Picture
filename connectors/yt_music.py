from ytmusicapi import YTMusic
import os
import json
import datetime

def get_service():
    """Initializes YTMusic with headers from env var or local file."""
    
    # 1. Priority: OAuth (Production/CI - Recommended)
    oauth_env = os.environ.get("YTMUSIC_OAUTH")
    if oauth_env:
        try:
            # Check if it's already a file path or raw JSON
            # We assume it's the raw JSON content of oauth.json
            with open("oauth.json", "w", encoding='utf-8') as f:
                f.write(oauth_env)
            return YTMusic("oauth.json")
        except Exception as e:
            print(f"Error initializing YTMusic via OAuth: {e}")

    # 2. Priority: Legacy Headers (Env)
    headers_json = os.environ.get("YTMUSIC_HEADERS")
    if headers_json:
        try:
            headers_dict = json.loads(headers_json)
            return YTMusic(auth=headers_dict)
        except Exception as e:
             pass

    # 3. Priority: Local File (Development)
    if os.path.exists("headers_auth.json"):
        try:
            return YTMusic("headers_auth.json")
        except:
             pass

    # 4. Fallback / Failure
    raise ValueError("YouTube Music authentication failed. Set YTMUSIC_OAUTH (preferred) or YTMUSIC_HEADERS.")

def get_yesterday_music():
    """
    Fetches history for yesterday (J-1 06:00 to J 03:00 roughly).
    Since API limits/structure might be simple 'history', we just fetch recent history 
    and filter by timestamp if possible, or just take the last N tracks that likely cover "yesterday evening".
    """
    yt = get_service()
    
    # Fetch history. 
    # logic: The script runs at 3AM. 
    # We want to know what was listened to "yesterday" and "earlier tonight".
    # Just fetching the last 50-100 tracks is usually a good proxy for "recent vibe".
    history = yt.get_history()
    
    # We can try to summarize it.
    # Return a list of "Artist - Title"
    summary = []
    for item in history[:50]: # Last 50 tracks (increased from 20 for better accuracy)
        title = item.get('title')
        artists = ", ".join([a['name'] for a in item.get('artists', [])])
        summary.append(f"{artists} - {title}")
    
    
        
    return summary
