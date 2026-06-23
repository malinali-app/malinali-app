// ignore_for_file: implementation_imports
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:malinali/services/database_bootstrap.dart';
import 'package:malinali/services/search_index_service.dart';
import 'package:malinali/services/search_service.dart';
// import 'package:malinali/setup_screen.dart';
import 'package:malinali/services/speech_recognition_service.dart';
import 'package:malinali/services/storage_service.dart';
import 'package:malinali/services/sync_database_access.dart';
import 'package:malinali/services/app_log.dart';
import 'package:malinali/services/replica_storage.dart';
import 'package:malinali/services/turso_sync_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:async';
import 'dart:io';


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

/// Prepares the local database, then opens the translator.
class InitialScreen extends StatefulWidget {
  const InitialScreen({super.key});

  @override
  State<InitialScreen> createState() => _InitialScreenState();
}

class _InitialScreenState extends State<InitialScreen> {
  String _status = 'Démarrage...';
  String? _error;

  @override
  void initState() {
    super.initState();
    _prepareLocalDatabase();
  }

  Future<bool> _seedFromBundledAssets(String appDbPath, {int? maxRows}) async {
    await DatabaseBootstrap.createEmptySchema(appDbPath);
    final seeded = await DatabaseBootstrap.seedDictionaryFromBundledAssets(
      appDbPath,
      maxRows: maxRows,
    );
    if (seeded) {
      await SearchIndexService.rebuild(appDbPath);
      AppLog.info('Dictionnaire chargé depuis les assets');
    }
    return seeded;
  }

  Future<void> _setStatus(String status) async {
    if (!mounted) {
      return;
    }
    setState(() {
      _status = status;
    });
  }

