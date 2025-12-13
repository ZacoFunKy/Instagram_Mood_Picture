"""
Module for AI-powered mood prediction using Google Generative AI (Gemini).

This module generates context-aware prompts and predicts user mood based on:
- Calendar agenda (40% weight)
- Sleep patterns (30% morning, 15% afternoon)
- Weather conditions (15% morning, 20% afternoon)
- Music listening history (10%)
- Time of day (5%)

The prediction logic differentiates between morning (3am) and afternoon (14h) executions
to provide contextually appropriate mood predictions.
"""

import os
import logging
from datetime import datetime
from typing import Dict, Optional, Tuple, List, Any
from enum import Enum

import google.generativeai as genai

from .mood_analyzer import MoodDataAnalyzer, log_analysis


# ============================================================================
# ENUMS & CONSTANTS
# ============================================================================

class ExecutionType(Enum):
    """Execution type determines context and prediction scope."""
    MATIN = "MATIN"           # 3am execution: full day prediction
    APRES_MIDI = "APRES-MIDI"  # 14h execution: evening + tomorrow prediction


class Season(Enum):
    """Seasons for contextual mood modifiers."""
    HIVER = "Hiver"
    PRINTEMPS = "Printemps"
    ETE = "Été"
    AUTOMNE = "Automne"


class WeekPhase(Enum):
    """Weekly phases for contextual mood adjustments."""
    DEBUT_SEMAINE = "Début de semaine (fraîcheur mentale)"
    MILIEU_SEMAINE = "Milieu de semaine (rythme de croisière)"
    FIN_SEMAINE = "Fin de semaine (libération proche)"
    WEEKEND = "Weekend (récupération)"


class MusicMoment(Enum):
    """Time of day classifications for music context."""
    TRES_TOT_MATIN = "Tôt le matin (réveil/activation)"
    MATINEE_MIDI = "Matinée/Midi (travail/activité)"
    APRES_MIDI_TIME = "Après-midi (concentration)"
    SOIREE = "Soirée (détente/social)"
    TARD_SOIR = "Tard le soir (relâchement/rumination)"


# Valid mood outputs
VALID_MOODS = {
    'creative', 'hard_work', 'confident', 'chill',
    'energetic', 'melancholy', 'intense', 'pumped', 'tired'
}

# Model preference order for cascade fallback
PREFERRED_MODELS = [
    'models/gemini-2.5-flash',
    'models/gemini-2.5-flash-lite',
    'models/gemini-2.0-flash-exp',
    'models/gemini-exp-1206',
    'models/gemini-2.0-flash-thinking-exp',
    'models/gemini-1.5-pro-latest',
    'models/gemini-1.5-pro',
    'models/gemini-1.5-flash-latest',
    'models/gemini-1.5-flash',
    'models/gemini-pro'
]

logger = logging.getLogger(__name__)


# ============================================================================
# HELPER FUNCTIONS - TEMPORAL CONTEXT
# ============================================================================

def get_execution_type(hour: int) -> ExecutionType:
    """
    Determines execution type based on current hour.

    Args:
        hour: Current hour (0-23)

    Returns:
        ExecutionType: MATIN if hour < 12, else APRES_MIDI
    """
    return ExecutionType.MATIN if hour < 12 else ExecutionType.APRES_MIDI


def get_season(month: int) -> Season:
    """
    Determines season based on month.

    Args:
        month: Month number (1-12)

    Returns:
        Season: Corresponding season enum
    """
    if month in [12, 1, 2]:
        return Season.HIVER
    elif month in [3, 4, 5]:
        return Season.PRINTEMPS
    elif month in [6, 7, 8]:
        return Season.ETE
    else:
        return Season.AUTOMNE


def get_week_phase(weekday_num: int) -> WeekPhase:
    """
    Determines weekly phase based on weekday.

    Args:
        weekday_num: Weekday number (0=Monday, 6=Sunday)

    Returns:
        WeekPhase: Corresponding week phase enum
    """
    if weekday_num in [0, 1]:  # Monday, Tuesday
        return WeekPhase.DEBUT_SEMAINE
    elif weekday_num in [2, 3]:  # Wednesday, Thursday
        return WeekPhase.MILIEU_SEMAINE
    elif weekday_num == 4:  # Friday
        return WeekPhase.FIN_SEMAINE
    else:  # Saturday, Sunday
        return WeekPhase.WEEKEND


def get_music_moment(hour: int) -> MusicMoment:
    """
    Determines music context moment based on hour.

    Args:
        hour: Current hour (0-23)

    Returns:
        MusicMoment: Time-based music context
    """
    if hour < 9:
        return MusicMoment.TRES_TOT_MATIN
    elif hour < 14:
        return MusicMoment.MATINEE_MIDI
    elif hour < 18:
        return MusicMoment.APRES_MIDI_TIME
    elif hour < 22:
        return MusicMoment.SOIREE
    else:
        return MusicMoment.TARD_SOIR


# ============================================================================
# CONTEXT BUILDER CLASSES
# ============================================================================

