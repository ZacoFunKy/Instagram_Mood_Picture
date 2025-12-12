"""
Pre-processing module for mood prediction data analysis.

This module analyzes and scores all context signals before sending to AI,
providing visibility and control over the mood prediction process.

Signals analyzed:
- Calendar/Agenda (40% weight)
- Sleep patterns (15-30% weight)
- Weather (15-20% weight)
- Music features (10% weight)
- Time of day (5% weight)
- Weekly patterns (variable boost)
"""

import logging
from datetime import datetime
from typing import Dict, List, Tuple, Optional
from enum import Enum

logger = logging.getLogger(__name__)


# ============================================================================
# CONFIGURATION - EXTERNALIZED KEYWORDS & THRESHOLDS
# ============================================================================

class MoodAnalyzerConfig:
    """Centralized configuration for mood analyzer."""
    
    # AGENDA EVENT KEYWORDS
    SPORT_INTENSE = ['crossfit', 'compétition', 'competition', 'hiit', 'marathon', 'triathlon', 
                     'match', 'rugby', 'football', 'basket']
    SPORT_MODERATE = ['run', 'gym', 'yoga', 'vélo', 'velo', 'natation', 'fitness', 'sport', 'musculation',
                      'train', 'training', 'entraînement', 'entrainement']
    
    # École de commerce/gestion - Cours créatifs/techniques
    WORK_CREATIVE = ['design', 'dev', 'développement', 'developpement', 'art', 'création', 'creation', 
                     'creative', 'projet perso', 'coding', 'dessin', 'photo', 'musique',
                     'machine', 'conception', 'algo', 'algorithmique', 'programmation']
    
    # École de commerce/gestion - Cours intensifs
    WORK_FOCUS = ['exam', 'examen', 'partiel', 'réunion', 'reunion', 'présentation', 'presentation', 
                  'projet', 'étude', 'etude', 'travail', 'meeting', 'rendu', 'deadline', 'soutenance',
                  'cm', 'td', 'cours magistral', 'travaux dirigés', 'tp', 'travaux pratiques',
                  'comptabilité', 'comptabilite', 'compta', 'gestion', 'finance', 'eco-gestion',
                  'eco gestion', 'miage', 'certification', 'business english', 'english',
                  'système', 'systeme', 'strat', 'stratégie', 'strategie']
    
    SOCIAL_ACTIVE = ['fête', 'fete', 'soirée', 'soiree', 'concert', 'bar', 'club', 'anniv', 
                     'anniversaire', 'party', 'festival', 'sortie', 'boîte', 'boite']
    SOCIAL_CALM = ['resto', 'restaurant', 'café', 'cafe', 'apéro', 'apero', 'dîner', 'diner', 
                   'déjeuner', 'dejeuner', 'brunch', 'repas', 'bouffe']
    
    # SLEEP THRESHOLDS (hours)
    SLEEP_CRITICAL = 5.0      # < 5h = très mauvais
    SLEEP_POOR = 6.0          # 5-6h = mauvais
    SLEEP_INADEQUATE = 7.0    # 6-7h = insuffisant
    SLEEP_OPTIMAL_MAX = 9.0   # 7-9h = optimal
    SLEEP_LONG = 9.0          # >= 9h = long repos
    
    # WEATHER KEYWORDS
    WEATHER_STORM = ['orage', 'storm', 'tempête', 'tempete']
    WEATHER_RAIN = ['pluie', 'rain', 'pluvieux']
    WEATHER_OVERCAST = ['grisaille', 'gris', 'overcast', 'nuageux', 'cloudy']
    WEATHER_SUNNY = ['soleil', 'sunny', 'ensoleillé', 'ensolleile', 'clear']
    
    # TEMPERATURE THRESHOLDS (Celsius)
    TEMP_COLD = 5.0           # < 5°C = froid
    TEMP_HOT = 25.0           # > 25°C = chaud
    
    # MUSIC FEATURE THRESHOLDS
    ENERGY_HIGH = 0.7         # > 0.7 = high energy
    TEMPO_EXPLOSIVE = 140     # > 140 BPM = explosive
    TEMPO_ENERGETIC = 120     # > 120 BPM = energetic
    TEMPO_SLOW = 90           # < 90 BPM = slow/chill
    
    VALENCE_HIGH = 0.7        # > 0.7 = très positif
    VALENCE_LOW = 0.3         # < 0.3 = négatif (mélancolique)
    VALENCE_MEDIUM_LOW = 0.35 # < 0.35 = légèrement négatif
    
    DANCEABILITY_HIGH = 0.7   # > 0.7 = dansant

    # TIME OF DAY THRESHOLDS (hours)
    TIME_EARLY_MORNING = 9    # < 9h = tôt le matin
    TIME_AFTERNOON = 14       # < 14h = matin/midi
    TIME_EVENING = 18         # < 18h = après-midi
    TIME_LATE = 22            # >= 22h = tard le soir
    
    # AGENDA OVERLOAD THRESHOLD (hours)
    AGENDA_OVERLOAD = 6.0     # > 6h d'événements = surcharge
    AGENDA_EXTREME = 9.0      # > 9h = burnout risk
    
    # SOURCE WEIGHTS (total = 100%)
    WEIGHT_AGENDA = 0.40      # 40%
    WEIGHT_SLEEP_MORNING = 0.30   # 30% (matin)
    WEIGHT_SLEEP_AFTERNOON = 0.15 # 15% (après-midi)
    WEIGHT_WEATHER_MORNING = 0.15 # 15% (matin)
    WEIGHT_WEATHER_AFTERNOON = 0.20  # 20% (après-midi)
    WEIGHT_MUSIC = 0.10       # 10%
    WEIGHT_TIME = 0.05        # 5%


