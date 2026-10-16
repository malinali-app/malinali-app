import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:languages_dart/languages_dart.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:malinali/pages/voice_setup_page.dart';
import 'package:malinali/utils/wakelock_helper.dart';
import 'package:malinali/widgets/connectivity_builder.dart';
import 'package:malinali/widgets/language_pill.dart';
import 'package:malinali/widgets/malinali_drawer.dart';
import 'package:malinali/services/local_voice_pairs.dart';
import 'package:malinali/services/malinali_audio_open_intent.dart';
import 'package:malinali/services/translation_model_service.dart';
import 'package:malinali/services/tts_service.dart';
import 'package:malinali/services/voice_pcm_stream.dart';
import 'package:malinali/services/voice_preferences.dart';
import 'package:malinali/services/voice_speech_resolver.dart';
import 'package:malinali/services/voice_turn_pipeline.dart';
import 'package:malinali/services/whisper_native.dart';
import 'package:malinali/services/whisper_specialist_models.dart';
import 'package:malinali/services/whisper_speech_service.dart';
import 'package:malinali/theme/malinali_chrome.dart';
import 'package:malinali/widgets/voice_pair_confirm_dialog.dart';
import 'package:malinali/widgets/voice_record_button.dart';

String _readableError(Object error) {
  if (error is StateError) {
    final message = error.message;
    if (message.isNotEmpty) return message;
  }
  final text = error.toString();
  const badState = 'Bad state: ';
  if (text.startsWith(badState)) return text.substring(badState.length);
  return text;
}

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
    this.decodeSharedAudio,
  });

  final VoicePreferencesStore? prefsStore;
  final TranslationModelService? modelService;
  final WhisperSpeechService? whisperService;
  final VoiceTurnPipeline? pipeline;
  final TtsService? ttsService;
  final VoiceSpeechResolver resolver;
  final VoicePreferences? initialPrefs;

  /// Decodes a shared note. Tests inject this to skip FFmpeg.
  final Future<DecodedSharedAudio> Function(String path)? decodeSharedAudio;

  @override
  State<VoiceChatPage> createState() => _VoiceChatPageState();
}

class _VoiceChatPageState extends State<VoiceChatPage> {
  late final VoicePreferencesStore _prefsStore;
  late final TranslationModelService _modelService;
  late final WhisperSpeechService _whisper;
  late final VoiceTurnPipeline _pipeline;
  late final TtsService _tts;
  final ScrollController _scrollController = ScrollController();

  VoicePreferences? _prefs;
  VoiceSpeechPlan? _plan;
  final List<VoiceTurn> _turns = [];
  String? _status;
  String? _error;
  bool _ready = false;
  bool _busy = false;
  bool _downloading = false;
  double? _downloadProgress;
  bool _ttsAvailable = false;
  StreamSubscription<String>? _audioShareSub;
  String? _currentLiveWavPath;
  String? _recordingsDir;
  Future<void>? _recordingStart;
  String? _queuedSharePath;
  bool _confirmingPair = false;
  bool _recordingBlocked = false;

