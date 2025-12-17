import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mongo_dart/mongo_dart.dart' as mongo;
import 'package:intl/intl.dart';
import 'package:sleek_circular_slider/sleek_circular_slider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:ui'; // For BackdropFilter
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint("Warning: Config file not found: $e");
  }
  runApp(const MoodApp());
}

class MoodApp extends StatelessWidget {
  const MoodApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mood',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(context),
      home: const MainScaffold(),
    );
  }

  ThemeData _buildTheme(BuildContext context) {
    final baseTextTheme = Theme.of(context).textTheme;
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Colors.black,
      textTheme: GoogleFonts.interTextTheme(baseTextTheme).apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF00FF9D), // Neon Green
        secondary: Color(0xFFBD00FF), // Neon Purple
        error: Color(0xFFFF0055),
        surface: Color(0xFF111111),
      ),
    );
  }
}

class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    InputScreen(),
    HistoryScreen(),
    StatsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          _screens[_currentIndex],
          Positioned(
            left: 20,
            right: 20,
            bottom: 20,
            child: GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              borderRadius: BorderRadius.circular(32),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _navItem(0, Icons.add_circle_outline_rounded,
                      Icons.add_circle_rounded),
                  _navItem(1, Icons.history_rounded, Icons.history_rounded),
                  _navItem(2, Icons.bar_chart_rounded, Icons.bar_chart_rounded),
                ],
              ),
            ).animate().slideY(
                begin: 1, end: 0, duration: 600.ms, curve: Curves.easeOutBack),
          ),
        ],
      ),
    );
  }

  Widget _navItem(int index, IconData icon, IconData activeIcon) {
    bool isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _currentIndex = index);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color:
              isSelected ? Colors.white.withOpacity(0.1) : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Icon(
          isSelected ? activeIcon : icon,
          color: isSelected ? const Color(0xFF00FF9D) : Colors.white54,
          size: 28,
        ),
      ),
    );
  }
}

// ============================================================================
// INPUT SCREEN
// ============================================================================

class InputScreen extends StatefulWidget {
  const InputScreen({super.key});

  @override
  State<InputScreen> createState() => _InputScreenState();
}

class _InputScreenState extends State<InputScreen> {
  double _sleepHours = 7.5;
  double _energyLevel = 0.5;
  double _stressLevel = 0.5;
  double _socialLevel = 0.5;

  bool _isSyncing = false;
  bool _syncSuccess = false;

  // Step Counting
  int _stepCount = 0;
  StreamSubscription<StepCount>? _stepCountStream;
  Timer? _autoSyncTimer;
  Timer? _stepRefreshTimer;

  @override
  void initState() {
    super.initState();
    _initPedometer();
    _startAutoSync();
    _startStepRefresh();
  }

  @override
  void dispose() {
    _stepCountStream?.cancel();
    _autoSyncTimer?.cancel();
    _stepRefreshTimer?.cancel();
    super.dispose();
  }

  void _startStepRefresh() {
    // Check for midnight reset every minute
    _stepRefreshTimer =
        Timer.periodic(const Duration(minutes: 1), (timer) async {
      await _checkMidnightReset();
    });
  }

  Future<void> _checkMidnightReset() async {
    DateTime now = DateTime.now();
    final today = DateFormat('yyyy-MM-dd').format(now);
    final prefs = await SharedPreferences.getInstance();
    final savedDate = prefs.getString('step_date');

    if (savedDate != today) {
      debugPrint("📅 New day detected ($today), resetting daily steps");
      setState(() {
        _stepCount = 0;
      });
      await prefs.setString('step_date', today);
      await prefs.setInt('daily_steps_accumulated', 0);
      // We don't reset 'last_sensor_value' here, as it's just a reference for deltas
    }
  }

  void _startAutoSync() {
    _autoSyncTimer = Timer.periodic(const Duration(hours: 2), (timer) {
      if (_stepCount > 0) {
        debugPrint("🔄 Auto-syncing step count: $_stepCount");
        _syncToBrain(silent: true);
      }
    });
  }

