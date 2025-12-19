class MoodEntry {
  final String date;
  final double sleepHours;
  final double? energy;
  final double? stress;
  final double? social;
  final int steps;
  final String? location;
  final DateTime lastUpdated;
  final String device;
  final String? moodSelected; // For reading back predicted data

  const MoodEntry({
    required this.date,
    required this.sleepHours,
    this.energy,
    this.stress,
    this.social,
    required this.steps,
    this.location,
    required this.lastUpdated,
    required this.device,
    this.moodSelected,
  });

  // Factory constructor for parsing JSON from DB
  factory MoodEntry.fromJson(Map<String, dynamic> json) {
    return MoodEntry(
      date: json['date'] as String,
      sleepHours: (json['sleep_hours'] as num?)?.toDouble() ?? 0.0,
      energy: (json['feedback_energy'] as num?)?.toDouble(), // Nullable
      stress: (json['feedback_stress'] as num?)?.toDouble(), // Nullable
      social: (json['feedback_social'] as num?)?.toDouble(), // Nullable
      steps: (json['steps_count'] as num?)?.toInt() ?? 0,
      location: json['location'] as String?,
      lastUpdated: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
          : (json['last_updated'] != null
              ? DateTime.tryParse(json['last_updated'] as String) ??
                  DateTime.now()
              : DateTime.now()),
      device: json['device'] as String? ?? 'unknown',
      moodSelected: json['mood_selected'] as String?,
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
      "last_updated": lastUpdated.toIso8601String(),
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
    );
  }

  // CopyWith helper (needed for StatsScreen merge logic)
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
    );
  }
}
