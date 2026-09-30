import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:malinali/services/audio_decode_service.dart';
import 'package:malinali/services/audio_transcription_service.dart';
import 'package:path/path.dart' as p;

/// Minimal PCM16 mono WAV builder for unit tests.
Uint8List buildPcm16MonoWav({
  required int sampleRate,
  required int sampleCount,
}) {
  final dataSize = sampleCount * 2;
  final bytes = BytesBuilder();
  void writeString(String s) => bytes.add(s.codeUnits);
  void writeUint16(int v) {
    bytes.addByte(v & 0xff);
    bytes.addByte((v >> 8) & 0xff);
  }

  void writeUint32(int v) {
    bytes.addByte(v & 0xff);
    bytes.addByte((v >> 8) & 0xff);
    bytes.addByte((v >> 16) & 0xff);
    bytes.addByte((v >> 24) & 0xff);
  }

  writeString('RIFF');
  writeUint32(36 + dataSize);
  writeString('WAVE');
  writeString('fmt ');
  writeUint32(16);
  writeUint16(1); // PCM
  writeUint16(1); // mono
  writeUint32(sampleRate);
  writeUint32(sampleRate * 2); // byte rate
  writeUint16(2); // block align
  writeUint16(16); // bits
  writeString('data');
  writeUint32(dataSize);
  for (var i = 0; i < sampleCount; i++) {
    writeUint16(0);
  }
  return bytes.toBytes();
}

class FakeWaveformTranscriber implements WaveformTranscriber {
  FakeWaveformTranscriber({
    this.finalText = 'bonjour le monde',
    this.emitFinalOnChunk = false,
  });

  final String finalText;
  final bool emitFinalOnChunk;
  int acceptCalls = 0;
  int resetCalls = 0;
  bool ready = false;

  @override
  Future<void> ensureReady() async {
    ready = true;
  }

  @override
  Future<void> reset() async {
    resetCalls++;
  }

  @override
  Future<bool> acceptWaveformBytes(Uint8List bytes) async {
    acceptCalls++;
    return emitFinalOnChunk && acceptCalls == 1;
  }

  @override
  Future<String> getResultJson() async => '{"text":"segment un"}';

  @override
  Future<String> getPartialResultJson() async => '{"partial":"bon"}';

  @override
  Future<String> getFinalResultJson() async => '{"text":"$finalText"}';
}

void main() {
  group('extractTextFromVoskJson', () {
    test('parses text field', () {
      expect(
        AudioTranscriptionService.extractTextFromVoskJson(
          '{"text":"salut"}',
        ),
        'salut',
      );
    });

    test('falls back on malformed json', () {
      expect(
        AudioTranscriptionService.extractTextFromVoskJson(
          'noise "text" : "hey" trailing',
        ),
        'hey',
      );
    });
  });

  group('transcriptFileNameFor', () {
    test('replaces extension with _transcript.txt', () {
      expect(
        transcriptFileNameFor(r'C:\tmp\PTT-20260928-WA0003.opus'),
        'PTT-20260928-WA0003_transcript.txt',
      );
    });
  });

  group('transcribeWav16kMono', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('malinali_stt_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('feeds PCM chunks and returns final text', () async {
      final wavPath = p.join(tempDir.path, 'silence.wav');
      // 0.5 s @ 16 kHz → 8000 samples → 16000 bytes PCM
      await File(wavPath).writeAsBytes(
        buildPcm16MonoWav(sampleRate: 16000, sampleCount: 8000),
      );

      final fake = FakeWaveformTranscriber(finalText: 'bonjour');
      final service = AudioTranscriptionService(
        transcriber: fake,
        chunkBytes: 4000,
      );

      final text = await service.transcribeWav16kMono(File(wavPath));
      expect(text, 'bonjour');
      expect(fake.ready, isTrue);
      expect(fake.resetCalls, 1);
      expect(fake.acceptCalls, greaterThan(1));
    });

    test('joins mid-utterance finals with tail', () async {
      final wavPath = p.join(tempDir.path, 'chunks.wav');
      await File(wavPath).writeAsBytes(
        buildPcm16MonoWav(sampleRate: 16000, sampleCount: 4000),
      );

      final fake = FakeWaveformTranscriber(
        finalText: 'monde',
        emitFinalOnChunk: true,
      );
      final service = AudioTranscriptionService(
        transcriber: fake,
        chunkBytes: 8000,
      );

      final text = await service.transcribeWav16kMono(File(wavPath));
      expect(text, 'segment un monde');
    });

    test('rejects wrong sample rate', () async {
      final wavPath = p.join(tempDir.path, 'bad_rate.wav');
      await File(wavPath).writeAsBytes(
        buildPcm16MonoWav(sampleRate: 44100, sampleCount: 100),
      );

      final service = AudioTranscriptionService(
        transcriber: FakeWaveformTranscriber(),
      );
      expect(
        () => service.transcribeWav16kMono(File(wavPath)),
        throwsA(isA<AudioTranscriptionException>()),
      );
    });
  });

  group('transcribeFile', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('malinali_stt_file_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('decode then STT via injected ffmpeg runner', () async {
      final opus = File(p.join(tempDir.path, 'note.opus'));
      await opus.writeAsBytes([1, 2, 3]);

      final fake = FakeWaveformTranscriber(finalText: 'ça marche');
      final service = AudioTranscriptionService(
        decodeService: AudioDecodeService(
          runner: (command) async {
            // Output path is the last quoted token in buildDecodeCommand.
            final match = RegExp(r'"([^"]+)"\s*$').firstMatch(command);
            final out = match!.group(1)!;
            await File(out).writeAsBytes(
              buildPcm16MonoWav(sampleRate: 16000, sampleCount: 1600),
            );
            return const FfmpegExecResult(success: true);
          },
        ),
        transcriber: fake,
        chunkBytes: 4000,
      );

      final phases = <String>[];
      final result = await service.transcribeFile(
        opus,
        workDirectory: tempDir,
        onProgress: (p) => phases.add(p.phase),
      );

      expect(result.cancelled, isFalse);
      expect(result.text, 'ça marche');
      expect(phases.first, 'decode');
      expect(phases.contains('transcribe'), isTrue);
      expect(phases.last, 'done');
    });

    test('missing file throws', () async {
      final service = AudioTranscriptionService(
        transcriber: FakeWaveformTranscriber(),
      );
      expect(
        () => service.transcribeFile(File(p.join(tempDir.path, 'nope.opus'))),
        throwsA(isA<AudioTranscriptionException>()),
      );
    });
  });
}
