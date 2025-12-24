import 'package:flutter/foundation.dart';

/// Configuration constants for Mood Analyzer
/// Matches src/core/analyzer.py
class MoodAnalyzerConfig {
  // === AGENDA KEYWORDS ===
  static const List<String> sportIntense = [
    'crossfit',
    'compétition',
    'competition',
    'hiit',
    'marathon',
    'triathlon',
    'match',
    'rugby',
    'football',
    'basket',
    'boxe'
  ];
  static const List<String> sportModerate = [
    'run',
    'gym',
    'yoga',
    'vélo',
    'velo',
    'natation',
    'fitness',
    'sport',
    'musculation',
    'train',
    'training',
    'entraînement',
    'entrainement',
    'pilates'
  ];
  static const List<String> workCreative = [
    'design',
    'dev',
    'développement',
    'developpement',
    'art',
    'création',
    'creation',
    'creative',
    'projet perso',
    'coding',
    'dessin',
    'photo',
    'musique',
    'machine',
    'conception',
    'algo',
    'algorithmique',
    'programmation'
  ];
  static const List<String> workFocusHigh = [
    'exam',
    'examen',
    'partiel',
    'soutenance',
    'certification',
    'concours',
    'final',
    'controle',
    'contrôle'
  ];
  static const List<String> workFocusNormal = [
    'réunion',
    'reunion',
    'présentation',
    'presentation',
    'projet',
    'étude',
    'etude',
    'travail',
    'meeting',
    'rendu',
    'deadline',
    'cm',
    'td',
    'cours magistral',
    'travaux dirigés',
    'tp',
    'travaux pratiques',
    'comptabilité',
    'comptabilite',
    'compta',
    'gestion',
    'finance',
    'eco-gestion',
    'eco gestion',
    'miage',
    'business english',
    'english',
    'système',
    'systeme',
    'strat',
    'stratégie',
    'strategie'
  ];
  static const List<String> socialActive = [
    'fête',
    'fete',
    'soirée',
    'soiree',
    'concert',
    'bar',
    'club',
    'anniv',
    'anniversaire',
    'party',
    'festival',
    'sortie',
    'boîte',
    'boite'
  ];
  static const List<String> socialCalm = [
    'resto',
    'restaurant',
    'café',
    'cafe',
    'apéro',
    'apero',
    'dîner',
    'diner',
    'déjeuner',
    'dejeuner',
    'brunch',
    'repas',
    'bouffe'
  ];

  // === WEATHER KEYWORDS ===
  static const List<String> weatherRain = [
    'orage',
    'storm',
    'tempête',
    'tempete',
    'pluie',
    'rain',
    'pluvieux',
    '🌧️',
    '⛈️',
    '🌧',
    '⛈'
  ];
  static const List<String> weatherCloudy = [
    'grisaille',
    'gris',
    'overcast',
    'nuageux',
    'cloudy',
    '☁️',
    '☁',
    '⛅'
  ];
  static const List<String> weatherSunny = [
    'soleil',
    'sunny',
    'ensoleillé',
    'ensolleile',
    'clear',
    '☀️',
    '☀'
  ];

  // === THRESHOLDS ===
  static const double sleepCritical = 6.0;
  static const double sleepPoor = 7.0;
  static const double sleepInadequate = 8.0;
  static const double sleepOptimalMin = 8.5;

  static const double energyHigh = 0.7;
}

enum MoodCategory {
  creative,
  hardWork,
  confident,
  chill,
  energetic,
  melancholy,
  intense,
  pumped,
  tired
}

enum SignalStrength { veryWeak, weak, neutral, moderate, strong, veryStrong }

class MoodLogic {
  static double _getSignalScore(SignalStrength strength) {
    switch (strength) {
      case SignalStrength.veryWeak:
        return -30.0;
      case SignalStrength.weak:
        return -10.0;
      case SignalStrength.neutral:
        return 0.0;
      case SignalStrength.moderate:
        return 5.0;
      case SignalStrength.strong:
        return 10.0;
      case SignalStrength.veryStrong:
        return 30.0;
    }
  }

