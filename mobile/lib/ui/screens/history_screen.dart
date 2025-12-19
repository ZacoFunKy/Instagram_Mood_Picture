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

      final entries = logs.map((json) => MoodEntry.fromJson(json)).toList();

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
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left: Date Block
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(dayNum,
                  style:
                      AppTheme.headerLarge.copyWith(fontSize: 24, height: 1.0)),
              Text(monthStr,
                  style: AppTheme.subText
                      .copyWith(fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(width: 16),

          // Middle: Context + Mood
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                        // Hide time if null/empty
                        timeOfDay != null ? "$dayName • $timeOfDay" : dayName,
                        style: AppTheme.subText
                            .copyWith(fontSize: 10, letterSpacing: 0.5)),
                    if (isSynced) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.cloud_done,
                          color: AppTheme.neonGreen.withOpacity(0.6), size: 10)
                    ]
                  ],
                ),
                const SizedBox(height: 4),
                if (entry.moodSelected != null)
                  Text(
                    entry.moodSelected!.toUpperCase(),
                    style: TextStyle(
                        color: moodColor,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        letterSpacing: 0.5),
                  )
                else
                  Text("PROCESSING...",
                      style: AppTheme.subText.copyWith(fontSize: 14)),
              ],
            ),
          ),

          // Right: Metrics Horizontal
          Row(
            children: [
              if (entry.sleepHours > 0)
                _miniMetric(Icons.bedtime, "${entry.sleepHours}h"),
              const SizedBox(width: 8),
              if (entry.steps > 0)
                _miniMetric(Icons.directions_walk,
                    "${(entry.steps / 1000).toStringAsFixed(1)}k"),
            ],
          )
        ],
      ),
    ).animate().fadeIn(delay: (50 * index).ms).slideX();
  }

  Widget _miniMetric(IconData icon, String value) {
    return Row(
      children: [
        Icon(icon, color: Colors.white54, size: 14),
        const SizedBox(width: 4),
        Text(value,
            style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      ],
    );
  }

  String? _formatTimeOfDay(DateTime? date) {
    if (date == null) return null;
    date = date.toLocal();
    int hour = date.hour;
    if (hour < 5) return "NUIT";
    if (hour < 12) return "MATIN";
    if (hour < 18) return "APRÈS-MIDI";
    return "SOIR";
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
