// ignore_for_file: implementation_imports
import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';
import 'package:ml_algo/src/persistence/sqlite_neighbor_search_store.dart';
import 'package:ml_algo/src/retrieval/hybrid_fts_searcher.dart';
import 'package:ml_algo/src/retrieval/translation_result.dart';
import 'package:ml_linalg/vector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:malinali/services/embedding_service.dart';
import 'package:malinali/services/load_fula_dataset.dart';
import 'package:malinali/services/query_stemmer.dart';

void main() {
  runApp(const MalinaliApp());
}

class MalinaliApp extends StatelessWidget {
  const MalinaliApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Malinali',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const TranslationScreen(),
    );
  }
}

class TranslationScreen extends StatefulWidget {
  const TranslationScreen({super.key});

  @override
  State<TranslationScreen> createState() => _TranslationScreenState();
}

class _TranslationScreenState extends State<TranslationScreen> {
  late CodeLineEditingController _inputController;
  late CodeLineEditingController _outputController;
  HybridFTSSearcher? _searcher;
  EmbeddingService? _embeddingService;
  bool _isLoading = true;
  bool _isTranslating = false;
  String _sourceLang = 'French';
  String _targetLang = 'Fula'; // Default: French → Fula
  String? _error;

  @override
  void initState() {
    super.initState();
    _inputController = CodeLineEditingController();
    _outputController = CodeLineEditingController();
    _initializeSearcher();
  }

