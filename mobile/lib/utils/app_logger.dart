import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

class AppLogger {
  static final AppLogger _instance = AppLogger._internal();
  factory AppLogger() => _instance;
  AppLogger._internal();

  final List<String> _logs = [];
  final int _maxLogs = 200;

  List<String> get logs => List.unmodifiable(_logs);

  void log(String message) {
    final timestamp = DateFormat('HH:mm:ss').format(DateTime.now());
    final logEntry = "[$timestamp] $message";

    // Print to console for development
    debugPrint(logEntry);

    // Store in memory
    _logs.insert(0, logEntry);
    if (_logs.length > _maxLogs) {
      _logs.removeLast();
    }
  }

  void error(String message, [dynamic error, StackTrace? stackTrace]) {
    final timestamp = DateFormat('HH:mm:ss').format(DateTime.now());
    final logEntry = "[$timestamp] 🔴 ERROR: $message ${error ?? ''}";

    debugPrint(logEntry);
    if (stackTrace != null) debugPrintStack(stackTrace: stackTrace);

    _logs.insert(0, logEntry);
    if (_logs.length > _maxLogs) {
      _logs.removeLast();
    }
  }

  void clear() {
    _logs.clear();
  }
}
