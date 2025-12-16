"""
Pre-processing module for mood prediction data analysis.

This module analyzes and scores all context signals before sending to AI,
providing visibility and control over the mood prediction process.

Signals analyzed:
- Calendar/Agenda (40% weight)
- Sleep patterns (35% weight - with VETO logic)
- Weather (15% weight)
- Music features (10% weight)
- Time of day (5% weight)
"""

import logging
from datetime import datetime, date, time
from enum import Enum
from typing import Dict, List, Tuple, Optional, Any

logger = logging.getLogger(__name__)


# ============================================================================
# CONFIGURATION - EXTERNALIZED KEYWORDS & THRESHOLDS
# ============================================================================

class MoodAnalyzerConfig:
    """Centralized configuration for mood analyzer."""
    
    # AGENDA EVENT KEYWORDS
    # Intensive Sports -> Pumped
    SPORT_INTENSE: List[str] = [
        'crossfit', 'compétition', 'competition', 'hiit', 'marathon', 'triathlon', 
        'match', 'rugby', 'football', 'basket', 'boxe'
    ]
    # Moderate Sports -> Energetic
    SPORT_MODERATE: List[str] = [
        'run', 'gym', 'yoga', 'vélo', 'velo', 'natation', 'fitness', 'sport', 'musculation',
        'train', 'training', 'entraînement', 'entrainement', 'pilates'
    ]
    
    # Creative Work -> Creative
    WORK_CREATIVE: List[str] = [
        'design', 'dev', 'développement', 'developpement', 'art', 'création', 'creation', 
        'creative', 'projet perso', 'coding', 'dessin', 'photo', 'musique',
        'machine', 'conception', 'algo', 'algorithmique', 'programmation'
    ]
    
    # High Pressure Work -> Intense/Stress
    WORK_FOCUS_HIGH: List[str] = [
        'exam', 'examen', 'partiel', 'soutenance', 'certification', 'concours', 'final', 'controle', 'contrôle'
    ]
    
    # Standard Work -> Hard Work
    WORK_FOCUS_NORMAL: List[str] = [
        'réunion', 'reunion', 'présentation', 'presentation', 
        'projet', 'étude', 'etude', 'travail', 'meeting', 'rendu', 'deadline',
        'cm', 'td', 'cours magistral', 'travaux dirigés', 'tp', 'travaux pratiques',
        'comptabilité', 'comptabilite', 'compta', 'gestion', 'finance', 'eco-gestion',
        'eco gestion', 'miage', 'business english', 'english',
        'système', 'systeme', 'strat', 'stratégie', 'strategie'
    ]
    
    # Social Active -> Confident/Energetic
    SOCIAL_ACTIVE: List[str] = [
        'fête', 'fete', 'soirée', 'soiree', 'concert', 'bar', 'club', 'anniv', 
        'anniversaire', 'party', 'festival', 'sortie', 'boîte', 'boite'
    ]
    # Social Calm -> Chill
    SOCIAL_CALM: List[str] = [
        'resto', 'restaurant', 'café', 'cafe', 'apéro', 'apero', 'dîner', 'diner', 
        'déjeuner', 'dejeuner', 'brunch', 'repas', 'bouffe'
    ]
    
    # SLEEP THRESHOLDS (hours)
    SLEEP_CRITICAL: float = 6.0      # < 6h = VETO (Automatiquement TIRED)
    SLEEP_POOR: float = 7.0          # 6-7h = Mauvais
    SLEEP_INADEQUATE: float = 8.0    # 7-8h = Insuffisant
    SLEEP_OPTIMAL_MIN: float = 8.5   # 8.5h+ = Bien
    SLEEP_OPTIMAL_MAX: float = 9.5   
    
    # WEATHER KEYWORDS
    WEATHER_RAIN: List[str] = ['orage', 'storm', 'tempête', 'tempete', 'pluie', 'rain', 'pluvieux']
    WEATHER_CLOUDY: List[str] = ['grisaille', 'gris', 'overcast', 'nuageux', 'cloudy']
    WEATHER_SUNNY: List[str] = ['soleil', 'sunny', 'ensoleillé', 'ensolleile', 'clear']
    
    # MUSIC FEATURE THRESHOLDS
    ENERGY_HIGH: float = 0.7         
    
    # TIME OF DAY THRESHOLDS (hours)
    TIME_EARLY_MORNING: int = 9    
    TIME_AFTERNOON: int = 14       
    TIME_EVENING: int = 18         
    TIME_LATE: int = 22            
    
    # SOURCE WEIGHTS (total = 100%)
    WEIGHT_AGENDA: float = 0.35      
    WEIGHT_SLEEP: float = 0.35       
    WEIGHT_WEATHER: float = 0.15 
    WEIGHT_MUSIC: float = 0.10       
    WEIGHT_TIME: float = 0.05


