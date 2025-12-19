import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:mongo_dart/mongo_dart.dart' as mongo;
import 'package:sleek_circular_slider/sleek_circular_slider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/mood_entry.dart';
import '../../services/database_service.dart';
import '../../services/pedometer_service.dart';
import '../../utils/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/interactive_segmented_bar.dart';
import '../widgets/neon_btn.dart';

class InputScreen extends StatefulWidget {
  const InputScreen({super.key});

  @override
  State<InputScreen> createState() => _InputScreenState();
}

class _InputScreenState extends State<InputScreen> with WidgetsBindingObserver {
  // State
  double _sleepHours = 7.5;
  double _energyLevel = 0.5;
  double _stressLevel = 0.5;
  double _socialLevel = 0.5;

  bool _isSyncing = false;
  bool _syncSuccess = false;
  String _temperature = "";
  String _cityName = "";
  bool _weatherLoading = false;
  String? _lastLoadedDate;

  // Stream Subscription
  StreamSubscription<int>? _stepSubscription;
  int _currentSteps = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initServices();
    _loadCachedLocation(); // Instant Load
    _fetchWeather(); // Background Refresh
    _checkTodayData(); // Check persistence
  }

  /// Check if we already have data for today in the database
  Future<void> _checkTodayData() async {
    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      if (_lastLoadedDate == dateStr) return; // Prevent double loads

      // Short timeout for UI initialization
      final collection = await DatabaseService.instance.overrides
          .timeout(const Duration(seconds: 5));

      debugPrint("🔍 Checking Persistence for $dateStr...");
      final doc = await collection.findOne(mongo.where.eq('date', dateStr));

      if (doc != null) {
        final entry = MoodEntry.fromJson(doc);
        if (mounted) {
          setState(() {
            _sleepHours = entry.sleepHours;
            // Restore sliders (use default if null, though DB usually has values)
            _energyLevel = entry.energy ?? 0.5;
            _stressLevel = entry.stress ?? 0.5;
            _socialLevel = entry.social ?? 0.5;
            _lastLoadedDate = dateStr;
          });
          debugPrint("✅ Persistence: Restored today's values");
        }
      } else {
        debugPrint("ℹ️ No persistence found for today.");
      }
    } catch (e) {
      debugPrint("ℹ️ Persistence check failed (Offline?): $e");
    }
  }

  Future<void> _loadCachedLocation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final city = prefs.getString('cached_city');
      final temp = prefs.getString('cached_temp');
      if (city != null && mounted) {
        setState(() {
          _cityName = city;
          if (temp != null) _temperature = temp;
        });
        debugPrint("📍 Loaded Cached Location: $city");
      }
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint("🔄 App Resumed: Retrying Weather/Location...");
      _fetchWeather();
      _checkTodayData(); // Re-check in case background sync happened
    }
  }

  void _initServices() {
    // Initialize Pedometer Logic via Service
    PedometerService.instance.init();

    // Listen to steps
    _stepSubscription =
        PedometerService.instance.stepStream.listen((steps) async {
      if (mounted) {
        setState(() => _currentSteps = steps);
      }
      // Cache for background service
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('last_known_steps', steps);
    });

    // Load initial value immediately
    setState(() {
      _currentSteps = PedometerService.instance.currentSteps;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stepSubscription?.cancel();
    super.dispose();
  }

  // --- ACTIONS ---

  Future<void> _syncToBrain({bool silent = false}) async {
    if (!silent) setState(() => _isSyncing = true);

    final uri = dotenv.env['MONGODB_URI'] ?? dotenv.env['MONGO_URI'];
    if (uri == null || uri.isEmpty) {
      debugPrint("❌ ERROR: MONGODB_URI (or MONGO_URI) is missing or empty.");
      if (!silent) _showError("Config Error: Missing Database URI");
      if (mounted) setState(() => _isSyncing = false);
      return;
    }

    try {
      // 1. Get DB Connection (target: mobile.overrides)
      final collection = await DatabaseService.instance.overrides
          .timeout(const Duration(seconds: 30));

      // 2. Prepare Data Model
      final entry = MoodEntry(
        date: DateFormat('yyyy-MM-dd').format(DateTime.now()),
        sleepHours: _sleepHours,
        energy: _energyLevel,
        stress: _stressLevel,
        social: _socialLevel,
        steps: _currentSteps,
        location: _cityName.isNotEmpty ? _cityName : null,
        lastUpdated: DateTime.now(),
        device: "android_app_mood_v2",
      );

      // 3. Upsert
      await collection
          .replaceOne(
            mongo.where.eq('date', entry.date),
            entry.toJson(),
            upsert: true,
          )
          .timeout(const Duration(seconds: 30));

      debugPrint("✅ Synced: ${entry.toJson()}");

      if (!silent) {
        await HapticFeedback.heavyImpact();
        if (mounted) {
          setState(() {
            _syncSuccess = true;
            _isSyncing = false;
          });
          _showSuccessDialog(); // New Pop-up

          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) setState(() => _syncSuccess = false);
          });
        }
      }
    } on TimeoutException {
      debugPrint("❌ Sync Timeout");
      if (!silent) _showError("Connection timed out. Check your internet.");
      if (mounted) setState(() => _isSyncing = false);
    } catch (e) {
      debugPrint("❌ Sync Error: $e");
      if (!silent) _showError("Sync Failed: Check Internet");
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Center(
        child: GlassCard(
          padding: const EdgeInsets.all(32),
          borderRadius: BorderRadius.circular(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.neonGreen.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check,
                    color: AppTheme.neonGreen, size: 48),
              ).animate().scale(curve: Curves.elasticOut, duration: 600.ms),
              const SizedBox(height: 24),
              Text(
                "DATA SYNCED",
                style: AppTheme.headerLarge.copyWith(fontSize: 24),
              ),
              const SizedBox(height: 8),
              Text(
                "Your mood data is safe.",
                style: AppTheme.subText,
              ),
            ],
          ),
        ),
      ).animate().fadeIn().scale(),
    );
  }

  Future<void> _fetchWeather() async {
    if (!mounted) return;
    setState(() => _weatherLoading = true);

    try {
      // Permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _temperature = "-";
            _weatherLoading = false;
          });
          return;
        }
      }

      // Position
      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low);

      // City Name
      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(
            position.latitude, position.longitude);
        if (placemarks.isNotEmpty) {
          setState(() => _cityName = placemarks.first.locality ?? "Unknown");
        }
      } catch (_) {}

      // API
      final url = Uri.parse(
          "https://api.open-meteo.com/v1/forecast?latitude=${position.latitude}&longitude=${position.longitude}&current=temperature_2m");
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final temp = data['current']['temperature_2m'];
        final unit = data['current_units']['temperature_2m'] ?? "°C";

        if (mounted) {
          setState(() => _temperature = "${temp.round()}$unit");
        }

        // Cache It
        final prefs = await SharedPreferences.getInstance();
        if (_cityName.isNotEmpty) {
          await prefs.setString('cached_city', _cityName);
        }
        await prefs.setString('cached_temp', _temperature);
      }
    } catch (e) {
      debugPrint("Weather Error: $e");
    } finally {
      if (mounted) setState(() => _weatherLoading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppTheme.neonPink),
    );
  }

  String _formatSleep(double value) {
    int minutes = (value * 60).round();
    int h = minutes ~/ 60;
    int m = minutes % 60;
    return '${h}h${m.toString().padLeft(2, '0')}';
  }

  // --- UI BUILDING ---

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            const SizedBox(height: 40),
            _buildSleepSlider(),
            const SizedBox(height: 40),
            Text("VITAL METRICS", style: AppTheme.labelSmall),
            const SizedBox(height: 20),
            _buildMetrics(),
            const SizedBox(height: 24),
            _buildStepCounter(),
            const SizedBox(height: 40),
            _buildSyncButton(),
            const SizedBox(height: 100),
          ],
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
              Text(_cityName.toUpperCase(), style: AppTheme.subText),
              const VerticalDivider(),
            ],
            if (_temperature.isNotEmpty) ...[
              // Fixed style to match City/Date (AppTheme.subText)
              Text(_temperature, style: AppTheme.subText),
              const VerticalDivider(),
            ],
            Text(DateFormat('dd MMM').format(DateTime.now()).toUpperCase(),
                style: AppTheme.subText),
          ],
        ),
      ),
    );
  }

  Widget _buildSleepSlider() {
    return Center(
      child: Container(
        width: 250,
        height: 250,
        decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [
          BoxShadow(
            color: AppTheme.neonPurple.withOpacity(0.2),
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
              progressBarColor: AppTheme.neonPurple,
              trackColor: Colors.white10,
              dotColor: Colors.white,
              shadowColor: AppTheme.neonPurple.withOpacity(0.5),
              shadowMaxOpacity: 0.5,
            ),
          ),
          innerWidget: (value) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                InkWell(
                  onTap: () => _pickSleepTimeManual(),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Text(_formatSleep(value),
                        style: AppTheme.headerLarge.copyWith(fontSize: 48)),
                  ),
                ),
                Text("SLEEP DURATION", style: AppTheme.labelSmall),
              ],
            ),
          ),
          onChange: (value) {
            double snapped = (value * 4).round() / 4;
            if (snapped != _sleepHours) {
              HapticFeedback.selectionClick();
              setState(() => _sleepHours = snapped);
            }
          },
        ),
      ),
    ).animate().fadeIn().scale();
  }

  Future<void> _pickSleepTimeManual() async {
    // Show a simple time picker-like dialog or just a text input for hours
    // Simplified: Circular slider is intuitive, but precise editing can be done via TimePicker
    // We treat "Hours" and "Minutes" as the input.

    TimeOfDay? picked = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(
            hour: _sleepHours.floor(),
            minute: ((_sleepHours - _sleepHours.floor()) * 60).round()),
        builder: (context, child) {
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
            child: Theme(
                data: ThemeData.dark().copyWith(
                    colorScheme: ColorScheme.dark(
                  primary: AppTheme.neonPurple,
                  onPrimary: Colors.white,
                  surface: const Color(0xFF1E1E1E),
                  onSurface: Colors.white,
                )),
                child: child!),
          );
        });

    if (picked != null) {
      double newHours = picked.hour + (picked.minute / 60.0);
      if (newHours > 12) {
        // Warning if > 12h? Or just clamp?
        // Let's allow it but the slider might look weird if > max.
        // Our slider max is 12. Let's clamp to 12 for UI consistency or assume user knows.
        if (newHours > 12) newHours = 12;
      }
      setState(() => _sleepHours = newHours);
    }
  }

  Widget _buildMetrics() {
    return Column(
      children: [
        _slider("ENERGY", "⚡", _energyLevel, AppTheme.neonGreen,
            (v) => setState(() => _energyLevel = v)),
        _slider("STRESS", "🧠", _stressLevel, AppTheme.neonPink,
            (v) => setState(() => _stressLevel = v)),
        _slider("SOCIAL", "💬", _socialLevel, AppTheme.neonBlue,
            (v) => setState(() => _socialLevel = v)),
      ],
    );
  }

  Widget _slider(String label, String emoji, double val, Color color,
      Function(double) change) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: InteractiveSegmentedBar(
        label: label,
        emoji: emoji,
        value: val,
        color: color,
        onChanged: change,
      ).animate().fadeIn().slideX(),
    );
  }

  Widget _buildStepCounter() {
    // Determine goal handling
    bool goalMet = _currentSteps >= 10000;

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
                  Text("STEPS TODAY", style: AppTheme.labelSmall),
                  const SizedBox(height: 4),
                  Text(
                    NumberFormat('#,###').format(_currentSteps),
                    style: AppTheme.valueLarge,
                  ),
                ],
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: goalMet ? AppTheme.neonGreen : Colors.white10,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              goalMet
                  ? "GOAL"
                  : "${(((_currentSteps / 10000) * 100).toInt())}%",
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: goalMet ? Colors.black : Colors.white54,
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn().slideY(begin: 0.2, end: 0);
  }

  Widget _buildSyncButton() {
    return NeonBtn(
      text: _syncSuccess ? "SYNCED" : "UPDATE MOOD",
      color: _syncSuccess ? AppTheme.neonGreen : AppTheme.neonPurple,
      isLoading: _isSyncing,
      onTap: _syncToBrain,
    ).animate().fadeIn().scale();
  }
}

class VerticalDivider extends StatelessWidget {
  const VerticalDivider({super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
        height: 12,
        width: 1,
        color: Colors.white24,
        margin: const EdgeInsets.symmetric(horizontal: 12));
  }
}
