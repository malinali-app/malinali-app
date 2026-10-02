import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:languages_dart/languages_dart.dart';
import 'package:malinali/pages/audio_transcription_page.dart';
import 'package:malinali/pages/document_translation_page.dart';
import 'package:malinali/pages/settings_page.dart';
import 'package:malinali/pages/translation_settings_page.dart';
import 'package:malinali/services/malinali_audio_open_intent.dart';
import 'package:malinali/services/marian_runtime.dart';
import 'package:malinali/services/speech_recognition_service.dart';
import 'package:malinali/services/translation_model_service.dart';
import 'package:malinali/services/vosk_model_service.dart';
import 'package:malinali/theme/malinali_chrome.dart';
import 'package:malinali/widgets/language_picker_sheet.dart';
import 'package:marian_flutter/marian_flutter.dart';
import 'package:share_plus/share_plus.dart';

/// Language-agnostic translate screen (MarianMT + dynamic Vosk mic).
class TranslatePage extends StatefulWidget {
  const TranslatePage({
    super.key,
    required this.initialMarian,
    this.initialModel,
    this.modelService,
    this.voskService,
    this.speechService,
  });

  final MarianService initialMarian;
  final TranslationModel? initialModel;
  final TranslationModelService? modelService;
  final VoskModelService? voskService;
  final SpeechRecognitionService? speechService;

  @override
  State<TranslatePage> createState() => _TranslatePageState();
}

class _TranslatePageState extends State<TranslatePage> {
  final _inputController = TextEditingController();
  final _inputFocusNode = FocusNode();
  final _inputScrollController = ScrollController();
  late final TranslationModelService _modelService;
  late final VoskModelService _voskService;

  late MarianService _marian;
  SpeechRecognitionService? _speech;

  Language _sourceLang = Languages.french;
  Language _targetLang = Languages.english;
  List<TranslationModel> _availableModels = [];
  TranslationModel? _selectedModel;
  Map<String, bool> _downloadedStatus = {};

  List<VoskModel> _voskModels = [];
  Map<String, bool> _voskDownloadedStatus = {};
  VoskModel? _matchingVoskModel;
  bool _isVoskModelDownloaded = false;
  bool _isDownloadingVosk = false;

  String _output = '';
  String? _error;
  bool _busy = false;
  bool _loadingModel = false;
  String _loadingModelLabel = 'Chargement...';
  bool _listening = false;
  bool _speechReady = false;
  StreamSubscription<String>? _audioShareSub;

  @override
  void initState() {
    super.initState();
    _modelService = widget.modelService ?? TranslationModelService();
    _voskService = widget.voskService ?? VoskModelService();
    _marian = widget.initialMarian;
    final boot = widget.initialModel ?? TranslationModelService.defaultBootModel;
    _selectedModel = boot;
    _sourceLang = boot.sourceLang;
    _targetLang = boot.targetLang;
    MarianRuntime.instance.attach(_marian, boot);
    _speech = widget.speechService ?? SpeechRecognitionService(modelService: _voskService);

    _inputController.addListener(() => setState(() {}));
    _initVoskAndSpeech();
    _loadAvailableModels();
    _listenForSharedAudio();
  }

