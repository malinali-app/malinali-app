import 'package:flutter/foundation.dart';
import 'package:marian_flutter/marian_flutter.dart';

/// Document-mode decode: longer outputs than street chat bubbles.
const TranslationConfig kDocumentTranslationConfig = TranslationConfig(
  numBeams: 2,
  maxNewTokens: 128,
  lengthPenalty: 1.2,
  noRepeatNgramSize: 3,
);

/// Progress snapshot for a running batch translation.
@immutable
class DocumentTranslationProgress {
  const DocumentTranslationProgress({
    required this.completedChunks,
    required this.totalChunks,
    this.cancelled = false,
  });

  final int completedChunks;
  final int totalChunks;
  final bool cancelled;

  double get fraction {
    if (totalChunks <= 0) return 1.0;
    return (completedChunks / totalChunks).clamp(0.0, 1.0);
  }

  bool get isComplete =>
      !cancelled && totalChunks > 0 && completedChunks >= totalChunks;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DocumentTranslationProgress &&
          completedChunks == other.completedChunks &&
          totalChunks == other.totalChunks &&
          cancelled == other.cancelled;

  @override
  int get hashCode =>
      Object.hash(completedChunks, totalChunks, cancelled);
}

/// Result of [DocumentTranslationService.translateDocument].
@immutable
class DocumentTranslationResult {
  const DocumentTranslationResult({
    required this.text,
    required this.chunkCount,
    required this.cancelled,
  });

  final String text;
  final int chunkCount;
  final bool cancelled;
}

/// Offline batch document translation: chunk → translate → join.
///
/// Designed to be unit-tested with a mocked [MarianService].
class DocumentTranslationService {
  DocumentTranslationService({
    this.maxChunkChars = defaultMaxChunkChars,
  });

  /// Soft upper bound on source characters per Marian call.
  /// Marian street models are short-context; keep chunks modest.
  static const int defaultMaxChunkChars = 400;

  final int maxChunkChars;

  /// Split [text] into translation units.
  List<String> chunkText(String text) {
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final trimmed = normalized.trim();
    if (trimmed.isEmpty) return const [];

    final paragraphs = normalized
        .split(RegExp(r'\n\s*\n'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();

    if (paragraphs.isEmpty) return const [];

    final chunks = <String>[];
    for (final paragraph in paragraphs) {
      if (paragraph.length <= maxChunkChars) {
        chunks.add(paragraph);
        continue;
      }
      chunks.addAll(_splitLongParagraph(paragraph));
    }
    return chunks;
  }

  List<String> _splitLongParagraph(String paragraph) {
    final sentences = _splitSentences(paragraph);
    final out = <String>[];
    final buffer = StringBuffer();

    void flush() {
      final s = buffer.toString().trim();
      if (s.isNotEmpty) out.add(s);
      buffer.clear();
    }

    for (final sentence in sentences) {
      if (sentence.length > maxChunkChars) {
        flush();
        out.addAll(_hardSplit(sentence));
        continue;
      }
      final candidate = buffer.isEmpty
          ? sentence
          : '${buffer.toString()} $sentence';
      if (candidate.length > maxChunkChars) {
        flush();
        buffer.write(sentence);
      } else {
        if (buffer.isNotEmpty) buffer.write(' ');
        buffer.write(sentence);
      }
    }
    flush();
    return out;
  }

  /// Split on `.!?` followed by whitespace, keeping the delimiter on the left.
  List<String> _splitSentences(String text) {
    final parts = <String>[];
    final re = RegExp(r'(?<=[.!?…])\s+');
    var start = 0;
    for (final match in re.allMatches(text)) {
      final end = match.start;
      final piece = text.substring(start, end).trim();
      if (piece.isNotEmpty) parts.add(piece);
      start = match.end;
    }
    final tail = text.substring(start).trim();
    if (tail.isNotEmpty) parts.add(tail);
    return parts.isEmpty ? [text.trim()] : parts;
  }

  List<String> _hardSplit(String text) {
    final out = <String>[];
    var i = 0;
    while (i < text.length) {
      final end = (i + maxChunkChars).clamp(0, text.length);
      // Prefer breaking on whitespace near the end of the window.
      var cut = end;
      if (end < text.length) {
        final window = text.substring(i, end);
        final space = window.lastIndexOf(RegExp(r'\s'));
        if (space > maxChunkChars ~/ 3) {
          cut = i + space;
        }
      }
      final piece = text.substring(i, cut).trim();
      if (piece.isNotEmpty) out.add(piece);
      i = cut;
      while (i < text.length && text[i].trim().isEmpty) {
        i++;
      }
    }
    return out;
  }

  /// Translate an entire document sequentially.
  ///
  /// Empty input returns an empty result without calling [marian].
  /// When [isCancelled] returns true between chunks, remaining work stops and
  /// [DocumentTranslationResult.cancelled] is true (partial text kept).
  Future<DocumentTranslationResult> translateDocument({
    required String sourceText,
    required MarianService marian,
    TranslationConfig config = kDocumentTranslationConfig,
    void Function(DocumentTranslationProgress progress)? onProgress,
    bool Function()? isCancelled,
    String Function(String chunk)? prepareSource,
  }) async {
    final chunks = chunkText(sourceText);
    if (chunks.isEmpty) {
      onProgress?.call(
        const DocumentTranslationProgress(
          completedChunks: 0,
          totalChunks: 0,
        ),
      );
      return const DocumentTranslationResult(
        text: '',
        chunkCount: 0,
        cancelled: false,
      );
    }

    final translated = <String>[];
    for (var i = 0; i < chunks.length; i++) {
      if (isCancelled?.call() == true) {
        onProgress?.call(
          DocumentTranslationProgress(
            completedChunks: i,
            totalChunks: chunks.length,
            cancelled: true,
          ),
        );
        return DocumentTranslationResult(
          text: translated.join('\n\n'),
          chunkCount: chunks.length,
          cancelled: true,
        );
      }

      final source = prepareSource?.call(chunks[i]) ?? chunks[i];
      final piece = await marian.translate(source, config: config);
      translated.add(piece.trim());
      onProgress?.call(
        DocumentTranslationProgress(
          completedChunks: i + 1,
          totalChunks: chunks.length,
        ),
      );
    }

    return DocumentTranslationResult(
      text: translated.join('\n\n'),
      chunkCount: chunks.length,
      cancelled: false,
    );
  }
}
