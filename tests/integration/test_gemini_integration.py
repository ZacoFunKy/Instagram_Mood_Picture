
import pytest
from unittest.mock import MagicMock, patch
from datetime import datetime

from src.adapters.clients.gemini import (
    construct_prompt, predict_mood, PromptBuilder, 
    TemporalContext, SleepContext, ExecutionType
)

class TestGeminiIntegration:
    """Test suite for Gemini Client and Prompt Engineering."""

    # ========================================================================
    # 1. PROMPT ENGINEERING
    # ========================================================================

    def test_prompt_content_morning_vs_afternoon(self, sample_sleep_context):
        """Verify distinct prompts for Morning (Capital) vs Afternoon (Debt)."""
        dt_morning = datetime(2025, 1, 1, 3, 0)
        dt_afternoon = datetime(2025, 1, 1, 14, 0)

        # Morning Prompt
        prompt_am = construct_prompt(
            "History", "Music", "Agenda", "Weather", 
            sample_sleep_context, execution_time=dt_morning
        )
        assert "MATIN - DÉPART" in prompt_am
        assert "CAPITAL SOMMEIL" in prompt_am

        # Afternoon Prompt
        prompt_pm = construct_prompt(
            "History", "Music", "Agenda", "Weather", 
            sample_sleep_context, execution_time=dt_afternoon
        )
        assert "APRÈS-MIDI - BILAN" in prompt_pm
        assert "DETTE PAYÉE MAINTENANT" in prompt_pm or "LA SANCTION" in prompt_pm

    def test_pre_analysis_injection(self):
        """Verify Algorithmic Baseline is injected into prompt."""
        mock_analysis = {
            'top_moods': [('tired', 20.0)],
            'source_weights': {'sleep': 0.35}
        }
        
        prompt = construct_prompt(
            "History", "Music", "Agenda", "Weather", {}, 
            execution_time=datetime(2025, 1, 1, 9, 0),
            preprocessor_analysis=mock_analysis
        )
        
        assert "ANCRE ALGORITHMIQUE" in prompt
        assert "TOP MOOD CALCULÉ : TIRED" in prompt
        assert "Poids utilisés" in prompt

    # ========================================================================
    # 2. PREDICT MOOD (ORCHESTRATION)
    # ========================================================================

    def test_predict_mood_success(self, mock_genai):
        """Test successful prediction flow."""
        # Setup Mock response
        model_instance = mock_genai.GenerativeModel.return_value
        model_instance.generate_content.return_value.text = "confident"
        
        mood = predict_mood(
            "History", "Music", "Agenda", "Weather",
            sleep_info={"sleep_hours": 8}
        )
        
        assert mood == "confident"
        mock_genai.configure.assert_called()

    def test_predict_mood_api_failure_resilience(self, mock_genai):
        """Test fallback to 'chill' when API fails repeatedly."""
        # Setup Mock to raise Exception
        model_instance = mock_genai.GenerativeModel.return_value
        model_instance.generate_content.side_effect = Exception("Quota Exceeded")
        
        mood = predict_mood(
            "History", "Music", "Agenda", 
            sleep_info={"sleep_hours": 8}
        )
        
        # Should fallback to 'chill' (or default logic)
        # Based on current implementation, it catches exception and returns "chill"
        assert mood == "chill"

    def test_predict_mood_dry_run(self):
        """Test dry run returns prompt without calling API."""
        res = predict_mood("Hist", "Mus", "Cal", dry_run=True)
        
        assert isinstance(res, dict)
        assert "mood" in res
        assert "prompt" in res
        assert res["mood"] == "dry_run"
