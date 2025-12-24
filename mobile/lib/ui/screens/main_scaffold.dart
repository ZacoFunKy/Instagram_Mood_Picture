import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:permission_handler/permission_handler.dart';

import '../widgets/glass_card.dart';
import 'input_screen.dart';
import 'history_screen.dart';
import 'stats_screen.dart';
import '../../utils/app_theme.dart';

class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    InputScreen(),
    HistoryScreen(),
    StatsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    // Request all necessary permissions at once
    await [
      Permission.location,
      Permission.activityRecognition,
    ].request();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          _screens[_currentIndex],
          Positioned(
            left: 20,
            right: 20,
            bottom: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withOpacity(0.1),
                    Colors.white.withOpacity(0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(
                  color: Colors.white.withOpacity(0.2),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 32,
                    spreadRadius: 4,
                  ),
                  BoxShadow(
                    color: AppTheme.neonGreen.withOpacity(0.1),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _navItem(0, Icons.add_circle_outline_rounded,
                      Icons.add_circle_rounded),
                  _navItem(1, Icons.history_rounded, Icons.history_rounded),
                  _navItem(2, Icons.bar_chart_rounded, Icons.bar_chart_rounded),
                ],
              ),
            ).animate().slideY(
                begin: 1, end: 0, duration: 600.ms, curve: Curves.easeOutBack),
          ),
        ],
      ),
    );
  }

  Widget _navItem(int index, IconData icon, IconData activeIcon) {
    bool isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _currentIndex = index);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
                  colors: [
                    AppTheme.neonGreen.withOpacity(0.3),
                    AppTheme.neonGreen.withOpacity(0.1),
                  ],
                )
              : LinearGradient(
                  colors: [
                    Colors.transparent,
                    Colors.transparent,
                  ],
                ),
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected
                ? AppTheme.neonGreen.withOpacity(0.5)
                : Colors.transparent,
            width: 1.5,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppTheme.neonGreen.withOpacity(0.4),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ]
              : [],
        ),
        child: Icon(
          isSelected ? activeIcon : icon,
          color: isSelected ? AppTheme.neonGreen : Colors.white54,
          size: 28,
        ),
      ),
    ).animate().fadeIn().scale();
  }
}