# ============================================================================
# ENUMS & CONSTANTS
# ============================================================================

class SignalStrength(Enum):
    """Signal strength classification for weighting mood impact."""
    VERY_WEAK = "very_weak"      # -30
    WEAK = "weak"                # -10
    NEUTRAL = "neutral"          # 0
    MODERATE = "moderate"        # +5
    STRONG = "strong"            # +10
    VERY_STRONG = "very_strong"  # +30


class MoodCategory(Enum):
    """Standardized mood categories."""
    CREATIVE = "creative"
    HARD_WORK = "hard_work"
    CONFIDENT = "confident"
    CHILL = "chill"
    ENERGETIC = "energetic"
    MELANCHOLY = "melancholy"
    INTENSE = "intense"
    PUMPED = "pumped"
    TIRED = "tired"


# ============================================================================
# SIGNAL ANALYZERS
# ============================================================================

class AgendaAnalyzer:
    """Analyzes calendar events to predict mood impact based on keywords."""

    @staticmethod
    def analyze_events(events: List[Dict[str, Any]], current_hour: int) -> Dict[str, Any]:
        """
        Analyzes calendar events emphasizing INTENSITY over DURATION.
        Includes Look-Ahead for High Stress events in the next 2 days.
        """
        today_events: List[str] = []
        upcoming_stress_events: List[str] = []
        mood_signals: List[Tuple[MoodCategory, SignalStrength]] = []
        total_pressure: float = 0.0
        
        now = datetime.now()
        today: date = now.date()
        current_time_obj: time = now.time()

        for event in events:
            summary: str = event.get('summary', '').lower()
            start: Dict[str, str] = event.get('start', {})
            
            # Parse event date/time safely
            event_date: Optional[date] = None
            event_time: Optional[time] = None

            try:
                if 'dateTime' in start:
                    # Generic ISO 8601 parsing (handles Z or offset)
                    dt_str = start['dateTime'].replace('Z', '+00:00')
                    event_dt = datetime.fromisoformat(dt_str)
                    event_date = event_dt.date()
                    event_time = event_dt.time()
                elif 'date' in start:
                    event_date = datetime.strptime(start['date'], '%Y-%m-%d').date()
                else:
                    continue
            except ValueError as e:
                logger.warning(f"Failed to parse event date: {e}")
                continue
            
            if not event_date:
                continue

            # ===== LOOK AHEAD: ANTICIPATORY STRESS (Next 2 days) =====
            days_diff = (event_date - today).days
            if 0 < days_diff <= 2:
                # Check for high stress keywords in near future
                if any(k in summary for k in MoodAnalyzerConfig.WORK_FOCUS_HIGH):
                    upcoming_stress_events.append(f"{summary} (in {days_diff}d)")
                    mood_signals.append((MoodCategory.HARD_WORK, SignalStrength.STRONG))
                    mood_signals.append((MoodCategory.INTENSE, SignalStrength.MODERATE))
                continue

            # ===== FILTER: Only TODAY's FUTURE events =====
            if event_date != today:
                continue

            # ===== PAST EVENTS (Today) - POST-EFFORT ANALYSIS =====
            if event_date == today and event_time is not None and event_time <= current_time_obj:
                 # Check for high stress past events (Exams, etc.) -> Fatigue/Crash
                 if any(k in summary for k in MoodAnalyzerConfig.WORK_FOCUS_HIGH):
                     mood_signals.append((MoodCategory.TIRED, SignalStrength.VERY_STRONG))
                     today_events.append(f"[DONE] {summary[:30]}")
                 continue
            
            # ===== ANALYZE TODAY'S FUTURE EVENT =====
            # Priority: Sport > Creative > High Focus > Social > Normal Focus > Calm Social
            
            if any(k in summary for k in MoodAnalyzerConfig.SPORT_INTENSE):
                mood_signals.append((MoodCategory.PUMPED, SignalStrength.VERY_STRONG))
                total_pressure += 2.0
            elif any(k in summary for k in MoodAnalyzerConfig.SPORT_MODERATE):
                mood_signals.append((MoodCategory.ENERGETIC, SignalStrength.STRONG))
                total_pressure += 1.0
            elif any(k in summary for k in MoodAnalyzerConfig.WORK_CREATIVE):
                mood_signals.append((MoodCategory.CREATIVE, SignalStrength.STRONG))
                total_pressure += 1.0
            elif any(k in summary for k in MoodAnalyzerConfig.WORK_FOCUS_HIGH):
                # Exam/Deadline -> High Stress
                mood_signals.append((MoodCategory.INTENSE, SignalStrength.VERY_STRONG))
                mood_signals.append((MoodCategory.HARD_WORK, SignalStrength.STRONG))
                total_pressure += 4.0
            elif any(k in summary for k in MoodAnalyzerConfig.WORK_FOCUS_NORMAL):
                # Meeting/Claass -> Mild impact
                mood_signals.append((MoodCategory.HARD_WORK, SignalStrength.MODERATE))
                total_pressure += 0.5
            elif any(k in summary for k in MoodAnalyzerConfig.SOCIAL_ACTIVE):
                mood_signals.append((MoodCategory.CONFIDENT, SignalStrength.STRONG))
                mood_signals.append((MoodCategory.ENERGETIC, SignalStrength.MODERATE))
                total_pressure += 1.0
            elif any(k in summary for k in MoodAnalyzerConfig.SOCIAL_CALM):
                mood_signals.append((MoodCategory.CHILL, SignalStrength.STRONG))
                total_pressure += 0.5
            else:
                # Default for unknown events
                mood_signals.append((MoodCategory.CONFIDENT, SignalStrength.MODERATE))
                total_pressure += 0.5

            today_events.append(summary[:30])

        return {
            'total_pressure': total_pressure,
            'event_count': len(today_events),
            'today_events': today_events[:5],
            'upcoming_stress': upcoming_stress_events,
            'mood_signals': mood_signals,
            'analysis': f"Pressure: {total_pressure:.1f} | Upcoming Stress: {len(upcoming_stress_events)}"
        }


