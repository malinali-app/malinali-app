import 'dart:io';

import 'package:filebridge/filebridge.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:malinali/services/audio_transcription_service.dart';
import 'package:malinali/services/speech_recognition_service.dart';
import 'package:malinali/services/vosk_model_service.dart';
import 'package:malinali/theme/malinali_chrome.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

/// Offline audio → text: pick .opus (WhatsApp) → decode → Vosk → glimpse.
class AudioTranscriptionPage extends StatefulWidget {
  const AudioTranscriptionPage({
    super.key,
    required this.voskService,
    this.speechService,
    this.voskModel,
    this.transcriptionService,
    this.initialAudioPath,
    this.initialTranscript,
    this.translationPairLabel,
  });

  final VoskModelService voskService;
  final SpeechRecognitionService? speechService;
  final VoskModel? voskModel;
  final AudioTranscriptionService? transcriptionService;

  /// Optional path for tests / deep links (e.g. shared WhatsApp note).
  final String? initialAudioPath;

  /// Optional pre-filled transcript (tests / restore).
  final String? initialTranscript;

  /// Current translate pair label (e.g. "Français → Pulaar") for the action button.
  final String? translationPairLabel;

  @override
  State<AudioTranscriptionPage> createState() => _AudioTranscriptionPageState();
}

enum _AudioPhase { idle, working, done, error }

class _AudioTranscriptionPageState extends State<AudioTranscriptionPage> {
  late final SpeechRecognitionService _speech;
  late final AudioTranscriptionService _service;
  final _glimpseScrollController = ScrollController();

  _AudioPhase _phase = _AudioPhase.idle;
  String? _sourcePath;
  String? _sourceName;
  String? _transcript;
  String? _savedPath;
  String? _error;
  String _statusLabel = '';
  double _fraction = 0;
  bool _cancelRequested = false;

  bool get _showGlimpse =>
      _transcript != null && _transcript!.trim().isNotEmpty;

  bool get _canExport =>
      _showGlimpse && _phase != _AudioPhase.working;

