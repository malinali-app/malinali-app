import 'package:flutter_test/flutter_test.dart';
import 'package:malinali/services/whisper_native.dart';

void main() {
  test('pcm16 little-endian samples become floats', () {
    final floats = pcm16LeToFloat32([0x00, 0x40, 0x00, 0x00, 0x00, 0x80]);
    expect(floats, hasLength(3));
    expect(floats[0], closeTo(0.5, 1e-4));
    expect(floats[1], 0);
    expect(floats[2], closeTo(-1, 1e-4));
  });
}
