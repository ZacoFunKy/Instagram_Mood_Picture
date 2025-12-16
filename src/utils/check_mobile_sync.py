#!/usr/bin/env python3
"""
Pre-Prediction Mobile Sync Checker
Ensures mobile data is fresh before AI prediction runs.
"""

import os
import sys
from datetime import datetime, timedelta
from pymongo import MongoClient

def check_mobile_sync_freshness():
    """
    Checks if mobile data was synced recently.
    Logs a warning if data is stale (> 3 hours old).
    """
    # Use MONGO_URI_MOBILE for overrides, fallback to MONGODB_URI
    mongo_uri = os.getenv("MONGO_URI_MOBILE") or os.getenv("MONGODB_URI")
    if not mongo_uri:
        print("⚠️  MONGO_URI_MOBILE or MONGODB_URI not set, skipping sync check")
        return
    
    try:
        client = MongoClient(mongo_uri, serverSelectionTimeoutMS=5000)
        db = client.get_default_database()
        collection = db['overrides']
        
        # Get today's date
        today = datetime.now().strftime("%Y-%m-%d")
        
        # Fetch today's override document
        doc = collection.find_one({"date": today})
        
        if not doc:
            print(f"⚠️  No mobile sync found for {today}")
            print("   The AI will proceed without step count/feedback data.")
            return
        
        # Check last_updated timestamp
        last_updated_str = doc.get("last_updated")
        if not last_updated_str:
            print("⚠️  Mobile sync exists but has no timestamp")
            return
        
        # Parse timestamp
        last_updated = datetime.fromisoformat(last_updated_str.replace('Z', '+00:00'))
        now = datetime.now(last_updated.tzinfo)
        age = now - last_updated
        
        # Check freshness
        if age > timedelta(hours=3):
            print(f"⚠️  Mobile data is STALE (last sync: {age.total_seconds() / 3600:.1f}h ago)")
            print("   Consider manually syncing the app before prediction.")
        else:
            print(f"✅ Mobile data is FRESH (last sync: {age.total_seconds() / 60:.0f}min ago)")
            
            # Log what data we have
            has_steps = doc.get("steps_count", 0) > 0
            has_feedback = "feedback_energy" in doc
            
            print(f"   - Step Count: {doc.get('steps_count', 0)} steps {'✅' if has_steps else '❌'}")
            print(f"   - Feedback Metrics: {'✅' if has_feedback else '❌'}")
            print(f"   - Sleep Hours: {doc.get('sleep_hours', 'N/A')}")
        
        client.close()
        
    except Exception as e:
        print(f"⚠️  Error checking mobile sync: {e}")

if __name__ == "__main__":
    print("=" * 60)
    print("PRE-PREDICTION MOBILE SYNC CHECK")
    print("=" * 60)
    check_mobile_sync_freshness()
    print("=" * 60)