class SleepAnalyzer:
    """Analyzes sleep patterns for mood impact."""

    @staticmethod
    def analyze_sleep(sleep_hours: float, bedtime: str, wake_time: str, 
                     execution_type: str) -> Dict[str, Any]:
        """
        Analyzes sleep metrics with VETO logic.
        < 6h = MOOD CRITICAL (Automatique TIRED)
        """
        mood_signals: List[Tuple[MoodCategory, SignalStrength]] = []
        quality = "UNKNOWN"
        veto_triggered = False

        if sleep_hours <= 0:
            mood_signals.append((MoodCategory.CHILL, SignalStrength.MODERATE))
            quality = "NO_DATA"
        
        # === VETO CONDITION ===
        elif sleep_hours < MoodAnalyzerConfig.SLEEP_CRITICAL:  # < 6h
            mood_signals.append((MoodCategory.TIRED, SignalStrength.VERY_STRONG))
            quality = "CRITICAL_VETO"
            veto_triggered = True
            
        elif sleep_hours < MoodAnalyzerConfig.SLEEP_POOR:      # 6h - 7h
            mood_signals.append((MoodCategory.TIRED, SignalStrength.STRONG))
            mood_signals.append((MoodCategory.INTENSE, SignalStrength.MODERATE))
            quality = "POOR"
            
        elif sleep_hours < MoodAnalyzerConfig.SLEEP_INADEQUATE: # 7h - 8h
            mood_signals.append((MoodCategory.TIRED, SignalStrength.MODERATE))
            quality = "INADEQUATE"
            
        elif sleep_hours >= MoodAnalyzerConfig.SLEEP_OPTIMAL_MIN: # > 8.5h
            mood_signals.append((MoodCategory.ENERGETIC, SignalStrength.STRONG))
            mood_signals.append((MoodCategory.CONFIDENT, SignalStrength.STRONG))
            quality = "OPTIMAL"
        else:
            # 8h - 8.5h: Decent
            mood_signals.append((MoodCategory.CHILL, SignalStrength.MODERATE))
            quality = "OK"

        return {
            'sleep_hours': sleep_hours,
            'quality': quality,
            'veto': veto_triggered,
            'mood_signals': mood_signals,
            'analysis': f"{sleep_hours:.1f}h - {quality}" + (" [VETO]" if veto_triggered else "")
        }