# ============================================================================
# ENUMS & CONSTANTS
# ============================================================================

class SignalStrength(Enum):
    """Signal strength classification."""
    VERY_WEAK = "very_weak"      # -30 to -10
    WEAK = "weak"                # -10 to 0
    NEUTRAL = "neutral"          # 0
    STRONG = "strong"            # 0 to +10
    VERY_STRONG = "very_strong"  # +10 to +30


class MoodCategory(Enum):
    """Mood categories for analysis."""
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
    """Analyzes calendar events to predict mood impact."""

    @staticmethod
    def analyze_events(events: List[Dict], current_hour: int) -> Dict:
        """
        Analyzes calendar events for TODAY ONLY, and ONLY future events.
        
        CRITICAL: Only future events (not yet happened) affect current mood.
        Past events already happened - they don't shape current vibe.
        
        This gives accurate "what's next today" analysis vs anticipatory stress.

        Args:
            events: List of calendar event dicts with 'summary' and 'start'
            current_hour: Current hour (0-23)

        Returns:
            Dict with:
            - total_duration: Total hours of FUTURE events TODAY
            - event_count: Number of FUTURE events TODAY
            - today_events: Future events remaining today
            - upcoming_events: Events in next 3 days (for context only)
            - mood_signals: List of (mood, strength) tuples
            - analysis: Human-readable summary
        """
        today_events = []
        upcoming_events = []
        mood_signals = []
        total_duration = 0
        
        # Get today's date and current time for filtering
        now = datetime.now()
        today = now.date()
        current_time = now.time()

        for event in events:
            summary = event.get('summary', '').lower()
            start = event.get('start', {})
            
            # Parse event date and time
            try:
                if isinstance(start, dict) and 'dateTime' in start:
                    event_dt = datetime.fromisoformat(start['dateTime'].replace('Z', '+00:00'))
                    event_date = event_dt.date()
                    event_time = event_dt.time()
                elif isinstance(start, dict) and 'date' in start:
                    event_date = datetime.strptime(start['date'], '%Y-%m-%d').date()
                    event_time = None  # All-day events are considered "future" if today
                else:
                    event_date = None
                    event_time = None
            except:
                event_date = None
                event_time = None
            
            # ===== FILTER: Only TODAY's FUTURE events =====
            if event_date is None:
                continue  # Skip events without date
            
            if event_date > today:
                # Store for reference but don't analyze
                upcoming_events.append(summary[:30])
                continue
            
            if event_date < today:
                # Past events: skip
                continue
            
            # It's today - check if it's in the future
            if event_time is not None and event_time <= current_time:
                # Event already happened today: skip it
                continue
            
            # ===== ANALYZE THIS FUTURE EVENT =====
            # Classify event using config keywords
            if any(keyword in summary for keyword in MoodAnalyzerConfig.SPORT_INTENSE):
                mood_signals.append((MoodCategory.PUMPED, SignalStrength.VERY_STRONG))
                total_duration += 1.5
            elif any(keyword in summary for keyword in MoodAnalyzerConfig.SPORT_MODERATE):
                mood_signals.append((MoodCategory.ENERGETIC, SignalStrength.STRONG))
                total_duration += 1
            elif any(keyword in summary for keyword in MoodAnalyzerConfig.WORK_CREATIVE):
                mood_signals.append((MoodCategory.CREATIVE, SignalStrength.STRONG))
                total_duration += 2
            elif any(keyword in summary for keyword in MoodAnalyzerConfig.WORK_FOCUS):
                # Check for high stress keywords specifically
                if any(s in summary for s in ['exam', 'partiel', 'deadline', 'soutenance', 'rendu']):
                    mood_signals.append((MoodCategory.INTENSE, SignalStrength.VERY_STRONG))
                    mood_signals.append((MoodCategory.HARD_WORK, SignalStrength.STRONG))
                else:
                    mood_signals.append((MoodCategory.HARD_WORK, SignalStrength.STRONG))
                total_duration += 2
            elif any(keyword in summary for keyword in MoodAnalyzerConfig.SOCIAL_ACTIVE):
                mood_signals.append((MoodCategory.CONFIDENT, SignalStrength.STRONG))
                total_duration += 3
            elif any(keyword in summary for keyword in MoodAnalyzerConfig.SOCIAL_CALM):
                mood_signals.append((MoodCategory.CONFIDENT, SignalStrength.WEAK))
                total_duration += 2
            else:
                # Catch-all: événement générique non catégorisé
                mood_signals.append((MoodCategory.CONFIDENT, SignalStrength.WEAK))
                total_duration += 1

            today_events.append(summary[:30])

        # Surcharge check using config (only for TODAY's FUTURE events)
        if total_duration > MoodAnalyzerConfig.AGENDA_EXTREME:
            mood_signals.append((MoodCategory.INTENSE, SignalStrength.VERY_STRONG))
            mood_signals.append((MoodCategory.TIRED, SignalStrength.STRONG))
            surcharge = True
        elif total_duration > MoodAnalyzerConfig.AGENDA_OVERLOAD:
            mood_signals.append((MoodCategory.INTENSE, SignalStrength.STRONG))
            mood_signals.append((MoodCategory.TIRED, SignalStrength.WEAK))
            surcharge = True
        else:
            surcharge = False

        return {
            'total_duration': total_duration,
            'event_count': len(today_events),
            'today_events': today_events[:5],
            'upcoming_events': upcoming_events[:5],
            'surcharge': surcharge,
            'mood_signals': mood_signals,
            'analysis': f"Today remaining: {total_duration:.1f}h - {'SURCHARGE' if surcharge else 'Normal'}" +
                       (f" | Upcoming: {len(upcoming_events)} events" if upcoming_events else " | No events left today")
        }


