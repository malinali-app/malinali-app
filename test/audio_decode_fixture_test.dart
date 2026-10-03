import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:malinali/services/wav_pcm_info.dart';
import 'package:path/path.dart' as p;

void main() {
  test('WhatsApp opus fixture is present and non-trivial', () async {
    final fixture = File(
      p.join('test', 'fixtures', 'audio', 'PTT-20260928-WA0003.opus'),
    );
    expect(await fixture.exists(), isTrue);
    expect(await fixture.length(), greaterThan(10 * 1024));
  });

  test('WavPcmInfo parses a minimal synthetic PCM WAV', () {
    final wav = _minimalPcmWav(
      sampleRate: 16000,
      numChannels: 1,
      bitsPerSample: 16,
      pcmBytes: Uint8List(320),
    );
    final info = WavPcmInfo.parse(wav);
    expect(info.audioFormat, 1);
    expect(info.numChannels, 1);
    expect(info.sampleRate, 16000);
    expect(info.bitsPerSample, 16);
    expect(info.dataByteCount, 320);
    expect(info.dataOffset, 44);
  });
}

Uint8List _minimalPcmWav({
  required int sampleRate,
  required int numChannels,
  required int bitsPerSample,
  required Uint8List pcmBytes,
}) {
  final byteRate = sampleRate * numChannels * bitsPerSample ~/ 8;
  final blockAlign = numChannels * bitsPerSample ~/ 8;
  final dataSize = pcmBytes.length;
  final riffSize = 36 + dataSize;
  final out = BytesBuilder();
  void ascii(String s) => out.add(s.codeUnits);
  void u16(int v) {
    final b = ByteData(2)..setUint16(0, v, Endian.little);
    out.add(b.buffer.asUint8List());
  }

  void u32(int v) {
    final b = ByteData(4)..setUint32(0, v, Endian.little);
    out.add(b.buffer.asUint8List());
  }

  ascii('RIFF');
  u32(riffSize);
  ascii('WAVE');
  ascii('fmt ');
  u32(16);
  u16(1);
  u16(numChannels);
  u32(sampleRate);
  u32(byteRate);
  u16(blockAlign);
  u16(bitsPerSample);
  ascii('data');
  u32(dataSize);
  out.add(pcmBytes);
  return out.toBytes();
}
