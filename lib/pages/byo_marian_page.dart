import 'package:flutter/material.dart';
import 'package:languages_dart/languages_dart.dart';
import 'package:malinali/services/translation_model_service.dart';
import 'package:malinali/theme/malinali_chrome.dart';
import 'package:malinali/widgets/language_picker_sheet.dart';
import 'package:url_launcher/url_launcher.dart';

/// Advanced: register a Hugging Face Marian / Candle pack (Bring Your Own).
class ByoMarianPage extends StatefulWidget {
  const ByoMarianPage({super.key, required this.modelService});

  final TranslationModelService modelService;

  @override
  State<ByoMarianPage> createState() => _ByoMarianPageState();
}

class _ByoMarianPageState extends State<ByoMarianPage> {
  final _repoController = TextEditingController();
  final _tokenController = TextEditingController();
  Language? _sourceLang;
  Language? _targetLang;
  bool _busy = false;
  String? _error;
  String? _success;
  List<TranslationModel> _custom = [];

  @override
  void initState() {
    super.initState();
    _reloadCustom();
  }

  @override
  void dispose() {
    _repoController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _reloadCustom() async {
    final list = await widget.modelService.loadCustomModels();
    if (!mounted) return;
    setState(() => _custom = list);
  }

  Future<void> _pickLang({required bool source}) async {
    final picked = await LanguagePickerSheet.show(
      context,
      languages: Languages.defaultLanguages,
      selected: source ? _sourceLang : _targetLang,
      title: source ? 'Langue source' : 'Langue cible',
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (source) {
        _sourceLang = picked;
      } else {
        _targetLang = picked;
      }
    });
  }

  Future<void> _register() async {
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });
    try {
      final model = await widget.modelService.registerHuggingFaceModel(
        repoId: _repoController.text,
        authToken: _tokenController.text.isEmpty ? null : _tokenController.text,
        sourceLang: _sourceLang,
        targetLang: _targetLang,
      );
      await _reloadCustom();
      if (!mounted) return;
      setState(() {
        _success =
            'Modèle ajouté: ${model.modelId} (${model.displayName}). '
            'Il apparaît dans la liste de traduction; le téléchargement '
            'se lance à la sélection.';
        _sourceLang ??= model.sourceLang;
        _targetLang ??= model.targetLang;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(TranslationModel model) async {
    await widget.modelService.removeCustomModel(model.modelId);
    await _reloadCustom();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bring Your Own — MarianMT')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ExplanationCard(
            onOpenDocs:
                () => launchUrl(
                  Uri.parse(
                    'https://huggingface.co/docs/hub/models-downloading',
                  ),
                ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _repoController,
            enabled: !_busy,
            style: const TextStyle(color: MalinaliChrome.onBlue),
            decoration: const InputDecoration(
              labelText: 'Identifiant Hugging Face',
              hintText: 'ex. Xenova/opus-mt-fr-en ou org/mon-finetune',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.cloud_download),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tokenController,
            enabled: !_busy,
            obscureText: true,
            style: const TextStyle(color: MalinaliChrome.onBlue),
            decoration: const InputDecoration(
              labelText: 'Jeton HF (optionnel, dépôts privés)',
              hintText: 'hf_… lecture seule recommandée',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.key),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _pickLang(source: true),
                  child: Text(
                    _sourceLang == null
                        ? 'Source (auto si opus-mt-*)'
                        : 'Source: ${languageDisplayName(_sourceLang!)}',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _pickLang(source: false),
                  child: Text(
                    _targetLang == null
                        ? 'Cible (auto si opus-mt-*)'
                        : 'Cible: ${languageDisplayName(_targetLang!)}',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _register,
            icon:
                _busy
                    ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.add),
            label: Text(_busy ? 'Vérification…' : 'Ajouter le modèle'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(color: MalinaliChrome.redAccent),
            ),
          ],
          if (_success != null) ...[
            const SizedBox(height: 12),
            Text(
              _success!,
              style: const TextStyle(color: MalinaliChrome.success),
            ),
          ],
          const SizedBox(height: 24),
          Text(
            'Modèles ajoutés',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: MalinaliChrome.onBlue,
                ),
          ),
          const SizedBox(height: 8),
          if (_custom.isEmpty)
            const Text(
              'Aucun modèle personnalisé pour l’instant.',
              style: TextStyle(color: MalinaliChrome.mutedOnBlue),
            )
          else
            ..._custom.map(
              (m) => Card(
                color: MalinaliChrome.customPanel,
                child: ListTile(
                  title: Text(m.displayName),
                  subtitle: Text(m.modelId),
                  trailing: IconButton(
                    tooltip: 'Retirer',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _remove(m),
                  ),
                  onTap: () => Navigator.pop(context, m),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ExplanationCard extends StatelessWidget {
  const _ExplanationCard({required this.onOpenDocs});

  final VoidCallback onOpenDocs;

  @override
  Widget build(BuildContext context) {
    const bodyStyle = TextStyle(
      fontFamily: 'NotoSans',
      color: MalinaliChrome.onBlue,
      fontSize: 14,
      height: 1.4,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Qu’est-ce qu’un modèle MarianMT « Candle » ?',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: MalinaliChrome.yellowBorder,
                  ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Malinali charge des poids Marian (.safetensors) '
              'via le moteur Rust Candle (marian_flutter)'
              'Le dépôt Hugging Face doit exposer des fichiers prêts à l\'usage : ',
              style: bodyStyle,
            ),
            const SizedBox(height: 8),
            const Text('• config.json — architecture Marian', style: bodyStyle),
            const Text(
              '• model.safetensors — poids (~75–285 Mo)',
              style: bodyStyle,
            ),
            const Text(
              '• tokenizer.json — OU la paire tokenizer-enc.json + tokenizer-dec.json ',
              style: bodyStyle,
            ),
            const SizedBox(height: 8),
            const Text(
              'Les dépôts Helsinki-NLP et Xenova/opus-mt-* fonctionnent tels quels.',
              style: bodyStyle,
            ),
            const SizedBox(height: 8),
            const Text(
              'Les langues sont déduites si le nom contient opus-mt-xx-yy '
              '(ex. opus-mt-fr-en). Sinon, choisissez source et cible ci-dessous. ',
              style: bodyStyle,
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onOpenDocs,
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Doc Hugging Face Hub'),
            ),
          ],
        ),
      ),
    );
  }
}
