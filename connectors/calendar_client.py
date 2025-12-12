"""
Calendar client for event management.

This module provides:
- Fetching events from Google Calendar API
- Parsing ICS calendar files (local or remote)
- Creating alert events for system failures
- Formatting events for AI context
"""

import os
import json
import datetime
import logging
from typing import List, Dict, Optional, Tuple, Any
from enum import Enum

import requests
from icalendar import Calendar
import recurring_ical_events
import pytz

from google.oauth2 import service_account
from googleapiclient.discovery import build

# Suppress Google API logging
logging.getLogger('googleapiclient.discovery_cache').setLevel(logging.ERROR)

logger = logging.getLogger(__name__)

# ============================================================================
# CONSTANTS
# ============================================================================

ICS_CONFIG_FILE = "ics_config.json"
API_TIMEOUT = 10
ALERT_EVENT_HOUR = 18
ALERT_EVENT_DURATION = 1


class CalendarSource(Enum):
    """Calendar event sources."""
    GOOGLE = "Google Calendar"
    ICS = "ICS File"
    UNKNOWN = "Unknown"


class EventPeriod(Enum):
    """Event time periods relative to today."""
    PAST = "PAST"
    TODAY = "TODAY"
    UPCOMING = "UPCOMING"


# ============================================================================
# EXCEPTIONS
# ============================================================================

class CalendarAuthError(Exception):
    """Raised when calendar authentication fails."""
    pass


class CalendarFetchError(Exception):
    """Raised when calendar fetching fails."""
    pass


# ============================================================================
# CONFIGURATION
# ============================================================================

class CalendarConfig:
    """Manages calendar configuration from environment."""

    def __init__(self):
        """Load configuration from environment variables."""
        self.service_account_str = os.environ.get("GOOGLE_SERVICE_ACCOUNT")
        self.calendar_ids_str = os.environ.get("TARGET_CALENDAR_ID")
        self.timezone = "Europe/Paris"

    def get_service_account_info(self) -> Optional[Dict]:
        """
        Parses service account credentials.

        Returns:
            Parsed JSON dict, or None if not configured

        Raises:
            CalendarAuthError: If JSON parsing fails
        """
        if not self.service_account_str:
            return None

        try:
            return json.loads(self.service_account_str)
        except json.JSONDecodeError as e:
            logger.error(f"Invalid service account JSON: {e}")
            raise CalendarAuthError(f"Invalid credentials: {e}") from e

    def get_calendar_ids(self) -> List[str]:
        """
        Parses calendar IDs from configuration.

        Returns:
            List of calendar ID strings
        """
        if not self.calendar_ids_str:
            return []

        return [cal_id.strip() for cal_id in self.calendar_ids_str.split(',') if cal_id.strip()]


# ============================================================================
# ICS PARSING
# ============================================================================

