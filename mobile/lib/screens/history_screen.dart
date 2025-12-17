import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mongo_dart/mongo_dart.dart' as mongo;

import '../services/mongo_service.dart';
import '../widgets/glass_card.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _history = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    try {
      // FIX: Wait for DB connection
      await MongoService.instance.getOrConnect();

      final db = MongoService.instance.db;

      if (db == null) {
        debugPrint("❌ DB Not Connected");
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      debugPrint("🔎 Querying daily_log collection...");
      final logs = await db
          .collection('daily_log')
          .find(mongo.where.sortBy('date', descending: true).limit(30))
          .toList();

      debugPrint("📊 Found ${logs.length} logs");

      Map<String, Map<String, String>> grouped = {};
      for (var log in logs) {
        String? d = log['date'];
        if (d == null) continue;
        String type = log['execution_type'] ?? 'UNKNOWN';
        String mood = log['mood_selected'] ?? '?';
        if (!grouped.containsKey(d)) grouped[d] = {};
        grouped[d]![type] = mood;
      }

      List<Map<String, dynamic>> list = [];
      grouped.forEach((k, v) => list.add({"date": k, "data": v}));
      list.sort((a, b) => b['date'].compareTo(a['date']));

      if (mounted) {
        setState(() {
          _history = list;
          _isLoading = false;
        });
      }
    } on SocketException catch (e) {
      debugPrint("🌐 SOCKET ERROR: $e");
      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      debugPrint("❌ Error fetching history: $e");
      if (mounted) {
        try {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("History Error: $e"),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ));
        } catch (_) {}
        setState(() => _isLoading = false);
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
            Text("HISTORY",
                    style: GoogleFonts.inter(
                        fontWeight: FontWeight.w900,
                        fontSize: 32,
                        letterSpacing: -1.5))
                .animate()
                .fadeIn()
                .slideY(),
            const SizedBox(height: 20),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.white))
                  : ListView.builder(
                      itemCount: _history.length,
                      itemBuilder: (context, index) {
                        final day = _history[index];
                        final moods = day['data'] as Map<String, String>;
                        return GlassCard(
                          padding: const EdgeInsets.all(16),
                          borderRadius: BorderRadius.circular(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(day['date'],
                                  style: GoogleFonts.inter(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white54)),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  _MoodPill("Matin", moods['MATIN']),
                                  _MoodPill("Midi", moods['APRES_MIDI']),
                                  _MoodPill("Soir", moods['SOIREE']),
                                ],
                              )
                            ],
                          ),
                        ).animate().fadeIn(delay: (50 * index).ms).slideX();
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _MoodPill(String label, String? mood) {
    bool hasMood = mood != null;
    return Column(
      children: [
        Text(label,
            style: const TextStyle(fontSize: 10, color: Colors.white38)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
              color: hasMood ? Colors.white : Colors.transparent,
              border: Border.all(color: Colors.white24),
              borderRadius: BorderRadius.circular(20)),
          child: Text(hasMood ? mood : "-",
              style: TextStyle(
                  color: hasMood ? Colors.black : Colors.white24,
                  fontWeight: FontWeight.bold,
                  fontSize: 10)),
        )
      ],
    );
  }
}
