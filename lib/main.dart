// ignore_for_file: implementation_imports
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:malinali/services/search_service.dart';
// import 'package:malinali/setup_screen.dart';
import 'package:malinali/services/speech_recognition_service.dart';
import 'package:malinali/services/storage_service.dart';
import 'package:malinali/services/turso_sync_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:sqlite3/sqlite3.dart' hide Row;
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'package:flutter/services.dart';

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
  @override
  void initState() {
    super.initState();
    _checkDatabase();
  }

  Future<void> _checkDatabase() async {
    try {
      final syncDbPath = await StorageService.getSyncDatabasePath();
      final syncDbFile = File(syncDbPath);
      bool exists = await syncDbFile.exists();

      if (exists) {
        final stat = await syncDbFile.stat();
        if (stat.size == 0) {
          exists = false;
        }
      }

      if (!exists) {
        print('ℹ️  Sync database not found, populating from text files...');

        // Create the database schema
        final db = sqlite3.open(syncDbPath);
        db.execute('''
        CREATE TABLE IF NOT EXISTS dictionary (
            source_word TEXT PRIMARY KEY,
            translated_word TEXT,
            category TEXT,
            source TEXT
        );
      ''');
        db.execute('''
        CREATE VIRTUAL TABLE IF NOT EXISTS documents USING fts5(
            content, 
            tokenize = 'unicode61'
        );
      ''');

        // 1. Populate dictionary table
        final srcDict = await rootBundle.loadString(
          'assets/fra-ful/src_dictionary.txt',
        );
        final tgtDict = await rootBundle.loadString(
          'assets/fra-ful/tgt_dictionary.txt',
        );
        final srcDictLines =
            srcDict
                .split('\n')
                .map((l) => l.trim())
                .where((l) => l.isNotEmpty)
                .toList();
        final tgtDictLines =
            tgtDict
                .split('\n')
                .map((l) => l.trim())
                .where((l) => l.isNotEmpty)
                .toList();

        final dictStmt = db.prepare(
          'INSERT OR IGNORE INTO dictionary (source_word, translated_word) VALUES (?, ?)',
        );
        for (
          var i = 0;
          i < srcDictLines.length && i < tgtDictLines.length;
          i++
        ) {
          dictStmt.execute([srcDictLines[i], tgtDictLines[i]]);
        }
        dictStmt.dispose();

        // 2. Populate FTS table
        final srcCombined = await rootBundle.loadString(
          'assets/fra-ful/combined_src.txt',
        );
        final tgtCombined = await rootBundle.loadString(
          'assets/fra-ful/combined_tgt.txt',
        );
        final srcLines =
            srcCombined
                .split('\n')
                .map((l) => l.trim())
                .where((l) => l.isNotEmpty)
                .toList();
        final tgtLines =
            tgtCombined
                .split('\n')
                .map((l) => l.trim())
                .where((l) => l.isNotEmpty)
                .toList();

        final ftsStmt = db.prepare(
          'INSERT INTO documents (content) VALUES (?)',
        );
        for (var i = 0; i < srcLines.length && i < tgtLines.length; i++) {
          ftsStmt.execute(['${srcLines[i]} → ${tgtLines[i]}']);
        }
        ftsStmt.dispose();

        db.dispose();
        print('✅ Default sync database populated successfully from text files');
      }

      if (mounted) {
        print('✅ Database ready, navigating to TranslationScreen');
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const TranslationScreen()),
        );
      }
    } catch (e) {
      print('❌ Error initializing database: $e');
      if (mounted) {
        // If extraction fails, we might still want to show setup screen as fallback
        // but the user wants to "jump on", so let's show an error if it really fails
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur d\'initialisation : $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
  SearchService? _searchService;
  TursoSyncService? _syncService;
  SpeechRecognitionService? _speechService;
  bool _isLoading = true;
  bool _isTranslating = false;
  bool _isListening = false; // Track if speech recognition is active
  String _sourceLang = 'French';
  String _targetLang = 'Fula'; // Default: French → Fula
  String? _error;
  TranslationDirection _direction = TranslationDirection.frenchToFula;
  bool _hasInputText =
      false; // Track if input has text for clear button visibility
  String? _statusMessage; // Status message for detailed loader

  List<SearchResult> _searchResults = [];

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

  Future<void> _initializeSearcher() async {
    try {
      setState(() {
        _statusMessage = 'Initialisation du service de recherche...';
      });

      // Initialize search service
      final searchService = SearchService();
      await searchService.initialize();

      // Initialize Turso sync service
      _syncService = TursoSyncService();
      await _syncService!.initialize();

      setState(() {
        _searchService = searchService;
        _isLoading = false;
        _statusMessage = null;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to initialize: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _translate() async {
    if (_searchService == null) return;

    final inputText = _inputController.text.trim();
    if (inputText.isEmpty) {
      _outputController.text = '';
      return;
    }

    setState(() {
      _isTranslating = true;
    });

    try {
      final results = await _searchService!.search(inputText);

      setState(() {
        _searchResults = results;
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

  /// Share the current translation results
  Future<void> _shareCurrentTranslation() async {
    final box = context.findRenderObject() as RenderBox?;
    final text = _outputController.text.trim();

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
    _syncService?.dispose(); // Close Turso sync service
    if (Platform.isAndroid) {
      _speechService?.dispose(); // Dispose speech recognition service
    }
    super.dispose();
  }

  Future<void> _resetDatabase() async {
    // Delete the sync database (replica)
    try {
      final syncDbPath = await StorageService.getSyncDatabasePath();

      final syncDbFile = File(syncDbPath);
      if (await syncDbFile.exists()) {
        await syncDbFile.delete();
        print('✅ Deleted sync database');
      }
    } catch (e) {
      print('Warning: Could not delete database: $e');
    }

    // Navigate back to initial screen (which will re-extract and initialize)
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
    } else if (_error != null) {
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
                onPressed: _resetDatabase,
                icon: const Icon(Icons.refresh),
                label: const Text('Réinitialiser la base de données'),
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
                onPressed: _isTranslating ? null : _translate,
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
                    child:
                        _searchResults.isEmpty
                            ? const SizedBox()
                            : ListView.separated(
                              padding: const EdgeInsets.all(12.0),
                              itemCount: _searchResults.length,
                              separatorBuilder:
                                  (context, index) => const Divider(),
                              itemBuilder: (context, index) {
                                final result = _searchResults[index];
                                return _SearchResultItem(result: result);
                              },
                            ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Scaffold(body: SafeArea(child: bodyContent));
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
    if (_syncService == null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Synchronisation en cours...'),
        duration: Duration(seconds: 1),
      ),
    );

    await _syncService!.sync();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Synchronisation terminée'),
          duration: Duration(seconds: 2),
        ),
      );
      // Reinitialize searcher to pick up new data
      await _initializeSearcher();
    }
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
      final targetPath = await StorageService.getSyncDatabasePath();

      // Close current search service to release database lock
      _searchService?.dispose();
      _searchService = null;

      // Wait a bit to ensure file handles are released
      await Future.delayed(const Duration(milliseconds: 100));

      final syncDbFile = File(targetPath);
      if (await syncDbFile.exists()) {
        await syncDbFile.delete();
      }

      // Copy selected database to sync path
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

      // Close current search service to release database lock
      _searchService?.dispose();
      _searchService = null;

      // Wait a bit to ensure file handles are released
      await Future.delayed(const Duration(milliseconds: 100));

      final syncDbPath = await StorageService.getSyncDatabasePath();
      final syncDbFile = File(syncDbPath);
      if (await syncDbFile.exists()) {
        await syncDbFile.delete();
      }

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

      // Create the sync database from text files
      final db = sqlite3.open(syncDbPath);
      db.execute('''
        CREATE TABLE IF NOT EXISTS dictionary (
            source_word TEXT PRIMARY KEY,
            translated_word TEXT,
            category TEXT,
            source TEXT
        );
      ''');
      db.execute('''
        CREATE VIRTUAL TABLE IF NOT EXISTS documents USING fts5(
            content, 
            tokenize = 'unicode61'
        );
      ''');

      final stmt = db.prepare('INSERT INTO documents (content) VALUES (?)');
      for (var i = 0; i < sourceLines.length; i++) {
        stmt.execute(['${sourceLines[i]} → ${targetLines[i]}']);
      }
      stmt.dispose();
      db.dispose();

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

class _SearchResultItem extends StatelessWidget {
  final SearchResult result;

  const _SearchResultItem({required this.result});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Target (Fula) - Primary
          RichText(
            text: TextSpan(
              style: const TextStyle(
                fontSize: 18,
                color: Colors.black,
                fontWeight: FontWeight.w500,
                fontFamily: 'NotoSans',
              ),
              children: _getHighlightedSpans(
                result.target,
                result.matchedTerms,
              ),
            ),
          ),
          const SizedBox(height: 6),
          // Source (French) - Secondary/Context
          Text(
            result.source,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  List<TextSpan> _getHighlightedSpans(String text, List<String> terms) {
    if (terms.isEmpty) return [TextSpan(text: text)];

    List<TextSpan> spans = [];
    String lowerText = text.toLowerCase();

    // Sort terms by length descending to match longest terms first
    final sortedTerms = List<String>.from(terms)
      ..sort((a, b) => b.length.compareTo(a.length));

    int lastMatchEnd = 0;

    while (lastMatchEnd < text.length) {
      int earliestMatchStart = -1;
      String? bestTerm;

      for (var term in sortedTerms) {
        if (term.isEmpty) continue;
        int index = lowerText.indexOf(term.toLowerCase(), lastMatchEnd);
        if (index != -1 &&
            (earliestMatchStart == -1 || index < earliestMatchStart)) {
          earliestMatchStart = index;
          bestTerm = term;
        }
      }

      if (earliestMatchStart != -1 && bestTerm != null) {
        // Add text before match
        if (earliestMatchStart > lastMatchEnd) {
          spans.add(
            TextSpan(text: text.substring(lastMatchEnd, earliestMatchStart)),
          );
        }
        // Add highlighted match
        spans.add(
          TextSpan(
            text: text.substring(
              earliestMatchStart,
              earliestMatchStart + bestTerm.length,
            ),
            style: const TextStyle(
              color: Colors.blue,
              fontWeight: FontWeight.bold,
              backgroundColor: Color(0xFFE3F2FD),
            ),
          ),
        );
        lastMatchEnd = earliestMatchStart + bestTerm.length;
      } else {
        // Add remaining text
        spans.add(TextSpan(text: text.substring(lastMatchEnd)));
        break;
      }
    }

    return spans;
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
    final label = isFrenchToFula ? 'Français → Pulaar' : 'Pulaar → Français';

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
