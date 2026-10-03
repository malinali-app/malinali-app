import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:malinali/services/audio_decode_service.dart';
import 'package:path/path.dart' as p;

void main() {
  group('AudioDecodeService.buildDecodeCommand', () {
    test('targets 16 kHz mono PCM WAV with overwrite', () {
      final service = AudioDecodeService(
        runner: (_) async => const FfmpegExecResult(success: true),
      );
      final cmd = service.buildDecodeCommand(
        inputPath: r'C:\tmp\note.ogg',
        outputPath: r'C:\tmp\note_16k_mono.wav',
      );
      expect(cmd, contains('-y'));
      expect(cmd, contains('-i "C:\\tmp\\note.ogg"'));
      expect(cmd, contains('-vn'));
      expect(cmd, contains('-ac 1'));
      expect(cmd, contains('-ar 16000'));
      expect(cmd, contains('-c:a pcm_s16le'));
      expect(cmd, contains('"C:\\tmp\\note_16k_mono.wav"'));
    });

    test('escapes double quotes in paths', () {
      final service = AudioDecodeService(
        runner: (_) async => const FfmpegExecResult(success: true),
      );
      final cmd = service.buildDecodeCommand(
        inputPath: r'C:\tmp\weird"name.opus',
        outputPath: r'C:\tmp\out.wav',
      );
      expect(cmd, contains(r'weird\"name.opus'));
    });

    test('respects custom sampleRate', () {
      final service = AudioDecodeService(
        sampleRate: 8000,
        runner: (_) async => const FfmpegExecResult(success: true),
      );
      final cmd = service.buildDecodeCommand(
        inputPath: 'in.ogg',
        outputPath: 'out.wav',
      );
      expect(cmd, contains('-ar 8000'));
    });
  });

  group('AudioDecodeService.decodeToWav16kMono', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('malinali_audio_decode_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('throws when input is missing', () async {
      final service = AudioDecodeService(
        runner: (_) async => const FfmpegExecResult(success: true),
      );
      final missing = File(p.join(tempDir.path, 'nope.ogg'));
      await expectLater(
        service.decodeToWav16kMono(missing, outputDirectory: tempDir),
        throwsA(isA<AudioDecodeException>()),
      );
    });

    test('invokes runner with built command and returns output file', () async {
      final input = File(p.join(tempDir.path, 'voice.ogg'));
      await input.writeAsBytes([0, 1, 2, 3]); // placeholder bytes

      String? seenCommand;
      final service = AudioDecodeService(
        runner: (command) async {
          seenCommand = command;
          final outPath = p.join(tempDir.path, 'voice_16k_mono.wav');
          await File(outPath).writeAsBytes(List<int>.filled(44, 0));
          return const FfmpegExecResult(success: true);
        },
      );

      final wav = await service.decodeToWav16kMono(
        input,
        outputDirectory: tempDir,
      );

      expect(seenCommand, isNotNull);
      expect(seenCommand, contains(input.path));
      expect(seenCommand, contains('-ar 16000'));
      expect(wav.path, p.join(tempDir.path, 'voice_16k_mono.wav'));
      expect(await wav.exists(), isTrue);
    });

    test('throws AudioDecodeException when FFmpeg fails', () async {
      final input = File(p.join(tempDir.path, 'bad.opus'));
      await input.writeAsString('not audio');

      final service = AudioDecodeService(
        runner: (_) async => const FfmpegExecResult(
          success: false,
          returnCode: 1,
          logs: 'Invalid data found',
        ),
      );

      await expectLater(
        service.decodeToWav16kMono(input, outputDirectory: tempDir),
        throwsA(
          isA<AudioDecodeException>().having(
            (e) => e.message,
            'message',
            contains('Invalid data found'),
          ),
        ),
      );
    });

    test('throws when runner succeeds but output file is empty', () async {
      final input = File(p.join(tempDir.path, 'voice.ogg'));
      await input.writeAsBytes([1, 2, 3]);

      final service = AudioDecodeService(
        runner: (command) async {
          // Create empty output matching default name.
          final out = File(p.join(tempDir.path, 'voice_16k_mono.wav'));
          await out.writeAsBytes([]);
          return const FfmpegExecResult(success: true);
        },
      );

      await expectLater(
        service.decodeToWav16kMono(input, outputDirectory: tempDir),
        throwsA(isA<AudioDecodeException>()),
      );
    });

    test('honours custom outputFileName', () async {
      final input = File(p.join(tempDir.path, 'a.ogg'));
      await input.writeAsBytes([9]);

      final service = AudioDecodeService(
        runner: (_) async {
          final out = File(p.join(tempDir.path, 'custom.wav'));
          await out.writeAsBytes([0, 0, 0, 0]);
          return const FfmpegExecResult(success: true);
        },
      );

      final wav = await service.decodeToWav16kMono(
        input,
        outputDirectory: tempDir,
        outputFileName: 'custom.wav',
      );
      expect(p.basename(wav.path), 'custom.wav');
    });
  });
}