  Future<void> _initPedometer() async {
    final status = await Permission.activityRecognition.request();
    if (!status.isGranted) return;

    final prefs = await SharedPreferences.getInstance();
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    // Initialize/Restore state
    if (prefs.getString('step_date') != today) {
      await prefs.setString('step_date', today);
      await prefs.setInt('daily_steps_accumulated', 0);
    }

    // Load persisted daily count
    _stepCount = prefs.getInt('daily_steps_accumulated') ?? 0;
    int lastSensorValue = prefs.getInt('last_sensor_value') ?? 0;

    _stepCountStream = Pedometer.stepCountStream.listen(
      (StepCount event) async {
        if (!mounted) return;

        int currentSensorValue = event.steps;
        int delta = 0;

        if (lastSensorValue == 0) {
          // First install or data wipe: assume 0 delta, just sync baseline
          lastSensorValue = currentSensorValue;
        } else if (currentSensorValue < lastSensorValue) {
          // Reboot detected (sensor reset): delta is the full current value
          debugPrint(
              "⚠️ Reboot detected: sensor $lastSensorValue -> $currentSensorValue");
          delta = currentSensorValue;
        } else {
          // Normal update
          delta = currentSensorValue - lastSensorValue;
        }

        if (delta > 0) {
          _stepCount += delta;
          lastSensorValue = currentSensorValue;

          await prefs.setInt('daily_steps_accumulated', _stepCount);
          await prefs.setInt('last_sensor_value', lastSensorValue);

          setState(() {});
        }
      },
      onError: (e) => debugPrint("Pedometer Error: $e"),
    );
  }

