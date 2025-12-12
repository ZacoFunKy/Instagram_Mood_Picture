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
    parser.add_argument("--dry-run", action="store_true", help="Run without calling Gemini or updating Instagram")
    parser.add_argument("--no-delay", action="store_true", help="Skip the random start delay")
    args = parser.parse_args()
    
    if args.dry_run:
        print("--- DRY RUN MODE ACTIVATED ---")

    print("--- Predictive Profile AI Starting ---")
    
    # [OPT] Randomize execution time (+/- 15 mins delay)
    # Cron runs at 3:00. We delay between 0 and 900 seconds (15 mins).
    if not args.dry_run and not args.no_delay:
        delay = random.randint(0, 900)
        print(f"Adding random delay of {delay} seconds to avoid detection...")
        time.sleep(delay)
    elif args.no_delay:
        print("Skipping random delay (--no-delay).")
    
    # 1. Connect DB & Fetch History
    historical_moods = []
    logs_col = None
    weekday = datetime.datetime.now().strftime("%A")
    
    try:
        db = mongo_client.get_database()
        logs_col = db['daily_logs']
        
        # Clean old logs first (pass collection!)
        if not args.dry_run:
             try:
                 mongo_client.clean_old_logs(logs_col)
             except Exception as cleanup_err:
                 print(f"Warning during cleanup: {cleanup_err}")
        
        # Fetch history (pass collection!)
        # arguments: collection, weekday
        history_docs = mongo_client.get_historical_moods(logs_col, weekday)
        historical_moods = [doc.get('mood_selected') for doc in history_docs]
        
        print("Connected to MongoDB.")
    except Exception as e:
        print(f"Error connecting to MongoDB/Fetching History: {e}")
        print("⚠️ CONTINGENCY MODE: Continuing without Database history.")
        # Proceed with empty history, do not return


    # 2. Data Fetching
    print(f"Date: {datetime.datetime.now().strftime('%Y-%m-%d')}, Weekday: {weekday}")
    print(f"History for {weekday}: {historical_moods}")
    
    # B. Music
    music_summary_str = "No music data available."
    try:
        music_summary = yt_music.get_yesterday_music()
        if isinstance(music_summary, list):
            music_summary_str = ", ".join(music_summary)
        else:
            music_summary_str = str(music_summary)
        print("Fetched Music History.")
    except Exception as e:
        print(f"Error fetching Music: {e}")
        print("Continuing without music data...")
        music_summary_str = "No music data available (Error fetching)."

    # C. Calendar
    calendar_summary_str = "No events."
    try:
        # get_today_events returns a string (joined events or message)
        calendar_summary_str = calendar_client.get_week_events()
        print("Fetched Calendar Events.")
    except Exception as e:
        print(f"Error fetching Calendar: {e}")
        calendar_summary_str = f"Error fetching calendar: {e}"

    # 3. AI Prediction
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
        print(f"Error generating prediction: {e}")
        return

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
