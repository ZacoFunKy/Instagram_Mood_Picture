"""Test script to verify ytmusicapi browser authentication and history retrieval."""
import sys
import os
# Add parent directory to path to import connectors
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from connectors.yt_music import get_full_history

print("Testing ytmusicapi browser authentication...\n")

try:
    history = get_full_history(limit=30)
    
    if not history:
        print("⚠️  No history items returned.")
        sys.exit(1)
    
    print(f"✅ SUCCESS! Retrieved {len(history)} items from history\n")
    print("Recent plays:")
    print("=" * 70)
    
    for i, item in enumerate(history[:30], 1):
        title = item.get('title', 'N/A')
        artists = ", ".join(item.get('artists', []))
        played = item.get('played', '')
        print(f"{i:2d}. {artists} - {title}")
        if played:
            print(f"    ({played})")
    
    print("=" * 70)
    print("\n✅ YTMUSICAPI BROWSER AUTH WORKING!")
    
except FileNotFoundError as e:
    print(f"❌ Auth file not found: {e}")
    print("\nRun 'python create_browser_auth.py' to generate browser_auth_new.json")
    sys.exit(1)
    
except Exception as e:
    print(f"❌ Error: {repr(e)}")
    import traceback
    traceback.print_exc()
    sys.exit(1)
