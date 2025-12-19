import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
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
      // 1. Fetch History (Processed Data)
      final dailyLogsCol = await DatabaseService.instance.dailyLogs
          .timeout(const Duration(seconds: 15));
      final historyDocs = await dailyLogsCol
          .find(mongo.where.sortBy('date', descending: true).limit(30))
          .toList();

      // 2. Fetch Local Overrides (Pending Data)
      final overridesCol = await DatabaseService.instance.overrides
          .timeout(const Duration(seconds: 15));
      final overrideDocs = await overridesCol
          .find(mongo.where.sortBy('date', descending: true).limit(7))
          .toList();

      // 3. Merge Strategies
      // We want to overlay overrides onto history because overrides are "latest user input"
      // that might not be processed yet.
      Map<String, MoodEntry> mergedMap = {};

      // Fill with history first
      for (var doc in historyDocs) {
        final entry = MoodEntry.fromJson(doc);
        mergedMap[entry.date] = entry;
      }

      // Overlay overrides (local precedence for Sleep/Steps/etc)
      for (var doc in overrideDocs) {
        final entry = MoodEntry.fromJson(doc);
        // If entry exists, we might want to keep the 'moodSelected' from history
        // but update metrics from override.
        if (mergedMap.containsKey(entry.date)) {
          final existing = mergedMap[entry.date]!;
          mergedMap[entry.date] = entry.copyWith(
            moodSelected:
                existing.moodSelected, // Keep predicted mood if exists
          );
        } else {
          mergedMap[entry.date] = entry;
        }
      }

      // Flatten back to list
      final entries = mergedMap.values.toList();
      // Sort Descending (Newest First)
      entries.sort((a, b) => b.date.compareTo(a.date));

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
              "Error: $e\n\nCheck internet or restart app."; // Show actual error
        });
      }
    }
  }

  void _calculateAverages(List<MoodEntry> entries) {
    if (entries.isEmpty) return;

    double totalSleep = 0;
    List<double> energyValues = [];
    List<double> stressValues = [];

    for (var e in entries) {
      totalSleep += e.sleepHours;
      if (e.energy != null) energyValues.add(e.energy!);
      if (e.stress != null) stressValues.add(e.stress!);
    }

    int count = entries.length;
    _avgSleep = "${(totalSleep / count).toStringAsFixed(1)}h";

    _avgEnergy = energyValues.isEmpty
        ? "-"
        : "${((energyValues.reduce((a, b) => a + b) / energyValues.length) * 100).toInt()}%";

    _avgStress = stressValues.isEmpty
        ? "-"
        : "${((stressValues.reduce((a, b) => a + b) / stressValues.length) * 100).toInt()}%";
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
    return SizedBox.expand(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 60, 24, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Text("ANALYTICS", style: AppTheme.headerLarge)
                .animate()
                .fadeIn()
                .slideY(),
            const SizedBox(height: 20),

            // Content
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

    return SingleChildScrollView(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                  child: _buildInfoCard(
                      "TOP MOOD", _topMood, AppTheme.neonPurple)),
              const SizedBox(width: 16),
              Expanded(
                  child: _buildInfoCard(
                      "AVG SLEEP", _avgSleep, AppTheme.neonGreen)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                  child: _buildInfoCard("ENERGY", _avgEnergy, Colors.amber)),
              const SizedBox(width: 16),
              Expanded(
                  child:
                      _buildInfoCard("STRESS", _avgStress, AppTheme.neonPink)),
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
      ),
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
        child: SizedBox(
          height: 200, // Increased height for X-axis labels
          child: BarChart(
            BarChartData(
              gridData: const FlGridData(show: false),
              titlesData: FlTitlesData(
                show: true,
                leftTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (val, meta) {
                      if (val.toInt() < 0 ||
                          val.toInt() >= _recentEntries.length)
                        return const SizedBox.shrink();
                      final entry = _recentEntries[val.toInt()];
                      try {
                        final date = DateTime.parse(entry.date);
                        final dayName = DateFormat('E')
                            .format(date)
                            .toUpperCase(); // MON, TUE
                        final dayNum = DateFormat('d').format(date); // 12
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(dayName,
                                  style: TextStyle(
                                      color: Colors.white54,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold)),
                              Text(dayNum,
                                  style: TextStyle(
                                      color: Colors.white30, fontSize: 10)),
                            ],
                          ),
                        );
                      } catch (_) {
                        return const SizedBox.shrink();
                      }
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              barGroups: _buildBarGroups(),
              barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                      tooltipBgColor: AppTheme.neonPurple,
                      tooltipPadding: const EdgeInsets.all(8),
                      tooltipMargin: 8,
                      fitInsideHorizontally: true, // Fix Overflow
                      fitInsideVertically: true, // Fix Overflow
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final dateStr = _recentEntries[groupIndex].date;
                        return BarTooltipItem(
                            "${rod.toY.round()}h\n",
                            const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14),
                            children: [
                              TextSpan(
                                  text: dateStr,
                                  style: const TextStyle(
                                      color: Colors.white70,
                                      fontWeight: FontWeight.normal,
                                      fontSize: 10))
                            ]);
                      })),
            ),
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
