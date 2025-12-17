import 'dart:io';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mongo_dart/mongo_dart.dart' as mongo;

import '../services/mongo_service.dart';
import '../widgets/glass_card.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});
  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  bool _isLoading = true;

  String _topMood = "-";
  String _avgSleep = "-";
  String _avgEnergy = "-";
  String _avgStress = "-";

  Map<String, int> _moodDistribution = {};
  List<double> _weeklySleep = [0, 0, 0, 0, 0, 0, 0];

  @override
  void initState() {
    super.initState();
    _fetchStats();
  }

  Future<void> _fetchStats() async {
    try {
      // FIX: Wait for DB connection
      await MongoService.instance.getOrConnect();

      final db = MongoService.instance.db;

      if (db == null) {
        debugPrint("❌ DB Not Connected");
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      debugPrint("🔎 Fetching Stats from persistent DB...");

      final logsColl = db.collection('daily_log');
      final logs = await logsColl.find(mongo.where.limit(100)).toList();
      debugPrint("📊 Found ${logs.length} daily logs in daily_log");

      final overridesColl =
          MongoService.instance.mobileDb?.collection('overrides') ??
              db.collection('overrides');

      final overrides = await overridesColl
          .find(mongo.where.sortBy('date', descending: true).limit(7))
          .toList();
      debugPrint("📊 Found ${overrides.length} overrides");

      Map<String, int> moodCounts = {};
      for (var log in logs) {
        String? m = log['mood_selected'];
        if (m != null) moodCounts[m] = (moodCounts[m] ?? 0) + 1;
      }
      _moodDistribution = moodCounts;

      String top = moodCounts.entries.isEmpty
          ? "-"
          : moodCounts.entries.reduce((a, b) => a.value > b.value ? a : b).key;

      double totalSleep = 0;
      double totalEnergy = 0;
      double totalStress = 0;
      int count = 0;

      List<double> sleepTrend = [];
      final recentOverrides = overrides.reversed.toList();

      for (var o in recentOverrides) {
        if (o['sleep_hours'] != null) {
          double s = (o['sleep_hours'] as num).toDouble();
          totalSleep += s;
          sleepTrend.add(s);
        } else {
          sleepTrend.add(0.0);
        }
        if (o['feedback_energy'] != null) {
          totalEnergy += (o['feedback_energy'] as num).toDouble();
        }
        if (o['feedback_stress'] != null) {
          totalStress += (o['feedback_stress'] as num).toDouble();
        }
        count++;
      }

      while (sleepTrend.length < 7) {
        sleepTrend.insert(0, 0.0);
      }
      _weeklySleep = sleepTrend.sublist(sleepTrend.length - 7);

      if (mounted) {
        setState(() {
          _topMood = top.toUpperCase();
          _avgSleep =
              count > 0 ? "${(totalSleep / count).toStringAsFixed(1)}h" : "-";
          _avgEnergy =
              count > 0 ? "${((totalEnergy / count) * 100).toInt()}%" : "-";
          _avgStress =
              count > 0 ? "${((totalStress / count) * 100).toInt()}%" : "-";
          _isLoading = false;
        });
      }
    } on SocketException catch (e) {
      debugPrint("🌐 STATS NETWORK ERROR: $e");
      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      debugPrint("❌ Error fetching stats: $e");
      if (mounted) {
        try {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Stats Error: $e"),
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
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 100), // Space for floating nav
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("ANALYTICS",
                      style: GoogleFonts.inter(
                          fontWeight: FontWeight.w900,
                          fontSize: 32,
                          letterSpacing: -1.5))
                  .animate()
                  .fadeIn()
                  .slideY(),
              const SizedBox(height: 20),
              _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.white))
                  : Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                                child: _buildInfoCard("TOP MOOD", _topMood,
                                    const Color(0xFFBD00FF))),
                            const SizedBox(width: 16),
                            Expanded(
                                child: _buildInfoCard("AVG SLEEP", _avgSleep,
                                    const Color(0xFF00FF9D))),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                                child: _buildInfoCard(
                                    "ENERGY", _avgEnergy, Colors.amber)),
                            const SizedBox(width: 16),
                            Expanded(
                                child: _buildInfoCard("STRESS", _avgStress,
                                    const Color(0xFFFF0055))),
                          ],
                        ),
                        const SizedBox(height: 48),
                        _buildSectionHeader("MOOD DISTRIBUTION"),
                        const SizedBox(height: 24),
                        GlassCard(
                          child: SizedBox(
                            height: 200,
                            child: _moodDistribution.isEmpty
                                ? Center(
                                    child: Text("No Data",
                                        style: GoogleFonts.inter(
                                            color: Colors.white38)))
                                : PieChart(
                                    PieChartData(
                                      sectionsSpace: 4,
                                      centerSpaceRadius: 40,
                                      sections: _buildPieSections(),
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 48),
                        _buildSectionHeader("SLEEP TREND (7 DAYS)"),
                        const SizedBox(height: 24),
                        GlassCard(
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
                                    tooltipPadding: const EdgeInsets.all(8),
                                    tooltipMargin: 8,
                                    fitInsideVertically: true,
                                    fitInsideHorizontally: true,
                                    getTooltipItem:
                                        (group, groupIndex, rod, rodIndex) {
                                      return BarTooltipItem(
                                        "${rod.toY.round()}h",
                                        const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 40),
                      ]
                          .animate(interval: 100.ms)
                          .fadeIn()
                          .slideY(begin: 0.1, end: 0),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Row(children: [
      Container(width: 4, height: 16, color: const Color(0xFF00FF9D)),
      const SizedBox(width: 8),
      Text(title,
          style: GoogleFonts.inter(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: 2,
              color: Colors.white70)),
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
              Text(label,
                  style: GoogleFonts.inter(
                      color: Colors.white38,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1)),
            ],
          ),
          const SizedBox(height: 12),
          Text(value,
              style: GoogleFonts.inter(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: Colors.white)),
        ],
      ),
    );
  }

  List<PieChartSectionData> _buildPieSections() {
    List<Color> colors = [
      const Color(0xFF00FF9D),
      const Color(0xFFBD00FF),
      const Color(0xFFFF0055),
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
        radius: 15, // Sleek thin ring
        badgeWidget: _Badge(e.key, color),
        badgePositionPercentageOffset: 1.5,
      );
    }).toList();
  }

  List<BarChartGroupData> _buildBarGroups() {
    int x = 0;
    return _weeklySleep.map((y) {
      return BarChartGroupData(x: x++, barRods: [
        BarChartRodData(
          toY: y,
          color: y >= 7 ? const Color(0xFF00FF9D) : const Color(0xFFFF0055),
          width: 12,
          borderRadius: BorderRadius.circular(4),
        )
      ]);
    }).toList();
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  const _Badge(this.text, this.color);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
          color: color.withOpacity(0.2),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color)),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 8, fontWeight: FontWeight.bold)),
    );
  }
}
