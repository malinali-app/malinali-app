import 'package:flutter/material.dart';
import 'package:malinali/pages/translate_page.dart';
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

/// Loads the on-device Marian model, then opens [TranslatePage].
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
    try {
      setState(() {
        _status = 'Initialisation Rust…';
        _error = null;
      });
      await MarianService.initRust();

      if (!mounted) return;
      setState(() => _status = 'Préparation des fichiers du modèle…');

      final marian = await MarianService.loadFromAssets(
        assetFolder: 'assets/fr-pul',
      );

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
          builder: (_) => TranslatePage(initialMarian: marian),
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
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _loadModel,
                  child: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _status,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
