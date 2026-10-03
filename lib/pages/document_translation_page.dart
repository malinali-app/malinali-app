import 'dart:io';

import 'package:aptabase_flutter/aptabase_flutter.dart';
import 'package:filebridge/filebridge.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:malinali/services/document_translation_service.dart';
import 'package:malinali/services/translation_model_service.dart';
import 'package:malinali/theme/malinali_chrome.dart';
import 'package:marian_flutter/marian_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

/// Batch document translation: pick → translate → glimpse → save/share.
/// Preview is read-only; editing belongs in an external app.
class DocumentTranslationPage extends StatefulWidget {
  const DocumentTranslationPage({
    super.key,
    required this.marian,
    required this.model,
    this.translationService,
  });

  final MarianService marian;
  final TranslationModel model;
  final DocumentTranslationService? translationService;

  @override
  State<DocumentTranslationPage> createState() =>
      _DocumentTranslationPageState();
}

enum _DocPhase { idle, translating, done, error }

class _DocumentTranslationPageState extends State<DocumentTranslationPage> {
  late final DocumentTranslationService _service;
  final _glimpseScrollController = ScrollController();

  _DocPhase _phase = _DocPhase.idle;
  String? _sourcePath;
  String? _sourceName;
  String? _savedPath;
  String? _error;
  int _completed = 0;
  int _total = 0;
  bool _cancelRequested = false;
  String? _translatedText;

  /// When true, the yellow target panel fills remaining height (read-only).
  bool get _showGlimpse =>
      _translatedText != null && _translatedText!.trim().isNotEmpty;

  bool get _canExport =>
      _showGlimpse && _phase != _DocPhase.translating;

  @override
  void initState() {
    super.initState();
    _service = widget.translationService ?? DocumentTranslationService();
  }

  @override
  void dispose() {
    _glimpseScrollController.dispose();
    super.dispose();
  }

  String get _pairLabel {
    final src = widget.model.sourceLang.name.isEmpty
        ? widget.model.sourceLang.nameEn
        : widget.model.sourceLang.name;
    final tgt = widget.model.targetLang.name.isEmpty
        ? widget.model.targetLang.nameEn
        : widget.model.targetLang.name;
    return '$src → $tgt';
  }

  Future<void> _ensureStoragePermission() async {
    if (kIsWeb) return;
    if (!(Platform.isAndroid || Platform.isIOS)) return;

    // App owns permission UX; filebridge only soft-fails on denial.
    await [
      Permission.storage,
      if (Platform.isAndroid) Permission.manageExternalStorage,
    ].request();
  }

  Future<void> _pickFile() async {
    setState(() {
      _error = null;
      _savedPath = null;
      _translatedText = null;
      _phase = _DocPhase.idle;
    });

    final file = await FileLoaderMonolith.loadTextFileFromUserPick(
      titlel10n: 'Choisir un document texte',
    );
    if (!mounted) return;
    if (file.path.isEmpty) return;

    setState(() {
      _sourcePath = file.path;
      _sourceName = p.basename(file.path);
    });
  }

