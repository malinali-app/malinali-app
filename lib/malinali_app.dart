import 'package:flutter/material.dart';
import 'package:malinali/pages/translate_page.dart';
import 'package:malinali/services/marian_runtime.dart';
import 'package:malinali/services/translation_model_service.dart';
import 'package:malinali/theme/malinali_chrome.dart';
import 'package:marian_flutter/marian_flutter.dart';

class MalinaliApp extends StatelessWidget {
  const MalinaliApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Malinali',
      theme: MalinaliChrome.theme(),
      debugShowCheckedModeBanner: false,
      home: const MarianBootScreen(),
    );
  }
}

/// Loads the preferred Marian model once, then opens [TranslatePage].
///
/// Reuses [MarianRuntime] when the process is still alive so background/resume
/// does not re-show this screen. On cold start, restores the last selected
/// model when already downloaded.
class MarianBootScreen extends StatefulWidget {
  const MarianBootScreen({super.key});

  @override
  State<MarianBootScreen> createState() => _MarianBootScreenState();
}

class _MarianBootScreenState extends State<MarianBootScreen> {
  String _status = 'Chargement du modèle…';
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadModel();
  }

  Future<void> _openTranslate(MarianService marian, TranslationModel model) {
    return Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => TranslatePage(
          initialMarian: marian,
          initialModel: model,
        ),
      ),
    );
  }

  Future<void> _loadModel() async {
    final runtime = MarianRuntime.instance;
    if (runtime.isReady) {
      if (!mounted) return;
      await _openTranslate(runtime.marian!, runtime.model!);
      return;
    }

    final modelService = TranslationModelService();
    try {
      setState(() {
        _status = 'Initialisation Rust…';
        _error = null;
      });
      await MarianService.initRust();

      if (!mounted) return;
      final bootModel = await MarianRuntime.resolveBootModel(modelService);
      setState(() => _status = 'Chargement ${bootModel.displayName}…');

      MarianService marian;
      if (bootModel.isAsset) {
        marian = await MarianService.loadFromAssets(
          assetFolder: bootModel.modelId,
        );
      } else {
        final dir = await modelService.downloadModel(bootModel);
        if (!mounted) return;
        setState(() => _status = 'Chargement du modèle…');
        marian = await MarianService.loadFromDirectory(dir.path);
      }

      runtime.attach(marian, bootModel);
      await MarianRuntime.saveLastSelectedModel(bootModel);

      if (!mounted) return;
      await _openTranslate(marian, bootModel);

      // Warmup off the critical path so resume / cold start feels snappier.
      marian.translate('Bonjour').then((_) {}, onError: (_) {});
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _status = 'Erreur';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_error == null) const CircularProgressIndicator(),
              const SizedBox(height: 24),
              Text(
                _status,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _loadModel,
                  child: const Text('Réessayer'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
