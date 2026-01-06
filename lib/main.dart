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
  String _targetLang = 'Fula';
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
      // Database structure: frenchText = English/French (source), englishText = Fula (target)
      List<TranslationResult> results;
      String resultSource = '';

      if (_sourceLang == 'Fula') {
        // Fula → English/French: Search in englishText (Fula), return frenchText (English/French)
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
            '  ${i + 1}. "${r.englishText}" → "${r.frenchText}" (distance: ${r.distance.toStringAsFixed(4)})',
          );
        }

        // Filter results to match target language (English or French)
        // Note: This is a simple heuristic - in production you might want more sophisticated filtering
        if (_targetLang == 'English') {
          // Filter to show only English results (heuristic: no French characters)
          results = results.where((r) {
            final text = r.frenchText.toLowerCase();
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
            final text = r.frenchText.toLowerCase();
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
        results = results.take(5).toList(); // Limit to 5 results
        print('DEBUG: After language filtering: ${results.length} results');
        for (var i = 0; i < results.length; i++) {
          final r = results[i];
          print(
            '  ${i + 1}. "${r.englishText}" → "${r.frenchText}" (distance: ${r.distance.toStringAsFixed(4)})',
          );
        }
      } else {
        // English/French → Fula: Search in frenchText (English/French), return englishText (Fula)
        // Stem query for FTS to handle word variations
        final stemmedQuery = QueryStemmer.stemQuery(inputText);

        // Use hybrid search: keyword filtering + semantic ranking
        // FTS uses stemmed query, semantic uses original embedding
        final keywordResults = await _searcher!.searchByKeyword(
          stemmedQuery,
          k: 5,
        );
        print(
          'DEBUG: Keyword search (stemmed: "$stemmedQuery") found ${keywordResults.length} results',
        );
        if (keywordResults.isNotEmpty) {
          print('DEBUG: FTS matches:');
          for (var i = 0; i < keywordResults.length; i++) {
            final r = keywordResults[i];
            print(
              '  ${i + 1}. "${r.frenchText}" → "${r.englishText}" (distance: ${r.distance.toStringAsFixed(4)})',
            );
          }
        }

        if (keywordResults.isNotEmpty) {
          // FTS found results - use hybrid search with larger search radius
          // Use stemmed query for FTS, original embedding for semantic
          results = await _searcher!.searchHybrid(
            keyword: stemmedQuery, // Use stemmed for FTS
            embedding: queryEmbedding, // Original embedding for semantic
            k: 5,
            searchRadius: 10, // Increase radius for cross-language similarity
          );

          // If hybrid still finds nothing, fallback to keyword-only
          // (This can happen when embeddings are in different languages)
          if (results.isEmpty) {
            print('DEBUG: Hybrid found 0, using keyword-only results');
            results = keywordResults;
            resultSource = 'FTS (keyword-only)';
          } else {
            resultSource = 'Hybrid (FTS + Semantic)';
            print(
              'DEBUG: Hybrid search results (FTS filtered + Semantic ranked):',
            );
            for (var i = 0; i < results.length; i++) {
              final r = results[i];
              print(
                '  ${i + 1}. "${r.frenchText}" → "${r.englishText}" (distance: ${r.distance.toStringAsFixed(4)})',
              );
            }
          }
        } else {
          // No FTS results, try semantic-only search
          results = await _searcher!.searchBySemantic(
            queryEmbedding,
            k: 5,
            searchRadius: 10,
          );
          resultSource = 'Semantic (embedding)';
          print('DEBUG: Semantic-only search results:');
          for (var i = 0; i < results.length; i++) {
            final r = results[i];
            print(
              '  ${i + 1}. "${r.frenchText}" → "${r.englishText}" (distance: ${r.distance.toStringAsFixed(4)})',
            );
          }
        }
      }

      print('DEBUG: Final results: ${results.length} from $resultSource');

      if (results.isEmpty) {
        _outputController.text = 'No translation found';
        print('DEBUG: No translation found');
      } else {
        // Determine which field to display based on target language
        // Database structure:
        // - frenchText: contains English or French (source)
        // - englishText: contains Fula (target)
        String getTargetText(TranslationResult result) {
          if (_targetLang == 'Fula') {
            return result.englishText; // Fula is in englishText
          } else {
            // Target is English or French, which is in frenchText
            // But we need to filter: if target is English, only show English results
            // For now, return frenchText (will contain both English and French)
            return result.frenchText;
          }
        }

        // Log the selected translation
        final selectedResult = results.first;
        print('DEBUG: Selected translation:');
        print('  Source: "${selectedResult.frenchText}"');
        print('  Target: "${getTargetText(selectedResult)}"');
        print('  Distance: ${selectedResult.distance.toStringAsFixed(4)}');
        print('  Method: $resultSource');

        // Build output with method explanation
        final buffer = StringBuffer();

        // Add method explanation
        String getMethodExplanation(String source) {
          if (source.contains('Hybrid')) {
            return '🔍 Hybrid Search (FTS + Semantic)\n'
                '   • FTS: Keyword matching (exact word matches)\n'
                '   • Semantic: Meaning-based similarity (AI embeddings)\n'
                '   • Results ranked by semantic similarity';
          } else if (source.contains('FTS') || source.contains('keyword')) {
            return '🔤 Keyword Search (FTS)\n'
                '   • Finds translations by matching keywords\n'
                '   • Fast and precise for exact matches';
          } else if (source.contains('Semantic')) {
            return '🧠 Semantic Search\n'
                '   • Finds translations by meaning similarity\n'
                '   • Uses AI embeddings to understand context\n'
                '   • Works even without exact word matches';
          }
          return 'Search method: $source';
        }

        buffer.writeln(getMethodExplanation(resultSource));
        buffer.writeln('');

        if (results.length == 1) {
          buffer.writeln('${getTargetText(results.first)}');
        } else {
          // Multiple results - display all with numbering
          print('DEBUG: Showing ${results.length} results to user');
          for (var i = 0; i < results.length; i++) {
            final result = results[i];
            buffer.writeln('${i + 1}. ${getTargetText(result)}');
          }
        }

        _outputController.text = buffer.toString().trim();
      }
    } catch (e) {
      _outputController.text = 'Error: $e';
    } finally {
      setState(() {
        _isTranslating = false;
      });
    }
  }

  void _swapLanguages() {
    setState(() {
      // Allow all combinations: English ↔ French ↔ Fula
      // Cycle through: English → French → Fula → English
      if (_sourceLang == 'English' && _targetLang == 'Fula') {
        _sourceLang = 'French';
        // _targetLang stays 'Fula'
      } else if (_sourceLang == 'French' && _targetLang == 'Fula') {
        _sourceLang = 'Fula';
        _targetLang = 'English';
      } else if (_sourceLang == 'Fula' && _targetLang == 'English') {
        _sourceLang = 'Fula';
        _targetLang = 'French';
      } else if (_sourceLang == 'Fula' && _targetLang == 'French') {
        _sourceLang = 'English';
        _targetLang = 'Fula';
      } else {
        // Fallback: just swap
        final temp = _sourceLang;
        _sourceLang = _targetLang;
        _targetLang = temp;
      }

      // Swap input and output
      final tempText = _inputController.text;
      _inputController.text = _outputController.text;
      _outputController.text = tempText;
    });
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
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _sourceLang,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.swap_horiz),
                    onPressed: _swapLanguages,
                    tooltip: 'Swap languages',
                  ),
                  Text(
                    _targetLang,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
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
                // Input editor
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
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Output editor (read-only)
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
