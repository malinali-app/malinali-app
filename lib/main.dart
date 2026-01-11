// ignore_for_file: implementation_imports
import 'package:flutter/foundation.dart' show compute, kDebugMode;
import 'package:flutter/material.dart';
import 'package:ml_algo/src/persistence/sqlite_neighbor_search_store.dart';
import 'package:ml_algo/src/retrieval/hybrid_fts_searcher.dart';
import 'package:ml_algo/src/retrieval/translation_result.dart';
import 'package:ml_linalg/vector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:malinali/services/embedding_service.dart';
import 'package:malinali/services/query_stemmer.dart';
import 'package:malinali/setup_screen.dart';
import 'package:malinali/services/generate_embeddings.dart';
import 'package:malinali/services/user_input_service.dart';
import 'package:malinali/services/speech_recognition_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';
import 'dart:io';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // SQLite3 is automatically initialized by sqlite3_flutter_libs plugin on Android
  // The plugin handles loading the native library automatically
  
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
        // Use Noto Sans for better Unicode support (especially for Fula characters)
        fontFamily: 'NotoSans',
      ),
      debugShowCheckedModeBanner: false,
      home: const InitialScreen(),
    );
  }
}

/// Initial screen that checks if database exists, shows setup if not
class InitialScreen extends StatefulWidget {
  const InitialScreen({super.key});

  @override
  State<InitialScreen> createState() => _InitialScreenState();
}

class _InitialScreenState extends State<InitialScreen> {
  bool _isChecking = true;

  @override
  void initState() {
    super.initState();
    _checkDatabase();
  }

  Future<void> _checkDatabase() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final dbPath = '${appDir.path}/malinali.db';
      final dbFile = File(dbPath);
      final exists = await dbFile.exists();
      
      // Debug logging
      print('🔍 Checking database at: $dbPath');
      print('   Database exists: $exists');
      if (exists) {
        final stat = await dbFile.stat();
        print('   Database size: ${stat.size} bytes');
        print('   Database modified: ${stat.modified}');
      }

      if (mounted) {
        setState(() {
          _isChecking = false;
        });

        // If database exists and has content (size > 0), go to translation screen
        if (exists) {
          final stat = await dbFile.stat();
          if (stat.size > 0) {
            print('✅ Database found and valid, navigating to TranslationScreen');
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => const TranslationScreen(),
              ),
            );
          } else {
            print('⚠️  Database file exists but is empty, showing setup screen');
          }
        } else {
          print('ℹ️  Database not found, showing setup screen');
        }
      }
    } catch (e) {
      print('❌ Error checking database: $e');
      if (mounted) {
        setState(() {
          _isChecking = false;
        });
      }
    }
  }

  void _onSetupComplete() {
    // Navigate to translation screen when setup is complete
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => const TranslationScreen(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Show setup screen if database doesn't exist
    return SetupScreen(onComplete: _onSetupComplete);
  }
}

class TranslationScreen extends StatefulWidget {
  const TranslationScreen({super.key});

  @override
  State<TranslationScreen> createState() => _TranslationScreenState();
}

class _TranslationScreenState extends State<TranslationScreen> {
  late TextEditingController _inputController;
  late TextEditingController _outputController;
  late FocusNode _inputFocusNode;
  HybridFTSSearcher? _searcher;
  SQLiteNeighborSearchStore? _store; // Keep reference to store to close it properly
  EmbeddingService? _embeddingService;
  UserInputService? _userInputService;
  SpeechRecognitionService? _speechService;
  bool _isLoading = true;
  bool _isTranslating = false;
  bool _isListening = false; // Track if speech recognition is active
  String _sourceLang = 'French';
  String _targetLang = 'Fula'; // Default: French → Fula
  String? _error;
  TranslationDirection _direction = TranslationDirection.frenchToFula;
  bool _hasInputText = false; // Track if input has text for clear button visibility
  String? _statusMessage; // Status message for detailed loader
  int _progressCurrent = 0;
  int _progressTotal = 0;

