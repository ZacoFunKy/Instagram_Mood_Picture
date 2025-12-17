import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:workmanager/workmanager.dart';
import 'services/background_service.dart'; // callbackDispatcher
import 'services/database_service.dart';
import 'ui/screens/main_scaffold.dart';
import 'utils/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint("Warning: Config file not found: $e");
  }

  // Init Background Service
  Workmanager().initialize(callbackDispatcher,
      isInDebugMode: false // Set true to debug easier
      );

  // Register Periodic Task (Every 2 Hours = 120 min)
  Workmanager().registerPeriodicTask("1", taskName,
      frequency: const Duration(hours: 2),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ));

  DatabaseService.instance.init();

  runApp(const MoodApp());
}

class MoodApp extends StatelessWidget {
  const MoodApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mood',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const MainScaffold(),
    );
  }
}
