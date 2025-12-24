import 'package:intl/intl.dart';

/// Lightweight Dart port of `src/core/analyzer.py` used on the backend.
/// Keeps the same weights, categories and veto logic so mobile live
/// predictions mirror the backend deterministic pre-processor.
class MoodAnalyzerConfig {
  // Agenda keywords
  static const List<String> sportIntense = [
    'crossfit', 'compétition', 'competition', 'hiit', 'marathon', 'triathlon',
    'match', 'rugby', 'football', 'basket', 'boxe'
  ];
  static const List<String> sportModerate = [
    'run', 'gym', 'yoga', 'vélo', 'velo', 'natation', 'fitness', 'sport',
    'musculation', 'train', 'training', 'entraînement', 'entrainement',
    'pilates'
  ];
  static const List<String> workCreative = [
    'design', 'dev', 'développement', 'developpement', 'art', 'création',
    'creation', 'creative', 'projet perso', 'coding', 'dessin', 'photo',
    'musique', 'machine', 'conception', 'algo', 'algorithmique',
    'programmation'
  ];
  static const List<String> workFocusHigh = [
    'exam', 'examen', 'partiel', 'soutenance', 'certification', 'concours',
    'final', 'controle', 'contrôle'
  ];
  static const List<String> workFocusNormal = [
    'réunion', 'reunion', 'présentation', 'presentation', 'projet', 'étude',
    'etude', 'travail', 'meeting', 'rendu', 'deadline', 'cm', 'td',
    'cours magistral', 'travaux dirigés', 'tp', 'travaux pratiques',
    'comptabilité', 'comptabilite', 'compta', 'gestion', 'finance',
    'eco-gestion', 'eco gestion', 'miage', 'business english', 'english',
    'système', 'systeme', 'strat', 'stratégie', 'strategie'
  ];
  static const List<String> socialActive = [
    'fête', 'fete', 'soirée', 'soiree', 'concert', 'bar', 'club', 'anniv',
    'anniversaire', 'party', 'festival', 'sortie', 'boîte', 'boite'
  ];
  static const List<String> socialCalm = [
    'resto', 'restaurant', 'café', 'cafe', 'apéro', 'apero', 'dîner',
    'diner', 'déjeuner', 'dejeuner', 'brunch', 'repas', 'bouffe'
  ];

  // Sleep thresholds (hours)
  static const double sleepCritical = 6.0;
  static const double sleepPoor = 7.0;
  static const double sleepInadequate = 8.0;
  static const double sleepOptimalMin = 8.5;

  // Weather keywords
  static const List<String> weatherRain = [
    'orage', 'storm', 'tempête', 'tempete', 'pluie', 'rain', 'pluvieux'
  ];
  static const List<String> weatherCloudy = [
    'grisaille', 'gris', 'overcast', 'nuageux', 'cloudy'
  ];
  static const List<String> weatherSunny = [
    'soleil', 'sunny', 'ensoleillé', 'ensolleile', 'clear'
  ];

  // Music thresholds
  static const double energyHigh = 0.7;

  // Source weights
  static const double weightAgenda = 0.35;
  static const double weightSleep = 0.35;
  static const double weightWeather = 0.15;
  static const double weightMusic = 0.10;
  static const double weightTime = 0.05;
}

enum SignalStrength { veryWeak, weak, neutral, moderate, strong, veryStrong }

enum MoodCategory {
  creative,
  hardWork,
  confident,
  chill,
  energetic,
  melancholy,
  intense,
  pumped,
  tired,
}

class MoodSignal {
  MoodSignal(this.mood, this.strength);
  final MoodCategory mood;
  final SignalStrength strength;
}

class MoodSourceSignal {
  MoodSourceSignal(this.signal, this.source);
  final MoodSignal signal;
  final String source;
}

class AnalyzerSection {
  AnalyzerSection({
    required this.moodSignals,
    required this.analysis,
    this.veto = false,
    this.totalPressure = 0,
  });

  final List<MoodSignal> moodSignals;
  final String analysis;
  final bool veto;
  final double totalPressure;
}

class AnalyzerResult {
  AnalyzerResult({
    required this.topMood,
    required this.moodScores,
    required this.sections,
  });

  final String topMood;
  final Map<String, double> moodScores;
  final Map<String, AnalyzerSection> sections;
}

