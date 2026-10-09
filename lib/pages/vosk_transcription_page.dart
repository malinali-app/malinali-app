import 'dart:async';
import 'dart:io';

import 'package:aptabase_flutter/aptabase_flutter.dart';
import 'package:filebridge/filebridge.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:malinali/pages/transcription_settings_page.dart';
import 'package:malinali/services/audio_transcription_service.dart';
import 'package:malinali/services/malinali_audio_open_intent.dart';
import 'package:malinali/services/speech_recognition_service.dart';
import 'package:malinali/services/vosk_model_service.dart';
import 'package:malinali/theme/malinali_chrome.dart';
import 'package:malinali/widgets/language_pill.dart';
import 'package:malinali/widgets/malinali_drawer.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

/// Vosk-only audio transcription: file / share / plain live mic.
class VoskTranscriptionPage extends StatefulWidget {
  const VoskTranscriptionPage({
    super.key,
    required this.voskService,
    this.speechService,
    this.initialModel,
    this.initialAudioPath,
    this.initialTranscript,
  });

  final VoskModelService voskService;
  final SpeechRecognitionService? speechService;
  final VoskModel? initialModel;
  final String? initialAudioPath;
  final String? initialTranscript;

  @override
  State<VoskTranscriptionPage> createState() => _VoskTranscriptionPageState();
}

enum _Phase { idle, working, done, error }

class _VoskTranscriptionPageState extends State<VoskTranscriptionPage> {
  late final SpeechRecognitionService _speech;
  final _textController = TextEditingController();
  StreamSubscription<String>? _shareSub;

  VoskModel? _model;
  List<VoskModel> _models = [];
  _Phase _phase = _Phase.idle;
  String? _sourcePath;
  String? _sourceName;
  String? _error;
  String _statusLabel = '';
  double _fraction = 0;
  bool _cancelRequested = false;
  bool _listening = false;
  bool _modelReady = false;

