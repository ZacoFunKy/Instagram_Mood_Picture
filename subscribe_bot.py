import os
import json
from dotenv import load_dotenv
from google.oauth2 import service_account
from googleapiclient.discovery import build

load_dotenv()

def subscribe_bot():
    """
    Attempts to add the specified calendars (from TARGET_CALENDAR_ID) 
    to the Service Account's own 'CalendarList'. 
    This is often required for the SA to see 'public' or 'imported' calendars.
    """
    service_account_info_str = os.environ.get("GOOGLE_SERVICE_ACCOUNT")
    if not service_account_info_str:
         print("Error: GOOGLE_SERVICE_ACCOUNT not set.")
         return

    try:
        service_account_info = json.loads(service_account_info_str)
    except json.JSONDecodeError:
        print("Error: Invalid JSON for GOOGLE_SERVICE_ACCOUNT.")
        return

    creds = service_account.Credentials.from_service_account_info(
        service_account_info, scopes=['https://www.googleapis.com/auth/calendar']) # Need write scope to insert

    service = build('calendar', 'v3', credentials=creds)

    target_cals_env = os.environ.get("TARGET_CALENDAR_ID")
    if not target_cals_env:
        print("No TARGET_CALENDAR_ID found in .env.")
        return

    ids = [x.strip() for x in target_cals_env.split(',') if x.strip()]
    
    print(f"Attempting to subscribe bot to {len(ids)} calendars...")
    
    for cal_id in ids:
        print(f"\nProcessing: {cal_id}")
        try:
            # Check if already present
            try:
                service.calendarList().get(calendarId=cal_id).execute()
                print(f" -> Already subscribed!")
                continue
            except:
                pass # Not found, proceed to insert

            # Insert
            # For imported calendars, sometimes just 'id' is enough.
            entry = {'id': cal_id}
            service.calendarList().insert(body=entry).execute()
            print(f" -> SUCCESS! Bot subscribed.")
            
        except Exception as e:
            print(f" -> FAILED. Reason: {e}")
            print("    (This usually means the calendar is Private and neither Shared nor Public. The URL import source might not be public to the bot.)")

if __name__ == "__main__":
    subscribe_bot()
