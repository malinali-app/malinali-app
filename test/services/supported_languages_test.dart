import 'package:flutter_test/flutter_test.dart';
import 'package:malinali/services/supported_languages.dart';

void main() {
  group('getAvailableTargetLanguages', () {
    test('Wolof source only targets French and English', () {
      final targets = getAvailableTargetLanguages(sourceIso: 'wo');
      final isos = targets.map((t) => t.iso).toList();
      expect(isos, containsAll(['fr', 'en']));
      expect(isos.length, 2);
    });

    test('Other low-resource source only targets French and English', () {
      final targets = getAvailableTargetLanguages(sourceIso: 'sw');
      final isos = targets.map((t) => t.iso).toList();
      expect(isos, containsAll(['fr', 'en']));
      expect(isos.length, 2);
    });

    test('French source targets English, Wolof, and African languages with BLEU >= 30', () {
      final targets = getAvailableTargetLanguages(sourceIso: 'fr', minBleuScore: 30.0);
      final isos = targets.map((t) => t.iso).toList();

      expect(isos, contains('en'));
      expect(isos, contains('wo'));
      expect(isos, contains('ln')); // Lingala BLEU 30.5
      expect(isos, isNot(contains('ha'))); // Hausa BLEU 24.4 (< 30)
      expect(isos, isNot(contains('yo'))); // Yoruba BLEU 25.9 (< 30)
      expect(isos, isNot(contains('ig'))); // Igbo BLEU 29.0 (< 30)
      expect(isos, isNot(contains('es'))); // No European languages other than en/fr
    });

    test('English source targets French, Wolof, and African languages with BLEU >= 30', () {
      final targets = getAvailableTargetLanguages(sourceIso: 'en', minBleuScore: 30.0);
      final isos = targets.map((t) => t.iso).toList();

      expect(isos, contains('fr'));
      expect(isos, contains('wo'));
      expect(isos, contains('ha')); // Hausa BLEU 34.1
      expect(isos, contains('ig')); // Igbo BLEU 39.5
      expect(isos, contains('ln')); // Lingala BLEU 36.7
      expect(isos, contains('rw')); // Kinyarwanda BLEU 33.3
      expect(isos, contains('lg')); // Ganda BLEU 30.4
      expect(isos, contains('sn')); // Shona BLEU 38.0
      expect(isos, contains('ny')); // Nyanja BLEU 31.4
      expect(isos, contains('tw')); // Twi BLEU 38.2
      expect(isos, contains('ee')); // Ewe BLEU 38.2

      // Low BLEU African languages excluded:
      expect(isos, isNot(contains('rn'))); // Rundi BLEU 10.4 (< 30)
      expect(isos, isNot(contains('sw'))); // Swahili BLEU 24.2 (< 30)
      expect(isos, isNot(contains('ti'))); // Tigrinya BLEU 25.3 (< 30)
    });

    test('targets are sorted alphabetically by display name', () {
      final targets = getAvailableTargetLanguages(sourceIso: 'en');
      final names = targets.map((t) => t.name.toLowerCase()).toList();
      expect(names, List<String>.from(names)..sort());
    });

    test('Subtitles have English names and BLEU hints', () {
      final targets = getAvailableTargetLanguages(sourceIso: 'fr');
      for (final t in targets) {
        expect(t.nameEn.isNotEmpty, isTrue);
      }
      final wolof = targets.firstWhere((t) => t.iso == 'wo');
      expect(wolof.nameEn, 'Wolof');
      expect(wolof.qualityHint, contains('BLEU'));
    });
  });
}
