
import pytest
import os
import sys
from unittest.mock import MagicMock, patch
from datetime import datetime, date

# Add project root to Python Path so modules can be imported
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from src.core.analyzer import MoodCategory, SignalStrength

# ============================================================================
# 1. GLOBAL MOCKS (ENV VARS & APIS)
# ============================================================================

@pytest.fixture(autouse=True)
def mock_env_vars():
    """Sets up fake environment variables for all tests."""
    with patch.dict(os.environ, {
        "GEMINI_API_KEY": "fake_key",
        "SPOTIFY_CLIENT_ID": "fake_id",
        "SPOTIFY_CLIENT_SECRET": "fake_secret",
        "GOOGLE_SERVICE_ACCOUNT": '{"project_id": "test"}',
        "TARGET_CALENDAR_ID": "cal_id",
    }):
        yield

@pytest.fixture
def mock_genai():
    """Mocks Google Generative AI (Gemini)."""
    with patch("src.adapters.clients.gemini.genai") as mock:
        # Configure
        mock.configure = MagicMock()
        
        # Model
        model_instance = MagicMock()
        mock.GenerativeModel.return_value = model_instance
        
        # Default happy path response
        response = MagicMock()
        response.text = "energetic"
        model_instance.generate_content.return_value = response
        
        yield mock

@pytest.fixture
def mock_requests():
    """Mocks generic requests (Weather, etc)."""
    with patch("requests.get") as mock_get:
        yield mock_get

@pytest.fixture
def mock_spotify():
    """Mocks Spotify Client."""
    with patch("src.adapters.clients.spotify.spotipy.Spotify") as mock_sp_cls:
        client = mock_sp_cls.return_value
        yield client

# ============================================================================
# 2. CONTEXT DATA FIXTURES
# ============================================================================

@pytest.fixture
def sample_sleep_context():
    """Returns sample sleep data."""
    return {
        "sleep_hours": 7.5, 
        "bedtime": "23:00", 
        "wake_time": "06:30",
        "quality": "OK"
    }

@pytest.fixture
def sample_weather_context():
    """Returns sample weather string."""
    return "Ensoleillé (Sunny), 20C"

@pytest.fixture
def sample_music_summary():
    """Returns sample music summary."""
    return "Artist - Song [V:0.8 E:0.9 D:0.7 T:128]"

@pytest.fixture
def sample_calendar_events():
    """Returns structured calendar events."""
    return [
        {
            "summary": "Focus Time",
            "start": {"dateTime": "2025-01-01T10:00:00Z"}
        },
        {
            "summary": "Meeting",
            "start": {"dateTime": "2025-01-01T14:00:00Z"}
        }
    ]
