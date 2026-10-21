import 'package:flutter_test/flutter_test.dart';
import 'package:malinali/services/wolof_spanish_phonetics.dart';

void main() {
  test('maps typical Wolof letters to Spanish phonetics', () {
    expect(wolofToSpanishPhonetics('bëgg'), 'beugu');
    expect(wolofToSpanishPhonetics('xarit'), 'jarit');
    expect(wolofToSpanishPhonetics('ñaari'), 'ñaari');
    expect(wolofToSpanishPhonetics('ceeb'), 'cheeb');
    expect(wolofToSpanishPhonetics('jëf'), 'dieuf');
    expect(wolofToSpanishPhonetics('suñu'), 'suñu');
    expect(wolofToSpanishPhonetics('ŋaar'), 'gaar');
  });

  test('does not rewrite letters produced by earlier replacements', () {
    // Wolof x → Spanish j must not become di.
    expect(wolofToSpanishPhonetics('xarit'), 'jarit');
    // Single g / ŋ→g must not become gu.
    expect(wolofToSpanishPhonetics('góor'), 'góor');
    expect(wolofToSpanishPhonetics('ŋaar'), 'gaar');
  });
}
