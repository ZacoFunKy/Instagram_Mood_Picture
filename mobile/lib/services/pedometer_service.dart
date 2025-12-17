import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

class PedometerService {
  // Singleton
  static final PedometerService _instance = PedometerService._internal();
  static PedometerService get instance => _instance;

  PedometerService._internal();

  StreamSubscription<StepCount>? _subscription;
  final StreamController<int> _stepController =
      StreamController<int>.broadcast();

  // Public Stream for UI
  Stream<int> get stepStream => _stepController.stream;

  int _stepsToday = 0;
  int _offset = 0; // Steps stored at start of day

  /// Initialize Pedometer and Permissions
  Future<void> init() async {
    bool granted = await Permission.activityRecognition.isGranted;
    if (!granted) {
      granted = await Permission.activityRecognition.request().isGranted;
    }

    if (granted) {
      // 1. Load persisted data to restore state before first event
      await _loadDayState();

      // 2. Listen to sensor updates
      _subscription = Pedometer.stepCountStream.listen(
        _onStepCount,
        onError: _onError,
      );
      debugPrint("👟 PedometerService: Started");
    } else {
      debugPrint("🚫 PedometerService: Permission Denied");
    }
  }

  void _onStepCount(StepCount event) async {
    final prefs = await SharedPreferences.getInstance();

    // Safety check for midnight reset while app was running
    await _checkMidnightReset();

    // Calibration: On first event or reboot
    if (_offset == 0) {
      // If we already have stored steps today, we need to respect them.
      // But simpler logic: Offset = Sensor - StepsToday.
      // If StepsToday is 0 (new day), Offset = Sensor.
      // If StepsToday is 500 (restored), and Sensor is 1000, Offset = 500.
      _offset = event.steps - _stepsToday;
      await prefs.setInt('steps_offset', _offset);
    }

    // Calculate real steps
    int calced = event.steps - _offset;

    // Handle Reboot (Sensor < Offset is impossible unless reboot reset to 0)
    if (calced < 0) {
      debugPrint("👟 Device Reboot Detected (Sensor Reset)");
      _offset = -_stepsToday; // Negative offset to keep current count
      calced = event.steps - _offset;
      await prefs.setInt('steps_offset', _offset);
    }

    _stepsToday = calced;
    _stepController.add(_stepsToday);

    // Persist
    await prefs.setInt('daily_steps', _stepsToday);
    // debugPrint("👟 Steps: $_stepsToday (Sensor: ${event.steps}, Offset: $_offset)");
  }

  void _onError(error) {
    debugPrint("❌ Pedometer Error: $error");
  }

  Future<void> _loadDayState() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final savedDate = prefs.getString('step_date');

    if (savedDate == today) {
      _stepsToday = prefs.getInt('daily_steps') ?? 0;
      _offset = prefs.getInt('steps_offset') ?? 0;
      // Emit immediately so UI has data before first sensor event
      _stepController.add(_stepsToday);
    } else {
      await _resetDay(prefs, today);
    }
  }

  Future<void> _checkMidnightReset() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final savedDate = prefs.getString('step_date');

    if (savedDate != today) {
      await _resetDay(prefs, today);
    }
  }

  Future<void> _resetDay(SharedPreferences prefs, String date) async {
    debugPrint("📅 New Day: Resetting Steps");
    await prefs.setString('step_date', date);
    await prefs.setInt('daily_steps', 0);
    await prefs.setInt('steps_offset', 0);
    _stepsToday = 0;
    _offset = 0;
    _stepController.add(0);
  }

  // Expose current value strictly
  int get currentSteps => _stepsToday;

  void dispose() {
    _subscription?.cancel();
    _stepController.close();
  }
}
