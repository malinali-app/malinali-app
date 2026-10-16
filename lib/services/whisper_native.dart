import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

void _ensureBindings() {
  sherpa_onnx.initBindings();
}

/// Final recognizer text, or the last partial when the engine returns nothing.
String preferSpokenTranscript(String finalText, String? partial) {
  final spoken = finalText.trim();
  if (spoken.isNotEmpty) return spoken;
  return partial?.trim() ?? '';
}

class WhisperOnnxPaths {
  const WhisperOnnxPaths({
    required this.encoder,
    required this.decoder,
    required this.tokens,
    this.modelType = 'whisper',
    this.joiner,
    this.sherpaModelType = '',
  });

  final String encoder;
  final String decoder;
  final String tokens;
  final String modelType;
  final String? joiner;

  /// sherpa-onnx online model family, e.g. `zipformer2`. Empty means auto.
  final String sherpaModelType;

  bool get isOnline => modelType == 'transducer';
}

/// One-shot sherpa-onnx decode of a 16 kHz WAV.
Future<Map<String, dynamic>> sherpaTranscribeWav({
  required String wavPath,
  required WhisperOnnxPaths model,
  String language = 'auto',
  bool translate = false,
  int? threads,
}) {
  final nThreads = threads ?? (Platform.isAndroid || Platform.isIOS ? 2 : 4);
  final lang = language.trim().toLowerCase();
  final encoder = model.encoder;
  final decoder = model.decoder;
  final tokens = model.tokens;
  final modelType = model.modelType;
  final joiner = model.joiner;

  return Isolate.run(() {
    _ensureBindings();

    final modelConfig = _offlineModelConfig(
      tokens: tokens,
      numThreads: nThreads,
      modelType: modelType,
      encoder: encoder,
      decoder: decoder,
      joiner: joiner,
      language: lang,
      translate: translate,
    );

    final config = sherpa_onnx.OfflineRecognizerConfig(model: modelConfig);
    final recognizer = sherpa_onnx.OfflineRecognizer(config);
    try {
      final wave = sherpa_onnx.readWave(wavPath);
      final stream = recognizer.createStream();
      try {
        stream.acceptWaveform(
          samples: wave.samples,
          sampleRate: wave.sampleRate,
        );
        recognizer.decode(stream);
        final text = recognizer.getResult(stream).text;
        return {'@type': 'ok', 'text': text};
      } finally {
        stream.free();
      }
    } catch (e) {
      return {'@type': 'error', 'message': e.toString()};
    } finally {
      recognizer.free();
    }
  });
}

/// Alias for backward compatibility
Future<Map<String, dynamic>> whisperTranscribeWav({
  required String wavPath,
  required WhisperOnnxPaths model,
  String language = 'auto',
  bool translate = false,
  int? threads,
}) => sherpaTranscribeWav(
  wavPath: wavPath,
  model: model,
  language: language,
  translate: translate,
  threads: threads,
);

/// Abstract base for live sessions (Offline/Whisper vs Online/Icefall).
abstract class SherpaLiveSession {
  Stream<String> get partials;
  void feed(Uint8List pcm16Bytes);
  Future<String> stop();
  Future<void> dispose();
  void setSink(IOSink? sink);
}

/// Offline Whisper over buffered PCM16 (live mic → one decode on stop).
class MalinaliWhisperLiveSession implements SherpaLiveSession {
  MalinaliWhisperLiveSession._(
    this._samples,
    this._model,
    this._language,
    this._translate,
  );

  final List<int> _samples;
  final WhisperOnnxPaths _model;
  final String _language;
  final bool _translate;
  bool _stopped = false;
  final StreamController<String> _partials =
      StreamController<String>.broadcast();
  final Completer<String> _final = Completer<String>();
  IOSink? _sink;

  @override
  Stream<String> get partials => _partials.stream;

  @override
  void setSink(IOSink? sink) => _sink = sink;

  @override
  void feed(Uint8List pcm16Bytes) {
    if (_stopped) return;
    _samples.addAll(pcm16Bytes);
    _sink?.add(pcm16Bytes);
  }

  @override
  Future<String> stop() async {
    if (_stopped) return _final.future;
    _stopped = true;
    await _sink?.close();
    _sink = null;
    try {
      final floats = _pcm16ToFloat(_samples);
      final encoder = _model.encoder;
      final decoder = _model.decoder;
      final tokens = _model.tokens;
      final lang = _language.trim().toLowerCase();
      final translate = _translate;
      final modelType = _model.modelType;
      final joiner = _model.joiner;

      final text = await Isolate.run(() {
        _ensureBindings();

        final modelConfig = _offlineModelConfig(
          tokens: tokens,
          numThreads: 2,
          modelType: modelType,
          encoder: encoder,
          decoder: decoder,
          joiner: joiner,
          language: lang,
          translate: translate,
        );

        final config = sherpa_onnx.OfflineRecognizerConfig(model: modelConfig);
        final recognizer = sherpa_onnx.OfflineRecognizer(config);
        try {
          final stream = recognizer.createStream();
          try {
            stream.acceptWaveform(samples: floats, sampleRate: 16000);
            recognizer.decode(stream);
            return recognizer.getResult(stream).text;
          } finally {
            stream.free();
          }
        } finally {
          recognizer.free();
        }
      });
      final spoken = text.trim();
      if (!_partials.isClosed) {
        if (spoken.isNotEmpty) _partials.add(spoken);
        await _partials.close();
      }
      _final.complete(spoken);
    } catch (e) {
      if (!_partials.isClosed) {
        _partials.addError(e);
        await _partials.close();
      }
      if (!_final.isCompleted) _final.complete('');
    }
    return _final.future;
  }

  @override
  Future<void> dispose() async {
    if (!_partials.isClosed) await _partials.close();
  }
}

