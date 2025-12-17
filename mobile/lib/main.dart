import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'services/mongo_service.dart';
import 'screens/main_scaffold.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: "assets/.env");
  } catch (e) {
    debugPrint("Warning: Config file not found: $e");
  }
  // Initialize DB in background to avoid blocking App Start
  // We use getOrConnect() in screens to await this if needed
  MongoService.instance.init();
  runApp(const MoodApp());
}

class MoodApp extends StatelessWidget {
  const MoodApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mood',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(context),
      home: const MainScaffold(),
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
        surface: Color(0xFF111111),
      ),
    );
  }
}