class SleepAnalyzer:
    """Analyzes sleep patterns for mood impact."""

    @staticmethod
    def analyze_sleep(sleep_hours: float, bedtime: str, wake_time: str, 
                     execution_type: str) -> Dict:
        """Analyzes sleep metrics and returns mood signals."""
        mood_signals: List[Tuple[MoodCategory, SignalStrength]] = []
        quality = "UNKNOWN"

        # Unknown/unmeasured sleep: don't punish heavily
        if sleep_hours <= 0:
            mood_signals.append((MoodCategory.CHILL, SignalStrength.WEAK))
            quality = "UNKNOWN"
        elif sleep_hours < MoodAnalyzerConfig.SLEEP_CRITICAL:
            mood_signals.append((MoodCategory.TIRED, SignalStrength.VERY_STRONG))
            mood_signals.append((MoodCategory.INTENSE, SignalStrength.WEAK))  # irritability/tension
            quality = "CRITICAL"
        elif sleep_hours < MoodAnalyzerConfig.SLEEP_POOR:
            mood_signals.append((MoodCategory.TIRED, SignalStrength.STRONG))
            quality = "POOR"
        elif sleep_hours < MoodAnalyzerConfig.SLEEP_INADEQUATE:
            mood_signals.append((MoodCategory.TIRED, SignalStrength.WEAK))
            quality = "INADEQUATE"
        elif sleep_hours <= MoodAnalyzerConfig.SLEEP_OPTIMAL_MAX:
            quality = "OPTIMAL"
        else:
            # Sleep > 9h = long rest/recovery
            mood_signals.append((MoodCategory.CHILL, SignalStrength.STRONG))
            quality = "LONG_REST"

        return {
            'sleep_hours': sleep_hours,
            'quality': quality,
            'mood_signals': mood_signals,
            'analysis': f"{sleep_hours:.1f}h sleep - {quality}"
        }


