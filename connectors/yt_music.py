from ytmusicapi import YTMusic
import os
import json
import datetime

def get_service():
    """Initializes YTMusic with headers from env var."""
    headers_json = os.environ.get("YTMUSIC_HEADERS")
    if not headers_json:
        raise ValueError("YTMUSIC_HEADERS environment variable not set")
    
    # Priority 1: Browser Auth (headers_auth.json)
    if os.path.exists("headers_auth.json"):
        print("Using Browser Auth (headers_auth.json)...")
        try:
            with open("headers_auth.json", "r", encoding='utf-8') as f:
                browser_headers = json.load(f)
            return YTMusic(auth=browser_headers)
        except json.JSONDecodeError as e:
            print(f"CRITICAL ERROR reading headers_auth.json: {e}")
            with open("headers_auth.json", "r", encoding='utf-8') as f:
                print(f"File content preview: {f.read()[:100]}")
            raise e

    # Priority 2: OAuth (from env)
    # Try to load formatted JSON from env
    try:
        headers = json.loads(headers_json)
        # Split into tokens.json and creds.json
        # creds.json needs client_id, client_secret (and maybe nothing else)
        # [FIX] Use env vars for sensitive OAuth data
        creds = {
            "client_id": os.environ.get("GOOGLE_CLIENT_ID", "YOUR_CLIENT_ID"),
            "client_secret": os.environ.get("GOOGLE_CLIENT_SECRET", "YOUR_CLIENT_SECRET")
        }
        with open("creds.json", "w") as f:
            json.dump(creds, f)

        # tokens.json needs the tokens (headers_json provided by user)
        # We assume headers contains keys like access_token, etc.
        # We REMOVE client_id/secret from this one to be safe
        tokens = {k:v for k,v in headers.items() if k not in ["client_id", "client_secret"]}
        
        with open("tokens.json", "w") as f:
            json.dump(tokens, f)
            
        return YTMusic(auth="tokens.json", oauth_credentials="creds.json")
    except json.JSONDecodeError:
        raise ValueError("YTMUSIC_HEADERS must be valid JSON")

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
