"""
Module for AI-powered mood prediction using Google Generative AI (Gemini).

This module generates context-aware prompts and predicts user mood based on strict psychological rules:
- MORNING (3am): "Capital Logic" - Sleep < 6h is a handicap. Adrenaline can mask it.
- AFTERNOON (14h): "Debt Logic" - Sleep < 6h is a sanction. Crash or Irritability (Intense) if forced.
- MUSIC: Always a fuel/positive (Fast = Pumped).
- RHYTHM: Monday = Fresh, Friday = Tired.
- AGENDA: Pressure > Duration.
"""

import os
import logging
from datetime import datetime
from typing import Dict, Optional, List, Any, Union
from enum import Enum

import google.generativeai as genai

from src.core.analyzer import MoodDataAnalyzer

# ============================================================================
# ENUMS & CONSTANTS
# ============================================================================

class ExecutionType(Enum):
    """Execution type determines context and prediction scope."""
    MATIN = "MATIN"            # 3am execution: full day prediction
    APRES_MIDI = "APRES-MIDI"  # 12h execution: afternoon check
    SOIREE = "SOIREE"          # 17h execution: evening/night prediction


class Season(Enum):
    """Seasons for contextual mood modifiers."""
    HIVER = "Hiver"
    PRINTEMPS = "Printemps"
    ETE = "Été"
    AUTOMNE = "Automne"


# Valid mood outputs
VALID_MOODS = {
    'creative', 'hard_work', 'confident', 'chill',
    'energetic', 'melancholy', 'intense', 'pumped', 'tired'
}

# Model preference order for cascade fallback
PREFERRED_MODELS = [
    'gemini-2.5-flash',
    'gemini-2.0-flash',
    'gemini-2.0-flash-lite',
    'gemini-flash-latest',
    'gemini-pro'
]

logger = logging.getLogger(__name__)


# ============================================================================
# HELPER FUNCTIONS - TEMPORAL CONTEXT
# ============================================================================

def get_execution_type(hour: int) -> ExecutionType:
    """Determines execution type based on hour."""
    if hour < 12:
        return ExecutionType.MATIN
    elif hour < 17:
        return ExecutionType.APRES_MIDI
    else:
        return ExecutionType.SOIREE


def get_season(month: int) -> Season:
    """Determines season based on month."""
    if month in [12, 1, 2]:
        return Season.HIVER
    elif month in [3, 4, 5]:
        return Season.PRINTEMPS
    elif month in [6, 7, 8]:
        return Season.ETE
    else:
        return Season.AUTOMNE


# ============================================================================
# CONTEXT BUILDER CLASSES
# ============================================================================

class TemporalContext:
    """Encapsulates temporal context for prompt generation."""

    def __init__(self, execution_time: datetime):
        self.now = execution_time
        self.hour = execution_time.hour
        self.month = execution_time.month
        self.weekday_num = execution_time.weekday()
        self.weekday_str = execution_time.strftime("%A")

        self.execution_type = get_execution_type(self.hour)
        self.season = get_season(self.month)
        self.execution_time_str = execution_time.strftime("%H:%M")


class SleepContext:
    """Encapsulates sleep information."""

    def __init__(self, bedtime: Optional[str] = None, wake_time: Optional[str] = None,
                 sleep_hours: Optional[float] = None):
        self.bedtime = bedtime or "Unknown"
        self.wake_time = wake_time or "Unknown"
        self.sleep_hours = sleep_hours or 0.0

    def to_dict(self) -> Dict[str, Any]:
        """Returns context as dictionary."""
        return {
            "bedtime": self.bedtime,
            "wake_time": self.wake_time,
            "sleep_hours": self.sleep_hours
        }


# ============================================================================
# PROMPT BUILDER
# ============================================================================

