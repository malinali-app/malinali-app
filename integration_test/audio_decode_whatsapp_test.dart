import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:malinali/services/audio_decode_service.dart';
import 'package:malinali/services/wav_pcm_info.dart';
import 'package:path/path.dart' as p;

/// Real FFmpegKit decode of a WhatsApp voice note (.opus).
///
/// Run on a device/desktop embedding (plugin required):
///   flutter test integration_test/audio_decode_whatsapp_test.dart -d windows
///   flutter test integration_test/audio_decode_whatsapp_test.dart -d android
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('decodes WhatsApp PTT opus to 16 kHz mono PCM WAV', () async {
    final fixture = _resolveFixture();
    expect(
      await fixture.exists(),
      isTrue,
      reason: 'Missing fixture at ${fixture.path}',
    );
    expect(await fixture.length(), greaterThan(1000));

    final outDir =
        await Directory.systemTemp.createTemp('malinali_opus_decode_');
    addTearDown(() async {
      if (await outDir.exists()) {
        await outDir.delete(recursive: true);
      }
    });

    final service = AudioDecodeService();
    final wav = await service.decodeToWav16kMono(
      fixture,
      outputDirectory: outDir,
    );

    expect(await wav.exists(), isTrue);
    final bytes = await wav.readAsBytes();
    expect(bytes.length, greaterThan(44));

    final info = WavPcmInfo.parse(bytes);
    expect(info.audioFormat, 1, reason: 'PCM');
    expect(info.numChannels, 1);
    expect(info.sampleRate, 16000);
    expect(info.bitsPerSample, 16);
    expect(info.dataByteCount, greaterThan(0));
  });
}

File _resolveFixture() {
  final fromCwd = File(
    p.join('test', 'fixtures', 'audio', 'PTT-20260928-WA0003.opus'),
  );
  if (fromCwd.existsSync()) return fromCwd;

  return File(
    p.normalize(
      p.join(
        p.dirname(Platform.script.toFilePath()),
        '..',
        'test',
        'fixtures',
        'audio',
        'PTT-20260928-WA0003.opus',
      ),
    ),
  );
}
