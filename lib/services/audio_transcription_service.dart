import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:malinali/services/audio_decode_service.dart';
import 'package:malinali/services/wav_pcm_info.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Progress for a file transcription job.
@immutable
class AudioTranscriptionProgress {
  const AudioTranscriptionProgress({
    required this.phase,
    this.fraction = 0,
    this.partialText = '',
  });

  /// `decode` | `transcribe` | `done` | `cancelled`
  final String phase;
  final double fraction;
  final String partialText;
}

@immutable
class AudioTranscriptionResult {
  const AudioTranscriptionResult({
    required this.text,
    required this.cancelled,
    this.wavPath,
  });

  final String text;
  final bool cancelled;
  final String? wavPath;
}

/// Feeds PCM16 mono chunks into a Vosk-compatible recognizer.
abstract class WaveformTranscriber {
  Future<void> ensureReady();
  Future<void> reset();
  Future<bool> acceptWaveformBytes(Uint8List bytes);
  Future<String> getResultJson();
  Future<String> getPartialResultJson();
  Future<String> getFinalResultJson();
}

/// Decodes a WAV and returns the transcript, skipping chunked Vosk.
typedef WholeFileTranscriber = Future<String> Function(File wavFile);

/// Offline audio file → text: FFmpeg decode then Vosk or Whisper.
class AudioTranscriptionService {
  AudioTranscriptionService({
    AudioDecodeService? decodeService,
    WaveformTranscriber? transcriber,
    this.wholeFileTranscriber,
    this.chunkBytes = defaultChunkBytes,
  })  : _decode = decodeService ?? AudioDecodeService(),
        _transcriber = transcriber;

  /// ~250 ms of 16 kHz mono s16le (16000 * 2 * 0.25).
  static const int defaultChunkBytes = 8000;

  final AudioDecodeService _decode;
  final WaveformTranscriber? _transcriber;
  final WholeFileTranscriber? wholeFileTranscriber;
  final int chunkBytes;

