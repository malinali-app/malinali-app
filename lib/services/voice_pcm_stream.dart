import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:malinali/services/audio_decode_service.dart';
import 'package:malinali/services/audio_transcription_service.dart';
import 'package:malinali/services/speech_recognition_service.dart';
import 'package:malinali/services/voice_speech_resolver.dart';
import 'package:malinali/services/wav_pcm_info.dart';
import 'package:malinali/services/whisper_native.dart';

/// 16 kHz mono PCM produced from a shared voice note.
class DecodedSharedAudio {
  const DecodedSharedAudio({required this.wavPath, required this.pcm16});

  final String wavPath;
  final Uint8List pcm16;
}

/// PCM pushed into the recognizer a voice plan selects.
abstract class VoicePcmFeed {
  String get engine;

  Future<void> feed(Uint8List pcm16);

  /// Latest text after [feed], when the engine emits partials.
  Future<String?> latestPartial();

  Future<String> finish();
}

/// `vosk`, `whisper`, or `sherpa-icefall` for [plan].
String voiceStreamEngine(VoiceSpeechPlan plan) {
  if (plan.strategy == VoiceSpeechStrategy.vosk) return 'vosk';
  final specialist = plan.specialist;
  if (specialist != null &&
      (specialist.id.contains('icefall') ||
          specialist.onnxRepo?.modelType == 'transducer')) {
    return 'sherpa-icefall';
  }
  return 'whisper';
}

/// Vosk recognizer fed with PCM chunks, same partials as the mic stream.
class VoskPcmFeed implements VoicePcmFeed {
  VoskPcmFeed(this._speech);

  final SpeechRecognitionService _speech;
  final List<String> _segments = [];
  String _partial = '';

  @override
  String get engine => 'vosk';

  @override
  Future<void> feed(Uint8List pcm16) async {
    final isFinal = await _speech.acceptWaveformBytes(pcm16);
    if (isFinal) {
      final text = AudioTranscriptionService.extractTextFromVoskJson(
        await _speech.getResultJson(),
      );
      if (text.isNotEmpty) _segments.add(text);
    }
    _partial = AudioTranscriptionService.extractPartialFromVoskJson(
      await _speech.getPartialResultJson(),
    );
  }

  @override
  Future<String?> latestPartial() async {
    final preview = [
      ..._segments,
      if (_partial.isNotEmpty) _partial,
    ].join(' ').trim();
    return preview.isEmpty ? null : preview;
  }

  @override
  Future<String> finish() async {
    final tail = AudioTranscriptionService.extractTextFromVoskJson(
      await _speech.getFinalResultJson(),
    );
    if (tail.isNotEmpty) _segments.add(tail);
    _partial = '';
    return _segments.join(' ').trim();
  }
}

/// Whisper or Sherpa transducer session. Both accept PCM via [feed].
class SherpaPcmFeed implements VoicePcmFeed {
  SherpaPcmFeed(this._session, {required this.engine}) {
    _sub = _session.partials.listen((text) {
      final trimmed = text.trim();
      if (trimmed.isNotEmpty) _partial = trimmed;
    });
  }

  final SherpaLiveSession _session;
  StreamSubscription<String>? _sub;
  String? _partial;

  @override
  final String engine;

  @override
  Future<void> feed(Uint8List pcm16) async {
    _session.feed(pcm16);
  }

  @override
  Future<String?> latestPartial() async => _partial;

  @override
  Future<String> finish() async {
    final text = await _session.stop();
    await _sub?.cancel();
    _sub = null;
    return preferSpokenTranscript(text, _partial);
  }
}

/// PCM payload of a 16 kHz mono 16-bit WAV.
Uint8List pcm16FromWavBytes(Uint8List bytes) {
  final info = WavPcmInfo.parse(bytes);
  if (info.audioFormat != 1 ||
      info.numChannels != 1 ||
      info.bitsPerSample != 16 ||
      info.sampleRate != 16000) {
    throw FormatException(
      'Attendu PCM 16 kHz mono 16-bit '
      '(${info.sampleRate} Hz, ${info.numChannels} ch, ${info.bitsPerSample} bit)',
    );
  }
  final end = (info.dataOffset + info.dataByteCount).clamp(0, bytes.length);
  if (end <= info.dataOffset) {
    throw const FormatException('WAV sans échantillons');
  }
  return Uint8List.sublistView(bytes, info.dataOffset, end);
}

/// Decode a shared note (`.opus` and the rest) to 16 kHz mono PCM.
Future<DecodedSharedAudio> decodeSharedVoicePcm(
  String path, {
  AudioDecodeService? decodeService,
}) async {
  final decode = decodeService ?? AudioDecodeService();
  final wav = await decode.decodeToWav16kMono(File(path));
  final pcm = pcm16FromWavBytes(await wav.readAsBytes());
  return DecodedSharedAudio(wavPath: wav.path, pcm16: pcm);
}