class TemporalContext:
    """Encapsulates temporal context for prompt generation."""

    def __init__(self, execution_time: datetime):
        """
        Initialize temporal context from execution time.

        Args:
            execution_time: Current datetime

        Raises:
            ValueError: If execution_time is not a datetime object
        """
        if not isinstance(execution_time, datetime):
            raise ValueError("execution_time must be a datetime object")

        self.now = execution_time
        self.hour = execution_time.hour
        self.month = execution_time.month
        self.weekday_num = execution_time.weekday()
        self.weekday_str = execution_time.strftime("%A")

        # Derived contexts
        self.execution_type = get_execution_type(self.hour)
        self.season = get_season(self.month)
        self.week_phase = get_week_phase(self.weekday_num)
        self.music_moment = get_music_moment(self.hour)
        self.execution_time_str = execution_time.strftime("%H:%M")

    @property
    def prediction_day(self) -> str:
        """Returns prediction scope based on execution type."""
        return "aujourd'hui et ce soir" if self.execution_type == ExecutionType.MATIN else "ce soir et demain matin"

    @property
    def prediction_date(self) -> str:
        """Returns formatted prediction date."""
        if self.execution_type == ExecutionType.MATIN:
            return self.now.strftime("%A %d/%m")
        else:
            return f"{self.now.strftime('%A %d/%m')} et demain"

    @property
    def execution_context_str(self) -> str:
        """Returns execution context description."""
        if self.execution_type == ExecutionType.MATIN:
            return "EXECUTION NUIT/MATIN - Prediction pour TOUTE la journée qui commence"
        else:
            return "EXECUTION APRES-MIDI - Prediction pour ce SOIR + demain matin (affinage rapide)"

    @property
    def sleep_impact(self) -> str:
        """Returns sleep impact description based on execution type."""
        if self.execution_type == ExecutionType.MATIN:
            return "CRITIQUE - Affecte TOUTE la journée"
        else:
            return "SECONDAIRE - Déjà vécu, affecte demain surtout"

    @property
    def agenda_scope(self) -> str:
        """Returns agenda scope based on execution type."""
        if self.execution_type == ExecutionType.MATIN:
            return "Tous les événements du jour"
        else:
            return "Events restants aujourd'hui + demain matin"


class SleepContext:
    """Encapsulates sleep information with defaults and validation."""

    def __init__(self, bedtime: Optional[str] = None, wake_time: Optional[str] = None,
                 sleep_hours: Optional[float] = None):
        """
        Initialize sleep context.

        Args:
            bedtime: Sleep time (format: "HH:MM" or "Unknown")
            wake_time: Wake time (format: "HH:MM" or "Unknown")
            sleep_hours: Total sleep duration in hours
        """
        self.bedtime = bedtime or "Unknown"
        self.wake_time = wake_time or "Unknown"
        self.sleep_hours = sleep_hours or 0

    def to_dict(self) -> Dict[str, any]:
        """Convert to dictionary for prompt template."""
        return {
            "bedtime": self.bedtime,
            "wake_time": self.wake_time,
            "sleep_hours": self.sleep_hours
        }


# ============================================================================
# PROMPT BUILDER
# ============================================================================

