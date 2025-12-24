class MoodEntry {
  final String date;
  final double sleepHours;
  final double? energy;
  final double? stress;
  final double? social;
  final int steps;
  final String? location;
  final DateTime? lastUpdated;
  final String device;
  final String? moodSelected;
  final String? executionType;
  // Rich metadata for detailed analysis
  final String? geminiPrompt;
  final String? algoPrediction;
  final String? weatherSummary;
  final Map<String, dynamic>? feedbackMetrics;
  final Map<String, dynamic>? musicMetrics;
  final String? musicSummary;
  final String? calendarSummary;

  const MoodEntry({
    required this.date,
    required this.sleepHours,
    this.energy,
    this.stress,
    this.social,
    required this.steps,
    this.location,
    this.lastUpdated,
    required this.device,
    this.moodSelected,
    this.executionType,
    this.geminiPrompt,
    this.algoPrediction,
    this.weatherSummary,
    this.feedbackMetrics,
    this.musicMetrics,
    this.musicSummary,
    this.calendarSummary,
  });

  // Factory constructor for parsing JSON from DB
  factory MoodEntry.fromJson(Map<String, dynamic> json) {
    final resolvedLocation = (json['location'] ?? json['city']) as String?;

    return MoodEntry(
      date: json['date'] as String,
      sleepHours: (json['sleep_hours'] as num?)?.toDouble() ?? 0.0,
      energy: (json['feedback_energy'] as num?)?.toDouble(),
      stress: (json['feedback_stress'] as num?)?.toDouble(),
      social: (json['feedback_social'] as num?)?.toDouble(),
      steps: (json['steps_count'] as num?)?.toInt() ?? 0,
      location: resolvedLocation,
      lastUpdated: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : (json['last_updated'] != null
              ? DateTime.tryParse(json['last_updated'] as String)
              : null),
      device: json['device'] as String? ?? 'unknown',
      moodSelected: json['mood_selected'] as String?,
      executionType: json['execution_type'] as String?,
      // Rich metadata
      geminiPrompt: json['gemini_prompt'] as String?,
      algoPrediction: json['algo_prediction'] as String?,
      weatherSummary: json['weather_summary'] as String?,
      feedbackMetrics: json['feedback_metrics'] as Map<String, dynamic>?,
      musicMetrics: json['music_metrics'] as Map<String, dynamic>?,
      musicSummary: json['music_summary'] as String?,
      calendarSummary: json['calendar_summary'] as String?,
    );
  }

  // Method to convert object to JSON for DB insertion
  Map<String, dynamic> toJson() {
    return {
      "date": date,
      "sleep_hours": sleepHours,
      "feedback_energy": energy,
      "feedback_stress": stress,
      "feedback_social": social,
      "steps_count": steps,
      "location": location,
      "last_updated": lastUpdated?.toIso8601String(),
      "device": device,
    };
  }

  // Helper for empty/default state
  factory MoodEntry.empty() {
    return MoodEntry(
      date: "",
      sleepHours: 7.0,
      steps: 0,
      lastUpdated: DateTime.now(),
      device: "unknown",
      executionType: null,
    );
  }

  // CopyWith helper
  MoodEntry copyWith({
    String? date,
    double? sleepHours,
    double? energy,
    double? stress,
    double? social,
    int? steps,
    String? location,
    DateTime? lastUpdated,
    String? device,
    String? moodSelected,
    String? executionType,
    String? geminiPrompt,
    String? algoPrediction,
    String? weatherSummary,
    Map<String, dynamic>? feedbackMetrics,
    Map<String, dynamic>? musicMetrics,
    String? musicSummary,
    String? calendarSummary,
  }) {
    return MoodEntry(
      date: date ?? this.date,
      sleepHours: sleepHours ?? this.sleepHours,
      energy: energy ?? this.energy,
      stress: stress ?? this.stress,
      social: social ?? this.social,
      steps: steps ?? this.steps,
      location: location ?? this.location,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      device: device ?? this.device,
      moodSelected: moodSelected ?? this.moodSelected,
      executionType: executionType ?? this.executionType,
      geminiPrompt: geminiPrompt ?? this.geminiPrompt,
      algoPrediction: algoPrediction ?? this.algoPrediction,
      weatherSummary: weatherSummary ?? this.weatherSummary,
      feedbackMetrics: feedbackMetrics ?? this.feedbackMetrics,
      musicMetrics: musicMetrics ?? this.musicMetrics,
      musicSummary: musicSummary ?? this.musicSummary,
      calendarSummary: calendarSummary ?? this.calendarSummary,
    );
  }
}
