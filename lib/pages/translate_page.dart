import 'package:aptabase_flutter/aptabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:languages_dart/languages_dart.dart';
import 'package:malinali/pages/document_translation_page.dart';
import 'package:malinali/pages/translation_settings_page.dart';
import 'package:malinali/services/marian_runtime.dart';
import 'package:malinali/services/translation_model_service.dart';
import 'package:malinali/services/tts_service.dart';
import 'package:malinali/services/voice_preferences.dart';
import 'package:malinali/theme/malinali_chrome.dart';
import 'package:malinali/widgets/language_picker_sheet.dart';
import 'package:malinali/widgets/language_pill.dart';
import 'package:malinali/widgets/malinali_drawer.dart';
import 'package:marian_flutter/marian_flutter.dart';
import 'package:share_plus/share_plus.dart';

/// Text-only MarianMT translation screen.
class TranslatePage extends StatefulWidget {
  const TranslatePage({
    super.key,
    required this.initialMarian,
    this.initialModel,
    this.modelService,
  });

  final MarianService initialMarian;
  final TranslationModel? initialModel;
  final TranslationModelService? modelService;

  @override
  State<TranslatePage> createState() => _TranslatePageState();
}

class _TranslatePageState extends State<TranslatePage> {
  final _inputController = TextEditingController();
  final _inputFocusNode = FocusNode();
  final _inputScrollController = ScrollController();
  late final TranslationModelService _modelService;
  late final TtsService _ttsService;

  late MarianService _marian;

  Language _sourceLang = Languages.french;
  Language _targetLang = Languages.english;
  List<TranslationModel> _availableModels = [];
  TranslationModel? _selectedModel;
  Map<String, bool> _downloadedStatus = {};

  String _output = '';
  String? _error;
  bool _busy = false;
  bool _loadingModel = false;
  String _loadingModelLabel = 'Chargement...';
  bool _ttsAvailable = false;

  @override
  void initState() {
    super.initState();
    _modelService = widget.modelService ?? TranslationModelService();
    _ttsService = TtsService();
    _marian = widget.initialMarian;
    final boot =
        widget.initialModel ?? TranslationModelService.defaultBootModel;
    _selectedModel = boot;
    _sourceLang = boot.sourceLang;
    _targetLang = boot.targetLang;
    MarianRuntime.instance.attach(_marian, boot);

    _inputController.addListener(() => setState(() {}));
    _ttsService.init();
    _checkTtsAvailability();
    _loadAvailableModels();
  }

  Future<void> _checkTtsAvailability() async {
    final available = await _ttsService.isAvailable();
    if (!mounted) return;
    setState(() => _ttsAvailable = available);
  }

  Future<void> _refreshDownloadedStatus([
    List<TranslationModel>? models,
  ]) async {
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
    final prefs = await VoicePreferencesStore().load();
    final List<TranslationModel> models = await _modelService
        .fetchAvailableModels(_sourceLang);

    // Filter by target languages from setup if present
    List<TranslationModel> filtered = models;
    if (prefs != null && prefs.targetLanguages.isNotEmpty) {
      final allowedIsos =
          prefs.targetLanguages.map((e) => e.toLowerCase()).toSet();
      filtered =
          models.where((m) {
            final iso =
                m.targetLang.localeIntl.locale.languageCode.toLowerCase();
            return allowedIsos.contains(iso);
          }).toList();
    }

    if (!mounted) return;

    setState(() {
      _availableModels = filtered;
    });
    await _refreshDownloadedStatus(filtered);

    if (filtered.isEmpty) return;

    // Keep the boot / last-selected model; do not auto-switch on startup
    // (that caused a second 5–10s load after MarianBootScreen).
    final selectedId = _selectedModel?.modelId;
    if (selectedId != null && filtered.any((m) => m.modelId == selectedId)) {
      return;
    }

    final currentTargetIso = _targetLang.localeIntl.locale.languageCode;
    TranslationModel? nextModel;

    for (final m in filtered) {
      if (m.targetLang.localeIntl.locale.languageCode == currentTargetIso) {
        nextModel = m;
        break;
      }
    }

    nextModel ??= filtered.first;
    if (nextModel.modelId == _selectedModel?.modelId) return;

    final isDownloaded =
        nextModel.isAsset || (_downloadedStatus[nextModel.modelId] ?? false);
    if (!isDownloaded) {
      if (!mounted) return;
      final confirm = await _confirmModelDownload(nextModel);
      if (confirm != true) return;
    }
    await _switchModel(nextModel);
  }

