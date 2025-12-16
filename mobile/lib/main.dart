import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mongo_dart/mongo_dart.dart' as mongo;
import 'package:intl/intl.dart';
import 'package:sleek_circular_slider/sleek_circular_slider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

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
      title: 'Brain Sync',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(context),
      home: const HomeScreen(),
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
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // State
  double _sleepHours = 7.0;
  String? _selectedMood;
  bool _isSyncing = false;
  bool _syncSuccess = false;

  // Constants
  static const List<Map<String, String>> _moods = [
    {'id': 'tired', 'emoji': '🧟', 'label': 'Dead'},
    {'id': 'chill', 'emoji': '🧘', 'label': 'Chill'},
    {'id': 'creative', 'emoji': '🎨', 'label': 'Flow'},
    {'id': 'pumped', 'emoji': '🔥', 'label': 'Pumped'},
    {'id': 'confident', 'emoji': '🚀', 'label': 'God Mode'},
  ];

  // Actions
  Future<void> _syncToBrain() async {
    if (_selectedMood == null) return;

    setState(() {
      _isSyncing = true;
      _syncSuccess = false;
    });

    mongo.Db? db;
    final String? uri = dotenv.env['MONGO_URI_MOBILE'];
    final String collectionName = dotenv.env['COLLECTION_NAME'] ?? 'overrides';

    if (uri == null) {
      _showError("Configuration manquante (.env)");
      setState(() => _isSyncing = false);
      return;
    }

    try {
      final String dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

      // 1. Connection with Timeout
      db = await mongo.Db.create(uri);
      await db.open().timeout(const Duration(seconds: 5), onTimeout: () {
        throw TimeoutException("Le serveur ne répond pas.");
      });

      // 2. Prepare Data
      final collection = db.collection(collectionName);
      final updateData = {
        "date": dateStr,
        "sleep_hours": _sleepHours,
        "mood_manual": _selectedMood,
        "last_updated": DateTime.now().toIso8601String(),
        "device": "android_app"
      };

      // 3. Upsert
      await collection.update(
        mongo.where.eq('date', dateStr),
        updateData,
        upsert: true,
      );

      // 4. Success Feedback
      await HapticFeedback.heavyImpact();
      if (mounted) {
        setState(() => _syncSuccess = true);
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _syncSuccess = false);
        });
      }
    } catch (e) {
      _showError("Erreur Sync: $e");
    } finally {
      if (db != null && db.isConnected) {
        await db.close();
      }
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // --- UI BUILDERS ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              const Spacer(),
              _buildSleepSlider(),
              const Spacer(),
              _buildMoodGrid(),
              const Spacer(flex: 2),
              _buildSyncButton(),
              const SizedBox(height: 20),
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
        Text(
          "MOOD OVERRIDE",
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
            color: Colors.white54,
          ),
        ),
        Text(
          DateFormat('MMM dd').format(DateTime.now()).toUpperCase(),
          style: GoogleFonts.inter(
            fontWeight: FontWeight.bold,
            color: Colors.white54,
          ),
        ),
      ],
    );
  }

  Widget _buildSleepSlider() {
    return Column(
      children: [
        SleekCircularSlider(
          initialValue: _sleepHours,
          max: 12,
          appearance: CircularSliderAppearance(
            size: 280,
            startAngle: 180,
            angleRange: 180,
            customColors: CustomSliderColors(
              progressBarColor: const Color(0xFF00FF9D),
              trackColor: Colors.white10,
              shadowColor: const Color(0xFF00FF9D),
              shadowMaxOpacity: 0.2,
            ),
            infoProperties: InfoProperties(
              mainLabelStyle: GoogleFonts.inter(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              modifier: (double value) => '${value.toStringAsFixed(1)}h',
            ),
          ),
          onChange: (double value) {
            // Haptic feedback only on integer changes to avoid spamming
            if (value.floor() != _sleepHours.floor()) {
              HapticFeedback.selectionClick();
            }
            setState(() => _sleepHours = value);
          },
        ),
        const Text(
          "SLEEP INPUT",
          style: TextStyle(color: Colors.white38, letterSpacing: 2),
        ),
      ],
    );
  }

  Widget _buildMoodGrid() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: _moods.map((mood) {
        final bool isSelected = _selectedMood == mood['id'];
        return GestureDetector(
          onTap: () {
            HapticFeedback.mediumImpact();
            setState(() => _selectedMood = isSelected ? null : mood['id']);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFFBD00FF).withOpacity(0.2)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color:
                    isSelected ? const Color(0xFFBD00FF) : Colors.transparent,
                width: 2,
              ),
            ),
            transform: isSelected
                ? Matrix4.diagonal3Values(1.15, 1.15, 1.0)
                : Matrix4.identity(),
            child: Text(
              mood['emoji']!,
              style: TextStyle(
                fontSize: 32,
                shadows: isSelected
                    ? [
                        const BoxShadow(
                            color: Color(0xFFBD00FF), blurRadius: 20)
                      ]
                    : [],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSyncButton() {
    final bool isEnabled = _selectedMood != null || _isSyncing;

    return GestureDetector(
      onTap: (isEnabled && !_isSyncing) ? _syncToBrain : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        opacity: isEnabled ? 1.0 : 0.3,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          height: 80,
          decoration: BoxDecoration(
            color: _syncSuccess
                ? const Color(0xFF00FF9D)
                : (_isSyncing ? Colors.grey[900] : Colors.transparent),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color:
                  _syncSuccess ? Colors.transparent : const Color(0xFF00FF9D),
              width: 2,
            ),
            boxShadow: _syncSuccess
                ? [const BoxShadow(color: Color(0xFF00FF9D), blurRadius: 30)]
                : [],
          ),
          child: Center(
            child: _isSyncing
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : Text(
                    _syncSuccess ? "SYNCED" : "SYNC TO BRAIN",
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color:
                          _syncSuccess ? Colors.black : const Color(0xFF00FF9D),
                      letterSpacing: 2,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