  Future<void> _syncToBrain({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isSyncing = true;
        _syncSuccess = false;
      });
    }

    mongo.Db? db;
    final String? uri =
        dotenv.env['MONGO_URI_MOBILE'] ?? dotenv.env['MONGO_URI'];
    final String collectionName = dotenv.env['COLLECTION_NAME'] ?? 'overrides';

    if (uri == null) {
      _showError("Config manquante");
      setState(() => _isSyncing = false);
      return;
    }

    try {
      final String dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      db = await mongo.Db.create(uri);
      await db.open().timeout(const Duration(seconds: 5));

      final collection = db.collection(collectionName);
      final updateData = {
        "date": dateStr,
        "sleep_hours": _sleepHours,
        "feedback_energy": _energyLevel,
        "feedback_stress": _stressLevel,
        "feedback_social": _socialLevel,
        "steps_count": _stepCount, // NEW: Step count
        "last_updated": DateTime.now().toIso8601String(),
        "device": "android_app_mood_v2"
      };

      await collection.update(mongo.where.eq('date', dateStr), updateData,
          upsert: true);

      if (!silent) {
        await HapticFeedback.heavyImpact();
        if (mounted) {
          setState(() => _syncSuccess = true);
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) setState(() => _syncSuccess = false);
          });
        }
      }
    } on SocketException catch (e) {
      debugPrint("🌐 Network Error (Sync): $e");
      if (!silent) _showError("Mode Hors-ligne : Connexion impossible");
    } catch (e) {
      if (!silent)
        _showError("Erreur de sync: ${e.toString().split(':').first}");
    } finally {
      await db?.close();
      if (mounted && !silent) setState(() => _isSyncing = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red));
  }

  String _formatSleep(double value) {
    int minutes = (value * 60).round();
    int h = minutes ~/ 60;
    int m = minutes % 60;
    return '${h}h${m.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              const SizedBox(height: 40),
              Center(
                child: Container(
                  width: 250,
                  height: 250,
                  decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFBD00FF).withOpacity(0.2),
                      blurRadius: 40,
                      spreadRadius: 10,
                    )
                  ]),
                  child: SleekCircularSlider(
                    initialValue: _sleepHours,
                    min: 0,
                    max: 12,
                    appearance: CircularSliderAppearance(
                      size: 240,
                      startAngle: 180,
                      angleRange: 180,
                      customWidths: CustomSliderWidths(
                          trackWidth: 10,
                          progressBarWidth: 15,
                          handlerSize: 10,
                          shadowWidth: 20),
                      customColors: CustomSliderColors(
                        progressBarColor: const Color(0xFFBD00FF),
                        trackColor: Colors.white10,
                        dotColor: Colors.white,
                        shadowColor: const Color(0xFFBD00FF).withOpacity(0.5),
                        shadowMaxOpacity: 0.5,
                      ),
                    ),
                    innerWidget: (double value) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _formatSleep(value),
                              style: GoogleFonts.inter(
                                  fontSize: 48,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: -2),
                            ),
                            Text("SLEEP DURATION",
                                style: GoogleFonts.inter(
                                    color: Colors.white38,
                                    fontSize: 10,
                                    letterSpacing: 1.5)),
                          ],
                        ),
                      );
                    },
                    onChange: (double value) {
                      double snapped = (value * 4).round() / 4;
                      if (snapped != _sleepHours) {
                        HapticFeedback.selectionClick();
                        setState(() => _sleepHours = snapped);
                      }
                    },
                  ),
                ),
              ).animate().fadeIn(duration: 800.ms).scale(),
              const SizedBox(height: 40),
              _buildLabel("VITAL METRICS"),
              const SizedBox(height: 20),
              _buildSlider("ENERGY", "⚡", _energyLevel, const Color(0xFF00FF9D),
                  (v) => setState(() => _energyLevel = v)),
              _buildSlider(
                  "STRESS",
                  "🧠",
                  _stressLevel,
                  const Color(0xFFFF0055),
                  (v) => setState(() => _stressLevel = v)),
              _buildSlider(
                  "SOCIAL",
                  "💬",
                  _socialLevel,
                  const Color(0xFF00C2FF),
                  (v) => setState(() => _socialLevel = v)),
              const SizedBox(height: 24),

              // Step Counter Display
              _buildStepCounter()
                  .animate()
                  .fadeIn(delay: 400.ms)
                  .slideY(begin: 0.2, end: 0),

              const SizedBox(height: 40),
              NeonBtn(
                text: _syncSuccess ? "SYNCED" : "UPDATE MOOD",
                color: _syncSuccess
                    ? const Color(0xFF00FF9D)
                    : const Color(0xFFBD00FF),
                isLoading: _isSyncing,
                onTap: _syncToBrain,
              ).animate().fadeIn(delay: 600.ms).scale(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text("MOOD",
            style: GoogleFonts.inter(
                fontWeight: FontWeight.w900,
                fontSize: 32,
                letterSpacing: -1.5)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
              color: Colors.white10, borderRadius: BorderRadius.circular(20)),
          child: Text(DateFormat('dd MMM').format(DateTime.now()).toUpperCase(),
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        ),
      ],
    );
  }

  Widget _buildLabel(String text) => Text(text,
      style: GoogleFonts.inter(
          fontWeight: FontWeight.bold,
          color: Colors.white24,
          letterSpacing: 2,
          fontSize: 10));

  Widget _buildSlider(String label, String emoji, double value, Color color,
      Function(double) onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: InteractiveSegmentedBar(
        label: label,
        emoji: emoji,
        value: value,
        color: color,
        onChanged: onChanged,
      ).animate().fadeIn(duration: 600.ms).slideX(begin: 0.2, end: 0),
    );
  }

  Widget _buildStepCounter() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Text("👟", style: TextStyle(fontSize: 20)),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("STEPS TODAY",
                      style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                          color: Colors.white38)),
                  const SizedBox(height: 4),
                  Text(
                    NumberFormat('#,###').format(_stepCount),
                    style: GoogleFonts.inter(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: Colors.white),
                  ),
                ],
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _stepCount >= 10000
                  ? const Color(0xFF00FF9D)
                  : Colors.white10,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _stepCount >= 10000
                  ? "GOAL"
                  : "${(((_stepCount / 10000) * 100).toInt())}%",
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: _stepCount >= 10000 ? Colors.black : Colors.white54,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// HISTORY SCREEN
// ============================================================================

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
    final String? uri = dotenv.env['MONGO_URI'];
    debugPrint(
        "🔍 Fetching history from MONGO_URI: ${uri != null ? 'SET' : 'NULL'}");

    if (uri == null) {
      debugPrint("❌ MONGO_URI is null, cannot fetch history");
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      debugPrint("📡 Connecting to MongoDB with URI: $uri");
      final db = await mongo.Db.create(uri);

      // Add timeout to open connection
      await db.open().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('MongoDB connection timeout after 10 seconds');
        },
      );
      debugPrint("✅ Connected to MongoDB");

      // Use standard ISO date query if needed, but here simple find is enough
      debugPrint("🔎 Querying daily_logs collection...");
      final logs = await db
          .collection('daily_logs')
          .find(mongo.where.sortBy('date', descending: true).limit(30))
          .toList();

      debugPrint("📊 Found ${logs.length} logs");

      Map<String, Map<String, String>> grouped = {};
      for (var log in logs) {
        String? d = log['date'];
        if (d == null) {
          debugPrint("⚠️ Skipping log with null date: $log");
          continue;
        }
        String type = log['execution_type'] ?? 'UNKNOWN';
        String mood = log['mood_selected'] ?? '?';
        if (!grouped.containsKey(d)) grouped[d] = {};
        grouped[d]![type] = mood;
      }

      List<Map<String, dynamic>> list = [];
      grouped.forEach((k, v) => list.add({"date": k, "data": v}));
      list.sort((a, b) => b['date'].compareTo(a['date']));

      debugPrint("✅ Processed ${list.length} days of history");

      if (mounted) {
        setState(() {
          _history = list;
          _isLoading = false;
        });
      }
      db.close();
    } on TimeoutException catch (e) {
      debugPrint("⏱️ TIMEOUT: Connection took too long - $e");
      debugPrint(
          "💡 Possible fixes: Check internet, increase timeout, verify MongoDB URI");
      if (mounted) setState(() => _isLoading = false);
    } on SocketException catch (e) {
      debugPrint("🌐 SOCKET ERROR: $e");
      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      debugPrint("❌ Error fetching history: $e");
      if (mounted) setState(() => _isLoading = false);
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
                    fontSize: 24,
                    letterSpacing: -1)),
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