  /// Transcribe [audioFile] (.opus / .ogg / .wav / …).
  Future<AudioTranscriptionResult> transcribeFile(
    File audioFile, {
    Directory? workDirectory,
    void Function(AudioTranscriptionProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (!await audioFile.exists()) {
      throw AudioTranscriptionException(
        'Fichier audio introuvable: ${audioFile.path}',
      );
    }

    onProgress?.call(
      const AudioTranscriptionProgress(phase: 'decode', fraction: 0),
    );

    if (isCancelled?.call() == true) {
      return const AudioTranscriptionResult(text: '', cancelled: true);
    }

    final workDir = workDirectory ??
        await Directory.systemTemp.createTemp('malinali_audio_stt_');
    final wav = await _decode.decodeToWav16kMono(
      audioFile,
      outputDirectory: workDir,
    );

    onProgress?.call(
      const AudioTranscriptionProgress(phase: 'transcribe', fraction: 0),
    );

    final text = await transcribeWav16kMono(
      wav,
      onProgress: (fraction, partial) {
        onProgress?.call(
          AudioTranscriptionProgress(
            phase: 'transcribe',
            fraction: fraction,
            partialText: partial,
          ),
        );
      },
      isCancelled: isCancelled,
    );

    final cancelled = isCancelled?.call() == true;
    onProgress?.call(
      AudioTranscriptionProgress(
        phase: cancelled ? 'cancelled' : 'done',
        fraction: 1,
        partialText: text,
      ),
    );

    return AudioTranscriptionResult(
      text: text,
      cancelled: cancelled,
      wavPath: wav.path,
    );
  }

  /// Transcribe an already-decoded 16 kHz mono PCM WAV.
  @visibleForTesting
  Future<String> transcribeWav16kMono(
    File wavFile, {
    void Function(double fraction, String partialText)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final bytes = await wavFile.readAsBytes();
    final info = WavPcmInfo.parse(bytes);
    if (info.audioFormat != 1) {
      throw AudioTranscriptionException('WAV non-PCM non supporté');
    }
    if (info.numChannels != 1 || info.bitsPerSample != 16) {
      throw AudioTranscriptionException(
        'Attendu mono 16-bit (reçu ${info.numChannels} ch / ${info.bitsPerSample} bit)',
      );
    }
    if (info.sampleRate != 16000) {
      throw AudioTranscriptionException(
        'Attendu 16 kHz (reçu ${info.sampleRate} Hz)',
      );
    }

    final direct = wholeFileTranscriber;
    if (direct != null) {
      if (isCancelled?.call() == true) return '';
      onProgress?.call(0.1, '');
      final text = await direct(wavFile);
      onProgress?.call(1, text);
      return text;
    }

    final transcriber = _transcriber;
    if (transcriber == null) {
      throw AudioTranscriptionException('Aucun moteur de transcription');
    }

    final dataEnd =
        (info.dataOffset + info.dataByteCount).clamp(0, bytes.length);
    final pcm = bytes.sublist(info.dataOffset, dataEnd);
    if (pcm.isEmpty) return '';

    await transcriber.ensureReady();
    await transcriber.reset();

    final segments = <String>[];
    final total = pcm.length;
    var offset = 0;

    while (offset < total) {
      if (isCancelled?.call() == true) break;

      final end = (offset + chunkBytes).clamp(0, total);
      final chunk = Uint8List.fromList(pcm.sublist(offset, end));
      final isFinal = await transcriber.acceptWaveformBytes(chunk);
      if (isFinal) {
        final text = extractTextFromVoskJson(
          await transcriber.getResultJson(),
        );
        if (text.isNotEmpty) segments.add(text);
      }

      final partial = extractPartialFromVoskJson(
        await transcriber.getPartialResultJson(),
      );
      final preview = [
        ...segments,
        if (partial.isNotEmpty) partial,
      ].join(' ').trim();

      offset = end;
      onProgress?.call(offset / total, preview);
    }

    if (isCancelled?.call() != true) {
      final tail = extractTextFromVoskJson(
        await transcriber.getFinalResultJson(),
      );
      if (tail.isNotEmpty) segments.add(tail);
    }

    return segments.join(' ').trim();
  }

  @visibleForTesting
  static String extractTextFromVoskJson(String jsonResult) {
    try {
      final decoded = jsonDecode(jsonResult);
      if (decoded is Map<String, dynamic>) {
        return (decoded['text'] as String? ?? '').trim();
      }
    } catch (_) {
      final m = RegExp(r'"text"\s*:\s*"([^"]*)"').firstMatch(jsonResult);
      return (m?.group(1) ?? '').trim();
    }
    return '';
  }

  @visibleForTesting
  static String extractPartialFromVoskJson(String jsonResult) {
    try {
      final decoded = jsonDecode(jsonResult);
      if (decoded is Map<String, dynamic>) {
        return (decoded['partial'] as String? ?? '').trim();
      }
    } catch (_) {
      final m = RegExp(r'"partial"\s*:\s*"([^"]*)"').firstMatch(jsonResult);
      return (m?.group(1) ?? '').trim();
    }
    return '';
  }
}

class AudioTranscriptionException implements Exception {
  AudioTranscriptionException(this.message);
  final String message;

  @override
  String toString() => 'AudioTranscriptionException: $message';
}

/// Suggested output filename for a transcript next to the source audio.
String transcriptFileNameFor(String audioPath) {
  final stem = p.basenameWithoutExtension(audioPath);
  return '${stem}_transcript.txt';
}

Future<Directory> audioSttWorkDirectory() async {
  final docs = await getApplicationDocumentsDirectory();
  final base = Platform.isWindows
      ? p.join(docs.path, 'Malinali_do_not_delete', 'audio_stt')
      : p.join(docs.path, 'audio_stt');
  final dir = Directory(base);
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
}
