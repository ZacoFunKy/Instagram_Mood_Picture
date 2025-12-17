import 'dart:io';
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

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    try {
      final collection = await DatabaseService.instance.logsCollection;

      // Query: Sort by date descending, limit 30
      final logs = await collection
          .find(mongo.where.sortBy('date', descending: true).limit(30))
          .toList();

      debugPrint("📊 History: Found ${logs.length} entries");

      final List<MoodEntry> entries =
          logs.map((json) => MoodEntry.fromJson(json)).toList();

      if (mounted) {
        setState(() {
          _history = entries;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("❌ History Error: $e");
      if (mounted) {
        setState(() => _isLoading = false);
        // Silently fail or show toast? Senior Architect says: Log it, don't crash UI.
        // Ideally show retry button, but for now just empty state.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("HISTORY", style: AppTheme.headerLarge)
                .animate()
                .fadeIn()
                .slideY(),
            const SizedBox(height: 20),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.white))
                  : _history.isEmpty
                      ? Center(
                          child: Text("No data yet.", style: AppTheme.subText))
                      : ListView.builder(
                          itemCount: _history.length,
                          itemBuilder: (context, index) {
                            final entry = _history[index];
                            return _buildHistoryItem(entry, index);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryItem(MoodEntry entry, int index) {
    // Logic for determining "Matin/Midi/Soir" isn't explicitly in MoodEntry
    // unless we saved multiple entries per day.
    // The current DB schema seems to overwrite 'date' so we have 1 entry per day.
    // So I will display the daily summary.

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDate(entry.date),
                  style: AppTheme.subText.copyWith(fontSize: 12),
                ),
                if (entry.moodSelected != null)
                  Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(8)),
                      child: Text(entry.moodSelected!,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 10)))
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _metricPill("💤 ${entry.sleepHours}h"),
                _metricPill("⚡ ${(entry.energy * 100).toInt()}%"),
                _metricPill("🧠 ${(entry.stress * 100).toInt()}%"),
                _metricPill("👟 ${entry.steps}"),
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

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('EEEE d MMMM').format(date).toUpperCase();
    } catch (_) {
      return dateStr;
    }
  }
}
