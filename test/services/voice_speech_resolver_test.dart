import 'package:flutter_test/flutter_test.dart';
import 'package:malinali/services/supported_languages.dart';
import 'package:malinali/services/translation_model_service.dart';
import 'package:malinali/services/voice_preferences.dart';
import 'package:malinali/services/voice_speech_resolver.dart';

void main() {
  const resolver = VoiceSpeechResolver();

  test('defaults are French → Wolof with quality Whisper size', () {
    expect(VoicePreferences.defaults.sourceIso, 'fr');
    expect(VoicePreferences.defaults.targetIso, 'wo');
    expect(VoicePreferences.defaults.whisperSize, VoiceWhisperSize.quality);
  });

  test('legacy Wolof→French prefs migrate to French→Wolof', () {
    final prefs = VoicePreferences.fromJson({
      'sourceIso': 'wo',
      'targetIso': 'fr',
      'whisperSize': 'quality',
    });
    expect(prefs.sourceIso, 'fr');
    expect(prefs.targetIso, 'wo');
  });

  test('Wolof to French cascade still resolves if forced (not offered in UI)', () {
    final plan = resolver.resolve(
      const VoicePreferences(
        sourceIso: 'wo',
        targetIso: 'fr',
        whisperSize: VoiceWhisperSize.quality,
      ),
    );
    expect(plan.strategy, VoiceSpeechStrategy.transcribeThenMarianToEnglish);
    expect(plan.specialist?.id, 'wolof-small');
    expect(plan.sourceToEnglish?.modelId, 'malinali-app/traduction-wolof-en-onnx');
    expect(plan.englishToTarget?.modelId, 'malinali-app/opus-mt-en-fr-onnx');
  });

  test('Yoruba to French uses the direct model and the Yoruba fine-tune', () {
    final plan = resolver.resolve(
      const VoicePreferences(
        sourceIso: 'yo',
        targetIso: 'fr',
        whisperSize: VoiceWhisperSize.quality,
      ),
    );
    expect(plan.strategy, VoiceSpeechStrategy.directTranslate);
    expect(plan.specialist?.id, 'yoruba-small');
    expect(plan.whisperLanguage, 'yo');
    expect(plan.sourceToEnglish?.modelId, 'malinali-app/opus-mt-yo-fr');
    expect(plan.englishToTarget, isNull);
    expect(plan.translateToEnglish, isFalse);
  });

  test('Swahili resolves to generic translate (no sw→en Marian)', () {
    final plan = resolver.resolve(
      const VoicePreferences(
        sourceIso: 'sw',
        targetIso: 'fr',
        whisperSize: VoiceWhisperSize.compact,
      ),
    );
    expect(plan.strategy, VoiceSpeechStrategy.genericTranslate);
    expect(plan.specialist, isNull);
    expect(plan.whisperLanguage, 'sw');
    expect(plan.genericModel.modelName, 'tiny');
  });

  test('Wolof to English transcribes then uses the direct wo→en model', () {
    final plan = resolver.resolve(
      const VoicePreferences(
        sourceIso: 'wo',
        targetIso: 'en',
        whisperSize: VoiceWhisperSize.quality,
      ),
    );
    expect(plan.strategy, VoiceSpeechStrategy.directTranslate);
    expect(plan.specialist?.id, 'wolof-small');
    expect(plan.whisperLanguage, 'en');
    expect(plan.sourceToEnglish?.modelId, 'malinali-app/traduction-wolof-en-onnx');
    expect(plan.englishToTarget, isNull);
    expect(plan.marianDownloads.map((m) => m.modelId), [
      'malinali-app/traduction-wolof-en-onnx',
    ]);
  });

  test('Kinyarwanda fine-tune is gated so cascade is not offered', () {
    final plan = resolver.resolve(
      const VoicePreferences(
        sourceIso: 'rw',
        targetIso: 'fr',
        whisperSize: VoiceWhisperSize.quality,
      ),
    );
    // No downloadable Whisper pack. A direct rw→fr Marian model still applies.
    expect(plan.strategy, VoiceSpeechStrategy.directTranslate);
    expect(plan.specialist, isNull);
    expect(plan.sourceToEnglish?.modelId, 'malinali-app/opus-mt-rw-fr');
  });

  test('spoken language list includes English, French, and Fon', () {
    final packs = voiceSpokenLanguagePacks();
    expect(packs.map((p) => p.id), ['generic-en', 'generic-fr', 'fon-small']);
  });

  test('Fon → French uses frenchOutputFineTune with fr prompt', () {
    final plan = resolver.resolve(
      const VoicePreferences(
        sourceIso: 'fon',
        targetIso: 'fr',
        whisperSize: VoiceWhisperSize.quality,
      ),
    );
    expect(plan.strategy, VoiceSpeechStrategy.frenchOutputFineTune);
    expect(plan.specialist?.id, 'fon-small');
    expect(plan.whisperLanguage, 'fr');
    expect(plan.translateToEnglish, isFalse);
    expect(plan.specialist?.emitsFrench, isTrue);
    expect(plan.marianDownloads, isEmpty);
  });

  test('Fon targets only French', () {
    final targets = getAvailableTargetLanguages(sourceIso: 'fon');
    expect(targets.map((t) => t.iso), ['fr']);
  });

  test('Fon prefs are not migrated away', () {
    final prefs = VoicePreferences.fromJson({
      'sourceIso': 'fon',
      'targetIso': 'fr',
      'whisperSize': 'quality',
    });
    expect(prefs.sourceIso, 'fon');
    expect(prefs.targetIso, 'fr');
  });

  test('voice English targets are sorted alphabetically', () {
    final targets = voiceEnglishTargetModels();
    final names = targets
        .map(
          (m) => m.targetLang.name.isEmpty
              ? m.targetLang.nameEn
              : m.targetLang.name,
        )
        .map((n) => n.toLowerCase())
        .toList();
    expect(names, List<String>.from(names)..sort());
    expect(
      targets.any((m) => m.modelId == 'malinali-app/traduction-en-wolof-onnx'),
      isTrue,
    );
  });

  test('French to Wolof is Whisper translate then LocaleNLP eng_wolof', () {
    final plan = resolver.resolve(
      const VoicePreferences(
        sourceIso: 'fr',
        targetIso: 'wo',
        whisperSize: VoiceWhisperSize.quality,
      ),
    );
    expect(plan.strategy, VoiceSpeechStrategy.genericTranslate);
    expect(plan.specialist, isNull);
    expect(plan.whisperLanguage, 'fr');
    expect(plan.translateToEnglish, isTrue);
    expect(plan.sourceToEnglish, isNull);
    expect(plan.englishToTarget?.modelId, 'malinali-app/traduction-en-wolof-onnx');
    expect(
      plan.englishToTarget?.sourcePrefix,
      TranslationModelService.kEngWolofSourcePrefix,
    );
    expect(plan.marianDownloads.map((m) => m.modelId), [
      'malinali-app/traduction-en-wolof-onnx',
    ]);
  });

  test('Wolof target uses English→Wolof ONNX fine-tune', () {
    final plan = resolver.resolve(
      const VoicePreferences(
        sourceIso: 'yo',
        targetIso: 'wo',
        whisperSize: VoiceWhisperSize.quality,
      ),
    );
    expect(plan.englishToTarget?.modelId, 'malinali-app/traduction-en-wolof-onnx');
    expect(
      plan.englishToTarget?.sourcePrefix,
      TranslationModelService.kEngWolofSourcePrefix,
    );
  });
}
