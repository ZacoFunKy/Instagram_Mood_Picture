import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../models/mood_entry.dart';
import '../../services/database_service.dart';
import '../../services/pedometer_service.dart';
import '../../services/cache_service.dart';
import '../../services/youtube_music_service.dart';
import '../../services/spotify_enrichment_service.dart';
import '../../services/google_calendar_service.dart';
import '../../services/sleep_tracking_service.dart';
import '../../services/adaptive_weights_service.dart';
import '../../utils/app_theme.dart';
import '../../logic/mood_logic.dart';

// ignore: depend_on_referenced_packages
import 'package:mongo_dart/mongo_dart.dart' as mongo;

class InputScreen extends StatefulWidget {
  const InputScreen({super.key});

  @override
  State<InputScreen> createState() => _InputScreenState();
}

class _InputScreenState extends State<InputScreen> with WidgetsBindingObserver {
  // === STATE VARIABLES ===
  double _sleepHours = 7.5;
  double _energyLevel = 0.5;
  double _stressLevel = 0.5;
  double _socialLevel = 0.5;
  bool _sleepIsAutoDetected = false;

  bool _isSyncing = false;
  String _temperature = "";
  String _cityName = "";
  String _weatherEmoji = "";
  int _currentSteps = 0;
  bool _manualSyncDoneToday = false;

  // Real-time Prediction
  String _predictedMood = "CHILL";
  Timer? _debounceTimer;

  // External Data Status
  bool _isCalendarConnected = false;
  bool _isMusicConnected = false;
  bool _isPedometerActive = false;

  // Cache
  List<Map<String, dynamic>> _todayEvents = [];
  Map<String, dynamic>? _musicMetrics;

