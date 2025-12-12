import os
import json
import datetime
import requests
from icalendar import Calendar
import recurring_ical_events
import pytz
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
        
        # Create event for Today 18h-19h (or next slot)
        event = {
            'summary': f"🚨 ALERT: {summary}",
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

def get_week_events():
    """
    Fetches events for the next 7 days, highlighting Today.
    Combines Google Calendar and ICS sources.
    """
    service_account_info_str = os.environ.get("GOOGLE_SERVICE_ACCOUNT")
    
    # Time range: Now to +8 days (to capture full week + overlap)
    # recurring_ical_events requires aware datetime if events are aware. using UTC is safest.
    now = datetime.datetime.now().astimezone(datetime.timezone.utc)
    end_time_dt = now + datetime.timedelta(days=8)
    today_date = now.date()
    
    # 1. Start fetching 2 days ago
    start_lookback = now - datetime.timedelta(days=2)
    start_time_gl = start_lookback.strftime('%Y-%m-%dT00:00:00Z')
    
    # We pass aware datetimes to fetch_ics_events
    # Ensure start_lookback is aware (it is if 'now' is aware)
    ics_events = fetch_ics_events(start_lookback, end_time_dt)

    # ... (Google Calendar setup) ...
    all_events = []
    # Add ICS events first (normalized structure)
    for ev in ics_events:
        # Normalize structure
        s = ev['start']
        # s is datetime (likely aware or naive depending on ICS)
        if isinstance(s, datetime.datetime):
             s_str = s.isoformat()
        else:
             s_str = s.isoformat() # Date object
             
        all_events.append({
            'start': {'dateTime': s_str},
            'summary': ev['summary'],
            'calendar_name': ev['calendar_name']
        })

    # ... Now continue with Google Calendar logic ...
    
    if not service_account_info_str:
         pass 
    else:
        try:
            service_account_info = json.loads(service_account_info_str)
            creds = service_account.Credentials.from_service_account_info(
                service_account_info, scopes=['https://www.googleapis.com/auth/calendar.readonly'])
            service = build('calendar', 'v3', credentials=creds)
            
            # Google Time Range
            start_time_gl = start_lookback.strftime('%Y-%m-%dT00:00:00Z')
            end_time_gl = end_time_dt.strftime('%Y-%m-%dT23:59:59Z')
            
            # ... (rest of Google Logic: fetch target_cals etc) ...
            target_cals_env = os.environ.get("TARGET_CALENDAR_ID")
            calendars = []
            if target_cals_env:
                ids = [x.strip() for x in target_cals_env.split(',') if x.strip()]
                for cal_id in ids:
                     calendars.append({'id': cal_id, 'summary': cal_id})
            
            if calendars:
                for cal in calendars:
                    cal_id = cal['id']
                    try:
                        events_result = service.events().list(calendarId=cal_id, timeMin=start_time_gl,
                                                            timeMax=end_time_gl, singleEvents=True,
                                                            orderBy='startTime').execute()
                        events = events_result.get('items', [])
                        for event in events:
                            event['calendar_name'] = cal.get('summary', 'Unknown')
                            all_events.append(event)
                    except Exception as e:
                        print(f"Failed to read calendar {cal_id}: {e}")
        except Exception as e:
            print(f"Google Calendar Error: {e}")

    # Final Merge & Sort
    if not all_events:
        return "No events found (Past, Today, or Week)."
        
    # Sort
    def get_start(x):
        return x['start'].get('dateTime', x['start'].get('date'))
        
    all_events.sort(key=get_start)

    today_str = today_date.strftime('%Y-%m-%d')
    
    past_summary = []
    today_summary = []
    upcoming_summary = []

    for event in all_events:
        start_raw = get_start(event)
        # Parse start_raw to compare dates
        # Try basic ISO parsing
        try:
            # Handle both '2025-12-12' and '2025-12-12T10:00:00+01:00'
             if 'T' in start_raw:
                 dt_val = datetime.datetime.fromisoformat(start_raw)
                 date_val = dt_val.date()
             else:
                 date_val = datetime.date.fromisoformat(start_raw)
        except:
             # Fallback string comparison
             date_val = None
        
        summary = event.get('summary', 'Busy')
        cal = event.get('calendar_name', '?')
        line = f"[{cal}] {start_raw}: {summary}"
        
        if date_val:
            if date_val < today_date:
                past_summary.append(line)
            elif date_val == today_date:
                today_summary.append(line)
            else:
                upcoming_summary.append(line)
        else:
            # Fallback based on string match
            if start_raw.startswith(today_str):
                 today_summary.append(line)
            elif start_raw < today_str:
                 past_summary.append(line)
            else:
                 upcoming_summary.append(line)

    output_lines = []
    
    if past_summary:
        output_lines.append("--- CONTEXTE PASSÉ (Hier/Avant-hier) ---")
        output_lines.extend(past_summary)
        output_lines.append("")

    if today_summary:
        output_lines.append("--- FOCUS AUJOURD'HUI ---")
        output_lines.extend(today_summary)
    else:
        output_lines.append("--- FOCUS AUJOURD'HUI : RIEN ---")
        
    if upcoming_summary:
        output_lines.append("\n--- CONTEXTE SEMAINE ---")
        output_lines.extend(upcoming_summary)
        
    return "\n".join(output_lines)
