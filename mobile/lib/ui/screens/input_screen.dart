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
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/mood_entry.dart';
import '../../services/database_service.dart';
import '../../services/pedometer_service.dart';
import '../../services/cache_service.dart';
import '../../services/youtube_music_service.dart';
import '../../services/spotify_enrichment_service.dart';
import '../../services/google_calendar_service_simple.dart';
import '../../services/sleep_tracking_service.dart';
import '../../services/adaptive_weights_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/mood_analyzer.dart';

class InputScreen extends StatefulWidget {
  const InputScreen({super.key});

  @override
  State<InputScreen> createState() => _InputScreenState();
}

class _InputScreenState extends State<InputScreen> with WidgetsBindingObserver {
  // Core State
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

  // Sleep Cache
  String _bedTime = "00:00";
  String _wakeTime = "08:00";

  // Backend Data Cache
  String? _backendAlgoPrediction;
  Map<String, dynamic>? _backendMusicMetrics;
  String? _backendCalendarSummary;
  String? _backendWeatherSummary;
  String? _lastLoadedDate;

  // New Services
  final _youtubeMusicService = YouTubeMusicService();
  final _spotifyEnrichmentService = SpotifyEnrichmentService();
  final _googleCalendarService = GoogleCalendarService();
  final _sleepTrackingService = SleepTrackingService();
  final _adaptiveWeightsService = AdaptiveWeightsService();

  // Real-time data
  Map<String, dynamic>? _currentTrack;
  Map<String, dynamic>? _musicFeatures;
  List<Map<String, dynamic>>? _todayEvents;
  Map<String, double>? _adaptiveWeights;

