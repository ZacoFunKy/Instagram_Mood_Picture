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

  final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

  // Vérifier si une entrée existe déjà pour aujourd'hui
  final existingDoc = await collection.findOne(mongo.where.eq('date', dateStr));

  if (existingDoc != null) {
    // Si l'entrée existe, ne mettre à jour QUE les steps et location
    // Ne PAS toucher aux valeurs sleep_hours, energy, stress, social
    var modifier = mongo.modify
        .set('steps_count', steps)
        .set('last_updated', DateTime.now().toIso8601String())
        .set('device', 'android_bg_sync');

    if (location != null) {
      modifier = modifier.set('location', location);
    }

    await collection.update(mongo.where.eq('date', dateStr), modifier);
    debugPrint("✅ Background Sync Complete (Update): $steps steps");
  } else {
    // Si aucune entrée n'existe, créer une nouvelle entrée SANS valeurs par défaut
    // pour sleep_hours (ne pas mettre 0, laisser le backend gérer)
    var newDoc = {
      'date': dateStr,
      'steps_count': steps,
      'last_updated': DateTime.now().toIso8601String(),
      'device': 'android_bg_sync',
    };

    if (location != null) {
      newDoc['location'] = location;
    }

    await collection.insert(newDoc);
    debugPrint("✅ Background Sync Complete (Insert): $steps steps");
  }
}
