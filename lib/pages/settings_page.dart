import 'package:flutter/material.dart';
import 'package:malinali/pages/byo_marian_page.dart';
import 'package:malinali/pages/translate_page.dart';
import 'package:malinali/pages/vosk_transcription_page.dart';
import 'package:malinali/services/marian_runtime.dart';
import 'package:malinali/services/translation_model_service.dart';
import 'package:malinali/services/vosk_model_service.dart';
import 'package:malinali/theme/malinali_chrome.dart';
import 'package:marian_flutter/marian_flutter.dart';

/// Settings hub for voice chat, written translation, and Vosk transcription.
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.modelService,
    this.selectedModel,
    this.voskService,
    this.onConversationTap,
  });

  final TranslationModelService modelService;
  final TranslationModel? selectedModel;
  final VoskModelService? voskService;
  final VoidCallback? onConversationTap;

  Future<void> _openWritten(BuildContext context) async {
    final runtime = MarianRuntime.instance;
    MarianService? marian = runtime.marian;
    TranslationModel? model = runtime.model ?? selectedModel;

    if (marian == null || model == null) {
      final boot = await MarianRuntime.resolveBootModel(modelService);
      model = boot;
      if (boot.isAsset) {
        marian = await MarianService.loadFromAssets(assetFolder: boot.modelId);
      } else {
        final dir = await modelService.downloadModel(boot);
        marian = await MarianService.loadFromDirectory(dir.path);
      }
      runtime.attach(marian, boot);
      await MarianRuntime.saveLastSelectedModel(boot);
    }

    if (!context.mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => TranslatePage(
          initialMarian: marian!,
          initialModel: model,
          modelService: modelService,
        ),
      ),
    );
  }

  Future<void> _openByo(BuildContext context) async {
    final model = await Navigator.push<TranslationModel>(
      context,
      MaterialPageRoute(
        builder: (_) => ByoMarianPage(modelService: modelService),
      ),
    );
    if (model != null && context.mounted) {
      Navigator.pop(context, model);
    }
  }

  void _openTranscription(BuildContext context) {
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => VoskTranscriptionPage(
          voskService: voskService ?? VoskModelService(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Paramètres'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
        children: [
          Card(
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: MalinaliChrome.yellowBorder.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.translate,
                  color: MalinaliChrome.yellowBorder,
                  size: 26,
                ),
              ),
              title: const Text(
                'Traduction vocale',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              subtitle: const Text(
                'Langues parlées, cible, taille du modèle',
                style: TextStyle(fontSize: 13),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(context);
                onConversationTap?.call();
              },
            ),
          ),
          Card(
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: MalinaliChrome.blueAction.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.file_present_outlined,
                  color: MalinaliChrome.yellowBorder,
                  size: 26,
                ),
              ),
              title: const Text(
                'Traduction écrite',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              subtitle: const Text(
                'Texte et fichier',
                style: TextStyle(fontSize: 13),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openWritten(context),
            ),
          ),
          Card(
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: MalinaliChrome.blueChip.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.audio_file_outlined,
                  color: MalinaliChrome.yellowBorder,
                  size: 26,
                ),
              ),
              title: const Text(
                'Transcription vocale',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              subtitle: const Text(
                'Micro et fichier audio',
                style: TextStyle(fontSize: 13),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openTranscription(context),
            ),
          ),
          Card(
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: MalinaliChrome.customPanel.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  color: MalinaliChrome.yellowBorder,
                  size: 26,
                ),
              ),
              title: const Text(
                'Utiliser mon modèle de traduction',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              subtitle: const Text(
                'MarianMT uniquement',
                style: TextStyle(fontSize: 13),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openByo(context),
            ),
          ),
        ],
      ),
    );
  }
}
