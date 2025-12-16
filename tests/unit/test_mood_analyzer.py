
import pytest
from datetime import datetime
from unittest.mock import MagicMock, patch

from src.core.analyzer import (
    MoodDataAnalyzer, MoodCategory, SignalStrength, 
    SleepAnalyzer, AgendaAnalyzer, TimeAnalyzer
)

class TestMoodAnalyzer:
    """Test suite for MoodDataAnalyzer logic."""

    def setup_method(self):
        self.analyzer = MoodDataAnalyzer()

    # ========================================================================
    # 1. SLEEP VETO LOGIC
    # ========================================================================

    def test_sleep_veto_activation(self):
        """Test that sleep < 6h triggers Veto."""
        result = SleepAnalyzer.analyze_sleep(4.0, "02:00", "06:00", "MATIN")
        
        assert result['veto'] is True
        assert result['quality'] == "CRITICAL_VETO"
        assert (MoodCategory.TIRED, SignalStrength.VERY_STRONG) in result['mood_signals']

    def test_sleep_veto_overrides_everything(self):
        """Test that Veto crushes positive signals in final scoring."""
        # Setup: Veto Sleep (TIRED++) vs Intense Sport (PUMPED++)
        signals = [
            (MoodCategory.TIRED, SignalStrength.VERY_STRONG, 'sleep'),
            (MoodCategory.PUMPED, SignalStrength.VERY_STRONG, 'agenda')
        ]
        weights = {'sleep': 0.35, 'agenda': 0.35}

        scores = self.analyzer._score_moods(signals, weights, veto_sleep=True)
        
        # TIRED should be dominant
        assert scores['tired'] > scores['pumped']
        
    def test_no_veto_normal_sleep(self):
        """Test normal sleep (7.5h) does not trigger veto."""
        result = SleepAnalyzer.analyze_sleep(7.5, "23:00", "06:30", "MATIN")
        assert result['veto'] is False

    # ========================================================================
    # 2. AGENDA PRESSURE
    # ========================================================================

    def test_agenda_exam_pressure(self):
        """Test that 'Examen' triggers High Pressure/Intense."""
        event = {'summary': 'Examen Final', 'start': {'dateTime': '2025-01-01T10:00'}}
        
        with patch('src.core.analyzer.datetime') as mock_dt:
            mock_dt.now.return_value = datetime(2025, 1, 1, 9, 0) # 1h before
            mock_dt.fromisoformat = datetime.fromisoformat # Keep original
            
            analysis = AgendaAnalyzer.analyze_events([event], 9)
            
            # Check for INTENSE due to Exam
            signals = [s[0] for s in analysis['mood_signals']]
            assert MoodCategory.INTENSE in signals
            assert analysis['total_pressure'] >= 4.0

    def test_agenda_routine_meeting(self):
        """Test that 'Réunion' has low pressure."""
        event = {'summary': 'Réunion équipe', 'start': {'dateTime': '2025-01-01T10:00'}}
        
        with patch('src.core.analyzer.datetime') as mock_dt:
            mock_dt.now.return_value = datetime(2025, 1, 1, 9, 0)
            mock_dt.fromisoformat = datetime.fromisoformat
            
            analysis = AgendaAnalyzer.analyze_events([event], 9)
            
            assert analysis['total_pressure'] < 2.0

    # ========================================================================
    # 3. WEEKLY RHYTHM
    # ========================================================================

    def test_monday_boost(self):
        """Test Monday gives energy boost."""
        # 0 = Monday
        res = TimeAnalyzer.analyze_time(hour=9, weekday=0, execution_type="MATIN")
        signals = [s[0] for s in res['mood_signals']]
        assert MoodCategory.ENERGETIC in signals

    def test_friday_fatigue(self):
        """Test Friday gives fatigue malus."""
        # 4 = Friday
        res = TimeAnalyzer.analyze_time(hour=14, weekday=4, execution_type="APRES-MIDI")
        signals = [s[0] for s in res['mood_signals']]
        assert MoodCategory.TIRED in signals

    # ========================================================================
    # 4. SCORING WEIGHTS
    # ========================================================================

    def test_full_analysis_integration(self):
        """Test a full analysis run produces a coherent report."""
        # Execute analyze
        report = self.analyzer.analyze(
            calendar_events=[],
            sleep_hours=8.0,
            bedtime="23:00", wake_time="07:00",
            weather="Ensoleillé", temperature=20,
            valence=0.8, energy=0.8, tempo=120, danceability=0.8,
            current_time=datetime(2025, 1, 1, 10, 0),
            execution_type="MATIN"
        )
        
        assert 'mood_scores' in report
        assert 'top_moods' in report
        assert 'summary' in report
        assert len(report['top_moods']) > 0
        
        # With high energy music + sun + good sleep -> Should be Energetic/Pumped
        top_mood = report['top_moods'][0][0]
        assert top_mood in ['energetic', 'pumped', 'confident']