  // Stream
  StreamSubscription<int>? _stepSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initServices();
    _loadCachedData();
    _fetchWeather();
    _checkManualSyncStatus();
    _loadBackendPrediction();
  }

  Future<void> _initServices() async {
    // Initialize pedometer
    await PedometerService.instance.init();
    _stepSubscription = PedometerService.instance.stepStream.listen((steps) {
      if (mounted) setState(() => _currentSteps = steps);
      SharedPreferences.getInstance()
          .then((prefs) => prefs.setInt('last_known_steps', steps));
    });
    setState(() => _currentSteps = PedometerService.instance.currentSteps);

    // Initialize sleep tracking
    await _sleepTrackingService.startTracking();

    // Load auto-detected sleep hours (default value)
    // Load auto-detected sleep hours (default value)
    final autoSleepHours = await _sleepTrackingService.getActualSleepHours();
    if (autoSleepHours != null && autoSleepHours > 0 && autoSleepHours <= 12) {
      setState(() {
        _sleepHours = autoSleepHours;
        _sleepIsAutoDetected = true;
      });

      final bed = await _sleepTrackingService.getBedtimeString();
      final wake = await _sleepTrackingService.getWakeTimeString();
      if (mounted)
        setState(() {
          _bedTime = bed;
          _wakeTime = wake;
        });

      debugPrint(
          '😴 Auto-detected sleep: ${autoSleepHours}h (${bed} → ${wake})');
    }

    // Load adaptive weights
    _adaptiveWeights = await _adaptiveWeightsService.getWeights();

    // Start listening to music changes
    _youtubeMusicService.trackStream.listen((track) {
      if (mounted && track != null) {
        setState(() => _currentTrack = track);
        _enrichCurrentTrack();
      }
    });

    // Fetch Google Calendar events
    try {
      _todayEvents = await _googleCalendarService.getTodayEvents();
    } catch (e) {
      print('Calendar not available: $e');
    }
  }

  Future<void> _loadCachedData() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedDate = prefs.getString('cached_date');
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    if (cachedDate == today) {
      setState(() {
        _sleepHours = prefs.getDouble('cached_sleep') ?? 7.5;
        _energyLevel = prefs.getDouble('cached_energy') ?? 0.5;
        _stressLevel = prefs.getDouble('cached_stress') ?? 0.5;
        _socialLevel = prefs.getDouble('cached_social') ?? 0.5;
      });
    }

    setState(() {
      _cityName = prefs.getString('cached_city') ?? "";
      _temperature = prefs.getString('cached_temp') ?? "";
      _weatherEmoji = prefs.getString('cached_weather_emoji') ?? "";
    });
  }

  Future<void> _checkManualSyncStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSyncStr = prefs.getString('last_manual_sync');
    if (lastSyncStr != null) {
      final lastSync = DateTime.parse(lastSyncStr);
      final today = DateTime.now();
      if (lastSync.year == today.year &&
          lastSync.month == today.month &&
          lastSync.day == today.day) {
        if (mounted) setState(() => _manualSyncDoneToday = true);
      }
    }
  }

  Future<void> _enrichCurrentTrack() async {
    if (_currentTrack == null) return;

    try {
      final features = await _spotifyEnrichmentService.enrichTrack(
        _currentTrack!['title'] ?? '',
        _currentTrack!['artist'] ?? '',
      );

      if (mounted && features != null) {
        setState(() => _musicFeatures = features);
        debugPrint(
            '🎵 Enriched track: ${_currentTrack!['title']} - Valence: ${features['valence']}, Energy: ${features['energy']}');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to enrich track: $e');
    }
  }

  Future<void> _loadBackendPrediction() async {
    // Try cache first
    final cachedData = await CacheService.getCachedBackendPrediction();
    if (cachedData != null && mounted) {
      setState(() {
        _backendAlgoPrediction = cachedData['mood_selected'] as String?;
        _backendMusicMetrics =
            cachedData['music_metrics'] as Map<String, dynamic>?;
        _backendCalendarSummary = cachedData['calendar_summary'] as String?;
        _backendWeatherSummary = cachedData['weather_summary'] as String?;
        _lastLoadedDate = cachedData['date'] as String?;
      });
      debugPrint("✅ Loaded backend data from cache");
      return;
    }

    // Fetch from database if cache miss
    try {
      final collection = await DatabaseService.instance.dailyLogs;
      final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final doc = await collection.findOne(mongo.where.eq('date', dateStr));

      if (doc != null && mounted) {
        // Cache the result
        await CacheService.cacheBackendPrediction(doc);

        setState(() {
          _backendAlgoPrediction = doc['mood_selected'] as String?;
          _backendMusicMetrics = doc['music_metrics'] as Map<String, dynamic>?;
          _backendCalendarSummary = doc['calendar_summary'] as String?;
          _backendWeatherSummary = doc['weather_summary'] as String?;
          _lastLoadedDate = dateStr;
        });
        debugPrint("✅ Backend data loaded and cached for $dateStr");
      }
    } catch (e) {
      debugPrint("⚠️ Backend load error: $e");
    }
  }

  Future<void> _fetchWeather() async {
    // Try cache first
    final cachedWeather = await CacheService.getCachedWeather();
    if (cachedWeather != null && mounted) {
      setState(() {
        _temperature = cachedWeather['temperature']!;
        _weatherEmoji = cachedWeather['emoji']!;
        _cityName = cachedWeather['city']!;
      });
      debugPrint("✅ Loaded weather from cache");
      return;
    }

    // Fetch fresh data if cache miss
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }

      // Try cached location first
      Position position;
      final cachedLoc = await CacheService.getCachedLocation();
      if (cachedLoc != null) {
        position = Position(
          latitude: cachedLoc['latitude']!,
          longitude: cachedLoc['longitude']!,
          timestamp: DateTime.now(),
          accuracy: 0,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0,
        );
        debugPrint("✅ Using cached location");
      } else {
        position = await Geolocator.getCurrentPosition(
                desiredAccuracy: LocationAccuracy.medium,
                timeLimit: const Duration(seconds: 10))
            .timeout(const Duration(seconds: 12));

        // Cache location
        await CacheService.cacheLocation(
          latitude: position.latitude,
          longitude: position.longitude,
        );
      }

      List<Placemark> placemarks =
          await placemarkFromCoordinates(position.latitude, position.longitude);
      String cityName = "Unknown";
      if (placemarks.isNotEmpty) {
        cityName = placemarks.first.locality ?? "Unknown";
      }

      final url = Uri.parse(
          "https://api.open-meteo.com/v1/forecast?latitude=${position.latitude}&longitude=${position.longitude}&current=temperature_2m,weathercode");

      final response = await http.get(url).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final temp = data['current']['temperature_2m'];
        final weatherCode = data['current']['weathercode'] ?? 0;
        final unit = data['current_units']['temperature_2m'] ?? "°C";

        final tempStr = "${temp.round()}$unit";
        final emoji = _getWeatherEmoji(weatherCode);

        // Cache the fresh data
        await CacheService.cacheWeather(
          temperature: tempStr,
          emoji: emoji,
          city: cityName,
        );

        if (mounted) {
          setState(() {
            _temperature = tempStr;
            _weatherEmoji = emoji;
            _cityName = cityName;
          });
        }
        debugPrint("✅ Weather fetched and cached");
      }
    } catch (e) {
      debugPrint("⚠️ Weather Error: $e");
    }
  }

  String _getWeatherEmoji(int code) {
    if (code == 0) return "☀️";
    if (code <= 3) return "⛅";
    if (code <= 48) return "☁️";
    if (code <= 67) return "🌧️";
    if (code <= 77) return "❄️";
    if (code <= 82) return "🌧️";
    if (code <= 99) return "⛈️";
    return "🌤️";
  }

  Future<void> _syncToBrain() async {
    setState(() => _isSyncing = true);

    final uri = dotenv.env['MONGODB_URI'] ?? dotenv.env['MONGO_URI'];
    if (uri == null || uri.isEmpty) {
      _showError("Config Error: Missing Database URI");
      setState(() => _isSyncing = false);
      return;
    }

    try {
      final collection = await DatabaseService.instance.overrides
          .timeout(const Duration(seconds: 20));

      final prefs = await SharedPreferences.getInstance();
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final cachedCity = prefs.getString('cached_city');
      String? locationToUse = _cityName.isNotEmpty ? _cityName : cachedCity;

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

      // Calculate predicted mood before saving
      final predictedMood = _estimateMoodHeuristic();

      // Record prediction for adaptive learning (actual mood will be determined by backend)
      await _adaptiveWeightsService.recordPrediction(
        predictedMood: predictedMood,
        actualMood: "", // Will be updated later when backend processes
        energyLevel: _energyLevel,
        stressLevel: _stressLevel,
        socialLevel: _socialLevel,
        steps: _currentSteps,
      );

      await collection
          .replaceOne(
            mongo.where.eq('date', entry.date),
            entry.toJson(),
            upsert: true,
          )
          .timeout(const Duration(seconds: 25));

      await Future.wait([
        prefs.setString('cached_date', today),
        prefs.setDouble('cached_sleep', _sleepHours),
        prefs.setDouble('cached_energy', _energyLevel),
        prefs.setDouble('cached_stress', _stressLevel),
        prefs.setDouble('cached_social', _socialLevel),
        prefs.setString('last_manual_sync', DateTime.now().toIso8601String()),
      ]);

      await HapticFeedback.heavyImpact();
      if (mounted) {
        setState(() {
          _manualSyncDoneToday = true;
          _isSyncing = false;
        });
        _showSuccessDialog();
      }
    } catch (e) {
      _showError("Sync Failed: Check Internet");
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(30),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.neonGreen.withOpacity(0.2),
                AppTheme.neonGreen.withOpacity(0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
                color: AppTheme.neonGreen.withOpacity(0.4), width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_rounded,
                  color: AppTheme.neonGreen, size: 60),
              const SizedBox(height: 16),
              Text("SYNCED!",
                  style:
                      AppTheme.headerLarge.copyWith(color: AppTheme.neonGreen)),
              const SizedBox(height: 8),
              Text("Your mood data has been saved.", style: AppTheme.subText),
            ],
          ),
        ),
      ),
    );
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppTheme.neonPink),
    );
  }

  String _estimateMoodHeuristic() {
    try {
      final analyzer = MoodDataAnalyzer();

      // === CALENDAR EVENTS (Real-time from Google Calendar if available) ===
      final List<Map<String, dynamic>> calendarEvents = [];

      if (_todayEvents != null && _todayEvents!.isNotEmpty) {
        // Use real-time Google Calendar data
        calendarEvents.addAll(_todayEvents!);
        debugPrint(
            "📅 Using ${_todayEvents!.length} real-time calendar events");
      } else if (_backendCalendarSummary != null &&
          _backendCalendarSummary!.isNotEmpty) {
        // Fallback to backend cached data
        final eventLines = _backendCalendarSummary!.split('\n');
        for (final line in eventLines) {
          if (line.trim().isEmpty) continue;
          calendarEvents.add({
            'summary': line.trim(),
            'start': {
              'dateTime': DateTime.now().toIso8601String(),
            }
          });
        }
        debugPrint(
            "📅 Using ${calendarEvents.length} backend calendar events (fallback)");
      }

      // === SLEEP DATA ===
      double sleepHours = _sleepHours;
      String bedtime = _bedTime;
      String wakeTime = _wakeTime;

      debugPrint(
          "😴 Using sleep: ${sleepHours}h (Bedtime: $bedtime, Wake: $wakeTime)");

      // === WEATHER CONDITION ===
      String weatherKeyword = "Inconnu";
      if (_weatherEmoji == "☀️") {
        weatherKeyword = "Soleil";
      } else if (_weatherEmoji == "🌧️" || _weatherEmoji == "⛈️") {
        weatherKeyword = "Pluie";
      } else if (_weatherEmoji == "☁️") {
        weatherKeyword = "Nuageux";
      } else if (_weatherEmoji == "❄️") {
        weatherKeyword = "Neige";
      }

      // === MUSIC DATA (Real-time YouTube Music + Spotify enrichment) ===
      double valence = 0.5;
      double energy = 0.5;
      int tempo = 120;
      double danceability = 0.5;

      if (_musicFeatures != null) {
        // Use real-time enriched music data
        valence = (_musicFeatures!['valence'] ?? 0.5).toDouble();
        energy = (_musicFeatures!['energy'] ?? 0.5).toDouble();
        tempo = (_musicFeatures!['tempo'] ?? 120).toInt();
        danceability = (_musicFeatures!['danceability'] ?? 0.5).toDouble();
        debugPrint(
            "🎵 Using real-time music: ${_currentTrack!['title']} - Valence: $valence, Energy: $energy");
      } else if (_backendMusicMetrics != null) {
        // Fallback to backend data
        valence = (_backendMusicMetrics!['valence'] ?? 0.5).toDouble();
        energy = (_backendMusicMetrics!['energy'] ?? 0.5).toDouble();
        tempo = (_backendMusicMetrics!['tempo'] ?? 120).toInt();
        danceability =
            (_backendMusicMetrics!['danceability'] ?? 0.5).toDouble();
        debugPrint("🎵 Using backend music data (fallback)");
      }

      // === TIME CONTEXT ===
      final now = DateTime.now();
      final timeOfDay =
          now.hour < 12 ? 'MATIN' : (now.hour < 18 ? 'APRES_MIDI' : 'SOIR');

      // === CALL ANALYZER ===
      final result = analyzer.analyze(
        calendarEvents: calendarEvents,
        sleepHours: sleepHours,
        bedtime: bedtime,
        wakeTime: wakeTime,
        weather: weatherKeyword,
        temperature: null,
        valence: valence,
        energy: energy,
        tempo: tempo,
        danceability: danceability,
        currentTime: now,
        executionType: timeOfDay,
      );

      // === APPLY ADAPTIVE WEIGHTS ===
      final moodScores = Map<String, double>.from(result.moodScores);
      final adaptiveWeights = _adaptiveWeights ??
          {
            'energy': 0.15,
            'stress': 0.15,
            'social': 0.10,
            'steps': 0.10,
          };

      // === APPLY LOCAL METRICS ADJUSTMENTS (with adaptive weights) ===
      // Energy Level: High energy boosts energetic/pumped/confident
      final energyWeight =
          adaptiveWeights['energy']! * 100; // Scale to 0-15 range
      if (_energyLevel > 0.7) {
        moodScores['energetic'] = (moodScores['energetic'] ?? 0) + energyWeight;
        moodScores['pumped'] =
            (moodScores['pumped'] ?? 0) + energyWeight * 0.66;
        moodScores['confident'] =
            (moodScores['confident'] ?? 0) + energyWeight * 0.66;
      } else if (_energyLevel < 0.3) {
        moodScores['tired'] = (moodScores['tired'] ?? 0) + energyWeight;
        moodScores['chill'] = (moodScores['chill'] ?? 0) + energyWeight * 0.66;
      }

      // Stress Level: High stress boosts intense/hardWork
      final stressWeight = adaptiveWeights['stress']! * 100;
      if (_stressLevel > 0.7) {
        moodScores['intense'] = (moodScores['intense'] ?? 0) + stressWeight;
        moodScores['hardWork'] =
            (moodScores['hardWork'] ?? 0) + stressWeight * 0.66;
      } else if (_stressLevel < 0.3) {
        moodScores['chill'] = (moodScores['chill'] ?? 0) + stressWeight * 0.66;
        moodScores['confident'] =
            (moodScores['confident'] ?? 0) + stressWeight * 0.33;
      }

      // Social Level: High social boosts confident/pumped
      final socialWeight = adaptiveWeights['social']! * 100;
      if (_socialLevel > 0.7) {
        moodScores['confident'] = (moodScores['confident'] ?? 0) + socialWeight;
        moodScores['pumped'] = (moodScores['pumped'] ?? 0) + socialWeight;
      } else if (_socialLevel < 0.3) {
        moodScores['melancholy'] =
            (moodScores['melancholy'] ?? 0) + socialWeight * 0.5;
        moodScores['chill'] = (moodScores['chill'] ?? 0) + socialWeight * 0.5;
      }

      // Steps: Goal achievement boosts energetic/pumped
      final stepsWeight = adaptiveWeights['steps']! * 100;
      if (_currentSteps >= 10000) {
        moodScores['energetic'] = (moodScores['energetic'] ?? 0) + stepsWeight;
        moodScores['pumped'] = (moodScores['pumped'] ?? 0) + stepsWeight * 0.5;
      } else if (_currentSteps < 3000) {
        moodScores['tired'] = (moodScores['tired'] ?? 0) + stepsWeight * 0.5;
      }

      // === VETO CHECK: Sleep < 6h should ALWAYS trigger tired ===
      // This is critical - backend has same logic
      if (result.sections['sleep']?.veto == true || sleepHours < 6.0) {
        final maxScore = moodScores.values.isNotEmpty
            ? moodScores.values.reduce((a, b) => a > b ? a : b)
            : 100.0;
        moodScores['tired'] = maxScore * 1.5;
        debugPrint(
            "⚠️ VETO TRIGGERED: Sleep ${sleepHours}h < 6h → Forced TIRED");
      }

      // Find top mood
      final sortedEntries = moodScores.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      final predictedMood =
          sortedEntries.isNotEmpty ? sortedEntries.first.key : 'chill';

      debugPrint(
          "🧠 Mood Prediction: $predictedMood (Sleep: ${sleepHours}h, Energy: ${(_energyLevel * 100).toInt()}%, Stress: ${(_stressLevel * 100).toInt()}%, Social: ${(_socialLevel * 100).toInt()}%, Steps: $_currentSteps)");
      debugPrint(
          "⚖️ Adaptive Weights: Energy=${energyWeight.toStringAsFixed(1)}, Stress=${stressWeight.toStringAsFixed(1)}, Social=${socialWeight.toStringAsFixed(1)}, Steps=${stepsWeight.toStringAsFixed(1)}");

      return predictedMood;
    } catch (e) {
      debugPrint("⚠️ Prediction error: $e");
      return 'chill';
    }
  }

  Color _getMoodColor(String mood) {
    switch (mood.toLowerCase()) {
      case 'creative':
        return AppTheme.neonPurple;
      case 'hardwork':
        return AppTheme.neonPink;
      case 'confident':
        return AppTheme.neonGreen;
      case 'chill':
        return AppTheme.neonBlue;
      case 'energetic':
        return Colors.orange;
      case 'melancholy':
        return Colors.indigo;
      case 'intense':
        return Colors.red;
      case 'pumped':
        return Colors.amber;
      case 'tired':
        return Colors.grey;
      default:
        return AppTheme.neonBlue;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stepSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 50, 20, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            const SizedBox(height: 20),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  children: [
                    _buildSleepCard(),
                    const SizedBox(height: 16),
                    _buildMetricsGrid(),
                    const SizedBox(height: 16),
                    _buildPredictionCard(),
                    const SizedBox(height: 16),
                    _buildSyncButton(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("TODAY", style: AppTheme.headerLarge)
                    .animate()
                    .fadeIn()
                    .slideX(),
                if (_cityName.isNotEmpty)
                  Text(_cityName.toUpperCase(),
                          style: AppTheme.subText.copyWith(fontSize: 12))
                      .animate()
                      .fadeIn(delay: 100.ms),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withOpacity(0.1),
                    Colors.white.withOpacity(0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                border:
                    Border.all(color: Colors.white.withOpacity(0.2), width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_weatherEmoji.isNotEmpty) ...[
                    Text(_weatherEmoji, style: const TextStyle(fontSize: 24)),
                    const SizedBox(width: 8),
                  ],
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (_temperature.isNotEmpty)
                        Text(_temperature,
                            style: GoogleFonts.spaceMono(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                      Text(
                          DateFormat('EEE, dd MMM')
                              .format(DateTime.now())
                              .toUpperCase(),
                          style: AppTheme.subText.copyWith(fontSize: 9)),
                    ],
                  ),
                ],
              ),
            ).animate().fadeIn().scale(),
          ],
        ),
        if (_manualSyncDoneToday)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.neonGreen.withOpacity(0.2),
                    AppTheme.neonGreen.withOpacity(0.1),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: AppTheme.neonGreen.withOpacity(0.5), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.neonGreen.withOpacity(0.3),
                    blurRadius: 12,
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_done_rounded,
                      color: AppTheme.neonGreen, size: 18),
                  const SizedBox(width: 8),
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
            )
                .animate()
                .fadeIn(duration: 400.ms)
                .scale(begin: const Offset(0.9, 0.9)),
          ),
      ],
    );
  }

  Widget _buildSleepCard() {
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
      emoji = "😊";
    } else {
      quality = "TOO MUCH";
      color = Colors.orange;
      emoji = "😪";
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.neonPurple.withOpacity(0.15),
            AppTheme.neonPurple.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border:
            Border.all(color: AppTheme.neonPurple.withOpacity(0.3), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text("SLEEP",
                      style: AppTheme.labelSmall.copyWith(fontSize: 11)),
                  if (_sleepIsAutoDetected) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.neonCyan.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: AppTheme.neonCyan.withOpacity(0.5),
                            width: 1),
                      ),
                      child: Text(
                        "AUTO",
                        style: TextStyle(
                          color: AppTheme.neonCyan,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withOpacity(0.5), width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(emoji, style: const TextStyle(fontSize: 14)),
                    const SizedBox(width: 6),
                    Text(quality,
                        style: TextStyle(
                            color: color,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              "${_sleepHours.toStringAsFixed(1)}h",
              style: GoogleFonts.spaceMono(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: AppTheme.neonPurple,
              ),
            ),
          ),
          const SizedBox(height: 16),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 10,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
              activeTrackColor: AppTheme.neonPurple,
              inactiveTrackColor: Colors.white10,
              thumbColor: Colors.white,
              overlayColor: AppTheme.neonPurple.withOpacity(0.3),
            ),
            child: Slider(
              value: _sleepHours,
              min: 0,
              max: 12,
              divisions: 48,
              onChanged: (value) {
                HapticFeedback.selectionClick();
                setState(() {
                  _sleepHours = value;
                  _sleepIsAutoDetected = false; // User manually edited
                });
              },
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("0h", style: AppTheme.labelSmall.copyWith(fontSize: 10)),
              Text("6h", style: AppTheme.labelSmall.copyWith(fontSize: 10)),
              Text("12h", style: AppTheme.labelSmall.copyWith(fontSize: 10)),
            ],
          ),
        ],
      ),
    ).animate().fadeIn().slideY();
  }

  Widget _buildMetricsGrid() {
    return Column(
      children: [
        _buildMetricBar("ENERGY", "⚡", _energyLevel, AppTheme.neonGreen,
            (v) => setState(() => _energyLevel = v)),
        const SizedBox(height: 12),
        _buildMetricBar("STRESS", "🧠", _stressLevel, AppTheme.neonPink,
            (v) => setState(() => _stressLevel = v)),
        const SizedBox(height: 12),
        _buildMetricBar("SOCIAL", "💬", _socialLevel, AppTheme.neonBlue,
            (v) => setState(() => _socialLevel = v)),
        const SizedBox(height: 12),
        _buildStepsCard(),
      ],
    );
  }

  Widget _buildMetricBar(String label, String emoji, double val, Color color,
      Function(double) change) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withOpacity(0.08),
            Colors.white.withOpacity(0.03),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.15), width: 1),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  Text(label,
                      style: AppTheme.labelSmall.copyWith(fontSize: 12)),
                ],
              ),
              Text("${(val * 100).toInt()}%",
                  style: TextStyle(
                      color: color, fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 12,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
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
      ),
    ).animate().fadeIn().slideX();
  }

  Widget _buildStepsCard() {
    bool goalMet = _currentSteps >= 10000;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withOpacity(0.08),
            Colors.white.withOpacity(0.03),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: goalMet
              ? AppTheme.neonGreen.withOpacity(0.4)
              : Colors.white.withOpacity(0.15),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.directions_walk,
            color: goalMet ? AppTheme.neonGreen : Colors.orange,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("STEPS",
                    style: AppTheme.labelSmall.copyWith(fontSize: 12)),
                Text(
                  "${_currentSteps.toStringAsFixed(0)} / 10,000",
                  style: GoogleFonts.spaceMono(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: goalMet ? AppTheme.neonGreen : Colors.white,
                  ),
                ),
              ],
            ),
          ),
          if (goalMet)
            Icon(Icons.check_circle, color: AppTheme.neonGreen, size: 24)
                .animate()
                .scale(duration: 400.ms),
        ],
      ),
    ).animate().fadeIn().slideX();
  }

  Widget _buildPredictionCard() {
    String predictedMood = _estimateMoodHeuristic();
    Color moodColor = _getMoodColor(predictedMood);

    final List<String> activeSources = [];
    if (_sleepHours > 0) activeSources.add('Sleep');
    if (_weatherEmoji.isNotEmpty || _backendWeatherSummary != null)
      activeSources.add('Weather');
    if (_backendMusicMetrics != null) activeSources.add('Music');
    if (_backendCalendarSummary != null && _backendCalendarSummary!.isNotEmpty)
      activeSources.add('Calendar');
    activeSources.add('Time');

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            moodColor.withOpacity(0.2),
            moodColor.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: moodColor.withOpacity(0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: moodColor.withOpacity(0.3),
            blurRadius: 20,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("LIVE PREDICTION",
                  style: AppTheme.labelSmall.copyWith(fontSize: 11)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: moodColor.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  "AI ALGO",
                  style: TextStyle(
                      fontSize: 9,
                      color: moodColor,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.psychology_rounded, color: moodColor, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      predictedMood.toUpperCase(),
                      style: GoogleFonts.spaceMono(
                        color: moodColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      activeSources.join(' • '),
                      style: AppTheme.labelSmall
                          .copyWith(fontSize: 9, color: Colors.white54),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn().scale();
  }

  Widget _buildSyncButton() {
    return GestureDetector(
      onTap: _isSyncing ? null : _syncToBrain,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _manualSyncDoneToday
                ? [AppTheme.neonGreen, AppTheme.neonGreen.withOpacity(0.8)]
                : [AppTheme.neonPurple, AppTheme.neonPurple.withOpacity(0.8)],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: (_manualSyncDoneToday
                      ? AppTheme.neonGreen
                      : AppTheme.neonPurple)
                  .withOpacity(0.5),
              blurRadius: 20,
              spreadRadius: 0,
            ),
          ],
        ),
        child: Center(
          child: _isSyncing
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 3,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _manualSyncDoneToday
                          ? Icons.check_circle_rounded
                          : Icons.cloud_upload_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _manualSyncDoneToday ? "SYNCED" : "UPDATE MOOD",
                      style: GoogleFonts.spaceMono(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    ).animate().fadeIn().slideY(begin: 0.3);
  }
}
