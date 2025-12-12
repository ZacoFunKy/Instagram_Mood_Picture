import os
import datetime
import json
from google.oauth2 import service_account
from googleapiclient.discovery import build
from dotenv import load_dotenv

load_dotenv()

def get_calendar_service():
    """Authenticates with Google Calendar API using Service Account."""
    creds_json = os.environ.get("GOOGLE_SERVICE_ACCOUNT")
    if not creds_json:
        print("Error: GOOGLE_SERVICE_ACCOUNT not set.")
        return None
    
    try:
        creds_dict = json.loads(creds_json)
        creds = service_account.Credentials.from_service_account_info(
            creds_dict, scopes=['https://www.googleapis.com/auth/calendar']
        )
        return build('calendar', 'v3', credentials=creds)
    except Exception as e:
        print(f"Auth Error: {e}")
        return None

def create_event(service, calendar_id, summary, description, date_start):
    """Creates a timed event (18h-19h)."""
    # Date format YYYY-MM-DD
    date_str = date_start.strftime('%Y-%m-%d')
    
    event = {
        'summary': summary,
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
                {'method': 'email', 'minutes': 24 * 60}, # 1 jour avant
                {'method': 'popup', 'minutes': 30},
            ],
        },
    }

    try:
        event = service.events().insert(calendarId=calendar_id, body=event).execute()
        print(f"Événement créé : {event.get('htmlLink')}")
    except Exception as e:
        print(f"Erreur lors de la création de '{summary}': {e}")

def main():
    service = get_calendar_service()
    if not service:
        return

    calendar_id = os.environ.get("TARGET_CALENDAR_ID")
    if not calendar_id:
        print("Error: TARGET_CALENDAR_ID not set.")
        return

    today = datetime.datetime.now()
    
    # 1. Instagram Session ID (Every 3 months = ~90 days)
    # Prévention car on ne peut pas connaître la date exacte d'expiration côté serveur
    ig_date = today + datetime.timedelta(days=90)
    create_event(
        service, 
        calendar_id, 
        "🔧 Maintenance Projet Insta-Mood : Renouveler Session ID", 
        "Pour éviter que le bot ne plante, connecte-toi sur Instagram, récupère le nouveau 'sessionid' et mets à jour le Secret GitHub 'IG_SESSIONID'.",
        ig_date
    )

    # 2. YouTube Music Headers (Every 6 months = ~180 days)
    yt_date = today + datetime.timedelta(days=180)
    create_event(
        service, 
        calendar_id, 
        "🔧 Maintenance Projet Insta-Mood : Renouveler Headers YouTube", 
        "Les headers YouTube expirent bientôt. Récupère les nouveaux headers (JSON) et mets à jour le Secret GitHub 'YTMUSIC_HEADERS'.",
        yt_date
    )

    print("Rappels de maintenance programmés (Français, 18h-19h) !")

if __name__ == "__main__":
    main()
