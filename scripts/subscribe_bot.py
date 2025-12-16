"""
Calendar subscription bot for service account access.

Enables service account access to shared/imported calendars by adding them
to the service account's calendar list.
"""

import os
import json
import logging
from typing import List, Optional, Dict, Any

from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError

logger = logging.getLogger(__name__)


# ============================================================================
# CONSTANTS
# ============================================================================

CALENDAR_SCOPES = ['https://www.googleapis.com/auth/calendar']


# ============================================================================
# EXCEPTIONS
# ============================================================================

class CalendarSubscriptionError(Exception):
    """Raised when calendar subscription operations fail."""
    pass


# ============================================================================
# CONFIGURATION
# ============================================================================

class SubscriptionConfig:
    """Manages subscription configuration."""

    def __init__(self) -> None:
        """Load configuration from environment."""
        self.service_account_str = os.environ.get("GOOGLE_SERVICE_ACCOUNT")
        self.calendar_ids_str = os.environ.get("TARGET_CALENDAR_ID")

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
            raise CalendarSubscriptionError(f"Invalid credentials: {e}") from e

    def get_calendar_ids(self) -> List[str]:
        """
        Parses calendar IDs from configuration.

        Returns:
            List of calendar ID strings.
        """
        if not self.calendar_ids_str:
            logger.warning("TARGET_CALENDAR_ID not configured")
            return []

        return [cal_id.strip() for cal_id in self.calendar_ids_str.split(',') if cal_id.strip()]

    def validate(self) -> bool:
        """
        Validates configuration.

        Returns:
            True if valid, raises exception otherwise.
        """
        if not self.service_account_str:
            raise CalendarSubscriptionError("GOOGLE_SERVICE_ACCOUNT not configured")

        cal_ids = self.get_calendar_ids()
        if not cal_ids:
            raise CalendarSubscriptionError("TARGET_CALENDAR_ID not configured")

        return True


# ============================================================================
# GOOGLE CALENDAR API
# ============================================================================

class CalendarListManager:
    """Manages calendar subscriptions via Google Calendar API."""

    def __init__(self, config: SubscriptionConfig) -> None:
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
            raise CalendarSubscriptionError(f"Service build failed: {e}") from e

    def is_subscribed(self, calendar_id: str) -> bool:
        """
        Checks if calendar is already in service account's list.

        Args:
            calendar_id: Calendar ID to check

        Returns:
            True if subscribed, False otherwise.
        """
        try:
            self.service.calendarList().get(calendarId=calendar_id).execute()
            return True
        except HttpError as e:
            if e.resp.status == 404:
                return False
            logger.warning(f"Subscription check failed for {calendar_id}: {e}")
            return False
        except Exception as e:
            logger.warning(f"Unexpected error checking subscription: {e}")
            return False

    def subscribe(self, calendar_id: str) -> bool:
        """
        Subscribes service account to a calendar.

        Args:
            calendar_id: Calendar ID to subscribe to

        Returns:
            True if successful (or already subscribed), False on error.
        """
        try:
            # Check existing subscription first
            if self.is_subscribed(calendar_id):
                logger.info(f"  ✅ Already subscribed: {calendar_id}")
                return True

            # Subscribe to calendar
            entry = {'id': calendar_id}
            self.service.calendarList().insert(body=entry).execute()

            logger.info(f"  ✅ Subscribed: {calendar_id}")
            return True

        except HttpError as e:
            if e.resp.status == 403:
                logger.error(
                    f"  ❌ Access denied (Private calendar): {calendar_id}\n"
                    f"     This usually means the calendar is not shared publicly.\n"
                    f"     The calendar URL import source must be public to the bot."
                )
            else:
                logger.error(f"  ❌ Subscription failed: HTTP {e.resp.status}")
            return False
        except Exception as e:
            logger.error(f"  ❌ Unexpected error: {e}")
            return False


# ============================================================================
# CALENDAR SUBSCRIBER
# ============================================================================

class CalendarSubscriber:
    """Orchestrates calendar subscription process."""

    def __init__(self, manager: CalendarListManager) -> None:
        """
        Initialize subscriber.

        Args:
            manager: CalendarListManager instance
        """
        self.manager = manager

    def subscribe_all(self, calendar_ids: List[str]) -> bool:
        """
        Subscribes to multiple calendars.

        Args:
            calendar_ids: List of calendar IDs

        Returns:
            True if all successful, False if any failed.
        """
        if not calendar_ids:
            logger.warning("No calendars to subscribe to")
            return False

        logger.info(f"Subscribing to {len(calendar_ids)} calendar(s)...")

        results = []
        for calendar_id in calendar_ids:
            logger.info(f"\nProcessing: {calendar_id}")
            success = self.manager.subscribe(calendar_id)
            results.append(success)

        success_count = sum(results)
        logger.info(f"\n✅ Successfully subscribed to {success_count}/{len(calendar_ids)} calendars")

        return all(results)


# ============================================================================
# PUBLIC API
# ============================================================================

def subscribe_bot_to_calendars() -> None:
    """
    Subscribes service account bot to configured calendars.

    Reads calendar IDs from TARGET_CALENDAR_ID environment variable (comma-separated).
    Useful for accessing shared/imported calendars.

    Requires environment variables:
    - GOOGLE_SERVICE_ACCOUNT: Service account credentials JSON
    - TARGET_CALENDAR_ID: Calendar IDs (comma-separated)
    """
    try:
        config = SubscriptionConfig()
        config.validate()

        manager = CalendarListManager(config)
        subscriber = CalendarSubscriber(manager)

        calendar_ids = config.get_calendar_ids()
        subscriber.subscribe_all(calendar_ids)

    except CalendarSubscriptionError as e:
        logger.error(f"Configuration error: {e}")
    except Exception as e:
        logger.error(f"Unexpected error: {e}")


if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s'
    )
    subscribe_bot_to_calendars()