class PromptBuilder:
    """Builds contextual mood prediction prompts using builder pattern."""

    MOOD_DESCRIPTIONS = ""

    DECISION_PROCESS = """
### PROTOCOLE DE DÉCISION FINAL (ARBRE STRICT)

**NIVEAU 1 - ACTIVITÉS PHYSIQUES (Priority Override)**
1. **SPORT INTENSE** (Crossfit, Compétition, HIIT) → **pumped**
2. **SPORT MODÉRÉ** (Run, Gym) → **energetic**

**NIVEAU 2 - CHARGE MENTALE & AGENDA**
3. **SURCHARGE** (> 6h) OU **Deadline urgente** → **intense**
4. **TRAVAIL CRÉATIF** (Design, Dev, Art) → **creative**
5. **ÉTUDES/FOCUS** (Exam, Projet, Réunion) → **hard_work**

**NIVEAU 3 - SOCIAL**
6. **ÉVÉNEMENT SOCIAL ACTIF** (Fête, Soirée, Concert) → **confident** (ou **pumped** si musique énergique)
7. **SOCIAL CALME** (Resto, Café) → **confident**

**NIVEAU 4 - MUSIQUE & MÉTÉO (SI AGENDA LÉGER/VIDE)**
8. **BPM >140** → **pumped** ou **intense**
9. **Musique énergique tôt (<9h)** → **pumped** ou **energetic**
10. **Rap/Hip-Hop + Soleil** → **confident**
11. **Pop/Indie + Chaleur >25°C** → **energetic**
12. **BPM <90 OU Musique Lo-Fi** → **creative** ou **chill**
13. **Répétition + Musique triste** → **melancholy**
14. **Musique calme tard (>22h)** → **chill** ou **melancholy**
15. **Musique Triste OU Pluie** → **melancholy**
16. **Aucune musique OU Froid <5°C OU Pluie** → **tired**
17. **Hiver + Musique lente** → **melancholy** ou **tired**
18. **Été + Musique énergique** → **pumped** ou **energetic**

**NIVEAU 5 - JOUR & FATIGUE**
19. **Lundi + Agenda léger** → **hard_work** ou **tired**
20. **Vendredi + Social/Musique énergique** → **confident** ou **pumped**
21. **Dimanche + Vide** → **chill**
22. **Fin semaine + Surcharge** → **tired** ou **intense**

---

### LES 9 MOODS AUTORISÉS :

**Travail & Attitude :**
* **creative** : Travail créatif, génération d'idées, art/perso
* **hard_work** : Études, focus intense, examens, réunions sérieuses
* **confident** : Social actif, attitude fière, "Boss mode"

**Énergie Quotidienne :**
* **chill** : Repos tranquille, détente, hamac mental
* **energetic** : Dynamique sain, sport modéré, bonne humeur
* **melancholy** : Tristesse, nostalgie, pluie intérieure

**Extrêmes :**
* **intense** : Charge max, deadline, focus extrême
* **pumped** : Énergie explosive, sport intense, fête, hype
* **tired** : Épuisement total, fatigue physique/morale

---

**TA RÉPONSE : UNIQUEMENT le mot du mood, minuscules, sans explication.**"""

    def __init__(self, temporal_context: TemporalContext, sleep_context: SleepContext):
        """
        Initialize prompt builder.

        Args:
            temporal_context: TemporalContext instance
            sleep_context: SleepContext instance
        """
        self.temporal = temporal_context
        self.sleep = sleep_context

    def build_objective_section(self) -> str:
        """Builds objective section of prompt."""
        return f"""Tu es une IA experte en psychologie comportementale et en analyse de données contextuelles. Tu gères l'avatar numérique de l'utilisateur.

**CONTEXTE TEMPOREL :**
- Jour : {self.temporal.weekday_str}
- Heure : {self.temporal.hour}h
- Saison : {self.temporal.season.value}
- Phase hebdomadaire : {self.temporal.week_phase.value}
- Moment musical : {self.temporal.music_moment.value}

Ta tâche est d'analyser les signaux faibles et forts pour déterminer l'état émotionnel et l'énergie de l'utilisateur.

---"""

    def build_agenda_section_morning(self, calendar_summary: str) -> str:
        """Builds agenda section optimized for morning execution."""
        return f"""
### 1. ANALYSE CONTEXTUELLE - AGENDA (L'ENVIRONNEMENT)
**Source : Agenda ({calendar_summary})**

**RÈGLES DE PRIORITÉ TEMPORELLE :**
1. **"--- FOCUS AUJOURD'HUI ---"** : C'est la vérité absolue. Si vide → musique + météo + contexte temporel.
2. **"--- CONTEXTE SEMAINE ---"** : Anticipe le stress (ex: partiel demain → **hard_work** ou **intense** aujourd'hui).
3. **"--- CONTEXTE PASSÉ ---"** : Explique la fatigue.

**INTERPRÉTATION ACTIVITÉS :**
* 🏃 **SPORT INTENSE** (Crossfit, Compétition, HIIT) → **pumped**
* 🚴 **SPORT MODÉRÉ** (Run, Gym, Yoga) → **energetic**
* 🧠 **TRAVAIL CRÉATIF** (Design, Dev, Art) → **creative**
* 📚 **ÉTUDES/FOCUS** (Exam, Projet urgent, Réunion) → **hard_work** ou **intense**
* 🎉 **SOCIAL ACTIF** (Fête, Soirée, Concert) → **confident** ou **pumped**
* 🍽️ **SOCIAL CALME** (Resto, Café) → **confident**
* 😰 **SURCHARGE** (> 6h dense) → **intense** ou **tired**
* 🛌 **REPOS/VIDE** → Voir musique + météo

**IMPACT DU JOUR :**
* **Lundi** : Reprise → **hard_work** (sauf repos)
* **Vendredi** : Libération → **confident** ou **pumped**
* **Samedi/Dimanche** : Repos → **chill** ou **energetic**

---"""

    def build_agenda_section_afternoon(self, calendar_summary: str) -> str:
        """Builds agenda section optimized for afternoon execution."""
        return f"""
### 1. ANALYSE CONTEXTUELLE - AGENDA (L'ENVIRONNEMENT)
**Source : Agenda ({calendar_summary})**

**RÈGLES DE PRIORITÉ TEMPORELLE :**
1. **"--- FOCUS AUJOURD'HUI ---"** : C'est la vérité absolue. Si vide → musique + météo + contexte temporel.
2. **"--- CONTEXTE SEMAINE ---"** : Anticipe le stress (ex: exam demain → **hard_work** ou **intense**).

**INTERPRÉTATION ACTIVITÉS :**
* 🏃 **SPORT INTENSE** (Crossfit, Compétition, HIIT) → **pumped**
* 🚴 **SPORT MODÉRÉ** (Run, Gym) → **energetic**
* 🧠 **TRAVAIL CRÉATIF** (Design, Dev, Art) → **creative**
* 📚 **ÉTUDES/FOCUS** (Exam, Projet, Réunion) → **hard_work** ou **intense**
* 🎉 **SOCIAL ACTIF** (Fête, Soirée) → **confident** ou **pumped**
* 🍽️ **SOCIAL CALME** (Resto, Café) → **confident**
* 😰 **SURCHARGE** (> 6h) → **intense** ou **tired**
* 🛌 **REPOS/VIDE ce soir** → Voir musique + météo

**IMPACT DU JOUR (SOIR) :**
* **Vendredi soir** : Libération → **FORCE confident** ou **chill**
* **Autres jours soir** : Suit l'agenda/musique normalement

---"""

    def build_sleep_section_morning(self, music_summary: str) -> str:
        """Builds sleep section optimized for morning execution (Critical Impact: 30%)."""
        sleep_dict = self.sleep.to_dict()
        
        return f"""
### 2. ANALYSE PHYSIOLOGIQUE - SOMMEIL
**Source : Estimation via activité musicale**

**DONNÉES DE SOMMEIL :**
* Coucher estimé : {sleep_dict['bedtime']}
* Réveil estimé : {sleep_dict['wake_time']}
* Durée totale : **{sleep_dict['sleep_hours']}h**

**IMPACT SUR L'HUMEUR :**
* **< 5h** : Épuisement total → **tired**
* **5-6h** : Fatigue significative → **tired** (léger)
* **6-7h** : Légère fatigue → Neutre (suit musique/agenda)
* **7-9h** : OPTIMAL → Neutre (aucun signal fatigue)
* **> 9h** : Récupération profonde → **chill** (repos)

---

### 3. ANALYSE SENSORIELLE - MUSIQUE & HISTORIQUE
**Source : Historique d'écoute**
**{music_summary}**
**Ceci est le reflet direct de l'inconscient et de l'humeur réelle.**

**SIGNAUX MUSICAUX RAPIDES :**
* **Musique Rapide / Metal / Techno / Hard Rock** → Décharge énergie → **intense** ou **pumped**
* **Rap / Hip-Hop / Trap** → Confiance en soi, "Boss mode" → **confident**
* **Électro Lourde / Hardstyle / Drum & Bass** → Énergie max → **pumped** ou **energetic**
* **Pop / Indie / Rock modéré** → Bonne humeur équilibrée → **energetic** ou **confident**
* **Lo-Fi / Jazz / Classique** → Besoin concentration → **creative** ou **chill**
* **Acoustique / Folk / Ballade** → Introspection, nostalgie → **melancholy** ou **tired**
* **Musique Triste / Lente / Ambient** → Fatigue morale → **melancholy** ou **tired**
* **Aucune musique** → Faible énergie → **tired** ou **chill**

**TEMPO & PATTERNS :**
* **BPM >140 (Hardstyle, Techno, DnB)** → **pumped** ou **intense**
* **BPM 120-140 (Pop, House, Hip-Hop)** → **energetic** ou **confident**
* **BPM 90-120 (Rock, Indie)** → **creative** ou **energetic**
* **BPM <90 (Ballade, Jazz, Lo-Fi)** → **chill** ou **tired**
* **Répétition (>5x même chanson)** → **melancholy** (rumination) ou **pumped** (obsession)
* **Écoute tôt matin (<9h) + énergique** → **pumped** ou **energetic**
* **Écoute tard soir (>22h) + calme** → **chill** ou **melancholy**

---"""

    def build_sleep_section_afternoon(self, music_summary: str) -> str:
        """Builds sleep section optimized for afternoon execution (Secondary Impact: 15%)."""
        sleep_dict = self.sleep.to_dict()
        
        return f"""
### 2. ANALYSE PHYSIOLOGIQUE - SOMMEIL
**Source : Estimation via activité musicale (la nuit dernière)**

**DONNÉES DE SOMMEIL :**
* Coucher : {sleep_dict['bedtime']}
* Réveil : {sleep_dict['wake_time']}
* Durée : **{sleep_dict['sleep_hours']}h**

**IMPACT RÉSIDUEL (après-midi) :**
* **< 5h** : Fatigue persistante → **tired**
* **5-7h** : Légère fatigue résiduelle → Suit musique/agenda
* **7-9h** : Aucun impact → Neutre
* **> 9h** : Bien reposé → Boost énergie

---

### 3. ANALYSE SENSORIELLE - MUSIQUE & HISTORIQUE
**Source : Historique d'écoute (ce matin/aujourd'hui)**
**{music_summary}**
**Ceci est le reflet direct de l'inconscient et de l'humeur réelle.**

**SIGNAUX MUSICAUX RAPIDES :**
* **Musique Rapide / Metal / Techno / Hard Rock** → Décharge énergie → **intense** ou **pumped**
* **Rap / Hip-Hop / Trap** → Confiance, "Boss mode" → **confident**
* **Électro Lourde / Hardstyle / Drum & Bass** → Énergie max → **pumped** ou **energetic**
* **Pop / Indie / Rock modéré** → Bonne humeur → **energetic** ou **confident**
* **Lo-Fi / Jazz / Classique** → Concentration → **creative** ou **chill**
* **Acoustique / Folk / Ballade** → Introspection → **melancholy** ou **tired**
* **Musique Triste / Lente / Ambient** → Fatigue morale → **melancholy** ou **tired**

**TEMPO & PATTERNS :**
* **BPM >140** → **pumped** ou **intense**
* **BPM 120-140** → **energetic** ou **confident**
* **BPM 90-120** → **creative** ou **energetic**
* **BPM <90** → **chill** ou **tired**
* **Répétition (>5x)** → **melancholy** (rumination) ou **pumped**
* **Tard soir (>22h) + calme** → **chill** ou **melancholy**

---"""

    def build_weather_section_morning(self, weather_summary: str) -> str:
        """Builds weather section optimized for morning execution (Impact: 15%)."""
        return f"""
### 4. ANALYSE DES CONTRAINTES - MÉTÉO
**Source : Météo ({weather_summary})**

**IMPACT MÉTÉO :**
* ☀️ **Grand Soleil** → Booste confiance, énergie → **pumped**, **confident**, **energetic**
* 🌤️ **Nuages légers** → Neutre, suit musique et agenda
* 🌧️ **Pluie/Grisaille** → Fatigue mentale → **melancholy**, **tired**
* ⛈️ **Orage** → Tension intense → **intense** ou **melancholy**
* 🌡️ **Froid <5°C** → Fatigue physique → **tired** ou **chill**
* 🌡️ **Chaleur >25°C** → Énergie boost → **energetic** ou **pumped**

**SAISON :**
* **Hiver/Automne** → Tendance **melancholy** ou **chill**
* **Été** → Tendance **energetic** ou **pumped**

---"""

    def build_weather_section_afternoon(self, weather_summary: str) -> str:
        """Builds weather section optimized for afternoon execution (Impact: 20%)."""
        return f"""
### 4. ANALYSE DES CONTRAINTES - MÉTÉO
**Source : Météo ({weather_summary})**

**IMPACT MÉTÉO (CE SOIR) :**
* ☀️ **Grand Soleil** → **pumped**, **confident**, **energetic**
* 🌤️ **Nuages légers** → Neutre
* 🌧️ **Pluie/Grisaille** → **melancholy**, **tired**
* ⛈️ **Orage** → **intense** ou **melancholy**
* 🌡️ **Froid <5°C** → **tired** ou **chill**
* 🌡️ **Chaleur >25°C** → **energetic** ou **pumped**

---"""

    def build_hour_section_morning(self) -> str:
        """Builds hour section optimized for morning execution (Impact: 5%)."""
        return ""

    def build_hour_section_afternoon(self) -> str:
        """Builds hour section optimized for afternoon execution (Impact: 5%)."""
        return ""

    def build_preprocessor_section(self, analysis: Optional[Dict]) -> str:
        """Builds preprocessor analysis section (PRIORITY SIGNAL)."""
        if not analysis:
            return """
### 1. PRÉ-ANALYSE ALGORITHMIQUE
**⚠️ Pas de pré-analyse disponible - analyse manuelle complète requise.**
"""
        
        top_moods = analysis.get('top_moods', [])
        weights = analysis.get('source_weights', {})
        
        if not top_moods:
            return """
### 1. PRÉ-ANALYSE ALGORITHMIQUE
**⚠️ Aucune prédiction générée - analyse manuelle complète requise.**
"""
        
        # Format top 3 predictions
        top_3_str = "\n".join([
            f"  {i}. **{mood if isinstance(mood, str) else mood}** (score: {score:.1f})"
            for i, (mood, score) in enumerate(top_moods[:3], 1)
        ])
        
        # Format weights
        weights_str = "\n".join([
            f"  - {source.capitalize()}: **{weight*100:.0f}%**"
            for source, weight in sorted(weights.items(), key=lambda x: -x[1])
        ])
        
        return f"""
# ═══════════════════════════════════════════════════════════════════════════
# SECTION 1 : PRÉ-ANALYSE ALGORITHMIQUE (PRIORITAIRE)
# ═══════════════════════════════════════════════════════════════════════════

## 📊 PRÉDICTIONS PONDÉRÉES (Analyse automatique)

**POIDS DES SOURCES (par importance) :**
{weights_str}

**TOP 3 MOODS PRÉDITS :**
{top_3_str}

## 🎯 PROTOCOLE D'UTILISATION (ÉTAPE PAR ÉTAPE)

**ÉTAPE 1 - BASELINE :**
Prends le **TOP 1** comme point de départ de ton analyse.

**ÉTAPE 2 - ANALYSE CRITIQUE :**
Analyse les données brutes (section 2) avec ton expertise :
  ✓ Si les données confirment le TOP 1 → **VALIDE-LE**
  ⚠️ Si tu détectes une incohérence ou un signal manquant → **AJUSTE**

**ÉTAPE 3 - DÉCISION FINALE :**
Tu es LIBRE de choisir :
  - Le **TOP 1** si l'analyse algorithmique est cohérente
  - Le **TOP 2 ou TOP 3** si plus adapté aux données qualitatives  
  - Un **autre mood** si tu détectes un signal fort manqué (événement critique, pattern inhabituel)

**RÈGLE IMPORTANTE :** L'algorithme donne une baseline scientifique, mais TOI seul vois les nuances contextuelles.
Utilise ton jugement d'expert pour la décision finale. Si tu ajustes, explique pourquoi brièvement dans ta réflexion interne.

---"""

    def build_raw_data_header(self) -> str:
        """Builds section header for raw data."""
        return """
# ═══════════════════════════════════════════════════════════════════════════
# SECTION 2 : DONNÉES BRUTES (Pour valider la pré-analyse)
# ═══════════════════════════════════════════════════════════════════════════

Utilise ces données pour **valider** ou **ajuster** la prédiction de la Section 1.
"""

    def build_morning_prompt(self, historical_moods: str, calendar_summary: str,
                         weather_summary: str, music_summary: str,
                         preprocessor_analysis: Optional[Dict] = None) -> str:
        """Morning prompt (3h): new, streamlined layout for clarity."""

        sleep_dict = self.sleep.to_dict()

        def format_preproc(pre: Optional[Dict]) -> str:
            if not pre:
                return "Aucune pré-analyse disponible (raisonne à partir des données brutes)."
            weights = pre.get('source_weights', {})
            top = pre.get('top_moods', [])
            weights_str = ", ".join([f"{k}:{int(v*100)}%" for k, v in weights.items()])
            top_str = " / ".join([f"{m if isinstance(m, str) else m}:{score:.1f}" for m, score in top[:3]])
            return f"Poids sources: {weights_str}\nTop pré-analyse: {top_str}"

        return f"""
### RÔLE
Tu es une IA de mood-triage. Ta sortie est **un seul mot** (mood autorisé) en minuscules.

### CONTEXTE D'EXÉCUTION (MATIN - 3h)
- Jour / date : {self.temporal.weekday_str} {self.temporal.now.strftime('%d/%m')}
- Heure locale : {self.temporal.execution_time_str}
- Portée : Prévision pour aujourd'hui et ce soir.
- Historique moods : {historical_moods if historical_moods else 'Non fourni'}

### PRÉ-ANALYSE (PRIORITAIRE SI PRÉSENTE)
{format_preproc(preprocessor_analysis)}

### DONNÉES BRUTES (ne pas inventer)
- Agenda (aujourd'hui + contexte semaine) :
{calendar_summary}
- Sommeil : coucher {sleep_dict['bedtime']} / réveil {sleep_dict['wake_time']} / durée {sleep_dict['sleep_hours']}h
- Météo : {weather_summary}
- Musique / historique :
{music_summary}

### MÉTHODE (RAISONNE EN 4 ÉTAPES)
1) Agenda d'abord : identifie charge (réunions serrées, livrables, déplacements) et nature (créatif, deep work, social, sport). Charge haute → hard_work/intense; créatif long sans stress → creative; social positif → confident/energetic; sport matinal → pumped/energetic.
2) Sommeil ensuite : <5h = fatigue forte, 5-7h = légère fatigue, 7-9h = neutre, >9h = repos/chill. Si sommeil très court et agenda chargé → hard_work mais énergie basse (tired si peu de contraintes). Sommeil long + peu d'agenda → chill/creative.
3) Météo : pluie/froid → réduit énergie (baisse confident/energetic, monte melancholy/tired/chill); soleil/chaleur modérée → monte confident/energetic; chaleur forte peut fatiguer (favorise tired/chill si déjà chargé).
4) Musique : BPM/énergie/valence. Haute énergie/tempo + valence haute → pumped/energetic/confident. Énergie basse + valence basse → melancholy/tired. Si musique contredit agenda+sommeil, garde agenda+sommeil comme ancre et ajuste seulement si cohérent.

### GUIDE DE SÉLECTION DU MOOD (RÈGLES CONCRÈTES)
- creative: journée légère, tâches ouvertes/créatives, sommeil ok (≥7h), météo neutre/agréable, musique plutôt inspirante/modérée.
- hard_work: livrables, réunions serrées, déplacements, beaucoup de tâches exigeantes; sommeil insuffisant n’annule pas, le devoir prime.
- confident: social positif, présentations, bonnes nouvelles; météo agréable; musique à haute valence et énergie modérée/haute.
- chill: peu de contraintes, volonté de détente/recovery; sommeil long ou besoin de repos; météo maussade mais sans obligations.
- energetic: sport prévu, déplacement dynamique, peu de stress; sommeil ok; météo agréable; musique énergique.
- melancholy: météo et musique basses en valence, introspection; peu de contraintes et sommeil moyen; éviter si obligations fortes.
- intense: charge critique + stress/urgence; météo/chaleur/orage peuvent accentuer; musique forte peut soutenir.
- pumped: sport/compétition imminent, musique très énergique; privilégier si activité physique est au centre.
- tired: <5h ou dette de sommeil marquée, peu de contraintes; si contraintes élevées, reste sur hard_work.

### CAS PARTICULIERS ET CONTRADICTIONS
- Sommeil très court + social positif: choisis confident si obligations sociales essentielles, sinon tired/chill.
- Agenda créatif + musique tristounette: reste sur creative si sommeil/météo OK; n’ajuste à melancholy que si absence de contraintes et valence très basse.
- Sport prévu mais météo très mauvaise: pumped si indoor; sinon energetic/chill selon fatigue.
- Données manquantes: utilise agenda comme ancre, sommeil comme modérateur, météo/musique comme affinement.

### RÈGLES DE PRIORISATION
- Si pré-analyse existe : pars du TOP 1 comme baseline et ne le changes que si un signal fort le contredit.
- Signal critique (deadline, sport intense, <5h de sommeil) > reste.
- Si signaux contradictoires, privilégie sommeil + agenda, puis ajuste avec météo (modère énergie) et musique (finesse du ton).
- Si données manquantes, reste prudent :
    * agenda chargé → hard_work ;
    * agenda léger → chill ;
    * social sans info énergie → confident ou chill selon ton météo/musique.
- Pas de justification dans la sortie : réponds uniquement le mood choisi parmi creative, hard_work, confident, chill, energetic, melancholy, intense, pumped, tired.

### SORTIE ATTENDUE
Renvoie uniquement l'un des moods autorisés : creative, hard_work, confident, chill, energetic, melancholy, intense, pumped, tired.
Pas d'explication, juste le mot.
"""

    def build_afternoon_prompt(self, historical_moods: str, calendar_summary: str,
                         weather_summary: str, music_summary: str,
                         preprocessor_analysis: Optional[Dict] = None) -> str:
        """Afternoon prompt (14h): new, streamlined layout for evening + tomorrow morning."""

        sleep_dict = self.sleep.to_dict()

        def format_preproc(pre: Optional[Dict]) -> str:
            if not pre:
                return "Aucune pré-analyse disponible (raisonne à partir des données brutes)."
            weights = pre.get('source_weights', {})
            top = pre.get('top_moods', [])
            weights_str = ", ".join([f"{k}:{int(v*100)}%" for k, v in weights.items()])
            top_str = " / ".join([f"{m if isinstance(m, str) else m}:{score:.1f}" for m, score in top[:3]])
            return f"Poids sources: {weights_str}\nTop pré-analyse: {top_str}"

        return f"""
### RÔLE
Tu es une IA de mood-triage. Ta sortie est **un seul mot** (mood autorisé) en minuscules.

### CONTEXTE D'EXÉCUTION (APRES-MIDI - 14h)
- Jour / date : {self.temporal.weekday_str} {self.temporal.now.strftime('%d/%m')}
- Heure locale : {self.temporal.execution_time_str}
- Portée : Prévision pour ce soir et demain matin.
- Historique moods : {historical_moods if historical_moods else 'Non fourni'}

### PRÉ-ANALYSE (PRIORITAIRE SI PRÉSENTE)
{format_preproc(preprocessor_analysis)}

### DONNÉES BRUTES (ne pas inventer)
- Agenda (reste de la journée + demain matin) :
{calendar_summary}
- Sommeil (nuit dernière) : coucher {sleep_dict['bedtime']} / réveil {sleep_dict['wake_time']} / durée {sleep_dict['sleep_hours']}h
- Météo : {weather_summary}
- Musique / historique récent :
{music_summary}

### MÉTHODE (RAISONNE EN 4 ÉTAPES)
1) Agenda restant + social prévu ce soir : charge haute (livrable, déplacement, obligations sociales lourdes) → hard_work/intense ; soirée sociale légère/positive → confident/energetic ; sport prévu → pumped/energetic ; soirée calme sans contrainte → chill/creative.
2) Sommeil de la nuit dernière : <5h = fatigue forte, 5-7h = légère, 7-9h = neutre, >9h = repos/chill. Si sommeil très court + charge ce soir → hard_work mais énergie basse (tired si charge faible). Sommeil bon + soirée libre → chill ou creative.
3) Météo de la soirée : pluie/froid → réduit énergie et moral (monte melancholy/tired/chill) ; ciel clair/agréable → monte confident/energetic/pumped ; chaleur forte peut fatiguer si déjà chargé.
4) Musique du jour : énergie/tempo/valence. Haute énergie + valence haute → pumped/energetic/confident. Énergie basse + valence basse → melancholy/tired. Si musique contredit agenda+sommeil, garde agenda+sommeil comme ancre et n'ajuste que légèrement.

### GUIDE DE SÉLECTION DU MOOD (RÈGLES CONCRÈTES)
- creative: soirée libre, activités créatives, sommeil ok (≥7h), météo neutre/agréable.
- hard_work: livrables à finir ce soir, obligations fortes; même si fatigue, le devoir prime (tired seulement si charge faible).
- confident: social positif (amis, présentation), météo agréable; musique haute valence/énergie.
- chill: soirée de repos sans contrainte; sommeil long ou besoin de récupération; météo maussade.
- energetic: activité légère et dynamique, sommeil ok, météo agréable; musique énergique.
- melancholy: faible valence musicale + mauvais temps + peu de contraintes; éviter si obligations.
- intense: urgence/pression ce soir; musique très énergétique OK; météo extrême peut amplifier.
- pumped: sport/compétition imminent; priorité si activité physique centrale.
- tired: <5h ou dette de sommeil; si obligations fortes, bascule vers hard_work.

### CAS PARTICULIERS ET CONTRADICTIONS
- Fatigue forte + événement social important: confident si impératif, sinon tired/chill.
- Travail à finir + musique très calme: garde hard_work; musique n’inverse pas l’ancre.
- Sortie prévue mais météo très mauvaise: energetic si motivation forte, sinon chill/melancholy selon valence.
- Données manquantes: agenda comme ancre, sommeil modère, météo/musique affinent.

### RÈGLES DE PRIORISATION
- Si pré-analyse existe : pars du TOP 1 comme baseline et ne le changes que si un signal fort le contredit.
- Signal critique (deadline ce soir, sport intense, <5h sommeil) > reste.
- Signaux mixtes : priorité sommeil + agenda, puis météo (modère énergie) et musique (affine le ton).
- Données manquantes :
    * soirée chargée → hard_work ;
    * soirée légère → chill ;
    * social prévu mais énergie inconnue → confident ou chill selon météo/musique.
- Pas de justification dans la sortie : réponds uniquement le mood choisi parmi creative, hard_work, confident, chill, energetic, melancholy, intense, pumped, tired.

### SORTIE ATTENDUE
Renvoie uniquement l'un des moods autorisés : creative, hard_work, confident, chill, energetic, melancholy, intense, pumped, tired.
Pas d'explication, juste le mot.
"""


