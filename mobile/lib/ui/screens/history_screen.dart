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

      // Trier explicitement par date en ordre décroissant (du plus récent au plus ancien)
      final entries = logs.map((json) => MoodEntry.fromJson(json)).toList();
      entries.sort((a, b) => b.date.compareTo(a.date));

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
    final timeOfDay = _formatTimeOfDay(entry.lastUpdated);

    Color moodColor = _getMoodColor(entry.moodSelected);

    return Container(
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
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: (50 * index).ms).slideY(begin: 0.3, end: 0);
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

  String? _formatTimeOfDay(DateTime? date) {
    if (date == null) return null;
    date = date.toLocal();
    int hour = date.hour;
    if (hour < 5) return "NUIT";
    if (hour < 12) return "MATIN";
    if (hour < 18) return "APRÈS-MIDI";
    if (hour < 24) return "SOIR";
    return "NUIT";
  }

  Color _getMoodColor(String? mood) {
    if (mood == null) return Colors.white;
    final m = mood.toLowerCase();
    if (m.contains('happy') || m.contains('festif')) return AppTheme.neonGreen;
    if (m.contains('sad') || m.contains('mélancolique')) return Colors.blueGrey;
    if (m.contains('calm') || m.contains('chill')) return Colors.cyan;
    if (m.contains('explosif') || m.contains('agressif'))
      return AppTheme.neonPink;
    return AppTheme.neonPurple;
  }
}
