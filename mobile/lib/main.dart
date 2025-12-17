import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'services/database_service.dart';
import 'ui/screens/main_scaffold.dart';
import 'utils/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await dotenv.load(fileName: "assets/.env");
  } catch (e) {
    debugPrint("Warning: Config file not found: $e");
  }

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
