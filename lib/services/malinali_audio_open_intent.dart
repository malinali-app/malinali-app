import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Holds an audio path opened from outside the app (WhatsApp share / file manager).
class MalinaliAudioOpenIntent {
  MalinaliAudioOpenIntent._();
  static final MalinaliAudioOpenIntent instance = MalinaliAudioOpenIntent._();

  static const channelName = 'app.malinali.l10n/audio_open';
  static const _channel = MethodChannel(channelName);

  final _pathController = StreamController<String>.broadcast();
  Stream<String> get pathStream => _pathController.stream;

  String? _pendingPath;

  String? get pendingPath => _pendingPath;

  bool get hasPending => _pendingPath != null && _pendingPath!.isNotEmpty;

  static const audioExtensions = {
    '.opus',
    '.ogg',
    '.m4a',
    '.mp3',
    '.wav',
    '.aac',
    '.amr',
    '.3gp',
    '.flac',
    '.wma',
    '.webm',
  };

  /// True when [path] ends with a known audio extension.
  @visibleForTesting
  static bool looksLikeAudio(String path) {
    final lower = path.toLowerCase();
    return audioExtensions.any(lower.endsWith);
  }

  void setPendingPath(String? path) {
    final cleaned = path?.trim() ?? '';
    if (cleaned.isEmpty) {
      _pendingPath = null;
      return;
    }
    debugPrint('MalinaliAudioOpenIntent: pending=$cleaned');
    _pendingPath = cleaned;
    _pathController.add(cleaned);
  }

  /// Returns and clears the pending path.
  String? takePendingPath() {
    final path = _pendingPath;
    _pendingPath = null;
    return path;
  }

  /// Clears pending state between unit tests.
  @visibleForTesting
  void resetForTest() {
    _pendingPath = null;
  }

  /// Captures Android VIEW/SEND intents (and optional argv paths on desktop).
  ///
  /// Always probes the MethodChannel (except on web) so unit tests can mock
  /// `getPendingAudioPath` on any host OS. MissingPluginException is ignored.
  Future<void> bootstrap({List<String> args = const []}) async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onAudioPath') {
        final path = call.arguments?.toString();
        if (path != null && path.isNotEmpty) {
          setPendingPath(path);
        }
      }
    });

    for (final arg in args) {
      final cleaned = arg.trim().replaceAll('"', '');
      if (looksLikeAudio(cleaned) && File(cleaned).existsSync()) {
        setPendingPath(cleaned);
        break;
      }
    }

    if (kIsWeb) return;

    try {
      final path = await _channel.invokeMethod<String>('getPendingAudioPath');
      if (path != null && path.isNotEmpty) {
        setPendingPath(path);
      }
    } on MissingPluginException {
      // Tests / unsupported platform without a mock handler.
    } catch (e) {
      debugPrint('MalinaliAudioOpenIntent.bootstrap error: $e');
    }
  }
}
