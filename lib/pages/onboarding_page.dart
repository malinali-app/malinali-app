import 'package:flutter/material.dart';
import 'package:malinali/services/supported_languages.dart';
import 'package:malinali/services/translation_model_service.dart';
import 'package:malinali/services/voice_preferences.dart';
import 'package:malinali/services/voice_speech_resolver.dart';
import 'package:malinali/services/voice_turn_pipeline.dart';
import 'package:malinali/services/whisper_speech_service.dart';
import 'package:malinali/theme/malinali_chrome.dart';
import 'package:malinali/utils/wakelock_helper.dart';
import 'package:malinali/widgets/connectivity_builder.dart';

class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({
    super.key,
    required this.store,
    this.pipeline,
    this.modelService,
    this.whisperService,
    this.resolver = const VoiceSpeechResolver(),
  });

  final VoicePreferencesStore store;
  final VoiceTurnPipeline? pipeline;
  final TranslationModelService? modelService;
  final WhisperSpeechService? whisperService;
  final VoiceSpeechResolver resolver;

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  String? _sourceIso;
  String? _targetIso;

  late final VoiceTurnPipeline _pipeline;
  late final TranslationModelService _modelService;

  @override
  void initState() {
    super.initState();
    _modelService = widget.modelService ?? TranslationModelService();
    final whisper = widget.whisperService ?? WhisperSpeechService();
    _pipeline = widget.pipeline ??
        VoiceTurnPipeline(
          whisper: whisper,
          modelService: _modelService,
          resolver: widget.resolver,
        );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onSourceSelected(String iso) {
    setState(() {
      _sourceIso = iso;
      // Auto-select the first available target for this source
      final targets = getAvailableTargetLanguages(sourceIso: iso);
      _targetIso = targets.isNotEmpty ? targets.first.iso : null;
      _currentPage = 1;
    });
    _pageController.animateToPage(
      1,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _onTargetSelected(String iso) {
    setState(() {
      _targetIso = iso;
    });
  }

  void _goToDownloadStep() {
    if (_targetIso == null) return;
    setState(() {
      _currentPage = 2;
    });
    _pageController.animateToPage(
      2,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _goBack() {
    if (_currentPage > 0) {
      final prev = _currentPage - 1;
      setState(() => _currentPage = prev);
      _pageController.animateToPage(
        prev,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  VoicePreferences _buildPreferences() {
    final src = _sourceIso ?? 'fr';
    final tgt = _targetIso ?? (src == 'wo' ? 'fr' : 'wo');
    return VoicePreferences(
      sourceIso: src,
      targetIso: tgt,
      whisperSize: VoiceWhisperSize.quality,
      appLanguageIso: 'fr',
      targetLanguages: [tgt],
    );
  }

  @override
  Widget build(BuildContext context) {
    final prefs = _buildPreferences();

    return Scaffold(
      backgroundColor: MalinaliChrome.blueBg,
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _SourceLanguageStep(
            selectedIso: _sourceIso,
            onSelected: _onSourceSelected,
          ),
          if (_sourceIso != null)
            _TargetLanguageStep(
              sourceIso: _sourceIso!,
              selectedTargetIso: _targetIso,
              onTargetSelected: _onTargetSelected,
              onBack: _goBack,
              onContinue: _goToDownloadStep,
            )
          else
            const SizedBox.shrink(),
          if (_sourceIso != null && _targetIso != null)
            _ModelDownloadStep(
              prefs: prefs,
              store: widget.store,
              pipeline: _pipeline,
              resolver: widget.resolver,
              onBack: _goBack,
            )
          else
            const SizedBox.shrink(),
        ],
      ),
    );
  }
}

class _SourceLanguageStep extends StatelessWidget {
  const _SourceLanguageStep({
    required this.selectedIso,
    required this.onSelected,
  });

  final String? selectedIso;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 48),
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.asset(
                  'assets/malinali_logo.jpg',
                  width: 72,
                  height: 72,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.translate,
                    size: 64,
                    color: MalinaliChrome.yellowBorder,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Malinali',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'NotoSans',
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Choisissez votre langue',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'NotoSans',
                fontSize: 16,
                color: MalinaliChrome.mutedOnBlue,
              ),
            ),
            const SizedBox(height: 36),
            ...kSupportedSourceLanguages.map((lang) {
              final isSelected = selectedIso == lang.iso;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Material(
                  color: isSelected
                      ? MalinaliChrome.blueAction.withValues(alpha: 0.3)
                      : MalinaliChrome.bluePanel,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: isSelected
                          ? MalinaliChrome.yellowBorder
                          : MalinaliChrome.whiteBorder.withValues(alpha: 0.15),
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => onSelected(lang.iso),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 18,
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: isSelected
                                ? MalinaliChrome.yellowBorder
                                : MalinaliChrome.blueBg,
                            foregroundColor: isSelected
                                ? Colors.black
                                : MalinaliChrome.onBlue,
                            child: Text(
                              lang.name.substring(0, 1).toUpperCase(),
                              style: const TextStyle(
                                fontFamily: 'NotoSans',
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  lang.name,
                                  style: const TextStyle(
                                    fontFamily: 'NotoSans',
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: MalinaliChrome.onBlue,
                                  ),
                                ),
                                if (lang.name != lang.nameEn)
                                  Text(
                                    lang.nameEn,
                                    style: const TextStyle(
                                      fontFamily: 'NotoSans',
                                      fontSize: 13,
                                      color: MalinaliChrome.mutedOnBlue,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.arrow_forward_ios,
                            size: 16,
                            color: MalinaliChrome.mutedOnBlue,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _TargetLanguageStep extends StatelessWidget {
  const _TargetLanguageStep({
    required this.sourceIso,
    required this.selectedTargetIso,
    required this.onTargetSelected,
    required this.onBack,
    required this.onContinue,
  });

  final String sourceIso;
  final String? selectedTargetIso;
  final ValueChanged<String> onTargetSelected;
  final VoidCallback onBack;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final targets = getAvailableTargetLanguages(sourceIso: sourceIso);

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: MalinaliChrome.onBlue),
                  onPressed: onBack,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Langue de traduction',
                    style: TextStyle(
                      fontFamily: 'NotoSans',
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: MalinaliChrome.onBlue,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Text(
              'Choisissez la langue vers laquelle traduire.',
              style: TextStyle(
                fontFamily: 'NotoSans',
                color: MalinaliChrome.mutedOnBlue,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  for (int i = 0; i < targets.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    Builder(
                      builder: (context) {
                        final option = targets[i];
                        final isSelected = option.iso == selectedTargetIso;

                        return Material(
                          color: isSelected
                              ? MalinaliChrome.blueAction.withValues(alpha: 0.3)
                              : MalinaliChrome.bluePanel,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: isSelected
                                  ? MalinaliChrome.yellowBorder
                                  : MalinaliChrome.whiteBorder.withValues(alpha: 0.12),
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            leading: CircleAvatar(
                              backgroundColor: isSelected
                                  ? MalinaliChrome.yellowBorder
                                  : MalinaliChrome.blueBg,
                              foregroundColor:
                                  isSelected ? Colors.black : MalinaliChrome.onBlue,
                              child: Text(
                                option.name.isNotEmpty
                                    ? option.name.substring(0, 1).toUpperCase()
                                    : option.iso.toUpperCase(),
                                style: const TextStyle(
                                  fontFamily: 'NotoSans',
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(
                              option.name,
                              style: const TextStyle(
                                fontFamily: 'NotoSans',
                                fontWeight: FontWeight.w600,
                                color: MalinaliChrome.onBlue,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  [
                                    if (option.nameEn.isNotEmpty &&
                                        option.nameEn != option.name)
                                      option.nameEn,
                                    option.iso.toUpperCase(),
                                  ].join(' · '),
                                  style: const TextStyle(
                                    fontFamily: 'NotoSans',
                                    color: MalinaliChrome.mutedOnBlue,
                                    fontSize: 13,
                                  ),
                                ),
                                if (option.qualityHint != null &&
                                    option.qualityHint!.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    option.qualityHint!,
                                    style: const TextStyle(
                                      fontFamily: 'NotoSans',
                                      color: MalinaliChrome.yellowBorder,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            trailing: isSelected
                                ? const Icon(
                                    Icons.check_circle,
                                    color: MalinaliChrome.yellowBorder,
                                  )
                                : const Icon(
                                    Icons.circle_outlined,
                                    color: MalinaliChrome.mutedOnBlue,
                                  ),
                            onTap: () => onTargetSelected(option.iso),
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: selectedTargetIso != null ? onContinue : null,
                style: FilledButton.styleFrom(
                  backgroundColor: MalinaliChrome.yellowBorder,
                  foregroundColor: Colors.black,
                  disabledBackgroundColor:
                      MalinaliChrome.yellowBorder.withValues(alpha: 0.3),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Continuer',
                  style: TextStyle(
                    fontFamily: 'NotoSans',
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelDownloadStep extends StatefulWidget {
  const _ModelDownloadStep({
    required this.prefs,
    required this.store,
    required this.pipeline,
    required this.resolver,
    required this.onBack,
  });

  final VoicePreferences prefs;
  final VoicePreferencesStore store;
  final VoiceTurnPipeline pipeline;
  final VoiceSpeechResolver resolver;
  final VoidCallback onBack;

  @override
  State<_ModelDownloadStep> createState() => _ModelDownloadStepState();
}

class _ModelDownloadStepState extends State<_ModelDownloadStep> {
  bool _downloading = false;
  double? _progress;
  String? _status;
  String? _error;
  late final VoiceSpeechPlan _plan;

  @override
  void initState() {
    super.initState();
    _plan = widget.resolver.resolve(widget.prefs);
    _checkAndStart();
  }

  @override
  void dispose() {
    WakelockHelper.disable();
    super.dispose();
  }

  Future<void> _checkAndStart() async {
    setState(() {
      _error = null;
      _progress = null;
      _status = 'Vérification des modèles…';
    });

    final already = await widget.pipeline.modelsReady(_plan);
    if (already) {
      await _finish();
      return;
    }

    // Model is not available locally. Check connectivity before attempting fetch.
    final online = await isConnected;
    if (!online) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _status = null;
      });
      return;
    }

    await _startDownload();
  }

  Future<void> _startDownload() async {
    // Check connectivity again immediately before fetching
    final online = await isConnected;
    if (!online) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _error = 'Pas de connexion Internet.';
      });
      return;
    }

    await WakelockHelper.enable();
    setState(() {
      _downloading = true;
      _error = null;
      _progress = null;
      _status = 'Téléchargement du modèle…';
    });

    try {
      await widget.pipeline.ensureModels(
        _plan,
        onStatus: (s) {
          if (mounted) setState(() => _status = s);
        },
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );

      if (!mounted) return;
      await _finish();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _error = 'Échec du téléchargement : $e';
        _status = null;
        _progress = null;
      });
    } finally {
      await WakelockHelper.disable();
    }
  }

  Future<void> _finish() async {
    await widget.store.save(widget.prefs);
    if (!mounted) return;
    Navigator.of(context).pop(widget.prefs);
  }

  String get _pairLabel {
    final src = voiceLanguageByIso(widget.prefs.sourceIso);
    final tgt = voiceLanguageByIso(widget.prefs.targetIso);
    final s = src?.name.isNotEmpty == true ? src!.name : widget.prefs.sourceIso.toUpperCase();
    final t = tgt?.name.isNotEmpty == true ? tgt!.name : widget.prefs.targetIso.toUpperCase();
    return '$s → $t';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConnectivityFutureBuilder(
        _buildOnlineContent(),
        _buildOfflineWidget(),
      ),
    );
  }

  Widget _buildOfflineWidget() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: MalinaliChrome.onBlue),
                onPressed: widget.onBack,
              ),
              const Spacer(),
            ],
          ),
          const Spacer(),
          const Icon(
            Icons.wifi_off_rounded,
            size: 64,
            color: MalinaliChrome.yellowBorder,
          ),
          const SizedBox(height: 24),
          const Text(
            'Pas de connexion Internet',
            style: TextStyle(
              fontFamily: 'NotoSans',
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Le modèle nécessaire pour la traduction ($_pairLabel) '
            'doit être téléchargé, mais aucun accès Internet n\'est disponible.\n\n'
            'Veuillez vous connecter à Internet pour continuer.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'NotoSans',
              fontSize: 14,
              color: MalinaliChrome.mutedOnBlue,
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: _checkAndStart,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
              style: FilledButton.styleFrom(
                backgroundColor: MalinaliChrome.yellowBorder,
                foregroundColor: Colors.black,
              ),
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildOnlineContent() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              if (!_downloading)
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: MalinaliChrome.onBlue),
                  onPressed: widget.onBack,
                ),
              const Spacer(),
            ],
          ),
          const Spacer(),
          if (_error != null) ...[
            const Icon(
              Icons.error_outline_rounded,
              size: 56,
              color: Colors.redAccent,
            ),
            const SizedBox(height: 16),
            const Text(
              'Erreur de téléchargement',
              style: TextStyle(
                fontFamily: 'NotoSans',
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'NotoSans',
                color: MalinaliChrome.mutedOnBlue,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _checkAndStart,
                style: FilledButton.styleFrom(
                  backgroundColor: MalinaliChrome.yellowBorder,
                  foregroundColor: Colors.black,
                ),
                child: const Text('Réessayer'),
              ),
            ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: _progress,
                      minHeight: 10,
                      backgroundColor:
                          MalinaliChrome.blueAction.withValues(alpha: 0.3),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        MalinaliChrome.yellowBorder,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _downloading
                            ? 'Téléchargement en cours…'
                            : 'Préparation…',
                        style: const TextStyle(
                          fontFamily: 'NotoSans',
                          fontSize: 13,
                          color: MalinaliChrome.mutedOnBlue,
                        ),
                      ),
                      if (_progress != null)
                        Text(
                          '${(_progress! * 100).toStringAsFixed(0)} %',
                          style: const TextStyle(
                            fontFamily: 'NotoSans',
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: MalinaliChrome.yellowBorder,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _status ?? 'Préparation des modèles…',
              style: const TextStyle(
                fontFamily: 'NotoSans',
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Configuration pour $_pairLabel',
              style: const TextStyle(
                fontFamily: 'NotoSans',
                fontSize: 14,
                color: MalinaliChrome.mutedOnBlue,
              ),
            ),
          ],
          const Spacer(),
        ],
      ),
    );
  }
}