  Future<void> _prepareLocalDatabase() async {
    try {
      AppLog.info('Préparation de la base locale...');
      await _setStatus('Chargement des identifiants...');

      final appDbPath = await StorageService.getAppDatabasePath();
      await SyncDatabaseAccess.ensureParentDirectory(appDbPath);
      final appDbFile = File(appDbPath);
      var hasLocalDb = await appDbFile.exists();

      if (hasLocalDb) {
        final stat = await appDbFile.stat();
        if (stat.size == 0) {
          await ReplicaStorage.deleteReplicaArtifacts(appDbPath);
          hasLocalDb = false;
        }
      }

      final hasLocalData = hasLocalDb &&
          await SearchIndexService.databaseHasTranslationData(appDbPath);

      // We no longer force a heavy sync on first run if it's slow.
      // We just ensure the schema exists and move to the main screen.
      if (!hasLocalDb) {
        await _setStatus('Initialisation de la base de données...');
        await DatabaseBootstrap.createEmptySchema(appDbPath);
        
        // Seed a tiny bit so the app isn't totally empty on first run
        if (!TursoSyncService.isConfigured) {
          await _seedFromBundledAssets(appDbPath, maxRows: 100);
        }
      }

      if (hasLocalData) {
        await _setStatus('Vérification de l\'index...');
        await SearchIndexService.rebuildIfNeeded(appDbPath);
      }

      await DatabaseBootstrap.ensureDataSources(appDbPath);

      AppLog.info('Préparation terminée, ouverture de l\'application');
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const TranslationScreen(databaseReady: true),
          ),
        );
      }
    } catch (e, stackTrace) {
      AppLog.error('Échec préparation', e, stackTrace);
      if (mounted) {
        setState(() {
          _error = e.toString();
          _status = 'Erreur';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _error = null;
                      _status = 'Nouvelle tentative...';
                    });
                    _prepareLocalDatabase();
                  },
                  child: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _status,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TranslationScreen extends StatefulWidget {
  /// When true, the database was prepared on [InitialScreen]; skip full-screen loader.
  final bool databaseReady;

  const TranslationScreen({super.key, this.databaseReady = false});

  @override
  State<TranslationScreen> createState() => _TranslationScreenState();
}

class _TranslationScreenState extends State<TranslationScreen> {
  late TextEditingController _inputController;
  late TextEditingController _outputController;
  late FocusNode _inputFocusNode;
  SearchService? _searchService;
  SpeechRecognitionService? _speechService;
  bool _isLoading = false;
  bool _isInitializingSearcher = false;
  bool _isTranslating = false;
  bool _isListening = false; // Track if speech recognition is active
  bool _isDatabaseEmpty = false; // Track if the database has no translation data
  static const String _sourceLang = 'French';
  static const String _targetLang = 'Fula';
  String? _error;
  bool _hasInputText =
      false; // Track if input has text for clear button visibility
  String? _statusMessage; // Status message for detailed loader

  List<SearchResult> _searchResults = [];
  List<LexicalTokenMatch> _lexicalMatches = [];

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

    //  Error starting speech recognition: Exception: Speech recognition is only supported on Android. For other platforms, use the record package.
    if (Platform.isAndroid) {
      _initializeSpeechRecognition();
    }
  }

  Future<void> _initializeSpeechRecognition() async {
    try {
      _speechService = SpeechRecognitionService();

      // Set up callbacks
      _speechService!.onResult = (text) async {
        if (mounted) {
          setState(() {
            _inputController.text = text;
            _isListening = false;
          });
          // Stop listening before translation to prevent background recording
          await _speechService!.stopListening();
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
            content: Text(
              'La reconnaissance vocale est disponible uniquement pour le français',
            ),
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

  Future<void> _initializeSearcher({
    bool requireTursoSync = false,
    void Function(int processed, int total)? onProgress,
  }) async {
    try {
      setState(() {
        _error = null;
        if (requireTursoSync) {
          _isLoading = true;
          _statusMessage = 'Synchronisation (2min environ)...';
        } else {
          _isInitializingSearcher = !widget.databaseReady;
          _statusMessage =
              widget.databaseReady
                  ? null
                  : 'Initialisation du service de recherche...';
        }
      });

      _searchService?.dispose();
      _searchService = null;

      final appDbPath = await StorageService.getAppDatabasePath();
      AppLog.info('Ouverture de la base: $appDbPath');

      if (requireTursoSync && TursoSyncService.isConfigured) {
        final downloadResult = await TursoSyncService().downloadToAppDatabase(
          appDbPath,
          onProgress: onProgress,
        );
        AppLog.info(
          'Sync manuelle: ${downloadResult.materializedRows} lignes, '
          '${await SearchIndexService.describeTranslationData(appDbPath)}',
        );
        // Indexing is now handled in a background isolate via compute() inside rebuildIfNeeded/rebuild
        await SearchIndexService.rebuildIfNeeded(appDbPath, force: true);
        await DatabaseBootstrap.ensureDataSources(appDbPath);
      } else {
        await SearchIndexService.rebuildIfNeeded(appDbPath);
        await DatabaseBootstrap.ensureDataSources(appDbPath);
      }

      final hasData = await SearchIndexService.databaseHasTranslationData(appDbPath);
      final hasIndex = await SearchIndexService.databaseHasSearchIndex(appDbPath);

      final searchService = SearchService();
      await searchService.initialize();

      setState(() {
        _searchService = searchService;
        _isDatabaseEmpty = !hasData || !hasIndex;
        _isLoading = false;
        _isInitializingSearcher = false;
        _statusMessage = null;
      });
    } catch (e, stackTrace) {
      AppLog.error('Échec initialisation recherche', e, stackTrace);
      _searchService?.dispose();
      _searchService = null;

      setState(() {
        _error = 'Échec de l\'initialisation : $e';
        _isLoading = false;
        _isInitializingSearcher = false;
        _statusMessage = null;
      });
    }
  }

  Future<void> _translate() async {
    if (_searchService == null) return;

    final inputText = _inputController.text.trim();
    if (inputText.isEmpty) {
      _outputController.text = '';
      setState(() {
        _searchResults = [];
        _lexicalMatches = [];
      });
      return;
    }

    setState(() {
      _isTranslating = true;
    });

    try {
      final lexicalMatches = await _searchService!.lookupLexicalTokens(
        inputText,
      );
      final results = await _searchService!.search(inputText);

      setState(() {
        _lexicalMatches = lexicalMatches;
        _searchResults = _filterExpressionResults(lexicalMatches, results);
      });
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() {
        _isTranslating = false;
      });
    }
  }

  List<SearchResult> _filterExpressionResults(
    List<LexicalTokenMatch> lexicalMatches,
    List<SearchResult> results,
  ) {
    final lexicalTargets =
        lexicalMatches
            .map((match) => _normalizeTranslation(match.translatedWord))
            .where((target) => target.isNotEmpty)
            .toSet();

    final seenTargets = <String>{};
    final filtered = <SearchResult>[];

    for (final result in results) {
      final target = _normalizeTranslation(result.target);
      if (target.isEmpty) {
        continue;
      }
      if (lexicalTargets.contains(target)) {
        continue;
      }
      if (!seenTargets.add(target)) {
        continue;
      }
      filtered.add(result);
    }

    return filtered;
  }

  String _normalizeTranslation(String value) => value.trim().toLowerCase();

  String _buildCopyableTranslationText(
    List<LexicalTokenMatch> lexicalMatches,
    List<SearchResult> expressionResults,
  ) {
    final lines = <String>[
      ...lexicalMatches.map((match) => match.translatedWord.trim()),
      ...expressionResults.map((result) => result.target.trim()),
    ].where((line) => line.isNotEmpty).toList();

    return lines.join('\n');
  }

  bool get _hasTranslationResults =>
      _lexicalMatches.isNotEmpty || _searchResults.isNotEmpty;

  /// Share the current translation results
  Future<void> _shareCurrentTranslation() async {
    final box = context.findRenderObject() as RenderBox?;
    final text = _buildCopyableTranslationText(_lexicalMatches, _searchResults);

    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aucun résultat à partager.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    try {
      await Share.share(
        'Traductions Malinali :\n\n$text',
        subject: 'Traductions Malinali',
        sharePositionOrigin:
            box != null ? box.localToGlobal(Offset.zero) & box.size : null,
      );
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
    _searchService?.dispose();
    if (Platform.isAndroid) {
      _speechService?.dispose(); // Dispose speech recognition service
    }
    super.dispose();
  }

  Future<void> _retryStartup() async {
    await _initializeSearcher(requireTursoSync: TursoSyncService.isConfigured);
  }

  Future<void> _resetLocalDatabase() async {
    if (!kDebugMode) {
      await _retryStartup();
      return;
    }

    try {
      final appDbPath = await StorageService.getAppDatabasePath();
      final syncDbPath = await StorageService.getSyncDatabasePath();
      await ReplicaStorage.deleteReplicaArtifacts(appDbPath);
      await ReplicaStorage.deleteReplicaArtifacts(syncDbPath);
      if (kDebugMode) {
        print('✅ Deleted local databases');
      }
    } catch (e) {
      print('Warning: Could not delete database: $e');
    }

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const InitialScreen()),
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
    } else if (_error != null && _searchService == null) {
      bodyContent = Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
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
                onPressed: _retryStartup,
                icon: const Icon(Icons.refresh),
                label: Text(
                  TursoSyncService.isConfigured
                      ? 'Réessayer la synchronisation'
                      : 'Réessayer',
                ),
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
                const Expanded(child: _LanguageDirectionLabel()),
                IconButton(
                  icon: const Icon(Icons.settings),
                  onPressed: _showSettingsDialog,
                  tooltip: 'Paramètres',
                ),
              ],
            ),
          ),
          // Input editor
          SizedBox(
            height: 160,
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.all(8.0),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
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
                                    color:
                                        _isListening
                                            ? Colors.red.shade100.withOpacity(
                                              0.9,
                                            )
                                            : Colors.blue.shade100.withOpacity(
                                              0.9,
                                            ),
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
                                    color:
                                        _isListening ? Colors.red : Colors.blue,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        // Clear button - bottom right, above mic button when mic is visible, otherwise bottom right
                        if (_hasInputText)
                          Positioned(
                            bottom:
                                _sourceLang == 'French' && Platform.isAndroid
                                    ? 18
                                    : 8,
                            right: 105,
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
                                    color: Colors.grey.shade200.withOpacity(
                                      0.9,
                                    ),
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
                onPressed:
                    (_isTranslating ||
                            _isInitializingSearcher ||
                            _searchService == null)
                        ? null
                        : _translate,
                icon:
                    _isTranslating
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
          // Output editor (read-only)
          Expanded(
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.all(8.0),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  Expanded(child: _buildTranslationResultsPanel()),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Scaffold(body: SafeArea(child: bodyContent));
  }

  Widget _buildTranslationResultsPanel() {
    if (_isInitializingSearcher) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_isDatabaseEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.cloud_download_outlined,
                size: 64,
                color: Colors.blue.shade200,
              ),
              const SizedBox(height: 16),
              const Text(
                'Le dictionnaire est vide',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Synchronisez pour télécharger les données de traduction.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _isTranslating ? null : _syncDatabase,
                icon: const Icon(Icons.sync),
                label: const Text('Synchroniser maintenant'),
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
    }

    if (!_hasTranslationResults) {
      return const SizedBox.expand();
    }

    return ListView(
      padding: const EdgeInsets.all(12.0),
      children: [
        if (_lexicalMatches.isNotEmpty) ...[
          Text(
            'Par mot',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          ..._lexicalMatches.map(
            (match) => _LexicalTokenMatchItem(match: match),
          ),
        ],
        if (_lexicalMatches.isNotEmpty && _searchResults.isNotEmpty)
          const SizedBox(height: 16),
        if (_searchResults.isNotEmpty) ...[
          Text(
            'Expressions',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          ...List.generate(_searchResults.length, (index) {
            final result = _searchResults[index];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (index > 0) const Divider(),
                _SearchResultItem(result: result),
              ],
            );
          }),
        ],
      ],
    );
  }

  Future<void> _showSettingsDialog() async {
    final option = await showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Paramètres'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.sync),
                  title: const Text('Synchroniser'),
                  subtitle: const Text('Vérifier les mises à jour'),
                  onTap: () => Navigator.of(context).pop('sync'),
                ),
                ListTile(
                  leading: const Icon(Icons.share),
                  title: const Text('Partager ces résultats'),
                  subtitle: const Text('Partager les traductions affichées'),
                  onTap: () => Navigator.of(context).pop('share'),
                ),
                ListTile(
                  leading: const Icon(Icons.mail),
                  title: const Text('Contribuer'),
                  subtitle: const Text('Nous contacter à hello@malinali.app'),
                  onTap: () => Navigator.of(context).pop('contribute'),
                ),
                if (kDebugMode)
                  ListTile(
                    leading: const Icon(Icons.delete_outline),
                    title: const Text('Réinitialiser le jeu de données local'),
                    subtitle: const Text(
                      'Supprime la base locale et recharge les assets de test',
                    ),
                    onTap: () => Navigator.of(context).pop('reset_local'),
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

    if (option == 'share') {
      await _shareCurrentTranslation();
    } else if (option == 'sync') {
      await _syncDatabase();
    } else if (option == 'contribute') {
      await _showContributeDialog();
    } else if (option == 'reset_local') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('Réinitialiser le jeu de données local'),
              content: const Text(
                'La base locale sera supprimée puis rechargée depuis les assets de test.',
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

      if (confirmed == true) {
        await _resetLocalDatabase();
      }
    } else if (option == 'database' || option == 'files') {
      // Show warning dialog for database/file operations
      final confirmed = await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
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

  Future<void> _syncDatabase() async {
    if (!TursoSyncService.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Turso n\'est pas configuré. Ajoutez vos identifiants dans secrets.txt.',
          ),
        ),
      );
      return;
    }

    // Show loading dialog with progress
    final progressNotifier = ValueNotifier<(int, int)>((0, 0));

    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => PopScope(
            canPop: false,
            child: ValueListenableBuilder<(int, int)>(
              valueListenable: progressNotifier,
              builder: (context, progress, child) {
                final processed = progress.$1;
                final total = progress.$2;
                return AlertDialog(
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 24),
                      const Text('Synchronisation du dictionnaire...'),
                      if (total > 0) ...[
                        const SizedBox(height: 8),
                        Text(
                          '$processed / $total lignes',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(
                          value: processed / total,
                          backgroundColor: Colors.grey[200],
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Colors.blue,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      const Text(
                        'Cela peut prendre jusqu\'à 2 minutes.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
    );

    try {
      await _initializeSearcher(
        requireTursoSync: true,
        onProgress: (processed, total) {
          progressNotifier.value = (processed, total);
        },
      );
    } finally {
      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog
      }
      progressNotifier.dispose();
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _error == null
              ? 'Synchronisation terminée'
              : 'Synchronisation échouée : $_error',
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Show dialog to contribute (pointing to email)
  Future<void> _showContributeDialog() async {
    await showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Contribuer'),
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Vous souhaitez enrichir Malinali avec de nouvelles traductions ?',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 16),
                Text(
                  'Contactez-nous par e-mail pour nous faire part de vos suggestions ou pour rejoindre l\'équipe de contributeurs.',
                ),
                SizedBox(height: 16),
                SelectableText(
                  'hello@malinali.app',
                  style: TextStyle(
                    color: Colors.blue,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Fermer'),
              ),
            ],
          ),
    );
  }

  Future<void> _selectDatabase() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
        _statusMessage = 'Copie de la base de données...';
      });

      final result = await FilePicker.platform.pickFiles();

      if (result == null || result.files.single.path == null) {
        setState(() {
          _isLoading = false;
          _statusMessage = null;
        });
        return;
      }

      final selectedPath = result.files.single.path!;
      final targetPath = await StorageService.getAppDatabasePath();

      // Close current services to release database lock
      _searchService?.dispose();
      _searchService = null;

      // Wait a bit to ensure file handles are released
      await Future.delayed(const Duration(milliseconds: 100));

      await ReplicaStorage.deleteReplicaArtifacts(targetPath);

      // Copy selected database to app path
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
        _statusMessage =
            'Veuillez sélectionner le fichier source (ex. Français)...';
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
        _statusMessage =
            'Veuillez sélectionner le fichier cible (ex. Pulaar)...';
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

      // Close current services to release database lock
      _searchService?.dispose();
      _searchService = null;

      // Wait a bit to ensure file handles are released
      await Future.delayed(const Duration(milliseconds: 100));

      final appDbPath = await StorageService.getAppDatabasePath();
      await ReplicaStorage.deleteReplicaArtifacts(appDbPath);

      // Validate line counts
      setState(() {
        _statusMessage = 'Validation des fichiers...';
      });

      final sourceFile = File(sourcePath);
      final targetFile = File(targetPath);
      final sourceContent = await sourceFile.readAsString();
      final targetContent = await targetFile.readAsString();
      final sourceLines =
          sourceContent
              .split('\n')
              .map((line) => line.trim())
              .where((line) => line.isNotEmpty)
              .toList();
      final targetLines =
          targetContent
              .split('\n')
              .map((line) => line.trim())
              .where((line) => line.isNotEmpty)
              .toList();

      if (sourceLines.length != targetLines.length) {
        setState(() {
          _isLoading = false;
          _error =
              'Erreur : Les fichiers ont un nombre de lignes différent.\n'
              'Source : ${sourceLines.length}, Cible : ${targetLines.length}';
          _statusMessage = null;
        });
        return;
      }

      await DatabaseBootstrap.populateDictionaryFromLinePairs(
        appDbPath,
        sourceLines,
        targetLines,
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

Future<void> _copyTranslationAtom(BuildContext context, String text) async {
  final value = text.trim();
  if (value.isEmpty) {
    return;
  }

  await Clipboard.setData(ClipboardData(text: value));
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copié.'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}

Widget _translationContextMenu(
  BuildContext context,
  String fullText,
  EditableTextState editableTextState,
) {
  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: editableTextState.contextMenuAnchors,
    buttonItems: [
      ContextMenuButtonItem(
        onPressed: () {
          ContextMenuController.removeAny();
          final selection = editableTextState.textEditingValue.selection;
          final selected =
              selection.isValid && !selection.isCollapsed
                  ? selection.textInside(fullText)
                  : fullText;
          _copyTranslationAtom(context, selected);
        },
        type: ContextMenuButtonType.copy,
      ),
    ],
  );
}

/// One translation line: selectable Pulaar text; long-press copies the full line.
class _TranslationResultAtom extends StatelessWidget {
  final String translation;
  final TextStyle translationStyle;
  final List<InlineSpan>? translationSpans;
  final Widget? subtitle;

  const _TranslationResultAtom({
    required this.translation,
    required this.translationStyle,
    this.translationSpans,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final contextMenuBuilder =
        (BuildContext ctx, EditableTextState state) =>
            _translationContextMenu(ctx, translation, state);

    final translationText =
        translationSpans != null
            ? SelectableText.rich(
              TextSpan(style: translationStyle, children: translationSpans),
              contextMenuBuilder: contextMenuBuilder,
            )
            : SelectableText(
              translation,
              style: translationStyle,
              contextMenuBuilder: contextMenuBuilder,
            );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _LongPressCopyWrapper(
          text: translation,
          child: translationText,
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          subtitle!,
        ],
      ],
    );
  }
}

/// Fires copy after a hold without taking part in the text-selection gesture arena.
class _LongPressCopyWrapper extends StatefulWidget {
  final String text;
  final Widget child;

  const _LongPressCopyWrapper({required this.text, required this.child});

  @override
  State<_LongPressCopyWrapper> createState() => _LongPressCopyWrapperState();
}

class _LongPressCopyWrapperState extends State<_LongPressCopyWrapper> {
  Timer? _holdTimer;

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  void _cancelHold() {
    _holdTimer?.cancel();
    _holdTimer = null;
  }

  void _startHold() {
    _cancelHold();
    _holdTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) {
        return;
      }
      _copyTranslationAtom(context, widget.text);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _startHold(),
      onPointerUp: (_) => _cancelHold(),
      onPointerCancel: (_) => _cancelHold(),
      child: widget.child,
    );
  }
}

class _LexicalTokenMatchItem extends StatelessWidget {
  final LexicalTokenMatch match;

  const _LexicalTokenMatchItem({required this.match});

  static const _translationStyle = TextStyle(
    fontSize: 18,
    color: Colors.black,
    fontWeight: FontWeight.w500,
    fontFamily: 'NotoSans',
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: _TranslationResultAtom(
        translation: match.translatedWord,
        translationStyle: _translationStyle,
        subtitle: SelectableText(
          '${match.sourceWord} (${_categoryLabel(match.category)})',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade600,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }

  String _categoryLabel(String category) {
    switch (category) {
      case 'noun':
        return 'nom';
      case 'verb':
        return 'verbe';
      case 'adjective':
        return 'adjectif';
      case 'adverb':
        return 'adverbe';
      case 'pronoun':
        return 'pronom';
      case 'preposition':
        return 'préposition';
      case 'conjunction':
        return 'conjonction';
      case 'interjection':
        return 'interjection';
      case 'numeral':
        return 'numéral';
      case 'article':
        return 'article';
      case 'determiner':
        return 'déterminant';
      default:
        return category;
    }
  }
}

class _SearchResultItem extends StatelessWidget {
  final SearchResult result;

  const _SearchResultItem({required this.result});

  static const _translationStyle = TextStyle(
    fontSize: 18,
    color: Colors.black,
    fontWeight: FontWeight.w500,
    fontFamily: 'NotoSans',
  );

  @override
  Widget build(BuildContext context) {
    final dataSource = result.dataSource;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: _TranslationResultAtom(
        translation: result.target,
        translationStyle: _translationStyle,
        translationSpans:
            result.matchedTerms.isEmpty
                ? null
                : _getHighlightedSpans(
                  result.target,
                  result.matchedTerms,
                  _translationStyle,
                ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              result.source,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
                fontStyle: FontStyle.italic,
              ),
            ),
            if (result.isPhrase && dataSource != null) ...[
              const SizedBox(height: 4),
              InkWell(
                onTap: () => _showDataSourceDialog(context, dataSource),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2.0),
                  child: Text(
                    dataSource.name,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue.shade700,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showDataSourceDialog(
    BuildContext context,
    DataSourceAttribution dataSource,
  ) {
    showDialog<void>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(dataSource.name),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (dataSource.author.isNotEmpty)
                    _DataSourceDetailRow(
                      label: 'Auteur',
                      value: dataSource.author,
                    ),
                  if (dataSource.year.isNotEmpty)
                    _DataSourceDetailRow(label: 'Année', value: dataSource.year),
                  if (dataSource.organization.isNotEmpty)
                    _DataSourceDetailRow(
                      label: 'Org',
                      value: dataSource.organization,
                    ),
                  if (dataSource.url.isNotEmpty)
                    _DataSourceDetailRow(label: 'URL', value: dataSource.url),
                  if (!dataSource.hasDetails)
                    const Text('Aucun détail supplémentaire.'),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Fermer'),
              ),
            ],
          ),
    );
  }

  static final TextStyle _matchHighlightStyle = TextStyle(
    color: Colors.blue.shade800,
    fontWeight: FontWeight.w700,
    decoration: TextDecoration.underline,
    decorationColor: Colors.blue.shade300,
  );

  List<TextSpan> _getHighlightedSpans(
    String text,
    List<String> terms,
    TextStyle baseStyle,
  ) {
    final spans = <TextSpan>[];
    final lowerText = text.toLowerCase();
    final highlightStyle = baseStyle.merge(_matchHighlightStyle);

    final sortedTerms = List<String>.from(terms)
      ..sort((a, b) => b.length.compareTo(a.length));

    var lastMatchEnd = 0;

    while (lastMatchEnd < text.length) {
      var earliestMatchStart = -1;
      String? bestTerm;

      for (final term in sortedTerms) {
        if (term.isEmpty) continue;
        final index = lowerText.indexOf(term.toLowerCase(), lastMatchEnd);
        if (index != -1 &&
            (earliestMatchStart == -1 || index < earliestMatchStart)) {
          earliestMatchStart = index;
          bestTerm = term;
        }
      }

      if (earliestMatchStart != -1 && bestTerm != null) {
        if (earliestMatchStart > lastMatchEnd) {
          spans.add(
            TextSpan(
              text: text.substring(lastMatchEnd, earliestMatchStart),
              style: baseStyle,
            ),
          );
        }
        spans.add(
          TextSpan(
            text: text.substring(
              earliestMatchStart,
              earliestMatchStart + bestTerm.length,
            ),
            style: highlightStyle,
          ),
        );
        lastMatchEnd = earliestMatchStart + bestTerm.length;
      } else {
        spans.add(TextSpan(text: text.substring(lastMatchEnd), style: baseStyle));
        break;
      }
    }

    return spans;
  }
}

class _DataSourceDetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DataSourceDetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: RichText(
        textAlign: TextAlign.left,
        text: TextSpan(
          style: DefaultTextStyle.of(context).style,
          children: [
            TextSpan(
              text: '$label : ',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

class _LanguageDirectionLabel extends StatelessWidget {
  const _LanguageDirectionLabel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Français → Pulaar',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.grey.shade700,
        ),
      ),
    );
  }
}