  @override
  void initState() {
    super.initState();
    _prefsStore = widget.prefsStore ?? VoicePreferencesStore();
    _modelService = widget.modelService ?? TranslationModelService();
    _whisper = widget.whisperService ?? WhisperSpeechService();
    _tts = widget.ttsService ?? TtsService();
    _pipeline =
        widget.pipeline ??
        VoiceTurnPipeline(
          whisper: _whisper,
          modelService: _modelService,
          resolver: widget.resolver,
        );
    _audioShareSub = MalinaliAudioOpenIntent.instance.pathStream.listen(
      _openSharedAudio,
    );
    final pending = MalinaliAudioOpenIntent.instance.takePendingPath();
    if (pending != null && pending.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_openSharedAudio(pending));
      });
    }
    unawaited(_ensureRecordingsDir());
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
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _openSharedAudio(String path) async {
    if (!mounted || path.isEmpty) return;
    if (_prefs == null || _busy || _downloading || _confirmingPair) {
      _queuedSharePath = path;
      return;
    }
    if (_queuedSharePath == path) _queuedSharePath = null;
    _confirmingPair = true;
    try {
      final pairs = await supportedVoicePairs(
        prefs: _prefs!,
        resolver: widget.resolver,
      );
      if (!mounted) return;
      final choice = await showVoicePairConfirmDialog(
        context: context,
        pairs: pairs,
        initialSource: _prefs!.sourceIso,
        initialTarget: _prefs!.targetIso,
      );
      if (!mounted || choice == null) return;
      if (choice.openSetup) {
        _queuedSharePath = path;
        _confirmingPair = false;
        await _openSetup();
        return;
      }
      final newer = _queuedSharePath;
      if (newer != null && newer != path) return;
      final updated = _prefs!.copyWith(
        sourceIso: choice.sourceIso,
        targetIso: choice.targetIso,
      );
      await _prefsStore.save(updated);
      if (!mounted) return;
      final plan = widget.resolver.resolve(updated);
      setState(() {
        _prefs = updated;
        _plan = plan;
      });
      await _ensureDownloads();
      if (!mounted) return;
      if (_ready) {
        await _streamSharedNote(path, plan);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _readableError(e);
        _status = null;
      });
    } finally {
      _confirmingPair = false;
    }
    await _drainQueuedShare();
  }

  Future<void> _drainQueuedShare() async {
    final path = _queuedSharePath;
    if (!mounted || path == null || path.isEmpty) return;
    if (_prefs == null || _busy || _downloading || _confirmingPair) return;
    _queuedSharePath = null;
    await _openSharedAudio(path);
  }

  Future<void> _streamSharedNote(String path, VoiceSpeechPlan plan) async {
    setState(() {
      _busy = true;
      _error = null;
      _status = 'Décodage…';
    });
    final decode = widget.decodeSharedAudio ?? decodeSharedVoicePcm;
    late final DecodedSharedAudio decoded;
    try {
      decoded = await decode(path);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _readableError(e);
        _status = null;
      });
      return;
    }
    if (!mounted) return;
    final wavPath = await _copyWavForPlayback(decoded.wavPath);
    final live = VoiceTurn(
      wavPath: wavPath,
      sourceTranscript: '',
      targetText: '',
      isTranslating: true,
    );
    setState(() {
      _turns.add(live);
      _status = 'Transcription…';
    });
    final index = _turns.length - 1;
    try {
      final text = await _pipeline.streamPcm(
        pcm16: decoded.pcm16,
        plan: plan,
        onPartial: (partial) {
          if (!mounted || index >= _turns.length) return;
          setState(() {
            _turns[index] = _turns[index].copyWith(sourceTranscript: partial);
          });
        },
      );
      if (!mounted || index >= _turns.length) return;
      final turn = await _pipeline.finalizeTurn(
        turn: _turns[index].copyWith(sourceTranscript: text),
        plan: plan,
        engine: voiceStreamEngine(plan),
        onStatus: (s) {
          if (mounted) setState(() => _status = s);
        },
      );
      if (!mounted) return;
      setState(() {
        if (index < _turns.length) _turns[index] = turn;
        _busy = false;
        _status =
            turn.timings != null && kDebugMode
                ? turn.timings!.summaryLine
                : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (index < _turns.length) {
          final kept = _turns[index].sourceTranscript?.trim() ?? '';
          _turns[index] = _turns[index].copyWith(
            isTranslating: false,
            sourceTranscript: kept.isNotEmpty ? kept : _readableError(e),
          );
        }
        _busy = false;
        _error = _readableError(e);
        _status = null;
      });
    }
  }

  Future<void> _bootstrap() async {
    var prefs = widget.initialPrefs ?? await _prefsStore.load();
    if (prefs == null) {
      if (!mounted) return;
      final result = await Navigator.of(context).push<VoicePreferences>(
        MaterialPageRoute(builder: (_) => VoiceSetupPage(store: _prefsStore)),
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
    await _drainQueuedShare();
  }

  Future<void> _ensureDownloads() async {
    final plan = _plan;
    final prefs = _prefs;
    if (plan == null || prefs == null) return;
    setState(() {
      _downloading = true;
      _error = null;
      _downloadProgress = null;
      _status = 'Préparation des modèles…';
      _ready = false;
    });
    await WakelockHelper.enable();
    try {
      // 1. Identify all needed models
      final primaryReady = await _pipeline.modelsReady(plan);
      final extraModels = <TranslationModel>[];
      for (final tgtIso in prefs.targetLanguages) {
        if (tgtIso == prefs.targetIso) continue;
        final extraPlan = widget.resolver.resolve(
          prefs.copyWith(targetIso: tgtIso),
        );
        for (final m in extraPlan.marianDownloads) {
          if (!await _modelService.isModelDownloaded(m)) {
            if (!extraModels.any((em) => em.modelId == m.modelId)) {
              extraModels.add(m);
            }
          }
        }
      }

      if (!primaryReady || extraModels.isNotEmpty) {
        // Model is not available locally. Check connectivity before attempting fetch.
        final online = await isConnected;
        if (!online) {
          if (!mounted) return;
          setState(() {
            _downloading = false;
            _ready = primaryReady;
            _error =
                'Pas de connexion Internet. Impossible de télécharger tous les modèles.';
            _status = primaryReady ? null : 'Hors ligne';
          });
          return;
        }

        final totalTasks = (primaryReady ? 0 : 1) + extraModels.length;
        var completedTasks = 0;

        // Download primary models first
        if (!primaryReady) {
          await _pipeline.ensureModels(
            plan,
            onStatus: (s) {
              if (mounted) setState(() => _status = s);
            },
            onProgress: (p) {
              if (mounted) {
                setState(
                  () => _downloadProgress = (completedTasks + (p ?? 0)) / totalTasks,
                );
              }
            },
          );
          completedTasks++;
        }

        // Then download extra target models if needed
        for (var i = 0; i < extraModels.length; i++) {
          final model = extraModels[i];
          final step =
              extraModels.length == 1
                  ? ''
                  : ' (${i + 1}/${extraModels.length})';
          if (mounted) {
            setState(() {
              _status = 'Téléchargement ${model.displayName}$step…';
            });
          }
          await _modelService.downloadModel(
            model,
            onProgress: (received, total) {
              if (mounted && total > 0) {
                final p = received / total;
                setState(
                  () => _downloadProgress = (completedTasks + p) / totalTasks,
                );
              }
            },
          );
          completedTasks++;
        }
      }
      // Speech model and Marian hops for this pair. The mic stays off until
      // both are on disk, so a missing pack cannot open a turn stuck on
      // « Écoute... ».
      if (!mounted) return;
      if (!await _pipeline.modelsReady(plan)) {
        setState(() {
          _ready = false;
          _downloading = false;
          _downloadProgress = null;
          _error = 'Les modèles de cette paire ne sont pas prêts.';
          _status = 'Modèles manquants';
        });
        return;
      }
      setState(() {
        _ready = true;
        _downloading = false;
        _downloadProgress = null;
        _status = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _ready = false;
        _downloadProgress = null;
        _error = _readableError(e);
        _status = 'Erreur de téléchargement';
      });
    } finally {
      await WakelockHelper.disable();
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _onRecordingComplete(String path) async {
    final plan = _plan;
    if (plan == null || !_ready) return;

    final start = _recordingStart;
    if (start != null) {
      try {
        await start;
      } catch (_) {
        return;
      }
    }
    if (_recordingBlocked) {
      _recordingBlocked = false;
      return;
    }

    var wavPath = _currentLiveWavPath;
    _currentLiveWavPath = null;
    if ((wavPath == null || wavPath.isEmpty) &&
        path != 'external' &&
        File(path).existsSync()) {
      wavPath = path;
    }
    if (wavPath == null || wavPath.isEmpty) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Enregistrement audio introuvable.';
        _status = null;
      });
      return;
    }

    // Check if we already have a live turn for this path
    final index = _turns.indexWhere((t) => t.wavPath == wavPath);
    final existingLiveTurn = index != -1 ? _turns[index] : null;

    setState(() {
      _busy = true;
      _error = null;
      _status = 'Transcription…';
    });

    try {
      final finalText = await _whisper.stopListening();
      final spoken = preferSpokenTranscript(
        finalText,
        existingLiveTurn?.sourceTranscript,
      );
      if (existingLiveTurn != null && spoken.isNotEmpty) {
        setState(() {
          _turns[index] = existingLiveTurn.copyWith(sourceTranscript: spoken);
        });
      }

      await _whisper.fixWavHeader(wavPath);
      if (spoken.isEmpty) {
        if (!mounted) return;
        setState(() {
          if (index != -1) {
            _turns[index] = _turns[index].copyWith(
              isTranslating: false,
              sourceTranscript: 'Aucune parole détectée.',
            );
          }
          _busy = false;
          _error = 'Aucune parole détectée.';
          _status = null;
        });
        return;
      }

      final turn = await _pipeline.finalizeTurn(
        turn: (existingLiveTurn ??
                VoiceTurn(
                  wavPath: wavPath,
                  sourceTranscript: spoken,
                  targetText: '',
                ))
            .copyWith(sourceTranscript: spoken),
        plan: plan,
        onStatus: (s) {
          if (mounted) setState(() => _status = s);
        },
      );
      if (!mounted) return;
      setState(() {
        if (index != -1) {
          _turns[index] = turn;
        } else {
          _turns.add(turn);
        }
        _busy = false;
        _status =
            turn.timings != null && kDebugMode
                ? turn.timings!.summaryLine
                : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (index != -1) {
          final kept = preferSpokenTranscript(
            '',
            _turns[index].sourceTranscript,
          );
          _turns[index] = _turns[index].copyWith(
            isTranslating: false,
            sourceTranscript: kept.isNotEmpty ? kept : _readableError(e),
          );
        }
        _busy = false;
        _error = _readableError(e);
        _status = null;
      });
    }
  }

  void _onRecordingStart() {
    final plan = _plan;
    if (plan == null) return;
    _recordingStart = _beginRecording(plan);
  }

  Future<void> _beginRecording(VoiceSpeechPlan plan) async {
    if (!await _pipeline.modelsReady(plan)) {
      _recordingBlocked = true;
      if (mounted) {
        setState(() {
          _ready = false;
          _error = 'Les modèles de cette paire ne sont pas prêts.';
          _status = 'Modèles manquants';
        });
      }
      if (!_downloading) {
        await _ensureDownloads();
      }
      return;
    }
    _recordingBlocked = false;

    await _ensureRecordingsDir();
    final dirPath = _recordingsDir;
    if (dirPath == null) return;
    final wavPath = p.join(
      dirPath,
      'audio_${DateTime.now().millisecondsSinceEpoch}.wav',
    );
    _currentLiveWavPath = wavPath;

    final liveTurn = VoiceTurn(
      wavPath: wavPath,
      sourceTranscript: '',
      targetText: '',
      isTranslating: true,
    );

    setState(() {
      _turns.add(liveTurn);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    _whisper.onPartialResult = (partial) {
      if (!mounted) return;
      final idx = _turns.indexWhere((t) => t.wavPath == wavPath);
      if (idx != -1) {
        setState(() {
          _turns[idx] = _turns[idx].copyWith(sourceTranscript: partial);
        });
        _scrollToBottom();
      }
    };

    _whisper.onResult = (finalText) {
      if (!mounted) return;
      final idx = _turns.indexWhere((t) => t.wavPath == wavPath);
      if (idx != -1) {
        setState(() {
          _turns[idx] = _turns[idx].copyWith(sourceTranscript: finalText);
        });
      }
    };

    try {
      await _startLiveCapture(wavPath, plan);
    } catch (e) {
      debugPrint('Error starting live STT: $e');
      if (mounted) {
        setState(() {
          _turns.removeWhere((t) => t.wavPath == wavPath);
          _error = 'Impossible de démarrer l\'enregistrement';
        });
      }
      rethrow;
    }
  }

  Future<void> _ensureRecordingsDir() async {
    if (_recordingsDir != null) return;
    final docs = await getApplicationDocumentsDirectory();
    final dirPath = p.join(docs.path, 'voice_recordings');
    Directory(dirPath).createSync(recursive: true);
    _recordingsDir = dirPath;
  }

  Future<String> _copyWavForPlayback(String sourcePath) async {
    final source = File(sourcePath);
    if (!source.existsSync()) return sourcePath;
    await _ensureRecordingsDir();
    final dirPath = _recordingsDir;
    if (dirPath == null) return sourcePath;
    if (p.dirname(sourcePath) == dirPath) return sourcePath;
    final dest = p.join(
      dirPath,
      'audio_${DateTime.now().millisecondsSinceEpoch}.wav',
    );
    await source.copy(dest);
    return dest;
  }

  Future<void> _startLiveCapture(String wavPath, VoiceSpeechPlan plan) async {
    await _activatePlanModel(plan);
    await _whisper.startListening(
      wavPath: wavPath,
      language: plan.whisperLanguage,
      translate: plan.translateToEnglish,
    );
  }

  Future<void> _activatePlanModel(VoiceSpeechPlan plan) async {
    final specialist = plan.specialist;
    if (specialist != null &&
        await _whisper.isSpecialistDownloaded(specialist)) {
      await _whisper.setActivePack(specialist);
      return;
    }
    await _whisper.setGenericModel(plan.genericModel);
    await _whisper.setActivePack(null);
  }

  void _onRecordingCancel() {
    final path = _currentLiveWavPath;
    _currentLiveWavPath = null;
    setState(() {
      _turns.removeWhere((t) => t.wavPath == path);
    });
    _whisper.stopListening().then((_) {
      if (path != null) {
        final f = File(path);
        if (f.existsSync()) f.deleteSync();
      }
    });
  }

  Future<void> _openSetup() async {
    final current = _prefs ?? VoicePreferences.defaults;
    final updated = await Navigator.of(context).push<VoicePreferences>(
      MaterialPageRoute(
        builder: (_) => VoiceSetupPage(store: _prefsStore, initial: current),
      ),
    );
    if (updated == null || !mounted) {
      await _drainQueuedShare();
      return;
    }
    setState(() {
      _prefs = updated;
      _plan = widget.resolver.resolve(updated);
      _turns.clear();
    });
    await _ensureDownloads();
    await _drainQueuedShare();
  }

  String get _pairLabel {
    final prefs = _prefs;
    if (prefs == null) return 'Traduction vocale';
    final srcLang = voiceLanguageByIso(prefs.sourceIso);
    final tgtLang = voiceLanguageByIso(prefs.targetIso);
    final src =
        srcLang == null
            ? prefs.sourceIso
            : (srcLang.name.isEmpty ? srcLang.nameEn : srcLang.name);
    final tgt =
        tgtLang == null
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
        child: Stack(
          children: [
            Column(
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
                            style: const TextStyle(
                              color: MalinaliChrome.mutedOnBlue,
                            ),
                          ),
                        if (_downloading) ...[
                          const SizedBox(height: 8),
                          LinearProgressIndicator(value: _downloadProgress),
                          if (_downloadProgress != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              '${(_downloadProgress! * 100).toStringAsFixed(0)} %',
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                fontFamily: 'NotoSans',
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: MalinaliChrome.yellowBorder,
                              ),
                            ),
                          ],
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
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
                  child:
                      _turns.isEmpty
                          ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child:
                                  (!_ready ||
                                          (_busy &&
                                              _status == 'Transcription…'))
                                      ? const CircularProgressIndicator()
                                      : Text(
                                        'Maintenez le micro pour parler.',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: MalinaliChrome.mutedOnBlue,
                                        ),
                                      ),
                            ),
                          )
                          : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                            itemCount: _turns.length,
                            itemBuilder: (context, index) {
                              return VoiceTurnBubbles(
                                turn: _turns[index],
                                sourceIso: _prefs?.sourceIso ?? 'fr',
                                targetIso: _prefs?.targetIso ?? 'fr',
                                tts: _tts,
                                ttsAvailable: _ttsAvailable,
                              );
                            },
                          ),
                ),
              ],
            ),
            Positioned(
              bottom: 24,
              right: 24,
              child: VoiceRecordButton(
                enabled: _ready && !_busy && !_downloading,
                onRecordingComplete: _onRecordingComplete,
                onRecordingStart: _onRecordingStart,
                onRecordingCancel: _onRecordingCancel,
                useExternalRecording: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class VoiceTurnBubbles extends StatelessWidget {
  const VoiceTurnBubbles({
    super.key,
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
                  leading: const Icon(
                    Icons.share,
                    color: MalinaliChrome.onBlue,
                  ),
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
    final iso = (targetLang?.localeIntl.locale.languageCode ?? targetIso)
        .toLowerCase();
    final isWellSupported =
        tts.isLanguageWellSupported(targetIso) ||
        tts.isLanguageWellSupported(iso);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onLongPress: () {
            final text = [
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
                    if (!(turn.isTranslating && turn.targetText.isEmpty))
                      _WavPlayRow(path: turn.wavPath),
                    if (_showSourceText ||
                        (turn.isTranslating && turn.targetText.isEmpty)) ...[
                      const SizedBox(height: 8),
                      Text(
                        turn.sourceTranscript?.isNotEmpty == true
                            ? turn.sourceTranscript!
                            : 'Écoute...',
                        style: TextStyle(
                          color:
                              turn.isTranslating && turn.targetText.isEmpty
                                  ? MalinaliChrome.sourceText.withValues(
                                    alpha: 0.6,
                                  )
                                  : MalinaliChrome.sourceText,
                          fontStyle:
                              turn.isTranslating && turn.targetText.isEmpty
                                  ? FontStyle.italic
                                  : FontStyle.normal,
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
        if (!turn.isTranslating)
          GestureDetector(
            onLongPress:
                _showTargetText
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
                      color: MalinaliChrome.yellowBorder.withValues(
                        alpha: 0.35,
                      ),
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
                          color:
                              _showTargetText
                                  ? MalinaliChrome.targetText
                                  : MalinaliChrome.mutedOnBlue,
                          fontSize: 16,
                          fontStyle:
                              _showTargetText
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
                              tooltip: 'Écouter',
                              onPressed: () async {
                                final lang = targetLang ??
                                    (targetIso.toLowerCase() == 'wo'
                                        ? Languages.wolof
                                        : null);
                                if (lang == null) return;
                                final ok = await tts.speak(
                                  turn.targetText,
                                  lang,
                                );
                                if (!ok && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
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
      await repairWavHeader(widget.path);
      final duration = await _player.setFilePath(widget.path);
      if (duration == Duration.zero) {
        throw StateError('Audio vide');
      }
      if (!mounted) return;
      setState(() => _playing = true);
      await _player.seek(Duration.zero);
      await _player.play();
      await _player.processingStateStream.firstWhere(
        (state) => state == ProcessingState.completed,
      );
    } catch (e) {
      debugPrint('Error playing audio: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lecture impossible : ${_readableError(e)}')),
        );
      }
    } finally {
      if (mounted && _playing) setState(() => _playing = false);
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
        const Text('Audio', style: TextStyle(color: MalinaliChrome.onBlue)),
      ],
    );
  }
}
