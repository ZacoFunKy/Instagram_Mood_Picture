import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screen_state/screen_state.dart';
import 'dart:async';

/// Service for automatic sleep tracking using Android sensors
/// Detects bedtime (screen off at night) and wake time (screen on in morning)
class SleepTrackingService {
  static final SleepTrackingService _instance = SleepTrackingService._internal();
  factory SleepTrackingService() => _instance;
  SleepTrackingService._internal();

  bool _isTracking = false;
  StreamSubscription<ScreenStateEvent>? _screenSubscription;

  /// Start automatic sleep tracking
  Future<void> startTracking() async {
    if (_isTracking) return;

    try {
      final screenState = ScreenState();
      _screenSubscription = screenState.screenStateStream?.listen((event) {
        _handleScreenEvent(event);
      });

      _isTracking = true;
      print('✅ Sleep tracking started');
    } catch (e) {
      print('⚠️ Sleep tracking error: $e');
    }
  }

  /// Handle screen state changes
  Future<void> _handleScreenEvent(ScreenStateEvent event) async {
    final now = DateTime.now();
    final hour = now.hour;

    // Bedtime detection: Screen off between 20:00 and 04:00
    if (event == ScreenStateEvent.SCREEN_OFF) {
      if (hour >= 20 || hour <= 4) {
        await _recordBedtime(now);
      }
    }

    // Wake time detection: Screen on between 05:00 and 11:00
    if (event == ScreenStateEvent.SCREEN_ON) {
      if (hour >= 5 && hour <= 11) {
        await _recordWakeTime(now);
      }
    }
  }

  /// Record bedtime
  Future<void> _recordBedtime(DateTime time) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastBedtime = prefs.getString('last_bedtime');

      // Only record if not already recorded in last 2 hours (avoid false detections)
      if (lastBedtime != null) {
        final last = DateTime.parse(lastBedtime);
        if (time.difference(last).inHours < 2) {
          return;
        }
      }

      await prefs.setString('last_bedtime', time.toIso8601String());
      print('😴 Bedtime recorded: ${time.hour}:${time.minute.toString().padLeft(2, '0')}');
    } catch (e) {
      print('⚠️ Record bedtime error: $e');
    }
  }

  /// Record wake time
  Future<void> _recordWakeTime(DateTime time) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastWakeTime = prefs.getString('last_waketime');

      // Only record if not already recorded today
      if (lastWakeTime != null) {
        final last = DateTime.parse(lastWakeTime);
        final today = DateTime(time.year, time.month, time.day);
        final lastDay = DateTime(last.year, last.month, last.day);
        if (today == lastDay) {
          return; // Already recorded wake time today
        }
      }

      await prefs.setString('last_waketime', time.toIso8601String());
      print('☀️ Wake time recorded: ${time.hour}:${time.minute.toString().padLeft(2, '0')}');
    } catch (e) {
      print('⚠️ Record wake time error: $e');
    }
  }

  /// Get actual sleep hours from tracked bedtime/wake time
  Future<double?> getActualSleepHours() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bedtimeStr = prefs.getString('last_bedtime');
      final waketimeStr = prefs.getString('last_waketime');

      if (bedtimeStr == null || waketimeStr == null) {
        return null;
      }

      final bedtime = DateTime.parse(bedtimeStr);
      final waketime = DateTime.parse(waketimeStr);

      // Check if wake time is after bedtime (same night)
      if (waketime.isBefore(bedtime)) {
        return null; // Invalid data
      }

      final sleepMinutes = waketime.difference(bedtime).inMinutes;
      final sleepHours = sleepMinutes / 60.0;

      // Sanity check: sleep between 2h and 14h
      if (sleepHours < 2 || sleepHours > 14) {
        return null;
      }

      print('💤 Detected sleep: ${sleepHours.toStringAsFixed(1)}h (${bedtime.hour}:${bedtime.minute.toString().padLeft(2, '0')} → ${waketime.hour}:${waketime.minute.toString().padLeft(2, '0')})');
      return sleepHours;
    } catch (e) {
      print('⚠️ Get sleep hours error: $e');
      return null;
    }
  }

  /// Get bedtime string for analyzer
  Future<String> getBedtimeString() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bedtimeStr = prefs.getString('last_bedtime');
      if (bedtimeStr == null) return "00:00";

      final bedtime = DateTime.parse(bedtimeStr);
      return '${bedtime.hour.toString().padLeft(2, '0')}:${bedtime.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return "00:00";
    }
  }

  /// Get wake time string for analyzer
  Future<String> getWakeTimeString() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final waketimeStr = prefs.getString('last_waketime');
      if (waketimeStr == null) return "08:00";

      final waketime = DateTime.parse(waketimeStr);
      return '${waketime.hour.toString().padLeft(2, '0')}:${waketime.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return "08:00";
    }
  }

  /// Stop tracking
  void stopTracking() {
    _screenSubscription?.cancel();
    _isTracking = false;
    print('⛔ Sleep tracking stopped');
  }

  /// Check if tracking is active
  bool get isTracking => _isTracking;
}