  // Helper to get display name for UI (keeps logic consistent with 'French'/'Fula')
  String _getDisplayName(String lang) {
    switch (lang) {
      case 'French':
        return 'Français';
      case 'Fula':
        return 'Pulaar';
      default:
        return lang;
    }
  }

  void _toggleDirection() {
    setState(() {
      if (_direction == TranslationDirection.frenchToFula) {
        _direction = TranslationDirection.fulaToFrench;
        _sourceLang = 'Fula';
        _targetLang = 'French';
      } else {
        _direction = TranslationDirection.frenchToFula;
        _sourceLang = 'French';
        _targetLang = 'Fula';
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _inputController = TextEditingController();
    _outputController = TextEditingController();
    _inputFocusNode = FocusNode();
    
    // Track input text changes to show/hide clear button
    _inputController.addListener(() {
      final hasText = _inputController.text.trim().isNotEmpty;
      if (_hasInputText != hasText) {
        setState(() {
          _hasInputText = hasText;
        });
      }
      // Debug: log when text changes
      if (kDebugMode) {
        print('Input text changed: "${_inputController.text}"');
      }
    });
    
    _initializeSearcher();
    
    if(Platform.isAndroid) {
      _initializeSpeechRecognition();
    }
  }

  Future<void> _initializeSpeechRecognition() async {
    try {
      _speechService = SpeechRecognitionService();
      
      // Set up callbacks
      _speechService!.onResult = (text) {
        if (mounted) {
          setState(() {
            _inputController.text = text;
            _isListening = false;
          });
          // Auto-translate after speech recognition
          _translate();
        }
      };
      
      _speechService!.onPartialResult = (text) {
        if (mounted) {
          setState(() {
            _inputController.text = text;
          });
        }
      };
      
      _speechService!.onError = () {
        if (mounted) {
          setState(() {
            _isListening = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Erreur lors de la reconnaissance vocale'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      };
    } catch (e) {
      print('Error initializing speech recognition: $e');
    }
  }

  Future<void> _toggleListening() async {
    if (_speechService == null) {
      await _initializeSpeechRecognition();
    }

    if (_isListening) {
      // Stop listening
      await _speechService!.stopListening();
      setState(() {
        _isListening = false;
      });
    } else {
      // Only allow speech recognition when source language is French
      if (_sourceLang != 'French') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('La reconnaissance vocale est disponible uniquement pour le français'),
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }

      // Start listening
      try {
        await _speechService!.startListening();
        setState(() {
          _isListening = true;
        });
      } catch (e) {
        print('Error starting speech recognition: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _initializeSearcher() async {
    try {
      // Initialize embedding service (ONNX model)
      final embeddingService = EmbeddingService();
      await embeddingService.initialize();

      final appDir = await getApplicationDocumentsDirectory();
      final dbPath = '${appDir.path}/malinali.db';
      final dbFile = File(dbPath);

      // Check if database exists
      if (!await dbFile.exists()) {
        setState(() {
          _error = 'Database not found. Please set up the database first.';
          _isLoading = false;
        });
        return;
      }

      // Close previous store if it exists
      _store?.close();
      _userInputService?.close();
      
      final store = SQLiteNeighborSearchStore(dbPath);
      _store = store; // Keep reference
      
      // Initialize user input service
      _userInputService = UserInputService(dbPath);

      // Load existing searcher from database
      HybridFTSSearcher? searcher;
      try {
        searcher = await HybridFTSSearcher.loadFromStore(store, 'fula');
        print('✅ Loaded existing Fula searcher from database');
      } catch (e) {
        final errorMessage = e.toString();
        // Check if this is a "searcher not found" error
        if (errorMessage.contains('not found') || 
            errorMessage.contains('Searcher with ID')) {
          setState(() {
            _error = 'Searcher with ID "fula" not found in database.\n\n'
                'This usually happens when:\n'
                '1. The database was created with a different model version\n'
                '2. The database needs to be regenerated\n\n'
                'Solution: Please regenerate the database using the Setup screen.\n'
                'Go back and select "Use Default Demo" or select your text files again.';
            _isLoading = false;
          });
        } else {
          setState(() {
            _error = 'Failed to load searcher from database: $e';
            _isLoading = false;
          });
        }
        return;
      }

      setState(() {
        _searcher = searcher;
        _embeddingService = embeddingService;
        _isLoading = false;
        _statusMessage = null; // Clear status message after successful initialization
        _progressCurrent = 0;
        _progressTotal = 0;
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
      // Generate embedding using ONNX model (only needed for semantic search)
      // Skip for Fula → French/English since we only use keyword search
      Vector? queryEmbedding;
      if (_sourceLang != 'Fula') {
        // Only generate embedding if we're doing semantic search
        if (_embeddingService != null) {
          // Use real ONNX model embedding
          queryEmbedding = await _embeddingService!.generateEmbedding(
            inputText,
          );
        } else {
          // Fallback: simple hash-based embedding (shouldn't happen if initialized)
          final embedding = List<double>.generate(384, (i) {
            final hash = (inputText.hashCode + i * 1000).abs();
            return (hash % 1000) / 1000.0;
          });
          queryEmbedding = Vector.fromList(embedding);
        }
      }

      // Handle different translation directions
      // Database structure: sourceText = English/French (source), targetText = Fula (target)
      List<TranslationResult> results;
      List<TranslationResult> ftsResults = [];
      List<TranslationResult> semanticResultsFinal = [];
      bool hasExactFtsMatch = false;
      // Track FTS indices to check if results have FTS backing (for distance threshold check)
      Set<int> ftsIndices = <int>{};

      if (_sourceLang == 'Fula') {
        // Fula → English/French: Search in targetText (Fula), return sourceText (English/French)
        // Skip semantic search since embeddings are stored for French (source), not Fula (target)
        // Use keyword search only - FTS searches both sourceText and targetText
        print(
          'DEBUG: Fula → ${_targetLang}: Using keyword search only (no semantic search - embeddings are for French, not Fula)',
        );

        // Use keyword search - FTS will match Fula text in targetText column
        final keywordResults = await _searcher!.searchByKeyword(
          inputText,
          k: 20,
        );
        print('DEBUG: Keyword search found ${keywordResults.length} results');

        // Also search user inputs
        List<TranslationResult> userInputResults = [];
        if (_userInputService != null) {
          final userInputs = _userInputService!.searchUserInputs(inputText);
          // Convert user inputs to TranslationResult format
          // For Fula → French/English, user inputs have sourceText = Fula, targetText = French/English
          for (var i = 0; i < userInputs.length; i++) {
            final input = userInputs[i];
            // Check if the user input matches the target language
            final matchesTarget = _targetLang == 'English'
                ? (input['sourceLang'] == 'Fula' || input['targetLang'] == 'English')
                : (input['sourceLang'] == 'Fula' || input['targetLang'] == 'French');
            
            if (matchesTarget || input['sourceLang'] == null) {
              // Create a pseudo TranslationResult for user input
              // We'll use a special pointIndex (negative) to identify user inputs
              userInputResults.add(
                TranslationResult(
                  sourceText: input['targetText'] as String, // Target language text
                  targetText: input['sourceText'] as String, // Fula text (what user searched)
                  distance: 0.0, // User inputs get priority (distance 0)
                  pointIndex: -(input['id'] as int), // Negative index for user inputs
                ),
              );
            }
          }
          print('DEBUG: User input search found ${userInputResults.length} results');
        }

        // Filter results to match target language (English or French)
        // Results have: sourceText = French/English, targetText = Fula (what user searched for)
        if (_targetLang == 'English') {
          // Filter to show only English results (heuristic: no French characters)
          results = keywordResults.where((r) {
            final text = r.sourceText.toLowerCase();
            return !text.contains('é') &&
                !text.contains('è') &&
                !text.contains('ê') &&
                !text.contains('à') &&
                !text.contains('ç') &&
                !text.contains('ù');
          }).toList();
        } else if (_targetLang == 'French') {
          // Filter to show only French results (heuristic: has French characters or common French words)
          results = keywordResults.where((r) {
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
        } else {
          // No filtering needed if target is Fula (shouldn't happen in this branch)
          results = keywordResults;
        }

        // Add user inputs at the beginning (they have priority)
        results = [...userInputResults, ...results];

        // Look for exact match
        TranslationResult? exactMatch;
        final normalizedInput = inputText.trim().toLowerCase();
        for (final r in results) {
          final normalizedTarget = r.targetText.trim().toLowerCase();
          if (normalizedTarget == normalizedInput) {
            exactMatch = r;
            break;
          }
        }

        results = results.take(3).toList(); // Limit to 3 results
        print('DEBUG: After language filtering: ${results.length} results');
        for (var i = 0; i < results.length; i++) {
          final r = results[i];
          print('  ${i + 1}. "${r.targetText}" → "${r.sourceText}"');
        }

        // For Fula → English/French, we only use keyword search (no semantic search)
        ftsResults = results;
        semanticResultsFinal = [];
        hasExactFtsMatch = exactMatch != null;
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

        // Also search user inputs
        List<TranslationResult> userInputResults = [];
        if (_userInputService != null) {
          final userInputs = _userInputService!.searchUserInputs(inputText);
          // Convert user inputs to TranslationResult format
          // For French/English → Fula, user inputs have sourceText = French/English, targetText = Fula
          for (var i = 0; i < userInputs.length; i++) {
            final input = userInputs[i];
            // Check if the user input matches the source language
            final matchesSource = _sourceLang == 'English'
                ? (input['sourceLang'] == 'English' || input['sourceLang'] == null)
                : (input['sourceLang'] == 'French' || input['sourceLang'] == null);
            
            if (matchesSource) {
              // Create a pseudo TranslationResult for user input
              userInputResults.add(
                TranslationResult(
                  sourceText: input['sourceText'] as String, // Source language text
                  targetText: input['targetText'] as String, // Fula text
                  distance: 0.0, // User inputs get priority (distance 0)
                  pointIndex: -(input['id'] as int), // Negative index for user inputs
                ),
              );
            }
          }
          print('DEBUG: User input search found ${userInputResults.length} results');
        }

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
        // queryEmbedding should not be null here since we're not in Fula → French/English branch
        final semanticResults = await _searcher!.searchBySemantic(
          queryEmbedding!,
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
        // Add user inputs first (they have priority), then regular results
        if (exactKeywordMatch != null) {
          final exactMatch = exactKeywordMatch;
          ftsResults = [
            ...userInputResults,
            exactMatch,
            ...filteredKeywordResults
                .where((r) => r.pointIndex != exactMatch.pointIndex)
                .take(2),
          ].take(3).toList();
          hasExactFtsMatch = true;
        } else {
          ftsResults = [...userInputResults, ...filteredKeywordResults].take(3).toList();
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
        if (_direction == TranslationDirection.fulaToFrench) {
          // When translating FROM Fula, the source phrase is in targetText (Fula)
          return result.targetText;
        } else {
          // When translating FROM English/French, the source phrase is in sourceText
          return result.sourceText;
        }
      }

      String getTargetText(TranslationResult result) {
        if (_direction == TranslationDirection.frenchToFula) {
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
        // Debug: log what we're displaying
        print(
          'DEBUG formatResult: sourceLang=$_sourceLang, targetLang=$_targetLang, '
          'result.sourceText="${result.sourceText.substring(0, result.sourceText.length > 50 ? 50 : result.sourceText.length)}...", '
          'result.targetText="${result.targetText.substring(0, result.targetText.length > 50 ? 50 : result.targetText.length)}...", '
          'display source="$source", display target="$target"',
        );
        final prefix = isExact ? '⭐ ' : '${index + 1}. ';
        return '$prefix$source → $target';
      }

      // Build Semantic column (first - better results)
      buffer.writeln('✨ Semantic');
      if (semanticResultsFinal.isEmpty) {
        buffer.writeln('Aucun résultat');
      } else {
        for (var i = 0; i < semanticResultsFinal.length; i++) {
          buffer.writeln(formatResult(semanticResultsFinal[i], i, false));
        }
      }

      // Build FTS column (second - keyword results)
      buffer.writeln('');
      buffer.writeln('🔤 Keyword');
      if (ftsResults.isEmpty) {
        buffer.writeln('Aucun résultat');
      } else {
        for (var i = 0; i < ftsResults.length; i++) {
          final isExact = hasExactFtsMatch && i == 0;
          buffer.writeln(formatResult(ftsResults[i], i, isExact));
        }
      }

      _outputController.text = buffer.toString().trim();
      buffer.writeln('');
      buffer.writeln('');
    } catch (e) {
      _outputController.text = 'Error: $e';
    } finally {
      setState(() {
        _isTranslating = false;
      });
    }
  }


  /// Share all user inputs
  Future<void> _shareUserInputs() async {
    final box = context.findRenderObject() as RenderBox?;
    if (_userInputService == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Service non initialisé.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final count = _userInputService!.getUserInputCount();
    if (count == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aucune entrée utilisateur à partager.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    try {
      // Get all user inputs
      final inputs = _userInputService!.getAllUserInputs();
      
      // Prepare source and target texts
      final sourceTexts = <String>[];
      final targetTexts = <String>[];
      
      for (final input in inputs) {
        sourceTexts.add(input['sourceText'] as String);
        targetTexts.add(input['targetText'] as String);
      }
      
      // Create files in application documents directory (like weebi pattern)
      final appDir = await getApplicationDocumentsDirectory();
      final sourceFile = File('${appDir.path}${Platform.pathSeparator}source.txt');
      final targetFile = File('${appDir.path}${Platform.pathSeparator}target.txt');
      
      // Write source.txt (one translation per line with "- " prefix)
      final sourceBuffer = StringBuffer();
      for (final sourceText in sourceTexts) {
        sourceBuffer.writeln(sourceText);
      }
      final sourceF = await compute(_writeFile, _FileWriteData(sourceFile.path, sourceBuffer.toString()));
      final sourceFX = XFile(sourceF.path);
      
      // Write target.txt (one translation per line with "- " prefix)
      final targetBuffer = StringBuffer();
      for (final targetText in targetTexts) {
        targetBuffer.writeln(targetText);
      }
      final targetF = await compute(_writeFile, _FileWriteData(targetFile.path, targetBuffer.toString()));
      final targetFX = XFile(targetF.path);
      
      // Share both files as XFile objects (matching weebi pattern)
      await Share.shareXFiles(
        [sourceFX, targetFX],
        text: 'Mes traductions Malinali ($count entrées)',
        subject: 'Mes traductions Malinali ($count entrées)',
        sharePositionOrigin: box != null ? box.localToGlobal(Offset.zero) & box.size : null,
      );
      
      // Clean up temporary files after a delay (to allow sharing to complete)
      Future.delayed(const Duration(seconds: 5), () async {
        try {
          if (await sourceFile.exists()) await sourceFile.delete();
          if (await targetFile.exists()) await targetFile.delete();
        } catch (e) {
          // Ignore cleanup errors
          if (kDebugMode) print('Error cleaning up temp files: $e');
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors du partage: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    _outputController.dispose();
    _inputFocusNode.dispose();
    _embeddingService?.dispose();
    _store?.close(); // Close database connection
    _userInputService?.close(); // Close user input service
    if(Platform.isAndroid) {
      _speechService?.dispose(); // Dispose speech recognition service
    }
    super.dispose();
  }

  Future<void> _goToSetup() async {
    // Delete the database so setup screen will be shown
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final dbPath = '${appDir.path}/malinali.db';
      final dbFile = File(dbPath);
      if (await dbFile.exists()) {
        await dbFile.delete();
        print('✅ Deleted database to trigger setup screen');
      }
    } catch (e) {
      print('Warning: Could not delete database: $e');
    }
    
    // Navigate back to initial screen (which will show setup)
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => const InitialScreen(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget bodyContent;
    if (_isLoading) {
      // Show detailed loader with progress if available
      if (_statusMessage != null) {
        bodyContent = Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Column(
                    children: [
                      Text(
                        _statusMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 14),
                      ),
                      if (_progressTotal > 0) ...[
                        const SizedBox(height: 12),
                        LinearProgressIndicator(
                          value: _progressCurrent / _progressTotal,
                          backgroundColor: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '$_progressCurrent / $_progressTotal',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        bodyContent = const Center(child: CircularProgressIndicator());
      }
    } else if (_error != null) {
      bodyContent = Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 64,
                color: Colors.red,
              ),
              const SizedBox(height: 24),
              Text(
                'Error',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
              ),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _goToSetup,
                icon: const Icon(Icons.settings),
                label: const Text('Go to Setup'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      bodyContent = Column(
        children: [
          // Language direction switcher at the top with settings button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            child: Row(
              children: [
                Expanded(
                  child: _LanguageDirectionSwitcher(
                    direction: _direction,
                    onToggle: _toggleDirection,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.settings),
                  onPressed: _showSettingsDialog,
                  tooltip: 'Paramètres',
                ),
              ],
            ),
          ),
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
                      _getDisplayName(_sourceLang),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Stack(
                      children: [
                        TextField(
                          controller: _inputController,
                          focusNode: _inputFocusNode,
                          autofocus: true,
                          maxLines: null,
                          expands: true,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _translate(),
                          style: const TextStyle(
                            fontSize: 16,
                            fontFamily: 'NotoSans',
                          ),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.all(12.0),
                            hintText: 'Tapez votre texte ici...',
                          ),
                        ),
                        // Mic button - bottom right corner, only visible when source is French
                        if (_sourceLang == 'French' && Platform.isAndroid)
                          Positioned(
                            bottom: 8,
                            right: 8,
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: _isTranslating ? null : _toggleListening,
                                borderRadius: BorderRadius.circular(24),
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: _isListening 
                                        ? Colors.red.shade100.withOpacity(0.9)
                                        : Colors.blue.shade100.withOpacity(0.9),
                                    borderRadius: BorderRadius.circular(24),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.1),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    _isListening ? Icons.mic : Icons.mic_none,
                                    size: 24,
                                    color: _isListening ? Colors.red : Colors.blue,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        // Clear button - bottom right, above mic button when mic is visible, otherwise bottom right
                        if (_hasInputText)
                          Positioned(
                            bottom: _sourceLang == 'French' && Platform.isAndroid ? 50 : 8,
                            right: 8,
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () {
                                  _inputController.clear();
                                  _inputFocusNode.requestFocus();
                                },
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade200.withOpacity(0.9),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Icon(
                                    Icons.clear,
                                    size: 18,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4.0),
          // Translate button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isTranslating ? null : _translate,
                icon: _isTranslating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow),
                label: const Text('Traduire'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  elevation: 2,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4.0),
          // Output editor (read-only, 80% of space)
          Expanded(
            flex: 6,
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
                      _getDisplayName(_targetLang),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _outputController,
                      readOnly: true,
                      maxLines: null,
                      expands: true,
                      style: const TextStyle(
                        fontSize: 16,
                        fontFamily: 'NotoSans',
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.all(12.0),
                        //hintText: 'La traduction apparaîtra ici...',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Scaffold(
      body: SafeArea(child: bodyContent),
    );
  }

  Future<void> _showSettingsDialog() async {
    final option = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Paramètres'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.save),
              title: const Text('Enregistrer une traduction'),
              subtitle: const Text('Ajouter une entrée source/target'),
              onTap: () => Navigator.of(context).pop('save'),
            ),
            if (_userInputService != null && _userInputService!.getUserInputCount() > 0)
              ListTile(
                leading: const Icon(Icons.share),
                title: const Text('Partager mes traductions'),
                subtitle: Text('${_userInputService!.getUserInputCount()} entrées'),
                onTap: () => Navigator.of(context).pop('share'),
              ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.storage),
              title: const Text('Sélectionner une base de données SQLite'),
              onTap: () => Navigator.of(context).pop('database'),
            ),
            ListTile(
              leading: const Icon(Icons.text_snippet),
              title: const Text('Sélectionner des fichiers source/cible'),
              onTap: () => Navigator.of(context).pop('files'),
            ),
          ],
        ),
      ),
    );

    if (option == null) return;

    if (option == 'save') {
      await _showSaveTranslationDialog();
    } else if (option == 'share') {
      await _shareUserInputs();
    } else if (option == 'database' || option == 'files') {
      // Show warning dialog for database/file operations
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Attention'),
          content: const Text(
            'Toutes les données actuelles seront perdues. '
            'Voulez-vous continuer ?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Continuer'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      if (option == 'database') {
        await _selectDatabase();
      } else if (option == 'files') {
        await _selectTextFiles();
      }
    }
  }

  /// Show dialog to save a translation (with form for source and target text)
  Future<void> _showSaveTranslationDialog() async {
    final sourceController = TextEditingController();
    final targetController = TextEditingController();
    bool sourceHasText = false;
    bool targetHasText = false;

    // Listen to text changes
    void updateButtonState() {
      final newSourceHasText = sourceController.text.trim().isNotEmpty;
      final newTargetHasText = targetController.text.trim().isNotEmpty;
      if (newSourceHasText != sourceHasText || newTargetHasText != targetHasText) {
        sourceHasText = newSourceHasText;
        targetHasText = newTargetHasText;
        // Force rebuild of dialog
        // Note: This is a simplified approach - in production you might want to use StatefulBuilder
      }
    }

    sourceController.addListener(updateButtonState);
    targetController.addListener(updateButtonState);

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          // Update state when text changes
          sourceController.addListener(() {
            setState(() {});
          });
          targetController.addListener(() {
            setState(() {});
          });

          final canSave = sourceController.text.trim().isNotEmpty &&
              targetController.text.trim().isNotEmpty;

          return AlertDialog(
            title: const Text('Enregistrer une traduction'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Source (${_getDisplayName(_sourceLang)})',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: sourceController,
                    autofocus: true,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: 'Texte source...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Cible (${_getDisplayName(_targetLang)})',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: targetController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: 'Texte cible...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Annuler'),
              ),
              ElevatedButton(
                onPressed: canSave
                    ? () => Navigator.of(context).pop(true)
                    : null,
                child: const Text('Enregistrer'),
              ),
            ],
          );
        },
      ),
    );

    sourceController.removeListener(updateButtonState);
    targetController.removeListener(updateButtonState);

    if (result == true) {
      final sourceText = sourceController.text.trim();
      final targetText = targetController.text.trim();

      if (sourceText.isEmpty || targetText.isEmpty) {
        return;
      }

      if (_userInputService == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Service non initialisé.'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }

      try {
        await _userInputService!.addUserInput(
          sourceText: sourceText,
          targetText: targetText,
          sourceLang: _sourceLang,
          targetLang: _targetLang,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Traduction enregistrée (${_userInputService!.getUserInputCount()} entrées au total)',
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erreur lors de l\'enregistrement: $e'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }

    sourceController.dispose();
    targetController.dispose();
  }

  Future<void> _selectDatabase() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
        _statusMessage = 'Copie de la base de données...';
        _progressCurrent = 0;
        _progressTotal = 0;
      });

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['db', 'sqlite'],
      );

      if (result == null || result.files.single.path == null) {
        setState(() {
          _isLoading = false;
          _statusMessage = null;
        });
        return;
      }

      final selectedPath = result.files.single.path!;
      final appDir = await getApplicationDocumentsDirectory();
      final targetPath = '${appDir.path}/malinali.db';

      // Close current searcher and store to release database lock
      _searcher = null;
      _store?.close();
      _store = null;
      
      // Wait a bit to ensure file handles are released
      await Future.delayed(const Duration(milliseconds: 100));

      // Delete existing database
      final targetFile = File(targetPath);
      if (await targetFile.exists()) {
        await targetFile.delete();
      }

      // Copy selected database
      await File(selectedPath).copy(targetPath);
      print('✅ Database copied to: $targetPath');
      
      setState(() {
        _statusMessage = 'Chargement de la base de données...';
      });

      // Reinitialize searcher
      await _initializeSearcher();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Erreur lors de la sélection de la base de données: $e';
        _statusMessage = null;
      });
    }
  }

  Future<void> _selectTextFiles() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
        _statusMessage = 'Veuillez sélectionner le fichier source (ex. Français)...';
        _progressCurrent = 0;
        _progressTotal = 0;
      });

      // Select source file
      final sourceResult = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt'],
      );

      if (sourceResult == null || sourceResult.files.single.path == null) {
        setState(() {
          _isLoading = false;
          _statusMessage = null;
        });
        return;
      }

      final sourcePath = sourceResult.files.single.path!;

      setState(() {
        _statusMessage = 'Veuillez sélectionner le fichier cible (ex. Pulaar)...';
      });

      // Select target file
      final targetResult = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt'],
      );

      if (targetResult == null || targetResult.files.single.path == null) {
        setState(() {
          _isLoading = false;
          _statusMessage = null;
        });
        return;
      }

      final targetPath = targetResult.files.single.path!;

      // Close current searcher and store to release database lock
      _searcher = null;
      _store?.close();
      _store = null;
      
      // Wait a bit to ensure file handles are released
      await Future.delayed(const Duration(milliseconds: 100));

      // Delete existing database
      final appDir = await getApplicationDocumentsDirectory();
      final dbPath = '${appDir.path}/malinali.db';
      final dbFile = File(dbPath);
      if (await dbFile.exists()) {
        await dbFile.delete();
      }

      // Validate line counts
      setState(() {
        _statusMessage = 'Validation des fichiers...';
      });

      final sourceFile = File(sourcePath);
      final targetFile = File(targetPath);
      final sourceContent = await sourceFile.readAsString();
      final targetContent = await targetFile.readAsString();
      final sourceLines = sourceContent
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      final targetLines = targetContent
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();

      if (sourceLines.length != targetLines.length) {
        setState(() {
          _isLoading = false;
          _error = 'Erreur : Les fichiers ont un nombre de lignes différent.\n'
              'Source : ${sourceLines.length}, Cible : ${targetLines.length}';
          _statusMessage = null;
        });
        return;
      }

      // Generate embeddings from files
      setState(() {
        _statusMessage = 'Génération des embeddings (cela peut prendre un moment)...';
        _progressCurrent = 0;
        _progressTotal = sourceLines.length;
      });

      await generateEmbeddingsFromFiles(
        sourceFilePath: sourcePath,
        targetFilePath: targetPath,
        dbPath: dbPath,
        searcherId: 'fula',
        onProgress: (current, total) {
          if (mounted) {
            setState(() {
              _progressCurrent = current;
              _progressTotal = total;
              _statusMessage =
                  'Génération des embeddings : $current / $total (${((current / total) * 100).toStringAsFixed(1)}%)';
            });
          }
        },
      );
      
      setState(() {
        _statusMessage = 'Chargement de la base de données...';
      });

      print('✅ Database created from text files');

      // Reinitialize searcher
      await _initializeSearcher();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Erreur lors de la génération de la base de données: $e';
        _statusMessage = null;
      });
    }
  }
}

enum TranslationDirection { frenchToFula, fulaToFrench }

class _LanguageDirectionSwitcher extends StatelessWidget {
  const _LanguageDirectionSwitcher({
    required this.direction,
    required this.onToggle,
  });

  final TranslationDirection direction;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final isFrenchToFula = direction == TranslationDirection.frenchToFula;
    final label = isFrenchToFula
        ? 'Français → Pulaar'
        : 'Pulaar → Français'; // french => fula

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
        ),
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

/// Helper class for file writing with compute
class _FileWriteData {
  final String path;
  final String content;

  _FileWriteData(this.path, this.content);
}

/// Helper function for writing files using compute (matching weebi pattern)
Future<File> _writeFile(_FileWriteData data) async {
  final file = File(data.path);
  await file.writeAsString(data.content);
  return file;
}