// ============================================================================
// STATS SCREEN (PREMIUM DASHBOARD)
// ============================================================================

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
    final String? mainUri = dotenv.env['MONGO_URI'];
    final String? mobileUri = dotenv.env['MONGO_URI_MOBILE'];

    debugPrint(
        "📊 StatsScreen init - mainUri: ${mainUri != null ? 'SET' : 'NULL'}, mobileUri: ${mobileUri != null ? 'SET' : 'NULL'}");

    if (mainUri == null || mobileUri == null) {
      debugPrint("❌ Missing MongoDB URIs");
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      debugPrint("📡 Connecting to main MongoDB for daily_logs...");
      final db = await mongo.Db.create(mainUri).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('Main DB timeout'),
      );
      await db.open();
      debugPrint("✅ Connected to main DB");

      final logsColl = db.collection('daily_logs');
      final logs = await logsColl.find(mongo.where.limit(100)).toList();
      debugPrint("📊 Found ${logs.length} daily logs");

      debugPrint("📡 Connecting to mobile MongoDB for overrides...");
      final dbMobile = await mongo.Db.create(mobileUri).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('Mobile DB timeout'),
      );
      await dbMobile.open();
      debugPrint("✅ Connected to mobile DB");

      final overridesColl = dbMobile.collection('overrides');
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
      db.close();
      dbMobile.close();
    } on TimeoutException catch (e) {
      debugPrint("⏱️ STATS TIMEOUT: $e");
      debugPrint("💡 Possible fixes: Check internet, increase timeout");
      if (mounted) setState(() => _isLoading = false);
    } on SocketException catch (e) {
      debugPrint("🌐 STATS NETWORK ERROR: $e");
      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      debugPrint("❌ Error fetching stats: $e");
      if (mounted) setState(() => _isLoading = false);
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
              const SizedBox(height: 32),
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

// ============================================================================
// PREMIUM UI WIDGETS
// ============================================================================

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius? borderRadius;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: borderRadius ?? BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class InteractiveSegmentedBar extends StatelessWidget {
  final String label;
  final String emoji;
  final double value; // 0.0 to 1.0
  final Color color;
  final Function(double) onChanged;

  const InteractiveSegmentedBar({
    super.key,
    required this.label,
    required this.emoji,
    required this.value,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [
              Text(emoji, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Text(label,
                  style: GoogleFonts.inter(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: Colors.white70,
                      letterSpacing: 1.5)),
            ]),
            Text("${(value * 10.0).toStringAsFixed(1)}",
                style: GoogleFonts.inter(
                    color: color, fontWeight: FontWeight.bold, fontSize: 14)),
          ],
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onPanUpdate: (details) {
            _updateValue(context, details.localPosition.dx);
          },
          onTapDown: (details) {
            _updateValue(context, details.localPosition.dx);
          },
          child: Container(
            height: 24,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Stack(
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      curve: Curves.easeOut,
                      width: constraints.maxWidth * value,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [color.withOpacity(0.5), color],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                              color: color.withOpacity(0.4),
                              blurRadius: 10,
                              offset: const Offset(0, 2))
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _updateValue(BuildContext context, double dx) {
    // Basic approximation assuming full width minus padding
    // Ideally we use LayoutBuilder but for simplicity in this monolithic file:
    double totalWidth = MediaQuery.of(context).size.width - 48; // 24*2 padding
    double newVal = (dx / totalWidth).clamp(0.0, 1.0);

    if (newVal != value) {
      if ((newVal - value).abs() > 0.05) HapticFeedback.lightImpact();
      onChanged(newVal);
    }
  }
}

class NeonBtn extends StatelessWidget {
  final VoidCallback onTap;
  final String text;
  final Color color;
  final bool isLoading;

  const NeonBtn(
      {super.key,
      required this.onTap,
      required this.text,
      required this.color,
      this.isLoading = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.4),
              blurRadius: 20,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Center(
          child: isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : Text(
                  text,
                  style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16),
                ),
        ),
      ),
    );
  }
}
