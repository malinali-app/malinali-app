import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

void _ensureBindings() {
  sherpa_onnx.initBindings();
}

class WhisperOnnxPaths {
  const WhisperOnnxPaths({
    required this.encoder,
    required this.decoder,
    required this.tokens,
  });

  final String encoder;
  final String decoder;
  final String tokens;
}

/// One-shot sherpa-onnx Whisper decode of a 16 kHz WAV.
Future<Map<String, dynamic>> whisperTranscribeWav({
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
  return Isolate.run(() {
    _ensureBindings();
    final config = sherpa_onnx.OfflineRecognizerConfig(
      model: sherpa_onnx.OfflineModelConfig(
        whisper: sherpa_onnx.OfflineWhisperModelConfig(
          encoder: encoder,
          decoder: decoder,
          language: lang == 'auto' ? '' : lang,
          task: translate ? 'translate' : 'transcribe',
        ),
        tokens: tokens,
        modelType: 'whisper',
        numThreads: nThreads,
        debug: false,
      ),
    );
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

/// Offline Whisper over buffered PCM16 (live mic → one decode on stop).
class MalinaliWhisperLiveSession {
  MalinaliWhisperLiveSession._(this._samples, this._model, this._language, this._translate);

  final List<int> _samples;
  final WhisperOnnxPaths _model;
  final String _language;
  final bool _translate;
  bool _stopped = false;
  final StreamController<String> _partials = StreamController<String>.broadcast();
  final Completer<String> _final = Completer<String>();

  Stream<String> get partials => _partials.stream;

  void feed(Uint8List pcm16Bytes) {
    if (_stopped) return;
    _samples.addAll(pcm16Bytes);
  }

  Future<String> stop() async {
    if (_stopped) return _final.future;
    _stopped = true;
    try {
      final floats = _pcm16ToFloat(_samples);
      final encoder = _model.encoder;
      final decoder = _model.decoder;
      final tokens = _model.tokens;
      final lang = _language.trim().toLowerCase();
      final translate = _translate;
      final text = await Isolate.run(() {
        _ensureBindings();
        final config = sherpa_onnx.OfflineRecognizerConfig(
          model: sherpa_onnx.OfflineModelConfig(
            whisper: sherpa_onnx.OfflineWhisperModelConfig(
              encoder: encoder,
              decoder: decoder,
              language: lang == 'auto' ? '' : lang,
              task: translate ? 'translate' : 'transcribe',
            ),
            tokens: tokens,
            modelType: 'whisper',
            numThreads: 2,
            debug: false,
          ),
        );
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
      if (!_partials.isClosed) await _partials.close();
      _final.complete(text);
    } catch (e) {
      if (!_partials.isClosed) {
        _partials.addError(e);
        await _partials.close();
      }
      if (!_final.isCompleted) _final.complete('');
    }
    return _final.future;
  }
}

Float32List _pcm16ToFloat(List<int> bytes) {
  final even = bytes.length - (bytes.length % 2);
  final pcm = Uint8List.fromList(bytes.sublist(0, even));
  final samples = pcm.buffer.asInt16List();
  final out = Float32List(samples.length);
  for (var i = 0; i < samples.length; i++) {
    out[i] = samples[i] / 32768.0;
  }
  return out;
}

Future<MalinaliWhisperLiveSession> startMalinaliWhisperLiveSession({
  required WhisperOnnxPaths model,
  String lang = 'auto',
  bool translate = false,
}) async {
  return MalinaliWhisperLiveSession._(<int>[], model, lang, translate);
}

/// No-op: sherpa recognizers are freed after each decode.
Future<void> whisperReleaseModel() async {}
