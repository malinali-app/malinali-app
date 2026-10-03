import 'dart:ffi';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Result of a single FFmpeg command execution.
@immutable
class FfmpegExecResult {
  const FfmpegExecResult({
    required this.success,
    this.logs = '',
    this.returnCode,
  });

  final bool success;
  final String logs;
  final int? returnCode;
}

/// Injectable FFmpeg runner (real kit or fake in tests).
typedef FfmpegCommandRunner = Future<FfmpegExecResult> Function(String command);

/// Default runner backed by [FFmpegKit].
Future<FfmpegExecResult> defaultFfmpegCommandRunner(String command) async {
  ensureWindowsFfmpegNativeReady();
  final session = await FFmpegKit.execute(command);
  final code = await session.getReturnCode();
  final logs = await session.getAllLogsAsString() ?? '';
  return FfmpegExecResult(
    success: ReturnCode.isSuccess(code),
    logs: logs,
    returnCode: code?.getValue(),
  );
}

/// Preload FFmpegKit + MinGW deps from the executable directory (Windows).
///
/// Mirrors the Vosk DLL preload pattern. Safe no-op if files are missing.
/// Does not fix a process that already loaded incompatible MinGW runtimes;
/// [windows/CMakeLists.txt] re-copies FFmpegKit DLLs last for that.
@visibleForTesting
void ensureWindowsFfmpegNativeReady() {
  if (!Platform.isWindows) return;
  try {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    // Dependency order: MinGW runtime → libav* → kit.
    const names = <String>[
      'libwinpthread-1.dll',
      'libgcc_s_seh-1.dll',
      'libstdc++-6.dll',
      'zlib1.dll',
      'avutil-60.dll',
      'swresample-6.dll',
      'swscale-9.dll',
      'avcodec-62.dll',
      'avformat-62.dll',
      'avfilter-11.dll',
      'avdevice-62.dll',
      'libffmpegkit.dll',
    ];
    for (final name in names) {
      final dll = File(p.join(exeDir, name));
      if (!dll.existsSync()) continue;
      try {
        DynamicLibrary.open(dll.path);
      } catch (_) {}
    }
  } catch (_) {}
}

/// Decodes arbitrary audio (Ogg/Opus, m4a, …) to 16 kHz mono PCM WAV.
///
/// Output matches what Vosk / Sherpa expect for offline STT.
class AudioDecodeService {
  AudioDecodeService({
    FfmpegCommandRunner? runner,
    this.sampleRate = 16000,
  }) : _runner = runner ?? defaultFfmpegCommandRunner;

  final FfmpegCommandRunner _runner;
  final int sampleRate;

  /// Builds the FFmpeg CLI for [inputPath] → [outputPath].
  ///
  /// Exposed for unit tests (no native FFmpeg required).
  @visibleForTesting
  String buildDecodeCommand({
    required String inputPath,
    required String outputPath,
  }) {
    // -vn: drop video if any
    // mono + 16 kHz + PCM s16le WAV — STT-friendly
    // Quotes protect paths with spaces (Windows / content copies).
    return '-y -i "${_escapePath(inputPath)}" '
        '-vn -ac 1 -ar $sampleRate -c:a pcm_s16le '
        '"${_escapePath(outputPath)}"';
  }

  String _escapePath(String path) => path.replaceAll('"', r'\"');

  /// Decode [input] to a WAV file under [outputDirectory] (or temp).
  ///
  /// Returns the created WAV [File]. Throws [AudioDecodeException] on failure.
  Future<File> decodeToWav16kMono(
    File input, {
    Directory? outputDirectory,
    String? outputFileName,
  }) async {
    if (!await input.exists()) {
      throw AudioDecodeException('Input file not found: ${input.path}');
    }

    final outDir = outputDirectory ?? await getTemporaryDirectory();
    if (!await outDir.exists()) {
      await outDir.create(recursive: true);
    }

    final stem = p.basenameWithoutExtension(input.path);
    final name = outputFileName ?? '${stem}_16k_mono.wav';
    final output = File(p.join(outDir.path, name));

    final command = buildDecodeCommand(
      inputPath: input.path,
      outputPath: output.path,
    );

    final result = await _runner(command);
    if (!result.success) {
      throw AudioDecodeException(
        'FFmpeg decode failed (code=${result.returnCode}): ${result.logs}',
      );
    }
    if (!await output.exists() || await output.length() == 0) {
      throw AudioDecodeException(
        'FFmpeg reported success but output is missing or empty: ${output.path}',
      );
    }
    return output;
  }
}

class AudioDecodeException implements Exception {
  AudioDecodeException(this.message);
  final String message;

  @override
  String toString() => 'AudioDecodeException: $message';
}
