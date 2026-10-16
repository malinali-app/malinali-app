import 'package:flutter_test/flutter_test.dart';
import 'package:malinali/services/voice_preferences.dart';
import 'package:malinali/services/voice_speech_resolver.dart';

void main() {
  group('VoiceSpeechResolver (Sherpa Icefall)', () {
    const resolver = VoiceSpeechResolver();

    test('spoken French uses Whisper translate and skips the fr→en model', () {
      final prefs = VoicePreferences.defaults.copyWith(
        sourceIso: 'fr',
        targetIso: 'en',
        whisperSize: VoiceWhisperSize.compact,
        useFastSttForEnFr: true,
      );
      final plan = resolver.resolve(prefs);
      expect(plan.specialist, isNull);
      expect(plan.genericModel.modelName, 'tiny');
      expect(plan.whisperLanguage, 'fr');
      expect(plan.translateToEnglish, isTrue);
      expect(plan.strategy, VoiceSpeechStrategy.genericTranslate);
      expect(plan.sourceToEnglish, isNull);
      expect(plan.englishToTarget, isNull);
      expect(plan.marianDownloads, isEmpty);
    });

    test('English to French stays on Whisper even when fast STT is enabled', () {
      final prefs = VoicePreferences.defaults.copyWith(
        sourceIso: 'en',
        targetIso: 'fr',
        useFastSttForEnFr: true,
      );
      final plan = resolver.resolve(prefs);
      expect(plan.specialist, isNull);
      expect(plan.whisperLanguage, 'en');
      expect(plan.translateToEnglish, isFalse);
      expect(plan.strategy, VoiceSpeechStrategy.directTranslate);
      expect(plan.sourceToEnglish?.modelId, 'malinali-app/opus-mt-en-fr-onnx');
    });

    test('French to Wolof is Whisper English then English→Wolof only', () {
      final prefs = VoicePreferences.defaults.copyWith(
        whisperSize: VoiceWhisperSize.quality,
        useFastSttForEnFr: true,
      );
      final plan = resolver.resolve(prefs);
      expect(plan.specialist, isNull);
      expect(plan.genericModel.modelName, 'small');
      expect(plan.whisperLanguage, 'fr');
      expect(plan.translateToEnglish, isTrue);
      expect(plan.strategy, VoiceSpeechStrategy.genericTranslate);
      expect(plan.sourceToEnglish, isNull);
      expect(plan.englishToTarget?.modelId, 'malinali-app/traduction-en-wolof-onnx');
    });

    test('English to Wolof still uses Kroko when fast STT is enabled', () {
      final prefs = VoicePreferences.defaults.copyWith(
        sourceIso: 'en',
        targetIso: 'wo',
        useFastSttForEnFr: true,
      );
      final plan = resolver.resolve(prefs);
      expect(plan.specialist?.id, 'icefall-en');
      expect(plan.strategy, VoiceSpeechStrategy.genericTranslate);
      expect(plan.englishToTarget?.modelId, 'malinali-app/traduction-en-wolof-onnx');
    });

    test('spoken French still translates inside Whisper when fast STT is off', () {
      final prefs = VoicePreferences.defaults.copyWith(
        sourceIso: 'fr',
        targetIso: 'en',
        useFastSttForEnFr: false,
      );
      final plan = resolver.resolve(prefs);
      expect(plan.specialist, isNull);
      expect(plan.translateToEnglish, isTrue);
      expect(plan.strategy, VoiceSpeechStrategy.genericTranslate);
      expect(plan.marianDownloads, isEmpty);
    });
  });
}
