// Package imports:
import 'package:aptabase_flutter/aptabase_flutter.dart';

// Project imports:
import 'package:malinali/utils/firebase_test_labs.dart';
import 'package:malinali/secrets.dart';

/// Same disabled key as widget tests: `A-SH` without host makes the SDK no-op
/// [Aptabase.instance.trackEvent] safely (avoids LateInitializationError).
const _aptabaseDisabledKey = 'A-SH-0000000000';

/// Initializes Aptabase, skipping real tracking on Firebase Test Lab devices.
Future<void> initAptabaseSkippingTestLab() async {
  final key =
      await isFirebaseTestLab() ? _aptabaseDisabledKey : malinaliAptabaseKey;
  await Aptabase.init(key);
}
