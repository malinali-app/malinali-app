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
  String _sourceLang = 'English';
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

      // Use hybrid search: keyword filtering + semantic ranking
      // For debugging: try keyword-only first to see if FTS works
      final keywordResults = await _searcher!.searchByKeyword(inputText, k: 5);
      print('DEBUG: Keyword search found ${keywordResults.length} results');

      List<TranslationResult> results;
      if (keywordResults.isNotEmpty) {
        // FTS found results - use hybrid search with larger search radius
        // for multilingual models (French embedding vs English embeddings)
        results = await _searcher!.searchHybrid(
          keyword: inputText,
          embedding: queryEmbedding,
          k: 5,
          searchRadius: 10, // Increase radius for cross-language similarity
        );

        // If hybrid still finds nothing, fallback to keyword-only
        // (This can happen when embeddings are in different languages)
        if (results.isEmpty) {
          print('DEBUG: Hybrid found 0, using keyword-only results');
          results = keywordResults;
        }
      } else {
        // No FTS results, try semantic-only search
        results = await _searcher!.searchBySemantic(
          queryEmbedding,
          k: 5,
          searchRadius: 10,
        );
      }

      print('DEBUG: Final results: ${results.length}');

      if (results.isEmpty) {
        _outputController.text = 'No translation found';
      } else if (results.length == 1) {
        // Single result - always return Fula (target language)
        // results.first.englishText is Fula, results.first.frenchText is source (English/French)
        _outputController.text = results.first.englishText;
      } else {
        // Multiple results - display all with numbering (always show Fula)
        final buffer = StringBuffer();
        for (var i = 0; i < results.length; i++) {
          final result = results[i];
          // Always show Fula (target language) in results
          buffer.writeln('${i + 1}. ${result.englishText}');
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
      final temp = _sourceLang;
      _sourceLang = _targetLang;
      _targetLang = temp;

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
