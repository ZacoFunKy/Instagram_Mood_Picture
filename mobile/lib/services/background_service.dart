import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:intl/intl.dart';
import 'package:mongo_dart/mongo_dart.dart' as mongo;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

import 'database_service.dart';
import '../models/mood_entry.dart';

const String taskName = "syncMoodData";

// Top-level function for WorkManager
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    debugPrint("🏗️ Background Task Started: $task");

    if (task == taskName) {
      try {
        // 1. Initialize Env (Required in background isolate)
        await dotenv.load(fileName: ".env");

        // 2. Connect DB
        await DatabaseService.instance.database
            .timeout(const Duration(seconds: 30));

        // 3. Get latest steps
        final prefs = await SharedPreferences.getInstance();
        int steps = prefs.getInt('last_known_steps') ?? 0;

        // 4. Get Location (Best Effort)
        String? city;
        try {
          // Check permission first (though WorkManager might skip if restricted)
          LocationPermission permission = await Geolocator.checkPermission();
          if (permission == LocationPermission.whileInUse ||
              permission == LocationPermission.always) {
            Position position = await Geolocator.getCurrentPosition(
                desiredAccuracy: LocationAccuracy.medium,
                timeLimit: const Duration(seconds: 10));

            List<Placemark> placemarks = await placemarkFromCoordinates(
                position.latitude, position.longitude);

            if (placemarks.isNotEmpty) {
              city = placemarks.first.locality;
              debugPrint("📍 Background Location: $city");
            }
          } else {
            debugPrint("⚠️ Background Location Permission Missing");
          }
        } catch (locError) {
          debugPrint("⚠️ Background Location Error: $locError");
        }

        // 5. Perform Sync
        await _performBackgroundSync(steps, city);

        return Future.value(true);
      } catch (e) {
        debugPrint("❌ Background Task Failed: $e");
        return Future.value(false);
      }
    }
    return Future.value(true);
  });
}

Future<void> _performBackgroundSync(int steps, String? location) async {
  final collection = await DatabaseService.instance.overrides;

  // We can only sync what we know. In background, we might not have access to
  // fresh sensor data properly without a foreground service.
  // However, we can re-push the last known state to ensure it's up to date.

  final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

  final entry = MoodEntry(
      date: dateStr,
      sleepHours:
          0, // We don't overwrite these zeroed values if upsert works correctly?
      // ACTUALLY: ReplaceOne will wipe them if we aren't careful.
      // We should probably FIND first, updates steps, then REPLACE.
      steps: steps,
      lastUpdated: DateTime.now(),
      device: "android_bg_sync");

  // Safer Background Update: Partial Update ($set)
  // We don't want to wipe Sleep/Energy if they were set in UI.
  // Safer Background Update: Partial Update ($set)
  var modifier = mongo.modify
      .set('steps', steps)
      .set('lastUpdated', DateTime.now().toIso8601String());

  if (location != null) {
    modifier = modifier.set('location', location);
  }

  await collection.update(mongo.where.eq('date', dateStr), modifier,
      upsert: true);

  debugPrint("✅ Background Sync Complete: $steps steps");
}
