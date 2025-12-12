import os
import json
import datetime
import requests
from typing import List, Dict, Any, Optional
from icalendar import Calendar
import recurring_ical_events
import pytz
import logging
# Suppress the "file_cache is only supported with oauth2client<4.0.0" warning
logging.getLogger('googleapiclient.discovery_cache').setLevel(logging.ERROR)

from google.oauth2 import service_account
from googleapiclient.discovery import build

def fetch_ics_events(start_dt, end_dt):
    """
    Reads 'ics_config.json', fetches URLs (or local files), parses events within range.
    """
    events_found = []
    
    config_path = "ics_config.json"
    if not os.path.exists(config_path):
        return []
        
    try:
        with open(config_path, "r") as f:
            config = json.load(f)
            urls = config.get("ics_urls", [])
    except Exception as e:
        print(f"Error reading ics_config.json: {e}")
        return []

    for url in urls:
        try:
            content = None
            if url.startswith("http"):
                # Remote fetch
                # print(f"DEBUG: Fetching ICS from {url[:30]}...")
                resp = requests.get(url, timeout=10)
                resp.raise_for_status()
                content = resp.content
            else:
                # Local file fetch (for testing if needed)
                if os.path.exists(url):
                   with open(url, 'rb') as f:
                       content = f.read()
                else:
                    # print(f"Warning: Local ICS file not found: {url}")
                    continue

            cal = Calendar.from_ical(content)
            
            # recurring_ical_events handles expansion and range check!
            subset = recurring_ical_events.of(cal).between(start_dt, end_dt)
            
            for event in subset:
                summary = str(event.get('summary'))
                dtstart = event.get('dtstart')
                if not dtstart:
                    continue
                
                event_dt = dtstart.dt
                events_found.append({
                    'start': event_dt, 
                    'summary': summary,
                    'calendar_name': 'Cours/ICS'
                })

        except Exception as e:
            print(f"Error fetching/parsing ICS {url}: {e}")
            
    return events_found


def create_report_event(summary, description):
    """
    Creates an urgent event in the calendar to alert the user of a system error.
    Used by main.py when something critical fails.
    """
    service_account_info_str = os.environ.get("GOOGLE_SERVICE_ACCOUNT")
    calendar_id = os.environ.get("TARGET_CALENDAR_ID")
    
    if not service_account_info_str or not calendar_id:
        print("Cannot create report event: Missing credentials/ID.")
        return

    try:
        service_account_info = json.loads(service_account_info_str)
        # [CRITICAL] Need write access here
        creds = service_account.Credentials.from_service_account_info(
            service_account_info, scopes=['https://www.googleapis.com/auth/calendar'])
        service = build('calendar', 'v3', credentials=creds)
        
        today = datetime.datetime.now()
        date_str = today.strftime('%Y-%m-%d')
        
        # Check for existing duplicate alert
        today_start_rfc = f"{date_str}T00:00:00Z"
        today_end_rfc = f"{date_str}T23:59:59Z"
        
        existing_events = service.events().list(
            calendarId=calendar_id,
            timeMin=today_start_rfc,
            timeMax=today_end_rfc,
            singleEvents=True
        ).execute().get('items', [])
        
        full_summary = f"🚨 ALERT: {summary}"
        
        print(f"DEBUG: Checking duplicates for '{full_summary}' among {len(existing_events)} exists.")
        for ev in existing_events:
            # print(f"DEBUG: Found event: {ev.get('summary')}")
            if ev.get('summary') == full_summary:
                print(f"Skipping Duplicate Alert: {summary}")
                return

        # Create event for Today 18h-19h (or next slot)
        event = {
            'summary': full_summary,
            'description': description,
            'start': {
                'dateTime': f"{date_str}T18:00:00",
                'timeZone': 'Europe/Paris',
            },
            'end': {
                'dateTime': f"{date_str}T19:00:00",
                'timeZone': 'Europe/Paris',
            },
            'reminders': {
                'useDefault': False,
                'overrides': [
                    {'method': 'popup', 'minutes': 10},
                    {'method': 'email', 'minutes': 1},
                ],
            },
            'colorId': '11' # Red color
        }
        
        service.events().insert(calendarId=calendar_id, body=event).execute()
        print(f"Created Alert Event: {summary}")
        
    except Exception as e:
        print(f"Failed to create report event: {e}")


# ------------------------------------------------------------------------------
# Core Logic: Fetchers
# ------------------------------------------------------------------------------