  @override
  void initState() {
    super.initState();
    _speech = widget.speechService ??
        SpeechRecognitionService(modelService: widget.voskService);
    _model = widget.initialModel ?? VoskModelService.assetFrenchModel;
    final seed = widget.initialTranscript?.trim();
    if (seed != null && seed.isNotEmpty) {
      _textController.text = seed;
      _phase = _Phase.done;
    }
    unawaited(_initModels());
    _shareSub = MalinaliAudioOpenIntent.instance.pathStream.listen((path) {
      if (path.isEmpty || !mounted) return;
      setState(() {
        _sourcePath = path;
        _sourceName = p.basename(path);
      });
      unawaited(_transcribeFile());
    });
    final pending = MalinaliAudioOpenIntent.instance.takePendingPath();
    if (pending != null && pending.isNotEmpty) {
      _sourcePath = pending;
      _sourceName = p.basename(pending);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_transcribeFile());
      });
    }
    final initial = widget.initialAudioPath;
    if (initial != null && initial.isNotEmpty) {
      _sourcePath = initial;
      _sourceName = p.basename(initial);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_transcribeFile());
      });
    }
  }

  Future<void> _initModels() async {
    try {
      final models = await widget.voskService.fetchAllSmallModels();
      var model = _model ?? VoskModelService.assetFrenchModel;
      final downloaded = await widget.voskService.isModelDownloaded(model);
      if (!downloaded && !model.isAsset) {
        model = VoskModelService.assetFrenchModel;
      }
      await _speech.initialize(model: model);
      if (!mounted) return;
      setState(() {
        _models = models;
        _model = model;
        _modelReady = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _phase = _Phase.error;
      });
    }
  }

  @override
  void dispose() {
    _shareSub?.cancel();
    _textController.dispose();
    if (widget.speechService == null) {
      _speech.dispose();
    }
    super.dispose();
  }

  Future<void> _pickModel() async {
    final picked = await Navigator.push<VoskModel>(
      context,
      MaterialPageRoute(
        builder: (_) => TranscriptionSettingsPage(
          voskService: widget.voskService,
          selectedModel: _model,
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _modelReady = false;
      _statusLabel = 'Chargement ${picked.langText}…';
    });
    try {
      final ready = await widget.voskService.isModelDownloaded(picked);
      if (!ready && !picked.isAsset) {
        await widget.voskService.downloadModel(picked);
      }
      await _speech.initialize(model: picked);
      if (!mounted) return;
      setState(() {
        _model = picked;
        _modelReady = true;
        _statusLabel = '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _modelReady = false;
      });
    }
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
      _phase = _Phase.idle;
      _fraction = 0;
      _statusLabel = '';
    });
    final file = await FileLoaderMonolith.loadAudioFileFromUserPick(
      titlel10n: 'Choisir un audio (.opus WhatsApp…)',
    );
    if (!mounted || file.path.isEmpty) return;
    setState(() {
      _sourcePath = file.path;
      _sourceName = p.basename(file.path);
    });
  }

  Future<void> _transcribeFile() async {
    final path = _sourcePath;
    final model = _model;
    if (path == null || path.isEmpty || model == null || _phase == _Phase.working) {
      return;
    }
    setState(() {
      _phase = _Phase.working;
      _cancelRequested = false;
      _error = null;
      _fraction = 0;
      _statusLabel = 'Décodage…';
    });
    try {
      if (_speech.isListening) await _speech.stopListening();
      final workDir = await audioSttWorkDirectory();
      Aptabase.instance.trackEvent('audio_transcription_started', {
        'vosk_model': model.name,
      });
      final service = AudioTranscriptionService(
        transcriber: VoskWaveformTranscriber(speech: _speech, model: model),
      );
      final result = await service.transcribeFile(
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
              _ => progress.phase,
            };
          });
        },
      );
      if (!mounted) return;
      if (_cancelRequested) {
        setState(() {
          _phase = _Phase.idle;
          _statusLabel = 'Annulé';
        });
        return;
      }
      _textController.text = result.text;
      setState(() {
        _phase = _Phase.done;
        _statusLabel = 'Terminé';
        _fraction = 1;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = e.toString();
        _statusLabel = 'Erreur';
      });
    }
  }

  Future<void> _toggleLiveMic() async {
    if (!_modelReady || _model == null) return;
    if (_listening) {
      await _speech.stopListening();
      if (!mounted) return;
      setState(() {
        _listening = false;
        _phase = _Phase.done;
        _statusLabel = 'Micro arrêté';
      });
      return;
    }
    _speech.onPartialResult = (partial) {
      if (!mounted) return;
      setState(() => _statusLabel = partial);
    };
    _speech.onResult = (text) {
      if (!mounted || text.trim().isEmpty) return;
      final existing = _textController.text.trim();
      _textController.text =
          existing.isEmpty ? text.trim() : '$existing\n${text.trim()}';
    };
    _speech.onError = () {
      if (!mounted) return;
      setState(() {
        _listening = false;
        _error = 'Erreur micro';
      });
    };
    await _speech.startListening();
    if (!mounted) return;
    setState(() {
      _listening = true;
      _phase = _Phase.working;
      _statusLabel = 'Écoute…';
      _error = null;
    });
  }

  Future<void> _shareTranscript() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    await SharePlus.instance.share(ShareParams(text: text));
  }

  Future<void> _saveTranscript() async {
    await _ensureStoragePermission();
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    await FileSaverV2.saveTxt(
      content: text,
      fileName: 'transcription.txt',
      l10nText: 'Enregistrer la transcription',
    );
  }

  @override
  Widget build(BuildContext context) {
    final modelLabel = _model?.langText ?? '…';
    return Scaffold(
      drawer: const MalinaliDrawer(),
      appBar: AppBar(
        centerTitle: true,
        title: LanguagePill(
          label: modelLabel,
          onTap: _pickModel,
          loading: !_modelReady && _statusLabel.contains('Chargement'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
/*           Text(
            'Transcription audio',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: MalinaliChrome.onBlue,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8), */
          Text(
            'Recevez un partage whatsapp, ouvrez un fichier, '
            'ou utilisez le micro.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: MalinaliChrome.mutedOnBlue,
                ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _phase == _Phase.working && !_listening
                      ? null
                      : _pickAudio,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Fichier'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _sourcePath == null ||
                          (_phase == _Phase.working && !_listening)
                      ? null
                      : _transcribeFile,
                  icon: const Icon(Icons.transcribe),
                  label: const Text('Transcrire'),
                ),
              ),
            ],
          ),
          if (_sourceName != null) ...[
            const SizedBox(height: 8),
            Text(
              _sourceName!,
              style: const TextStyle(color: MalinaliChrome.mutedOnBlue),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: !_modelReady || (_phase == _Phase.working && !_listening)
                ? null
                : _toggleLiveMic,
            icon: Icon(_listening ? Icons.stop : Icons.mic),
            label: Text(_listening ? 'Arrêter le micro' : 'Micro en direct'),
          ),
          if (_statusLabel.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(_statusLabel),
          ],
          if (_phase == _Phase.working && !_listening) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: _fraction > 0 ? _fraction : null),
            TextButton(
              onPressed: () => setState(() => _cancelRequested = true),
              child: const Text('Annuler'),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _textController,
            maxLines: 12,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Transcript…',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _textController.text.trim().isEmpty
                      ? null
                      : _shareTranscript,
                  icon: const Icon(Icons.share),
                  label: const Text('Partager'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _textController.text.trim().isEmpty
                      ? null
                      : _saveTranscript,
                  icon: const Icon(Icons.save_alt),
                  label: const Text('Enregistrer'),
                ),
              ),
            ],
          ),
          if (_models.isEmpty && _modelReady == false && _error == null)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
