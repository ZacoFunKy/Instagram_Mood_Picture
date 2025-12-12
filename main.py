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

The script differentiates between morning (3am) and afternoon (14h) executions
for contextually appropriate mood predictions.
"""

import os
import datetime
import sys
import argparse
import time
import random
import logging
import statistics
from typing import List, Optional, Dict, Tuple, Any

from dotenv import load_dotenv

# Add project root for nested imports
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from connectors import (
    mongo_client,
    yt_music,
    calendar_client,
    insta_web_client,
    gemini_client,
    weather_client
)


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
RANDOM_DELAY_MAX_SECONDS = 900  # 15 minutes
DRY_RUN_PROMPT_FILE = "dry_run_prompt.log"
DEFAULT_FALLBACK_MOOD = "energetic"
MUSIC_ENRICHMENT_LIMIT = 50
MUSIC_HISTORY_LIMIT = 500


# ============================================================================
# ARGUMENT PARSING
# ============================================================================

def parse_arguments() -> argparse.Namespace:
    """
    Parses and validates command-line arguments.

    Returns:
        Parsed arguments namespace

    Raises:
        SystemExit: If argument parsing fails
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
# EXECUTION FLOW
# ============================================================================

def apply_stealth_delay(no_delay: bool) -> None:
    """
    Applies random execution delay for stealth/load distribution.

    Args:
        no_delay: If True, skips delay entirely

    Raises:
        None (logs warnings/info only)
    """
    if no_delay:
        logger.info("Random delay skipped (--no-delay flag)")
        return

    delay_seconds = random.randint(0, RANDOM_DELAY_MAX_SECONDS)
    logger.info(f"Applying random stealth delay: {delay_seconds}s (0-15 min)")
    time.sleep(delay_seconds)


# ============================================================================
# DATABASE OPERATIONS
# ============================================================================