  Future<bool?> _confirmModelDownload(TranslationModel model) {
    return showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
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
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.redAccent,
                  ),
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
  }

  Future<void> _switchModel(TranslationModel model) async {
    if (!mounted) return;

    setState(() {
      _loadingModel = true;
      _loadingModelLabel =
          model.downloadSizeHint != null
              ? 'Téléchargement ${model.downloadSizeHint}…'
              : 'Chargement...';
      _error = null;
    });

    try {
      MarianService marian;
      if (model.isAsset) {
        marian = await MarianService.loadFromAssets(assetFolder: model.modelId);
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
        _downloadedStatus = {..._downloadedStatus, model.modelId: true};
      });
      Aptabase.instance.trackEvent('model_switched', {
        'model_id': model.modelId,
        'source_lang': model.sourceLang.nameEn,
        'target_lang': model.targetLang.nameEn,
      });
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
    _ttsService.stop();
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
        _selectedModel?.prepareSourceText(text) ?? text,
        config: kStreetTranslationConfig,
      );
      if (!mounted) return;
      setState(() => _output = translated.trim());
      Aptabase.instance.trackEvent('text_translation_performed', {
        'source_lang': _sourceLang.nameEn,
        'target_lang': _targetLang.nameEn,
        'model_id': _selectedModel?.modelId ?? 'unknown',
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyOutput() async {
    if (_output.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _output));
    Aptabase.instance.trackEvent('output_copied');
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Copié')));
  }

  Future<void> _shareOutput() async {
    if (_output.isEmpty) return;
    Aptabase.instance.trackEvent('output_shared');
    await SharePlus.instance.share(ShareParams(text: _output));
  }

  Future<void> _speakOutput() async {
    if (_output.isEmpty) return;
    final success = await _ttsService.speak(_output, _targetLang);
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Synthèse vocale non disponible pour cette langue'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _openDocumentTranslation() {
    final model = _selectedModel;
    if (model == null || _loadingModel) return;
    Aptabase.instance.trackEvent('document_translation_page_opened');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => DocumentTranslationPage(marian: _marian, model: model),
      ),
    );
  }

  Future<void> _openTranslationSettings() async {
    Aptabase.instance.trackEvent('settings_opened');
    final result = await Navigator.push<TranslationModel>(
      context,
      MaterialPageRoute(
        builder:
            (context) => TranslationSettingsPage(
              modelService: _modelService,
              selectedModel: _selectedModel,
            ),
      ),
    );

    if (result != null && result.modelId != _selectedModel?.modelId) {
      await _switchModel(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasInput = _inputController.text.trim().isNotEmpty;
    final srcName =
        _sourceLang.name.isEmpty ? _sourceLang.nameEn : _sourceLang.name;
    final targetName =
        _targetLang.name.isEmpty ? _targetLang.nameEn : _targetLang.name;

    return Scaffold(
      backgroundColor: MalinaliChrome.blueBg,
      drawer: const MalinaliDrawer(),
      appBar: AppBar(
        centerTitle: true,
        title: LanguagePill(
          label: '$srcName → $targetName',
          onTap: _openTranslationSettings,
          loading: _loadingModel,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.description_outlined),
            tooltip: 'Traduire un document',
            onPressed: _openDocumentTranslation,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_loadingModel)
              const LinearProgressIndicator(
                minHeight: 2,
                backgroundColor: Colors.transparent,
                color: MalinaliChrome.yellowBorder,
              ),
            Expanded(
              flex: 5,
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: MalinaliChrome.bluePanel,
                  border: Border.all(
                    color: MalinaliChrome.whiteBorder.withValues(alpha: 0.15),
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
                    if (hasInput || _loadingModel)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            if (_loadingModel)
                              Expanded(
                                child: Row(
                                  children: [
                                    const SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: MalinaliChrome.yellowBorder,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        _loadingModelLabel,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: MalinaliChrome.onBlue,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              const Spacer(),
                            if (hasInput)
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
                        ),
                      ),
                    if (hasInput || _loadingModel)
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: Colors.white.withValues(alpha: 0.15),
                      ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
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
                                  selectionColor: MalinaliChrome.sourceText
                                      .withValues(alpha: 0.28),
                                  selectionHandleColor:
                                      MalinaliChrome.sourceText,
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
                                  fontSize: 18,
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
                                    color: MalinaliChrome.sourceText.withValues(
                                      alpha: 0.45,
                                    ),
                                    fontSize: 18,
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
                    icon:
                        _busy
                            ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                            : const Icon(Icons.arrow_forward_rounded, size: 18),
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
                    color: MalinaliChrome.yellowBorder.withValues(alpha: 0.6),
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
                    if (_output.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (_ttsAvailable)
                              IconButton(
                                icon: const Icon(
                                  Icons.volume_up_rounded,
                                  size: 18,
                                ),
                                onPressed: _speakOutput,
                                tooltip: 'Écouter',
                                color: MalinaliChrome.targetText,
                              ),
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
                      ),
                    if (_output.isNotEmpty)
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: Colors.white.withValues(alpha: 0.15),
                      ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(14),
                        child:
                            _error != null
                                ? Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade900.withValues(
                                      alpha: 0.35,
                                    ),
                                    border: Border.all(
                                      color: MalinaliChrome.redAccent,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                    fontSize: 18,
                                    height: 1.4,
                                    fontFamily: 'NotoSans',
                                    color:
                                        _output.isEmpty
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
