import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:share_plus/share_plus.dart';
import 'package:malinali/pages/voice_setup_page.dart';
import 'package:malinali/pages/vosk_transcription_page.dart';
import 'package:malinali/widgets/language_pill.dart';
import 'package:malinali/widgets/malinali_drawer.dart';
import 'package:malinali/services/malinali_audio_open_intent.dart';
import 'package:malinali/services/marian_runtime.dart';
import 'package:malinali/services/translation_model_service.dart';
import 'package:malinali/services/tts_service.dart';
import 'package:malinali/services/voice_preferences.dart';
import 'package:malinali/services/voice_speech_resolver.dart';
import 'package:malinali/services/voice_turn_pipeline.dart';
import 'package:malinali/services/vosk_model_service.dart';
import 'package:malinali/services/whisper_specialist_models.dart';
import 'package:malinali/services/whisper_speech_service.dart';
import 'package:malinali/theme/malinali_chrome.dart';
import 'package:malinali/widgets/voice_record_button.dart';
import 'package:marian_flutter/marian_flutter.dart';

/// Voice-first home: hold-to-record chat with speech → English → Marian.
class VoiceChatPage extends StatefulWidget {
  const VoiceChatPage({
    super.key,
    this.prefsStore,
    this.modelService,
    this.whisperService,
    this.pipeline,
    this.ttsService,
    this.resolver = const VoiceSpeechResolver(),
    this.initialPrefs,
  });

  final VoicePreferencesStore? prefsStore;
  final TranslationModelService? modelService;
  final WhisperSpeechService? whisperService;
  final VoiceTurnPipeline? pipeline;
  final TtsService? ttsService;
  final VoiceSpeechResolver resolver;
  final VoicePreferences? initialPrefs;

  @override
  State<VoiceChatPage> createState() => _VoiceChatPageState();
}

class _VoiceChatPageState extends State<VoiceChatPage> {
  late final VoicePreferencesStore _prefsStore;
  late final TranslationModelService _modelService;
  late final WhisperSpeechService _whisper;
  late final VoiceTurnPipeline _pipeline;
  late final TtsService _tts;

  VoicePreferences? _prefs;
  VoiceSpeechPlan? _plan;
  final List<VoiceTurn> _turns = [];
  String? _status;
  String? _error;
  bool _ready = false;
  bool _busy = false;
  bool _downloading = false;
  bool _ttsAvailable = false;
  StreamSubscription<String>? _audioShareSub;