class ICSFetcher:
    """Fetches and parses ICS calendar files."""

    def __init__(self, config_file: str = ICS_CONFIG_FILE):
        """
        Initialize ICS fetcher.

        Args:
            config_file: Path to ICS config JSON file
        """
        self.config_file = config_file

    def fetch_events(self, start_dt: datetime.datetime,
                    end_dt: datetime.datetime) -> List[Dict[str, Any]]:
        """
        Fetches events from ICS sources.

        Sources can be HTTP URLs or local files, defined in ics_config.json.

        Args:
            start_dt: Start time for event range
            end_dt: End time for event range

        Returns:
            List of event dicts with keys: start, summary, calendar_name

        Example:
            >>> fetcher = ICSFetcher()
            >>> events = fetcher.fetch_events(start_dt, end_dt)
        """
        if not os.path.exists(self.config_file):
            logger.debug(f"ICS config file not found: {self.config_file}")
            return []

        try:
            with open(self.config_file, "r", encoding="utf-8") as f:
                config = json.load(f)
                urls = config.get("ics_urls", [])
        except Exception as e:
            logger.warning(f"Failed to read ICS config: {e}")
            return []

        events_found = []

        for url in urls:
            try:
                content = self._fetch_content(url)
                if not content:
                    continue

                events = self._parse_calendar(content, start_dt, end_dt)
                events_found.extend(events)

            except Exception as e:
                logger.warning(f"Error processing ICS {url}: {e}")

        logger.info(f"[OK] Fetched {len(events_found)} ICS events")
        return events_found

    @staticmethod
    def _fetch_content(url: str) -> Optional[bytes]:
        """
        Fetches ICS content from URL or local file.

        Args:
            url: HTTP URL or local file path

        Returns:
            File content bytes, or None on error
        """
        try:
            if url.startswith("http"):
                response = requests.get(url, timeout=API_TIMEOUT)
                response.raise_for_status()
                return response.content
            else:
                if os.path.exists(url):
                    with open(url, "rb") as f:
                        return f.read()
                logger.warning(f"Local ICS file not found: {url}")
                return None

        except requests.exceptions.Timeout:
            logger.warning(f"ICS fetch timeout: {url}")
            return None
        except requests.exceptions.HTTPError as e:
            logger.warning(f"ICS fetch HTTP error {e.response.status_code}: {url}")
            return None
        except Exception as e:
            logger.warning(f"Failed to fetch ICS content: {e}")
            return None

    @staticmethod
    def _parse_calendar(content: bytes, start_dt: datetime.datetime,
                       end_dt: datetime.datetime) -> List[Dict[str, Any]]:
        """
        Parses calendar content and extracts events in range.

        Args:
            content: ICS file content bytes
            start_dt: Start time for range
            end_dt: End time for range

        Returns:
            List of normalized event dicts
        """
        try:
            cal = Calendar.from_ical(content)

            # Handle recurring events
            subset = recurring_ical_events.of(cal).between(start_dt, end_dt)

            events = []
            for event in subset:
                summary = str(event.get('summary', 'Busy'))
                dtstart = event.get('dtstart')

                if not dtstart:
                    continue

                event_dt = dtstart.dt
                events.append({
                    'start': {'dateTime': event_dt.isoformat()},
                    'summary': summary,
                    'calendar_name': 'ICS'
                })

            return events

        except Exception as e:
            logger.warning(f"Failed to parse calendar: {e}")
            return []


# ============================================================================
# GOOGLE CALENDAR
# ============================================================================

class GoogleCalendarFetcher:
    """Fetches events from Google Calendar API."""

    def __init__(self, config: Optional[CalendarConfig] = None):
        """
        Initialize fetcher.

        Args:
            config: CalendarConfig instance
        """
        self.config = config or CalendarConfig()

    def fetch_events(self, start_dt: datetime.datetime,
                    end_dt: datetime.datetime) -> List[Dict[str, Any]]:
        """
        Fetches events from Google Calendar.

        Args:
            start_dt: Start time for event range
            end_dt: End time for event range

        Returns:
            List of event dicts in Google Calendar format

        Raises:
            CalendarFetchError: If API call fails
        """
        try:
            service = self._build_service()
            calendar_ids = self.config.get_calendar_ids()

            if not calendar_ids:
                logger.debug("No Google Calendar IDs configured")
                return []

            events = []
            for cal_id in calendar_ids:
                cal_events = self._fetch_calendar(service, cal_id, start_dt, end_dt)
                events.extend(cal_events)

            logger.info(f"[OK] Fetched {len(events)} Google Calendar events")
            return events

        except CalendarAuthError as e:
            logger.warning(f"Google Calendar auth failed: {e}")
            raise CalendarFetchError(str(e)) from e
        except Exception as e:
            logger.error(f"Google Calendar fetch failed: {e}")
            raise CalendarFetchError(str(e)) from e

    def _build_service(self) -> any:
        """
        Builds Google Calendar API service.

        Returns:
            Google API service object

        Raises:
            CalendarAuthError: If authentication fails
        """
        try:
            service_account_info = self.config.get_service_account_info()

            if not service_account_info:
                raise CalendarAuthError("Service account credentials not configured")

            creds = service_account.Credentials.from_service_account_info(
                service_account_info,
                scopes=['https://www.googleapis.com/auth/calendar.readonly']
            )

            return build('calendar', 'v3', credentials=creds)

        except Exception as e:
            raise CalendarAuthError(f"Failed to build service: {e}") from e

    @staticmethod
    def _fetch_calendar(service: any, cal_id: str,
                       start_dt: datetime.datetime,
                       end_dt: datetime.datetime) -> List[Dict[str, Any]]:
        """
        Fetches events from a specific Google Calendar.

        Args:
            service: Google API service
            cal_id: Calendar ID
            start_dt: Start time
            end_dt: End time

        Returns:
            List of event dicts
        """
        try:
            time_min = start_dt.strftime('%Y-%m-%dT00:00:00Z')
            time_max = end_dt.strftime('%Y-%m-%dT23:59:59Z')

            response = service.events().list(
                calendarId=cal_id,
                timeMin=time_min,
                timeMax=time_max,
                singleEvents=True,
                orderBy='startTime'
            ).execute()

            items = response.get('items', [])

            for item in items:
                item['calendar_name'] = response.get('summary', cal_id)

            logger.debug(f"  → {cal_id}: {len(items)} events")
            return items

        except Exception as e:
            logger.warning(f"Failed to fetch calendar {cal_id}: {e}")
            return []