  // Services
  final _sleepTrackingService = SleepTrackingService();
  final _calendarService = GoogleCalendarService();
  final _musicService = YouTubeMusicService();
  final _adaptiveService = AdaptiveWeightsService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initServices();
    _loadCachedData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounceTimer?.cancel();
    super.dispose();
  }

  // === INITIALIZATION ===
  Future<void> _initServices() async {
    try {
      // 1. Pedometer
      await PedometerService.instance.init();
      PedometerService.instance.stepStream.listen((steps) {
        if (mounted) setState(() => _currentSteps = steps);
      });
      setState(() => _isPedometerActive = true);

      // 2. Sleep
      await _sleepTrackingService.startTracking();
      final autoSleep = await _sleepTrackingService.getActualSleepHours();
      if (autoSleep != null && autoSleep > 0) {
        if (mounted) {
          setState(() {
            _sleepHours = autoSleep;
            _sleepIsAutoDetected = true;
          });
        }
      }

      // 3. Calendar
      try {
        final events = await _calendarService.getTodayEvents();
        if (mounted) {
          setState(() {
            _todayEvents = events;
            _isCalendarConnected = true;
          });
        }
      } catch (e) {
        debugPrint("Calendar init error: $e");
      }

      // 4. Music
      _musicService.trackStream.listen((track) {
        if (track != null && mounted) {
          setState(() => _isMusicConnected = true);
          // Simulate metrics for now or fetch real ones
          _musicMetrics = {'energy': 0.7, 'valence': 0.5};
          _recalculatePrediction();
        }
      });

      // 5. Weather
      _fetchWeather();

      // Initial Prediction
      _recalculatePrediction();
    } catch (e) {
      debugPrint("❌ Service Init Error: $e");
    }
  }

  Future<void> _fetchWeather() async {
    // Simplified weather fetch for brevity - reusing logic from before but cleaner
    // (In real app, move this to separate service class entirely)
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      Position pos = await Geolocator.getCurrentPosition(
          timeLimit: const Duration(seconds: 5));
      final url = Uri.parse(
          "https://api.open-meteo.com/v1/forecast?latitude=${pos.latitude}&longitude=${pos.longitude}&current=temperature_2m,weathercode");
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted) {
          setState(() {
            _temperature = "${data['current']['temperature_2m']}°C";
            _weatherEmoji = _getWeatherEmoji(data['current']['weathercode']);
          });
          _recalculatePrediction();
        }
      }
    } catch (_) {}
  }

  String _getWeatherEmoji(int code) {
    if (code == 0) return "☀️";
    if (code <= 3) return "⛅";
    if (code <= 48) return "☁️";
    if (code <= 82) return "🌧️";
    return "🌤️";
  }

  Future<void> _loadCachedData() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    if (prefs.getString('cached_date') == today) {
      if (mounted) {
        setState(() {
          _sleepHours = prefs.getDouble('cached_sleep') ?? 7.5;
          _energyLevel = prefs.getDouble('cached_energy') ?? 0.5;
          _stressLevel = prefs.getDouble('cached_stress') ?? 0.5;
          _socialLevel = prefs.getDouble('cached_social') ?? 0.5;
          _manualSyncDoneToday = true;
        });
      }
    }
  }

  // === LOGIC ===
  void _onInputChanged() {
    // Debounce prediction to avoid lag
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 150), () {
      _recalculatePrediction();
    });
  }

  void _recalculatePrediction() {
    final mood = MoodLogic.analyze(
      calendarEvents: _todayEvents,
      sleepHours: _sleepHours,
      weather: _weatherEmoji,
      energyLevel: _energyLevel,
      stressLevel: _stressLevel,
      socialLevel: _socialLevel,
      musicMetrics: _musicMetrics,
    );
    if (mounted && mood != _predictedMood) {
      setState(() => _predictedMood = mood.toUpperCase());
    }
  }

  Future<void> _sync() async {
    setState(() => _isSyncing = true);
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final entry = MoodEntry(
        date: today,
        sleepHours: _sleepHours,
        energy: _energyLevel,
        stress: _stressLevel,
        social: _socialLevel,
        steps: _currentSteps,
        lastUpdated: DateTime.now(),
        device: "android_app_v2",
        // Additional fields...
      );

      final collection = await DatabaseService.instance.overrides;
      await collection.replaceOne(mongo.where.eq('date', today), entry.toJson(),
          upsert: true);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_date', today);
      await prefs.setDouble('cached_sleep', _sleepHours);
      await prefs.setDouble('cached_energy', _energyLevel);
      await prefs.setDouble('cached_stress', _stressLevel);
      await prefs.setDouble('cached_social', _socialLevel);

      if (mounted) {
        setState(() {
          _manualSyncDoneToday = true;
          _isSyncing = false;
        });
        _showSuccess();
      }
    } catch (e) {
      debugPrint("Sync error: $e");
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  void _showSuccess() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: const Text("Synced successfully!"),
          backgroundColor: AppTheme.neonGreen),
    );
  }

  // === UI BUILDER ===
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Ensure dark background
      body: SizedBox.expand(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 60, 20, 100),
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              const SizedBox(height: 24),
              _buildConnectivityRow(),
              const SizedBox(height: 24),
              _buildGlassContainer(
                child: _buildSleepSection(),
              ),
              const SizedBox(height: 16),
              _buildGlassContainer(
                child: _buildMetricsSection(),
              ),
              const SizedBox(height: 16),
              _buildPredictionCard(),
              const SizedBox(height: 24),
              _buildSyncButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGlassContainer({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: child,
          ),
        ),
      ),
    ).animate().fadeIn().slideY(begin: 0.1, end: 0);
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("DAILY DATA",
                style: AppTheme.headerLarge.copyWith(fontSize: 28)),
            Text(DateFormat('EEEE, d MMM').format(DateTime.now()).toUpperCase(),
                style: AppTheme.subText),
          ],
        ),
        if (_weatherEmoji.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Text(_weatherEmoji, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 8),
                Text(_temperature,
                    style: AppTheme.valueLarge.copyWith(fontSize: 14)),
              ],
            ),
          )
      ],
    );
  }

  Widget _buildConnectivityRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildStatusChip(Icons.calendar_today, "Events", _isCalendarConnected),
        _buildStatusChip(Icons.music_note, "Music", _isMusicConnected),
        _buildStatusChip(Icons.directions_walk, "Steps", _isPedometerActive),
      ],
    );
  }

  Widget _buildStatusChip(IconData icon, String label, bool isActive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isActive
            ? AppTheme.neonGreen.withOpacity(0.1)
            : Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: isActive
                ? AppTheme.neonGreen.withOpacity(0.5)
                : Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Icon(icon,
              size: 14, color: isActive ? AppTheme.neonGreen : Colors.grey),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  color: isActive ? AppTheme.neonGreen : Colors.grey,
                  fontSize: 10,
                  fontWeight: FontWeight.bold))
        ],
      ),
    );
  }

  // === SLEEP SECTION ===
  Widget _buildSleepSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.bedtime_rounded,
                    color: AppTheme.neonPurple, size: 20),
                const SizedBox(width: 8),
                Text("SLEEP DURATION", style: AppTheme.labelSmall),
              ],
            ),
            if (_sleepIsAutoDetected)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: AppTheme.neonCyan.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4)),
                child: const Text("AUTO",
                    style: TextStyle(
                        color: AppTheme.neonCyan,
                        fontSize: 8,
                        fontWeight: FontWeight.bold)),
              )
          ],
        ),
        const SizedBox(height: 16),
        Center(
          child: GestureDetector(
            onTap: _showSleepInputDialog,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                  border: Border.all(color: Colors.white24),
                  borderRadius: BorderRadius.circular(12)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(_sleepHours.toStringAsFixed(1),
                      style: GoogleFonts.spaceMono(
                          fontSize: 42,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                  const SizedBox(width: 4),
                  Text("h",
                      style: TextStyle(color: Colors.white54, fontSize: 20)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: AppTheme.neonPurple,
            inactiveTrackColor: Colors.white10,
            thumbColor: Colors.white,
            overlayColor: AppTheme.neonPurple.withOpacity(0.2),
            trackHeight: 6,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
          ),
          child: Slider(
            value: _sleepHours,
            min: 0,
            max: 12,
            divisions: 24, // 0.5 steps
            onChanged: (val) {
              setState(() {
                _sleepHours = val;
                _sleepIsAutoDetected = false;
              });
              _onInputChanged();
            },
          ),
        ),
      ],
    );
  }

  void _showSleepInputDialog() {
    final controller = TextEditingController(text: _sleepHours.toString());
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              backgroundColor: const Color(0xFF1E1E1E),
              title: const Text("Enter Sleep Hours",
                  style: TextStyle(color: Colors.white)),
              content: TextField(
                controller: controller,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24)),
                  focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: AppTheme.neonPurple)),
                ),
              ),
              actions: [
                TextButton(
                    child: const Text("Cancel"),
                    onPressed: () => Navigator.pop(context)),
                TextButton(
                    child: const Text("Set",
                        style: TextStyle(color: AppTheme.neonPurple)),
                    onPressed: () {
                      final val = double.tryParse(controller.text);
                      if (val != null && val >= 0 && val <= 24) {
                        setState(() {
                          _sleepHours = val;
                          _sleepIsAutoDetected = false;
                        });
                        _onInputChanged();
                      }
                      Navigator.pop(context);
                    }),
              ],
            ));
  }

  // === METRICS SECTION ===
  Widget _buildMetricsSection() {
    return Column(
      children: [
        _buildEnhancedSlider("ENERGY", "⚡", _energyLevel, AppTheme.neonGreen,
            (v) => setState(() => _energyLevel = v)),
        const Divider(color: Colors.white10, height: 24),
        _buildEnhancedSlider("STRESS", "🧠", _stressLevel, AppTheme.neonPink,
            (v) => setState(() => _stressLevel = v)),
        const Divider(color: Colors.white10, height: 24),
        _buildEnhancedSlider("SOCIAL", "💬", _socialLevel, AppTheme.neonBlue,
            (v) => setState(() => _socialLevel = v)),
      ],
    );
  }

  Widget _buildEnhancedSlider(String label, String icon, double value,
      Color color, Function(double) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(icon, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Text(label, style: AppTheme.labelSmall),
              ],
            ),
            Text("${(value * 100).toInt()}%",
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace')),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildStepButton(Icons.remove, () {
              final newValue = (value - 0.05).clamp(0.0, 1.0);
              onChanged(newValue);
              _onInputChanged();
            }),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: color,
                  inactiveTrackColor: Colors.white10,
                  thumbColor: Colors.white,
                  trackHeight: 4,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 8),
                ),
                child: Slider(
                  value: value,
                  min: 0,
                  max: 1,
                  divisions: 20, // 5% increments
                  onChanged: (val) {
                    onChanged(val);
                    _onInputChanged();
                  },
                ),
              ),
            ),
            _buildStepButton(Icons.add, () {
              final newValue = (value + 0.05).clamp(0.0, 1.0);
              onChanged(newValue);
              _onInputChanged();
            }),
          ],
        ),
      ],
    );
  }

  Widget _buildStepButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white70, size: 16),
      ),
    );
  }

  // === PREDICTION SECTION ===
  Widget _buildPredictionCard() {
    Color glow = _getMoodColor(_predictedMood);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: glow.withOpacity(0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: glow.withOpacity(0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
              color: glow.withOpacity(0.1), blurRadius: 20, spreadRadius: 2),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, color: glow, size: 32),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("LIVE PREDICTION",
                    style: TextStyle(
                        color: Colors.white38,
                        fontSize: 10,
                        letterSpacing: 1.5)),
                Text(_predictedMood,
                    style: GoogleFonts.spaceMono(
                        color: glow,
                        fontWeight: FontWeight.bold,
                        fontSize: 24,
                        letterSpacing: 1)),
              ],
            ),
          ),
        ],
      ),
    )
        .animate(target: _predictedMood.isNotEmpty ? 1 : 0)
        .shimmer(duration: 1000.ms, color: glow.withOpacity(0.5));
  }

  // === SYNC BUTTON ===
  Widget _buildSyncButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isSyncing ? null : _sync,
        style: ElevatedButton.styleFrom(
          backgroundColor:
              _manualSyncDoneToday ? AppTheme.neonGreen : AppTheme.neonPurple,
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 8,
          shadowColor:
              (_manualSyncDoneToday ? AppTheme.neonGreen : AppTheme.neonPurple)
                  .withOpacity(0.5),
        ),
        child: _isSyncing
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2))
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(_manualSyncDoneToday
                      ? Icons.check_circle
                      : Icons.cloud_upload),
                  const SizedBox(width: 8),
                  Text(_manualSyncDoneToday ? "SYNCED" : "UPDATE MOOD",
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
      ),
    );
  }

  Color _getMoodColor(String mood) {
    if (mood.contains('TIRED')) return Colors.orange;
    if (mood.contains('ENERGETIC') || mood.contains('PUMPED'))
      return AppTheme.neonGreen;
    if (mood.contains('INTENSE')) return AppTheme.neonPink;
    return AppTheme.neonBlue;
  }
}
