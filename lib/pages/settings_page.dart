import 'package:flutter/material.dart';
import 'package:malinali/pages/byo_marian_page.dart';
import 'package:malinali/pages/transcription_settings_page.dart';
import 'package:malinali/pages/translation_settings_page.dart';
import 'package:malinali/services/translation_model_service.dart';
import 'package:malinali/services/vosk_model_service.dart';
import 'package:malinali/theme/malinali_chrome.dart';

/// Settings hub:
/// - Traduction (MarianMT text translation models)
/// - Utiliser mon propre modèle (Hugging Face MarianMT)
/// - Transcription (VOSK speech-to-text models)
class SettingsPage extends StatelessWidget {
  final TranslationModelService modelService;
  final TranslationModel? selectedModel;
  final VoskModelService? voskService;
  final VoskModel? selectedVoskModel;

  const SettingsPage({
    super.key,
    required this.modelService,
    this.selectedModel,
    this.voskService,
    this.selectedVoskModel,
  });

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
                  color: MalinaliChrome.blueAction.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.translate,
                  color: MalinaliChrome.yellowBorder,
                  size: 26,
                ),
              ),
              title: const Text(
                'Traduction',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              subtitle: const Text(
                'MarianMT hors-ligne',
                style: TextStyle(fontSize: 13),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final model = await Navigator.push<TranslationModel>(
                  context,
                  MaterialPageRoute(
                    builder: (context) => TranslationSettingsPage(
                      modelService: modelService,
                      selectedModel: selectedModel,
                      voskService: voskService,
                    ),
                  ),
                );
                if (model != null && context.mounted) {
                  Navigator.pop(context, model);
                }
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
                'Utiliser mon propre modèle',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              subtitle: const Text(
                'MarianMT uniquement',
                style: TextStyle(fontSize: 13),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openByo(context),
            ),
          ),
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
                  Icons.mic,
                  color: MalinaliChrome.yellowBorder,
                  size: 26,
                ),
              ),
              title: const Text(
                'Transcription',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              subtitle: const Text(
                'Gérer les modèles vocaux VOSK (reconnaissance vocale)',
                style: TextStyle(fontSize: 13),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final voskModel = await Navigator.push<VoskModel>(
                  context,
                  MaterialPageRoute(
                    builder: (context) => TranscriptionSettingsPage(
                      voskService: voskService ?? VoskModelService(),
                      selectedModel: selectedVoskModel,
                    ),
                  ),
                );
                if (voskModel != null && context.mounted) {
                  Navigator.pop(context, voskModel);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