  Future<void> _startTranslation() async {
    final path = _sourcePath;
    if (path == null || path.isEmpty || _phase == _DocPhase.translating) {
      return;
    }

    final sourceText = await FileLoaderMonolith.readTextFile(path);
    if (!mounted) return;
    if (sourceText.trim().isEmpty) {
      setState(() {
        _phase = _DocPhase.error;
        _error = 'Le fichier est vide ou illisible.';
      });
      return;
    }

    setState(() {
      _phase = _DocPhase.translating;
      _cancelRequested = false;
      _completed = 0;
      _total = 0;
      _error = null;
      _savedPath = null;
      _translatedText = null;
    });

    try {
      Aptabase.instance.trackEvent('document_translation_started', {
        'model_id': widget.model.modelId,
        'source_lang': widget.model.sourceLang.nameEn,
        'target_lang': widget.model.targetLang.nameEn,
      });
      final result = await _service.translateDocument(
        sourceText: sourceText,
        marian: widget.marian,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _completed = progress.completedChunks;
            _total = progress.totalChunks;
          });
        },
        isCancelled: () => _cancelRequested,
      );

      if (!mounted) return;

      if (result.cancelled) {
        setState(() {
          _phase = _DocPhase.idle;
          _translatedText = null;
        });
        Aptabase.instance.trackEvent('document_translation_cancelled');
        return;
      }

      setState(() {
        _phase = _DocPhase.done;
        _translatedText = result.text;
      });
      Aptabase.instance.trackEvent('document_translation_completed', {
        'chunks': result.chunkCount,
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _DocPhase.error;
        _error = e.toString();
      });
      Aptabase.instance.trackEvent('document_translation_error', {
        'error': e.toString(),
      });
    }
  }

  Future<void> _saveResult() async {
    final text = _translatedText;
    if (text == null || text.trim().isEmpty) return;

    await _ensureStoragePermission();
    final baseName = _sourceName ?? 'document.txt';
    final stem = p.basenameWithoutExtension(baseName);
    final outName = '${stem}_traduit.txt';

    final saved = await FileSaverV2.saveTxt(
      content: text,
      fileName: outName,
      l10nText: 'Enregistrer la traduction',
    );

    if (!mounted) return;
    if (saved.isEmpty) return; // user cancelled — keep preview

    Aptabase.instance.trackEvent('document_translation_saved');
    setState(() {
      _phase = _DocPhase.done;
      _savedPath = saved;
      _error = null;
    });
  }

  Future<void> _shareSaved() async {
    final path = _savedPath;
    final text = _translatedText;
    Aptabase.instance.trackEvent('document_translation_shared');
    if (path != null && path.isNotEmpty && File(path).existsSync()) {
      await SharePlus.instance.share(
        ShareParams(files: [XFile(path)], text: 'Traduction Malinali'),
      );
      return;
    }
    if (text != null && text.isNotEmpty) {
      await SharePlus.instance.share(ShareParams(text: text));
    }
  }

  void _cancel() {
    setState(() => _cancelRequested = true);
  }

  @override
  Widget build(BuildContext context) {
    final showGlimpse = _showGlimpse;
    final canExport = _canExport;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Traduire un document'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Traduction hors-ligne par lots',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: MalinaliChrome.yellowBorder,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Importez un fichier texte (.txt/.md). '
                      'Vérifiez l’aperçu, puis enregistrez ou partagez.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: MalinaliChrome.onBlue,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Modèle : $_pairLabel',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: MalinaliChrome.mutedOnBlue,
                          ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _phase == _DocPhase.translating ? null : _pickFile,
              icon: const Icon(Icons.upload_file),
              label: Text(
                _sourceName == null
                    ? 'Choisir un fichier…'
                    : 'Fichier : $_sourceName',
              ),
            ),
            const SizedBox(height: 12),
            if (_phase == _DocPhase.translating) ...[
              LinearProgressIndicator(
                value: _total > 0 ? _completed / _total : null,
              ),
              const SizedBox(height: 8),
              Text(
                _total > 0
                    ? 'Blocs traduits : $_completed / $_total'
                    : 'Préparation…',
                textAlign: TextAlign.center,
                style: const TextStyle(color: MalinaliChrome.onBlue),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _cancel,
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Annuler'),
              ),
            ] else ...[
              FilledButton.icon(
                onPressed: _sourcePath == null ? null : _startTranslation,
                icon: const Icon(Icons.translate),
                label: const Text('Lancer la traduction'),
              ),
            ],
            if (_phase == _DocPhase.error && _error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (_savedPath != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(
                    Icons.check_circle,
                    color: MalinaliChrome.success,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _savedPath!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: MalinaliChrome.success,
                            fontWeight: FontWeight.w600,
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            if (showGlimpse) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Aperçu (lecture seule)',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: MalinaliChrome.onBlue,
                          ),
                    ),
                  ),
                  if (canExport) ...[
                    IconButton(
                      icon: const Icon(Icons.save_outlined),
                      tooltip: 'Enregistrer',
                      color: MalinaliChrome.yellowBorder,
                      onPressed: _saveResult,
                    ),
                    IconButton(
                      icon: const Icon(Icons.share_outlined),
                      tooltip: 'Partager',
                      color: MalinaliChrome.onBlue,
                      onPressed: _shareSaved,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: MalinaliChrome.bluePanel,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: MalinaliChrome.yellowBorder,
                      width: 1,
                    ),
                  ),
                  child: Scrollbar(
                    controller: _glimpseScrollController,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _glimpseScrollController,
                      padding: const EdgeInsets.all(14),
                      child: SelectableText(
                        _translatedText!,
                        style: const TextStyle(
                          fontFamily: 'NotoSans',
                          fontSize: 16,
                          height: 1.4,
                          color: MalinaliChrome.targetText,
                        ),
                      ),
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
}