# ============================================================================
# MOOD PREDICTION
# ============================================================================

def _extract_valid_mood(response_text: str) -> Optional[str]:
    """
    Extracts a valid mood from response text.

    Args:
        response_text: Raw response from AI model

    Returns:
        Valid mood string if found, None otherwise
    """
    cleaned = response_text.strip().lower().replace(".", "").replace("\n", "")

    for mood in VALID_MOODS:
        if mood in cleaned:
            return mood

    return None


def _try_model(model_name: str, prompt: str) -> Optional[str]:
    """
    Attempts to get mood prediction from a specific model.

    Args:
        model_name: Gemini model name
        prompt: Mood prediction prompt

    Returns:
        Valid mood if successful, None otherwise

    Raises:
        Exception: If model call fails
    """
    try:
        logger.info(f"[AI] Tentative avec modèle: {model_name}")
        model = genai.GenerativeModel(model_name)
        response = model.generate_content(prompt)
        mood = _extract_valid_mood(response.text)

        if mood:
            logger.info(f"[OK] Modèle {model_name} a répondu: {mood}")
            return mood

        logger.warning(f"[WARN] Réponse invalide de {model_name}: {response.text}")
        return None

    except Exception as e:
        logger.debug(f"[WARN] Erreur avec {model_name}: {e}")
        return None


