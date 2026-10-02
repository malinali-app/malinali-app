/// Local smoke test: Helsinki EN→HA Candle pack in malinali-app cache.
///
///   flutter test test/opus_mt_en_ha_local_test.dart
library;

import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marian_flutter/marian_flutter.dart';
import 'package:path/path.dart' as p;

void main() {
  test('local opus-mt-en-ha translates Hello', () async {
    final modelDir = Directory(
      p.join(
        Directory.current.path,
        '.cache',
        'african_candle',
        'opus-mt-en-ha',
      ),
    );
    for (final name in const [
      'config.json',
      'model.safetensors',
      'tokenizer-enc.json',
      'tokenizer-dec.json',
    ]) {
      final f = File(p.join(modelDir.path, name));
      expect(f.existsSync(), isTrue, reason: 'missing ${f.path}');
    }

    final lib = _hostLibrary();
    expect(lib.existsSync(), isTrue, reason: 'missing ${lib.path}');

    await MarianService.initRust(
      externalLibrary: ExternalLibrary.open(lib.path),
    );
    addTearDown(RustLib.dispose);

    final marian = await MarianService.loadFromDirectory(modelDir.path);
    expect(await marian.isReady, isTrue);

    final hello = await marian.translate('Hello');
    // ignore: avoid_print
    print('TRANSLATE Hello => [$hello]');
    // Upstream Helsinki OPUS en-ha (JW300) itself emits garbage for bare "Hello".
    expect(hello.trim(), isNotEmpty);

    final thanks = await marian.translate('Thank you');
    // ignore: avoid_print
    print('TRANSLATE Thank you => [$thanks]');
    expect(thanks.toLowerCase(), contains('gode'));
  }, timeout: const Timeout(Duration(minutes: 3)));
}

File _hostLibrary() {
  final release = p.join(
    Directory.current.path,
    '..',
    'marian_flutter',
    'rust',
    'target',
    'release',
  );
  if (Platform.isWindows) {
    return File(p.join(release, 'marian_flutter.dll'));
  }
  if (Platform.isMacOS) {
    return File(p.join(release, 'libmarian_flutter.dylib'));
  }
  return File(p.join(release, 'libmarian_flutter.so'));
}
