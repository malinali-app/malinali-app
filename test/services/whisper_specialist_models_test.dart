import 'package:flutter_test/flutter_test.dart';
import 'package:languages_dart/languages_dart.dart';
import 'package:malinali/services/whisper_specialist_models.dart';

void main() {
  test('catalogue lists six packs with first-wave downloads', () {
    expect(kWhisperSpecialistPacks, hasLength(6));
    final downloadable =
        kWhisperSpecialistPacks.where((p) => p.isDownloadable).toList();
    expect(downloadable.map((p) => p.id), [
      'swahili-small',
      'yoruba-small',
      'wolof-small',
    ]);
    for (final pack in downloadable) {
      expect(pack.ggmlUrl, contains('malinali-app/'));
      expect(pack.ggmlUrl, endsWith('ggml-model-q8_0.bin'));
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
      expect(pack.ggmlUrl, isNull);
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

  test('wolof-small is the M9and2M fine-tune, not the parked dofbi pack', () {
    final wolof = whisperSpecialistById('wolof-small')!;
    expect(kShowWolofText, isTrue);
    expect(wolof.isDownloadable, isTrue);
    expect(wolof.ggmlUrl, contains('whisper-small-wolof-ggml'));
    expect(wolof.ggmlUrl, endsWith('ggml-model-q8_0.bin'));
    expect(wolof.upstreamRepo, 'M9and2M/whisper-small-wolof');
    expect(wolof.fileName, 'wolof-small.bin');
    expect(whisperSpecialistById('wolof-asr'), isNull);
  });
}

String languageIsoCode(Language language) =>
    language.localeIntl.locale.languageCode;