# ============================================================================
# EVENT ALERT CREATION
# ============================================================================

class AlertEventCreator:
    """Creates alert events in Google Calendar."""

    def __init__(self, config: Optional[CalendarConfig] = None):
        """
        Initialize creator.

        Args:
            config: CalendarConfig instance
        """
        self.config = config or CalendarConfig()

    def create_alert(self, summary: str, description: str) -> bool:
        """
        Creates an alert event in Google Calendar.

        Used to notify user of system failures.

        Args:
            summary: Alert summary
            description: Alert description

        Returns:
            True if successful, False otherwise

        Example:
            >>> creator = AlertEventCreator()
            >>> created = creator.create_alert("Data Sync Failed", "YouTube Music sync error")
        """
        try:
            service = self._build_service()
            calendar_ids = self.config.get_calendar_ids()

            if not calendar_ids:
                logger.warning("No calendar IDs configured for alerts")
                return False

            cal_id = calendar_ids[0]  # Use first calendar

            # Check for duplicate alert today
            if self._has_duplicate_alert(service, cal_id, summary):
                logger.info(f"Duplicate alert skipped: {summary}")
                return True

            # Create event
            event = self._build_event(summary, description)
            service.events().insert(calendarId=cal_id, body=event).execute()

            logger.info(f"[OK] Alert event created: {summary}")
            return True

        except Exception as e:
            logger.error(f"Failed to create alert: {e}")
            return False

    def _build_service(self) -> any:
        """Builds Google API service with write access."""
        service_account_info = self.config.get_service_account_info()

        if not service_account_info:
            raise ValueError("Service account credentials not configured")

        creds = service_account.Credentials.from_service_account_info(
            service_account_info,
            scopes=['https://www.googleapis.com/auth/calendar']
        )

        return build('calendar', 'v3', credentials=creds)

    def _has_duplicate_alert(self, service: any, cal_id: str, summary: str) -> bool:
        """Checks if similar alert already exists today."""
        try:
            today = datetime.date.today()
            date_str = today.strftime('%Y-%m-%d')
            time_min = f"{date_str}T00:00:00Z"
            time_max = f"{date_str}T23:59:59Z"

            response = service.events().list(
                calendarId=cal_id,
                timeMin=time_min,
                timeMax=time_max
            ).execute()

            alert_summary = f"[ALERT] ALERT: {summary}"

            for event in response.get('items', []):
                if event.get('summary') == alert_summary:
                    return True

            return False

        except Exception as e:
            logger.debug(f"Duplicate check failed: {e}")
            return False

    @staticmethod
    def _build_event(summary: str, description: str) -> Dict[str, Any]:
        """Builds event object."""
        today = datetime.date.today().isoformat()

        return {
            'summary': f"[ALERT] ALERT: {summary}",
            'description': description,
            'start': {
                'dateTime': f"{today}T{ALERT_EVENT_HOUR:02d}:00:00",
                'timeZone': 'Europe/Paris',
            },
            'end': {
                'dateTime': f"{today}T{ALERT_EVENT_HOUR + ALERT_EVENT_DURATION:02d}:00:00",
                'timeZone': 'Europe/Paris',
            },
            'reminders': {
                'useDefault': False,
                'overrides': [
                    {'method': 'popup', 'minutes': 10},
                    {'method': 'email', 'minutes': 1},
                ],
            },
            'colorId': '11'  # Red color
        }


# ============================================================================
# EVENT FORMATTING
# ============================================================================

