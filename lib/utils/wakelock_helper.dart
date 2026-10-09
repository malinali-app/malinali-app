import 'package:wakelock_plus/wakelock_plus.dart';

/// Helper to manage screen wakelock safely across platforms and test environments.
class WakelockHelper {
  static Future<void> enable() async {
    try {
      await WakelockPlus.enable();
    } catch (_) {
      // Ignored on unsupported platforms or during widget/unit tests
    }
  }

  static Future<void> disable() async {
    try {
      await WakelockPlus.disable();
    } catch (_) {
      // Ignored on unsupported platforms or during widget/unit tests
    }
  }
}
