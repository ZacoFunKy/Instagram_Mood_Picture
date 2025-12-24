import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:mongo_dart/mongo_dart.dart' as mongo;
import 'package:intl/intl.dart';

import '../../models/mood_entry.dart';
import '../../services/database_service.dart';
import '../../utils/app_theme.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<MoodEntry> _history = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // History reads from profile_predictor.daily_logs
      final collection = await DatabaseService.instance.dailyLogs
          .timeout(const Duration(seconds: 15));

      final logs = await collection
          .find(mongo.where.sortBy('date', descending: true).limit(30))
          .toList();

      debugPrint("📊 History: Found ${logs.length} entries");

      // Trier explicitement par date/heure en ordre décroissant (plus récent en premier)
      final entries = logs.map((json) => MoodEntry.fromJson(json)).toList();
      entries.sort((a, b) {
        final tsA = a.lastUpdated ?? DateTime.tryParse("${a.date}T00:00:00") ?? DateTime(1970);
        final tsB = b.lastUpdated ?? DateTime.tryParse("${b.date}T00:00:00") ?? DateTime(1970);
        return tsB.compareTo(tsA);
      });

      if (mounted) {
        setState(() {
          _history = entries;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("❌ History Error: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage =
              "Error: $e\n\nCheck internet or restart app."; // Show actual error
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            24, 60, 24, 120), // Manual padding instead of SafeArea
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("HISTORY", style: AppTheme.headerLarge)
                .animate()
                .fadeIn()
                .slideY(),
            const SizedBox(height: 20),
            Expanded(
              child: _buildContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white));
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.signal_wifi_off, color: Colors.white54, size: 48),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: AppTheme.subText.copyWith(fontSize: 14),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _fetchHistory,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.neonPurple,
                foregroundColor: Colors.white,
              ),
              child: const Text("RETRY"),
            )
          ],
        ),
      );
    }

    if (_history.isEmpty) {
      return Center(child: Text("No data yet.", style: AppTheme.subText));
    }

    return ListView.builder(
      itemCount: _history.length,
      itemBuilder: (context, index) {
        final entry = _history[index];
        return _buildHistoryItem(entry, index);
      },
    );
  }

  Widget _buildHistoryItem(MoodEntry entry, int index) {
    bool isSynced = true;

    // Date Formatting
    final date = DateTime.parse(entry.date);
    final dayNum = DateFormat('d').format(date);
    final monthStr = DateFormat('MMM').format(date).toUpperCase();
    final dayName = DateFormat('EEEE').format(date).toUpperCase();
    final timeOfDay = _formatTimeOfDay(entry.executionType, entry.lastUpdated, entry.date);

    Color moodColor = _getMoodColor(entry.moodSelected);

    return GestureDetector(
      onTap: () => _showDetailModal(entry),
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withOpacity(0.08),
              Colors.white.withOpacity(0.03),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.15), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: moodColor.withOpacity(0.1),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left: Date Block with better styling
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: moodColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: moodColor.withOpacity(0.3)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(dayNum,
                      style: AppTheme.headerLarge
                          .copyWith(fontSize: 28, height: 1.0, color: moodColor)),
                  Text(monthStr,
                      style: AppTheme.subText.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: moodColor.withOpacity(0.8))),
                ],
              ),
            ),
            const SizedBox(width: 16),

            // Middle: Context + Mood
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                            // Hide time if null/empty
                            timeOfDay != null ? "$dayName • $timeOfDay" : dayName,
                            style: AppTheme.subText.copyWith(
                                fontSize: 11,
                                letterSpacing: 0.5,
                                color: Colors.white70)),
                      ),
                      if (isSynced) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.neonGreen.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.cloud_done,
                                  color: AppTheme.neonGreen, size: 12),
                              const SizedBox(width: 4),
                              Text("SYNC",
                                  style: TextStyle(
                                      color: AppTheme.neonGreen,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                        )
                      ]
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (entry.moodSelected != null)
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: moodColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: moodColor.withOpacity(0.4)),
                      ),
                      child: Text(
                        entry.moodSelected!.toUpperCase(),
                        style: TextStyle(
                            color: moodColor,
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            letterSpacing: 0.8),
                      ),
                    )
                  else
                    Text("PROCESSING...",
                        style: AppTheme.subText.copyWith(fontSize: 14)),
                  const SizedBox(height: 12),
                  // Metrics in Row
                  Row(
                    children: [
                      if (entry.sleepHours > 0) ...[
                        _miniMetric(Icons.bedtime, "${entry.sleepHours}h"),
                        const SizedBox(width: 12),
                      ],
                      if (entry.steps > 0)
                        _miniMetric(Icons.directions_walk,
                            "${(entry.steps / 1000).toStringAsFixed(1)}k"),
                      if (entry.location != null &&
                          entry.location!.isNotEmpty) ...[
                        const SizedBox(width: 12),
                        _miniMetric(Icons.location_on, entry.location!),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "TAP FOR DETAILS",
                    style: AppTheme.labelSmall.copyWith(
                      fontSize: 9,
                      color: Colors.white30,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(delay: (50 * index).ms).slideY(begin: 0.3, end: 0);
  }

  void _showDetailModal(MoodEntry entry) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _DetailModal(entry: entry),
    );
  }

  Widget _miniMetric(IconData icon, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white70, size: 14),
          const SizedBox(width: 4),
          Text(value,
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  String? _formatTimeOfDay(String? executionType, DateTime? date, String? dateStr) {
    // Priorité 1 : Utiliser execution_type de la DB si disponible
    if (executionType != null && executionType.isNotEmpty) {
      final execType = executionType.toUpperCase();
      if (execType.contains('MATIN')) return "MATIN";
      if (execType.contains('APRES') || execType.contains('MIDI')) return "APRÈS-MIDI";
      if (execType.contains('SOIREE') || execType.contains('SOIR')) return "SOIR";
      if (execType.contains('NUIT')) return "NUIT";
    }
    
    // Priorité 2 : Utiliser l'heure si disponible
    if (date != null) {
      date = date.toLocal();
      int hour = date.hour;
      if (hour < 5) return "NUIT";
      if (hour < 12) return "MATIN";
      if (hour < 18) return "APRÈS-MIDI";
      if (hour < 24) return "SOIR";
    }
    
    // Fallback par défaut
    return "SOIR";
  }

  Color _getMoodColor(String? mood) {
    if (mood == null) return Colors.white;
    final m = mood.toLowerCase();
    if (m.contains('happy') || m.contains('festif')) {
      return AppTheme.neonGreen;
    }
    if (m.contains('sad') || m.contains('mélancolique')) {
      return Colors.blueGrey;
    }
    if (m.contains('calm') || m.contains('chill')) {
      return Colors.cyan;
    }
    if (m.contains('explosif') || m.contains('agressif')) {
      return AppTheme.neonPink;
    }
    return AppTheme.neonPurple;
  }
}

/// Detail Modal for showing comprehensive mood data
class _DetailModal extends StatelessWidget {
  final MoodEntry entry;

  const _DetailModal({required this.entry});

  @override
  Widget build(BuildContext context) {
    final moodColor = _getMoodColorStatic(entry.moodSelected);
    
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with close button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "MOOD DETAILS",
                    style: AppTheme.headerLarge.copyWith(fontSize: 20),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, size: 20),
                    ),
                  ),
                ],
              ),
            ),
            Divider(color: Colors.white.withOpacity(0.1), height: 1),

            // Content
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Date & Time
                  _buildDetailSection(
                    "DATE & TIME",
                    "${entry.date} • ${_formatTimeOfDayStatic(entry.executionType, entry.lastUpdated, entry.date)}",
                  ),
                  const SizedBox(height: 24),

                  // Mood Prediction
                  _buildDetailSection(
                    "MOOD PREDICTION",
                    entry.moodSelected?.toUpperCase() ?? "Processing...",
                    color: moodColor,
                  ),
                  const SizedBox(height: 24),

                  // Location
                  if (entry.location != null && entry.location!.isNotEmpty) ...[
                    _buildDetailSection(
                      "LOCATION",
                      entry.location!,
                      icon: Icons.location_on,
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Sleep Hours
                  if (entry.sleepHours > 0) ...[
                    _buildDetailSection(
                      "SLEEP DURATION",
                      "${entry.sleepHours.toStringAsFixed(1)}h",
                      icon: Icons.bedtime,
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Steps
                  if (entry.steps > 0) ...[
                    _buildDetailSection(
                      "ACTIVITY (STEPS)",
                      "${entry.steps} steps (${(entry.steps / 1000).toStringAsFixed(1)}k)",
                      icon: Icons.directions_walk,
                    ),
                    const SizedBox(height: 24),
                  ],

            // Gemini Prompt
                  if (entry.geminiPrompt != null && entry.geminiPrompt!.isNotEmpty) ...[
                    _buildDetailSection(
                      "AI PROMPT (Gemini)",
                      entry.geminiPrompt!.length > 500
                          ? entry.geminiPrompt!.substring(0, 500) + "..."
                          : entry.geminiPrompt!,
                      fontSize: 11,
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Algo Prediction
                  if (entry.algoPrediction != null &&
                      entry.algoPrediction!.isNotEmpty) ...[
                    _buildDetailSection(
                      "ALGORITHM PREDICTION",
                      entry.algoPrediction!.toUpperCase(),
                      color: AppTheme.neonPurple,
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Weather Data
                  if (entry.weatherSummary != null &&
                      entry.weatherSummary!.isNotEmpty) ...[
                    _buildDetailSection(
                      "WEATHER DATA",
                      entry.weatherSummary!,
                      fontSize: 12,
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Music Data
                  if (entry.musicSummary != null &&
                      entry.musicSummary!.isNotEmpty) ...[
                    _buildDetailSection(
                      "MUSIC ANALYSIS",
                      entry.musicSummary!.length > 300
                          ? entry.musicSummary!.substring(0, 300) + "..."
                          : entry.musicSummary!,
                      fontSize: 11,
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Music Metrics (if available)
                  if (entry.musicMetrics != null && entry.musicMetrics!.isNotEmpty) ...[
                    Text("MUSIC METRICS", style: AppTheme.labelSmall),
                    const SizedBox(height: 12),
                    _buildMetricBar(
                      "Valence",
                      (entry.musicMetrics!['avg_valence'] as num? ?? 0).toDouble().clamp(0.0, 1.0),
                      AppTheme.neonGreen,
                    ),
                    _buildMetricBar(
                      "Energy",
                      (entry.musicMetrics!['avg_energy'] as num? ?? 0).toDouble().clamp(0.0, 1.0),
                      AppTheme.neonPink,
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Calendar Data
                  if (entry.calendarSummary != null &&
                      entry.calendarSummary!.isNotEmpty) ...[
                    _buildDetailSection(
                      "CALENDAR EVENTS",
                      entry.calendarSummary!.length > 300
                          ? entry.calendarSummary!.substring(0, 300) + "..."
                          : entry.calendarSummary!,
                      fontSize: 11,
                    ),
                    const SizedBox(height: 24),
                  ],

                  // User Feedback Metrics
                  if (entry.energy != null ||
                      entry.stress != null ||
                      entry.social != null) ...[
                    Text("USER FEEDBACK", style: AppTheme.labelSmall),
                    const SizedBox(height: 12),
                    if (entry.energy != null)
                      _buildMetricBar(
                        "Energy",
                        entry.energy!,
                        AppTheme.neonGreen,
                      ),
                    if (entry.stress != null)
                      _buildMetricBar(
                        "Stress",
                        entry.stress!,
                        AppTheme.neonPink,
                      ),
                    if (entry.social != null)
                      _buildMetricBar(
                        "Social",
                        entry.social!,
                        AppTheme.neonBlue,
                      ),
                    const SizedBox(height: 24),
                  ],

                  // Execution Type
                  if (entry.executionType != null &&
                      entry.executionType!.isNotEmpty) ...[
                    _buildDetailSection(
                      "EXECUTION TYPE",
                      entry.executionType!.toUpperCase(),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Device Info
                  _buildDetailSection(
                    "SOURCE",
                    entry.device,
                    fontSize: 12,
                  ),
                  const SizedBox(height: 24),

                  // Last Updated
                  if (entry.lastUpdated != null) ...[
                    _buildDetailSection(
                      "LAST UPDATED",
                      entry.lastUpdated!.toLocal().toString().split('.').first,
                      fontSize: 12,
                      color: Colors.white30,
                    ),
                  ],

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    ).animate().slideY(begin: 1, end: 0, duration: 400.ms, curve: Curves.easeOut);
  }

  Widget _buildDetailSection(
    String label,
    String value, {
    Color? color,
    IconData? icon,
    double fontSize = 14,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTheme.labelSmall),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: (color ?? Colors.white).withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, color: color ?? Colors.white70, size: 18),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  value,
                  style: TextStyle(
                    color: color ?? Colors.white,
                    fontSize: fontSize,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetricBar(String label, double value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: AppTheme.subText),
              Text(
                "${(value * 100).toStringAsFixed(0)}%",
                style: TextStyle(color: color, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: value.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: Colors.white.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }

  static Color _getMoodColorStatic(String? mood) {
    if (mood == null) return Colors.white;
    final m = mood.toLowerCase();
    if (m.contains('happy') || m.contains('festif') || m.contains('energetic') || m.contains('pumped')) {
      return AppTheme.neonGreen;
    }
    if (m.contains('sad') || m.contains('mélancolique') || m.contains('melancholy')) {
      return Colors.blueGrey;
    }
    if (m.contains('calm') || m.contains('chill') || m.contains('creative')) {
      return Colors.cyan;
    }
    if (m.contains('explosif') || m.contains('agressif') || m.contains('intense')) {
      return AppTheme.neonPink;
    }
    if (m.contains('hard_work') || m.contains('confident')) {
      return AppTheme.neonPurple;
    }
    if (m.contains('tired')) {
      return Colors.orange;
    }
    return AppTheme.neonPurple;
  }

  static String? _formatTimeOfDayStatic(String? executionType, DateTime? date, String? dateStr) {
    if (executionType != null && executionType.isNotEmpty) {
      final execType = executionType.toUpperCase();
      if (execType.contains('MATIN')) return "MATIN";
      if (execType.contains('APRES') || execType.contains('MIDI')) return "APRÈS-MIDI";
      if (execType.contains('SOIREE') || execType.contains('SOIR')) return "SOIR";
      if (execType.contains('NUIT')) return "NUIT";
    }
    
    if (date != null) {
      date = date.toLocal();
      int hour = date.hour;
      if (hour < 5) return "NUIT";
      if (hour < 12) return "MATIN";
      if (hour < 18) return "APRÈS-MIDI";
      if (hour < 24) return "SOIR";
    }
    
    return "SOIR";
  }
}
