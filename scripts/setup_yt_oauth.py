from ytmusicapi.setup import setup_oauth
import os
from dotenv import load_dotenv

load_dotenv()

def setup():
    print("--- YouTube Music OAuth Setup ---")
    print("This script will help you generate the 'oauth.json' file.")
    print("1. You will be asked to visit a Google URL.")
    print("2. Log in with your YouTube Music account.")
    print("3. Allow access.")
    print("4. Press Enter here when done.")
    print("\nStarting setup...\n")
    
    # Load credentials from .env
    # Note: These must be set in .env or passed manually
    client_id = os.environ.get("GOOGLE_CLIENT_ID")
    client_secret = os.environ.get("GOOGLE_CLIENT_SECRET")
    
    if not client_id or not client_secret:
        print("❌ Error: GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET not found in .env.")
        print("Please ensure your .env file contains these keys.")
        return

    # Use the standalone function with required args
    setup_oauth(client_id=client_id, client_secret=client_secret, filepath="oauth.json")
    
    print("\n✅ Success! 'oauth.json' has been created.")
    print("👉 Open this file, copy its ENTIRE content, and paste it into your .env variable 'YTMUSIC_OAUTH' or GitHub Secret.")

if __name__ == "__main__":
    setup()