class PromptBuilder:
    """Builds contextual mood prediction prompts using strict psychological rules."""

    def __init__(self, temporal_context: TemporalContext, sleep_context: SleepContext):
        self.temporal = temporal_context
        self.sleep = sleep_context

    def _build_week_rhythm_section(self) -> str:
        """Inverted Rhythm: Monday Fresh, Friday Tired."""
        day_num = self.temporal.weekday_num
        if day_num == 0:  # Monday
            return "LUNDI : Bonus d'énergie (Batterie pleine, Fresh Start)."
        elif day_num == 4:  # Friday
            return "VENDREDI : Malus de fatigue (Batterie vide, usure de la semaine)."
        elif day_num in [5, 6]:
            return "WEEKEND : Récupération / Liberté."
        else:
            return "SEMAINE (Mar-Jeu) : Rythme de croisière."

    def build_preprocessor_section(self, analysis: Optional[Dict[str, Any]]) -> str:
        """Constructs the pre-processor analysis section."""
        if not analysis:
            return "### 0. ANCRE ALGORITHMIQUE\n- Non disponible."

        # Safety check for expected keys
        top_moods = analysis.get('top_moods', [])
        top_mood = top_moods[0][0].upper() if top_moods else "UNKNOWN"
        
        weights = analysis.get('source_weights', {})
        weights_str = ", ".join([f"{k.capitalize()}: {int(v*100)}%" for k, v in weights.items()])
        
        return f"""
### 0. ANCRE ALGORITHMIQUE (BASELINE)
Voici une pré-analyse basée sur des règles mathématiques strictes (Veto Sommeil <6h, Pression Agenda, etc.).
- **TOP MOOD CALCULÉ : {top_mood}**
- Poids utilisés : {weights_str}
- **TA CONSIGNE** : Utilise ce résultat comme **ANCRE**. 
    - Si les données brutes confirment l'algo -> Valide le mood.
    - Si tu détectes une nuance subtile que l'algo a ratée (ex: Adrénaline positive malgré fatigue) -> Tu as le droit d'ajuster.
"""

    def _build_feedback_section(self, feedback: Optional[Dict[str, float]]) -> str:
        """Constructs the User Feedback section if data exists."""
        if not feedback:
            return ""
        
        energy = int(feedback.get('energy', 0.5) * 100)
        stress = int(feedback.get('stress', 0.5) * 100)
        social = int(feedback.get('social', 0.5) * 100)
        
        return f"""
### 00. FEEDBACK UTILISATEUR (PRIORITÉ ABSOLUE)
L'utilisateur a donné son ressenti en temps réel via l'app mobile.
CES DONNÉES SONT LA VÉRITÉ TERRAIN. Utilise-les pour moduler l'analyse.

- **ÉNERGIE PHYSIQUE : {energy}%** (0=À plat, 100=En forme)
- **STRESS MENTAL : {stress}%** (0=Zen, 100=Explosion)
- **BATTERIE SOCIALE : {social}%** (0=Loup solitaire, 100=Besoin de foule)

**INSTRUCTION :** 
- Si Stress > 80% -> Forte chance de **intense** ou **tired**.
- Si Énergie > 80% -> Forte chance de **pumped**, **energetic** ou **confident**.
- Si Social > 80% -> Cherche **confident** ou **pumped**.
- Si Social < 20% -> Cherche **chill**, **creative** ou **tired**.
"""

    def _build_steps_section(self, steps_count: Optional[int]) -> str:
        """Constructs the Step Count section if data exists."""
        if not steps_count or steps_count < 200:
            # Ignore if no data or too low (user just woke up / hasn't synced yet)
            return ""
        
        # Categorize activity level
        if steps_count >= 10000:
            activity_level = "TRÈS ACTIF (Objectif atteint)"
            mood_hint = "Forte chance de **energetic**, **pumped** ou **confident**."
        elif steps_count >= 5000:
            activity_level = "ACTIF (Modéré)"
            mood_hint = "Penche vers **energetic** ou **chill**."
        else:
            activity_level = "SÉDENTAIRE (Peu de mouvement)"
            mood_hint = "Peut indiquer **tired**, **chill** ou **creative** (journée calme)."
        
        return f"""
### 00B. ACTIVITÉ PHYSIQUE (COMPTEUR DE PAS)
L'utilisateur a effectué **{steps_count:,} pas** aujourd'hui.
**NIVEAU D'ACTIVITÉ : {activity_level}**

**INSTRUCTION :** 
- {mood_hint}
- Combine cette donnée avec le niveau d'Énergie du Feedback pour affiner.
"""


    def build_morning_prompt(self, historical_moods: str, calendar_summary: str,
                             weather_summary: str, music_summary: str,
                             preprocessor_analysis: Optional[Dict[str, Any]] = None,
                             feedback: Optional[Dict[str, float]] = None,
                             steps_count: Optional[int] = None) -> str:
        """
        Génère le prompt pour le MATIN (3h).
        LOGIQUE : "CAPITAL DE DÉPART"
        """
        sleep_hours = self.sleep.sleep_hours
        
        # Determine Sleep Status for Prompt
        if sleep_hours < 6.0:
            sleep_status = "CRITIQUE (< 6h). DÉPART RÉSERVOIR VIDE. Handicap majeur."
        elif sleep_hours < 7.5:
            sleep_status = "MOYEN. Légère fatigue de fond."
        else:
            sleep_status = "OPTIMAL. Réservoir plein."

        # Pre-processor section
        algo_section = self.build_preprocessor_section(preprocessor_analysis)
        feedback_section = self._build_feedback_section(feedback)
        steps_section = self._build_steps_section(steps_count)

        prompt = f"""
### RÔLE
Tu es mon extension numérique. Tu analyses ma psychologie pour prédire mon mood du jour.
Ta réponse doit être **UN SEUL MOT** parmi la liste autorisée.

### LISTE DES MOODS AUTORISÉS (Respect strict)
- creative, hard_work, confident, chill, energetic, melancholy, intense, pumped, tired.

{feedback_section}
{steps_section}
{algo_section}

### 1. CONTEXTE TEMPOREL (MATIN - DÉPART)
- Jour : {self.temporal.weekday_str} ({self._build_week_rhythm_section()})
- Saison : {self.temporal.season.value}
- Heure : {self.temporal.execution_time_str}

### 2. HISTORIQUE & PATTERNS
- Tendance récente sur ce créneau ({self.temporal.weekday_str} Matin) :
{historical_moods}

### 3. ANALYSE PHYSIOLOGIQUE (CAPITAL SOMMEIL)
- Sommeil : {sleep_hours}h
- STATUS : **{sleep_status}**
- **RÈGLE D'OR MATIN** :
    - Si Sommeil < 6h : Je suis **tired** par défaut.
    - **EXCEPTION** : Si j'ai une ÉNORME pression (Exam, Compétition) ou Musique violente, l'adrénaline prend le dessus -> **intense** ou **pumped**. Mais c'est une dette.

### 4. ANALYSE DE L'AGENDA (PRESSION > DURÉE)
{calendar_summary}
- **RÈGLES** :
    - Examen / Rendu / Deadline = PRESSION MAX -> **hard_work** ou **intense**.
    - Sport = ÉNERGIE -> **pumped** ou **energetic**.
    - Social = CONFIANCE -> **confident**.
    - Vide = RIEN -> Laisser la place à la musique/météo.

### 5. ANALYSE SENSORIELLE (MUSIQUE & MÉTÉO)
- Météo : {weather_summary}
- Musique Récente :
{music_summary}

- **RÈGLES MUSIQUE (CARBURANT)** :
    - Rapide / Metal / Techno = **pumped** ou **energetic** (Jamais stress).
    - Rap / Hip-Hop = **confident**.
    - Calme / Lo-Fi = **creative** ou **chill**.
    - Triste / Nostalgique = **melancholy**.

### ALGORITHME DE DÉCISION (MATIN)
1. **CHECK SOMMEIL** : Si < 6h, Mood de base = **tired**.
2. **CHECK URGENCE** : Y a-t-il un événement majeur (Exam, Sport) ?
    - OUI : L'adrénaline écrase la fatigue -> **intense** (Stress) ou **pumped** (Sport).
    - NON : Le **tired** reste dominant.
3. **CHECK MUSIQUE** : Si pas de fatigue critique, la musique donne la teinte (Metal->Pumped, Rap->Confident).
4. **CHECK MÉTÉO** : Pluie le matin = Malus moral (**melancholy**). Soleil = Bonus (**energetic**).

**TA RÉPONSE :** Uniquement le mood. Pas de phrase.
"""
        return prompt

    def build_afternoon_prompt(self, historical_moods: str, calendar_summary: str,
                               weather_summary: str, music_summary: str,
                               preprocessor_analysis: Optional[Dict[str, Any]] = None,
                               feedback: Optional[Dict[str, float]] = None,
                               steps_count: Optional[int] = None) -> str:
        """
        Génère le prompt pour l'APRÈS-MIDI (14h).
        LOGIQUE : "DETTE & CRASH"
        """
        sleep_hours = self.sleep.sleep_hours
        
        # Determine Sleep Status for Prompt
        if sleep_hours < 6.0:
            sleep_status = "CRITIQUE (< 6h). DETTE PAYÉE MAINTENANT. RISQUE DE CRASH."
        else:
            sleep_status = "STABLE."

        # Pre-processor section
        algo_section = self.build_preprocessor_section(preprocessor_analysis)
        feedback_section = self._build_feedback_section(feedback)
        steps_section = self._build_steps_section(steps_count)

        prompt = f"""
### RÔLE
Tu es mon extension numérique. Tu analyses ma psychologie pour prédire mon mood de l'après-midi/soirée.
Ta réponse doit être **UN SEUL MOT** parmi la liste autorisée.

### LISTE DES MOODS AUTORISÉS
- creative, hard_work, confident, chill, energetic, melancholy, intense, pumped, tired.

{feedback_section}
{steps_section}
{algo_section}

### 1. CONTEXTE TEMPOREL (APRÈS-MIDI - BILAN)
- Jour : {self.temporal.weekday_str} ({self._build_week_rhythm_section()})
- Heure : {self.temporal.execution_time_str}

### 2. HISTORIQUE & PATTERNS
- Tendance récente sur ce créneau ({self.temporal.weekday_str} Après-midi) :
{historical_moods}

### 3. ANALYSE PHYSIOLOGIQUE (LA SANCTION)
- Sommeil nuit dernière : {sleep_hours}h
- STATUS : **{sleep_status}**
- **RÈGLE D'OR APRÈS-MIDI (CRASH)** :
    - Si Sommeil < 6h : JE NE PEUX PLUS ÊTRE PRODUCTIF.
    - Si j'essaie de travailler (Agenda chargé) -> Je deviens **intense** (Irritable, à bout).
    - Si je n'ai rien de prévu -> Je suis **tired** (Crash complet).
    - Aucune musique ne peut sauver ça.

### 4. ANALYSE DE L'AGENDA (RESTE DE LA JOURNÉE)
{calendar_summary}
- **RÈGLES** :
    - Soirée festive -> **confident** ou **pumped**.
    - Soirée calme -> **chill** ou **creative**.
    - Encore du travail -> Risque de **intense** si fatigué, **hard_work** si en forme.

### 5. ANALYSE SENSORIELLE
- Météo : {weather_summary}
- Musique du jour :
{music_summary}

### ALGORITHME DE DÉCISION (APRÈS-MIDI)
1. **CHECK CRASH** : Si Sommeil < 6h :
    - Agenda chargé ce soir ? -> **intense** (Je subis).
    - Agenda vide ? -> **tired** (Je dors).
    - *Rien d'autre n'est possible.*
2. **SI FORME OK (>6h)** :
    - Suivre l'Agenda (Soirée -> Confident, Sport -> Pumped).
    - Si Agenda vide -> Suivre la Musique (Metal -> Energetic, LoFi -> Chill).
    - Si Vendredi après-midi -> **tired** (Fin de semaine) ou **chill** (Libération), sauf si grosse fête (**pumped**).

**TA RÉPONSE :** Uniquement le mood. Pas de phrase.
"""
        return prompt

    def build_evening_prompt(self, historical_moods: str, calendar_summary: str,
                             weather_summary: str, music_summary: str,
                             preprocessor_analysis: Optional[Dict[str, Any]] = None,
                             feedback: Optional[Dict[str, float]] = None,
                             steps_count: Optional[int] = None) -> str:
        """
        Génère le prompt pour la SOIRÉE (18h+).
        LOGIQUE : "WIND DOWN vs NIGHT LIFE"
        """
        sleep_hours = self.sleep.sleep_hours
        
        # Less critical in evening, but cumulative fatigue matters
        if sleep_hours < 6.0:
            sleep_status = "CRITIQUE. Réservoir vide. Envie de dormir."
        else:
            sleep_status = "OK."

        algo_section = self.build_preprocessor_section(preprocessor_analysis)
        feedback_section = self._build_feedback_section(feedback)
        steps_section = self._build_steps_section(steps_count)

        prompt = f"""
### RÔLE
Tu es mon extension numérique. Tu analyses ma psychologie pour prédire mon mood de la soirée.
Ta réponse doit être **UN SEUL MOT** parmi la liste autorisée.

### LISTE DES MOODS AUTORISÉS
- creative, hard_work, confident, chill, energetic, melancholy, intense, pumped, tired.

{feedback_section}
{steps_section}
{algo_section}

### 1. CONTEXTE TEMPOREL (SOIRÉE - WIND DOWN)
- Jour : {self.temporal.weekday_str}
- Heure : {self.temporal.execution_time_str}

### 2. HISTORIQUE & PATTERNS
- Tendance récente sur ce créneau ({self.temporal.weekday_str} Soirée) :
{historical_moods}

### 3. FATIGUE CUMULÉE
- Sommeil nuit dernière : {sleep_hours}h.
- Si je suis fatigué -> **tired** ou **chill**.
- Si j'ai encore de l'énergie (ou fête) -> **pumped**.

### 4. AGENDA SOIRÉE
{calendar_summary}
- **RÈGLES** :
    - Soirée festive / Sortie -> **pumped** ou **confident**.
    - Travail tardif -> **intense** ou **hard_work**.
    - Rien / Dîner calme -> **chill** ou **creative** (Passions).
    - Vacances -> **chill**.

### 5. AMBIANCE (MUSIQUE & MÉTÉO)
- Météo : {weather_summary}
- Musique :
{music_summary}

### ALGORITHME DE DÉCISION (SOIRÉE)
1. **CHECK AGENDA** : Une sortie prévue ? -> **pumped** / **confident**.
2. **CHECK FATIGUE** : Si grosse fatigue et pas de sortie -> **tired**.
3. **CHECK RELAX** : Si pas de stress et pas de sortie -> **chill** ou **creative** (selon musique).
4. **CHECK TRAVAIL** : Si deadline demain -> **hard_work**.

**TA RÉPONSE :** Uniquement le mood. Pas de phrase.
"""
        return prompt


