import 'package:flutter/material.dart';
import 'package:malinali/pages/onboarding_page.dart';
import 'package:malinali/pages/voice_chat_page.dart';
import 'package:malinali/services/translation_model_service.dart';
import 'package:malinali/services/voice_preferences.dart';
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

/// Inits Rust once, then opens the app home.
class MarianBootScreen extends StatefulWidget {
  const MarianBootScreen({super.key});

  @override
  State<MarianBootScreen> createState() => _MarianBootScreenState();
}

class _MarianBootScreenState extends State<MarianBootScreen> {
  String _status = 'Démarrage…';
  String? _error;
  final _prefsStore = VoicePreferencesStore();

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _openHome(VoicePreferences prefs) async {
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        settings: const RouteSettings(name: '/'),
        builder: (_) => VoiceChatPage(
          initialPrefs: prefs,
        ),
      ),
    );
  }

  Future<void> _boot() async {
    try {
      setState(() {
        _status = 'Initialisation…';
        _error = null;
      });
      await MarianService.initRust();

      if (!mounted) return;
      final prefs = await _prefsStore.load();

      if (prefs == null) {
        if (!mounted) return;
        final newPrefs = await Navigator.of(context).push<VoicePreferences>(
          MaterialPageRoute(
            builder: (_) => OnboardingFlow(store: _prefsStore),
          ),
        );
        if (newPrefs != null) {
          await _openHome(newPrefs);
        }
      } else {
        await _openHome(prefs);
      }
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
                  onPressed: _boot,
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
