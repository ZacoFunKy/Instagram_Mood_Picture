
import pytest
from unittest.mock import MagicMock, patch
from datetime import datetime
from src.adapters.repositories.mongo import DailyLogManager, MongoDBOperationError

@pytest.fixture
def mock_collection():
    return MagicMock()

def test_save_log_tri_daily(mock_collection):
    """Verify that logs with different execution types are saved correctly."""
    manager = DailyLogManager()
    
    # Test Data
    date_str = "2024-12-16"
    
    log_morning = {
        "date": date_str,
        "execution_type": "MATIN",
        "mood_selected": "tired"
    }
    
    log_evening = {
        "date": date_str,
        "execution_type": "SOIREE",
        "mood_selected": "chill"
    }

    # 1. Save Morning Log
    manager.save_log(mock_collection, log_morning)
    
    # Verify replace_one called with compound query for MATIN
    mock_collection.replace_one.assert_any_call(
        {"date": date_str, "execution_type": "MATIN"},
        log_morning,
        upsert=True
    )

    # 2. Save Evening Log
    manager.save_log(mock_collection, log_evening)

    # Verify replace_one called with compound query for SOIREE
    mock_collection.replace_one.assert_any_call(
        {"date": date_str, "execution_type": "SOIREE"},
        log_evening,
        upsert=True
    )

def test_get_historical_moods_filtering(mock_collection):
    """Verify that historical fetch respects execution_type filter."""
    manager = DailyLogManager()
    weekday = "Monday"
    
    # Mock return data
    mock_cursor = MagicMock()
    mock_cursor.sort.return_value = mock_cursor
    mock_cursor.limit.return_value = [
        {"date": "2024-12-09", "execution_type": "SOIREE", "mood": "happy"},
        {"date": "2024-12-02", "execution_type": "SOIREE", "mood": "tired"}
    ]
    mock_collection.find.return_value = mock_cursor
    
    # 1. Fetch with specific execution type
    results = manager.get_historical_moods(mock_collection, weekday, execution_type="SOIREE")
    
    # Verify query includes execution_type
    mock_collection.find.assert_called_with({"weekday": weekday, "execution_type": "SOIREE"})
    assert len(results) == 2

    # 2. Fetch without execution type (Backward compatibility / broad search)
    manager.get_historical_moods(mock_collection, weekday, execution_type=None)
    
    # Verify query relies only on weekday
    mock_collection.find.assert_called_with({"weekday": weekday})