# ============================================================================
# PUBLIC API
# ============================================================================

def construct_prompt(
    historical_moods: str,
    music_summary: str,
    calendar_summary: str,
    weather_summary: str,
    sleep_info: Optional[Dict[str, Any]] = None,
    execution_time: Optional[datetime] = None,
    preprocessor_analysis: Optional[Dict[str, Any]] = None,
    feedback_metrics: Optional[Dict[str, float]] = None,
    steps_count: Optional[int] = None
) -> str:
    """
    Constructs the mood prediction prompt using the appropriate builder strategy.
    
    Args:
        historical_moods: String summary of past moods (unused in current prompts but kept for API).
        music_summary: Formatted string of music analysis.
        calendar_summary: Formatted string of calendar events.
        weather_summary: Formatted string of weather.
        sleep_info: Dictionary containing sleep metrics.
        execution_time: Override for current time (for testing).
        preprocessor_analysis: Result from MoodDataAnalyzer.
        
    Returns:
        Formatted prompt string.
    """
    execution_time = execution_time or datetime.now()
    sleep_info = sleep_info or {}

    temporal_context = TemporalContext(execution_time)
    sleep_context = SleepContext(
        bedtime=sleep_info.get("bedtime"),
        wake_time=sleep_info.get("wake_time"),
        sleep_hours=sleep_info.get("sleep_hours")
    )

    builder = PromptBuilder(temporal_context, sleep_context)
    
    if temporal_context.execution_type == ExecutionType.MATIN:
        return builder.build_morning_prompt(
            historical_moods, calendar_summary, weather_summary, music_summary,
            preprocessor_analysis, feedback_metrics, steps_count
        )
    elif temporal_context.execution_type == ExecutionType.APRES_MIDI:
        return builder.build_afternoon_prompt(
            historical_moods, calendar_summary, weather_summary, music_summary,
            preprocessor_analysis, feedback_metrics, steps_count
        )
    else:
        return builder.build_evening_prompt(
            historical_moods, calendar_summary, weather_summary, music_summary,
            preprocessor_analysis, feedback_metrics, steps_count
        )


