"""
Predictive Profile AI: Automated Mood & Profile Picture Updater.

This module orchestrates a complete mood prediction pipeline:
1. Collects contextual data (calendar, weather, music, sleep)
2. Predicts mood using AI with cascade model fallback
3. Updates Instagram profile picture based on mood
4. Logs results to MongoDB

Supports execution modes:
- Normal: Full pipeline with API calls
- Dry run: Simulation mode without external updates
- No AI: Fallback to default mood without Gemini
- No delay: Immediate execution without random stealth delay
"""

import os
import sys
import argparse
import datetime
import logging
import statistics
from typing import List, Dict, Tuple, Any

from dotenv import load_dotenv

# Add project root for nested imports
# Add project root for nested imports
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from src.adapters.repositories import mongo as mongo_client
from src.adapters.clients import (
    yt_music,
    calendar as calendar_client,
    insta_web as insta_web_client,
    gemini as gemini_client,
    weather as weather_client
)
from src.adapters.clients.gemini import get_execution_type
from src.utils.db_maintenance import run_maintenance


# ============================================================================
# CONFIGURATION & SETUP
# ============================================================================

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(module)s - %(message)s',
    handlers=[logging.StreamHandler(sys.stdout)]
)
logger = logging.getLogger(__name__)

# Load environment variables
load_dotenv()

# Constants
DRY_RUN_PROMPT_FILE = "dry_run_prompt.log"
DEFAULT_FALLBACK_MOOD = "energetic"
MUSIC_ENRICHMENT_LIMIT = 20
MUSIC_HISTORY_LIMIT = 500


# ============================================================================
# ARGUMENT PARSING
# ============================================================================