class WeatherAnalyzer:
    """Analyzes weather conditions for mood impact."""

    @staticmethod
    def analyze_weather(weather_summary: str, 
                       temperature: Optional[float] = None, 
                       execution_type: str = 'UNKNOWN') -> Dict[str, Any]:
        """Analyzes weather context. Morning Rain penalties applied."""
        mood_signals: List[Tuple[MoodCategory, SignalStrength]] = []
        weather_lower = weather_summary.lower()
        
        is_rain = any(k in weather_lower for k in MoodAnalyzerConfig.WEATHER_RAIN)
        is_cloudy = any(k in weather_lower for k in MoodAnalyzerConfig.WEATHER_CLOUDY)
        is_sunny = any(k in weather_lower for k in MoodAnalyzerConfig.WEATHER_SUNNY)

        if is_rain:
            if execution_type == 'MATIN':
                # Morning Rain -> Melancholy
                mood_signals.append((MoodCategory.MELANCHOLY, SignalStrength.VERY_STRONG))
                mood_signals.append((MoodCategory.INTENSE, SignalStrength.STRONG))
            else:
                mood_signals.append((MoodCategory.MELANCHOLY, SignalStrength.MODERATE))
                mood_signals.append((MoodCategory.CHILL, SignalStrength.MODERATE))
        elif is_cloudy:
            mood_signals.append((MoodCategory.MELANCHOLY, SignalStrength.MODERATE))
        elif is_sunny:
            mood_signals.append((MoodCategory.CONFIDENT, SignalStrength.STRONG))
            mood_signals.append((MoodCategory.PUMPED, SignalStrength.MODERATE))

        return {
            'weather': weather_summary,
            'temperature': temperature,
            'mood_signals': mood_signals,
            'analysis': f"{weather_summary}"
        }


class MusicAnalyzer:
    """Analyzes music features for mood impact."""

    @staticmethod
    def analyze_music(valence: float, energy: float, tempo: int, 
                     danceability: float) -> Dict[str, Any]:
        """
        Analyzes Spotify audio features.
        NOTE: Music is treated as a positive/neutral influence only.
        """
        mood_signals: List[Tuple[MoodCategory, SignalStrength]] = []
        vibe = "FLOW"

        # High Energy -> Pumped
        if energy > MoodAnalyzerConfig.ENERGY_HIGH:
            mood_signals.append((MoodCategory.PUMPED, SignalStrength.STRONG))
            mood_signals.append((MoodCategory.ENERGETIC, SignalStrength.STRONG))
            vibe = "BOOST"
        elif energy > 0.5:
            mood_signals.append((MoodCategory.ENERGETIC, SignalStrength.MODERATE))
            vibe = "VIBE"
        else:
            mood_signals.append((MoodCategory.CHILL, SignalStrength.STRONG))
            vibe = "CHILL"

        if valence > 0.6:
            mood_signals.append((MoodCategory.CONFIDENT, SignalStrength.MODERATE))
        
        if danceability > 0.7:
             mood_signals.append((MoodCategory.CREATIVE, SignalStrength.MODERATE))

        return {
            'valence': valence,
            'energy': energy,
            'tempo': tempo,
            'danceability': danceability,
            'vibe': vibe,
            'mood_signals': mood_signals,
            'analysis': f"V:{valence:.2f} E:{energy:.2f} - {vibe}"
        }


