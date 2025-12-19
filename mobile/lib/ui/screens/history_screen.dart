import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:mongo_dart/mongo_dart.dart' as mongo;
import 'package:intl/intl.dart';

import '../../models/mood_entry.dart';
import '../../services/database_service.dart';
import '../../utils/app_theme.dart';
import '../widgets/glass_card.dart';

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
    bool isSynced = true; // For now assuming all history is synced if from DB

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    if (isSynced)
                      Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: Icon(Icons.cloud_done,
                            color: Colors.white30, size: 14),
                      ),
                    Text(
                      _formatDate(entry),
                      style: AppTheme.subText
                          .copyWith(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                if (entry.moodSelected != null)
                  Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                          color: Colors.white12,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white10)),
                      child: Text(entry.moodSelected!.toUpperCase(),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                              letterSpacing: 1.0)))
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (entry.sleepHours > 0)
                  _metricPill("💤 ${entry.sleepHours}h"),
                if (entry.energy != null && entry.energy! > 0)
                  _metricPill("⚡ ${(entry.energy! * 100).toInt()}%"),
                if (entry.stress != null && entry.stress! > 0)
                  _metricPill("🧠 ${(entry.stress! * 100).toInt()}%"),
                if (entry.social != null && entry.social! > 0)
                  _metricPill("💬 ${(entry.social! * 100).toInt()}%"),
                if (entry.steps > 0)
                  _metricPill(
                      "👟 ${NumberFormat('#,###').format(entry.steps)}"),
              ],
            )
          ],
        ),
      ).animate().fadeIn(delay: (50 * index).ms).slideX(),
    );
  }

  Widget _metricPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          border: Border.all(color: Colors.white12),
          borderRadius: BorderRadius.circular(12)),
      child: Text(text,
          style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.white70)),
    );
  }

  String _formatDate(MoodEntry entry) {
    try {
      final date = DateTime.parse(entry.date); // This is YYYY-MM-DD
      // Use local day name
      String dayStr = DateFormat('EEEE d MMMM').format(date).toUpperCase();

      // Determine Time of Day correctly
      // We need to ensure entry.lastUpdated is in Local Time or handled correctly
      // entry.lastUpdated comes from MongoDB ISO string, usually UTC.

      DateTime localUpdated = entry.lastUpdated.toLocal();
      String timeOfDay = "MATIN";
      int hour = localUpdated.hour;

      if (hour < 12) {
        timeOfDay = "MATIN";
      } else if (hour < 18) {
        timeOfDay = "APRÈS-MIDI";
      } else {
        timeOfDay = "SOIR";
      }

      return "$dayStr • $timeOfDay";
    } catch (_) {
      return entry.date;
    }
  }
}
