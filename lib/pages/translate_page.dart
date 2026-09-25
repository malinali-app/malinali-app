import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:languages_dart/languages_dart.dart';
import 'package:malinali/pages/settings_page.dart';
import 'package:malinali/pages/translation_settings_page.dart';
import 'package:malinali/services/speech_recognition_service.dart';
import 'package:malinali/services/translation_model_service.dart';
import 'package:malinali/services/vosk_model_service.dart';
import 'package:marian_flutter/marian_flutter.dart';
import 'package:share_plus/share_plus.dart';

/// Language-agnostic translate screen (MarianMT + dynamic Vosk mic).
class TranslatePage extends StatefulWidget {
  const TranslatePage({
    super.key,
    required this.initialMarian,
    this.modelService,
    this.voskService,
    this.speechService,
  });

  final MarianService initialMarian;
  final TranslationModelService? modelService;
  final VoskModelService? voskService;
  final SpeechRecognitionService? speechService;

  @override
  State<TranslatePage> createState() => _TranslatePageState();
}

class _TranslatePageState extends State<TranslatePage> {
  final _inputController = TextEditingController();
  final _inputFocusNode = FocusNode();
  late final TranslationModelService _modelService;
  late final VoskModelService _voskService;

  late MarianService _marian;
  SpeechRecognitionService? _speech;

  Language _sourceLang = Languages.french;
  Language _targetLang = TranslationModelService.privateModels.first.targetLang;
  List<TranslationModel> _availableModels = [];
  TranslationModel? _selectedModel = TranslationModelService.privateModels.first;

  List<VoskModel> _voskModels = [];
  VoskModel? _matchingVoskModel;
  bool _isVoskModelDownloaded = false;
  bool _isDownloadingVosk = false;

  String _output = '';
  String? _error;
  bool _busy = false;
  bool _loadingModel = false;
  bool _listening = false;
  bool _speechReady = false;