# ============================================================================
# PRE-PROCESSING & ANALYSIS
# ============================================================================

def preprocess_context_data(
    calendar_events: List[Dict],
    sleep_hours: float,
    bedtime: str,
    wake_time: str,
    weather: str,
    temperature: Optional[float],
    music_stats: Dict[str, float],
    execution_time: datetime
) -> Dict[str, Any]:
    """
    Pre-processes all context data before sending to AI.

    This function analyzes calendar, sleep, weather, and music data independently
    to score mood signals, allowing visibility and control over the prediction process.

    Args:
        calendar_events: List of calendar events
        sleep_hours: Total sleep hours
        bedtime: Bedtime string
        wake_time: Wake time string
        weather: Weather description
        temperature: Temperature in Celsius
        music_stats: Dict with 'valence', 'energy', 'tempo', 'danceability'
        execution_time: Current datetime

    Returns:
        Dict with complete pre-processed analysis
    """
    executor_type = get_execution_type(execution_time.hour)
    
    # Extract music features with defaults
    valence = music_stats.get('valence', 0.5)
    energy = music_stats.get('energy', 0.5)
    tempo = music_stats.get('tempo', 100)
    danceability = music_stats.get('danceability', 0.5)

    # Run complete analysis
    analyzer = MoodDataAnalyzer()
    analysis = analyzer.analyze(
        calendar_events=calendar_events,
        sleep_hours=sleep_hours,
        bedtime=bedtime,
        wake_time=wake_time,
        weather=weather,
        temperature=temperature,
        valence=valence,
        energy=energy,
        tempo=tempo,
        danceability=danceability,
        current_time=execution_time,
        execution_type=executor_type.value
    )

    # Log results
    log_analysis(analysis, logger)
    
    return analysis