  @override
  void initState() {
    super.initState();
    _prefsStore = widget.prefsStore ?? VoicePreferencesStore();
    _modelService = widget.modelService ?? TranslationModelService();
    _whisper = widget.whisperService ?? WhisperSpeechService();
    _tts = widget.ttsService ?? TtsService();
    _pipeline = widget.pipeline ??
        VoiceTurnPipeline(
          whisper: _whisper,
          modelService: _modelService,
          resolver: widget.resolver,
        );
    _audioShareSub =
        MalinaliAudioOpenIntent.instance.pathStream.listen(_openSharedAudio);
    final pending = MalinaliAudioOpenIntent.instance.takePendingPath();
    if (pending != null && pending.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_openSharedAudio(pending));
      });
    }
    unawaited(_bootstrap());
    _checkTtsAvailability();
  }

  Future<void> _checkTtsAvailability() async {
    final available = await _tts.isAvailable();
    if (!mounted) return;
    setState(() => _ttsAvailable = available);
  }

  @override
  void dispose() {
    _audioShareSub?.cancel();
    super.dispose();
  }

  Future<void> _openSharedAudio(String path) async {
    if (!mounted || path.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VoskTranscriptionPage(
          voskService: VoskModelService(),
          initialAudioPath: path,
        ),
      ),
    );
  }

  Future<void> _bootstrap() async {
    try {
      await MarianService.initRust();
    } catch (_) {
      // May already be initialized from boot.
    }

    var prefs = widget.initialPrefs ?? await _prefsStore.load();
    if (prefs == null) {
      if (!mounted) return;
      final result = await Navigator.of(context).push<VoicePreferences>(
        MaterialPageRoute(
          builder: (_) => VoiceSetupPage(store: _prefsStore),
        ),
      );
      prefs = result ?? await _prefsStore.load() ?? VoicePreferences.defaults;
      if (result == null) {
        await _prefsStore.save(prefs);
      }
    }

    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _plan = widget.resolver.resolve(prefs!);
    });
    await _ensureDownloads();
  }

  Future<void> _ensureDownloads() async {
    final plan = _plan;
    if (plan == null) return;
    setState(() {
      _downloading = true;
      _error = null;
      _status = 'Préparation des modèles…';
      _ready = false;
    });
    try {
      final already = await _pipeline.modelsReady(plan);
      if (!already) {
        await _pipeline.ensureModels(
          plan,
          onStatus: (s) {
            if (mounted) setState(() => _status = s);
          },
        );
      }
      // Preload English→target into runtime when present.
      final toTarget = plan.englishToTarget;
      if (toTarget != null) {
        setState(() => _status = 'Chargement ${toTarget.displayName}…');
        final dir = await _modelService.downloadModel(toTarget);
        final marian = await MarianService.loadFromDirectory(dir.path);
        MarianRuntime.instance.attach(marian, toTarget);
      }
      if (!mounted) return;
      setState(() {
        _ready = true;
        _downloading = false;
        _status = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _ready = false;
        _error = e.toString();
        _status = 'Erreur de téléchargement';
      });
    }
  }

  Future<void> _onRecordingComplete(String path) async {
    final plan = _plan;
    if (plan == null || !_ready || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _status = 'Transcription…';
    });
    try {
      final turn = await _pipeline.run(wavPath: path, plan: plan);
      if (!mounted) return;
      setState(() {
        _turns.add(turn);
        _busy = false;
        _status = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
        _status = null;
      });
    }
  }

  Future<void> _openSetup() async {
    final current = _prefs ?? VoicePreferences.defaults;
    final updated = await Navigator.of(context).push<VoicePreferences>(
      MaterialPageRoute(
        builder: (_) => VoiceSetupPage(
          store: _prefsStore,
          initial: current,
        ),
      ),
    );
    if (updated == null || !mounted) return;
    setState(() {
      _prefs = updated;
      _plan = widget.resolver.resolve(updated);
      _turns.clear();
    });
    await _ensureDownloads();
  }

  String get _pairLabel {
    final prefs = _prefs;
    if (prefs == null) return 'Conversation';
    final srcLang = voiceLanguageByIso(prefs.sourceIso);
    final tgtLang = voiceLanguageByIso(prefs.targetIso);
    final src = srcLang == null
        ? prefs.sourceIso
        : (srcLang.name.isEmpty ? srcLang.nameEn : srcLang.name);
    final tgt = tgtLang == null
        ? prefs.targetIso
        : (tgtLang.name.isEmpty ? tgtLang.nameEn : tgtLang.name);
    return '$src → $tgt';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: MalinaliDrawer(onConversationTap: _openSetup),
      appBar: AppBar(
        centerTitle: true,
        title: LanguagePill(
          label: _pairLabel,
          onTap: _openSetup,
          loading: _downloading,
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_status != null || _error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_status != null)
                      Text(
                        _status!,
                        style: const TextStyle(color: MalinaliChrome.mutedOnBlue),
                      ),
                    if (_downloading) ...[
                      const SizedBox(height: 8),
                      const LinearProgressIndicator(),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                      TextButton(
                        onPressed: _ensureDownloads,
                        child: const Text('Réessayer'),
                      ),
                    ],
                  ],
                ),
              ),
            Expanded(
            child: _turns.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: (!_ready || _busy)
                          ? const CircularProgressIndicator()
                          : Text(
                              'Maintenez le micro pour parler.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: MalinaliChrome.mutedOnBlue),
                            ),
                    ),
                  )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _turns.length,
                      itemBuilder: (context, index) {
                        return _VoiceTurnBubbles(
                          turn: _turns[index],
                          sourceIso: _prefs?.sourceIso ?? 'wo',
                          targetIso: _prefs?.targetIso ?? 'fr',
                          tts: _tts,
                          ttsAvailable: _ttsAvailable,
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 24, 32),
              child: SizedBox(
                height: 220,
                child: Align(
                  alignment: Alignment.bottomRight,
                  child: VoiceRecordButton(
                    enabled: _ready && !_busy && !_downloading,
                    onRecordingComplete: _onRecordingComplete,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoiceTurnBubbles extends StatelessWidget {
  const _VoiceTurnBubbles({
    required this.turn,
    required this.sourceIso,
    required this.targetIso,
    required this.tts,
    required this.ttsAvailable,
  });

  final VoiceTurn turn;
  final String sourceIso;
  final String targetIso;
  final TtsService tts;
  final bool ttsAvailable;

  /// Wolof source text only exists on the fine-tune path (English bridge set).
  bool get _showSourceText {
    final text = turn.sourceTranscript;
    if (text == null || text.isEmpty) return false;
    if (sourceIso == 'wo' && !kShowWolofText && turn.englishText != null) {
      return false;
    }
    return true;
  }

  bool get _showTargetText => targetIso != 'wo' || kShowWolofText;

  void _copy(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copié dans le presse-papier'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _share(String text) {
    SharePlus.instance.share(ShareParams(text: text));
  }

  void _showMenu(BuildContext context, String text) {
    showModalBottomSheet(
      context: context,
      backgroundColor: MalinaliChrome.bluePanel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (context) => SafeArea(
            child: Wrap(
              children: [
                ListTile(
                  leading: const Icon(Icons.copy, color: MalinaliChrome.onBlue),
                  title: const Text(
                    'Copier',
                    style: TextStyle(color: MalinaliChrome.onBlue),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _copy(context, text);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.share, color: MalinaliChrome.onBlue),
                  title: const Text(
                    'Partager',
                    style: TextStyle(color: MalinaliChrome.onBlue),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _share(text);
                  },
                ),
              ],
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final targetLang = voiceLanguageByIso(targetIso);
    final iso = targetLang?.localeIntl.locale.languageCode.toLowerCase();
    final isWellSupported = iso != null && tts.isLanguageWellSupported(iso);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onLongPress: () {
            final text =
                [
                  if (_showSourceText) turn.sourceTranscript,
                  if (turn.englishText != null) turn.englishText,
                ].join('\n');
            if (text.isNotEmpty) _showMenu(context, text);
          },
          child: Align(
            alignment: Alignment.centerRight,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.85,
              ),
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 6),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: MalinaliChrome.bluePanel,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: MalinaliChrome.whiteBorder.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _WavPlayRow(path: turn.wavPath),
                    if (_showSourceText) ...[
                      const SizedBox(height: 8),
                      Text(
                        turn.sourceTranscript!,
                        style: const TextStyle(
                          color: MalinaliChrome.sourceText,
                        ),
                      ),
                    ],
                    if (turn.englishText != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        turn.englishText!,
                        style: const TextStyle(
                          color: MalinaliChrome.mutedOnBlue,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        GestureDetector(
          onLongPress: _showTargetText
              ? () => _showMenu(context, turn.targetText)
              : null,
          child: Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.85,
              ),
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 6),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: MalinaliChrome.customPanel,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: MalinaliChrome.yellowBorder.withValues(alpha: 0.35),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _showTargetText
                          ? turn.targetText
                          : 'Le texte wolof n’est pas affiché pour l’instant.',
                      style: TextStyle(
                        color: _showTargetText
                            ? MalinaliChrome.targetText
                            : MalinaliChrome.mutedOnBlue,
                        fontSize: 16,
                        fontStyle: _showTargetText
                            ? FontStyle.normal
                            : FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (ttsAvailable && isWellSupported)
                          IconButton(
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            icon: const Icon(
                              Icons.volume_up_rounded,
                              color: MalinaliChrome.yellowBorder,
                              size: 20,
                            ),
                            onPressed:
                                targetLang == null
                                    ? null
                                    : () async {
                                      final ok = await tts.speak(
                                        turn.targetText,
                                        targetLang,
                                      );
                                      if (!ok && context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'Synthèse vocale indisponible pour cette langue.',
                                                ),
                                              ),
                                            );
                                      }
                                    },
                          ),
                        IconButton(
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          icon: const Icon(
                            Icons.copy_rounded,
                            color: MalinaliChrome.yellowBorder,
                            size: 20,
                          ),
                          onPressed: () => _copy(context, turn.targetText),
                          tooltip: 'Copier',
                        ),
                        IconButton(
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          icon: const Icon(
                            Icons.share_rounded,
                            color: MalinaliChrome.yellowBorder,
                            size: 20,
                          ),
                          onPressed: () => _share(turn.targetText),
                          tooltip: 'Partager',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _WavPlayRow extends StatefulWidget {
  const _WavPlayRow({required this.path});

  final String path;

  @override
  State<_WavPlayRow> createState() => _WavPlayRowState();
}

class _WavPlayRowState extends State<_WavPlayRow> {
  final AudioPlayer _player = AudioPlayer();
  bool _playing = false;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
      if (mounted) setState(() => _playing = false);
      return;
    }
    try {
      await _player.setFilePath(widget.path);
      if (mounted) setState(() => _playing = true);
      await _player.play();
      await _player.playerStateStream.firstWhere(
        (s) => s.processingState == ProcessingState.completed,
      ).timeout(const Duration(seconds: 30), onTimeout: () => _player.playerState);
    } catch (e) {
      debugPrint('Error playing audio: $e');
    } finally {
      if (mounted) setState(() => _playing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          icon: Icon(
            _playing ? Icons.pause : Icons.play_arrow,
            color: MalinaliChrome.yellowBorder,
          ),
          onPressed: _toggle,
        ),
        const Text(
          'Audio',
          style: TextStyle(color: MalinaliChrome.onBlue),
        ),
      ],
    );
  }
}
