"""
MongoDB client for daily mood logs and historical data.

This module provides database operations for:
- Storing daily mood predictions with context
- Retrieving historical mood patterns by weekday
- Maintenance: cleaning old logs to maintain database size
"""

import os
import logging
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any
from typing_extensions import deprecated

import pymongo
from pymongo import MongoClient
from pymongo.errors import ServerSelectionTimeoutError, OperationFailure
import certifi

logger = logging.getLogger(__name__)


# ============================================================================
# CONSTANTS
# ============================================================================

DATABASE_NAME = "profile_predictor"
LOGS_COLLECTION_NAME = "daily_log"

MAX_LOG_RETENTION_DAYS = 365
CONNECTION_TIMEOUT_MS = 10000
DEFAULT_LOG_LIMIT = 4


# ============================================================================
# EXCEPTIONS
# ============================================================================

class MongoDBConnectionError(Exception):
    """Raised when MongoDB connection fails."""
    pass


class MongoDBOperationError(Exception):
    """Raised when database operations fail."""
    pass


# ============================================================================
# DATABASE CONNECTION
# ============================================================================

class DatabaseConfig:
    """Encapsulates MongoDB connection configuration."""

    def __init__(self, uri: Optional[str] = None):
        """
        Initialize database configuration.

        Args:
            uri: MongoDB connection URI (defaults to MONGODB_URI env var)

        Raises:
            ValueError: If URI not provided and env var not set
        """
        self.uri = uri or os.environ.get("MONGODB_URI")
        if not self.uri:
            raise ValueError("MONGODB_URI environment variable not set")

    def get_client(self) -> MongoClient:
        """
        Creates a MongoDB client with secure SSL/TLS configuration.

        Returns:
            Connected MongoClient instance.

        Raises:
            MongoDBConnectionError: If connection fails.
        """
        try:
            # Use certifi for secure CA bundle (fixes Windows TLS issues)
            client = MongoClient(
                self.uri,
                tlsCAFile=certifi.where(),
                serverSelectionTimeoutMS=CONNECTION_TIMEOUT_MS,
                connectTimeoutMS=CONNECTION_TIMEOUT_MS
            )
            # Verify connection
            client.admin.command('ping')
            logger.info("[OK] MongoDB connected successfully")
            return client

        except ServerSelectionTimeoutError:
            logger.error("MongoDB connection timeout")
            raise MongoDBConnectionError("Connection timeout") from None
        except OperationFailure as e:
            logger.error(f"MongoDB authentication failed: {e}")
            raise MongoDBConnectionError(f"Authentication failed: {e}") from None
        except Exception as e:
            logger.error(f"MongoDB connection failed: {e}")
            raise MongoDBConnectionError(str(e)) from e


class DatabaseConnection:
    """Singleton connection manager for MongoDB."""

    _instance: Optional['DatabaseConnection'] = None
    _client: Optional[MongoClient] = None

    def __new__(cls) -> 'DatabaseConnection':
        """Singleton pattern: single instance."""
        if cls._instance is None:
            cls._instance = super().__new__(cls)
        return cls._instance

    def get_client(self) -> MongoClient:
        """
        Gets or creates MongoDB client.

        Returns:
            MongoClient instance.

        Raises:
            MongoDBConnectionError: If connection fails.
        """
        if self._client is None:
            try:
                config = DatabaseConfig()
                self._client = config.get_client()
            except ValueError as e:
                logger.error(str(e))
                raise MongoDBConnectionError(str(e)) from e

        return self._client

    def get_database(self) -> pymongo.database.Database:
        """
        Gets database instance.

        Returns:
            MongoDB database object.

        Raises:
            MongoDBConnectionError: If connection fails.
        """
        client = self.get_client()
        return client[DATABASE_NAME]

    def close(self) -> None:
        """Closes database connection."""
        if self._client:
            self._client.close()
            self._client = None
            logger.info("MongoDB connection closed")


# ============================================================================
# LOG MANAGEMENT
# ============================================================================

