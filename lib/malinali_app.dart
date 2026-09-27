import 'package:flutter/material.dart';
import 'package:malinali/pages/translate_page.dart';
import 'package:malinali/services/translation_model_service.dart';
import 'package:marian_flutter/marian_flutter.dart';

class MalinaliApp extends StatelessWidget {
  const MalinaliApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Malinali',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
        fontFamily: 'NotoSans',
      ),
      debugShowCheckedModeBanner: false,
      home: const MarianBootScreen(),
    );
  }
}

/// Downloads the small public Xenova FR→EN model, then opens [TranslatePage].
/// French→Pulaar is selected later in settings and downloads from Hugging Face.
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

  Future<void> _loadModel() async {
    final modelService = TranslationModelService();
    final bootModel = TranslationModelService.defaultBootModel;
    try {
      setState(() {
        _status = 'Initialisation Rust…';
        _error = null;
      });
      await MarianService.initRust();

      if (!mounted) return;
      setState(() => _status = 'Téléchargement ${bootModel.modelId}…');

      final dir = await modelService.downloadModel(bootModel);

      if (!mounted) return;
      setState(() => _status = 'Chargement du modèle…');
      final marian = await MarianService.loadFromDirectory(dir.path);

      // First Candle forward pays mmap / CPU warmup; do it off the translate UI.
      if (!mounted) return;
      setState(() => _status = 'Préparation de la traduction…');
      try {
        await marian.translate('Bonjour');
      } catch (_) {
        // Warmup is best-effort; real errors still surface on user translate.
      }

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => TranslatePage(
            initialMarian: marian,
            initialModel: bootModel,
          ),
        ),
      );
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