  @override
  void initState() {
    super.initState();
    _modelService = widget.modelService ?? TranslationModelService();
    _voskService = widget.voskService ?? VoskModelService();
    _marian = widget.initialMarian;
    _speech = widget.speechService ?? SpeechRecognitionService(modelService: _voskService);

    _inputController.addListener(() => setState(() {}));
    _initVoskAndSpeech();
    _loadAvailableModels();
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

  Future<void> _loadAvailableModels() async {
    final models = await _modelService.fetchAvailableModels(_sourceLang);
    if (!mounted) return;

    setState(() {
      _availableModels = models;
    });

    if (models.isNotEmpty) {
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
      if (nextModel.modelId != _selectedModel?.modelId) {
        await _switchModel(nextModel);
      }
    }
  }

  Future<void> _switchModel(TranslationModel model) async {
    if (!mounted) return;

    setState(() {
      _loadingModel = true;
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

      if (mounted) {
        setState(() {
          _marian = marian;
          _selectedModel = model;
          _targetLang = model.targetLang;
          _sourceLang = model.sourceLang;
          _loadingModel = false;
          _output = '';
        });
        await _updateVoskModelForSource();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingModel = false;
          _error = 'Failed to load model: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _speech?.dispose();
    _inputController.dispose();
    _inputFocusNode.dispose();
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
        content: Text(
          'Pour dicter votre texte en ${model.langText}, le modèle vocal (${model.sizeText}) doit être téléchargé.',
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
          SnackBar(content: Text('Erreur téléchargement voix: $e')),
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
    await Share.share(_output);
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
    final hasVosk = _matchingVoskModel != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
          child: Row(
            children: [
              InkWell(
                onTap: _loadingModel ? null : _openTranslationModelPicker,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$srcName → $targetName',
                        style: const TextStyle(
                          fontFamily: 'NotoSans',
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E3A8A),
                        ),
                      ),
                      if (hasVosk) ...[
                        const SizedBox(width: 6),
                        Tooltip(
                          message: _isVoskModelDownloaded
                              ? 'Saisie vocale prête (${_matchingVoskModel!.langText})'
                              : 'Saisie vocale disponible (${_matchingVoskModel!.langText})',
                          child: Icon(
                            Icons.mic,
                            size: 18,
                            color: _isVoskModelDownloaded
                                ? Colors.green
                                : const Color(0xFF2563EB),
                          ),
                        ),
                      ],
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 20,
                        color: Color(0xFF64748B),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              if (_loadingModel)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Chargement...',
                        style: TextStyle(
                          fontFamily: 'NotoSans',
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: 'Paramètres',
                color: const Color(0xFF64748B),
                onPressed: _showSettings,
              ),
            ],
          ),
        ),
        if (_loadingModel)
          const LinearProgressIndicator(
            minHeight: 2,
            backgroundColor: Colors.transparent,
          ),
      ],
    );
  }

  Widget _buildTargetLanguageDropdown() {
    final currentTargetIso = _targetLang.localeIntl.locale.languageCode;
    final availableTargets = _availableModels.map((m) => m.targetLang).toList();

    // Check if current target is in available targets
    final hasCurrent = availableTargets.any(
      (l) => l.localeIntl.locale.languageCode == currentTargetIso,
    );

    final currentName =
        _targetLang.name.isEmpty ? _targetLang.nameEn : _targetLang.name;

    if (!hasCurrent && availableTargets.isNotEmpty) {
      return Text(
        currentName,
        style: const TextStyle(
          fontFamily: 'NotoSans',
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1E3A8A),
        ),
      );
    }

    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: hasCurrent ? currentTargetIso : null,
        icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF2563EB)),
        style: const TextStyle(
          fontFamily: 'NotoSans',
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1E3A8A),
        ),
        onChanged: (iso) {
          if (iso == null) return;
          final model = _availableModels.firstWhere(
            (m) => m.targetLang.localeIntl.locale.languageCode == iso,
          );
          _switchModel(model);
        },
        items: _availableModels.map((m) {
          final name =
              m.targetLang.name.isEmpty ? m.targetLang.nameEn : m.targetLang.name;
          return DropdownMenuItem<String>(
            value: m.targetLang.localeIntl.locale.languageCode,
            child: Text(
              name,
              style: const TextStyle(
                fontFamily: 'NotoSans',
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E3A8A),
              ),
            ),
          );
        }).toList(),
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
          color: Colors.blue.shade50,
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
                  ? Colors.red.shade100.withValues(alpha: 0.9)
                  : Colors.blue.shade50,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              _listening ? Icons.mic : Icons.mic_none,
              size: 20,
              color: _listening ? Colors.red.shade700 : const Color(0xFF2563EB),
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
              color: Colors.grey.shade100,
              border: Border.all(color: Colors.blue.shade200),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  Icons.mic_none,
                  size: 20,
                  color: Colors.grey.shade700,
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    padding: const EdgeInsets.all(1),
                    decoration: const BoxDecoration(
                      color: Color(0xFF2563EB),
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
      backgroundColor: const Color(0xFFF1F5F9), // slate 100
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
                  color: Colors.white,
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 4,
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
                          Text(
                            srcName,
                            style: const TextStyle(
                              fontFamily: 'NotoSans',
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: Color(0xFF1E3A8A),
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
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Icon(
                                  Icons.close,
                                  size: 16,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Divider(height: 1, thickness: 1, color: Colors.grey.shade200),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        child: TextField(
                          controller: _inputController,
                          focusNode: _inputFocusNode,
                          autofocus: true,
                          maxLines: null,
                          expands: true,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _translate(),
                          style: const TextStyle(
                            fontSize: 16,
                            height: 1.4,
                            fontFamily: 'NotoSans',
                            color: Color(0xFF0F172A),
                          ),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: 'Tapez votre texte ici...',
                            hintStyle: TextStyle(
                              fontFamily: 'NotoSans',
                              color: Colors.grey.shade400,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (hasInput)
                      Align(
                        alignment: Alignment.bottomRight,
                        child: Padding(
                          padding: const EdgeInsets.all(10.0),
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2563EB),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
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
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 5,
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC), // slate 50
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 4,
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
                                  color: const Color(0xFF475569),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.share_rounded, size: 18),
                                  onPressed: _shareOutput,
                                  tooltip: 'Partager',
                                  color: const Color(0xFF475569),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                    Divider(height: 1, thickness: 1, color: Colors.grey.shade200),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(14),
                        child: _error != null
                            ? Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  border: Border.all(color: Colors.red.shade200),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.error_outline,
                                      color: Colors.red.shade700,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _error!,
                                        style: TextStyle(
                                          fontFamily: 'NotoSans',
                                          fontSize: 14,
                                          color: Colors.red.shade900,
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
                                      ? Colors.grey.shade400
                                      : const Color(0xFF0F172A),
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
