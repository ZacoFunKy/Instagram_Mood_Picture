import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:mongo_dart/mongo_dart.dart' as mongo;
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sleek_circular_slider/sleek_circular_slider.dart';

import '../services/mongo_service.dart';
import '../widgets/glass_card.dart';
import '../widgets/interactive_segmented_bar.dart';
import '../widgets/neon_btn.dart';

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
  String _temperature = "";
  String _cityName = ""; // Store city
  bool _weatherLoading = false;

  // Step Counting
  int _stepCount = 0;
  int _stepsAtLastReset = 0; // Steps stored at start of day
  StreamSubscription<StepCount>? _stepCountStream;
  Timer? _autoSyncTimer;
  Timer? _stepRefreshTimer;

  @override
  void initState() {
    super.initState();
    _loadDailySteps(); // Load saved steps first
    _initPedometer();
    _startAutoSync();
    _startStepRefresh();
    _fetchWeather(); // Fetch weather on init
  }

  // --- ACCUMULATOR LOGIC ---
  Future<void> _loadDailySteps() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final savedDate = prefs.getString('step_date');

    if (savedDate == today) {
      setState(() {
        _stepCount = prefs.getInt('daily_steps') ?? 0;
        _stepsAtLastReset = prefs.getInt('steps_at_reset') ?? 0;
      });
    } else {
      // New day, reset
      await prefs.setString('step_date', today);
      await prefs.setInt('daily_steps', 0);
      await prefs.setInt('steps_at_reset', 0); // Will be set on first event
      setState(() {
        _stepCount = 0;
        _stepsAtLastReset = 0;
      });
    }
  }

  void _onStepCount(StepCount event) async {
    final prefs = await SharedPreferences.getInstance();

    // 1. If it's our first event of the day/session and we have no baseline:
    if (_stepsAtLastReset == 0) {
      _stepsAtLastReset = event.steps - _stepCount; // Re-align offset
      await prefs.setInt('steps_at_reset', _stepsAtLastReset);
    }

    // 2. Calculate steps
    int calculated = event.steps - _stepsAtLastReset;

    // 3. Handle Reboots (Sensor resets to 0)
    if (calculated < 0) {
      _stepsAtLastReset = 0 - _stepCount;
      calculated = event.steps - _stepsAtLastReset;
      await prefs.setInt('steps_at_reset', _stepsAtLastReset);
    }

    setState(() {
      _stepCount = calculated;
    });

    // 4. Save
    await prefs.setInt('daily_steps', _stepCount);
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
    final prefs = await SharedPreferences.getInstance();
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final savedDate = prefs.getString('step_date');

    if (savedDate != today) {
      debugPrint("📅 Midnight detected! Resetting accumulator.");
      await prefs.setString('step_date', today);
      await prefs.setInt('daily_steps', 0);
      await prefs.setInt('steps_at_reset', 0);

      setState(() {
        _stepCount = 0;
        _stepsAtLastReset = 0;
      });
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

  void _initPedometer() async {
    bool granted = await Permission.activityRecognition.isGranted;
    if (!granted) {
      granted = await Permission.activityRecognition.request().isGranted;
    }

    if (granted) {
      _stepCountStream = Pedometer.stepCountStream.listen(
        _onStepCount,
        onError: (error) => debugPrint("Step Count Error: $error"),
      );
    }
  }

  Future<void> _syncToBrain({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isSyncing = true;
        _syncSuccess = false;
      });
    }

    try {
      // FIX: Wait for connection!
      await MongoService.instance.getOrConnect();

      final db = MongoService.instance.mobileDb ?? MongoService.instance.db;
      final String collectionName =
          dotenv.env['COLLECTION_NAME'] ?? 'overrides';

      if (db == null) {
        _showError("DB Not Connected");
        setState(() => _isSyncing = false);
        return;
      }

      final String dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

      final collection = db.collection(collectionName);
      final updateData = {
        "date": dateStr,
        "sleep_hours": _sleepHours,
        "feedback_energy": _energyLevel,
        "feedback_stress": _stressLevel,
        "feedback_social": _socialLevel,
        "steps_count": _stepCount,
        "last_updated": DateTime.now().toIso8601String(),
        "device": "android_app_mood_v2"
      };

      await collection.replaceOne(mongo.where.eq('date', dateStr), updateData,
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
      if (!silent)
        _showError("Erreur Réseau: Impossible de joindre le serveur");
    } catch (e) {
      debugPrint("❌ Sync Error: $e");
      if (!silent)
        _showError(
            "Erreur: ${e.toString().replaceAll('ConnectionException', 'Problème de connexion')}");
      if (mounted) setState(() => _isSyncing = false);
    } finally {
      if (mounted && !silent) setState(() => _isSyncing = false);
    }
  }

  // --- WEATHER ---
  Future<void> _fetchWeather() async {
    if (!mounted) return;
    setState(() => _weatherLoading = true);

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint("🚫 Location permission denied");
          setState(() => _temperature = "-");
          return;
        }
      }

      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low);

      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (placemarks.isNotEmpty) {
          setState(() {
            _cityName = placemarks.first.locality ?? "Unknown";
          });
        }
      } catch (e) {
        debugPrint("City Error: $e");
      }

      final url = Uri.parse(
          "https://api.open-meteo.com/v1/forecast?latitude=${position.latitude}&longitude=${position.longitude}&current=temperature_2m");

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final temp = data['current']['temperature_2m'];
        final unit = data['current_units']['temperature_2m'] ?? "°C";
        setState(() => _temperature = "${temp.round()}$unit");
      } else {
        debugPrint("API Error: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("❌ Weather Error: $e");
    } finally {
      if (mounted) setState(() => _weatherLoading = false);
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
              const SizedBox(height: 100), // ADDED PADDING FOR FAB
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Center(
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        borderRadius: BorderRadius.circular(30),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_cityName.isNotEmpty) ...[
              Text(_cityName.toUpperCase(),
                  style: GoogleFonts.inter(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: Colors.white70)),
              Container(
                  height: 12,
                  width: 1,
                  color: Colors.white24,
                  margin: const EdgeInsets.symmetric(horizontal: 12)),
            ],
            if (_temperature.isNotEmpty && _temperature != "-") ...[
              Text(_temperature,
                  style: GoogleFonts.inter(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: Colors.white)),
              Container(
                  height: 12,
                  width: 1,
                  color: Colors.white24,
                  margin: const EdgeInsets.symmetric(horizontal: 12)),
            ],
            Text(DateFormat('dd MMM').format(DateTime.now()).toUpperCase(),
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.white70)),
          ],
        ),
      ),
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