class WeatherAnalyzer:
    """Analyzes weather conditions for mood impact."""

    @staticmethod
    def analyze_weather(weather_summary: str, temperature: Optional[float] = None) -> Dict:
        """
        Analyzes weather conditions.

        Args:
            weather_summary: Weather description
            temperature: Optional temperature in Celsius

        Returns:
            Dict with mood signals and analysis
        """
        mood_signals = []
        weather_lower = weather_summary.lower()

        if any(keyword in weather_lower for keyword in MoodAnalyzerConfig.WEATHER_STORM):
            mood_signals.append((MoodCategory.INTENSE, SignalStrength.STRONG))
        elif any(keyword in weather_lower for keyword in MoodAnalyzerConfig.WEATHER_RAIN):
            mood_signals.append((MoodCategory.MELANCHOLY, SignalStrength.WEAK))
        elif any(keyword in weather_lower for keyword in MoodAnalyzerConfig.WEATHER_OVERCAST):
            mood_signals.append((MoodCategory.MELANCHOLY, SignalStrength.WEAK))
        elif any(keyword in weather_lower for keyword in MoodAnalyzerConfig.WEATHER_SUNNY):
            mood_signals.append((MoodCategory.CONFIDENT, SignalStrength.STRONG))
            mood_signals.append((MoodCategory.PUMPED, SignalStrength.WEAK))

        if temperature is not None:
            if temperature < MoodAnalyzerConfig.TEMP_COLD:
                mood_signals.append((MoodCategory.TIRED, SignalStrength.WEAK))
                mood_signals.append((MoodCategory.CHILL, SignalStrength.WEAK))
            elif temperature > MoodAnalyzerConfig.TEMP_HOT:
                mood_signals.append((MoodCategory.ENERGETIC, SignalStrength.WEAK))
                mood_signals.append((MoodCategory.PUMPED, SignalStrength.WEAK))

        return {
            'weather': weather_summary,
            'temperature': temperature,
            'mood_signals': mood_signals,
            'analysis': f"{weather_summary}" + (f" ({temperature}°C)" if temperature else "")
        }