  void _listenForSharedAudio() {
    final pending = MalinaliAudioOpenIntent.instance.takePendingPath();
    if (pending != null && pending.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openAudioTranscription(initialAudioPath: pending);
      });
    }
    _audioShareSub = MalinaliAudioOpenIntent.instance.pathStream.listen((path) {
      if (!mounted || path.isEmpty) return;
      MalinaliAudioOpenIntent.instance.takePendingPath();
      _openAudioTranscription(initialAudioPath: path);
    });
  }

  Future<void> _initVoskAndSpeech() async {
    try {
      final models = await _voskService.fetchAllSmallModels();
      if (!mounted) return;
      setState(() {
        _voskModels = models;
      });
      await _updateVoskModelForSource();
    } catch (_) {}
  }

  Future<void> _updateVoskModelForSource() async {
    final matching = _voskService.findModelForLanguage(_sourceLang, _voskModels);
    final downloaded = matching != null && await _voskService.isModelDownloaded(matching);

    if (!mounted) return;

    setState(() {
      _matchingVoskModel = matching;
      _isVoskModelDownloaded = downloaded;
      _speechReady = false;
      if (matching != null) {
        _voskDownloadedStatus = {
          ..._voskDownloadedStatus,
          matching.name: downloaded,
        };
      }
    });

    if (matching != null && downloaded) {
      await _initSpeechForModel(matching);
    }
  }

  Future<void> _initSpeechForModel(VoskModel model) async {
    final speech = _speech;
    if (speech == null) return;

    try {
      await speech.initialize(model: model);
      speech.onPartialResult = (partial) {
        if (!mounted || !_listening) return;
        _inputController.text = partial;
        _inputController.selection = TextSelection.collapsed(
          offset: _inputController.text.length,
        );
      };
      speech.onResult = (result) {
        if (!mounted) return;
        final text = result.trim();
        if (text.isEmpty) return;
        _inputController.text = text;
        _inputController.selection = TextSelection.collapsed(
          offset: text.length,
        );
      };
      speech.onError = () {
        if (mounted) setState(() => _listening = false);
      };
      if (mounted) setState(() => _speechReady = true);
    } catch (_) {
      if (mounted) setState(() => _speechReady = false);
    }
  }

  Future<void> _refreshDownloadedStatus([List<TranslationModel>? models]) async {
    final list = models ?? _availableModels;
    final status = <String, bool>{};
    for (final model in list) {
      status[model.modelId] =
          model.isAsset || await _modelService.isModelDownloaded(model);
    }
    if (!mounted) return;
    setState(() => _downloadedStatus = status);
  }

  Future<void> _loadAvailableModels() async {
    final models = await _modelService.fetchAvailableModels(_sourceLang);
    if (!mounted) return;

    setState(() {
      _availableModels = models;
    });
    await _refreshDownloadedStatus(models);

    if (models.isEmpty) return;

    // Keep the boot / last-selected model; do not auto-switch on startup
    // (that caused a second 5–10s load after MarianBootScreen).
    final selectedId = _selectedModel?.modelId;
    if (selectedId != null && models.any((m) => m.modelId == selectedId)) {
      return;
    }

    final currentTargetIso = _targetLang.localeIntl.locale.languageCode;
    TranslationModel? nextModel;

    // Try to keep current target if available for the new source
    for (final m in models) {
      if (m.targetLang.localeIntl.locale.languageCode == currentTargetIso) {
        nextModel = m;
        break;
      }
    }

    // Otherwise default to the first one (e.g. Fula if available)
    nextModel ??= models.first;
    if (nextModel.modelId == _selectedModel?.modelId) return;

    final isDownloaded = nextModel.isAsset ||
        (_downloadedStatus[nextModel.modelId] ?? false);
    if (!isDownloaded) {
      if (!mounted) return;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Téléchargement requis'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Le modèle de traduction pour ${nextModel!.displayName} doit être téléchargé'
                ' (${nextModel.downloadSizeHint ?? 'environ 150 Mo'}).',
              ),
              const SizedBox(height: 12),
              const Text(
                'Ne quittez pas l\'écran et ne mettez pas l\'application en arrière-plan pendant le téléchargement.',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.redAccent),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Plus tard'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Télécharger'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }
    await _switchModel(nextModel);
  }

  Future<void> _switchModel(TranslationModel model) async {
    if (!mounted) return;

    setState(() {
      _loadingModel = true;
      _loadingModelLabel = model.downloadSizeHint != null
          ? 'Téléchargement ${model.downloadSizeHint}…'
          : 'Chargement...';
      _error = null;
    });

    try {
      MarianService marian;
      if (model.isAsset) {
        marian = await MarianService.loadFromAssets(
          assetFolder: model.modelId,
        );
      } else {
        final dir = await _modelService.downloadModel(model);
        marian = await MarianService.loadFromDirectory(dir.path);
      }

      if (!mounted) return;
      MarianRuntime.instance.attach(marian, model);
      await MarianRuntime.saveLastSelectedModel(model);
      if (!mounted) return;
      setState(() {
        _marian = marian;
        _selectedModel = model;
        _targetLang = model.targetLang;
        _sourceLang = model.sourceLang;
        _loadingModel = false;
        _output = '';
        _downloadedStatus = {
          ..._downloadedStatus,
          model.modelId: true,
        };
      });
      await _updateVoskModelForSource();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingModel = false;
          _error = 'Erreur lors du chargement du modèle : $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _audioShareSub?.cancel();
    _speech?.dispose();
    _inputController.dispose();
    _inputFocusNode.dispose();
    _inputScrollController.dispose();
    super.dispose();
  }

  Future<void> _translate() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _busy) return;

    setState(() {
      _busy = true;
      _error = null;
      _output = '';
    });

    try {
      final translated = await _marian.translate(
        text,
        config: kStreetTranslationConfig,
      );
      if (!mounted) return;
      setState(() => _output = translated.trim());
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleListening() async {
    final speech = _speech;
    if (speech == null || !_speechReady || _busy) return;
    if (_listening || speech.isListening) {
      await speech.stopListening();
      if (mounted) {
        setState(() => _listening = false);
        _translate();
      }
      return;
    }
    setState(() => _listening = true);
    try {
      await speech.startListening();
    } catch (e) {
      if (mounted) {
        setState(() {
          _listening = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _promptDownloadVoskModel(VoskModel model) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Saisie vocale en ${model.langText}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pour dicter votre texte en ${model.langText}, le modèle vocal (${model.sizeText}) doit être téléchargé.',
            ),
            const SizedBox(height: 12),
            const Text(
              'Ne quittez pas l\'écran et ne mettez pas l\'application en arrière-plan pendant le téléchargement.',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.redAccent),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Plus tard'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Télécharger'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _isDownloadingVosk = true);

    try {
      await _voskService.downloadModel(model);
      if (mounted) {
        setState(() {
          _isDownloadingVosk = false;
          _isVoskModelDownloaded = true;
        });
        await _initSpeechForModel(model);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saisie vocale activée pour ${model.langText}')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isDownloadingVosk = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur téléchargement voix: $e'),
            action: SnackBarAction(
              label: 'Copier',
              onPressed: () => Clipboard.setData(ClipboardData(text: e.toString())),
            ),
          ),
        );
      }
    }
  }

  Future<void> _copyOutput() async {
    if (_output.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _output));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copié')),
    );
  }

  Future<void> _shareOutput() async {
    if (_output.isEmpty) return;
    await SharePlus.instance.share(ShareParams(text: _output));
  }

  void _openDocumentTranslation() {
    final model = _selectedModel;
    if (model == null || _loadingModel) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DocumentTranslationPage(
          marian: _marian,
          model: model,
        ),
      ),
    );
  }

  Future<void> _openAudioTranscription({String? initialAudioPath}) async {
    if (_loadingModel) return;
    final srcName =
        _sourceLang.name.isEmpty ? _sourceLang.nameEn : _sourceLang.name;
    final targetName =
        _targetLang.name.isEmpty ? _targetLang.nameEn : _targetLang.name;
    final transcript = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => AudioTranscriptionPage(
          voskService: _voskService,
          speechService: _speech,
          voskModel: _matchingVoskModel ?? VoskModelService.assetFrenchModel,
          initialAudioPath: initialAudioPath,
          translationPairLabel: '$srcName → $targetName',
        ),
      ),
    );
    if (!mounted) return;
    final text = transcript?.trim();
    if (text == null || text.isEmpty) return;

    _inputController.text = text;
    _inputController.selection = TextSelection.collapsed(offset: text.length);
    setState(() {
      _output = '';
      _error = null;
    });
    await _translate();
  }

  void _showSettings() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsPage(
          modelService: _modelService,
          selectedModel: _selectedModel,
          voskService: _voskService,
          selectedVoskModel: _matchingVoskModel,
        ),
      ),
    );

    if (result is TranslationModel && result.modelId != _selectedModel?.modelId) {
      await _switchModel(result);
    } else {
      await _updateVoskModelForSource();
    }
  }

  void _openTranslationModelPicker() async {
    final result = await Navigator.push<TranslationModel>(
      context,
      MaterialPageRoute(
        builder: (context) => TranslationSettingsPage(
          modelService: _modelService,
          selectedModel: _selectedModel,
          voskService: _voskService,
        ),
      ),
    );

    if (result != null && result.modelId != _selectedModel?.modelId) {
      await _switchModel(result);
    } else {
      await _updateVoskModelForSource();
    }
  }

  Widget _buildLanguageHeader() {
    final srcName =
        _sourceLang.name.isEmpty ? _sourceLang.nameEn : _sourceLang.name;
    final targetName =
        _targetLang.name.isEmpty ? _targetLang.nameEn : _targetLang.name;
    const headerIconConstraints = BoxConstraints(minWidth: 40, minHeight: 40);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
          child: Row(
            children: [
              Flexible(
                child: InkWell(
                  onTap: _loadingModel ? null : _openTranslationModelPicker,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10.0,
                      vertical: 6.0,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: MalinaliChrome.blueChip,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text.rich(
                            TextSpan(
                              style: const TextStyle(
                                fontFamily: 'NotoSans',
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                              children: [
                                TextSpan(
                                  text: srcName,
                                  style: const TextStyle(
                                    color: MalinaliChrome.sourceText,
                                  ),
                                ),
                                const TextSpan(
                                  text: ' → ',
                                  style: TextStyle(
                                    color: MalinaliChrome.onBlue,
                                  ),
                                ),
                                TextSpan(
                                  text: targetName,
                                  style: const TextStyle(
                                    color: MalinaliChrome.targetText,
                                  ),
                                ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 20,
                          color: MalinaliChrome.onBlue,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_loadingModel) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.sizeOf(context).width * 0.48,
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border:
                              Border.all(color: MalinaliChrome.yellowBorder),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: MalinaliChrome.yellowBorder,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                _loadingModelLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: 'NotoSans',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: MalinaliChrome.onBlue,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ] else
                const Spacer(),
              // Hide unused actions while downloading so the status chip stays on-screen.
              if (!_loadingModel) ...[
                IconButton(
                  icon: const Icon(Icons.audio_file_outlined),
                  tooltip: 'Transcription audio',
                  color: MalinaliChrome.onBlue,
                  visualDensity: VisualDensity.compact,
                  constraints: headerIconConstraints,
                  onPressed: _openAudioTranscription,
                ),
                IconButton(
                  icon: const Icon(Icons.description_outlined),
                  tooltip: 'Traduire un document',
                  color: MalinaliChrome.onBlue,
                  visualDensity: VisualDensity.compact,
                  constraints: headerIconConstraints,
                  onPressed: _openDocumentTranslation,
                ),
              ],
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: 'Paramètres',
                color: MalinaliChrome.onBlue,
                visualDensity: VisualDensity.compact,
                constraints: headerIconConstraints,
                onPressed: _showSettings,
              ),
            ],
          ),
        ),
        Container(height: 3, color: MalinaliChrome.redAccent),
        if (_loadingModel)
          const LinearProgressIndicator(
            minHeight: 2,
            backgroundColor: Colors.transparent,
            color: MalinaliChrome.yellowBorder,
          ),
      ],
    );
  }

  List<Language> _uniqueLanguages(Iterable<Language> languages) {
    final seenIso = <String>{};
    final seenLabel = <String>{};
    final out = <Language>[];
    for (final language in languages) {
      final iso = languageIsoCode(language).toLowerCase();
      final label = languageDisplayName(language).trim().toLowerCase();
      // Collapse both identical ISO codes and identical display names
      // (e.g. two catalog entries both showing "English").
      if (!seenIso.add(iso)) continue;
      if (label.isNotEmpty && !seenLabel.add(label)) continue;
      out.add(language);
    }
    return out;
  }

  TranslationModel? _modelForTarget(Language target) {
    return _modelService.preferredModelForPair(
          _availableModels,
          sourceIso: languageIsoCode(_sourceLang),
          targetIso: languageIsoCode(target),
        ) ??
        () {
          final iso = languageIsoCode(target);
          for (final m in _availableModels) {
            if (languageIsoCode(m.targetLang) == iso) return m;
          }
          return null;
        }();
  }

  LanguagePickerBadges _badgesForTarget(Language language) {
    final model = _modelForTarget(language);
    if (model == null) return const LanguagePickerBadges();
    final ready = model.isAsset || (_downloadedStatus[model.modelId] ?? false);
    return LanguagePickerBadges(
      translationAvailable: true,
      translationReady: ready,
    );
  }

  Future<void> _openTargetLanguagePicker() async {
    if (_loadingModel || _availableModels.isEmpty) return;
    await _refreshDownloadedStatus();
    if (!mounted) return;
    final targets = _uniqueLanguages(_availableModels.map((m) => m.targetLang));
    final picked = await LanguagePickerSheet.show(
      context,
      languages: targets,
      selected: _targetLang,
      title: 'Langue cible',
      badgesFor: _badgesForTarget,
    );
    if (picked == null || !mounted) return;
    final iso = languageIsoCode(picked);
    if (iso == languageIsoCode(_targetLang)) return;
    final model = _modelForTarget(picked);
    if (model == null) return;

    final isDownloaded =
        model.isAsset || (_downloadedStatus[model.modelId] ?? false);
    if (!isDownloaded) {
      if (!mounted) return;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Téléchargement requis'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Le modèle de traduction pour ${model.displayName} doit être téléchargé'
                ' (${model.downloadSizeHint ?? 'environ 150 Mo'}).',
              ),
              const SizedBox(height: 12),
              const Text(
                'Ne quittez pas l\'écran et ne mettez pas l\'application en arrière-plan pendant le téléchargement.',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.redAccent),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Plus tard'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Télécharger'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    await _switchModel(model);
  }

  Future<void> _openSourceLanguagePicker() async {
    if (_loadingModel) return;

    List<Language> sources;
    List<TranslationModel> allModels = _availableModels;
    try {
      allModels = await _modelService.fetchAllAvailableModels();
      sources = _uniqueLanguages(allModels.map((m) => m.sourceLang));
      await _refreshDownloadedStatus(allModels);
    } catch (_) {
      sources = _uniqueLanguages(
        _availableModels.isEmpty
            ? [Languages.french]
            : _availableModels.map((m) => m.sourceLang),
      );
    }
    if (sources.isEmpty) sources = [Languages.french];
    if (!mounted) return;

    final statusSnapshot = Map<String, bool>.from(_downloadedStatus);
    final picked = await LanguagePickerSheet.show(
      context,
      languages: sources,
      selected: _sourceLang,
      title: 'Langue source',
      badgesFor: (language) {
        final iso = languageIsoCode(language);
        final forSource = allModels
            .where((m) => languageIsoCode(m.sourceLang) == iso)
            .toList();
        final hasTranslation = forSource.isNotEmpty;
        final ready = forSource.any(
          (m) => m.isAsset || (statusSnapshot[m.modelId] ?? false),
        );
        final vosk = _voskService.findModelForLanguage(language, _voskModels);
        final voskReady =
            vosk != null && (_voskDownloadedStatus[vosk.name] ?? false);
        return LanguagePickerBadges(
          translationAvailable: hasTranslation,
          translationReady: ready,
          voskAvailable: vosk != null,
          voskReady: voskReady,
        );
      },
    );
    if (picked == null || !mounted) return;
    final iso = languageIsoCode(picked);
    if (iso == languageIsoCode(_sourceLang)) return;

    setState(() => _sourceLang = picked);
    await _loadAvailableModels();
    await _updateVoskModelForSource();
  }

  Widget _buildTargetLanguageDropdown() {
    final currentName = languageDisplayName(_targetLang);
    return InkWell(
      onTap: _loadingModel || _availableModels.isEmpty
          ? null
          : _openTargetLanguagePicker,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              currentName,
              style: const TextStyle(
                fontFamily: 'NotoSans',
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: MalinaliChrome.targetText,
              ),
            ),
            if (_availableModels.isNotEmpty)
              const Icon(
                Icons.arrow_drop_down,
                color: MalinaliChrome.yellowBorder,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMicButton() {
    final matching = _matchingVoskModel;
    if (matching == null) return const SizedBox.shrink();

    if (_isDownloadingVosk) {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: MalinaliChrome.blueAction.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (_isVoskModelDownloaded && _speechReady) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _busy ? null : _toggleListening,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _listening
                  ? MalinaliChrome.redAccent.withValues(alpha: 0.25)
                  : MalinaliChrome.blueAction.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              _listening ? Icons.mic : Icons.mic_none,
              size: 20,
              color: _listening
                  ? MalinaliChrome.redAccent
                  : MalinaliChrome.yellowBorder,
            ),
          ),
        ),
      );
    }

    // Voice model available but not downloaded yet: Progressive Disclosure
    return Material(
      color: Colors.transparent,
      child: Tooltip(
        message: 'Activer la saisie vocale pour ${matching.langText}',
        child: InkWell(
          onTap: () => _promptDownloadVoskModel(matching),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: MalinaliChrome.bluePanel,
              border: Border.all(
                color: MalinaliChrome.whiteBorder.withValues(alpha: 0.35),
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(
                  Icons.mic_none,
                  size: 20,
                  color: MalinaliChrome.mutedOnBlue,
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    padding: const EdgeInsets.all(1),
                    decoration: const BoxDecoration(
                      color: MalinaliChrome.blueAction,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.arrow_downward,
                      size: 9,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasInput = _inputController.text.trim().isNotEmpty;
    final srcName =
        _sourceLang.name.isEmpty ? _sourceLang.nameEn : _sourceLang.name;

    return Scaffold(
      backgroundColor: MalinaliChrome.blueBg,
      body: SafeArea(
        child: Column(
          children: [
            _buildLanguageHeader(),
            Expanded(
              flex: 5,
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: MalinaliChrome.bluePanel,
                  border: Border.all(
                    color: MalinaliChrome.whiteBorder,
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          InkWell(
                            onTap: _loadingModel ? null : _openSourceLanguagePicker,
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    srcName,
                                    style: const TextStyle(
                                      fontFamily: 'NotoSans',
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                      color: MalinaliChrome.sourceText,
                                    ),
                                  ),
                                  const Icon(
                                    Icons.arrow_drop_down,
                                    color: MalinaliChrome.sourceText,
                                    size: 22,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const Spacer(),
                          if (_matchingVoskModel != null) _buildMicButton(),
                          if (hasInput) ...[
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: () {
                                _inputController.clear();
                                _inputFocusNode.requestFocus();
                                setState(() {
                                  _output = '';
                                  _error = null;
                                });
                              },
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Icon(
                                  Icons.close,
                                  size: 16,
                                  color: MalinaliChrome.sourceText,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: Colors.white.withValues(alpha: 0.15),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        child: ScrollbarTheme(
                          data: ScrollbarThemeData(
                            thumbColor: WidgetStateProperty.all(
                              MalinaliChrome.sourceText.withValues(alpha: 0.5),
                            ),
                            trackColor: WidgetStateProperty.all(
                              Colors.white.withValues(alpha: 0.08),
                            ),
                            thickness: WidgetStateProperty.all(4),
                            radius: const Radius.circular(4),
                          ),
                          child: Scrollbar(
                            controller: _inputScrollController,
                            thumbVisibility: true,
                            trackVisibility: true,
                            child: Theme(
                              data: Theme.of(context).copyWith(
                                textSelectionTheme: TextSelectionThemeData(
                                  cursorColor: MalinaliChrome.sourceText,
                                  selectionColor:
                                      MalinaliChrome.sourceText.withValues(alpha: 0.28),
                                  selectionHandleColor: MalinaliChrome.sourceText,
                                ),
                              ),
                              child: TextField(
                              controller: _inputController,
                              focusNode: _inputFocusNode,
                              scrollController: _inputScrollController,
                              autofocus: true,
                              cursorColor: MalinaliChrome.sourceText,
                              maxLines: null,
                              expands: true,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _translate(),
                              style: const TextStyle(
                                fontSize: 16,
                                height: 1.4,
                                fontFamily: 'NotoSans',
                                color: MalinaliChrome.sourceText,
                              ),
                              decoration: InputDecoration(
                                filled: false,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                disabledBorder: InputBorder.none,
                                errorBorder: InputBorder.none,
                                focusedErrorBorder: InputBorder.none,
                                hintText: 'Tapez votre texte ici...',
                                hintStyle: TextStyle(
                                  fontFamily: 'NotoSans',
                                  color: MalinaliChrome.sourceText.withValues(alpha: 0.45),
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (hasInput)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: MalinaliChrome.blueAction,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    onPressed: _busy ? null : _translate,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.arrow_forward_rounded,
                            size: 18,
                          ),
                    label: const Text(
                      'Traduire',
                      style: TextStyle(
                        fontFamily: 'NotoSans',
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
            Expanded(
              flex: 5,
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: MalinaliChrome.bluePanel,
                  border: Border.all(
                    color: MalinaliChrome.yellowBorder,
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildTargetLanguageDropdown(),
                          if (_output.isNotEmpty)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.copy_rounded, size: 18),
                                  onPressed: _copyOutput,
                                  tooltip: 'Copier',
                                  color: MalinaliChrome.targetText,
                                ),
                                IconButton(
                                  icon: const Icon(Icons.share_rounded, size: 18),
                                  onPressed: _shareOutput,
                                  tooltip: 'Partager',
                                  color: MalinaliChrome.targetText,
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: Colors.white.withValues(alpha: 0.15),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(14),
                        child: _error != null
                            ? Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade900.withValues(alpha: 0.35),
                                  border: Border.all(color: MalinaliChrome.redAccent),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(
                                      Icons.error_outline,
                                      color: MalinaliChrome.targetText,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: SelectableText(
                                        _error!,
                                        style: const TextStyle(
                                          fontFamily: 'NotoSans',
                                          fontSize: 14,
                                          color: MalinaliChrome.sourceText,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : Text(
                                _output.isEmpty
                                    ? 'La traduction apparaîtra ici...'
                                    : _output,
                                style: TextStyle(
                                  fontSize: 16,
                                  height: 1.4,
                                  fontFamily: 'NotoSans',
                                  color: _output.isEmpty
                                      ? MalinaliChrome.targetText
                                          .withValues(alpha: 0.45)
                                      : MalinaliChrome.targetText,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