  /// Main Analysis Function
  static String analyze({
    required List<Map<String, dynamic>> calendarEvents,
    required double sleepHours,
    required String weather, // Emoji or description
    required double energyLevel, // User slider 0-1
    required double stressLevel, // User slider 0-1
    required double socialLevel, // User slider 0-1
    required Map<String, dynamic>? musicMetrics,
  }) {
    final scores = <String, double>{
      'creative': 0.0,
      'hard_work': 0.0,
      'confident': 0.0,
      'chill': 0.0,
      'energetic': 0.0,
      'melancholy': 0.0,
      'intense': 0.0,
      'pumped': 0.0,
      'tired': 0.0
    };

    void addScore(MoodCategory mood, SignalStrength strength,
        [double weight = 1.0]) {
      final key = mood
          .toString()
          .split('.')
          .last
          .replaceAll(RegExp(r'(?=[A-Z])'), '_')
          .toLowerCase();
      // Adjust key mapping if needed: hardWork -> hard_work
      final finalKey = key == 'hard_work' ? 'hard_work' : key;

      scores[finalKey] =
          (scores[finalKey] ?? 0) + (_getSignalScore(strength) * weight);
    }

    // 1. SLEEP ANALYSIS (Veto Logic)
    bool sleepVeto = false;
    if (sleepHours < MoodAnalyzerConfig.sleepCritical) {
      addScore(MoodCategory.tired, SignalStrength.veryStrong, 2.0);
      sleepVeto = true;
    } else if (sleepHours < MoodAnalyzerConfig.sleepPoor) {
      addScore(MoodCategory.tired, SignalStrength.strong);
    } else if (sleepHours >= MoodAnalyzerConfig.sleepOptimalMin) {
      addScore(MoodCategory.energetic, SignalStrength.strong);
      addScore(MoodCategory.confident, SignalStrength.strong);
    }

    // 2. AGENDA ANALYSIS
    for (var event in calendarEvents) {
      final summary = (event['summary'] as String? ?? '').toLowerCase();
      if (summary.isEmpty) continue;

      if (MoodAnalyzerConfig.sportIntense.any((k) => summary.contains(k))) {
        addScore(MoodCategory.pumped, SignalStrength.veryStrong);
      } else if (MoodAnalyzerConfig.sportModerate
          .any((k) => summary.contains(k))) {
        addScore(MoodCategory.energetic, SignalStrength.strong);
      } else if (MoodAnalyzerConfig.workCreative
          .any((k) => summary.contains(k))) {
        addScore(MoodCategory.creative, SignalStrength.strong);
      } else if (MoodAnalyzerConfig.workFocusHigh
          .any((k) => summary.contains(k))) {
        addScore(MoodCategory.intense, SignalStrength.veryStrong);
        addScore(MoodCategory.hardWork, SignalStrength.strong);
      } else if (MoodAnalyzerConfig.workFocusNormal
          .any((k) => summary.contains(k))) {
        addScore(MoodCategory.hardWork, SignalStrength.moderate);
      } else if (MoodAnalyzerConfig.socialActive
          .any((k) => summary.contains(k))) {
        addScore(MoodCategory.confident, SignalStrength.strong);
        addScore(MoodCategory.energetic, SignalStrength.moderate);
      } else if (MoodAnalyzerConfig.socialCalm
          .any((k) => summary.contains(k))) {
        addScore(MoodCategory.chill, SignalStrength.strong);
      }
    }

    // 3. WEATHER ANALYSIS
    final weatherLower = weather.toLowerCase();
    if (MoodAnalyzerConfig.weatherRain.any((k) => weatherLower.contains(k))) {
      addScore(MoodCategory.melancholy, SignalStrength.moderate);
      addScore(MoodCategory.chill, SignalStrength.moderate);
    } else if (MoodAnalyzerConfig.weatherCloudy
        .any((k) => weatherLower.contains(k))) {
      addScore(MoodCategory.melancholy, SignalStrength.moderate);
    } else if (MoodAnalyzerConfig.weatherSunny
        .any((k) => weatherLower.contains(k))) {
      addScore(MoodCategory.confident, SignalStrength.strong);
      addScore(MoodCategory.pumped, SignalStrength.moderate);
    }

    // 4. MUSIC ANALYSIS
    if (musicMetrics != null) {
      final energy = (musicMetrics['energy'] as num?)?.toDouble() ?? 0.5;
      final valence = (musicMetrics['valence'] as num?)?.toDouble() ?? 0.5;

      if (energy > 0.7) {
        addScore(MoodCategory.pumped, SignalStrength.strong);
        addScore(MoodCategory.energetic, SignalStrength.strong);
      } else if (energy < 0.4) {
        addScore(MoodCategory.chill, SignalStrength.strong);
      }

      if (valence > 0.7) {
        addScore(MoodCategory.confident, SignalStrength.moderate);
      }
    }

    // 5. USER METRICS (Adaptive Weights simulation)
    // Energy
    if (energyLevel > 0.7) {
      addScore(MoodCategory.energetic, SignalStrength.strong);
      addScore(MoodCategory.pumped, SignalStrength.moderate);
    } else if (energyLevel < 0.3) {
      addScore(MoodCategory.tired, SignalStrength.strong);
    }

    // Stress
    if (stressLevel > 0.7) {
      addScore(MoodCategory.intense, SignalStrength.strong);
      addScore(MoodCategory.hardWork, SignalStrength.moderate);
    } else if (stressLevel < 0.3) {
      addScore(MoodCategory.chill, SignalStrength.moderate);
    }

    // Social
    if (socialLevel > 0.7) {
      addScore(MoodCategory.confident, SignalStrength.strong);
    } else if (socialLevel < 0.3) {
      addScore(MoodCategory.melancholy, SignalStrength.moderate);
    }

    // 6. TIME ANALYSIS
    final hour = DateTime.now().hour;
    final weekday = DateTime.now().weekday;
    if (weekday == DateTime.monday) {
      addScore(MoodCategory.energetic, SignalStrength.moderate);
    } else if (weekday == DateTime.friday) {
      addScore(MoodCategory.tired, SignalStrength.moderate);
      addScore(MoodCategory.chill, SignalStrength.strong);
    }

    // VETO OVERRIDE
    if (sleepVeto) {
      // Find current max
      double maxScore = 0;
      if (scores.isNotEmpty) {
        maxScore = scores.values.reduce((a, b) => a > b ? a : b);
      }
      scores['tired'] = (maxScore > 0 ? maxScore : 10) * 1.5;
    }

    // Return Top Mood
    var topMood = 'chill';
    double topScore = -9999;

    scores.forEach((k, v) {
      if (v > topScore) {
        topScore = v;
        topMood = k;
      }
    });

    return topMood;
  }
}