class TimeAnalyzer:
    """Analyzes week-day and time-of-day execution context."""
    
    @staticmethod
    def analyze_time(hour: int, weekday: int, execution_type: str) -> Dict[str, Any]:
        """
        Analyzes time.
        Monday = Energy Boost.
        Friday = Fatigue/Chill.
        """
        mood_signals: List[Tuple[MoodCategory, SignalStrength]] = []
        days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
        day_name = days[weekday] if 0 <= weekday < 7 else "Unknown"
        
        # Weekly Rhythm
        if weekday == 0:  # Monday -> Requinqué
            mood_signals.append((MoodCategory.ENERGETIC, SignalStrength.STRONG))
            mood_signals.append((MoodCategory.PUMPED, SignalStrength.MODERATE))
        
        elif weekday == 4:  # Friday -> Tired/Chill
            mood_signals.append((MoodCategory.TIRED, SignalStrength.MODERATE))
            mood_signals.append((MoodCategory.CHILL, SignalStrength.STRONG))
            
        elif weekday in [5, 6]:  # Weekend
            mood_signals.append((MoodCategory.CHILL, SignalStrength.STRONG))

        # Time of Day logic can be extended here if needed
        # Currently mainly handled by execution_type passed to other analyzers

        return {
            'hour': hour,
            'day': day_name,
            'mood_signals': mood_signals,
            'analysis': f"{day_name} {hour:02d}h"
        }


# ============================================================================
# MAIN ANALYZER
# ============================================================================

