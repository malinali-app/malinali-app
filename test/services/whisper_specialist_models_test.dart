import 'package:flutter_test/flutter_test.dart';
import 'package:languages_dart/languages_dart.dart';
import 'package:malinali/services/whisper_specialist_models.dart';

void main() {
  test('catalogue lists specialist packs with first-wave downloads', () {
    expect(kWhisperSpecialistPacks, hasLength(8));
    final fineTunes =
        kWhisperSpecialistPacks
            .where((p) => p.id.endsWith('-small') && p.isDownloadable)
            .toList();
    expect(fineTunes.map((p) => p.id), [
      'swahili-small',
      'yoruba-small',
      'wolof-small',
    ]);
    for (final pack in fineTunes) {
      expect(pack.onnxRepo?.repoId, contains('malinali-app/'));
      expect(pack.onnxRepo?.repoId, contains('-onnx'));
      expect(pack.translate, isFalse);
    }
  });

  test('gated and non-commercial packs stay unavailable', () {
    final blocked = kWhisperSpecialistPacks.where((p) => !p.isDownloadable);
    expect(blocked.map((p) => p.id), [
      'kinyarwanda-small',
      'dioula-tiny',
      'moore-small',
    ]);
    for (final pack in blocked) {
      expect(pack.unavailableReason, isNotEmpty);
      expect(pack.onnxRepo, isNull);
    }
  });

  test('yoruba and wolof have Marian outbound; swahili does not', () {
    expect(whisperSpecialistById('yoruba-small')!.hasMarianOutbound, isTrue);
    expect(whisperSpecialistById('swahili-small')!.hasMarianOutbound, isFalse);
    expect(whisperSpecialistById('wolof-small')!.hasMarianOutbound, isTrue);
  });

  test('languageForWhisperIso resolves known African languages', () {
    expect(languageIsoCode(languageForWhisperIso('yo')!), 'yo');
    expect(languageIsoCode(languageForWhisperIso('sw')!), 'sw');
    expect(languageIsoCode(languageForWhisperIso('rw')!), 'rw');
    expect(languageIsoCode(languageForWhisperIso('wo')!), 'wo');
    expect(languageIsoCode(languageForWhisperIso('dyu')!), 'dyu');
    expect(languageIsoCode(languageForWhisperIso('mos')!), 'mos');
    expect(languageForWhisperIso('xx'), isNull);
  });

  test('whisperSpecialistById returns null for unknown id', () {
    expect(whisperSpecialistById('nope'), isNull);
    expect(whisperSpecialistById('yoruba-small')!.whisperLang, 'yo');
    expect(whisperSpecialistById('wolof-small')!.whisperLang, 'en');
    expect(whisperSpecialistById('wolof-small')!.translate, isFalse);
  });

  test('english fast STT downloads the Kroko streaming zipformer', () {
    final en = whisperSpecialistById('icefall-en')!;
    expect(en.labelFr, 'Anglais (Kroko)');
    expect(en.upstreamRepo, 'Banafo/Kroko-ASR (CC-BY-SA)');
    expect(
      en.onnxRepo?.repoId,
      'csukuangfj/sherpa-onnx-streaming-zipformer-en-kroko-2025-08-06',
    );
    expect(en.onnxRepo?.files, [
      'encoder.onnx',
      'decoder.onnx',
      'tokens.txt',
      'joiner.onnx',
    ]);
    expect(en.onnxRepo?.modelType, 'transducer');
    expect(en.onnxRepo?.sherpaModelType, 'zipformer2');
  });

  test('wolof-small is the M9and2M fine-tune, not the parked dofbi pack', () {
    final wolof = whisperSpecialistById('wolof-small')!;
    expect(kShowWolofText, isTrue);
    expect(wolof.isDownloadable, isTrue);
    expect(wolof.onnxRepo?.repoId, 'malinali-app/whisper-small-wolof-onnx');
    expect(wolof.upstreamRepo, 'M9and2M/whisper-small-wolof');
    expect(wolof.dirName, 'wolof-small');
    expect(whisperSpecialistById('wolof-asr'), isNull);
  });
}

String languageIsoCode(Language language) =>
    language.localeIntl.locale.languageCode;
