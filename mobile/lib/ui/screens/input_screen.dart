import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:mongo_dart/mongo_dart.dart' as mongo;
import 'package:sleek_circular_slider/sleek_circular_slider.dart';

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

class _InputScreenState extends State<InputScreen> {
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

  // Stream Subscription
  StreamSubscription<int>? _stepSubscription;
  int _currentSteps = 0;

  @override
  void initState() {
    super.initState();
    _initServices();
    _fetchWeather();
  }

  void _initServices() {
    // Initialize Pedometer Logic via Service
    PedometerService.instance.init();

    // Listen to steps
    _stepSubscription = PedometerService.instance.stepStream.listen((steps) {
      if (mounted) {
        setState(() => _currentSteps = steps);
      }
    });

    // Load initial value immediately
    setState(() {
      _currentSteps = PedometerService.instance.currentSteps;
    });

    // Auto-sync timer could be here, or in the service.
    // Keeping UI specific logic here for now.
  }

  @override
  void dispose() {
    _stepSubscription?.cancel();
    super.dispose();
  }

  // --- ACTIONS ---

  Future<void> _syncToBrain({bool silent = false}) async {
    if (!silent) setState(() => _isSyncing = true);

    try {
      // 1. Get DB Connection
      final db = await DatabaseService.instance.database;
      final collection = await DatabaseService.instance.logsCollection;

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
      await collection.replaceOne(
        mongo.where.eq('date', entry.date),
        entry.toJson(),
        upsert: true,
      );

      debugPrint("✅ Synced: ${entry.toJson()}");

      if (!silent) {
        await HapticFeedback.heavyImpact();
        if (mounted) {
          setState(() {
            _syncSuccess = true;
            _isSyncing = false;
          });
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) setState(() => _syncSuccess = false);
          });
        }
      }
    } catch (e) {
      debugPrint("❌ Sync Error: $e");
      if (!silent) _showError("Sync Error: $e");
      if (mounted) setState(() => _isSyncing = false);
    }
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
        setState(() => _temperature = "${temp.round()}$unit");
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
              Text(_temperature,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
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
                Text(_formatSleep(value),
                    style: AppTheme.headerLarge.copyWith(fontSize: 48)),
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
