import 'package:flutter/material.dart';
import 'package:languages_dart/languages_dart.dart';
import 'package:malinali/services/translation_model_service.dart';
import 'package:malinali/services/voice_preferences.dart';
import 'package:malinali/theme/malinali_chrome.dart';

class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key, required this.store});

  final VoicePreferencesStore store;

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  final PageController _pageController = PageController();
  String? _appLanguageIso;
  final List<String> _selectedTargetIsos = ['en', 'fr'];

  void _onAppLanguageSelected(String iso) {
    setState(() {
      _appLanguageIso = iso;
    });
    _pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _complete() async {
    final prefs = VoicePreferences(
      sourceIso: _appLanguageIso ?? 'fr',
      targetIso: _selectedTargetIsos.firstWhere((iso) => iso != _appLanguageIso,
          orElse: () => _selectedTargetIsos.first),
      whisperSize: VoiceWhisperSize.quality,
      appLanguageIso: _appLanguageIso,
      targetLanguages: _selectedTargetIsos,
    );
    await widget.store.save(prefs);
    if (!mounted) return;
    Navigator.of(context).pop(prefs);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MalinaliChrome.blueBg,
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _AppLanguageStep(onSelected: _onAppLanguageSelected),
          _TargetLanguageStep(
            appLanguageIso: _appLanguageIso ?? 'fr',
            selectedIsos: _selectedTargetIsos,
            onChanged: (isos) => setState(() {
              _selectedTargetIsos.clear();
              _selectedTargetIsos.addAll(isos);
            }),
            onComplete: _complete,
          ),
        ],
      ),
    );
  }
}

class _AppLanguageStep extends StatelessWidget {
  const _AppLanguageStep({required this.onSelected});

  final ValueChanged<String> onSelected;

  static const List<Map<String, String>> languages = [
    {'iso': 'fr', 'flag': '🇫🇷'},
    {'iso': 'en', 'flag': '🇺🇸'},
    {'iso': 'es', 'flag': '🇪🇸'},
    {'iso': 'pt', 'flag': '🇵🇹'},
    {'iso': 'de', 'flag': '🇩🇪'},
    {'iso': 'ar', 'flag': '🇸🇦'},
    {'iso': 'zh', 'flag': '🇨🇳'},
    {'iso': 'ja', 'flag': '🇯🇵'},
    {'iso': 'ru', 'flag': '🇷🇺'},
    {'iso': 'hi', 'flag': '🇮🇳'},
    {'iso': 'wo', 'flag': '🇸🇳'}, // Wolof
    {'iso': 'ha', 'flag': '🇳🇬'}, // Hausa
    {'iso': 'yo', 'flag': '🇳🇬'}, // Yoruba
    {'iso': 'ig', 'flag': '🇳🇬'}, // Igbo
    {'iso': 'sw', 'flag': '🇰🇪'}, // Swahili
    {'iso': 'ff', 'flag': '🇬🇳'}, // Pulaar/Fulah
    {'iso': 'ln', 'flag': '🇨🇩'}, // Lingala
    {'iso': 'sn', 'flag': '🇿🇼'}, // Shona
    {'iso': 'rw', 'flag': '🇷🇼'}, // Kinyarwanda
    {'iso': 'rn', 'flag': '🇧🇮'}, // Rundi
    {'iso': 'lg', 'flag': '🇺🇬'}, // Ganda
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          const SizedBox(height: 60),
          const Text(
            'Malinali',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 40),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(24),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 20,
                crossAxisSpacing: 20,
              ),
              itemCount: languages.length,
              itemBuilder: (context, index) {
                final lang = languages[index];
                return InkWell(
                  onTap: () => onSelected(lang['iso']!),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        lang['flag']!,
                        style: const TextStyle(fontSize: 40),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TargetLanguageStep extends StatefulWidget {
  const _TargetLanguageStep({
    required this.appLanguageIso,
    required this.selectedIsos,
    required this.onChanged,
    required this.onComplete,
  });

  final String appLanguageIso;
  final List<String> selectedIsos;
  final ValueChanged<List<String>> onChanged;
  final VoidCallback onComplete;

  @override
  State<_TargetLanguageStep> createState() => _TargetLanguageStepState();
}

class _TargetLanguageStepState extends State<_TargetLanguageStep> {
  late List<String> _current;
  List<TranslationModel> _availableTargets = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _current = List.from(widget.selectedIsos);
    if (!_current.contains('en')) _current.add('en');
    _loadTargets();
  }

  Future<void> _loadTargets() async {
    final service = TranslationModelService();
    final all = await service.fetchAllAvailableModels();
    final sourceIso = widget.appLanguageIso.toLowerCase();
    
    // Get all targets available from this source
    final targets = all.where((m) => 
      m.sourceLang.localeIntl.locale.languageCode.toLowerCase() == sourceIso
    ).toList();

    if (!mounted) return;
    setState(() {
      _availableTargets = targets;
      _loading = false;
    });
  }

  void _toggle(String iso) {
    setState(() {
      if (_current.contains(iso)) {
        if (iso != 'en') {
          _current.remove(iso);
        }
      } else {
        _current.add(iso);
      }
    });
    widget.onChanged(_current);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SafeArea(
      child: Column(
        children: [
          const SizedBox(height: 40),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Langues de traduction',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Choisissez les langues vers lesquelles vous voulez traduire.',
              style: TextStyle(color: MalinaliChrome.mutedOnBlue),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _availableTargets.length,
              itemBuilder: (context, index) {
                final model = _availableTargets[index];
                final iso = model.targetLang.localeIntl.locale.languageCode;
                final isSelected = _current.contains(iso);
                final isEnglish = iso == 'en';

                return CheckboxListTile(
                  value: isSelected,
                  onChanged: isEnglish ? null : (_) => _toggle(iso),
                  title: Text(
                    model.targetLang.name.isEmpty
                        ? model.targetLang.nameEn
                        : model.targetLang.name,
                    style: const TextStyle(color: Colors.white),
                  ),
                  secondary: isEnglish ? const Icon(Icons.lock, color: Colors.white54, size: 16) : null,
                  activeColor: MalinaliChrome.yellowBorder,
                  checkColor: Colors.black,
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: widget.onComplete,
                style: FilledButton.styleFrom(
                  backgroundColor: MalinaliChrome.yellowBorder,
                  foregroundColor: Colors.black,
                ),
                child: const Text('Continuer'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
