import 'package:flutter/foundation.dart';

/// Logs to the Flutter console (visible with `flutter run`).
class AppLog {
  static void info(String message) {
    debugPrint('[Malinali] $message');
  }

  static void warn(String message) {
    debugPrint('[Malinali] WARN: $message');
  }

  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    debugPrint('[Malinali] ERROR: $message');
    if (error != null) {
      debugPrint('[Malinali] $error');
    }
    if (stackTrace != null) {
      debugPrint('[Malinali] $stackTrace');
    }
  }
}