class MoodDataAnalyzer:
    """Orchestrates analysis of all data sources to produce a cohesive mood report."""

    def __init__(self):
        self.agenda_analyzer = AgendaAnalyzer()
        self.sleep_analyzer = SleepAnalyzer()
        self.weather_analyzer = WeatherAnalyzer()
        self.music_analyzer = MusicAnalyzer()
        self.time_analyzer = TimeAnalyzer()

    def analyze(self, calendar_events: List[Dict[str, Any]], sleep_hours: float, 
               bedtime: str, wake_time: str, weather: str, temperature: Optional[float],
               valence: float, energy: float, tempo: int, danceability: float,
               current_time: datetime, execution_type: str) -> Dict[str, Any]:
        """
        Performs holistic mood analysis.
        
        Returns:
            Dict containing detailed analysis, signals, and final scores.
        """
        # Run sub-analyzers
        agenda_analysis = self.agenda_analyzer.analyze_events(calendar_events, current_time.hour)
        sleep_analysis = self.sleep_analyzer.analyze_sleep(sleep_hours, bedtime, wake_time, execution_type)
        weather_analysis = self.weather_analyzer.analyze_weather(weather, temperature, execution_type)
        music_analysis = self.music_analyzer.analyze_music(valence, energy, tempo, danceability)
        time_analysis = self.time_analyzer.analyze_time(current_time.hour, current_time.weekday(), execution_type)

        # Merge signals with sources
        all_signals_with_source: List[Tuple[MoodCategory, SignalStrength, str]] = []
        
        source_map = [
            (agenda_analysis, 'agenda'),
            (sleep_analysis, 'sleep'),
            (weather_analysis, 'weather'),
            (music_analysis, 'music'),
            (time_analysis, 'time')
        ]

        for analysis, source_name in source_map:
            for mood, strength in analysis['mood_signals']:
                all_signals_with_source.append((mood, strength, source_name))

        # Define Weights
        source_weights = {
            'agenda': MoodAnalyzerConfig.WEIGHT_AGENDA,
            'sleep': MoodAnalyzerConfig.WEIGHT_SLEEP,
            'weather': MoodAnalyzerConfig.WEIGHT_WEATHER,
            'music': MoodAnalyzerConfig.WEIGHT_MUSIC,
            'time': MoodAnalyzerConfig.WEIGHT_TIME
        }

        # Calculate Scores
        mood_scores = self._score_moods(
            all_signals_with_source, 
            source_weights, 
            veto_sleep=sleep_analysis.get('veto', False)
        )

        return {
            'timestamp': current_time.isoformat(),
            'execution_type': execution_type,
            'source_weights': source_weights,
            'agenda': agenda_analysis,
            'sleep': sleep_analysis,
            'weather': weather_analysis,
            'music': music_analysis,
            'time': time_analysis,
            'mood_scores': mood_scores,
            'top_moods': sorted(mood_scores.items(), key=lambda x: x[1], reverse=True)[:3],
            'summary': self._generate_summary(
                agenda_analysis, sleep_analysis, weather_analysis, 
                music_analysis, time_analysis, mood_scores
            )
        }

    @staticmethod
    def _score_moods(signals: List[Tuple[MoodCategory, SignalStrength, str]], 
                    source_weights: Dict[str, float],
                    veto_sleep: bool = False) -> Dict[str, float]:
        """
        Calculates final mood scores based on weighted signals.
        Applies Sleep VETO if triggered (forces TIRED to top).
        """
        mood_scores = {mood.value: 0.0 for mood in MoodCategory}
        
        strength_weights = {
            SignalStrength.VERY_WEAK: -30.0,
            SignalStrength.WEAK: -10.0,
            SignalStrength.NEUTRAL: 0.0,
            SignalStrength.MODERATE: 5.0,
            SignalStrength.STRONG: 10.0,
            SignalStrength.VERY_STRONG: 30.0
        }

        for mood, strength, source in signals:
            base_score = strength_weights[strength]
            weight = source_weights.get(source, 1.0)
            mood_scores[mood.value] += (base_score * weight)

        # Normalize negative scores to baseline 0
        min_score = min(mood_scores.values()) if mood_scores else 0.0
        if min_score < 0:
            for mood_key in mood_scores:
                mood_scores[mood_key] -= min_score
        
        # Apply VETO Override
        if veto_sleep:
            max_current = max(mood_scores.values()) if mood_scores else 100.0
            # Ensure TIRED dominates by 50% margin
            mood_scores['tired'] = max_current * 1.5

        return mood_scores

    @staticmethod
    def _generate_summary(agenda: Dict, sleep: Dict, weather: Dict, 
                         music: Dict, time: Dict, scores: Dict[str, float]) -> str:
        """Formatted summary string."""
        top_mood = max(scores.items(), key=lambda x: x[1])[0] if scores else "UNKNOWN"
        
        return f"""
MOOD ANALYSIS SUMMARY:
=====================
[AGENDA] {agenda.get('analysis', 'N/A')}
[SLEEP]  {sleep.get('analysis', 'N/A')}
[WEATHER] {weather.get('analysis', 'N/A')}
[MUSIC]  {music.get('analysis', 'N/A')}
[TIME]   {time.get('analysis', 'N/A')}

TOP MOOD: {top_mood.upper()}
"""

def log_analysis(analysis: Dict[str, Any], _logger: logging.Logger) -> None:
    """Helper to log analysis summary."""
    _logger.info("[MOOD_ANALYZER] Analysis complete")
    if analysis.get('top_moods'):
        _logger.info(f"[MOOD_ANALYZER] Top mood: {analysis['top_moods'][0][0]}")
    _logger.info(f"[MOOD_ANALYZER] Summary:\n{analysis.get('summary', '')}")
