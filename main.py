import os
import datetime
import sys
import argparse
import time
import random
from dotenv import load_dotenv

# Load env vars from .env for local testing
load_dotenv()

# Add project root to sys.path to ensure imports work
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from connectors import mongo_client, yt_music, calendar_client, insta_web_client, gemini_client

def main():
    parser = argparse.ArgumentParser(description="Predictive Profile AI")
    parser.add_argument("--no-ai", action="store_true", help="Skip Gemini and default to energetic")
    args = parser.parse_args()
    
    # ... (skipping unchanged parts)

    # 3. AI Prediction
    mood_name = "energetic" # Default fallback
    
    if args.no_ai:
        print("Skipping AI prediction (--no-ai). Defaulting to 'energetic'.")
        mood_name = "energetic"
    else:
        try:
            if args.dry_run:
                 result = gemini_client.predict_mood(historical_moods, music_summary_str, calendar_summary_str, dry_run=True)
                 mood_name = result["mood"] # "dry_run"
                 prompt = result["prompt"]
                 
                 # Save to log
                 log_file = "dry_run_prompt.log"
                 with open(log_file, "w", encoding="utf-8") as f:
                     f.write(f"--- PROMPT GENERATED ON {datetime.datetime.now()} ---\n")
                     f.write(prompt)
                 print(f"Dry run: Prompt saved to {log_file}")
                 print("Dry run: Skipping Instagram update and Mongo save.")
                 return
                 
            mood_name = gemini_client.predict_mood(historical_moods, music_summary_str, calendar_summary_str)
            print(f">>> PREDICTED MOOD: {mood_name} <<<")
            
        except Exception as e:
            print(f"Error generating prediction (Quota/API Fail): {e}")
            print("⚠️ FALLBACK MODE: Defaulting to 'energetic' mood.")
            mood_name = "energetic"

    # 4. Action (Instagram)
    try:
        insta_web_client.update_profile_picture_web(mood_name)
    except Exception as e:
        print(f"Error updating Instagram: {e}")

    # 5. Save Log
    log_entry = {
        "date": datetime.datetime.now().strftime("%Y-%m-%d"),
        "weekday": weekday,
        "mood_selected": mood_name,
        "music_summary": music_summary_str[:200] + "..." if len(music_summary_str) > 200 else music_summary_str,
        "calendar_summary": calendar_summary_str[:500] if len(calendar_summary_str) > 500 else calendar_summary_str,
    }
    
    try:
        if logs_col is not None:
            # function is save_log(collection, data)
            mongo_client.save_log(logs_col, log_entry)
            print("Daily log saved to MongoDB.")
        else:
            print("Skipping MongoDB save (Not connected).")
    except Exception as e:
        print(f"Error saving log: {e}")

    print("--- Execution Complete ---")

if __name__ == "__main__":
    main()
