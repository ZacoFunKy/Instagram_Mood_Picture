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

const String taskName = "syncMoodData";

// Top-level function for WorkManager
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    debugPrint("🏗️ Background Task Started: $task");

    if (task == taskName) {
      int retryCount = 0;
      const maxRetries = 2;

      while (retryCount < maxRetries) {
        try {
          // 1. Initialize Env (Required in background isolate)
          await dotenv.load(fileName: ".env");

          // 2. Connect DB with timeout
          try {
            await DatabaseService.instance.database
                .timeout(const Duration(seconds: 30));
          } catch (e) {
            debugPrint("⚠️ DB Connection Failed (Retry $retryCount/$maxRetries): $e");
            if (retryCount < maxRetries - 1) {
              await Future.delayed(const Duration(seconds: 5));
              retryCount++;
              continue;
            }
            throw Exception("Max retries reached for DB connection");
          }

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
            debugPrint("⚠️ Background Location Error (Non-blocking): $locError");
            // Don't retry, location is optional
          }

          // 5. Perform Sync
          await _performBackgroundSync(steps, city);

          debugPrint("✅ Background Task Completed Successfully");
          return Future.value(true);
        } catch (e) {
          debugPrint("❌ Background Task Error (Retry $retryCount/$maxRetries): $e");
          if (retryCount < maxRetries - 1) {
            retryCount++;
            await Future.delayed(const Duration(seconds: 5));
          } else {
            debugPrint("❌ Background Task Failed after $maxRetries retries");
            return Future.value(false);
          }
        }
      }
      return Future.value(false);
    }
    return Future.value(true);
  });
}

Future<void> _performBackgroundSync(int steps, String? location) async {
  final collection = await DatabaseService.instance.overrides;
  final prefs = await SharedPreferences.getInstance();

  final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
  final now = DateTime.now().toIso8601String();

  // Vérifier si une entrée existe déjà pour aujourd'hui
  final existingDoc = await collection.findOne(mongo.where.eq('date', dateStr));

  if (existingDoc != null) {
    // Si l'entrée existe, ne mettre à jour QUE les steps et location
    // Ne PAS toucher aux valeurs sleep_hours, energy, stress, social
    var modifier = mongo.modify
        .set('steps_count', steps)
        .set('last_updated', now)
        .set('last_auto_sync', now)  // Track when the auto-sync happened
        .set('device', 'android_bg_sync');

    if (location != null) {
      modifier = modifier.set('location', location);
    }

    await collection.update(mongo.where.eq('date', dateStr), modifier);
    
    // Update cache: Track last automatic sync timestamp
    await prefs.setString('last_auto_sync_timestamp', now);
    
    debugPrint("✅ Background Sync Complete (Update): $steps steps at $now");
  } else {
    // Si aucune entrée n'existe, créer une nouvelle entrée SANS valeurs par défaut
    // pour sleep_hours (ne pas mettre 0, laisser le backend gérer)
    var newDoc = {
      'date': dateStr,
      'steps_count': steps,
      'last_updated': now,
      'last_auto_sync': now,  // Track when the auto-sync happened
      'device': 'android_bg_sync',
    };

    if (location != null) {
      newDoc['location'] = location;
    }

    await collection.insert(newDoc);
    
    // Update cache: Track last automatic sync timestamp
    await prefs.setString('last_auto_sync_timestamp', now);
    
    debugPrint("✅ Background Sync Complete (Insert): $steps steps at $now");
  }
}
