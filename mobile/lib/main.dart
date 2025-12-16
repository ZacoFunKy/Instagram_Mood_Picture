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
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Colors.white10)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          backgroundColor: Colors.black,
          selectedItemColor: const Color(0xFF00FF9D),
          unselectedItemColor: Colors.white38,
          showSelectedLabels: false,
          showUnselectedLabels: false,
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(
                icon: Icon(Icons.add_circle_outline_rounded),
                activeIcon: Icon(Icons.add_circle_rounded),
                label: 'Input'),
            BottomNavigationBarItem(
                icon: Icon(Icons.history_rounded), label: 'History'),
            BottomNavigationBarItem(
                icon: Icon(Icons.bar_chart_rounded), label: 'Stats'),
          ],
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
  int _stepCountAtMidnight = 0; // Reference point for today's count
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
    // Reset step count at midnight for new day
    DateTime now = DateTime.now();
    final today = DateFormat('yyyy-MM-dd').format(now);
    final prefs = await SharedPreferences.getInstance();
    final savedDate = prefs.getString('step_date');

    if (savedDate != today) {
      // New day detected, reset counter
      debugPrint("📅 New day detected, resetting step counter");
      setState(() {
        _stepCountAtMidnight =
            0; // Will be reinitialized on next pedometer event
      });
      await prefs.setString('step_date', today);
      await prefs.remove('step_midnight');
    }
  }

  void _startAutoSync() {
    // Auto-sync every 2 hours to keep step count fresh
    _autoSyncTimer = Timer.periodic(const Duration(hours: 2), (timer) {
      if (_stepCount > 0) {
        debugPrint("🔄 Auto-syncing step count: $_stepCount");
        _syncToBrain(silent: true);
      }
    });
  }

  Future<void> _initPedometer() async {
    // Request permission
    final status = await Permission.activityRecognition.request();
    if (!status.isGranted) {
      debugPrint("Activity Recognition permission denied");
      return;
    }

    // Load saved midnight reference from SharedPreferences ONCE
    final prefs = await SharedPreferences.getInstance();
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final savedDate = prefs.getString('step_date');
    final savedMidnight = prefs.getInt('step_midnight') ?? 0;

    // Initialize midnight reference ONCE at startup
    if (savedDate == today && savedMidnight > 0) {
      // Same day, restore saved reference
      _stepCountAtMidnight = savedMidnight;
      debugPrint(
          "📅 Step counter restored: midnight=$_stepCountAtMidnight (from saved)");
    }
    // If different day or no saved value, it will be initialized on first pedometer event

    // Listen for real-time step count updates
    _stepCountStream = Pedometer.stepCountStream.listen(
      (StepCount event) async {
        if (mounted) {
          // Initialize midnight reference ONLY if not already set
          if (_stepCountAtMidnight == 0) {
            _stepCountAtMidnight = event.steps;
            await prefs.setString('step_date', today);
            await prefs.setInt('step_midnight', event.steps);
            debugPrint(
                "📅 Step counter initialized: midnight=${event.steps} (first time)");
          }

          setState(() {
            // Calculate today's steps by subtracting midnight reference
            _stepCount = event.steps - _stepCountAtMidnight;
            if (_stepCount < 0) {
              // Handle phone restart (step counter reset)
              debugPrint("⚠️ Step counter reset detected, reinitializing");
              _stepCountAtMidnight = event.steps;
              _stepCount = 0;
              prefs.setInt('step_midnight', event.steps);
            }
          });
        }
      },
      onError: (error) {
        debugPrint("Pedometer Error: $error");
      },
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
    } catch (e) {
      if (!silent) _showError("Erreur: $e");
    } finally {
      db?.close();
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
                child: SleekCircularSlider(
                  initialValue: _sleepHours,
                  min: 0,
                  max: 12,
                  appearance: CircularSliderAppearance(
                    size: 240,
                    startAngle: 180,
                    angleRange: 180,
                    customColors: CustomSliderColors(
                      progressBarColor: const Color(0xFFBD00FF),
                      trackColor: Colors.white10,
                      dotColor: Colors.white,
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
              _buildStepCounter(),

              const SizedBox(height: 40),
              GestureDetector(
                onTap: !_isSyncing ? _syncToBrain : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  height: 64,
                  decoration: BoxDecoration(
                    color:
                        _syncSuccess ? const Color(0xFF00FF9D) : Colors.white,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Center(
                    child: _isSyncing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.black, strokeWidth: 2))
                        : Text(
                            _syncSuccess ? "SYNCED" : "UPDATE MOOD",
                            style: GoogleFonts.inter(
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                                color: Colors.black),
                          ),
                  ),
                ),
              ),
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
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                Text(emoji),
                const SizedBox(width: 8),
                Text(label,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 12))
              ]),
              Text("${(value * 100).toInt()}",
                  style: TextStyle(color: color, fontWeight: FontWeight.bold)),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: color,
              thumbColor: color,
              overlayColor: color.withOpacity(0.2),
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
                value: value,
                onChanged: onChanged,
                onChangeEnd: (_) => HapticFeedback.mediumImpact()),
          ),
        ],
      ),
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
      debugPrint("🌐 SOCKET/NETWORK ERROR: $e");
      debugPrint(
          "💡 Possible causes: No internet, DNS resolution failed, firewall blocked");
      if (mounted) setState(() => _isLoading = false);
    } on FormatException catch (e) {
      debugPrint(
          "📝 FORMAT ERROR: Invalid MongoDB URI or response format - $e");
      if (mounted) setState(() => _isLoading = false);
    } catch (e, stackTrace) {
      debugPrint("❌ Error fetching history: ${e.runtimeType} - $e");
      debugPrint("Stack trace: $stackTrace");
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
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                              color: Colors.white10,
                              borderRadius: BorderRadius.circular(16)),
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
                        );
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
      debugPrint("💡 Check: Internet connection, DNS resolution, firewall");
      if (mounted) setState(() => _isLoading = false);
    } catch (e, stackTrace) {
      debugPrint("❌ Error fetching stats: ${e.runtimeType} - $e");
      debugPrint("Stack trace: $stackTrace");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("ANALYTICS",
                  style: GoogleFonts.inter(
                      fontWeight: FontWeight.w900,
                      fontSize: 32,
                      letterSpacing: -1.5)),
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
                        SizedBox(
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
                        const SizedBox(height: 48),
                        _buildSectionHeader("SLEEP TREND (7 DAYS)"),
                        const SizedBox(height: 24),
                        SizedBox(
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
                        const SizedBox(height: 40),
                      ],
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
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white10)),
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