class DailyLogManager:
    """Manages daily mood log storage and retrieval."""

    @staticmethod
    def save_log(collection: pymongo.collection.Collection, entry: Dict[str, Any]) -> None:
        """
        Saves or updates a daily log entry.
        Performs upsert based on date (one log per day).

        Args:
            collection: MongoDB collection.
            entry: Log entry dict with 'date', 'mood_selected', etc.

        Raises:
            MongoDBOperationError: If save fails.
        """
        try:
            date_str = entry.get("date")
            if not date_str:
                raise ValueError("Entry missing 'date' field")

            execution_type = entry.get("execution_type", "UNKNOWN")

            # Upsert: update if exists (date + execution_type), insert if not
            result = collection.replace_one(
                {"date": date_str, "execution_type": execution_type},
                entry,
                upsert=True
            )

            if result.upserted_id:
                logger.info(f"[OK] New log inserted for {date_str}")
            else:
                logger.info(f"[OK] Log updated for {date_str}")

        except pymongo.errors.DuplicateKeyError as e:
            logger.error(f"Duplicate key error: {e}")
            raise MongoDBOperationError(f"Duplicate entry for {entry.get('date')}") from e
        except Exception as e:
            logger.error(f"Failed to save log: {e}")
            raise MongoDBOperationError(f"Save failed: {e}") from e


    @staticmethod
    def get_historical_moods(collection: pymongo.collection.Collection,
                             weekday: str,
                             execution_type: Optional[str] = None,
                             limit: int = DEFAULT_LOG_LIMIT) -> List[Dict[str, Any]]:
        """
        Retrieves historical moods for a specific weekday.
        Used for trend analysis and contextual mood prediction.

        Args:
            collection: MongoDB collection.
            weekday: Day name (e.g., "Monday").
            limit: Maximum number of entries to retrieve.

        Returns:
            List of log entries (chronological order: oldest to newest).
        """
        try:
            query = {"weekday": weekday}
            if execution_type:
                query["execution_type"] = execution_type

            cursor = collection.find(query).sort(
                "date",
                pymongo.DESCENDING
            ).limit(limit)

            entries = list(cursor)
            # Reverse to chronological order (oldest to newest)
            entries = entries[::-1]

            logger.info(f"[OK] Retrieved {len(entries)} historical moods for {weekday}")
            return entries

        except Exception as e:
            logger.error(f"Failed to retrieve historical moods for {weekday}: {e}")
            raise MongoDBOperationError(f"Retrieval failed: {e}") from e

    @staticmethod
    def clean_old_logs(collection: pymongo.collection.Collection,
                      retention_days: int = MAX_LOG_RETENTION_DAYS) -> int:
        """
        Deletes logs older than retention period.

        Args:
            collection: MongoDB collection.
            retention_days: Days to retain (default 365).

        Returns:
            Number of deleted documents.
        """
        try:
            cutoff_date = (datetime.now() - timedelta(days=retention_days)).strftime("%Y-%m-%d")

            # Count before deletion
            count_before = collection.count_documents({})

            # Delete documents with date < cutoff_date
            result = collection.delete_many({"date": {"$lt": cutoff_date}})

            deleted_count = result.deleted_count
            count_after = collection.count_documents({})

            if deleted_count > 0:
                logger.info(f"🧹 Cleaned {deleted_count} old logs. "
                          f"Retention: {retention_days} days. "
                          f"Total before: {count_before}, after: {count_after}")

            return deleted_count

        except Exception as e:
            logger.warning(f"Log cleanup failed: {e}")
            return 0

    @staticmethod
    def get_daily_override(db: pymongo.database.Database,
                          date_str: str) -> Dict[str, Any]:
        """
        Retrieves manual overrides (sleep, mood) for a specific date.
        Collection: 'overrides' (from MONGO_URI_MOBILE if available)
        """
        try:
            # Try to use mobile database for overrides
            mongo_uri_mobile = os.environ.get("MONGO_URI_MOBILE")
            if mongo_uri_mobile:
                try:
                    mobile_client = MongoClient(
                        mongo_uri_mobile,
                        tlsCAFile=certifi.where(),
                        serverSelectionTimeoutMS=CONNECTION_TIMEOUT_MS,
                        connectTimeoutMS=CONNECTION_TIMEOUT_MS
                    )
                    mobile_db = mobile_client.get_default_database()
                    collection = mobile_db['overrides']
                except Exception as mobile_error:
                    logger.warning(f"Failed to connect to MONGO_URI_MOBILE, using fallback: {mobile_error}")
                    collection = db['overrides']
            else:
                # Fallback to main database
                collection = db['overrides']
            
            override = collection.find_one({"date": date_str})
            if override:
                logger.info(f"[OK] Found manual override for {date_str}: {override}")
                return override
            return {}
        except Exception as e:
            logger.warning(f"Failed to fetch overrides: {e}")
            return {}


# ============================================================================
# PUBLIC API
# ============================================================================

def get_database() -> pymongo.database.Database:
    """
    Gets database instance.
    This is the main entry point for database access.

    Returns:
        MongoDB database object.

    Raises:
        MongoDBConnectionError: If connection fails.
    """
    try:
        conn = DatabaseConnection()
        return conn.get_database()
    except MongoDBConnectionError as e:
        logger.error(f"Database connection failed: {e}")
        raise


@deprecated("Use get_database() instead")
def connect_db() -> MongoClient:
    """
    Gets MongoDB client instance.
    Maintained for backward compatibility.

    Returns:
        MongoClient instance.

    Raises:
        MongoDBConnectionError: If connection fails.
    """
    try:
        conn = DatabaseConnection()
        return conn.get_client()
    except MongoDBConnectionError as e:
        logger.error(f"Failed to connect: {e}")
        raise


def save_log(collection: pymongo.collection.Collection, data: Dict[str, Any]) -> None:
    """
    Saves a daily log entry.
    Performs upsert and triggers maintenance cleanup.

    Args:
        collection: MongoDB collection.
        data: Log entry dict.

    Raises:
        MongoDBOperationError: If save fails.
    """
    manager = DailyLogManager()
    manager.save_log(collection, data)
    # Perform maintenance after each save
    try:
        manager.clean_old_logs(collection)
    except Exception as e:
        logger.warning(f"Log cleanup warning: {e}")


def get_historical_moods(collection: pymongo.collection.Collection,
                        weekday: str,
                        execution_type: Optional[str] = None) -> List[Dict[str, Any]]:
    """
    Retrieves historical moods for a weekday.

    Args:
        collection: MongoDB collection.
        weekday: Day name.

    Returns:
        List of historical mood entries.
    """
    manager = DailyLogManager()
    return manager.get_historical_moods(collection, weekday, execution_type)


def clean_old_logs(collection: pymongo.collection.Collection) -> None:
    """
    Cleans old logs from database.

    Args:
        collection: MongoDB collection.
    """
    manager = DailyLogManager()
    manager.clean_old_logs(collection)


def get_daily_override(date_str: str) -> Dict[str, Any]:
    """
    Retrieves manual overrides for a date.

    Args:
        date_str: Date string YYYY-MM-DD.
    """
    try:
        db = get_database()
        manager = DailyLogManager()
        return manager.get_daily_override(db, date_str)
    except Exception as e:
        logger.warning(f"Override fetch failed: {e}")
        return {}
