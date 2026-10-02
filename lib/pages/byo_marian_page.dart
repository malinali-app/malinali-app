import 'package:flutter/material.dart';
import 'package:languages_dart/languages_dart.dart';
import 'package:malinali/services/translation_model_service.dart';
import 'package:malinali/theme/malinali_chrome.dart';
import 'package:malinali/widgets/language_picker_sheet.dart';
import 'package:url_launcher/url_launcher.dart';

/// Register a Hugging Face MarianMT pack (bring your own).
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
      appBar: AppBar(title: const Text('Mon modèle')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'MarianMT uniquement — dépôt Hugging Face.',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: MalinaliChrome.mutedOnBlue,
                  fontWeight: FontWeight.w600,
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
                        ? 'Langue Source'
                        : languageDisplayName(_sourceLang!),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _pickLang(source: false),
                  child: Text(
                    _targetLang == null
                        ? 'Langue Cible'
                        : languageDisplayName(_targetLang!),
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
          const SizedBox(height: 28),
          _ExplanationCard(
            onOpenDocs:
                () => launchUrl(
                  Uri.parse(
                    'https://huggingface.co/docs/hub/models-downloading',
                  ),
                ),
          ),
          const SizedBox(height: 16),
          const _MarianCredit(),
        ],
      ),
    );
  }
}

class _MarianCredit extends StatelessWidget {
  const _MarianCredit();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text(
          'Basé sur ',
          style: TextStyle(
            fontFamily: 'NotoSans',
            color: MalinaliChrome.mutedOnBlue,
            fontSize: 12,
            height: 1.35,
          ),
        ),
        InkWell(
          onTap: () => launchUrl(Uri.parse('https://marian-nmt.github.io/')),
          child: const Text(
            'Marian',
            style: TextStyle(
              fontFamily: 'NotoSans',
              color: MalinaliChrome.yellowBorder,
              fontSize: 12,
              height: 1.35,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
        const Text(
          ', framework de traduction neuronale.',
          style: TextStyle(
            fontFamily: 'NotoSans',
            color: MalinaliChrome.mutedOnBlue,
            fontSize: 12,
            height: 1.35,
          ),
        ),
      ],
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
      fontSize: 13,
      height: 1.4,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Fichiers MarianMT requis',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: MalinaliChrome.yellowBorder,
                  ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Le dépôt Hugging Face doit contenir : '
              'config.json, model.safetensors, et tokenizer.json '
              '(ou tokenizer-enc.json + tokenizer-dec.json). '
              'Helsinki-NLP et Xenova/opus-mt-* fonctionnent tels quels.',
              style: bodyStyle,
            ),
            const SizedBox(height: 4),
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