def predict_mood_with_cascade(prompt: str, dry_run: bool = False) -> str:
    """
    Predicts mood using cascade fallback through multiple models.

    This implements a resilient model selection strategy:
    1. Tries preferred models in order
    2. Returns first successful response
    3. Falls back to 'chill' if all models fail

    Args:
        prompt: Mood prediction prompt
        dry_run: If True, returns 'dry_run' without API calls

    Returns:
        Predicted mood string

    Raises:
        ValueError: If GEMINI_API_KEY is not set
    """
    if dry_run:
        logger.info("Dry run mode: Skipping Gemini API call")
        return "dry_run"

    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        raise ValueError("GEMINI_API_KEY environment variable not set")

    genai.configure(api_key=api_key)

    for model_name in PREFERRED_MODELS:
        mood = _try_model(model_name, prompt)
        if mood:
            return mood

    logger.error("[ERROR] Tous les modèles ont échoué. Utilisation du mood par défaut: chill")
    return "chill"


# ============================================================================
# PUBLIC API
# ============================================================================

def construct_prompt(
    historical_moods: str,
    music_summary: str,
    calendar_summary: str,
    weather_summary: str,
    sleep_info: Optional[Dict[str, any]] = None,
    execution_time: Optional[datetime] = None,
    preprocessor_analysis: Optional[Dict] = None
) -> str:
    """
    Constructs a contextual mood prediction prompt.

    This function generates a comprehensive prompt that guides Gemini AI
    to predict user mood based on multiple contextual signals. The prompt
    automatically differentiates between morning (3am) and afternoon (14h)
    execution contexts.

    Args:
        historical_moods: String representation of historical mood patterns
        music_summary: Summary of listening history with Spotify features
        calendar_summary: String of upcoming calendar events
        weather_summary: Weather forecast summary
        sleep_info: Optional dict with keys: bedtime, wake_time, sleep_hours
        execution_time: Optional datetime for reproducibility (defaults to now)
        preprocessor_analysis: Optional pre-analysis results from MoodDataAnalyzer

    Returns:
        Complete prompt string ready for Gemini

    Raises:
        ValueError: If required arguments are invalid
    """
    missing_elements = []
    # Empty list is valid (dry_run mode), only warn if None or contains Error
    if historical_moods is None or (isinstance(historical_moods, str) and ("Error" in historical_moods or "Erreur" in historical_moods)):
        missing_elements.append("historical_moods")
    if not music_summary or "Error" in music_summary or "Erreur" in music_summary:
        missing_elements.append("music_summary")
    if not calendar_summary or "Error" in calendar_summary or "Erreur" in calendar_summary:
        missing_elements.append("calendar_summary")
    if not weather_summary or weather_summary == "Non disponible" or "Error" in weather_summary:
        missing_elements.append("weather_summary")
    
    if missing_elements:
        logger.warning(f"[WARN] Missing context summaries: {', '.join(missing_elements)}")

    execution_time = execution_time or datetime.now()
    sleep_info = sleep_info or {}

    temporal_context = TemporalContext(execution_time)
    sleep_context = SleepContext(
        bedtime=sleep_info.get("bedtime"),
        wake_time=sleep_info.get("wake_time"),
        sleep_hours=sleep_info.get("sleep_hours")
    )

    builder = PromptBuilder(temporal_context, sleep_context)
    
    # Choose appropriate prompt builder based on execution type
    if temporal_context.execution_type == ExecutionType.MATIN:
        return builder.build_morning_prompt(
            historical_moods, calendar_summary, weather_summary, music_summary,
            preprocessor_analysis
        )
    else:
        return builder.build_afternoon_prompt(
            historical_moods, calendar_summary, weather_summary, music_summary,
            preprocessor_analysis
        )