class MusicAnalyzer:
    """Analyzes music features for mood impact."""

    @staticmethod
    def analyze_music(valence: float, energy: float, tempo: int, 
                     danceability: float) -> Dict:
        """Analyzes Spotify audio features and returns mood signals."""
        mood_signals: List[Tuple[MoodCategory, SignalStrength]] = []
        vibe = "BALANCED"

        # High energy + fast tempo
        if energy > MoodAnalyzerConfig.ENERGY_HIGH and tempo > MoodAnalyzerConfig.TEMPO_EXPLOSIVE:
            mood_signals.append((MoodCategory.PUMPED, SignalStrength.STRONG))
            vibe = "EXPLOSIVE"
        elif energy > MoodAnalyzerConfig.ENERGY_HIGH and tempo > MoodAnalyzerConfig.TEMPO_ENERGETIC:
            mood_signals.append((MoodCategory.ENERGETIC, SignalStrength.STRONG))
            vibe = "ENERGETIC"

        # Tension/aggressive: high energy + low valence
        if energy > 0.8 and valence < 0.4:
            mood_signals.append((MoodCategory.INTENSE, SignalStrength.STRONG))
            vibe = "AGGRESSIVE"

        # Danceability: party/groove vs relaxed groove
        if danceability > MoodAnalyzerConfig.DANCEABILITY_HIGH:
            if energy > 0.6:
                mood_signals.append((MoodCategory.PUMPED, SignalStrength.WEAK))
                mood_signals.append((MoodCategory.CONFIDENT, SignalStrength.WEAK))
            else:
                mood_signals.append((MoodCategory.CHILL, SignalStrength.WEAK))

        # Valence: positivity/negativity
        if valence > MoodAnalyzerConfig.VALENCE_HIGH:
            mood_signals.append((MoodCategory.CONFIDENT, SignalStrength.WEAK))
        elif valence < MoodAnalyzerConfig.VALENCE_LOW and energy < 0.4:
            mood_signals.append((MoodCategory.MELANCHOLY, SignalStrength.STRONG))
            vibe = "MELANCHOLIC"
        elif valence < MoodAnalyzerConfig.VALENCE_MEDIUM_LOW:
            mood_signals.append((MoodCategory.MELANCHOLY, SignalStrength.WEAK))

        # Neutral focus zone
        if 0.4 <= valence <= 0.6 and 0.5 <= energy <= 0.65:
            mood_signals.append((MoodCategory.HARD_WORK, SignalStrength.WEAK))
            if vibe == "BALANCED":
                vibe = "FOCUS"

        # Tempo contribution
        if tempo > MoodAnalyzerConfig.TEMPO_EXPLOSIVE:
            mood_signals.append((MoodCategory.INTENSE, SignalStrength.WEAK))
        elif tempo > MoodAnalyzerConfig.TEMPO_ENERGETIC:
            mood_signals.append((MoodCategory.ENERGETIC, SignalStrength.WEAK))
        elif tempo < MoodAnalyzerConfig.TEMPO_SLOW:
            mood_signals.append((MoodCategory.CHILL, SignalStrength.WEAK))

        return {
            'valence': valence,
            'energy': energy,
            'tempo': tempo,
            'danceability': danceability,
            'vibe': vibe,
            'mood_signals': mood_signals,
            'analysis': f"V:{valence:.2f} E:{energy:.2f} T:{tempo}BPM - {vibe}"
        }


class TimeAnalyzer:
    """Analyzes time-based mood patterns."""

    @staticmethod
    def analyze_time(hour: int, weekday: int, execution_type: str) -> Dict:
        """Analyzes time of day and weekday patterns and returns mood signals."""
        mood_signals: List[Tuple[MoodCategory, SignalStrength]] = []
        day_name = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][weekday]
        time_period = "UNKNOWN"

        # Day of week analysis
        if weekday == 0:  # Monday
            mood_signals.append((MoodCategory.HARD_WORK, SignalStrength.WEAK))
            if hour < 12:
                mood_signals.append((MoodCategory.TIRED, SignalStrength.WEAK))
        elif weekday == 4:  # Friday
            mood_signals.append((MoodCategory.CONFIDENT, SignalStrength.STRONG))
            if hour >= 14:
                mood_signals.append((MoodCategory.PUMPED, SignalStrength.WEAK))
        elif weekday in [5, 6]:  # Weekend
            mood_signals.append((MoodCategory.CHILL, SignalStrength.STRONG))

        # Time of day analysis
        if hour < MoodAnalyzerConfig.TIME_EARLY_MORNING:
            time_period = "EARLY_MORNING"
        elif hour < MoodAnalyzerConfig.TIME_AFTERNOON:
            time_period = "MORNING_AFTERNOON"
        elif hour < MoodAnalyzerConfig.TIME_EVENING:
            time_period = "AFTERNOON"
        else:
            time_period = "EVENING"
            if hour >= MoodAnalyzerConfig.TIME_LATE:
                # Late evening (>22h): CHILL/relaxation > fatigue
                # If no events left, it's just wind-down time
                mood_signals.append((MoodCategory.CHILL, SignalStrength.VERY_STRONG))

        return {
            'hour': hour,
            'day': day_name,
            'weekday': weekday,
            'time_period': time_period,
            'mood_signals': mood_signals,
            'analysis': f"{day_name} {hour:02d}h - {time_period}"
        }


