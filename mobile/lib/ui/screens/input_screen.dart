import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../models/mood_entry.dart';
import '../../services/database_service.dart';
import '../../services/pedometer_service.dart';
import '../../services/youtube_music_service.dart';
import '../../services/ics_service.dart';
import '../../services/youtube_music_cloud_service.dart';
import '../../utils/app_logger.dart';
import '../../services/spotify_enrichment_service.dart';
import '../../services/google_calendar_service.dart';
import '../../services/sleep_tracking_service.dart';
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
  TimeOfDay _sleepDuration =
      const TimeOfDay(hour: 7, minute: 30); // Default 7h 30m
  double _energyLevel = 0.5;
  double _stressLevel = 0.5;
  double _socialLevel = 0.5;
  bool _sleepIsAutoDetected = false;

  bool _isSyncing = false;
  String _temperature = "";
  String _cityName = "Locating..."; // Restore city name
  String _weatherEmoji = "";
  int _currentSteps = 0;
  bool _manualSyncDoneToday = false;

  // Real-time Prediction
  String _predictedMood = "CHILL";
  Timer? _debounceTimer;

  // External Data Status
  bool _isCalendarConnected = false;
  bool _isMusicConnected = false; // Will check checkMusicStatus
  bool _isPedometerActive = false;

  // Cache
  List<Map<String, dynamic>> _todayEvents = [];
  List<Map<String, dynamic>> _recentEnrichedTracks = [];

  // Services
  final _sleepTrackingService = SleepTrackingService();
  final _calendarService = GoogleCalendarService();
  final _musicService = YouTubeMusicService();
  final _spotifyService = SpotifyEnrichmentService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadCachedData(); // Load first!
    _initServices();
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
      final pedometerGranted = await Permission.activityRecognition.isGranted;
      if (mounted) setState(() => _isPedometerActive = pedometerGranted);

      PedometerService.instance.stepStream.listen((steps) {
        if (mounted) setState(() => _currentSteps = steps);
      });

      // 2. Sleep (Only override if not already loaded from cache/sync)
      if (!_manualSyncDoneToday) {
        await _sleepTrackingService.startTracking();
        final autoSleep = await _sleepTrackingService.getActualSleepHours();
        if (autoSleep != null && autoSleep > 0) {
          // Convert double hours to TimeOfDay
          int hours = autoSleep.floor();
          int minutes = ((autoSleep - hours) * 60).round();

          if (mounted) {
            setState(() {
              _sleepDuration = TimeOfDay(hour: hours, minute: minutes);
              _sleepIsAutoDetected = true;
            });
          }
        }
      }

      // 3. Calendar
      try {
        // Try sign in silently first to check connection
        final isSignedIn = await _calendarService.signInSilently();
        if (mounted) setState(() => _isCalendarConnected = isSignedIn);

        // Fetch Google Events
        List<Map<String, dynamic>> googleEvents = [];
        if (isSignedIn) {
          googleEvents = await _calendarService.getTodayEvents();
        }

        // Fetch ICS Events (Always try, doesn't need Google Sign-In)
        final icsEvents = await IcsService().getTodayEvents();

        final allEvents = [...googleEvents, ...icsEvents];
        // Sort by time
        allEvents.sort((a, b) {
          final tA = a['start']['dateTime'] ?? '';
          final tB = b['start']['dateTime'] ?? '';
          return tA.compareTo(tB);
        });

        if (mounted) {
          setState(() {
            _todayEvents = List<Map<String, dynamic>>.from(allEvents);
            // If we have ICS events, we are "Connected" in terms of data availability
            if (icsEvents.isNotEmpty) {
              _isCalendarConnected = true;
            }
          });
        }
      } catch (e) {
        debugPrint("Calendar init error: $e");
      }

      // 4. Music - Listen & Enrich
      _checkMusicConnection();

      // Load Local + Cloud History
      final localTracks = await _musicService.getRecentTracks();
      _processMusicHistory(localTracks);

      // Async fetch cloud history (don't await to block UI)
      YoutubeMusicCloudService().getRecentTracks().then((cloudTracks) {
        if (cloudTracks.isNotEmpty && mounted) {
          _processMusicHistory(cloudTracks);
          // If we got cloud tracks, we are definitely "Connected"
          setState(() => _isMusicConnected = true);
        }
      });

      // Check Permission for Music Listener (Silent check only)
      await _musicService.isNotificationPermissionGranted();
      // Dialog removed per user request ("delete the music sync pop up")
      // User must tap the "MUSIC" chip manually to enable it.

      _musicService.trackStream.listen((track) async {
        if (track != null) {
          // Track is already added to history self by Service
          // We just need to refresh our enriched list
          await _processMusicHistory(_musicService.getRecentTracks());
        }
      });

      // 5. Weather & Location
      _fetchWeatherAndLocation();

      // Initial Prediction
      _recalculatePrediction();
    } catch (e) {
      debugPrint("❌ Service Init Error: $e");
    }
  }

  Future<void> _checkMusicConnection() async {
    try {
      // Check if we can get current track (implies permission/service ready)
      final track = await _musicService.getCurrentTrack();
      if (track != null) {
        if (mounted) setState(() => _isMusicConnected = true);
        return;
      }

      // Fallback to playing check, and also consider if we have any enriched tracks (sticky status)
      final isPlaying = await _musicService.isPlaying();
      if (mounted) {
        setState(() {
          _isMusicConnected = isPlaying || _recentEnrichedTracks.isNotEmpty;
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchWeatherAndLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) setState(() => _cityName = "No GPS");
          return;
        }
      }

      Position pos = await Geolocator.getCurrentPosition(
          timeLimit: const Duration(seconds: 5));

      // Reverse Geocoding for City Name
      try {
        final placemarks =
            await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (placemarks.isNotEmpty) {
          final city = placemarks.first.locality ?? "Unknown";
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('cached_location', city);

          if (mounted) setState(() => _cityName = city);
        }
      } catch (e) {
        debugPrint("Geocoding error: $e");
      }

      final url = Uri.parse(
          "https://api.open-meteo.com/v1/forecast?latitude=${pos.latitude}&longitude=${pos.longitude}&current=temperature_2m,weathercode");
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted) {
          final temp = "${data['current']['temperature_2m']}°C";
          final emoji = _getWeatherEmoji(data['current']['weathercode']);

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('cached_temperature', temp);
          await prefs.setString('cached_weather_emoji', emoji);

          setState(() {
            _temperature = temp;
            _weatherEmoji = emoji;
          });
          _recalculatePrediction();
        }
      }
    } catch (_) {}
  }

  // === MUSIC ENRICHMENT HELPER ===
  Future<void> _processMusicHistory(
      List<Map<String, dynamic>> rawTracks) async {
    if (rawTracks.isEmpty) return;

    List<Map<String, dynamic>> enriched = [];
    for (var track in rawTracks) {
      // Create a copy to modify
      var trackData = Map<String, dynamic>.from(track);

      // Enrich if not already done (assuming service doesn't store enrichment yet,
      // but if we want to be efficient we should probably store it in service too.
      // For now, simple enrichment on read)
      final features = await _spotifyService.getAudioFeatures(
          trackData['title'], trackData['artist']);

      trackData['energy'] = features['energy'];
      trackData['valence'] = features['valence'];
      enriched.add(trackData);
    }

    if (mounted) {
      setState(() {
        _recentEnrichedTracks = enriched;
        _isMusicConnected = true; // Green if we have data!
      });
      _recalculatePrediction();
    }
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

    // 1. Always load independent cache first (Location/Weather don't depend on sync date)
    if (mounted) {
      setState(() {
        _cityName = prefs.getString('cached_location') ?? "Locating...";
        _temperature = prefs.getString('cached_temperature') ?? "";
        _weatherEmoji = prefs.getString('cached_weather_emoji') ?? "";
      });
    }

    // 2. Check if we already synced today for daily metrics
    if (prefs.getString('last_sync_date') == today) {
      double cachedSleep = prefs.getDouble('cached_sleep') ?? 7.5;
      int hours = cachedSleep.floor();
      int minutes = ((cachedSleep - hours) * 60).round();

      if (mounted) {
        setState(() {
          _sleepDuration = TimeOfDay(hour: hours, minute: minutes);
          _energyLevel = prefs.getDouble('cached_energy') ?? 0.5;
          _stressLevel = prefs.getDouble('cached_stress') ?? 0.5;
          _socialLevel = prefs.getDouble('cached_social') ?? 0.5;
          _manualSyncDoneToday = true; // Use this to lock init
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
    double sleepHours = _sleepDuration.hour + (_sleepDuration.minute / 60.0);
    final mood = MoodLogic.analyze(
      calendarEvents: _todayEvents,
      sleepHours: sleepHours,
      weather: _weatherEmoji,
      energyLevel: _energyLevel,
      stressLevel: _stressLevel,
      socialLevel: _socialLevel,
      recentTracks: _recentEnrichedTracks,
    );
    if (mounted && mood != _predictedMood) {
      setState(() => _predictedMood = mood.toUpperCase());
    }
  }

  Future<void> _sync() async {
    setState(() => _isSyncing = true);
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      double sleepHours = _sleepDuration.hour + (_sleepDuration.minute / 60.0);

      final entry = MoodEntry(
        date: today,
        sleepHours: sleepHours,
        energy: _energyLevel,
        stress: _stressLevel,
        social: _socialLevel,
        steps: _currentSteps,
        lastUpdated: DateTime.now(),
        device: "android_app_v2",
        location: _cityName, // Add Location
        // Additional fields...
      );

      final collection = await DatabaseService.instance.overrides;
      await collection.replaceOne(mongo.where.eq('date', today), entry.toJson(),
          upsert: true);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_sync_date', today); // Correct Key
      await prefs.setDouble('cached_sleep', sleepHours);
      await prefs.setDouble('cached_energy', _energyLevel);
      await prefs.setDouble('cached_stress', _stressLevel);
      await prefs.setDouble('cached_social', _socialLevel);
      await prefs.setString('cached_location', _cityName); // Cache Location
      await prefs.setString('cached_temperature', _temperature);
      await prefs.setString('cached_weather_emoji', _weatherEmoji);

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

  void _showStepsDialog() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Steps",
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, anim1, anim2) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              margin: const EdgeInsets.all(32),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E).withOpacity(0.95),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                    color: AppTheme.neonGreen.withOpacity(0.3), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.neonGreen.withOpacity(0.1),
                    blurRadius: 20,
                    spreadRadius: 5,
                  )
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.neonGreen.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.directions_walk,
                        color: AppTheme.neonGreen, size: 32),
                  ),
                  const SizedBox(height: 20),
                  Text("ACTIVITY LEVEL",
                      style: AppTheme.headerLarge
                          .copyWith(fontSize: 18, letterSpacing: 1.2)),
                  const SizedBox(height: 8),
                  Text("Total steps today",
                      style: AppTheme.subText.copyWith(color: Colors.white54)),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        _currentSteps.toString(),
                        style: GoogleFonts.spaceMono(
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "${(_currentSteps / 1000).toStringAsFixed(1)} km est.",
                    style: AppTheme.subText
                        .copyWith(fontSize: 12, color: AppTheme.neonCyan),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.neonGreen.withOpacity(0.2),
                        foregroundColor: AppTheme.neonGreen,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                        side: BorderSide(
                            color: AppTheme.neonGreen.withOpacity(0.5)),
                      ),
                      child: const Text("KEEP MOVING",
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        return Transform.scale(
          scale: Curves.easeOutBack.transform(anim1.value),
          child: FadeTransition(opacity: anim1, child: child),
        );
      },
    );
  }

  void _showMusicPermissionDialog() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Music Permission",
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, anim1, anim2) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              margin: const EdgeInsets.all(32),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E).withOpacity(0.95),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                    color: AppTheme.neonPurple.withOpacity(0.3), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.neonPurple.withOpacity(0.1),
                    blurRadius: 20,
                    spreadRadius: 5,
                  )
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.neonPurple.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.music_note,
                        color: AppTheme.neonPurple, size: 32),
                  ),
                  const SizedBox(height: 20),
                  Text("MUSIC SYNC",
                      style: AppTheme.headerLarge
                          .copyWith(fontSize: 18, letterSpacing: 1.2)),
                  const SizedBox(height: 12),
                  const Text(
                    "To detect what you're listening to and analyze your mood, we need 'Notification Access'.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, height: 1.5),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _musicService.requestNotificationPermission();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.neonBlue.withOpacity(0.2),
                        foregroundColor: AppTheme.neonBlue,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text("ENABLE ACCESS",
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('music_permission_suppressed', true);
                    },
                    child: Text("Don't ask again",
                        style: TextStyle(color: Colors.white.withOpacity(0.5))),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text("Maybe Later",
                        style: TextStyle(color: Colors.white38)),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        return Transform.scale(
          scale: Curves.easeOutBack.transform(anim1.value),
          child: FadeTransition(opacity: anim1, child: child),
        );
      },
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
        GestureDetector(
          onLongPress: _showDebugLogs, // Secret Debug Menu
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("DAILY DATA",
                  style: AppTheme.headerLarge.copyWith(fontSize: 28)),
              Row(
                children: [
                  Icon(Icons.location_on, size: 14, color: Colors.white54),
                  const SizedBox(width: 4),
                  Text(_cityName.toUpperCase(), // Display City
                      style:
                          AppTheme.subText.copyWith(color: AppTheme.neonCyan)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                  DateFormat('EEEE, d MMM')
                      .format(DateTime.now())
                      .toUpperCase(),
                  style: AppTheme.subText),
            ],
          ),
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

  void _showDebugLogs() {
    final logs = AppLogger().logs;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black.withOpacity(0.9),
        title: Text("Debug Logs", style: TextStyle(color: AppTheme.neonGreen)),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: ListView.builder(
            itemCount: logs.length,
            itemBuilder: (context, index) {
              final log = logs[index];
              final isError = log.contains("ERROR") || log.contains("🔴");
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2.0),
                child: Text(log,
                    style: TextStyle(
                        color: isError ? Colors.redAccent : Colors.white70,
                        fontSize: 10,
                        fontFamily: 'monospace')),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              AppLogger().clear();
              Navigator.pop(context);
              _showDebugLogs();
            }, // Clear and reopen to refresh? Or just clear.
            child: Text("Clear", style: TextStyle(color: Colors.orange)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Close", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectivityRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildStatusChip(
          Icons.calendar_today,
          "Events",
          _isCalendarConnected,
          onTap: () async {
            if (!_isCalendarConnected) {
              final success = await _calendarService.signIn();
              if (mounted) setState(() => _isCalendarConnected = success);
            }
          },
        ),
        _buildStatusChip(
          Icons.music_note,
          "Music",
          _isMusicConnected,
          onTap: () {
            if (!_isMusicConnected) {
              _musicService.requestNotificationPermission();
              // Clear suppression to allow re-asking
              SharedPreferences.getInstance().then((prefs) {
                prefs.remove('music_permission_suppressed');
                _checkMusicConnection();
              });
            }
          },
        ),
        _buildStatusChip(
          Icons.directions_walk,
          "Steps",
          _isPedometerActive,
          onTap: _showStepsDialog,
        ),
      ],
    );
  }

  Widget _buildStatusChip(IconData icon, String label, bool isActive,
      {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
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
        const SizedBox(height: 16),
        Center(
          child: GestureDetector(
            onTap: _pickSleepTime, // Use Time Picker
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                  border:
                      Border.all(color: AppTheme.neonPurple.withOpacity(0.5)),
                  color: AppTheme.neonPurple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                      "${_sleepDuration.hour}h ${_sleepDuration.minute.toString().padLeft(2, '0')}m",
                      style: GoogleFonts.spaceMono(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                  const SizedBox(width: 8),
                  Icon(Icons.edit, size: 16, color: Colors.white54)
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickSleepTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _sleepDuration,
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.neonPurple,
              onPrimary: Colors.white,
              surface: Color(0xFF1E1E1E),
              onSurface: Colors.white,
            ),
            dialogBackgroundColor: Colors.black,
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != _sleepDuration) {
      setState(() {
        _sleepDuration = picked;
        _sleepIsAutoDetected = false;
      });
      _onInputChanged();
    }
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
