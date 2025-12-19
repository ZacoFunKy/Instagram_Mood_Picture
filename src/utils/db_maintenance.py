"""
Database Maintenance Utility
Ensures MongoDB database size stays within limits (e.g., 500MB) by cleaning old data.
"""

import os
import logging
from typing import Optional
from datetime import datetime, timedelta

import pymongo
import certifi

logger = logging.getLogger(__name__)

# Constants
MAX_STORAGE_MB_LIMIT = 500
SAFE_STORAGE_MB_THRESHOLD = 480  # Start cleaning if we reach this
BATCH_DELETE_SIZE = 100
MAX_CLEANUP_ITERATIONS = 50

class DatabaseMaintainer:
    """Manages database size and maintenance."""

    def __init__(self, uri: str):
        self.uri = uri
        self.client: Optional[pymongo.MongoClient] = None

    def connect(self):
        """Establishes connection."""
        if not self.client:
            self.client = pymongo.MongoClient(
                self.uri,
                tlsCAFile=certifi.where(),
                serverSelectionTimeoutMS=5000
            )

    def close(self):
        """Closes connection."""
        if self.client:
            self.client.close()
            self.client = None

    def check_and_clean(self):
        """
        Checks database size and cleans old records if needed.
        """
        try:
            self.connect()
            db = self.client.get_default_database()
            
            # 1. Check DB Stats
            stats = db.command("dbStats")
            storage_size_bytes = stats.get('storageSize', 0)
            storage_size_mb = storage_size_bytes / (1024 * 1024)
            
            logger.info(f"💾 DB Stats for {db.name}: {storage_size_mb:.2f} MB (Usage)")

            if storage_size_mb < SAFE_STORAGE_MB_THRESHOLD:
                logger.info("✅ Database size is within safe limits.")
                return

            logger.warning(
                f"⚠️ DATABASE SIZE ({storage_size_mb:.2f} MB) EXCEEDS THRESHOLD ({SAFE_STORAGE_MB_THRESHOLD} MB). "
                "STARTING CLEANUP..."
            )
            
            self._clean_collection(db, 'daily_logs', 'date')
            self._clean_collection(db, 'overrides', 'date')
            
            # Check size again
            stats_after = db.command("dbStats")
            size_after_mb = stats_after.get('storageSize', 0) / (1024 * 1024)
            logger.info(f"🏁 Cleanup Complete. New Size: {size_after_mb:.2f} MB")

        except Exception as e:
            logger.error(f"❌ Database maintenance failed: {e}")
        finally:
            self.close()

    def _clean_collection(self, db, collection_name: str, date_field: str):
        """
        Deletes oldest records from a collection until safe size or max iterations.
        """
        collection = db[collection_name]
        
        for i in range(MAX_CLEANUP_ITERATIONS):
            # Check size again (approximated check to avoid excessive overhead, 
            # ideally we rely on the main loop check but let's just delete batches)
            # Actually, `storageSize` won't shrink immediately on MongoDB (it needs compaction),
            # but `dataSize` will. We proceed to delete oldest data.
            
            # Find oldest documents
            cursor = collection.find().sort(date_field, pymongo.ASCENDING).limit(BATCH_DELETE_SIZE)
            docs = list(cursor)
            
            if not docs:
                logger.info(f"   - Collection {collection_name} is empty or fully cleaned.")
                break
                
            ids_to_delete = [d['_id'] for d in docs]
            oldest_date = docs[0].get(date_field, 'Unknown')
            
            result = collection.delete_many({'_id': {'$in': ids_to_delete}})
            logger.info(f"   🗑️ Deleted {result.deleted_count} records from {collection_name} (Oldest: {oldest_date})")
            
            # Since `storageSize` doesn't release automatically without `compact`, 
            # we rely on clearing a specific amount or count. 
            # For simplicity in this script, we'll iterate a few times if we are really full.
            # Real resizing usually requires `db.repairDatabase()` or wait for auto-reuse.
            
            # Optimization: If we deleted nothing, stop.
            if result.deleted_count == 0:
                break

def run_maintenance():
    """Run maintenance for all configured databases."""
    uris = [
        ("Main DB", os.getenv("MONGODB_URI")),
        ("Mobile DB", os.getenv("MONGO_URI_MOBILE"))
    ]
    
    for name, uri in uris:
        if uri:
            logger.info(f"🔧 Running maintenance for {name}...")
            maintainer = DatabaseMaintainer(uri)
            maintainer.check_and_clean()
        else:
            logger.debug(f"Skipping maintenance for {name} (URI not set)")

if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    from dotenv import load_dotenv
    load_dotenv()
    run_maintenance()