def fetch_historical_moods(weekday: str, dry_run: bool) -> List[str]:
    """
    Retrieves historical mood patterns from MongoDB.

    For database analysis and trend detection.

    Args:
        weekday: Current weekday name (Monday, Tuesday, etc.)
        dry_run: If True, skips database connection

    Returns:
        List of historical mood strings, empty list on error or dry_run

    Logs:
        Connection status, retrieved history, or warnings/errors
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
        historical_docs = mongo_client.get_historical_moods(logs_collection, weekday)
        moods = [doc.get('mood_selected') for doc in historical_docs if doc.get('mood_selected')]

        logger.info(f"MongoDB connected. Historical moods for {weekday}: {moods}")
        return moods

    except Exception as db_error:
        logger.error(f"MongoDB error: {db_error}")
        logger.warning("[WARN] CONTINGENCY MODE: Proceeding without database history")
        return []


def save_daily_log(
    weekday: str,
    mood: str,
    music_summary: str,
    calendar_summary: str,
    dry_run: bool
) -> None:
    """
    Saves execution log to MongoDB.

    Args:
        weekday: Current weekday
        mood: Predicted mood
        music_summary: Music history summary
        calendar_summary: Calendar events summary
        dry_run: If True, skips save

    Raises:
        None (logs errors only, doesn't propagate)
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
        }

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

    Returns:
        Calendar events as formatted string, or error message

    Logs:
        Success or failure information
    """
    try:
        events = calendar_client.get_week_events()
        logger.info("Calendar events fetched successfully")
        return events
    except Exception as calendar_error:
        logger.error(f"Calendar fetch failed: {calendar_error}")
        return f"Error fetching calendar: {calendar_error}"


def get_weather_summary() -> str:
    """
    Fetches weather forecast for Bordeaux.

    Returns:
        Weather summary string

    Logs:
        Weather data or errors
    """
    try:
        weather = weather_client.get_bordeaux_weather()
        # Log already done by weather_client, no need to duplicate
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

    Calculates average valence, energy, and tempo to determine
    overall listening vibe for AI context.

    Args:
        tracks: List of track dicts with 'spotify' metadata

    Returns:
        Tuple of (vibe_summary_string, metrics_dict)

    Logic:
        - Extracts Spotify features (valence, energy, tempo)
        - Calculates averages using statistics.mean()
        - Determines vibe classification based on ranges
        - Returns human-readable summary + structured metrics
    """
    if not tracks:
        return "Aucune écoute récente.", {
            "avg_energy": 0,
            "avg_valence": 0,
            "avg_tempo": 0,
            "dominant_vibe": "Silence"
        }

    # Extract Spotify metrics from tracks
    valences = []
    energies = []
    tempos = []

    for track in tracks:
        spotify = track.get('spotify')
        if spotify:
            valences.append(spotify.get('valence', 0.5))
            energies.append(spotify.get('energy', 0.5))
            tempos.append(spotify.get('tempo', 120))

    # Handle no Spotify data
    if not valences:
        return "Métadonnées Spotify indisponibles.", {
            "avg_energy": 0.5,
            "avg_valence": 0.5,
            "avg_tempo": 120,
            "dominant_vibe": "Inconnu"
        }

    # Calculate averages
    avg_valence = statistics.mean(valences)
    avg_energy = statistics.mean(energies)
    avg_tempo = statistics.mean(tempos)

    # Classify vibe based on metrics
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
    """
    Classifies vibe based on Spotify metrics.

    Args:
        valence: Positivity score (0-1)
        energy: Intensity score (0-1)
        tempo: Tempo in BPM

    Returns:
        Vibe classification string
    """
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
    calendar_summary: str = ""
) -> Tuple[str, Dict[str, Any], Dict[str, Any]]:
    """
    Fetches and enriches music listening history.

    This function:
    1. Retrieves full YouTube Music history
    2. Filters by date (yesterday + today if before run_hour)
    3. Enriches with Spotify audio features
    4. Estimates sleep schedule from music activity
    5. Analyzes metrics for AI context
    6. Formats results for prompt injection

    Args:
        run_hour: Script execution hour (default 3am)
        calendar_summary: Calendar data for wake time estimation

    Returns:
        Tuple of (formatted_summary_string, sleep_info_dict, music_metrics_dict)
        where sleep_info contains: bedtime, wake_time, sleep_hours
        and music_metrics contains: avg_valence, avg_energy, avg_tempo, dominant_vibe

    Raises:
        Exception: Caught internally, returns error message with defaults

    Logic:
        - "yesterday" tracks always included
        - "today" tracks included only if current hour < run_hour
        - Fallback to last 30 items if heuristics fail
        - Limits to MUSIC_ENRICHMENT_LIMIT tracks for performance
        - Builds summary with [V:valence E:energy D:danceability T:tempo] format
    """
    try:
        # Fetch YouTube Music history
        items = yt_music.get_full_history(limit=MUSIC_HISTORY_LIMIT)
        now = datetime.datetime.now()
        include_today = now.hour < run_hour

        # Helper functions for date filtering
        def is_today_played(text: Optional[str]) -> bool:
            """Checks if text indicates today's play."""
            if not text:
                return False
            t = text.lower()
            return (any(s in t for s in ["today", "aujourd", "il y a", "minutes", "heures"]) and
                    not any(s in t for s in ["yesterday", "hier"]))

        def is_yesterday_played(text: Optional[str]) -> bool:
            """Checks if text indicates yesterday's play."""
            return text and any(s in text.lower() for s in ["yesterday", "hier"])

        # Filter tracks by date
        filtered_tracks = [
            item for item in items
            if is_yesterday_played(item.get("played", "")) or 
               (include_today and is_today_played(item.get("played", "")))
        ]

        # Fallback: use last 30 items if filter found nothing
        if not filtered_tracks:
            logger.warning("Date filter found no tracks, using fallback (last 30 items)")
            filtered_tracks = items[:30]

        # Limit track count for performance
        filtered_tracks = filtered_tracks[:MUSIC_ENRICHMENT_LIMIT]

        logger.info(f"Enriching {len(filtered_tracks)} tracks with Spotify audio features...")

        # Enrich with Spotify features
        enriched_tracks = yt_music.enrich_with_spotify(
            filtered_tracks,
            max_enrich=MUSIC_ENRICHMENT_LIMIT
        )

        # Estimate sleep schedule
        sleep_info = yt_music.estimate_sleep_schedule(
            enriched_tracks,
            calendar_summary=calendar_summary,
            run_hour=run_hour
        )
        logger.info(
            f"Sleep estimate: Bedtime {sleep_info['bedtime']}, "
            f"Wake {sleep_info['wake_time']}, "
            f"Duration {sleep_info['sleep_hours']}h"
        )

        # Analyze music metrics
        vibe_summary, music_metrics = analyze_music_metrics(enriched_tracks)
        logger.info(f"Music analysis: {vibe_summary}")

        # Build track summary with features
        summary_parts = []
        for track in enriched_tracks:
            artists = ", ".join(track.get("artists", [])).strip()
            title = track.get("title", "")
            spotify = track.get("spotify")

            if not artists or not title:
                continue

            if spotify:
                # Format: "Artist - Title [V:0.8 E:0.7 D:0.6 T:128]"
                valence = spotify.get("valence", 0.5)
                energy = spotify.get("energy", 0.5)
                danceability = spotify.get("danceability", 0.5)
                tempo = int(spotify.get("tempo", 120))
                summary_parts.append(
                    f"{artists} - {title} [V:{valence:.2f} E:{energy:.2f} D:{danceability:.2f} T:{tempo}]"
                )
            else:
                summary_parts.append(f"{artists} - {title}")

        summary_str = ", ".join(summary_parts)
        logger.info(f"Music window: {len(enriched_tracks)} tracks, include_today={include_today}")

        # Combine vibe summary with track list
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
    """
    Creates a calendar alert event on critical component failure.

    Used for monitoring: critical failures are recorded as calendar events
    for user awareness and debugging.

    Args:
        component: Component name (e.g., "YouTube Music", "Instagram")
        error: Exception that caused the failure
        dry_run: If True, skips alert creation

    Raises:
        None (logs errors only, doesn't propagate)
    """
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

    Workflow:
    1. Parse arguments and apply stealth delay
    2. Collect context data (calendar, weather, music, sleep)
    3. Predict mood using AI or fallback
    4. Update Instagram profile picture
    5. Save execution log to database

    Handles errors gracefully with fallbacks and alerts.
    """
    args = parse_arguments()

    # Logging
    if args.dry_run:
        logger.info("--- DRY RUN MODE ACTIVATED ---")
    logger.info("--- Predictive Profile AI Starting ---")

    # Apply stealth delay
    apply_stealth_delay(args.no_delay)

    # Setup temporal context
    now = datetime.datetime.now()
    weekday = now.strftime("%A")
    logger.info(f"Timestamp: {now.strftime('%Y-%m-%d %H:%M:%S')}, Weekday: {weekday}")

    # ========================================================================
    # STEP 1: Collect Context Data
    # ========================================================================

    logger.info(">>> STEP 1: Collecting context data...")

    # Historical moods
    historical_moods = fetch_historical_moods(weekday, args.dry_run)

    # Calendar
    calendar_summary = get_calendar_summary()

    # Weather
    weather_summary = get_weather_summary()

    # Music (uses calendar for sleep estimation)
    try:
        music_summary, sleep_info, music_metrics = get_music_summary_for_window(
            run_hour=3,
            calendar_summary=calendar_summary
        )
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
        mood = DEFAULT_FALLBACK_MOOD
    else:
        try:
            # Get structured calendar events for pre-processor
            calendar_events = calendar_client.get_calendar_events_structured()
            
            result = gemini_client.predict_mood(
                historical_moods,
                music_summary,
                calendar_summary,
                weather_summary,
                sleep_info,
                dry_run=args.dry_run,
                music_metrics=music_metrics,
                calendar_events=calendar_events
            )

            if args.dry_run:
                # Dry run: save prompt to file
                mood = result["mood"]
                prompt = result["prompt"]
                with open(DRY_RUN_PROMPT_FILE, "w", encoding="utf-8") as f:
                    f.write(f"--- PROMPT GENERATED ON {now} ---\n{prompt}")
                logger.info(f"Dry run: Prompt saved to {DRY_RUN_PROMPT_FILE}")
            else:
                # Production: use predicted mood
                mood = result
                logger.info(f">>> PREDICTED MOOD: {mood} <<<")

        except ValueError as config_error:
            logger.error(f"Configuration error: {config_error}")
            logger.warning("[WARN] FALLBACK MODE: Using default mood")
            mood = DEFAULT_FALLBACK_MOOD
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

    save_daily_log(weekday, mood, music_summary, calendar_summary, args.dry_run)

    # ========================================================================
    # Completion
    # ========================================================================

    logger.info("--- Execution Complete ---")


if __name__ == "__main__":
    main()
