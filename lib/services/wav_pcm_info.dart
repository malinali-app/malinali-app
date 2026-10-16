import 'dart:typed_data';

/// Minimal PCM WAV header reader for decode / STT pipelines.
class WavPcmInfo {
  const WavPcmInfo({
    required this.audioFormat,
    required this.numChannels,
    required this.sampleRate,
    required this.bitsPerSample,
    required this.dataByteCount,
    required this.dataOffset,
  });

  final int audioFormat;
  final int numChannels;
  final int sampleRate;
  final int bitsPerSample;
  final int dataByteCount;

  /// Byte offset where PCM samples begin.
  final int dataOffset;

  static WavPcmInfo parse(Uint8List bytes) {
    if (bytes.length < 44) {
      throw FormatException('WAV too short (${bytes.length} bytes)');
    }
    final bd = ByteData.sublistView(bytes);
    final riff = String.fromCharCodes(bytes.sublist(0, 4));
    final wave = String.fromCharCodes(bytes.sublist(8, 12));
    if (riff != 'RIFF' || wave != 'WAVE') {
      throw FormatException('Not a RIFF/WAVE file');
    }

    var offset = 12;
    int? audioFormat;
    int? numChannels;
    int? sampleRate;
    int? bitsPerSample;
    int? dataByteCount;
    int? dataOffset;

    while (offset + 8 <= bytes.length) {
      final id = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final size = bd.getUint32(offset + 4, Endian.little);
      final dataStart = offset + 8;
      if (id == 'fmt ' && size >= 16) {
        audioFormat = bd.getUint16(dataStart, Endian.little);
        numChannels = bd.getUint16(dataStart + 2, Endian.little);
        sampleRate = bd.getUint32(dataStart + 4, Endian.little);
        bitsPerSample = bd.getUint16(dataStart + 14, Endian.little);
      } else if (id == 'data') {
        dataByteCount = size;
        dataOffset = dataStart;
        break;
      }
      offset = dataStart + size + (size.isOdd ? 1 : 0);
    }

    if (audioFormat == null ||
        numChannels == null ||
        sampleRate == null ||
        bitsPerSample == null ||
        dataByteCount == null ||
        dataOffset == null) {
      throw FormatException('Incomplete WAV fmt/data chunks');
    }

    return WavPcmInfo(
      audioFormat: audioFormat,
      numChannels: numChannels,
      sampleRate: sampleRate,
      bitsPerSample: bitsPerSample,
      dataByteCount: dataByteCount,
      dataOffset: dataOffset,
    );
  }
}

/// Fills RIFF and data sizes on the 44-byte placeholder header written while
/// recording. Returns false when [bytes] is not that header or already matches
/// the file length. Does not append bytes.
bool patchPlaceholderWavHeader(Uint8List bytes) {
  if (bytes.length < 44) return false;
  if (String.fromCharCodes(bytes.sublist(36, 40)) != 'data') return false;
  final bd = ByteData.sublistView(bytes);
  final dataLength = bytes.length - 44;
  final riffOk = bd.getUint32(4, Endian.little) == bytes.length - 8;
  final dataOk = bd.getUint32(40, Endian.little) == dataLength;
  if (riffOk && dataOk) return false;
  bd.setUint32(4, bytes.length - 8, Endian.little);
  bd.setUint32(40, dataLength, Endian.little);
  return true;
}
