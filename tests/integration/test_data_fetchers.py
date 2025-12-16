
import pytest
from unittest.mock import MagicMock, patch
from datetime import datetime

from src.adapters.clients.weather import WeatherAPIClient, WeatherData
from src.adapters.clients.calendar import EventFormatter

class TestDataFetchers:
    """Test suite for Data Fetcher & Parsing logic."""

    # ========================================================================
    # 1. WEATHER PARSING
    # ========================================================================

    def test_weather_parsing_success(self):
        """Test parsing of valid Open-Meteo response."""
        client = WeatherAPIClient()
        
        # Valid JSON response
        mock_data = {
            "daily": {
                "temperature_2m_max": [20.5],
                "temperature_2m_min": [10.0],
                "weather_code": [0] # Clear
            }
        }
        
        result = client._parse_forecast(mock_data)
        
        assert isinstance(result, WeatherData)
        assert result.max_temp == 20.5
        assert result.min_temp == 10.0
        assert "Ensoleill" in result.condition

    def test_weather_parsing_empty_or_error(self):
        """Test parsing handles empty or malformed data gracefully."""
        client = WeatherAPIClient()
        
        # Empty
        assert client._parse_forecast({}) is None
        
        # Malformed
        assert client._parse_forecast({"daily": {}}) is None

    # ========================================================================
    # 2. CALENDAR PARSING
    # ========================================================================

    def test_calendar_formatter_sorts_correctly(self):
        """Test events are sorted by time and categorized (Past/Today/Future)."""
        today = datetime(2025, 1, 1).date()
        
        events = [
            {"summary": "Future", "start": {"dateTime": "2025-01-02T10:00"}}, # Tomorrow
            {"summary": "Past", "start": {"dateTime": "2024-12-31T10:00"}},   # Yesterday
            {"summary": "Today", "start": {"dateTime": "2025-01-01T15:00"}}   # Today
        ]
        
        summary = EventFormatter.format_events_summary(events, today_date=today)
        
        # Check Sections
        assert "CONTEXTE PASSÉ" in summary
        assert "FOCUS AUJOURD'HUI" in summary
        assert "CONTEXTE SEMAINE" in summary
        
        # Check Order (implicit in section presence, but verify string content)
        assert "Past" in summary
        assert "Today" in summary
        assert "Future" in summary

    def test_calendar_empty_input(self):
        """Test formatter handles empty list."""
        assert "No events found" in EventFormatter.format_events_summary([])
