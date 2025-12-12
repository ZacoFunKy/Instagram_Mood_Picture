import os
import datetime
import sys
import argparse
import time
import random
import logging
from typing import List, Optional, Any, Dict
from dotenv import load_dotenv

# Add project root to sys.path to ensure imports work if run from nested dirs
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from connectors import mongo_client, yt_music, calendar_client, insta_web_client, gemini_client, weather_client

# Configure Logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(module)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

# Load env vars
load_dotenv()

def setup_arguments() -> argparse.Namespace:
    """Configures and parses command line arguments."""
    parser = argparse.ArgumentParser(description="Predictive Profile AI: Automated Mood & Profile Updater")
    parser.add_argument("--dry-run", action="store_true", help="Run simulation without external API calls (Gemini/Instagram)")
    parser.add_argument("--no-delay", action="store_true", help="Execute immediately without random sleep timer")
    parser.add_argument("--no-ai", action="store_true", help="Skip AI prediction and fallback to default mood 'energetic'")
    return parser.parse_args()

def handle_random_delay(args: argparse.Namespace) -> None:
    """Handles the random execution delay for stealth."""
    if not args.dry_run and not args.no_delay:
        delay_seconds = random.randint(0, 900) # 0-15 minutes
        logger.info(f"Adding random stealth delay of {delay_seconds} seconds...")
        time.sleep(delay_seconds)
    elif args.no_delay:
        logger.info("Random delay skipped (--no-delay).")

def fetch_db_history(weekday: str, dry_run: bool) -> List[str]:
    """Connects to MongoDB and retrieves historical mood data."""
    if dry_run:
        logger.info("Dry Run: Skipping DB Connection.")
        return []

    try:
        db = mongo_client.get_database()
        logs_col = db['daily_logs']
        
        # Maintenance: Clean old logs
        try:
            mongo_client.clean_old_logs(logs_col)
        except Exception as e:
            logger.warning(f"Log cleanup warning: {e}")

        history_docs = mongo_client.get_historical_moods(logs_col, weekday)
        moods = [doc.get('mood_selected') for doc in history_docs]
        logger.info(f"MongoDB Connected. History for {weekday}: {moods}")
        return moods
    except Exception as e:
        logger.error(f"MongoDB Error: {e}")
        logger.warning("⚠️ CONTINGENCY MODE: Proceeding without DB history.")
        return []

def get_music_summary_for_window(run_hour: int = 3) -> str:
    """Fetches yesterday's music (+ today if before run_hour).

    - Uses ytmusicapi browser auth history.
    - Filters items based on 'played' text: Yesterday/Hier, Aujourd'hui/Today, 'il y a' hours/minutes.
    """
    try:
        items = yt_music.get_full_history(limit=500)
        now = datetime.datetime.now()
        include_today = now.hour < run_hour
        filtered = []

        def is_today_played(text: str) -> bool:
            t = (text or "").lower()
            return any(s in t for s in ["today", "aujourd", "il y a", "minutes", "heures"]) and not any(s in t for s in ["yesterday", "hier"])

        def is_yesterday_played(text: str) -> bool:
            t = (text or "").lower()
            return any(s in t for s in ["yesterday", "hier"])

        for it in items:
            played = it.get("played", "")
            if is_yesterday_played(played) or (include_today and is_today_played(played)):
                artists = ", ".join(it.get("artists", [])).strip()
                title = it.get("title", "")
                if artists and title:
                    filtered.append(f"{artists} - {title}")

        if not filtered:
            # Fallback: take last ~30 items if heuristics fail
            for it in items[:30]:
                artists = ", ".join(it.get("artists", [])).strip()
                title = it.get("title", "")
                if artists and title:
                    filtered.append(f"{artists} - {title}")

        summary_str = ", ".join(filtered[:80])
        logger.info(f"Music window fetched. Count={len(filtered)} include_today={include_today}")
        return summary_str if summary_str else "No music in window"
    except Exception as e:
        logger.error(f"Music Fetch failed: {e}")
        return "No music data available (Error fetching)."

def get_calendar_summary() -> str:
    """Fetches calendar events."""
    try:
        events = calendar_client.get_week_events()
        logger.info("Calendar events fetched successfully.")
        return events
    except Exception as e:
        logger.error(f"Calendar Fetch failed: {e}")
        return f"Error fetching calendar: {e}"