class AgendaAnalyzer {
  static AnalyzerSection analyzeEvents(
    List<Map<String, dynamic>> events,
    DateTime now,
  ) {
    final today = DateTime(now.year, now.month, now.day);
    final List<MoodSignal> signals = [];
    final List<String> todayEvents = [];
    final List<String> upcomingStress = [];
    double totalPressure = 0;

    for (final event in events) {
      final summary = (event['summary'] ?? '').toString().toLowerCase();
      final start = (event['start'] ?? {}) as Map<String, dynamic>;

      DateTime? eventDate;
      DateTime? eventDateTime;

      try {
        if (start.containsKey('dateTime')) {
          final raw = start['dateTime'].toString().replaceAll('Z', '+00:00');
          eventDateTime = DateTime.parse(raw);
          eventDate = DateTime(eventDateTime.year, eventDateTime.month, eventDateTime.day);
        } else if (start.containsKey('date')) {
          final raw = start['date'].toString();
          eventDate = DateTime.parse(raw);
        }
      } catch (_) {
        continue;
      }

      eventDate ??= today;

      final daysDiff = eventDate.difference(today).inDays;
      if (daysDiff > 0 && daysDiff <= 2) {
        if (MoodAnalyzerConfig.workFocusHigh.any(summary.contains)) {
          upcomingStress.add('$summary (in ${daysDiff}d)');
          signals.add(MoodSignal(MoodCategory.hardWork, SignalStrength.strong));
          signals.add(MoodSignal(MoodCategory.intense, SignalStrength.moderate));
        }
        continue;
      }

      if (eventDate.isAfter(today) || eventDate.isBefore(today)) {
        continue;
      }

      final hasTime = eventDateTime != null;
      if (hasTime && eventDateTime!.isBefore(now)) {
        if (MoodAnalyzerConfig.workFocusHigh.any(summary.contains)) {
          signals.add(MoodSignal(MoodCategory.tired, SignalStrength.veryStrong));
          todayEvents.add('[DONE] ${summary.substring(0, summary.length.clamp(0, 30))}');
        }
        continue;
      }

      if (MoodAnalyzerConfig.sportIntense.any(summary.contains)) {
        signals.add(MoodSignal(MoodCategory.pumped, SignalStrength.veryStrong));
        totalPressure += 2.0;
      } else if (MoodAnalyzerConfig.sportModerate.any(summary.contains)) {
        signals.add(MoodSignal(MoodCategory.energetic, SignalStrength.strong));
        totalPressure += 1.0;
      } else if (MoodAnalyzerConfig.workCreative.any(summary.contains)) {
        signals.add(MoodSignal(MoodCategory.creative, SignalStrength.strong));
        totalPressure += 1.0;
      } else if (MoodAnalyzerConfig.workFocusHigh.any(summary.contains)) {
        signals.add(MoodSignal(MoodCategory.intense, SignalStrength.veryStrong));
        signals.add(MoodSignal(MoodCategory.hardWork, SignalStrength.strong));
        totalPressure += 4.0;
      } else if (MoodAnalyzerConfig.workFocusNormal.any(summary.contains)) {
        signals.add(MoodSignal(MoodCategory.hardWork, SignalStrength.moderate));
        totalPressure += 0.5;
      } else if (MoodAnalyzerConfig.socialActive.any(summary.contains)) {
        signals.add(MoodSignal(MoodCategory.confident, SignalStrength.strong));
        signals.add(MoodSignal(MoodCategory.energetic, SignalStrength.moderate));
        totalPressure += 1.0;
      } else if (MoodAnalyzerConfig.socialCalm.any(summary.contains)) {
        signals.add(MoodSignal(MoodCategory.chill, SignalStrength.strong));
        totalPressure += 0.5;
      } else {
        signals.add(MoodSignal(MoodCategory.confident, SignalStrength.moderate));
        totalPressure += 0.5;
      }

      todayEvents.add(summary.substring(0, summary.length.clamp(0, 30)));
    }

    return AnalyzerSection(
      moodSignals: signals,
      analysis: 'Pressure: ${totalPressure.toStringAsFixed(1)} | Upcoming Stress: ${upcomingStress.length}',
      totalPressure: totalPressure,
    );
  }
}