def _extract_valid_mood(response_text: str) -> Optional[str]:
    """
    Validates and cleans the model's response.
    
    Args:
        response_text: Raw text from Gemini.
        
    Returns:
        Valid mood string or None.
    """
    cleaned = response_text.strip().lower().replace(".", "").replace("\n", "")
    for mood in VALID_MOODS:
        if mood in cleaned:
            return mood
    return None


def predict_mood(
    historical_moods: str,
    music_summary: str,
    calendar_summary: str,
    weather_summary: str = "Non disponible",
    sleep_info: Optional[Dict[str, Any]] = None,
    dry_run: bool = False,
    music_metrics: Optional[Dict[str, Any]] = None,
    calendar_events: Optional[List[Dict[str, Any]]] = None,
    feedback_metrics: Optional[Dict[str, float]] = None,
    steps_count: Optional[int] = None
) -> Union[str, Dict[str, str]]:
    """
    Main entry point for mood prediction.
    Orchestrates the hybrid approach: Rule-Based Pre-analysis + LLM Prediction.

    Args:
        historical_moods: Previous mood history.
        music_summary: Music analysis string.
        calendar_summary: Calendar analysis string.
        weather_summary: Weather string.
        sleep_info: Sleep metrics dictionary.
        dry_run: If True, returns prompt without API call.
        music_metrics: Structured music metrics for pre-processor.
        calendar_events: Structured calendar events for pre-processor.

    Returns:
        Predicted mood string, or dict if dry_run.
    """
    
    # 1. Pre-processing (Deterministic Anchor)
    preprocessor_analysis = None
    try:
        execution_time = datetime.now()
        analyzer = MoodDataAnalyzer()
        
        # Default metrics if missing
        if not music_metrics:
            music_metrics = {'avg_valence': 0.5, 'avg_energy': 0.5, 'avg_tempo': 100}

        # Run Analysis
        preprocessor_analysis = analyzer.analyze(
            calendar_events=calendar_events if calendar_events else [],
            sleep_hours=sleep_info.get('sleep_hours', 7.5) if sleep_info else 7.5,
            bedtime=sleep_info.get('bedtime', '23:00') if sleep_info else '23:00',
            wake_time=sleep_info.get('wake_time', '07:00') if sleep_info else '07:00',
            weather=weather_summary,
            temperature=None,
            valence=music_metrics.get('avg_valence', 0.5),
            energy=music_metrics.get('avg_energy', 0.5),
            tempo=int(music_metrics.get('avg_tempo', 100)),
            danceability=0.5,
            current_time=execution_time,
            execution_type=get_execution_type(execution_time.hour).name
        )
    except Exception as e:
        logger.warning(f"Pre-processing failed (Non-blocking): {e}")

    # 2. Construct Prompt (Hybrid)
    prompt = construct_prompt(
        historical_moods, music_summary, calendar_summary, weather_summary, 
        sleep_info, execution_time=datetime.now(), preprocessor_analysis=preprocessor_analysis,
        feedback_metrics=feedback_metrics,
        steps_count=steps_count
    )

    # 3. Handle Dry Run
    if dry_run:
        return {"mood": "dry_run", "prompt": prompt}

    # 4. Call Gemini API
    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        logger.error("No GEMINI_API_KEY found in environment.")
        return "chill"

    genai.configure(api_key=api_key)

    for model_name in PREFERRED_MODELS:
        try:
            logger.info(f"Predicting with model: {model_name}")
            model = genai.GenerativeModel(model_name)
            response = model.generate_content(prompt)
            mood = _extract_valid_mood(response.text)
            
            if mood:
                logger.info(f"Model {model_name} predicted: {mood}")
                return mood
            else:
                logger.warning(f"Model {model_name} returned invalid mood format: {response.text}")
                
        except Exception as e:
            logger.warning(f"Model {model_name} failed: {e}")
            continue

    logger.error("All models failed. Fallback to default.")
    return "chill"