/// Real-time Sherpa OnlineRecognizer session (Zipformer/Icefall).
class SherpaOnlineLiveSession implements SherpaLiveSession {
  SherpaOnlineLiveSession._(this._model);

  final WhisperOnnxPaths _model;
  final StreamController<String> _partials =
      StreamController<String>.broadcast();

  sherpa_onnx.OnlineRecognizer? _recognizer;
  sherpa_onnx.OnlineStream? _stream;
  bool _stopped = false;
  IOSink? _sink;
  String _latest = '';

  @override
  Stream<String> get partials => _partials.stream;

  @override
  void setSink(IOSink? sink) => _sink = sink;

  Future<void> _init() async {
    _ensureBindings();
    try {
      final config = sherpa_onnx.OnlineRecognizerConfig(
        feat: const sherpa_onnx.FeatureConfig(
          sampleRate: 16000,
          featureDim: 80,
        ),
        model: sherpa_onnx.OnlineModelConfig(
          transducer: sherpa_onnx.OnlineTransducerModelConfig(
            encoder: _model.encoder,
            decoder: _model.decoder,
            joiner: _model.joiner ?? '',
          ),
          tokens: _model.tokens,
          numThreads: 2,
          debug: true, // Enable debug for now
          modelType: _model.sherpaModelType,
        ),
      );
      _recognizer = sherpa_onnx.OnlineRecognizer(config);
      _stream = _recognizer!.createStream();
      print('SherpaOnlineLiveSession: Initialized successfully');
    } catch (e, stack) {
      print('SherpaOnlineLiveSession: Initialization failed: $e');
      print(stack);
      _partials.addError(e);
    }
  }

  @override
  void feed(Uint8List pcm16Bytes) {
    if (_stopped || _recognizer == null || _stream == null) return;
    _sink?.add(pcm16Bytes);
    final floats = _pcm16ToFloat(pcm16Bytes);
    if (floats.isEmpty) return;

    try {
      _stream!.acceptWaveform(samples: floats, sampleRate: 16000);
      while (_recognizer!.isReady(_stream!)) {
        _recognizer!.decode(_stream!);
      }
      final result = _recognizer!.getResult(_stream!);
      if (result.text.isNotEmpty) {
        _latest = result.text;
        print('SherpaOnlineLiveSession: Got text: ${result.text}');
        _partials.add(result.text);
      }
    } catch (e) {
      print('SherpaOnlineLiveSession: Feed error: $e');
    }
  }

  @override
  Future<String> stop() async {
    if (_stopped) return '';
    _stopped = true;
    await _sink?.close();
    _sink = null;

    if (_recognizer != null && _stream != null) {
      _stream!.inputFinished();
      while (_recognizer!.isReady(_stream!)) {
        _recognizer!.decode(_stream!);
      }
      final result = preferSpokenTranscript(
        _recognizer!.getResult(_stream!).text,
        _latest,
      );
      if (result.isNotEmpty && !_partials.isClosed) {
        _partials.add(result);
      }
      await dispose();
      return result;
    }

    await dispose();
    return '';
  }

  @override
  Future<void> dispose() async {
    _stream?.free();
    _recognizer?.free();
    _stream = null;
    _recognizer = null;
    if (!_partials.isClosed) await _partials.close();
  }
}

Float32List pcm16LeToFloat32(List<int> bytes) {
  final even = bytes.length - (bytes.length % 2);
  final out = Float32List(even ~/ 2);
  if (even == 0) return out;
  final pcm = Uint8List(even);
  pcm.setRange(0, even, bytes);
  final view = ByteData.sublistView(pcm);
  for (var i = 0; i < out.length; i++) {
    out[i] = view.getInt16(i * 2, Endian.little) / 32768.0;
  }
  return out;
}

Float32List _pcm16ToFloat(List<int> bytes) => pcm16LeToFloat32(bytes);

Future<SherpaLiveSession> startSherpaLiveSession({
  required WhisperOnnxPaths model,
  String lang = 'auto',
  bool translate = false,
}) async {
  if (model.isOnline) {
    final session = SherpaOnlineLiveSession._(model);
    await session._init();
    return session;
  } else {
    return MalinaliWhisperLiveSession._(<int>[], model, lang, translate);
  }
}

/// Legacy alias
Future<MalinaliWhisperLiveSession> startMalinaliWhisperLiveSession({
  required WhisperOnnxPaths model,
  String lang = 'auto',
  bool translate = false,
}) async {
  return MalinaliWhisperLiveSession._(<int>[], model, lang, translate);
}

/// No-op: sherpa recognizers are freed after each decode.
Future<void> whisperReleaseModel() async {}

sherpa_onnx.OfflineModelConfig _offlineModelConfig({
  required String tokens,
  required int numThreads,
  required String modelType,
  required String encoder,
  required String decoder,
  required String? joiner,
  required String language,
  required bool translate,
}) {
  final whisper = modelType == 'whisper';
  final transducer = modelType == 'transducer';
  return sherpa_onnx.OfflineModelConfig(
    tokens: tokens,
    numThreads: numThreads,
    debug: false,
    modelType: modelType,
    whisper:
        whisper
            ? sherpa_onnx.OfflineWhisperModelConfig(
              encoder: encoder,
              decoder: decoder,
              language: language == 'auto' ? '' : language,
              task: translate ? 'translate' : 'transcribe',
            )
            : const sherpa_onnx.OfflineWhisperModelConfig(),
    transducer:
        transducer
            ? sherpa_onnx.OfflineTransducerModelConfig(
              encoder: encoder,
              decoder: decoder,
              joiner: joiner ?? '',
            )
            : const sherpa_onnx.OfflineTransducerModelConfig(),
  );
}