class SleepAnalyzer {
  static AnalyzerSection analyzeSleep(
    double sleepHours,
    String bedtime,
    String wakeTime,
    String executionType,
  ) {
    final signals = <MoodSignal>[];
    var quality = 'UNKNOWN';
    var veto = false;

    if (sleepHours <= 0) {
      signals.add(MoodSignal(MoodCategory.chill, SignalStrength.moderate));
      quality = 'NO_DATA';
    } else if (sleepHours < MoodAnalyzerConfig.sleepCritical) {
      signals.add(MoodSignal(MoodCategory.tired, SignalStrength.veryStrong));
      quality = 'CRITICAL_VETO';
      veto = true;
    } else if (sleepHours < MoodAnalyzerConfig.sleepPoor) {
      signals.add(MoodSignal(MoodCategory.tired, SignalStrength.strong));
      signals.add(MoodSignal(MoodCategory.intense, SignalStrength.moderate));
      quality = 'POOR';
    } else if (sleepHours < MoodAnalyzerConfig.sleepInadequate) {
      signals.add(MoodSignal(MoodCategory.tired, SignalStrength.moderate));
      quality = 'INADEQUATE';
    } else if (sleepHours >= MoodAnalyzerConfig.sleepOptimalMin) {
      signals.add(MoodSignal(MoodCategory.energetic, SignalStrength.strong));
      signals.add(MoodSignal(MoodCategory.confident, SignalStrength.strong));
      quality = 'OPTIMAL';
    } else {
      signals.add(MoodSignal(MoodCategory.chill, SignalStrength.moderate));
      quality = 'OK';
    }

    return AnalyzerSection(
      moodSignals: signals,
      analysis: '${sleepHours.toStringAsFixed(1)}h - $quality${veto ? ' [VETO]' : ''}',
      veto: veto,
    );
  }
}

class WeatherAnalyzer {
  static AnalyzerSection analyzeWeather(
    String summary, {
    double? temperature,
    String executionType = 'UNKNOWN',
  }) {
    final lower = summary.toLowerCase();
    final signals = <MoodSignal>[];

    final isRain = MoodAnalyzerConfig.weatherRain.any(lower.contains);
    final isCloudy = MoodAnalyzerConfig.weatherCloudy.any(lower.contains);
    final isSunny = MoodAnalyzerConfig.weatherSunny.any(lower.contains);

    if (isRain) {
      if (executionType == 'MATIN') {
        signals.add(MoodSignal(MoodCategory.melancholy, SignalStrength.veryStrong));
        signals.add(MoodSignal(MoodCategory.intense, SignalStrength.strong));
      } else {
        signals.add(MoodSignal(MoodCategory.melancholy, SignalStrength.moderate));
        signals.add(MoodSignal(MoodCategory.chill, SignalStrength.moderate));
      }
    } else if (isCloudy) {
      signals.add(MoodSignal(MoodCategory.melancholy, SignalStrength.moderate));
    } else if (isSunny) {
      signals.add(MoodSignal(MoodCategory.confident, SignalStrength.strong));
      signals.add(MoodSignal(MoodCategory.pumped, SignalStrength.moderate));
    }

    return AnalyzerSection(
      moodSignals: signals,
      analysis: summary,
    );
  }
}

class MusicAnalyzer {
  static AnalyzerSection analyzeMusic(
    double valence,
    double energy,
    int tempo,
    double danceability,
  ) {
    final signals = <MoodSignal>[];
    var vibe = 'FLOW';

    if (energy > MoodAnalyzerConfig.energyHigh) {
      signals.add(MoodSignal(MoodCategory.pumped, SignalStrength.strong));
      signals.add(MoodSignal(MoodCategory.energetic, SignalStrength.strong));
      vibe = 'BOOST';
    } else if (energy > 0.5) {
      signals.add(MoodSignal(MoodCategory.energetic, SignalStrength.moderate));
      vibe = 'VIBE';
    } else {
      signals.add(MoodSignal(MoodCategory.chill, SignalStrength.strong));
      vibe = 'CHILL';
    }

    if (valence > 0.6) {
      signals.add(MoodSignal(MoodCategory.confident, SignalStrength.moderate));
    }
    if (danceability > 0.7) {
      signals.add(MoodSignal(MoodCategory.creative, SignalStrength.moderate));
    }

    return AnalyzerSection(
      moodSignals: signals,
      analysis: 'V:${valence.toStringAsFixed(2)} E:${energy.toStringAsFixed(2)} - $vibe',
    );
  }
}