def parse_arguments() -> argparse.Namespace:
    """
    Parses and validates command-line arguments.

    Returns:
        Parsed arguments namespace.
    """
    parser = argparse.ArgumentParser(
        description="Predictive Profile AI: Automated Mood & Profile Picture Updater",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python main.py                    # Normal execution with delay
  python main.py --dry-run          # Simulation mode with prompt output
  python main.py --no-ai            # Use default mood, skip Gemini
  python main.py --no-delay         # Execute immediately
  python main.py --dry-run --no-ai  # Simulate with default mood
        """
    )

    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Simulation mode: skip Instagram update, save prompt to file"
    )
    parser.add_argument(
        "--no-delay",
        action="store_true",
        help="Execute immediately without random 0-15min stealth delay"
    )
    parser.add_argument(
        "--no-ai",
        action="store_true",
        help="Skip AI prediction, fallback to default mood 'energetic'"
    )

    return parser.parse_args()


# ============================================================================
# DATABASE OPERATIONS
# ============================================================================

def fetch_historical_moods(weekday: str, execution_type: str, dry_run: bool) -> List[str]:
    """
    Retrieves historical mood patterns from MongoDB.

    Args:
        weekday: Current weekday name.
        dry_run: If True, skips database connection.

    Returns:
        List of historical mood strings.
    """
    if dry_run:
        logger.info("Dry run: skipping database connection")
        return []

    try:
        db = mongo_client.get_database()
        logs_collection = db['daily_logs']


        # Maintenance: Clean old logs
        try:
            mongo_client.clean_old_logs(logs_collection)
        except Exception as cleanup_error:
            logger.warning(f"Log cleanup warning: {cleanup_error}")

        # Retrieve historical moods
        historical_docs = mongo_client.get_historical_moods(logs_collection, weekday, execution_type)
        moods = [doc.get('mood_selected') for doc in historical_docs if doc.get('mood_selected')]

        logger.info(f"MongoDB connected. Historical moods for {weekday} ({execution_type}): {moods}")
        return moods  # type: ignore

    except Exception as db_error:
        logger.error(f"MongoDB error: {db_error}")
        logger.warning("[WARN] CONTINGENCY MODE: Proceeding without database history")
        return []


def save_daily_log(
    weekday: str,
    mood: str,
    music_summary: str,
    calendar_summary: str,
    execution_type: str,
    dry_run: bool,
    location: str = None
) -> None:
    """
    Saves execution log to MongoDB.

    Args:
        weekday: Current weekday.
        mood: Predicted mood.
        music_summary: Music history summary.
        calendar_summary: Calendar events summary.
        execution_type: Time of execution (MATIN, APRES_MIDI, SOIREE, NUIT).
        dry_run: If True, skips save.
        location: Location override (e.g., city name). If None, no location is saved.
    """
    if dry_run:
        logger.info("Dry run: skipping database save")
        return

    try:
        db = mongo_client.get_database()
        logs_collection = db['daily_logs']

        entry = {
            "date": datetime.datetime.now().strftime("%Y-%m-%d"),
            "weekday": weekday,
            "mood_selected": mood,
            "music_summary": music_summary[:200] + "..." if len(music_summary) > 200 else music_summary,
            "calendar_summary": calendar_summary[:500] if len(calendar_summary) > 500 else calendar_summary,
            "week_rhythm": "Standard", # Placeholder
            "execution_type": execution_type,
            "created_at": datetime.datetime.now().isoformat()
        }
        
        # Only add location if explicitly provided and not None
        if location:
            entry["location"] = location

        mongo_client.save_log(logs_collection, entry)
        logger.info("Daily log saved to MongoDB")

    except Exception as save_error:
        logger.error(f"Failed to save log to MongoDB: {save_error}")


# ============================================================================
# CONTEXT COLLECTION
# ============================================================================

def get_calendar_summary() -> str:
    """
    Fetches and summarizes calendar events.
    """
    try:
        events = calendar_client.get_week_events()
        logger.info("Calendar events fetched successfully")
        return events
    except Exception as calendar_error:
        logger.error(f"Calendar fetch failed: {calendar_error}")
        return f"Error fetching calendar: {calendar_error}"


def get_weather_summary(manual_city: str = None) -> str:
    """
    Fetches weather forecast for Bordeaux or manual city.
    """
    try:
        weather = weather_client.get_bordeaux_weather(manual_city)
        return weather
    except Exception as weather_error:
        logger.error(f"Weather fetch failed: {weather_error}")
        return "Weather unavailable (Error)"


# ============================================================================
# MUSIC ANALYSIS
# ============================================================================

def analyze_music_metrics(tracks: List[Dict[str, Any]]) -> Tuple[str, Dict[str, Any]]:
    """
    Analyzes music tracks to extract vibe summary and metrics.

    Args:
        tracks: List of track dicts with 'spotify' metadata.

    Returns:
        Tuple of (vibe_summary_string, metrics_dict).
    """
    if not tracks:
        return "Aucune écoute récente.", {
            "avg_energy": 0,
            "avg_valence": 0,
            "avg_tempo": 0,
            "dominant_vibe": "Silence"
        }

    valences = []
    energies = []
    tempos = []

    for track in tracks:
        spotify = track.get('spotify')
        if isinstance(spotify, dict): # Ensure dict type
            valences.append(spotify.get('valence', 0.5))
            energies.append(spotify.get('energy', 0.5))
            tempos.append(spotify.get('tempo', 120))

    if not valences:
        return "Métadonnées Spotify indisponibles.", {
            "avg_energy": 0.5,
            "avg_valence": 0.5,
            "avg_tempo": 120,
            "dominant_vibe": "Inconnu"
        }

    avg_valence = statistics.mean(valences)
    avg_energy = statistics.mean(energies)
    avg_tempo = statistics.mean(tempos)

    vibe = _classify_vibe(avg_valence, avg_energy, avg_tempo)
    summary = f"Vibe Global: {vibe} (Valence moy: {avg_valence:.2f}, Energy moy: {avg_energy:.2f}, Tempo moy: {avg_tempo:.0f} BPM)"

    metrics = {
        "avg_energy": round(avg_energy, 2),
        "avg_valence": round(avg_valence, 2),
        "avg_tempo": round(avg_tempo, 0),
        "dominant_vibe": vibe
    }

    return summary, metrics


def _classify_vibe(valence: float, energy: float, tempo: float) -> str:
    """Classifies vibe based on Spotify metrics."""
    if energy > 0.7 and tempo > 135:
        return "EXPLOSIF / AGRESSIF"
    elif valence < 0.35:
        return "SAD / MÉLANCOLIQUE"
    elif valence > 0.7 and energy > 0.6:
        return "HAPPY / FESTIF"
    elif energy < 0.4:
        return "CALME / CHILL"
    else:
        return "NEUTRE / FOCUS"


def get_music_summary_for_window(
    run_hour: int = 3,
    calendar_summary: str = "",
    override_sleep_hours: float = None
) -> Tuple[str, Dict[str, Any], Dict[str, Any]]:
    """
    Fetches and enriches music listsening history.
    """
    try:
        items = yt_music.get_full_history(limit=MUSIC_HISTORY_LIMIT)
        now = datetime.datetime.now()
        include_today = now.hour < run_hour

        # Date helpers
        def is_today_played(text: str) -> bool:
            if not text: return False
            t = text.lower()
            return (any(s in t for s in ["today", "aujourd", "il y a", "minutes", "heures"]) and
                    not any(s in t for s in ["yesterday", "hier"]))

        def is_yesterday_played(text: str) -> bool:
            return bool(text and any(s in text.lower() for s in ["yesterday", "hier"]))

        filtered_tracks = [
            item for item in items
            if is_yesterday_played(str(item.get("played", ""))) or 
               (include_today and is_today_played(str(item.get("played", ""))))
        ]

        if not filtered_tracks:
            logger.warning("Date filter found no tracks, using fallback (last 30 items)")
            filtered_tracks = items[:30]

        filtered_tracks = filtered_tracks[:MUSIC_ENRICHMENT_LIMIT]
        logger.info(f"Enriching {len(filtered_tracks)} tracks with Spotify audio features...")

        enriched_tracks = yt_music.enrich_with_spotify(
            filtered_tracks,
            max_enrich=MUSIC_ENRICHMENT_LIMIT
        )

        sleep_info = yt_music.estimate_sleep_schedule(
            enriched_tracks,
            calendar_summary=calendar_summary,
            run_hour=run_hour
        )

        if override_sleep_hours is not None:
             sleep_info["sleep_hours"] = float(override_sleep_hours)
             sleep_info["status"] = "MANUAL_OVERRIDE" 
             logger.info(f"!!! SLEEP OVERRIDE APPLIED: {sleep_info['sleep_hours']}h (Manual Input) !!!")
        else:
             logger.info(
                f"Sleep estimate: Bedtime {sleep_info['bedtime']}, "
                f"Wake {sleep_info['wake_time']}, "
                f"Duration {sleep_info['sleep_hours']}h"
            )

        vibe_summary, music_metrics = analyze_music_metrics(enriched_tracks)
        logger.info(f"Music analysis: {vibe_summary}")

        summary_parts = []
        for track in enriched_tracks:
            artists = ", ".join(track.get("artists", [])).strip()
            title = track.get("title", "")
            spotify = track.get("spotify")

            if not artists or not title:
                continue

            if isinstance(spotify, dict):
                val = spotify.get("valence", 0.5)
                enr = spotify.get("energy", 0.5)
                dnc = spotify.get("danceability", 0.5)
                tmp = int(spotify.get("tempo", 120))
                summary_parts.append(
                    f"{artists} - {title} [V:{val:.2f} E:{enr:.2f} D:{dnc:.2f} T:{tmp}]"
                )
            else:
                summary_parts.append(f"{artists} - {title}")

        summary_str = ", ".join(summary_parts)
        full_summary = f"{vibe_summary}\n\nTitres: {summary_str}" if summary_str else vibe_summary

        return full_summary, sleep_info, music_metrics

    except Exception as music_error:
        logger.error(f"Music fetch failed: {music_error}")
        return "No music data available (Error fetching).", {
            "bedtime": "Unknown",
            "wake_time": "Unknown",
            "sleep_hours": 0,
            "last_track_time": "Unknown"
        }, {
            "avg_energy": 0.5,
            "avg_valence": 0.5,
            "avg_tempo": 120,
            "dominant_vibe": "Inconnu"
        }


# ============================================================================
# ALERT MECHANISMS
# ============================================================================

def create_failure_alert(component: str, error: Exception, dry_run: bool) -> None:
    """Creates a calendar alert event on critical component failure."""
    if dry_run:
        logger.info(f"Dry run: Would create alert for {component} failure")
        return

    try:
        calendar_client.create_report_event(
            f"Echec {component}",
            f"Le script a rencontré une erreur critique sur {component}.\nErreur: {error}"
        )
        logger.info(f"Failure alert created for {component}")
    except Exception as alert_error:
        logger.error(f"Failed to create failure alert: {alert_error}")


# ============================================================================
# MAIN EXECUTION
# ============================================================================

def main() -> None:
    """
    Main execution function for mood prediction pipeline.
    """
    args = parse_arguments()

    if args.dry_run:
        logger.info("--- DRY RUN MODE ACTIVATED ---")
    logger.info("--- Predictive Profile AI Starting ---")

    now_dt = datetime.datetime.now()
    weekday = now_dt.strftime("%A")
    current_exec_type = get_execution_type(now_dt.hour).name
    logger.info(f"Timestamp: {now_dt.strftime('%Y-%m-%d %H:%M:%S')}, Weekday: {weekday}, Type: {current_exec_type}")

    # ========================================================================
    # STEP 0: Database Maintenance (Auto-Clean)
    # ========================================================================
    if not args.dry_run:
        try:
             run_maintenance()
        except Exception as maintenance_error:
             logger.warning(f"Database maintenance failed (non-blocking): {maintenance_error}")

    # ========================================================================
    # STEP 1: Collect Context Data
    # ========================================================================
    logger.info(">>> STEP 1: Collecting context data...")

    # Check for Mobile Overrides
    feedback_metrics = None
    manual_sleep = None
    steps_count = None
    override_location = None

    try:
        current_date_str = now_dt.strftime("%Y-%m-%d")
        overrides = mongo_client.get_daily_override(current_date_str)
        
        # 1. Extract Sleep Override (Hard Data)
        manual_sleep = overrides.get("sleep_hours")
        if manual_sleep:
            logger.info(f"!!! MANUAL SLEEP REPORT: {manual_sleep}h !!!")
            
        # 2. Extract Feedback Metrics (Soft Data for AI)
        if "feedback_energy" in overrides:
            feedback_metrics = {
                "energy": float(overrides.get("feedback_energy", 0.5)),
                "stress": float(overrides.get("feedback_stress", 0.5)),
                "social": float(overrides.get("feedback_social", 0.5))
            }
            logger.info(f"!!! USER FEEDBACK RECEIVED: {feedback_metrics} !!!")
        
        # 3. Extract Step Count
        steps_count = overrides.get("steps_count")
        if steps_count:
            logger.info(f"!!! STEP COUNT: {steps_count} steps !!!")

        # 4. Extract Location Override
        override_location = overrides.get("location")
        if override_location:
            logger.info(f"!!! LOCATION OVERRIDE: {override_location} !!!")

    except Exception as override_error:
        logger.warning(f"Failed to check mobile feedback: {override_error}")

    try:
        historical_moods = fetch_historical_moods(weekday, current_exec_type, args.dry_run)
        calendar_summary = get_calendar_summary()
        weather_summary = get_weather_summary(override_location)
    except Exception as context_error:
        logger.error(f"Context collection failed: {context_error}")
        weather_summary = "Weather Error"

    try:
        music_summary, sleep_info, music_metrics = get_music_summary_for_window(
            run_hour=3,
            calendar_summary=calendar_summary,
            override_sleep_hours=manual_sleep
        )
        
        # Override is now handled inside the function for better logging
             
    except Exception as music_error:
        logger.error(f"Music collection failed: {music_error}")
        music_summary = "Error fetching music data"
        sleep_info = {
            "bedtime": "Unknown",
            "wake_time": "Unknown",
            "sleep_hours": 0
        }
        music_metrics = {
            "avg_energy": 0.5,
            "avg_valence": 0.5,
            "avg_tempo": 120,
            "dominant_vibe": "Inconnu"
        }
        if not args.dry_run:
            create_failure_alert("YouTube Music", music_error, args.dry_run)

    # ========================================================================
    # STEP 2: Predict Mood
    # ========================================================================
    logger.info(">>> STEP 2: Predicting mood...")
    mood = DEFAULT_FALLBACK_MOOD

    if args.no_ai:
        logger.info("Skipping AI prediction (--no-ai). Using default: 'energetic'")
    else:
        try:
            calendar_events = calendar_client.get_calendar_events_structured()
            
            result = gemini_client.predict_mood(
                historical_moods=",".join(historical_moods), # Join list to string
                music_summary=music_summary,
                calendar_summary=calendar_summary,
                weather_summary=weather_summary,
                sleep_info=sleep_info,
                dry_run=args.dry_run,
                music_metrics=music_metrics,
                calendar_events=calendar_events,
                feedback_metrics=feedback_metrics,  # Pass user feedback
                steps_count=steps_count  # NEW: Pass step count
            )

            if isinstance(result, dict) and args.dry_run:
                mood = str(result.get("mood", DEFAULT_FALLBACK_MOOD))
                prompt = result.get("prompt", "")
                with open(DRY_RUN_PROMPT_FILE, "w", encoding="utf-8") as f:
                    f.write(f"--- PROMPT GENERATED ON {now_dt} ---\n{prompt}")
                logger.info(f"Dry run: Prompt saved to {DRY_RUN_PROMPT_FILE}")
            else:
                mood = str(result)
                logger.info(f">>> PREDICTED MOOD: {mood} <<<")

        except Exception as prediction_error:
            logger.error(f"AI prediction failed: {prediction_error}")
            logger.warning("[WARN] FALLBACK MODE: Using default mood")
            mood = DEFAULT_FALLBACK_MOOD

    # ========================================================================
    # STEP 3: Update Instagram
    # ========================================================================
    logger.info(">>> STEP 3: Updating Instagram profile...")

    if args.dry_run:
        logger.info(f"Dry run: Would update Instagram to {mood}")
    else:
        try:
            insta_web_client.update_profile_picture_web(mood)
            logger.info(f"[OK] Instagram profile updated to {mood}")
        except Exception as instagram_error:
            logger.error(f"Instagram update failed: {instagram_error}")
            create_failure_alert("Instagram Update", instagram_error, args.dry_run)

    # ========================================================================
    # STEP 4: Save Execution Log
    # ========================================================================
    logger.info(">>> STEP 4: Saving execution log...")
    
    # Determine which location was actually used
    # Only use override_location if it's explicitly provided and not empty
    # Avoid "Bordeaux (Default/History)" - leave as None/empty if missing
    final_location = override_location if (override_location and override_location.strip()) else None
    
    save_daily_log(weekday, mood, music_summary, calendar_summary, current_exec_type, args.dry_run, location=final_location)

    logger.info("--- Execution Complete ---")


if __name__ == "__main__":
    main()