def predict_mood(
    historical_moods: str,
    music_summary: str,
    calendar_summary: str,
    weather_summary: str = "Non disponible",
    sleep_info: Optional[Dict[str, any]] = None,
    dry_run: bool = False,
    music_metrics: Optional[Dict[str, any]] = None,
    calendar_events: Optional[List[Dict[str, any]]] = None
) -> str | Dict[str, str]:
    """
    Predicts user mood for upcoming period.

    Generates a contextual prompt and uses Gemini AI with cascade fallback
    to predict mood. Execution type (morning/afternoon) is automatically
    determined by current time.
    
    NOW INCLUDES: Pre-processing analysis as priority signal in prompt.

    Args:
        historical_moods: Historical mood patterns
        music_summary: Music listening history
        calendar_summary: Calendar events
        weather_summary: Weather forecast (default "Non disponible")
        sleep_info: Optional sleep information
        dry_run: If True, returns dict with mood and prompt for inspection

    Returns:
        str: Predicted mood (one of VALID_MOODS) in production
        dict: {"mood": "dry_run", "prompt": prompt_text} in dry_run mode

    Raises:
        ValueError: If GEMINI_API_KEY not set
    """
    
    # NEW: Run pre-processing analysis
    preprocessor_analysis = None
    try:
        # Extract necessary data (with defaults for missing data)
        execution_time = datetime.now()
        
        # Use calendar_events parameter if provided, else empty list
        events_list = calendar_events if calendar_events else []
        
        # Parse weather if available
        weather_desc = weather_summary if weather_summary != "Non disponible" else "Unknown"
        weather_temp = None  # TODO: Extract from weather_summary in future
        
        # Use sleep info if available
        sleep_hours = sleep_info.get('sleep_hours', 7.5) if sleep_info else 7.5
        bedtime = sleep_info.get('bedtime', '23:00') if sleep_info else '23:00'
        wake_time = sleep_info.get('wake_time', '07:00') if sleep_info else '07:00'
        
        # Music features (extract from music_metrics or use defaults)
        if music_metrics:
            music_valence = music_metrics.get('avg_valence', 0.5)
            music_energy = music_metrics.get('avg_energy', 0.5)
            music_tempo = int(music_metrics.get('avg_tempo', 120))
            music_danceability = 0.5  # Not in avg metrics, use default
        else:
            music_valence = 0.5
            music_energy = 0.5
            music_tempo = 120
            music_danceability = 0.5
        
        # Run analysis
        analyzer = MoodDataAnalyzer()
        preprocessor_analysis = analyzer.analyze(
            calendar_events=events_list,
            sleep_hours=sleep_hours,
            bedtime=bedtime,
            wake_time=wake_time,
            weather=weather_desc,
            temperature=weather_temp,
            valence=music_valence,
            energy=music_energy,
            tempo=music_tempo,
            danceability=music_danceability,
            current_time=execution_time,
            execution_type='APRES_MIDI' if execution_time.hour >= 12 else 'MATIN'
        )
        
        # Log pre-processor prediction
        top_mood = preprocessor_analysis['top_moods'][0][0]
        top_mood_str = top_mood if isinstance(top_mood, str) else top_mood
        logger.info(f"[PRE-PROCESSOR] Top prediction: {top_mood_str.upper()} (score: {preprocessor_analysis['top_moods'][0][1]:.1f})")
        logger.info(f"[PRE-PROCESSOR] Weights: Agenda {preprocessor_analysis['source_weights']['agenda']*100:.0f}%, Sleep {preprocessor_analysis['source_weights']['sleep']*100:.0f}%, Weather {preprocessor_analysis['source_weights']['weather']*100:.0f}%")
        
    except Exception as preprocess_error:
        logger.warning(f"[WARN] Pre-processing failed: {preprocess_error}")
        logger.debug(f"Pre-processing error details: {preprocess_error}", exc_info=True)
        preprocessor_analysis = None
    
    # Build prompt with pre-processor analysis
    prompt = construct_prompt(
        historical_moods, music_summary, calendar_summary, weather_summary, 
        sleep_info, preprocessor_analysis=preprocessor_analysis
    )

    if dry_run:
        return {"mood": "dry_run", "prompt": prompt}

    ai_mood = predict_mood_with_cascade(prompt, dry_run=False)
    
    # Compare with pre-processor if available
    if preprocessor_analysis:
        preprocessed_mood = preprocessor_analysis['top_moods'][0][0]
        preprocessed_mood_str = preprocessed_mood if isinstance(preprocessed_mood, str) else preprocessed_mood
        
        if preprocessed_mood_str != ai_mood:
            logger.info(f"[COMPARISON] Pre-processor predicted '{preprocessed_mood_str}', AI predicted '{ai_mood}'")
        else:
            logger.info(f"[COMPARISON] Pre-processor and AI agree: {ai_mood}")
    
    return ai_mood
