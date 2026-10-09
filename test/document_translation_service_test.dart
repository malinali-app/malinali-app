import 'package:flutter_test/flutter_test.dart';
import 'package:malinali/services/document_translation_service.dart';
import 'package:marian_flutter/marian_flutter.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'document_translation_service_test.mocks.dart';

@GenerateMocks([MarianService])
void main() {
  late DocumentTranslationService service;
  late MockMarianService mockMarian;

  setUp(() {
    service = DocumentTranslationService(maxChunkChars: 40);
    mockMarian = MockMarianService();
  });

  group('chunkText', () {
    test('empty and whitespace-only return no chunks', () {
      expect(service.chunkText(''), isEmpty);
      expect(service.chunkText('   \n\n  '), isEmpty);
    });

    test('short paragraph stays as a single chunk', () {
      expect(service.chunkText('Bonjour le monde.'), ['Bonjour le monde.']);
    });

    test('blank-line paragraphs become separate chunks', () {
      const text = 'Premier paragraphe.\n\nDeuxième paragraphe.';
      expect(service.chunkText(text), [
        'Premier paragraphe.',
        'Deuxième paragraphe.',
      ]);
    });

    test('long paragraph splits on sentence boundaries', () {
      // Each sentence is under 40 chars; together they exceed it.
      const text =
          'Phrase une assez courte. Phrase deux aussi courte. Phrase trois finale.';
      final chunks = service.chunkText(text);
      expect(chunks.length, greaterThan(1));
      expect(chunks.every((c) => c.length <= 40), isTrue);
      expect(chunks.join(' '), contains('Phrase une'));
      expect(chunks.join(' '), contains('Phrase trois'));
    });

    test('oversized run without spaces is hard-split', () {
      final long = 'a' * 95;
      final chunks = service.chunkText(long);
      expect(chunks.length, greaterThanOrEqualTo(3));
      expect(chunks.every((c) => c.length <= 40), isTrue);
      expect(chunks.join(), long);
    });

    test('normalizes CRLF', () {
      expect(service.chunkText('A\r\n\r\nB'), ['A', 'B']);
    });
  });

  group('translateDocument', () {
    test('empty source does not call Marian', () async {
      final result = await service.translateDocument(
        sourceText: '   ',
        marian: mockMarian,
      );
      expect(result.text, isEmpty);
      expect(result.chunkCount, 0);
      expect(result.cancelled, isFalse);
      verifyNever(
        mockMarian.translate(any, config: anyNamed('config')),
      );
    });

    test('translates chunks sequentially and joins with blank lines', () async {
      when(
        mockMarian.translate(any, config: anyNamed('config')),
      ).thenAnswer((invocation) async {
        final text = invocation.positionalArguments[0] as String;
        return 'TR:$text';
      });

      const source = 'Alpha.\n\nBeta.';
      final progresses = <DocumentTranslationProgress>[];

      final result = await service.translateDocument(
        sourceText: source,
        marian: mockMarian,
        onProgress: progresses.add,
      );

      expect(result.cancelled, isFalse);
      expect(result.chunkCount, 2);
      expect(result.text, 'TR:Alpha.\n\nTR:Beta.');
      expect(progresses, [
        const DocumentTranslationProgress(
          completedChunks: 1,
          totalChunks: 2,
        ),
        const DocumentTranslationProgress(
          completedChunks: 2,
          totalChunks: 2,
        ),
      ]);
      verify(
        mockMarian.translate('Alpha.', config: kDocumentTranslationConfig),
      ).called(1);
      verify(
        mockMarian.translate('Beta.', config: kDocumentTranslationConfig),
      ).called(1);
      verifyNoMoreInteractions(mockMarian);
    });

    test('prepareSource prefixes each chunk before Marian', () async {
      when(
        mockMarian.translate(any, config: anyNamed('config')),
      ).thenAnswer((invocation) async {
        final text = invocation.positionalArguments[0] as String;
        return 'TR:$text';
      });

      final result = await service.translateDocument(
        sourceText: 'Alpha.\n\nBeta.',
        marian: mockMarian,
        prepareSource: (chunk) => '>>wol<< $chunk',
      );

      expect(result.text, 'TR:>>wol<< Alpha.\n\nTR:>>wol<< Beta.');
      verify(
        mockMarian.translate(
          '>>wol<< Alpha.',
          config: kDocumentTranslationConfig,
        ),
      ).called(1);
      verify(
        mockMarian.translate(
          '>>wol<< Beta.',
          config: kDocumentTranslationConfig,
        ),
      ).called(1);
    });

    test('uses provided TranslationConfig', () async {
      const custom = TranslationConfig(
        numBeams: 1,
        maxNewTokens: 64,
        lengthPenalty: 1.0,
        noRepeatNgramSize: 0,
      );
      when(
        mockMarian.translate(any, config: anyNamed('config')),
      ).thenAnswer((_) async => 'ok');

      await service.translateDocument(
        sourceText: 'Hello.',
        marian: mockMarian,
        config: custom,
      );

      verify(mockMarian.translate('Hello.', config: custom)).called(1);
    });

    test('cancels between chunks and keeps partial output', () async {
      var calls = 0;
      when(
        mockMarian.translate(any, config: anyNamed('config')),
      ).thenAnswer((invocation) async {
        calls++;
        final text = invocation.positionalArguments[0] as String;
        return 'TR:$text';
      });

      final progresses = <DocumentTranslationProgress>[];
      final result = await service.translateDocument(
        sourceText: 'One.\n\nTwo.\n\nThree.',
        marian: mockMarian,
        onProgress: progresses.add,
        isCancelled: () => calls >= 1,
      );

      expect(result.cancelled, isTrue);
      expect(result.text, 'TR:One.');
      expect(result.chunkCount, 3);
      expect(
        progresses.last,
        const DocumentTranslationProgress(
          completedChunks: 1,
          totalChunks: 3,
          cancelled: true,
        ),
      );
      verify(
        mockMarian.translate(any, config: anyNamed('config')),
      ).called(1);
    });

    test('propagates Marian errors from a chunk', () async {
      when(
        mockMarian.translate(any, config: anyNamed('config')),
      ).thenThrow(Exception('candle boom'));

      await expectLater(
        service.translateDocument(
          sourceText: 'Fail me.',
          marian: mockMarian,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('reports zero progress for empty input', () async {
      DocumentTranslationProgress? progress;
      await service.translateDocument(
        sourceText: '',
        marian: mockMarian,
        onProgress: (p) => progress = p,
      );
      expect(
        progress,
        const DocumentTranslationProgress(
          completedChunks: 0,
          totalChunks: 0,
        ),
      );
      expect(progress!.fraction, 1.0);
      expect(progress!.isComplete, isFalse);
    });
  });

  group('DocumentTranslationProgress', () {
    test('fraction and isComplete', () {
      const mid = DocumentTranslationProgress(
        completedChunks: 2,
        totalChunks: 4,
      );
      expect(mid.fraction, 0.5);
      expect(mid.isComplete, isFalse);

      const done = DocumentTranslationProgress(
        completedChunks: 4,
        totalChunks: 4,
      );
      expect(done.isComplete, isTrue);

      const cancelled = DocumentTranslationProgress(
        completedChunks: 4,
        totalChunks: 4,
        cancelled: true,
      );
      expect(cancelled.isComplete, isFalse);
    });
  });
}