def alert_failure(component: str, error: Exception, dry_run: bool) -> None:
    """Triggers a calendar alert event on critical failure."""
    if dry_run:
        return
    try:
        calendar_client.create_report_event(
            f"Echec {component}",
            f"Le script a rencontré une erreur critique sur {component}.\nErreur: {error}"
        )
        logger.info(f"Alert event created for {component} failure.")
    except Exception as ie:
        logger.error(f"Failed to create alert event: {ie}")

def save_daily_log(
    weekday: str, 
    mood: str, 
    music: str, 
    calendar: str, 
    dry_run: bool
) -> None:
    """Saves the execution log to MongoDB."""
    if dry_run:
        logger.info("Dry Run: Skipping DB Save.")
        return

    try:
        db = mongo_client.get_database()
        logs_col = db['daily_logs']
        
        entry = {
            "date": datetime.datetime.now().strftime("%Y-%m-%d"),
            "weekday": weekday,
            "mood_selected": mood,
            "music_summary": music[:200] + "..." if len(music) > 200 else music,
            "calendar_summary": calendar[:500] if len(calendar) > 500 else calendar,
        }
        mongo_client.save_log(logs_col, entry)
        logger.info("Daily log saved to MongoDB.")
    except Exception as e:
        logger.error(f"Failed to save log to MongoDB: {e}")

def main():
    args = setup_arguments()
    
    if args.dry_run:
        logger.info("--- DRY RUN MODE ACTIVATED ---")
    
    logger.info("--- Predictive Profile AI Starting ---")
    
    handle_random_delay(args)
    
    weekday: str = datetime.datetime.now().strftime("%A")
    logger.info(f"Date: {datetime.datetime.now().strftime('%Y-%m-%d')}, Weekday: {weekday}")

    # 1. Fetch Context Data
    historical_moods = fetch_db_history(weekday, args.dry_run)
    
    # Music
    try:
        music_summary_str = get_music_summary_for_window(run_hour=3)
    except Exception as music_err: 
         music_summary_str = "Error"
    
    # Check for failure string (returned by get_music_summary on handled error)
    if "Error" in music_summary_str and not args.dry_run:
         logger.error("Triggering Alert for Music Failure...")
         alert_failure("YouTube Music", Exception(music_summary_str), args.dry_run)

    # Calendar
    calendar_summary_str = get_calendar_summary()

    # Weather
    weather_summary_str = weather_client.get_bordeaux_weather()

    # 2. AI Prediction
    mood_name = "energetic" # Default fallback
    
    if args.no_ai:
        logger.info("Skipping AI prediction (--no-ai). Defaulting to 'energetic'.")
    else:
        try:
            if args.dry_run:
                 result = gemini_client.predict_mood(historical_moods, music_summary_str, calendar_summary_str, weather_summary_str, dry_run=True)
                 mood_name = result["mood"]
                 prompt = result["prompt"]
                 log_file = "dry_run_prompt.log"
                 with open(log_file, "w", encoding="utf-8") as f:
                     f.write(f"--- PROMPT GENERATED ON {datetime.datetime.now()} ---\n{prompt}")
                 logger.info(f"Dry run: Prompt saved to {log_file}")
            else:
                mood_name = gemini_client.predict_mood(historical_moods, music_summary_str, calendar_summary_str, weather_summary_str)
                logger.info(f">>> PREDICTED MOOD: {mood_name} <<<")
                
        except Exception as e:
            logger.error(f"AI Prediction Failed (Quota/API): {e}")
            logger.warning("⚠️ FALLBACK MODE: Defaulting to 'energetic' mood.")
            mood_name = "energetic"

    # 3. Action (Instagram)
    if not args.dry_run: # Logic check: dry_run handled in `save_daily_log` but not explicitly in action call in old code (it was try/expect)
         # Actually old code handled dry_run inside `predict_mood` returning early?
         # No, wait. 
         # In old code: if dry_run: return (it exited before instagram update).
         # So here we must wrap Instagram update.
        try:
            insta_web_client.update_profile_picture_web(mood_name)
        except Exception as e:
             logger.error(f"Instagram Update Failed: {e}")
             alert_failure("Instagram Update", e, args.dry_run)
    else:
        logger.info(f"Dry Run: Would update Instagram to {mood_name}")

    # 4. Save Log
    save_daily_log(weekday, mood_name, music_summary_str, calendar_summary_str, args.dry_run)
    
    logger.info("--- Execution Complete ---")

if __name__ == "__main__":
    main()
