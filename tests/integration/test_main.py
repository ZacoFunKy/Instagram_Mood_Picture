
import pytest
from unittest.mock import MagicMock, patch
import sys
import os

# Import main (requires project root in path)
from src import main

class TestMainOrchestrator:
    """Test suite for the Main script orchestration."""

    @patch("src.main.weather_client.get_bordeaux_weather")
    @patch("src.main.calendar_client.get_week_events")
    @patch("src.main.get_music_summary_for_window")
    @patch("src.main.yt_music.SleepEstimator")
    @patch("src.main.gemini_client.predict_mood")
    @patch("src.main.logger") # Mock logger to avoid spam
    def test_main_execution_flow(self, mock_logger, mock_predict, mock_sleep, mock_music, mock_cal, mock_weather):
        """
        Verify the script runs from start to finish without error and calls key components.
        """
        # --- SETUP MOCKS ---
        mock_weather.return_value = "Sunny"
        mock_cal.return_value = "Meeting"
        # get_music_summary_for_window returns (summary, sleep_info, metrics)
        mock_music.return_value = ("Metal", {"sleep_hours": 8}, {})
        
        # Sleep Mock (called inside get_music_summary_for_window usually, but if we mock that, we might not need this?)
        # Wait, if we mock get_music_summary_for_window, main() won't call SleepEstimator directly if it's inside that function.
        # Let's check main() logic. If main() calls get_music_summary_for_window, then that function does the sleep estimation.
        # So mocking get_music_summary_for_window is enough for the music/sleep part.
        # But we kept mock_sleep in the signature. Let's keep it but it might not be called.
        # Actually, let's assume main() calls get_music_summary_for_window.
        
        # Adjust mock_music return to match signature: (str, dict, dict)
        
        # Predict Mock
        mock_predict.return_value = "pumped"
        
        # --- EXECUTE MAIN LOGIC ---
        # Patch sys.argv to avoid argparse conflict with pytest args
        with patch.object(sys, 'argv', ['main.py', '--no-delay', '--dry-run']):
             # Call main
             try:
                 main.main()
             except SystemExit:
                 # Should not happen if argv is clean, but catch if it does
                 pass 
             except Exception as e:
                 pytest.fail(f"Main crashed: {e}")
                 
             # --- ASSERTIONS ---
             # Verify connectors were called
             mock_weather.assert_called_once()
             mock_cal.assert_called_once()
             mock_music.assert_called_once()
             # mock_sleep might not be called if we mocked the wrapper
             mock_predict.assert_called_once()

    def test_main_handles_exception_gracefully(self):
        """Test that main doesn't crash if a connector fails."""
        with patch("src.main.weather_client.get_bordeaux_weather", side_effect=Exception("API Error")):
             with patch.object(sys, 'argv', ['main.py', '--no-delay', '--dry-run']):
                 # It should catch exception and log it, not crash the process
                 try:
                     main.main()
                 except Exception as e:
                     pytest.fail(f"Main crashed on handled exception: {e}")
                 # If main.py has global try/except it passes.
