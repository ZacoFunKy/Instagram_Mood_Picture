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
import '../../utils/mood_analyzer.dart';
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
  String? _lastLoadedDate;
  bool _manualSyncDoneToday = false;

  // Backend analyzer context
  String? _backendAlgoPrediction;
  Map<String, dynamic>? _backendMusicMetrics;
  String? _backendCalendarSummary;
  String? _backendWeatherSummary;

  String _weatherEmoji = ""; // Weather emoji (☀️🌧️⛈️❄️)

  // Stream Subscription
  StreamSubscription<int>? _stepSubscription;
  int _currentSteps = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initServices();
    _loadCachedLocation(); // Instant Load
    _loadCachedInputs(); // Instant Load Inputs
    _fetchWeather(); // Background Refresh
    _checkTodayData(); // Check persistence
    _checkManualSyncStatus(); // Check if manual sync done today
    _loadBackendPrediction(); // Load backend analyzer context
  }

  /// Check if manual sync was performed today
  Future<void> _checkManualSyncStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastSyncStr = prefs.getString('last_manual_sync');
      
      if (lastSyncStr != null) {
        final lastSync = DateTime.parse(lastSyncStr);
        final today = DateTime.now();
        
        // Check if sync was today
        if (lastSync.year == today.year && 
            lastSync.month == today.month && 
            lastSync.day == today.day) {
          if (mounted) {
            setState(() => _manualSyncDoneToday = true);
          }
          debugPrint("✅ Manual sync detected today at ${lastSync.hour}:${lastSync.minute.toString().padLeft(2, '0')}");
        }
      }
    } catch (e) {
      debugPrint("⚠️ Manual sync status check error: $e");
    }
  }

  /// Load backend prediction data (calendar, music, weather) from daily_logs
  Future<void> _loadBackendPrediction() async {
    try {
      final collection = await DatabaseService.instance.dailyLogs;
      final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final doc = await collection
          .findOne(mongo.where.eq('date', dateStr).sortBy('last_updated', descending: true))
          .timeout(const Duration(seconds: 8));

      if (doc != null && mounted) {
        setState(() {
          _backendAlgoPrediction = doc['algo_prediction'] as String?;
          _backendMusicMetrics = (doc['music_metrics'] as Map?)?.cast<String, dynamic>();
          _backendCalendarSummary = doc['calendar_summary'] as String?;
          _backendWeatherSummary = doc['weather_summary'] as String?;
        });
        
        // Log loaded data for debugging
        debugPrint("✅ Backend analyzer context loaded:");
        debugPrint("   - Music: ${_backendMusicMetrics != null ? 'Available' : 'Missing'}");
        debugPrint("   - Calendar: ${_backendCalendarSummary != null ? 'Available' : 'Missing'}");
        debugPrint("   - Weather: ${_backendWeatherSummary != null ? 'Available' : 'Missing'}");
        debugPrint("   - Algo prediction: $_backendAlgoPrediction");
      } else {
        debugPrint("ℹ️ No backend data found for today (first run?)");
      }
    } catch (e) {
      debugPrint("⚠️ Backend prediction fetch failed: $e");
    }
  }

  /// Check if we already have data for today in the database
  Future<void> _checkTodayData({bool retry = true}) async {
    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      if (_lastLoadedDate == dateStr) return; // Prevent double loads

      // Increased timeout + Retry Logic
      debugPrint("🔍 Checking Persistence for $dateStr...");

      mongo.DbCollection? collection;
      try {
        collection = await DatabaseService.instance.overrides
            .timeout(const Duration(seconds: 10)); // Increased limit
      } catch (e) {
        if (retry) {
          debugPrint("⚠️ DB not ready, retrying persistence check in 2s...");
          await Future.delayed(const Duration(seconds: 2));
          return _checkTodayData(retry: false);
        }
        rethrow;
      }

      final doc = await collection.findOne(mongo.where.eq('date', dateStr))
          .timeout(const Duration(seconds: 8));

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

          // Update cache with latest DB truth
          final prefs = await SharedPreferences.getInstance();
          await Future.wait([
            prefs.setDouble('cached_sleep', _sleepHours),
            prefs.setDouble('cached_energy', _energyLevel),
            prefs.setDouble('cached_stress', _stressLevel),
            prefs.setDouble('cached_social', _socialLevel),
          ]);

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
      final cachedCity = prefs.getString('cached_city');
      final cachedTemp = prefs.getString('cached_temp');
      final cachedCityDate = prefs.getString('cached_city_date');
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

      // N'utiliser le cache que s'il date d'aujourd'hui
      if (cachedCity != null && cachedCityDate == today && mounted) {
        setState(() {
          _cityName = cachedCity;
          if (cachedTemp != null) _temperature = cachedTemp;
        });
        debugPrint("📍 Loaded Cached Location: $cachedCity (today)");
      } else {
        debugPrint("ℹ️ Cached location is stale or missing; will refetch.");
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

  Future<void> _loadCachedInputs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final cachedDate = prefs.getString('cached_date');

      // Si la date a changé (nouveau jour), réinitialiser les valeurs
      if (cachedDate != today) {
        debugPrint("🔄 New day detected! Resetting values to defaults.");
        await prefs.setString('cached_date', today);
        await prefs.remove('cached_sleep');
        await prefs.remove('cached_energy');
        await prefs.remove('cached_stress');
        await prefs.remove('cached_social');
        
        // Réinitialiser les valeurs par défaut
        if (mounted) {
          setState(() {
            _sleepHours = 7.5;
            _energyLevel = 0.5;
            _stressLevel = 0.5;
            _socialLevel = 0.5;
          });
        }
        return;
      }

      // Charger les valeurs en cache si même jour
      if (mounted) {
        setState(() {
          if (prefs.containsKey('cached_sleep')) {
            _sleepHours = prefs.getDouble('cached_sleep') ?? 7.5;
          }
          if (prefs.containsKey('cached_energy')) {
            _energyLevel = prefs.getDouble('cached_energy') ?? 0.5;
          }
          if (prefs.containsKey('cached_stress')) {
            _stressLevel = prefs.getDouble('cached_stress') ?? 0.5;
          }
          if (prefs.containsKey('cached_social')) {
            _socialLevel = prefs.getDouble('cached_social') ?? 0.5;
          }
        });
        debugPrint("💾 Loaded Cached Inputs for $today");
      }
    } catch (e) {
      debugPrint("⚠️ Cache Load Error: $e");
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
      // 1. Get DB Connection (target: mobile.overrides) with timeout
      final collection = await DatabaseService.instance.overrides
          .timeout(const Duration(seconds: 20));

      // 2. Prepare data with proper location handling
      final prefs = await SharedPreferences.getInstance();
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final cachedCity = prefs.getString('cached_city');
      String? locationToUse;

      if (_cityName.isNotEmpty) {
        locationToUse = _cityName; // Use fresh city if available
      } else if (cachedCity != null && cachedCity.isNotEmpty) {
        locationToUse = cachedCity; // Fallback to last known city
      }

      final entry = MoodEntry(
        date: today,
        sleepHours: _sleepHours,
        energy: _energyLevel,
        stress: _stressLevel,
        social: _socialLevel,
        steps: _currentSteps,
        location: locationToUse,
        lastUpdated: DateTime.now(),
        device: "android_app_mood_v2",
      );

      // 3. Upsert with timeout optimization
      await collection
          .replaceOne(
            mongo.where.eq('date', entry.date),
            entry.toJson(),
            upsert: true,
          )
          .timeout(const Duration(seconds: 25));

      debugPrint("✅ Synced: ${entry.toJson()}");

      if (!silent) {
        // Cache locally for next startup + track manual sync
        await Future.wait([
          prefs.setString('cached_date', today),
          prefs.setDouble('cached_sleep', _sleepHours),
          prefs.setDouble('cached_energy', _energyLevel),
          prefs.setDouble('cached_stress', _stressLevel),
          prefs.setDouble('cached_social', _socialLevel),
          prefs.setString('last_manual_sync', DateTime.now().toIso8601String()),  // Track manual sync
        ]);

        await HapticFeedback.heavyImpact();
        if (mounted) {
          setState(() {
            _syncSuccess = true;
            _manualSyncDoneToday = true;  // Persist across day
            _isSyncing = false;
          });
          _showSuccessDialog();

          // Reset only _syncSuccess animation after 2 seconds, keep _manualSyncDoneToday
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

    try {
      final prefs = await SharedPreferences.getInstance();
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      
      // Check cache first - reuse weather for entire day
      final cachedWeatherDate = prefs.getString('cached_weather_date');
      if (cachedWeatherDate == today) {
        final cachedTemp = prefs.getString('cached_temp');
        final cachedCity = prefs.getString('cached_city');
        if (cachedTemp != null && cachedCity != null) {
          if (mounted) {
            setState(() {
              _temperature = cachedTemp;
              _cityName = cachedCity;
            });
          }
          debugPrint("✅ Using cached weather for $today");
          return;
        }
      }

      // Permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) setState(() {
            _cityName = "";
            _temperature = "-";
          });
          return;
        }
      }

      // Get position with timeout
      Position position;
      try {
        position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.medium,
            timeLimit: const Duration(seconds: 10))
            .timeout(const Duration(seconds: 12));
      } catch (e) {
        debugPrint("⚠️ Location fetch timeout or error: $e");
        if (mounted) setState(() => _cityName = "");
        return;
      }

      // Reverse geocoding for city name
      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(
            position.latitude, position.longitude);
        if (placemarks.isNotEmpty && mounted) {
          setState(() => _cityName = placemarks.first.locality ?? "Unknown");
        }
      } catch (_) {
        if (mounted) setState(() => _cityName = "");
      }

      // Fetch weather with timeout
      final url = Uri.parse(
          "https://api.open-meteo.com/v1/forecast?latitude=${position.latitude}&longitude=${position.longitude}&current=temperature_2m");
      
      final response = await http.get(url)
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final temp = data['current']['temperature_2m'];
        final unit = data['current_units']['temperature_2m'] ?? "°C";

        final tempStr = "${temp.round()}$unit";

        if (mounted) {
          setState(() => _temperature = tempStr);
        }

        // Cache weather + date
        await Future.wait([
          if (_cityName.isNotEmpty)
            prefs.setString('cached_city', _cityName),
          prefs.setString('cached_temp', tempStr),
          prefs.setString('cached_weather_date', today),
        ]);
        
        debugPrint("✅ Weather cached for $today");
      } else {
        debugPrint("⚠️ Weather API error: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("⚠️ Weather Error: $e");
      if (mounted) setState(() => _cityName = "");
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            const SizedBox(height: 12),
            // Sleep + Metrics + Steps in compact grid
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left: Sleep Selector (Compact)
                Flexible(
                  flex: 2,
                  child: _buildCompactSleepSelector(),
                ),
                const SizedBox(width: 12),
                // Right: Metrics Stack
                Flexible(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildCompactMetrics(),
                      const SizedBox(height: 12),
                      _buildStepCounter(),
                      const SizedBox(height: 12),
                      _buildSleepQualityBadge(),
                      const SizedBox(height: 12),
                      _buildDataConfidenceScore(),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildLivePredictionPreview(),
            const SizedBox(height: 12),
            _buildSyncButton(),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      borderRadius: BorderRadius.circular(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Location & Weather
              Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_cityName.isNotEmpty) ...[
                      Text(_cityName.toUpperCase(), 
                        style: AppTheme.subText.copyWith(fontSize: 10)),
                      const SizedBox(width: 6),
                    ],
                    if (_temperature.isNotEmpty)
                      Text(_temperature, 
                        style: AppTheme.subText.copyWith(fontSize: 10)),
                  ],
                ),
              ),
              // Date
              Text(DateFormat('dd MMM').format(DateTime.now()).toUpperCase(),
                  style: AppTheme.subText.copyWith(fontSize: 10)),
            ],
          ),
          // Manual sync indicator - compact and prominent
          if (_manualSyncDoneToday)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.neonGreen.withOpacity(0.2),
                      AppTheme.neonGreen.withOpacity(0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.neonGreen.withOpacity(0.5),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.neonGreen.withOpacity(0.3),
                      blurRadius: 8,
                      spreadRadius: 0,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_rounded, 
                      color: AppTheme.neonGreen, 
                      size: 16),
                    const SizedBox(width: 6),
                    Text(
                      "SYNCED TODAY",
                      style: GoogleFonts.spaceMono(
                        color: AppTheme.neonGreen,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 400.ms).scale(begin: const Offset(0.8, 0.8)),
            ),
        ],
      ),
    );
  }

  // Compact sleep selector for no-scroll layout
  Widget _buildCompactSleepSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.neonPurple.withOpacity(0.15),
            AppTheme.neonPurple.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.neonPurple.withOpacity(0.3), width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("SLEEP", style: AppTheme.labelSmall.copyWith(fontSize: 11)),
          const SizedBox(height: 12),
          // Display with tap to edit
          InkWell(
            onTap: () => _pickSleepTimeManual(),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.neonPurple.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    _formatSleep(_sleepHours),
                    style: GoogleFonts.spaceMono(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.neonPurple,
                    ),
                  ),
                  Text("tap to edit", style: AppTheme.labelSmall.copyWith(fontSize: 9, color: Colors.white54)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Compact slider
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 6,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: _sleepHours,
              min: 0,
              max: 12,
              activeColor: AppTheme.neonPurple,
              inactiveColor: Colors.white10,
              onChanged: (value) {
                double snapped = (value * 4).round() / 4;
                if (snapped != _sleepHours) {
                  HapticFeedback.selectionClick();
                  setState(() => _sleepHours = snapped);
                }
              },
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("0h", style: AppTheme.subText.copyWith(fontSize: 10)),
                Text("6h", style: AppTheme.subText.copyWith(fontSize: 10)),
                Text("12h", style: AppTheme.subText.copyWith(fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Compact metrics for no-scroll layout
  Widget _buildCompactMetrics() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.06),
            Colors.white.withOpacity(0.02),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("VITAL METRICS", style: AppTheme.labelSmall.copyWith(fontSize: 11)),
          const SizedBox(height: 12),
          _buildCompactMetricBar("ENERGY", "⚡", _energyLevel, AppTheme.neonGreen,
              (v) => setState(() => _energyLevel = v)),
          const SizedBox(height: 10),
          _buildCompactMetricBar("STRESS", "🧠", _stressLevel, AppTheme.neonPink,
              (v) => setState(() => _stressLevel = v)),
          const SizedBox(height: 10),
          _buildCompactMetricBar("SOCIAL", "💬", _socialLevel, AppTheme.neonBlue,
              (v) => setState(() => _socialLevel = v)),
        ],
      ),
    );
  }

  Widget _buildCompactMetricBar(String label, String emoji, double val, Color color,
      Function(double) change) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text("$emoji $label", style: AppTheme.labelSmall.copyWith(fontSize: 12)),
            Text("${(val * 100).toInt()}%", style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 8,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: val,
              min: 0,
              max: 1,
              activeColor: color,
              inactiveColor: color.withOpacity(0.2),
              onChanged: change,
            ),
          ),
        ),
      ],
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.08),
            Colors.white.withOpacity(0.03),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: goalMet ? AppTheme.neonGreen.withOpacity(0.4) : Colors.white.withOpacity(0.15),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.directions_walk,
                    color: goalMet ? AppTheme.neonGreen : Colors.orange,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("STEPS", style: AppTheme.labelSmall.copyWith(fontSize: 10)),
                      Text(
                        NumberFormat('#,###').format(_currentSteps),
                        style: GoogleFonts.spaceMono(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: goalMet ? AppTheme.neonGreen.withOpacity(0.2) : Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  goalMet ? "✓ GOAL" : "${(((_currentSteps / 10000) * 100).toInt())}%",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: goalMet ? AppTheme.neonGreen : Colors.orange,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSyncButton() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppTheme.neonGreen.withOpacity(0.3),
            blurRadius: 16,
            spreadRadius: 0,
          ),
        ],
      ),
      child: NeonBtn(
        text: _syncSuccess ? "SYNCED" : "UPDATE MOOD",
        color: _syncSuccess ? AppTheme.neonGreen : AppTheme.neonPurple,
        isLoading: _isSyncing,
        onTap: _syncToBrain,
      ),
    ).animate().fadeIn().scale();
  }

  Widget _buildSleepQualityBadge() {
    // Sleep quality: < 6h = bad, 6-8h = good, > 8h = too much
    String quality;
    Color color;
    String emoji;
    
    if (_sleepHours < 6) {
      quality = "INSUFFICIENT";
      color = AppTheme.neonPink;
      emoji = "😴";
    } else if (_sleepHours <= 8) {
      quality = "OPTIMAL";
      color = AppTheme.neonGreen;
      emoji = "😴";
    } else {
      quality = "TOO MUCH";
      color = Colors.orange;
      emoji = "😴";
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4), width: 1),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Sleep Quality", style: AppTheme.labelSmall.copyWith(fontSize: 10)),
                Text(
                  quality,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataConfidenceScore() {
    // Calculate confidence based on how many fields are filled
    int filledFields = 0;
    int totalFields = 6; // energy, stress, social, steps, sleep, location
    
    if (_energyLevel > 0) filledFields++;
    if (_stressLevel > 0) filledFields++;
    if (_socialLevel > 0) filledFields++;
    if (_currentSteps > 0) filledFields++;
    if (_sleepHours > 0) filledFields++;
    if (_cityName.isNotEmpty) filledFields++;
    
    double confidence = filledFields / totalFields;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.15), width: 1),
      ),
      child: Row(
        children: [
          Text("📊", style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Data Quality", style: AppTheme.labelSmall.copyWith(fontSize: 10)),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: confidence,
                          minHeight: 4,
                          backgroundColor: Colors.white.withOpacity(0.1),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            confidence > 0.7 ? AppTheme.neonGreen : AppTheme.neonPurple,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "${(confidence * 100).toInt()}%",
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: confidence > 0.7 ? AppTheme.neonGreen : AppTheme.neonPurple,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLivePredictionPreview() {
    // Analyzer-based prediction with ALL data sources
    String predictedMood = _estimateMoodHeuristic();
    Color moodColor = _getMoodColor(predictedMood);
    
    // Build dynamic sources list based on available data
    final List<String> activeSources = [];
    if (_sleepHours > 0) activeSources.add('Sleep');
    if (_weatherEmoji.isNotEmpty || _backendWeatherSummary != null) activeSources.add('Weather');
    if (_backendMusicMetrics != null) activeSources.add('Music');
    if (_backendCalendarSummary != null && _backendCalendarSummary!.isNotEmpty) activeSources.add('Calendar');
    activeSources.add('Time');
    
    final sourcesText = activeSources.join(' • ');
    
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            moodColor.withOpacity(0.15),
            moodColor.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: moodColor.withOpacity(0.3), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text("LIVE PREDICTION", style: AppTheme.labelSmall.copyWith(fontSize: 10)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: moodColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  "ALGO",
                  style: TextStyle(fontSize: 8, color: moodColor, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.psychology_outlined, color: moodColor, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      predictedMood.toUpperCase(),
                      style: TextStyle(
                        color: moodColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      sourcesText,
                      style: AppTheme.labelSmall.copyWith(fontSize: 9, color: Colors.white54),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _estimateMoodHeuristic() {
    // Use backend MoodDataAnalyzer with ALL available data sources
    try {
      final analyzer = MoodDataAnalyzer();

      // === CALENDAR: Parse backend summary into structured events ===
      final List<Map<String, dynamic>> calendarEvents = [];
      if (_backendCalendarSummary != null && _backendCalendarSummary!.isNotEmpty) {
        // Parse calendar summary (format: "event1, event2, ...")
        final eventLines = _backendCalendarSummary!.split('\n');
        for (final line in eventLines) {
          if (line.trim().isEmpty) continue;
          
          // Create event structure for analyzer
          calendarEvents.add({
            'summary': line.trim().toLowerCase(),
            'start': {
              'date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
            },
          });
        }
        debugPrint("📅 Parsed ${calendarEvents.length} calendar events");
      }

      // === MUSIC: Use backend metrics (from YouTube Music API) ===
      final valence = _backendMusicMetrics?['avg_valence']?.toDouble() ?? 0.5;
      final energy = _backendMusicMetrics?['avg_energy']?.toDouble() ?? 0.5;
      final tempo = _backendMusicMetrics?['avg_tempo']?.toInt() ?? 100;
      final danceability = _backendMusicMetrics?['avg_danceability']?.toDouble() ?? 0.5;
      debugPrint("🎵 Music: valence=$valence, energy=$energy, tempo=$tempo");

      // === WEATHER: Build summary from LOCAL app data (real-time) ===
      String weatherSummary = 'Unknown';
      double? temperature;
      
      if (_weatherEmoji.isNotEmpty || _cityName.isNotEmpty) {
        // Map weather emoji to backend-compatible keywords
        if (_weatherEmoji.contains('☀') || _weatherEmoji.contains('🌞')) {
          weatherSummary = 'Soleil';
        } else if (_weatherEmoji.contains('🌧') || _weatherEmoji.contains('⛈')) {
          weatherSummary = 'Pluie';
        } else if (_weatherEmoji.contains('☁') || _weatherEmoji.contains('🌥')) {
          weatherSummary = 'Nuageux';
        } else if (_weatherEmoji.contains('❄') || _weatherEmoji.contains('🌨')) {
          weatherSummary = 'Neige';
        }
        
        // Add temperature if available
        if (_temperature.isNotEmpty) {
          try {
            temperature = double.parse(_temperature.replaceAll('°C', '').trim());
          } catch (_) {}
        }
        
        debugPrint("🌤️ Weather: $weatherSummary (${_temperature})");
      } else if (_backendWeatherSummary != null) {
        // Fallback to backend data if local not available
        weatherSummary = _backendWeatherSummary!;
      }

      // === TIME: Execution type based on current hour ===
      final now = DateTime.now();
      final hour = now.hour;
      String executionType;
      if (hour < 12) {
        executionType = 'MATIN';
      } else if (hour < 17) {
        executionType = 'APRES-MIDI';
      } else {
        executionType = 'SOIREE';
      }

      // === RUN ANALYZER with ALL data sources ===
      final result = analyzer.analyze(
        calendarEvents: calendarEvents,
        sleepHours: _sleepHours,
        bedtime: '23:00', // Could be enhanced with actual tracking
        wakeTime: '07:00',
        weather: weatherSummary,
        temperature: temperature,
        valence: valence,
        energy: energy,
        tempo: tempo,
        danceability: danceability,
        currentTime: now,
        executionType: executionType,
      );

      debugPrint("🧠 Analyzer result: ${result.topMood} (sleep=${_sleepHours}h, weather=$weatherSummary)");
      return result.topMood;
    } catch (e) {
      debugPrint("⚠️ Analyzer failed: $e");
      // Fallback to simple heuristic
      if (_sleepHours < 6) return "tired";
      if (_energyLevel > 0.7) return "energetic";
      if (_stressLevel > 0.7) return "intense";
      return "chill";
    }
  }

  Color _getMoodColor(String mood) {
    final m = mood.toLowerCase();
    if (m.contains('happy') || m.contains('festif') || m.contains('energetic') || m.contains('pumped')) {
      return AppTheme.neonGreen;
    }
    if (m.contains('sad') || m.contains('mélancolique') || m.contains('melancholy')) {
      return Colors.blueGrey;
    }
    if (m.contains('calm') || m.contains('chill') || m.contains('creative')) {
      return Colors.cyan;
    }
    if (m.contains('intense') || m.contains('agressif') || m.contains('stressed')) {
      return AppTheme.neonPink;
    }
    if (m.contains('hard_work') || m.contains('confident')) {
      return AppTheme.neonPurple;
    }
    if (m.contains('tired')) {
      return Colors.orange;
    }
    return AppTheme.neonPurple;
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
