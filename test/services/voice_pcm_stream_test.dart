import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:malinali/services/translation_model_service.dart';
import 'package:malinali/services/voice_pcm_stream.dart';
import 'package:malinali/services/voice_preferences.dart';
import 'package:malinali/services/voice_speech_resolver.dart';
import 'package:malinali/services/voice_turn_pipeline.dart';
import 'package:malinali/services/whisper_native.dart';
import 'package:malinali/services/whisper_specialist_models.dart';
import 'package:malinali/services/whisper_speech_service.dart';

class _FakeWhisper extends Fake implements WhisperSpeechService {
  int transcribeCalls = 0;

  @override
  Future<void> releaseParkedModel() async {}

  @override
  Future<String> transcribeWav(
    String audioPath, {
    void Function(int percent)? onProgress,
    String? language,
    bool? translate,
  }) async {
    transcribeCalls++;
    return 'file';
  }
}

class _FakeModelService extends Fake implements TranslationModelService {
  @override
  Future<bool> isModelDownloaded(TranslationModel model) async => true;
}

class _RecordingFeed implements VoicePcmFeed {
  int bytes = 0;
  final partials = <String>[];

  @override
  String get engine => 'whisper';

  @override
  Future<void> feed(Uint8List pcm16) async {
    bytes += pcm16.length;
  }

  @override
  Future<String?> latestPartial() async => 'salut';

  @override
  Future<String> finish() async => 'bonjour';
}

Uint8List _wav16k(Uint8List pcm) {
  final bytes = Uint8List(44 + pcm.length);
  final bd = ByteData.sublistView(bytes);
  bytes.setRange(0, 4, 'RIFF'.codeUnits);
  bd.setUint32(4, 36 + pcm.length, Endian.little);
  bytes.setRange(8, 12, 'WAVE'.codeUnits);
  bytes.setRange(12, 16, 'fmt '.codeUnits);
  bd.setUint32(16, 16, Endian.little);
  bd.setUint16(20, 1, Endian.little);
  bd.setUint16(22, 1, Endian.little);
  bd.setUint32(24, 16000, Endian.little);
  bd.setUint32(28, 32000, Endian.little);
  bd.setUint16(32, 2, Endian.little);
  bd.setUint16(34, 16, Endian.little);
  bytes.setRange(36, 40, 'data'.codeUnits);
  bd.setUint32(40, pcm.length, Endian.little);
  bytes.setRange(44, 44 + pcm.length, pcm);
  return bytes;
}

void main() {
  test('pcm16FromWavBytes returns the PCM payload', () {
    final pcm = Uint8List.fromList([1, 2, 3, 4]);
    expect(pcm16FromWavBytes(_wav16k(pcm)), pcm);
  });

  test('voiceStreamEngine follows vosk, whisper, and sherpa', () {
    expect(
      voiceStreamEngine(
        const VoiceSpeechPlan(
          strategy: VoiceSpeechStrategy.vosk,
          whisperSize: VoiceWhisperSize.compact,
          whisperLanguage: 'fr',
          sourceIso: 'fr',
        ),
      ),
      'vosk',
    );
    expect(
      voiceStreamEngine(
        const VoiceSpeechPlan(
          strategy: VoiceSpeechStrategy.genericTranslate,
          whisperSize: VoiceWhisperSize.compact,
          whisperLanguage: 'fr',
          sourceIso: 'fr',
        ),
      ),
      'whisper',
    );
    final icefall = whisperSpecialistById('icefall-fr');
    expect(icefall, isNotNull);
    expect(
      voiceStreamEngine(
        VoiceSpeechPlan(
          strategy: VoiceSpeechStrategy.directTranslate,
          whisperSize: VoiceWhisperSize.compact,
          whisperLanguage: 'fr',
          sourceIso: 'fr',
          specialist: icefall,
        ),
      ),
      'sherpa-icefall',
    );
  });

  test('streamPcm feeds PCM and does not transcribe the whole file', () async {
    final whisper = _FakeWhisper();
    final feed = _RecordingFeed();
    final pipeline = VoiceTurnPipeline(
      whisper: whisper,
      modelService: _FakeModelService(),
      openPcmFeed: (_) async => feed,
    );
    const plan = VoiceSpeechPlan(
      strategy: VoiceSpeechStrategy.genericTranslate,
      whisperSize: VoiceWhisperSize.compact,
      whisperLanguage: 'fr',
      sourceIso: 'fr',
    );
    final partials = <String>[];
    final text = await pipeline.streamPcm(
      pcm16: Uint8List(9000),
      plan: plan,
      onPartial: partials.add,
    );

    expect(text, 'bonjour');
    expect(feed.bytes, 9000);
    expect(partials, ['salut', 'salut']);
    expect(whisper.transcribeCalls, 0);
  });

  test('finish keeps the last partial when the recognizer returns nothing', () async {
    final session = _ScriptedSession('');
    final feed = SherpaPcmFeed(session, engine: 'sherpa-icefall');
    session.emit('bonjour');
    await Future<void>.delayed(Duration.zero);
    expect(await feed.finish(), 'bonjour');
    expect(preferSpokenTranscript('', 'bonjour'), 'bonjour');
    expect(preferSpokenTranscript('salut', 'bonjour'), 'salut');
  });
}

class _ScriptedSession implements SherpaLiveSession {
  _ScriptedSession(this.finalText);

  String finalText;
  final StreamController<String> _partials = StreamController<String>.broadcast();

  @override
  Stream<String> get partials => _partials.stream;

  void emit(String text) => _partials.add(text);

  @override
  void feed(Uint8List pcm16Bytes) {}

  @override
  Future<String> stop() async => finalText;

  @override
  Future<void> dispose() async {}

  @override
  void setSink(IOSink? sink) {}
}