  Future<void> _initializeSearcher() async {
    try {
      // Initialize embedding service (ONNX model)
      final embeddingService = EmbeddingService();
      await embeddingService.initialize();

      final appDir = await getApplicationDocumentsDirectory();
      final dbPath = '${appDir.path}/fula_translations.db';
      final store = SQLiteNeighborSearchStore(dbPath);

      // Check if Fula searcher already exists in database
      HybridFTSSearcher? searcher;
      try {
        searcher = await HybridFTSSearcher.loadFromStore(store, 'fula');
        print('✅ Loaded existing Fula searcher from database');
      } catch (e) {
        // Searcher doesn't exist, need to create it
        print(
          'Creating Fula translation database (this will take a while for 30k+ pairs)...',
        );
        await loadEnglishFrenchFulaDataset();
        searcher = await HybridFTSSearcher.loadFromStore(store, 'fula');
        print('✅ Fula translation database created and loaded');
      }

      setState(() {
        _searcher = searcher;
        _embeddingService = embeddingService;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to initialize: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _translate() async {
    if (_searcher == null) return;

    final inputText = _inputController.text.trim();
    if (inputText.isEmpty) {
      _outputController.text = '';
      return;
    }

    setState(() {
      _isTranslating = true;
    });

    try {
      // Generate embedding using ONNX model
      Vector queryEmbedding;
      if (_embeddingService != null) {
        // Use real ONNX model embedding
        queryEmbedding = await _embeddingService!.generateEmbedding(inputText);
      } else {
        // Fallback: simple hash-based embedding (shouldn't happen if initialized)
        final embedding = List<double>.generate(384, (i) {
          final hash = (inputText.hashCode + i * 1000).abs();
          return (hash % 1000) / 1000.0;
        });
        queryEmbedding = Vector.fromList(embedding);
      }

      // Handle different translation directions
      // Database structure: sourceText = English/French (source), targetText = Fula (target)
      List<TranslationResult> results;
      List<TranslationResult> ftsResults = [];
      List<TranslationResult> semanticResultsFinal = [];
      bool hasExactFtsMatch = false;
      String resultSource = '';
      // Track FTS indices to check if results have FTS backing (for distance threshold check)
      Set<int> ftsIndices = <int>{};

      if (_sourceLang == 'Fula') {
        // Fula → English/French: Search in targetText (Fula), return sourceText (English/French)
        // Use semantic search since embeddings are stored for Fula
        print(
          'DEBUG: Fula → ${_targetLang}: Using semantic search (Fula embeddings)',
        );
        results = await _searcher!.searchBySemantic(
          queryEmbedding,
          k: 10, // Get more results to filter by target language
          searchRadius: 10,
        );
        resultSource = 'Semantic (embedding)';
        print('DEBUG: Semantic search results (before filtering):');
        for (var i = 0; i < results.length; i++) {
          final r = results[i];
          print(
            '  ${i + 1}. "${r.targetText}" → "${r.sourceText}" (distance: ${r.distance.toStringAsFixed(4)})',
          );
        }

        // Filter results to match target language (English or French)
        // Note: This is a simple heuristic - in production you might want more sophisticated filtering
        if (_targetLang == 'English') {
          // Filter to show only English results (heuristic: no French characters)
          results = results.where((r) {
            final text = r.sourceText.toLowerCase();
            // Simple heuristic: English text typically doesn't have French-specific characters
            // This is not perfect but works for most cases
            return !text.contains('é') &&
                !text.contains('è') &&
                !text.contains('ê') &&
                !text.contains('à') &&
                !text.contains('ç') &&
                !text.contains('ù');
          }).toList();
        } else if (_targetLang == 'French') {
          // Filter to show only French results (heuristic: has French characters or common French words)
          results = results.where((r) {
            final text = r.sourceText.toLowerCase();
            // Simple heuristic: French text often has French-specific characters
            return text.contains('é') ||
                text.contains('è') ||
                text.contains('ê') ||
                text.contains('à') ||
                text.contains('ç') ||
                text.contains('ù') ||
                text.contains(' le ') ||
                text.contains(' la ') ||
                text.contains(' de ');
          }).toList();
        }
        results = results.take(3).toList(); // Limit to 3 results
        print('DEBUG: After language filtering: ${results.length} results');
        for (var i = 0; i < results.length; i++) {
          final r = results[i];
          print(
            '  ${i + 1}. "${r.targetText}" → "${r.sourceText}" (distance: ${r.distance.toStringAsFixed(4)})',
          );
        }
        // For Fula → English/French, we only have semantic search
        ftsResults = [];
        semanticResultsFinal = results;
        hasExactFtsMatch = false;
      } else {
        // English/French → Fula: Search in sourceText (English/French), return targetText (Fula)
        // Stem query for FTS to handle word variations
        // Choose stemming strategy based on the current source language.
        // - English: use Porter/Snowball stemming
        // - French: conservative normalization (no aggressive stemming)
        final queryLanguage = _sourceLang == 'English'
            ? QueryLanguage.english
            : QueryLanguage.french;
        final stemmedQuery = QueryStemmer.stemQuery(inputText, queryLanguage);

        // Always run both:
        // - Keyword (FTS) search over sourceText
        // - Semantic search over Fula embeddings
        //
        // Then merge results, favouring:
        // - Strong semantic similarity
        // - Candidates that also match FTS
        // - Outputs whose length is closer to the input length

        // 1) Keyword search (FTS)
        final keywordResults = await _searcher!.searchByKeyword(
          stemmedQuery,
          k: 20,
        );
        print(
          'DEBUG: Keyword search (stemmed: "$stemmedQuery") found ${keywordResults.length} results',
        );

        // Filter FTS results to match source language (English or French)
        // This ensures we only get results from the correct source language
        List<TranslationResult> filteredKeywordResults = keywordResults;
        if (_sourceLang == 'English') {
          // Filter to show only English results (heuristic: no French characters)
          filteredKeywordResults = keywordResults.where((r) {
            final text = r.sourceText.toLowerCase();
            return !text.contains('é') &&
                !text.contains('è') &&
                !text.contains('ê') &&
                !text.contains('à') &&
                !text.contains('ç') &&
                !text.contains('ù');
          }).toList();
        } else if (_sourceLang == 'French') {
          // Filter to show only French results (heuristic: has French characters or common French words)
          filteredKeywordResults = keywordResults.where((r) {
            final text = r.sourceText.toLowerCase();
            return text.contains('é') ||
                text.contains('è') ||
                text.contains('ê') ||
                text.contains('à') ||
                text.contains('ç') ||
                text.contains('ù') ||
                text.contains(' le ') ||
                text.contains(' la ') ||
                text.contains(' de ');
          }).toList();
        }
        print(
          'DEBUG: After source language filtering: ${filteredKeywordResults.length} FTS results (from ${keywordResults.length})',
        );

        if (filteredKeywordResults.isNotEmpty) {
          print('DEBUG: FTS matches (filtered by source language):');
          for (var i = 0; i < filteredKeywordResults.length; i++) {
            final r = filteredKeywordResults[i];
            print(
              '  ${i + 1}. "${r.sourceText}" → "${r.targetText}" (distance: ${r.distance.toStringAsFixed(4)})',
            );
          }
        }

        // Look for an exact phrase match in filtered FTS results (after simple normalization).
        // If we find one, we will prefer it outright as the final answer.
        TranslationResult? exactKeywordMatch;
        final normalizedInput = inputText.trim().toLowerCase();
        for (final r in filteredKeywordResults) {
          final normalizedSource = r.sourceText.trim().toLowerCase();
          if (normalizedSource == normalizedInput) {
            exactKeywordMatch = r;
            break;
          }
        }

        // 2) Semantic search (always run, regardless of FTS outcome)
        final semanticResults = await _searcher!.searchBySemantic(
          queryEmbedding,
          k: 50,
          searchRadius: 10,
        );
        print(
          'DEBUG: Semantic search (embedding) found ${semanticResults.length} results',
        );

        // Filter semantic results to match source language (English or French)
        // This ensures we only get results from the correct source language
        // Made more lenient to avoid filtering out valid results
        List<TranslationResult> filteredSemanticResults = semanticResults;
        if (_sourceLang == 'English') {
          // Filter to show only English results (heuristic: no French characters)
          // More lenient: only exclude if it clearly has French characters
          filteredSemanticResults = semanticResults.where((r) {
            final text = r.sourceText.toLowerCase();
            // Exclude if it has French-specific characters
            final hasFrenchChars =
                text.contains('é') ||
                text.contains('è') ||
                text.contains('ê') ||
                text.contains('à') ||
                text.contains('ç') ||
                text.contains('ù') ||
                text.contains('ô') ||
                text.contains('î') ||
                text.contains('û');
            return !hasFrenchChars;
          }).toList();
        } else if (_sourceLang == 'French') {
          // Filter to show only French results (heuristic: has French characters or common French words)
          // More lenient: check for French words with or without spaces, and French characters
          filteredSemanticResults = semanticResults.where((r) {
            final text = r.sourceText.toLowerCase();
            // Check for French characters
            final hasFrenchChars =
                text.contains('é') ||
                text.contains('è') ||
                text.contains('ê') ||
                text.contains('à') ||
                text.contains('ç') ||
                text.contains('ù') ||
                text.contains('ô') ||
                text.contains('î') ||
                text.contains('û');
            // Check for common French words (with or without spaces, at word boundaries)
            final hasFrenchWords = RegExp(
              r'\b(le|la|de|du|des|les|un|une|et|ou|est|sont|dans|pour|avec|sur|par|que|qui|quoi|comment|où|quand|pourquoi)\b',
            ).hasMatch(text);
            return hasFrenchChars || hasFrenchWords;
          }).toList();
        }
        print(
          'DEBUG: After source language filtering: ${filteredSemanticResults.length} semantic results (from ${semanticResults.length})',
        );

        // Store FTS indices for later checking if results have FTS backing
        // Use filtered keyword results to only include results in the correct source language
        ftsIndices = filteredKeywordResults.map((r) => r.pointIndex).toSet();

        // Prepare FTS results (top 3)
        // If we have an exact match, put it first
        if (exactKeywordMatch != null) {
          final exactMatch = exactKeywordMatch;
          ftsResults = [
            exactMatch,
            ...filteredKeywordResults
                .where((r) => r.pointIndex != exactMatch.pointIndex)
                .take(2),
          ].toList();
          hasExactFtsMatch = true;
        } else {
          ftsResults = filteredKeywordResults.take(3).toList();
          hasExactFtsMatch = false;
        }

        // Prepare semantic results (top 3, re-ranked)
        semanticResultsFinal = [];
        if (filteredSemanticResults.isNotEmpty) {
          // Compute input length (in tokens)
          final inputTokens = inputText
              .split(RegExp(r'\s+'))
              .where((w) => w.trim().isNotEmpty)
              .toList();
          final inputLen = inputTokens.length;

          const alpha = 0.3; // strength of length penalty
          const ftsBoost = 0.7; // multiplier < 1.0 to reward FTS matches

          // Build scored candidates
          final scored = <_ScoredResult>[];
          for (final r in filteredSemanticResults) {
            final inFts = ftsIndices.contains(r.pointIndex);

            // Length of target text (Fula output)
            final targetText = r.targetText;
            final outputTokens = targetText
                .split(RegExp(r'\s+'))
                .where((w) => w.trim().isNotEmpty)
                .toList();
            final outputLen = outputTokens.length;

            final lenDiffRatio = (outputLen - inputLen).abs() / (inputLen + 1);
            final lengthPenalty = 1 + alpha * lenDiffRatio;

            var score = r.distance * lengthPenalty;
            if (inFts) {
              score *= ftsBoost;
            }

            scored.add(
              _ScoredResult(
                result: r,
                score: score,
                inFts: inFts,
                lengthPenalty: lengthPenalty,
              ),
            );
          }

          // Sort by score (ascending: lower is better)
          scored.sort((a, b) => a.score.compareTo(b.score));

          // Take top-k semantic candidates after re-ranking
          const k = 3;
          semanticResultsFinal = scored.take(k).map((s) => s.result).toList();

          print('DEBUG: Semantic results (top $k):');
          for (var i = 0; i < semanticResultsFinal.length; i++) {
            final r = semanticResultsFinal[i];
            final inFts = ftsIndices.contains(r.pointIndex);
            print(
              '  ${i + 1}. "${r.sourceText}" → "${r.targetText}" '
              '(distance: ${r.distance.toStringAsFixed(4)}, inFTS: $inFts)',
            );
          }
        }

        // Store results for display (we'll use both FTS and semantic separately)
        results =
            ftsResults; // Keep for backward compatibility, but we'll build split view
        resultSource = 'Split View (FTS + Semantic)';

        print(
          'DEBUG: FTS results: ${ftsResults.length}, Semantic results: ${semanticResultsFinal.length}',
        );
      }

      print(
        'DEBUG: Final results: FTS=${ftsResults.length}, Semantic=${semanticResultsFinal.length}',
      );

      // Always show split view, even if both are empty (will show "No match" for both)
      // Determine which field to display based on translation direction
      // Database structure:
      // - sourceText: contains English or French (source)
      // - targetText: contains Fula (target)
      //
      // For display, we want to show: source phrase → target translation
      // This allows users to assess if the translation is likely correct
      String getSourceText(TranslationResult result) {
        if (_sourceLang == 'Fula') {
          // When translating FROM Fula, the source phrase is in targetText (Fula)
          return result.targetText;
        } else {
          // When translating FROM English/French, the source phrase is in sourceText
          return result.sourceText;
        }
      }

      String getTargetText(TranslationResult result) {
        if (_targetLang == 'Fula') {
          // When translating TO Fula, the target is in targetText
          return result.targetText;
        } else {
          // When translating TO English/French, the target is in sourceText
          return result.sourceText;
        }
      }

      // Build split view output: FTS on left, Semantic on right
      final buffer = StringBuffer();

      // Helper to format a result line
      String formatResult(TranslationResult result, int index, bool isExact) {
        final source = getSourceText(result);
        final target = getTargetText(result);
        final prefix = isExact ? '⭐ ' : '${index + 1}. ';
        return '$prefix$source → $target';
      }

      // Build FTS column (left)
      buffer.writeln('🔤 Keyword');
      if (ftsResults.isEmpty) {
        buffer.writeln('No match');
      } else {
        for (var i = 0; i < ftsResults.length; i++) {
          final isExact = hasExactFtsMatch && i == 0;
          buffer.writeln(formatResult(ftsResults[i], i, isExact));
        }
      }

      buffer.writeln('');
      buffer.writeln('─────────────────────────────────────');
      buffer.writeln('');

      // Build Semantic column (right)
      buffer.writeln('✨ Semantic');
      if (semanticResultsFinal.isEmpty) {
        buffer.writeln('No match');
      } else {
        for (var i = 0; i < semanticResultsFinal.length; i++) {
          buffer.writeln(formatResult(semanticResultsFinal[i], i, false));
        }
      }

      _outputController.text = buffer.toString().trim();
    } catch (e) {
      _outputController.text = 'Error: $e';
    } finally {
      setState(() {
        _isTranslating = false;
      });
    }
  }

  void _onSourceLanguageChanged(String? newLang) {
    if (newLang == null || newLang == _sourceLang) return;

    // Prevent selecting the same language for both source and target
    if (newLang == _targetLang) {
      // Swap them instead
      setState(() {
        _targetLang = _sourceLang;
        _sourceLang = newLang;
        // Swap input and output
        final tempText = _inputController.text;
        _inputController.text = _outputController.text;
        _outputController.text = tempText;
      });
    } else {
      setState(() {
        _sourceLang = newLang;
      });
    }
  }

  void _onTargetLanguageChanged(String? newLang) {
    if (newLang == null || newLang == _targetLang) return;

    // Prevent selecting the same language for both source and target
    if (newLang == _sourceLang) {
      // Swap them instead
      setState(() {
        _sourceLang = _targetLang;
        _targetLang = newLang;
        // Swap input and output
        final tempText = _inputController.text;
        _inputController.text = _outputController.text;
        _outputController.text = tempText;
      });
    } else {
      setState(() {
        _targetLang = newLang;
      });
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    _outputController.dispose();
    _embeddingService?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Malinali'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Source language dropdown
                DropdownButton<String>(
                  value: _sourceLang,
                  underline: Container(), // Remove default underline
                  items: const [
                    DropdownMenuItem(value: 'French', child: Text('French')),
                    DropdownMenuItem(value: 'English', child: Text('English')),
                    DropdownMenuItem(value: 'Fula', child: Text('Fula')),
                  ],
                  onChanged: _onSourceLanguageChanged,
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8.0),
                  child: Icon(Icons.arrow_forward, size: 20),
                ),
                // Target language dropdown
                DropdownButton<String>(
                  value: _targetLang,
                  underline: Container(), // Remove default underline
                  items: const [
                    DropdownMenuItem(value: 'French', child: Text('French')),
                    DropdownMenuItem(value: 'English', child: Text('English')),
                    DropdownMenuItem(value: 'Fula', child: Text('Fula')),
                  ],
                  onChanged: _onTargetLanguageChanged,
                ),
              ],
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text('Error: $_error'))
          : Column(
              children: [
                // Input editor (20% of space)
                Expanded(
                  flex: 2,
                  child: Container(
                    margin: const EdgeInsets.all(8.0),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(
                            _sourceLang,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                        Expanded(
                          child: CodeEditor(
                            controller: _inputController,
                            style: CodeEditorStyle(
                              fontSize: 16,
                              fontFamily: 'monospace',
                            ),
                            autocompleteSymbols: false,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Output editor (read-only, 80% of space)
                Expanded(
                  flex: 8,
                  child: Container(
                    margin: const EdgeInsets.all(8.0),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(
                            _targetLang,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                        Expanded(
                          child: CodeEditor(
                            controller: _outputController,
                            readOnly: true,
                            style: CodeEditorStyle(
                              fontSize: 16,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
      floatingActionButton: _isLoading
          ? null
          : FloatingActionButton(
              onPressed: _isTranslating ? null : _translate,
              tooltip: 'Translate',
              child: _isTranslating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.translate),
            ),
    );
  }
}

/// Internal helper for scoring and re-ranking translation results.
class _ScoredResult {
  final TranslationResult result;
  final double score;
  final bool inFts;
  final double lengthPenalty;

  const _ScoredResult({
    required this.result,
    required this.score,
    required this.inFts,
    required this.lengthPenalty,
  });
}