# ============================================================================
# MAIN ANALYZER
# ============================================================================

class MoodDataAnalyzer:
    """Main analyzer that combines all signals and scores moods."""

    def __init__(self):
        self.agenda_analyzer = AgendaAnalyzer()
        self.sleep_analyzer = SleepAnalyzer()
        self.weather_analyzer = WeatherAnalyzer()
        self.music_analyzer = MusicAnalyzer()
        self.time_analyzer = TimeAnalyzer()

    def analyze(self, calendar_events: List[Dict], sleep_hours: float, 
               bedtime: str, wake_time: str, weather: str, temperature: Optional[float],
               valence: float, energy: float, tempo: int, danceability: float,
               current_time: datetime, execution_type: str) -> Dict:
        """
        Complete analysis of all mood signals.

        Args:
            calendar_events: List of calendar events
            sleep_hours: Total sleep hours
            bedtime: Bedtime string
            wake_time: Wake time string
            weather: Weather description
            temperature: Temperature in Celsius
            valence: Average music valence (0-1)
            energy: Average music energy (0-1)
            tempo: Average music tempo (BPM)
            danceability: Average music danceability (0-1)
            current_time: Current datetime
            execution_type: 'MATIN' or 'APRES_MIDI'

        Returns:
            Comprehensive analysis dict
        """
        # Analyze each signal
        agenda_analysis = self.agenda_analyzer.analyze_events(calendar_events, current_time.hour)
        sleep_analysis = self.sleep_analyzer.analyze_sleep(sleep_hours, bedtime, wake_time, execution_type)
        weather_analysis = self.weather_analyzer.analyze_weather(weather, temperature)
        music_analysis = self.music_analyzer.analyze_music(valence, energy, tempo, danceability)
        time_analysis = self.time_analyzer.analyze_time(current_time.hour, current_time.weekday(), execution_type)

        # Determine source weights based on execution type
        if execution_type == 'MATIN':
            source_weights = {
                'agenda': MoodAnalyzerConfig.WEIGHT_AGENDA,
                'sleep': MoodAnalyzerConfig.WEIGHT_SLEEP_MORNING,
                'weather': MoodAnalyzerConfig.WEIGHT_WEATHER_MORNING,
                'music': MoodAnalyzerConfig.WEIGHT_MUSIC,
                'time': MoodAnalyzerConfig.WEIGHT_TIME
            }
        else:  # APRES_MIDI
            source_weights = {
                'agenda': MoodAnalyzerConfig.WEIGHT_AGENDA,
                'sleep': MoodAnalyzerConfig.WEIGHT_SLEEP_AFTERNOON,
                'weather': MoodAnalyzerConfig.WEIGHT_WEATHER_AFTERNOON,
                'music': MoodAnalyzerConfig.WEIGHT_MUSIC,
                'time': MoodAnalyzerConfig.WEIGHT_TIME
            }

        # Tag signals with their source for weighted scoring
        all_signals_with_source = []
        for mood, strength in agenda_analysis['mood_signals']:
            all_signals_with_source.append((mood, strength, 'agenda'))
        for mood, strength in sleep_analysis['mood_signals']:
            all_signals_with_source.append((mood, strength, 'sleep'))
        for mood, strength in weather_analysis['mood_signals']:
            all_signals_with_source.append((mood, strength, 'weather'))
        for mood, strength in music_analysis['mood_signals']:
            all_signals_with_source.append((mood, strength, 'music'))
        for mood, strength in time_analysis['mood_signals']:
            all_signals_with_source.append((mood, strength, 'time'))

        # Score each mood WITH WEIGHTS
        mood_scores = self._score_moods(all_signals_with_source, source_weights)

        # Keep raw signals for debugging (without source tag)
        all_signals_raw = (
            agenda_analysis['mood_signals'] +
            sleep_analysis['mood_signals'] +
            weather_analysis['mood_signals'] +
            music_analysis['mood_signals'] +
            time_analysis['mood_signals']
        )

        # Generate report
        report = {
            'timestamp': current_time.isoformat(),
            'execution_type': execution_type,
            'source_weights': source_weights,  # Include weights in report
            'agenda': agenda_analysis,
            'sleep': sleep_analysis,
            'weather': weather_analysis,
            'music': music_analysis,
            'time': time_analysis,
            'all_signals': all_signals_raw,  # Raw signals for compatibility
            'mood_scores': mood_scores,
            'top_moods': sorted(mood_scores.items(), key=lambda x: x[1], reverse=True)[:3],
            'summary': self._generate_summary(
                agenda_analysis, sleep_analysis, weather_analysis, 
                music_analysis, time_analysis, mood_scores, source_weights
            )
        }

        return report

    @staticmethod
    def _score_moods(signals: List[Tuple[MoodCategory, SignalStrength, str]], 
                    source_weights: Dict[str, float]) -> Dict[str, float]:
        """
        Scores each mood based on signals WITH WEIGHTED SOURCES.

        Args:
            signals: List of (mood, strength, source) tuples
            source_weights: Dict of source -> weight (e.g., {'agenda': 0.40, 'sleep': 0.30})

        Returns:
            Dict of mood -> score
        """
        mood_scores = {mood.value: 0.0 for mood in MoodCategory}

        # Signal strength base weights (before source multiplier)
        strength_weights = {
            SignalStrength.VERY_WEAK: -30,
            SignalStrength.WEAK: -10,
            SignalStrength.NEUTRAL: 0,
            SignalStrength.STRONG: +10,
            SignalStrength.VERY_STRONG: +30
        }

        # Aggregate signals by source
        for mood, strength, source in signals:
            base_score = strength_weights[strength]
            source_weight = source_weights.get(source, 1.0)  # Default 1.0 if source not found
            weighted_score = base_score * source_weight
            mood_scores[mood.value] += weighted_score

        # NEW: Normalize scores to keep nuance (no floor at 0)
        # Find min score to shift range
        min_score = min(mood_scores.values()) if mood_scores.values() else 0
        
        # If all scores are negative, shift them up to make relative differences visible
        if min_score < 0:
            for mood in mood_scores:
                mood_scores[mood] = mood_scores[mood] - min_score  # Shift to positive range
        
        # Floor only very negative scores (< -5.0 original)
        for mood in mood_scores:
            if mood_scores[mood] < 0:
                mood_scores[mood] = max(0, mood_scores[mood])

        return mood_scores

    @staticmethod
    def _generate_summary(agenda: Dict, sleep: Dict, weather: Dict, 
                         music: Dict, time: Dict, scores: Dict,
                         weights: Dict[str, float]) -> str:
        """Generates human-readable summary with weights."""
        top_mood = max(scores.items(), key=lambda x: x[1])[0]
        
        summary = f"""
MOOD ANALYSIS SUMMARY:
=====================

WEIGHTS (Execution: {time.get('analysis', 'N/A')}):
  Agenda:  {weights.get('agenda', 0)*100:.0f}%
  Sleep:   {weights.get('sleep', 0)*100:.0f}%
  Weather: {weights.get('weather', 0)*100:.0f}%
  Music:   {weights.get('music', 0)*100:.0f}%
  Time:    {weights.get('time', 0)*100:.0f}%

[AGENDA] {agenda['analysis']}
[SLEEP]  {sleep['analysis']}
[WEATHER] {weather['analysis']}
[MUSIC]  {music['analysis']}
[TIME]   {time['analysis']}

TOP MOOD PREDICTION: {top_mood.upper()}

Mood Scores (weighted):
"""
        for mood, score in sorted(scores.items(), key=lambda x: x[1], reverse=True):
            bar = '█' * int(score / 2) if score > 0 else ''
            summary += f"  {mood:12} {score:5.1f} {bar}\n"

        return summary


# ============================================================================
# LOGGING & DEBUG
# ============================================================================

def log_analysis(analysis: Dict, logger: logging.Logger) -> None:
    """Logs analysis results."""
    logger.info("[MOOD_ANALYZER] Analysis complete")
    logger.info(f"[MOOD_ANALYZER] Top mood: {analysis['top_moods'][0][0]}")
    logger.info(f"[MOOD_ANALYZER] Summary:\n{analysis['summary']}")