  @override
  void initState() {
    super.initState();
    _speech = widget.speechService ??
        SpeechRecognitionService(modelService: widget.voskService);
    _service = widget.transcriptionService ??
        AudioTranscriptionService(
          transcriber: VoskWaveformTranscriber(
            speech: _speech,
            model: widget.voskModel ?? VoskModelService.assetFrenchModel,
          ),
        );

    final initial = widget.initialAudioPath;
    if (initial != null && initial.isNotEmpty) {
      _sourcePath = initial;
      _sourceName = p.basename(initial);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _start();
      });
    } else {
      final seed = widget.initialTranscript?.trim();
      if (seed != null && seed.isNotEmpty) {
        _transcript = seed;
        _phase = _AudioPhase.done;
        _statusLabel = 'Terminé — vérifiez l’aperçu';
      }
    }
  }

  @override
  void dispose() {
    _glimpseScrollController.dispose();
    // Do not dispose shared speech if injected from TranslatePage.
    if (widget.speechService == null) {
      _speech.dispose();
    }
    super.dispose();
  }

  Future<void> _ensureStoragePermission() async {
    if (kIsWeb) return;
    if (!(Platform.isAndroid || Platform.isIOS)) return;
    await [
      Permission.storage,
      if (Platform.isAndroid) Permission.manageExternalStorage,
    ].request();
  }

  Future<void> _pickAudio() async {
    setState(() {
      _error = null;
      _savedPath = null;
      _transcript = null;
      _phase = _AudioPhase.idle;
      _fraction = 0;
      _statusLabel = '';
    });

    final file = await FileLoaderMonolith.loadAudioFileFromUserPick(
      titlel10n: 'Choisir un audio (.opus WhatsApp…)',
    );
    if (!mounted) return;
    if (file.path.isEmpty) return;

    setState(() {
      _sourcePath = file.path;
      _sourceName = p.basename(file.path);
    });
  }

  Future<void> _start() async {
    final path = _sourcePath;
    if (path == null || path.isEmpty || _phase == _AudioPhase.working) return;

    setState(() {
      _phase = _AudioPhase.working;
      _cancelRequested = false;
      _error = null;
      _savedPath = null;
      _transcript = null;
      _fraction = 0;
      _statusLabel = 'Décodage…';
    });

    try {
      if (_speech.isListening) {
        await _speech.stopListening();
      }

      final workDir = await audioSttWorkDirectory();
      final result = await _service.transcribeFile(
        File(path),
        workDirectory: workDir,
        isCancelled: () => _cancelRequested,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _fraction = progress.fraction;
            _statusLabel = switch (progress.phase) {
              'decode' => 'Décodage audio…',
              'transcribe' =>
                'Transcription… ${(progress.fraction * 100).clamp(0, 100).toStringAsFixed(0)} %',
              'done' => 'Terminé',
              'cancelled' => 'Annulé',
              _ => progress.phase,
            };
            if (progress.partialText.isNotEmpty) {
              _transcript = progress.partialText;
            }
          });
        },
      );

      if (!mounted) return;

      if (result.cancelled) {
        setState(() {
          _phase = _AudioPhase.idle;
          _statusLabel = 'Annulé';
        });
        return;
      }

      if (result.text.trim().isEmpty) {
        setState(() {
          _phase = _AudioPhase.error;
          _error = 'Aucune parole détectée dans ce fichier.';
          _transcript = null;
        });
        return;
      }

      setState(() {
        _phase = _AudioPhase.done;
        _transcript = result.text;
        _statusLabel = 'Terminé — vérifiez l’aperçu';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _AudioPhase.error;
        _error = e.toString();
      });
    }
  }

  Future<void> _saveTranscript() async {
    final text = _transcript;
    if (text == null || text.trim().isEmpty) return;

    await _ensureStoragePermission();
    final outName = transcriptFileNameFor(_sourceName ?? 'audio.opus');
    final saved = await FileSaverV2.saveTxt(
      content: text,
      fileName: outName,
      l10nText: 'Enregistrer la transcription',
    );
    if (!mounted) return;
    if (saved.isEmpty) return; // user cancelled — keep preview

    setState(() {
      _phase = _AudioPhase.done;
      _savedPath = saved;
      _error = null;
    });
  }

  Future<void> _share() async {
    final path = _savedPath;
    final text = _transcript;
    if (path != null && path.isNotEmpty && File(path).existsSync()) {
      await SharePlus.instance.share(
        ShareParams(files: [XFile(path)], text: 'Transcription Malinali'),
      );
      return;
    }
    if (text != null && text.isNotEmpty) {
      await SharePlus.instance.share(ShareParams(text: text));
    }
  }

  void _cancel() => setState(() => _cancelRequested = true);

  void _sendToTranslate() {
    final text = _transcript?.trim();
    if (text == null || text.isEmpty) return;
    Navigator.pop(context, text);
  }

  String get _translateButtonLabel {
    final pair = widget.translationPairLabel?.trim();
    if (pair == null || pair.isEmpty) return 'Traduire';
    return 'Traduire ($pair)';
  }

  @override
  Widget build(BuildContext context) {
    final showGlimpse = _showGlimpse;
    final canExport = _canExport;
    final voskLabel =
        widget.voskModel?.langText ?? VoskModelService.assetFrenchModel.langText;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Audio → texte'),
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
                      'Note vocale hors-ligne',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: MalinaliChrome.yellowBorder,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Chargez un audio (.opus WhatsApp / .ogg / .wav). ',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: MalinaliChrome.onBlue,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Modèle voix : $voskLabel',
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
              onPressed: _phase == _AudioPhase.working ? null : _pickAudio,
              icon: const Icon(Icons.audio_file_outlined),
              label: Text(
                _sourceName == null
                    ? 'Charger un audio (.opus)…'
                    : 'Fichier : $_sourceName',
              ),
            ),
            const SizedBox(height: 12),
            if (_phase == _AudioPhase.working) ...[
              LinearProgressIndicator(
                value: _fraction > 0 ? _fraction : null,
              ),
              const SizedBox(height: 8),
              Text(
                _statusLabel,
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
                onPressed: _sourcePath == null ? null : _start,
                icon: const Icon(Icons.record_voice_over),
                label: const Text('Transcrire'),
              ),
            ],
            if (_phase == _AudioPhase.error && _error != null) ...[
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
                      onPressed: _saveTranscript,
                    ),
                    IconButton(
                      icon: const Icon(Icons.share_outlined),
                      tooltip: 'Partager',
                      color: MalinaliChrome.onBlue,
                      onPressed: _share,
                    ),
                  ],
                ],
              ),
              if (canExport) ...[
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _sendToTranslate,
                  icon: const Icon(Icons.translate),
                  label: Text(_translateButtonLabel),
                ),
              ],
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
                        _transcript!,
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
