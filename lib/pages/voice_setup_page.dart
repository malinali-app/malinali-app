import 'package:flutter/material.dart';
import 'package:malinali/services/supported_languages.dart';
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

    final targets = getAvailableTargetLanguages(sourceIso: _sourceIso);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Traduction vocale'),
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
                  final available = getAvailableTargetLanguages(sourceIso: _sourceIso);
                  if (!available.any((t) => t.iso == _targetIso)) {
                    _targetIso = available.isNotEmpty ? available.first.iso : 'fr';
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
          ...targets.map((target) {
            final subtitleParts = [
              if (target.nameEn.isNotEmpty && target.nameEn != target.name)
                target.nameEn,
              target.iso.toUpperCase(),
              if (target.qualityHint != null) target.qualityHint!,
            ];
            final subtitle = subtitleParts.join(' · ');
            return RadioListTile<String>(
              value: target.iso,
              groupValue: _targetIso,
              title: Text(target.name),
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
