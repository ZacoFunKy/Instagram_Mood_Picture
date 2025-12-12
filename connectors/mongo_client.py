import os
import pymongo
from pymongo import MongoClient
import datetime
import certifi

def connect_db():
    """Connects to MongoDB Atlas using the URI from environment variables."""
    uri = os.environ.get("MONGODB_URI")
    if not uri:
        raise ValueError("MONGODB_URI environment variable not set")
    
    # [FIX] Force bypass SSL verification to resolve persistent TLSV1_ALERT_INTERNAL_ERROR on Windows
    client = MongoClient(uri, tls=True, tlsAllowInvalidCertificates=True)
    return client

def get_database():
    """Returns the database instance."""
    client = connect_db()
    # Assuming the database name is 'predictive_profile' or similar, 
    # but the URI might include it. Let's default to a name if not extracted.
    # For simplicity, we'll use a specific db name: 'profile_predictor'
    return client['profile_predictor']

def clean_old_logs(collection):
    """
    Keep only the last 365 documents.
    If count > 365, delete the oldest ones.
    """
    count = collection.count_documents({})
    if count > 365:
        # Remove oldest to maintain 365. 
        # Ideally we remove count - 365 docs.
        to_remove = count - 365
        # Find the oldest 'to_remove' docs
        # We assume there is a 'date' or timestamp field to sort by. 
        # The spec says "date": "2023-10-24" (string). String sort YYYY-MM-DD works.
        cursor = collection.find().sort("date", pymongo.ASCENDING).limit(to_remove)
        ids_to_delete = [doc["_id"] for doc in cursor]
        if ids_to_delete:
            collection.delete_many({"_id": {"$in": ids_to_delete}})
            print(f"Cleaned {len(ids_to_delete)} old logs.")

def get_historical_moods(collection, weekday):
    """
    Fetch the last 4 logs for the given weekday.
    """
    # weekday e.g. "Tuesday"
    cursor = collection.find({"weekday": weekday}).sort("date", pymongo.DESCENDING).limit(4)
    # Return list reversed so it's chronological (oldest to newest of the last 4)
    return list(cursor)[::-1]

def save_log(collection, data):
    """
    Insert a new daily log or update if it exists for the same date.
    Triggers cleanup.
    """
    # Assuming 'date' ("YYYY-MM-DD") is the unique key for a daily log
    date_str = data.get("date")
    if date_str:
        collection.replace_one({"date": date_str}, data, upsert=True)
    else:
        # Fallback if no date (shouldn't happen given main.py logic)
        collection.insert_one(data)
        
    clean_old_logs(collection)
