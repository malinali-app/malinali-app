import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:malinali/services/vosk_model_service.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';
import 'package:vosk_flutter/vosk_flutter.dart';

/// Cross-platform speech recognition via Vosk and microphone streaming.
/// Supports both Android and Windows desktop.
class SpeechRecognitionService {
  final VoskModelService _modelService;
  AudioRecorder? _audioRecorder;
  final AudioRecorder Function()? _recorderFactory;

  VoskFlutterPlugin? _vosk;
  Model? _model;
  Recognizer? _recognizer;
  VoskModel? _currentModel;

  bool _isInitialized = false;
  bool _isListening = false;

  StreamSubscription<List<int>>? _audioSubscription;

  Function(String)? onResult;
  Function(String)? onPartialResult;
  Function()? onError;

  SpeechRecognitionService({
    VoskModelService? modelService,
    AudioRecorder? audioRecorder,
    AudioRecorder Function()? recorderFactory,
  })  : _modelService = modelService ?? VoskModelService(),
        _audioRecorder = audioRecorder,
        _recorderFactory = recorderFactory;

  AudioRecorder _getRecorder() {
    return _audioRecorder ??=
        (_recorderFactory != null ? _recorderFactory() : AudioRecorder());
  }

  VoskModel? get currentModel => _currentModel;
  bool get isInitialized => _isInitialized;
  bool get isListening => _isListening;

  /// Ensure Windows MinGW companion DLLs are preloaded to avoid error 127.
  static void _ensureWindowsDllsLoaded() {
    if (!Platform.isWindows) return;
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      for (final name in [
        'libwinpthread-1.dll',
        'libgcc_s_seh-1.dll',
        'libstdc++-6.dll',
        'libvosk.dll',
      ]) {
        final dllFile = File(p.join(exeDir, name));
        if (dllFile.existsSync()) {
          try {
            DynamicLibrary.open(dllFile.path);
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  /// Initialize with a specific [VoskModel] (defaults to French asset model).
  Future<void> initialize({VoskModel? model}) async {
    final targetModel = model ?? VoskModelService.assetFrenchModel;
    if (_isInitialized && _currentModel?.name == targetModel.name) {
      return;
    }

    try {
      _ensureWindowsDllsLoaded();
      _vosk ??= VoskFlutterPlugin.instance();

      // Dispose existing model and recognizer if any
      await _disposeRecognizerAndModel();

      final modelPath = await _modelService.getModelPath(targetModel);
      _model = await _vosk!.createModel(modelPath);
      _recognizer = await _vosk!.createRecognizer(
        model: _model!,
        sampleRate: 16000,
      );

      _currentModel = targetModel;
      _isInitialized = true;
    } catch (e) {
      _isInitialized = false;
      onError?.call();
      rethrow;
    }
  }

  /// Switch the active VOSK model.
  Future<void> switchModel(VoskModel model) async {
    if (_isListening) {
      await stopListening();
    }
    await initialize(model: model);
  }

  /// Start recording and streaming audio into the VOSK recognizer.
  Future<void> startListening() async {
    if (!_isInitialized) {
      await initialize();
    }
    if (_isListening) return;

    try {
      final recorder = _getRecorder();
      final hasPermission = await recorder.hasPermission();
      if (!hasPermission) {
        throw Exception('Microphone permission not granted');
      }

      final stream = await recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );

      _isListening = true;

      _audioSubscription = stream.listen(
        (chunk) async {
          if (!_isListening || _recognizer == null) return;
          try {
            final isFinal = await _recognizer!.acceptWaveformBytes(chunk);
            if (isFinal) {
              final jsonResult = await _recognizer!.getResult();
              final text = _extractTextFromJson(jsonResult);
              if (text.isNotEmpty) {
                onResult?.call(text);
              }
            } else {
              final jsonResult = await _recognizer!.getPartialResult();
              final partial = _extractPartialFromJson(jsonResult);
              if (partial.isNotEmpty) {
                onPartialResult?.call(partial);
              }
            }
          } catch (_) {
            onError?.call();
          }
        },
        onError: (_) {
          _isListening = false;
          onError?.call();
        },
      );
    } catch (e) {
      _isListening = false;
      onError?.call();
      rethrow;
    }
  }

  /// Stop listening and flush the final recognition result.
  Future<void> stopListening() async {
    _isListening = false;

    try {
      await _audioSubscription?.cancel();
      _audioSubscription = null;

      final recorder = _audioRecorder;
      if (recorder != null) {
        try {
          await recorder.stop();
        } catch (_) {}
      }

      if (_recognizer != null) {
        final jsonResult = await _recognizer!.getFinalResult();
        final text = _extractTextFromJson(jsonResult);
        if (text.isNotEmpty) {
          onResult?.call(text);
        }
      }
    } catch (_) {}
  }

  Future<void> _disposeRecognizerAndModel() async {
    _recognizer = null;
    _model = null;
    _currentModel = null;
    _isInitialized = false;
  }

  String _extractTextFromJson(String jsonResult) {
    try {
      final decoded = jsonDecode(jsonResult);
      if (decoded is Map<String, dynamic>) {
        return (decoded['text'] as String? ?? '').trim();
      }
    } catch (_) {
      final textMatch = RegExp(r'"text"\s*:\s*"([^"]*)"').firstMatch(jsonResult);
      return (textMatch?.group(1) ?? '').trim();
    }
    return '';
  }

  String _extractPartialFromJson(String jsonResult) {
    try {
      final decoded = jsonDecode(jsonResult);
      if (decoded is Map<String, dynamic>) {
        return (decoded['partial'] as String? ?? '').trim();
      }
    } catch (_) {
      final textMatch =
          RegExp(r'"partial"\s*:\s*"([^"]*)"').firstMatch(jsonResult);
      return (textMatch?.group(1) ?? '').trim();
    }
    return '';
  }

  void dispose() {
    stopListening();
    _audioRecorder?.dispose();
    _audioRecorder = null;
    _disposeRecognizerAndModel();
    _vosk = null;
  }
}
