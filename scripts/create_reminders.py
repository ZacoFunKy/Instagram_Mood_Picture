"""
Maintenance reminder scheduler for project management.

Creates recurring calendar events to remind about:
- Instagram session ID renewal (every 90 days)
- YouTube Music headers refresh (every 180 days)
"""

import os
import logging
import datetime
import json
from typing import Optional, Dict, Any, List

from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError

logger = logging.getLogger(__name__)


# ============================================================================
# CONSTANTS
# ============================================================================

CALENDAR_SCOPES = ['https://www.googleapis.com/auth/calendar']
REMINDER_HOUR = 18
REMINDER_DURATION = 1

INSTAGRAM_SESSION_DAYS = 90
YOUTUBE_HEADERS_DAYS = 180

TIMEZONE = "Europe/Paris"


# ============================================================================
# EXCEPTIONS
# ============================================================================

class ReminderServiceError(Exception):
    """Raised when reminder service operations fail."""
    pass


# ============================================================================
# CONFIGURATION
# ============================================================================

class ReminderConfig:
    """Manages reminder configuration."""

    def __init__(self) -> None:
        """Load configuration from environment."""
        self.service_account_str = os.environ.get("GOOGLE_SERVICE_ACCOUNT")
        self.calendar_id = os.environ.get("TARGET_CALENDAR_ID")

    def get_service_account_info(self) -> Optional[Dict[str, Any]]:
        """
        Parses service account credentials.

        Returns:
            Parsed JSON dict, or None if not configured.
        """
        if not self.service_account_str:
            return None

        try:
            return json.loads(self.service_account_str)
        except json.JSONDecodeError as e:
            logger.error(f"Invalid service account JSON: {e}")
            raise ReminderServiceError(f"Invalid credentials: {e}") from e

    def validate(self) -> bool:
        """
        Validates configuration.

        Returns:
            True if valid, raises exception otherwise.
        """
        if not self.service_account_str:
            raise ReminderServiceError("GOOGLE_SERVICE_ACCOUNT not configured")
        if not self.calendar_id:
            raise ReminderServiceError("TARGET_CALENDAR_ID not configured")
        return True


# ============================================================================
# GOOGLE CALENDAR API
# ============================================================================

class GoogleCalendarService:
    """Provides Google Calendar API interface."""

    def __init__(self, config: ReminderConfig) -> None:
        self.config = config
        self.service = self._build_service()

    def _build_service(self) -> Any:
        """
        Builds Google Calendar API service.
        """
        try:
            creds_info = self.config.get_service_account_info()
            creds = service_account.Credentials.from_service_account_info(
                creds_info,
                scopes=CALENDAR_SCOPES
            )
            return build('calendar', 'v3', credentials=creds)
        except Exception as e:
            logger.error(f"Failed to build Calendar service: {e}")
            raise ReminderServiceError(f"Service build failed: {e}") from e

    def create_event(self, summary: str, description: str,
                    target_date: datetime.date) -> bool:
        """
        Creates an event on target date.

        Args:
            summary: Event title
            description: Event description
            target_date: Target date for event

        Returns:
            True if successful, False otherwise.
        """
        try:
            date_str = target_date.strftime('%Y-%m-%d')
            event = {
                'summary': summary,
                'description': description,
                'start': {
                    'dateTime': f"{date_str}T{REMINDER_HOUR:02d}:00:00",
                    'timeZone': TIMEZONE,
                },
                'end': {
                    'dateTime': f"{date_str}T{REMINDER_HOUR + REMINDER_DURATION:02d}:00:00",
                    'timeZone': TIMEZONE,
                },
                'reminders': {
                    'useDefault': False,
                    'overrides': [
                        {'method': 'email', 'minutes': 24 * 60},  # 1 day before
                        {'method': 'popup', 'minutes': 30},
                    ],
                },
            }

            result = self.service.events().insert(
                calendarId=self.config.calendar_id,
                body=event
            ).execute()

            logger.info(f"✅ Event created: {result.get('htmlLink')}")
            return True

        except HttpError as e:
            logger.error(f"Calendar API error: {e}")
            return False
        except Exception as e:
            logger.error(f"Event creation failed: {e}")
            return False


# ============================================================================
# MAINTENANCE REMINDER SCHEDULER
# ============================================================================

class MaintenanceReminderScheduler:
    """Schedules maintenance reminder events."""

    def __init__(self, service: GoogleCalendarService) -> None:
        self.service = service

    def schedule_instagram_renewal(self) -> bool:
        """
        Schedules Instagram session ID renewal reminder.
        Creates reminder 90 days from now.
        """
        target_date = datetime.date.today() + datetime.timedelta(days=INSTAGRAM_SESSION_DAYS)

        return self.service.create_event(
            summary="🔧 Maintenance: Renew Instagram Session ID",
            description=(
                "Instagram session IDs expire (~90 days).\n\n"
                "1. Log in to Instagram\n"
                "2. Open browser DevTools (F12)\n"
                "3. Go to Application → Cookies → instagram.com\n"
                "4. Copy 'sessionid' value\n"
                "5. Update GitHub secret 'IG_SESSIONID'\n\n"
                "This prevents the bot from crashing."
            ),
            target_date=target_date
        )

    def schedule_youtube_headers_renewal(self) -> bool:
        """
        Schedules YouTube Music headers refresh reminder.
        Creates reminder 180 days from now.
        """
        target_date = datetime.date.today() + datetime.timedelta(days=YOUTUBE_HEADERS_DAYS)

        return self.service.create_event(
            summary="🔧 Maintenance: Refresh YouTube Music Headers",
            description=(
                "YouTube Music authentication headers expire (~180 days).\n\n"
                "1. Install: pip install ytmusicapi\n"
                "2. Run: ytmusicapi browser\n"
                "3. Follow browser auth flow\n"
                "4. Copy generated headers JSON\n"
                "5. Update GitHub secret 'YTMUSIC_HEADERS'\n\n"
                "This prevents YouTube Music sync failures."
            ),
            target_date=target_date
        )

    def schedule_all_reminders(self) -> bool:
        """
        Schedules all maintenance reminders.

        Returns:
            True if all successful, False if any failed.
        """
        results = [
            self.schedule_instagram_renewal(),
            self.schedule_youtube_headers_renewal()
        ]

        success = all(results)
        if success:
            logger.info("✅ All maintenance reminders scheduled (French, 18h-19h)")
        else:
            logger.warning("⚠️ Some reminders failed to schedule")

        return success


# ============================================================================
# PUBLIC API
# ============================================================================

def create_maintenance_reminders() -> None:
    """
    Creates maintenance reminder events in Google Calendar.

    Schedules:
    - Instagram session ID renewal (90 days)
    - YouTube Music headers refresh (180 days)

    Requires environment variables:
    - GOOGLE_SERVICE_ACCOUNT: Service account credentials JSON
    - TARGET_CALENDAR_ID: Google Calendar ID
    """
    try:
        config = ReminderConfig()
        config.validate()

        service = GoogleCalendarService(config)
        scheduler = MaintenanceReminderScheduler(service)
        scheduler.schedule_all_reminders()

    except ReminderServiceError as e:
        logger.error(f"Configuration error: {e}")
    except Exception as e:
        logger.error(f"Unexpected error: {e}")


if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    create_maintenance_reminders()
