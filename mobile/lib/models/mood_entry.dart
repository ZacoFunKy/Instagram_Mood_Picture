class MoodEntry {
  final String date;
  final double sleepHours;
  final double energy;
  final double stress;
  final double social;
  final int steps;
  final String? location;
  final DateTime lastUpdated;
  final String device;
  final String? moodSelected; // For reading back predicted data

  const MoodEntry({
    required this.date,
    required this.sleepHours,
    required this.energy,
    required this.stress,
    required this.social,
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
      energy: (json['feedback_energy'] as num?)?.toDouble() ?? 0.5,
      stress: (json['feedback_stress'] as num?)?.toDouble() ?? 0.5,
      social: (json['feedback_social'] as num?)?.toDouble() ?? 0.5,
      steps: (json['steps_count'] as num?)?.toInt() ?? 0,
      location: json['location'] as String?,
      lastUpdated: json['last_updated'] != null
          ? DateTime.tryParse(json['last_updated'] as String) ?? DateTime.now()
          : DateTime.now(),
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
      // 'mood_selected' is usually written by backend, but if we needed to write it:
      // "mood_selected": moodSelected,
    };
  }

  // Helper for empty/default state
  factory MoodEntry.empty() {
    return MoodEntry(
      date: "",
      sleepHours: 7.0,
      energy: 0.5,
      stress: 0.5,
      social: 0.5,
      steps: 0,
      lastUpdated: DateTime.now(),
      device: "unknown",
    );
  }
}