class TimeAnalyzer {
  static AnalyzerSection analyzeTime(DateTime now, String executionType) {
    final signals = <MoodSignal>[];
    final weekday = now.weekday % 7; // 1=Mon..7=Sun in Dart
    final dayIdx = weekday == 7 ? 0 : weekday - 1; // align with python list
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final dayName = days[dayIdx.clamp(0, 6)];

    if (dayIdx == 0) {
      signals.add(MoodSignal(MoodCategory.energetic, SignalStrength.strong));
      signals.add(MoodSignal(MoodCategory.pumped, SignalStrength.moderate));
    } else if (dayIdx == 4) {
      signals.add(MoodSignal(MoodCategory.tired, SignalStrength.moderate));
      signals.add(MoodSignal(MoodCategory.chill, SignalStrength.strong));
    } else if (dayIdx == 5 || dayIdx == 6) {
      signals.add(MoodSignal(MoodCategory.chill, SignalStrength.strong));
    }

    return AnalyzerSection(
      moodSignals: signals,
      analysis: '$dayName ${DateFormat('HH').format(now)}h',
    );
  }
}

class MoodDataAnalyzer {
  AnalyzerResult analyze({
    required List<Map<String, dynamic>> calendarEvents,
    required double sleepHours,
    required String bedtime,
    required String wakeTime,
    required String weather,
    double? temperature,
    required double valence,
    required double energy,
    required int tempo,
    required double danceability,
    required DateTime currentTime,
    required String executionType,
  }) {
    final agenda = AgendaAnalyzer.analyzeEvents(calendarEvents, currentTime);
    final sleep = SleepAnalyzer.analyzeSleep(sleepHours, bedtime, wakeTime, executionType);
    final weatherSection = WeatherAnalyzer.analyzeWeather(
      weather,
      temperature: temperature,
      executionType: executionType,
    );
    final music = MusicAnalyzer.analyzeMusic(valence, energy, tempo, danceability);
    final time = TimeAnalyzer.analyzeTime(currentTime, executionType);

    final allSignals = <MoodSourceSignal>[];
    void push(List<MoodSignal> signals, String source) {
      for (final s in signals) {
        allSignals.add(MoodSourceSignal(s, source));
      }
    }

    push(agenda.moodSignals, 'agenda');
    push(sleep.moodSignals, 'sleep');
    push(weatherSection.moodSignals, 'weather');
    push(music.moodSignals, 'music');
    push(time.moodSignals, 'time');

    final moodScores = _scoreMoods(
      allSignals,
      vetoSleep: sleep.veto,
    );

    final sorted = moodScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topMood = sorted.isNotEmpty ? sorted.first.key : 'balanced';

    return AnalyzerResult(
      topMood: topMood,
      moodScores: moodScores,
      sections: {
        'agenda': agenda,
        'sleep': sleep,
        'weather': weatherSection,
        'music': music,
        'time': time,
      },
    );
  }

  Map<String, double> _scoreMoods(
    List<MoodSourceSignal> signals, {
    bool vetoSleep = false,
  }) {
    final scores = {
      for (final mood in MoodCategory.values) mood.name: 0.0,
    };

    const strengthWeights = {
      SignalStrength.veryWeak: -30.0,
      SignalStrength.weak: -10.0,
      SignalStrength.neutral: 0.0,
      SignalStrength.moderate: 5.0,
      SignalStrength.strong: 10.0,
      SignalStrength.veryStrong: 30.0,
    };

    const sourceWeights = {
      'agenda': MoodAnalyzerConfig.weightAgenda,
      'sleep': MoodAnalyzerConfig.weightSleep,
      'weather': MoodAnalyzerConfig.weightWeather,
      'music': MoodAnalyzerConfig.weightMusic,
      'time': MoodAnalyzerConfig.weightTime,
    };

    for (final entry in signals) {
      final base = strengthWeights[entry.signal.strength] ?? 0.0;
      final weight = sourceWeights[entry.source] ?? 1.0;
      scores.update(entry.signal.mood.name, (v) => v + base * weight);
    }

    final minScore = scores.values.isNotEmpty ? scores.values.reduce((a, b) => a < b ? a : b) : 0.0;
    if (minScore < 0) {
      scores.updateAll((key, value) => value - minScore);
    }

    if (vetoSleep) {
      final maxScore = scores.values.isNotEmpty ? scores.values.reduce((a, b) => a > b ? a : b) : 100.0;
      scores['tired'] = maxScore * 1.5;
    }

    return scores;
  }
}
