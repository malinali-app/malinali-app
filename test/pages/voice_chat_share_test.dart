import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malinali/pages/voice_chat_page.dart';
import 'package:malinali/pages/vosk_transcription_page.dart';
import 'package:malinali/services/malinali_audio_open_intent.dart';
import 'package:malinali/services/translation_model_service.dart';
import 'package:malinali/services/tts_service.dart';
import 'package:malinali/services/voice_pcm_stream.dart';
import 'package:malinali/services/voice_preferences.dart';
import 'package:malinali/services/voice_turn_pipeline.dart';
import 'package:malinali/services/whisper_speech_service.dart';
import 'package:malinali/services/whisper_specialist_models.dart';

class _MemoryStore extends VoicePreferencesStore {
  VoicePreferences? saved;

  @override
  Future<VoicePreferences?> load() async => saved;

  @override
  Future<void> save(VoicePreferences prefs) async {
    saved = prefs;
  }
}

class _FakeWhisper extends Fake implements WhisperSpeechService {
  int transcribeCalls = 0;

  @override
  Future<bool> isGenericDownloaded(WhisperModel model) async => false;

  @override
  Future<bool> isSpecialistDownloaded(WhisperSpecialistPack pack) async =>
      false;

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

class _FakeModels extends Fake implements TranslationModelService {
  _FakeModels(this.readyId);

  final String readyId;

  @override
  Future<bool> isModelDownloaded(TranslationModel model) async =>
      model.modelId == readyId;
}

class _FakeTts extends Fake implements TtsService {
  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<void> init() async {}

  @override
  Future<void> stop() async {}

  @override
  bool isLanguageWellSupported(String iso) => false;
}

class _RecordingFeed implements VoicePcmFeed {
  int bytes = 0;

  @override
  String get engine => 'whisper';

  @override
  Future<void> feed(Uint8List pcm16) async {
    bytes += pcm16.length;
  }

  @override
  Future<String?> latestPartial() async => 'bonjour';

  @override
  Future<String> finish() async => 'bonjour';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    MalinaliAudioOpenIntent.instance.resetForTest();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') return '.';
        return null;
      },
    );
    for (final name in [
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.isEnabled',
    ]) {
      messenger.setMockMessageHandler(name, (_) async => null);
    }
  });

  tearDown(() {
    MalinaliAudioOpenIntent.instance.resetForTest();
  });

  testWidgets('shared note confirms a local pair and streams PCM', (tester) async {
    final frEn = curatedMarianForPair(sourceIso: 'fr', targetIso: 'en');
    expect(frEn, isNotNull);
    final whisper = _FakeWhisper();
    final feed = _RecordingFeed();
    final pipeline = VoiceTurnPipeline(
      whisper: whisper,
      modelService: _FakeModels(frEn!.modelId),
      openPcmFeed: (_) async => feed,
      translate: (model, text) async => 'hello there',
    );
    const prefs = VoicePreferences(
      sourceIso: 'fr',
      targetIso: 'en',
      whisperSize: VoiceWhisperSize.quality,
      useFastSttForEnFr: false,
      targetLanguages: ['en'],
    );
    MalinaliAudioOpenIntent.instance.setPendingPath('/notes/whatsapp.opus');

    await tester.pumpWidget(
      MaterialApp(
        home: VoiceChatPage(
          initialPrefs: prefs,
          prefsStore: _MemoryStore(),
          pipeline: pipeline,
          whisperService: whisper,
          modelService: _FakeModels(frEn.modelId),
          ttsService: _FakeTts(),
          decodeSharedAudio: (_) async => DecodedSharedAudio(
            wavPath: 'note.wav',
            pcm16: Uint8List(4),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(VoskTranscriptionPage), findsNothing);
    expect(find.text('Langues de cette note'), findsOneWidget);

    await tester.tap(find.text('Traduire'));
    await tester.pumpAndSettle();

    expect(find.byType(VoskTranscriptionPage), findsNothing);
    expect(feed.bytes, 4);
    expect(whisper.transcribeCalls, 0);
    expect(find.text('hello there'), findsOneWidget);
    expect(find.text('bonjour'), findsWidgets);
  });
}
