import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mongo_dart/mongo_dart.dart' as mongo;

import '../../models/mood_entry.dart';
import '../../services/database_service.dart';
import '../../utils/app_theme.dart';
import '../widgets/glass_card.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});
  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  bool _isLoading = true;
  String? _errorMessage;

  // Stats Data
  String _topMood = "-";
  String _avgSleep = "-";
  String _avgEnergy = "-";
  String _avgStress = "-";

  Map<String, int> _moodDistribution = {};
  List<MoodEntry> _recentEntries = [];

  @override
  void initState() {
    super.initState();
    _fetchStats();
  }

  Future<void> _fetchStats() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final collection = await DatabaseService.instance.logsCollection;

      // Fetch last 30 days for robust stats
      final logs = await collection
          .find(mongo.where.sortBy('date', descending: true).limit(30))
          .toList();

      final entries = logs.map((e) => MoodEntry.fromJson(e)).toList();

      if (entries.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // Calculate Stats
      _calculateAverages(entries);
      _calculateMoodDistribution(entries);

      // Get recent 7 days for charts
      _recentEntries = entries.take(7).toList().reversed.toList();

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint("❌ Stats Error: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage =
              "Unable to load analytics.\nCheck your internet connection.";
        });
      }
    }
  }

  void _calculateAverages(List<MoodEntry> entries) {
    if (entries.isEmpty) return;

    double totalSleep = 0;
    double totalEnergy = 0;
    double totalStress = 0;

    for (var e in entries) {
      totalSleep += e.sleepHours;
      totalEnergy += e.energy;
      totalStress += e.stress;
    }

    int count = entries.length;
    _avgSleep = "${(totalSleep / count).toStringAsFixed(1)}h";
    _avgEnergy = "${((totalEnergy / count) * 100).toInt()}%";
    _avgStress = "${((totalStress / count) * 100).toInt()}%";
  }

  void _calculateMoodDistribution(List<MoodEntry> entries) {
    Map<String, int> distribution = {};
    for (var e in entries) {
      if (e.moodSelected != null) {
        String m = e.moodSelected!;
        distribution[m] = (distribution[m] ?? 0) + 1;
      }
    }
    _moodDistribution = distribution;

    if (distribution.isNotEmpty) {
      _topMood = distribution.entries
          .reduce((a, b) => a.value > b.value ? a : b)
          .key
          .toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 100),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("ANALYTICS", style: AppTheme.headerLarge)
                  .animate()
                  .fadeIn()
                  .slideY(),
              const SizedBox(height: 20),
              _buildContent(),
            ],
          ),
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
          children: [
            const SizedBox(height: 48),
            const Icon(Icons.error_outline, color: Colors.white54, size: 48),
            const SizedBox(height: 16),
            Text(_errorMessage!,
                textAlign: TextAlign.center, style: AppTheme.subText),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _fetchStats,
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.neonPurple),
              child: const Text("RETRY", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }

    if (_recentEntries.isEmpty) {
      return Center(
          child: Text("No stats available yet.", style: AppTheme.subText));
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(
                child:
                    _buildInfoCard("TOP MOOD", _topMood, AppTheme.neonPurple)),
            const SizedBox(width: 16),
            Expanded(
                child:
                    _buildInfoCard("AVG SLEEP", _avgSleep, AppTheme.neonGreen)),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _buildInfoCard("ENERGY", _avgEnergy, Colors.amber)),
            const SizedBox(width: 16),
            Expanded(
                child: _buildInfoCard("STRESS", _avgStress, AppTheme.neonPink)),
          ],
        ),
        const SizedBox(height: 48),

        // Charts
        if (_moodDistribution.isNotEmpty) ...[
          _buildSectionHeader("MOOD DISTRIBUTION"),
          const SizedBox(height: 24),
          _buildPieChart(),
          const SizedBox(height: 48),
        ],

        _buildSectionHeader("SLEEP TREND (7 DAYS)"),
        const SizedBox(height: 24),
        _buildBarChart(),
      ].animate(interval: 100.ms).fadeIn().slideY(begin: 0.1, end: 0),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Row(children: [
      Container(width: 4, height: 16, color: AppTheme.neonGreen),
      const SizedBox(width: 8),
      Text(title, style: AppTheme.labelSmall),
    ]);
  }

  Widget _buildInfoCard(String label, String value, Color accent) {
    return GlassCard(
      padding: const EdgeInsets.all(20),
      borderRadius: BorderRadius.circular(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(backgroundColor: accent, radius: 4),
              const SizedBox(width: 8),
              Text(label, style: AppTheme.labelSmall),
            ],
          ),
          const SizedBox(height: 12),
          Text(value, style: AppTheme.valueLarge),
        ],
      ),
    );
  }

  Widget _buildPieChart() {
    return GlassCard(
      child: SizedBox(
        height: 200,
        child: PieChart(
          PieChartData(
            sectionsSpace: 4,
            centerSpaceRadius: 40,
            sections: _buildPieSections(),
          ),
        ),
      ),
    );
  }

  List<PieChartSectionData> _buildPieSections() {
    List<Color> colors = [
      AppTheme.neonGreen,
      AppTheme.neonPurple,
      AppTheme.neonPink,
      Colors.amber,
      Colors.cyan
    ];
    int i = 0;
    return _moodDistribution.entries.map((e) {
      final color = colors[i % colors.length];
      i++;
      return PieChartSectionData(
        color: color,
        value: e.value.toDouble(),
        title: '',
        radius: 15,
        badgeWidget: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
              color: Colors.black54, borderRadius: BorderRadius.circular(4)),
          child: Text(e.key,
              style: TextStyle(
                  color: color, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        badgePositionPercentageOffset: 1.5,
      );
    }).toList();
  }

  Widget _buildBarChart() {
    return GlassCard(
      child: SizedBox(
        height: 180,
        child: BarChart(
          BarChartData(
            gridData: const FlGridData(show: false),
            titlesData: const FlTitlesData(show: false),
            borderData: FlBorderData(show: false),
            barGroups: _buildBarGroups(),
            barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                    tooltipBgColor: Colors.black87,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      return BarTooltipItem("${rod.toY.round()}h",
                          const TextStyle(color: Colors.white));
                    })),
          ),
        ),
      ),
    );
  }

  List<BarChartGroupData> _buildBarGroups() {
    int x = 0;
    return _recentEntries.map((e) {
      final y = e.sleepHours;
      return BarChartGroupData(x: x++, barRods: [
        BarChartRodData(
          toY: y,
          color: y >= 7 ? AppTheme.neonGreen : AppTheme.neonPink,
          width: 12,
          borderRadius: BorderRadius.circular(4),
        )
      ]);
    }).toList();
  }
}
