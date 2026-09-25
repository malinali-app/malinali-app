import 'package:flutter/material.dart';
import 'package:malinali/pages/transcription_settings_page.dart';
import 'package:malinali/pages/translation_settings_page.dart';
import 'package:malinali/services/translation_model_service.dart';
import 'package:malinali/services/vosk_model_service.dart';

/// Settings hub with two distinct tiles:
/// - Traduction (MarianMT text translation models)
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
            elevation: 1,
            margin: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 4.0),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.translate,
                  color: Colors.blue.shade700,
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
                'Gérer et télécharger les modèles MarianMT',
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
            elevation: 1,
            margin: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 4.0),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.mic,
                  color: Colors.orange.shade800,
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
