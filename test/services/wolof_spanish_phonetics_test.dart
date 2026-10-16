import 'package:flutter_test/flutter_test.dart';
import 'package:malinali/services/wolof_spanish_phonetics.dart';

void main() {
  test('maps typical Wolof letters to Spanish phonetics', () {
    expect(wolofToSpanishPhonetics('bëgg'), 'begg');
    expect(wolofToSpanishPhonetics('xarit'), 'jarit');
    expect(wolofToSpanishPhonetics('ñaari'), 'ñaari');
    expect(wolofToSpanishPhonetics('ceeb'), 'cheeb');
    expect(wolofToSpanishPhonetics('jëf'), 'yef');
    expect(wolofToSpanishPhonetics('suñu'), 'suñu');
    expect(wolofToSpanishPhonetics('ŋaar'), 'gaar');
  });
}
