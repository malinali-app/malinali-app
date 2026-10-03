// Dart imports:
import 'dart:io';

// Flutter imports:
import 'package:flutter/services.dart';

const _channel = MethodChannel('com.malinali.malinaliapp/firebase_test_lab');

/// Whether the app is running in Firebase Test Lab (Play pre-launch reports).
///
/// Always false on non-Android platforms. Failures default to false so real
/// devices keep analytics.
Future<bool> isFirebaseTestLab() async {
  if (!Platform.isAndroid) return false;
  try {
    return await _channel.invokeMethod<bool>('isFirebaseTestLab') ?? false;
  } on PlatformException {
    return false;
  }
}
