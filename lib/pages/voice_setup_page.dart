import 'package:flutter/material.dart';
import 'package:malinali/services/voice_preferences.dart';
import 'package:malinali/theme/malinali_chrome.dart';

/// First-launch spoken language, target, and speech model size.
class VoiceSetupPage extends StatefulWidget {
  const VoiceSetupPage({
    super.key,
    this.store,
    this.initial,
  });

  final VoicePreferencesStore? store;
  final VoicePreferences? initial;

  @override
  State<VoiceSetupPage> createState() => _VoiceSetupPageState();
}

class _VoiceSetupPageState extends State<VoiceSetupPage> {
  late String _sourceIso;
  late String _targetIso;
  late VoiceWhisperSize _size;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final seed = widget.initial ?? VoicePreferences.defaults;
    _sourceIso = seed.sourceIso;
    _targetIso = seed.targetIso;
    _size = seed.whisperSize;
  }

  Future<void> _continue() async {
    setState(() => _saving = true);
    final prefs = VoicePreferences(
      sourceIso: _sourceIso,
      targetIso: _targetIso,
      whisperSize: _size,
    );
    final store = widget.store ?? VoicePreferencesStore();
    await store.save(prefs);
    if (!mounted) return;
    Navigator.of(context).pop(prefs);
  }

  @override
  Widget build(BuildContext context) {
    final spoken = voiceSpokenLanguagePacks();
    final selectedPack = spoken.firstWhere(
      (p) => p.iso.toLowerCase() == _sourceIso.toLowerCase(),
      orElse: () => spoken.first,
    );
    final isGeneric = selectedPack.ggmlUrl == 'builtin';

    final targets = voiceEnglishTargetModels().where((m) {
      final targetIso = m.targetLang.localeIntl.locale.languageCode.toLowerCase();
      if (targetIso == _sourceIso.toLowerCase()) return false;

      // 1. English is always a target for non-English sources
      if (targetIso == 'en') return true;

      // 2. If we have a direct model from source -> target, allow it
      final direct = curatedMarianForPair(sourceIso: _sourceIso, targetIso: targetIso);
      if (direct != null) return true;

      // 3. For English source, show all English -> X models
      if (_sourceIso.toLowerCase() == 'en') return true;

      // 4. For French source, allow bridge through English to any target
      if (_sourceIso.toLowerCase() == 'fr') return true;

      // 5. For other languages, restrict to English and French by default
      // (This covers the bridge Source -> English -> French)
      return targetIso == 'fr';
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Conversation'),
        automaticallyImplyLeading: widget.initial != null,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Choisissez la langue parlée et la langue cible',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: MalinaliChrome.mutedOnBlue,
                ),
          ),
          const SizedBox(height: 20),
          Text(
            'Je parle',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          ...spoken.map((pack) {
            final lang = voiceLanguageByIso(pack.iso);
            final label = lang == null
                ? pack.labelFr
                : (lang.name.isEmpty ? lang.nameEn : lang.name);
            return RadioListTile<String>(
              value: pack.iso,
              groupValue: _sourceIso,
              title: Text(label),
              subtitle: Text(pack.labelFr),
              activeColor: MalinaliChrome.yellowBorder,
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _sourceIso = v;
                  // Avoid source == target
                  if (_sourceIso.toLowerCase() == _targetIso.toLowerCase()) {
                    if (_sourceIso.toLowerCase() == 'en') {
                      _targetIso = 'fr';
                    } else {
                      _targetIso = 'en';
                    }
                  }
                  // If switching to African source, ensure target is en/fr
                  if (_sourceIso != 'en' && _sourceIso != 'fr') {
                    if (_targetIso != 'en' && _targetIso != 'fr') {
                      _targetIso = 'fr';
                    }
                  }
                });
              },
            );
          }),
          const SizedBox(height: 16),
          Text(
            'Traduire vers',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          ...targets.map((model) {
            final iso = model.targetLang.localeIntl.locale.languageCode;
            final englishName = model.targetLang.nameEn;
            final subtitle = model.qualityHint != null
                ? '$englishName • ${model.qualityHint}'
                : englishName;
            return RadioListTile<String>(
              value: iso,
              groupValue: _targetIso,
              title: Text(
                model.targetLang.name.isEmpty
                    ? model.targetLang.nameEn
                    : model.targetLang.name,
              ),
              subtitle: Text(subtitle),
              activeColor: MalinaliChrome.yellowBorder,
              onChanged: (v) {
                if (v == null) return;
                setState(() => _targetIso = v);
              },
            );
          }),
          if (isGeneric) ...[
            const SizedBox(height: 16),
            Text(
              'Qualité vocale',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              '250 Mo donne en général de meilleurs résultats.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: MalinaliChrome.mutedOnBlue,
                  ),
            ),
            const SizedBox(height: 8),
            ...VoiceWhisperSize.values.map((size) {
              return RadioListTile<VoiceWhisperSize>(
                value: size,
                groupValue: _size,
                title: Text(size.sizeHintFr),
                subtitle: Text(
                  size == VoiceWhisperSize.quality ? 'Recommandé' : 'Plus léger',
                ),
                activeColor: MalinaliChrome.yellowBorder,
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _size = v);
                },
              );
            }),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _continue,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Continuer'),
          ),
        ],
      ),
    );
  }
}