def _fetch_from_ics(start_dt: datetime.datetime, end_dt: datetime.datetime) -> List[Dict]:
    """Internal helper: Fetches events from ICS sources defined in config."""
    # Re-uses existing fetch_ics_events logic but normalized
    return fetch_ics_events(start_dt, end_dt)

def _fetch_from_google(start_dt: datetime.datetime, end_dt: datetime.datetime) -> List[Dict]:
    """Internal helper: Fetches events from Google Calendar API."""
    service_account_info_str = os.environ.get("GOOGLE_SERVICE_ACCOUNT")
    target_cals_env = os.environ.get("TARGET_CALENDAR_ID")
    
    if not service_account_info_str or not target_cals_env:
        return []

    events_found = []
    try:
        service_account_info = json.loads(service_account_info_str)
        creds = service_account.Credentials.from_service_account_info(
            service_account_info, scopes=['https://www.googleapis.com/auth/calendar.readonly'])
        service = build('calendar', 'v3', credentials=creds)
        
        # Format dates for Google API (RFC3339)
        time_min = start_dt.strftime('%Y-%m-%dT00:00:00Z')
        time_max = end_dt.strftime('%Y-%m-%dT23:59:59Z')
        
        calendar_ids = [x.strip() for x in target_cals_env.split(',') if x.strip()]
        
        for cal_id in calendar_ids:
            try:
                # Get calendar summary (name) if possible, or use ID
                # We skip getting metadata to save a call, we use ID as name or update later
                
                resp = service.events().list(
                    calendarId=cal_id,
                    timeMin=time_min,
                    timeMax=time_max,
                    singleEvents=True,
                    orderBy='startTime'
                ).execute()
                
                items = resp.get('items', [])
                for item in items:
                    # Normalize to flat structure
                    item['calendar_name'] = resp.get('summary', cal_id)
                    events_found.append(item)
                    
            except Exception as e:
                print(f"Warning: Failed to fetch calendar {cal_id}: {e}")
                
    except Exception as e:
        print(f"Google Calendar Global Error: {e}")
        
    return events_found

def _format_events_summary(all_events: List[Dict], today_date: datetime.date) -> str:
    """Formats the list of event dictionaries into a readable string."""
    if not all_events:
        return "No events found (Past, Today, or Week)."
        
    def get_start_str(x):
        return x['start'].get('dateTime', x['start'].get('date'))
        
    all_events.sort(key=get_start_str)

    today_str = today_date.strftime('%Y-%m-%d')
    
    past, today_ev, upcoming = [], [], []

    for event in all_events:
        start_raw = get_start_str(event)
        summary = event.get('summary', 'Busy')
        cal_name = event.get('calendar_name', '?')
        line = f"[{cal_name}] {start_raw}: {summary}"
        
        # Simple string comparison works for ISO dates
        start_date_part = start_raw.split('T')[0]
        
        if start_date_part < today_str:
            past.append(line)
        elif start_date_part == today_str:
            today_ev.append(line)
        else:
            upcoming.append(line)

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

# ------------------------------------------------------------------------------
# Public API
# ------------------------------------------------------------------------------

def get_week_events() -> str:
    """
    Main entry point: Fetches Google + ICS events for the week and formatting them.
    Returns a string summary for the AI.
    """
    # Time range: Now - 2 days to Now + 8 days
    now_utc = datetime.datetime.now(datetime.timezone.utc)
    start_dt = now_utc - datetime.timedelta(days=2)
    end_dt = now_utc + datetime.timedelta(days=8)
    
    # 1. Fetch
    ics_events = _fetch_from_ics(start_dt, end_dt)
    google_events = _fetch_from_google(start_dt, end_dt)
    
    # 2. Merge & Normalize
    # ICS events need to match Google structure roughly for the formatter
    normalized_events = []
    
    for ev in ics_events:
        # Convert datetime obj to ISO string for consistency
        s_val = ev['start']
        s_str = s_val.isoformat() if hasattr(s_val, 'isoformat') else str(s_val)
        
        normalized_events.append({
            'start': {'dateTime': s_str}, # Mock Google Structure
            'summary': ev['summary'],
            'calendar_name': ev.get('calendar_name', 'ICS')
        })
        
    normalized_events.extend(google_events)
    
    # 3. Format
    today_local = datetime.date.today()
    return _format_events_summary(normalized_events, today_local)