class EventFormatter:
    """Formats events for AI prompt context."""

    @staticmethod
    def format_events_summary(all_events: List[Dict[str, Any]],
                            today_date: Optional[datetime.date] = None) -> str:
        """
        Formats event list into readable summary.

        Groups events into PAST, TODAY, and UPCOMING sections.

        Args:
            all_events: List of event dicts
            today_date: Reference date (defaults to today)

        Returns:
            Formatted string summary

        Example:
            >>> events = [{"start": {"dateTime": "2025-12-12T14:00"}, "summary": "Meeting"}]
            >>> summary = EventFormatter.format_events_summary(events)
        """
        if not all_events:
            return "No events found (Past, Today, or Week)."

        today_date = today_date or datetime.date.today()
        today_str = today_date.strftime('%Y-%m-%d')

        # Sort by start time
        sorted_events = sorted(
            all_events,
            key=lambda x: EventFormatter._get_start_str(x)
        )

        past, today_ev, upcoming = [], [], []

        for event in sorted_events:
            start_raw = EventFormatter._get_start_str(event)
            summary = event.get('summary', 'Busy')
            cal_name = event.get('calendar_name', '?')
            line = f"[{cal_name}] {start_raw}: {summary}"

            start_date_part = start_raw.split('T')[0] if 'T' in start_raw else start_raw

            if start_date_part < today_str:
                past.append(line)
            elif start_date_part == today_str:
                today_ev.append(line)
            else:
                upcoming.append(line)

        # Format output
        output = []

        if past:
            output.append("--- CONTEXTE PASSÉ (Hier/Avant-hier) ---")
            output.extend(past)
            output.append("")

        if today_ev:
            output.append("--- FOCUS AUJOURD'HUI ---")
            output.extend(today_ev)
        else:
            output.append("--- FOCUS AUJOURD'HUI : RIEN ---")

        if upcoming:
            output.append("\n--- CONTEXTE SEMAINE ---")
            output.extend(upcoming)

        return "\n".join(output)

    @staticmethod
    def _get_start_str(event: Dict[str, Any]) -> str:
        """Extracts start datetime string from event."""
        start_dict = event.get('start', {})
        return start_dict.get('dateTime', start_dict.get('date', ''))


# ============================================================================
# PUBLIC API
# ============================================================================

def get_calendar_events_structured() -> List[Dict[str, Any]]:
    """
    Fetches structured calendar events (raw event dicts).

    Used for pre-processor analysis instead of formatted summary.

    Returns:
        List of event dicts with 'summary' and 'start' fields

    Example:
        >>> events = get_calendar_events_structured()
        >>> events[0]  # {'summary': 'Meeting', 'start': {...}}
    """
    try:
        # Time range: 2 days past to 8 days future
        now = datetime.datetime.now()
        start_dt = now - datetime.timedelta(days=2)
        end_dt = now + datetime.timedelta(days=8)

        # Fetch from both sources
        ics_fetcher = ICSFetcher()
        ics_events = ics_fetcher.fetch_events(start_dt, end_dt)

        google_fetcher = GoogleCalendarFetcher()
        google_events = google_fetcher.fetch_events(start_dt, end_dt)

        # Combine and return raw events
        all_events = ics_events + google_events
        logger.debug(f"Retrieved {len(all_events)} structured calendar events")
        return all_events

    except Exception as e:
        logger.warning(f"Failed to get structured calendar events: {e}")
        return []


def get_week_events() -> str:
    """
    Fetches and formats calendar events for the week.

    Combines events from Google Calendar and ICS files, groups by time period.

    Returns:
        Formatted string summary ready for AI prompt

    Example:
        >>> summary = get_week_events()
        >>> print(summary)
    """
    try:
        # Use structured events to get formatted summary
        all_events = get_calendar_events_structured()

        formatter = EventFormatter()
        return formatter.format_events_summary(all_events)

    except Exception as e:
        logger.error(f"Failed to get week events: {e}")
        return "Calendar unavailable (Error)"


def create_report_event(summary: str, description: str) -> None:
    """
    Creates an alert event in Google Calendar.

    Used by main.py to notify of system failures.

    Args:
        summary: Alert title
        description: Alert details

    Example:
        >>> create_report_event("YouTube Music Sync Failed", "Connection timeout")
    """
    creator = AlertEventCreator()
    creator.create_alert(summary, description)
