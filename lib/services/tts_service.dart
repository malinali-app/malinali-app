import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:languages_dart/languages_dart.dart';

class TtsService {
  final FlutterTts _flutterTts = FlutterTts();
  bool _initialized = false;
  bool? _isTtsAvailable;

  /// High-confidence ISO codes for system TTS engines.
  /// Standard OS engines (Android/iOS/Windows) usually have high-quality
  /// voices for these. We exclude most African languages for now as they
  /// often fall back to "weird" voices.
  static const Set<String> _wellSupportedIsos = {
    'en', // English
    'fr', // French
    'es', // Spanish
    'de', // German
    'it', // Italian
    'pt', // Portuguese
    'nl', // Dutch
    'ru', // Russian
    'zh', // Chinese
    'ja', // Japanese
    'ko', // Korean
    'sw', // Swahili (often supported by Google)
  };

  Future<void> init() async {
    if (_initialized) return;
    try {
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setPitch(1.0);
      _initialized = true;
    } catch (e) {
      debugPrint('Error initializing TTS: $e');
    }
  }

  /// Returns true if the platform has a functional TTS engine.
  Future<bool> isAvailable() async {
    if (_isTtsAvailable != null) return _isTtsAvailable!;
    
    try {
      // Just check if the channel is reachable by calling a simple method.
      // We don't use isLanguageAvailable here as it might be missing on some platforms.
      await _flutterTts.getLanguages;
      _isTtsAvailable = true;
    } catch (e) {
      debugPrint('TTS not available on this platform: $e');
      _isTtsAvailable = false;
    }
    return _isTtsAvailable!;
  }

  /// Returns true if the language is in our high-confidence whitelist.
  bool isLanguageWellSupported(String iso) {
    return _wellSupportedIsos.contains(iso.toLowerCase());
  }

  /// Attempts to speak [text] in the given [language].
  /// Returns true if the language is supported and speaking started.
  Future<bool> speak(String text, Language language) async {
    if (text.isEmpty) return false;
    if (!await isAvailable()) return false;
    await init();

    final langCode = await _resolveEngineLanguage(language);
    
    try {
      final dynamic setResult = await _flutterTts.setLanguage(langCode);
      final applied = setResult == true || setResult == 1;
      if (!applied) {
        debugPrint('TTS: Language $langCode not supported on this device.');
        return false;
      }
      await _flutterTts.speak(text);
      return true;
    } catch (e) {
      debugPrint('TTS Speak Error: $e');
      return false;
    }
  }

  Future<void> stop() async {
    try {
      await _flutterTts.stop();
    } catch (e) {
      debugPrint('TTS Stop Error: $e');
    }
  }

  /// Locale tag the engine will actually select.
  ///
  /// Windows SAPI matches the full name (`fr-FR`). Passing `fr` leaves the
  /// default English voice in place and French text is read in English.
  Future<String> _resolveEngineLanguage(Language language) async {
    final iso = language.localeIntl.locale.languageCode.toLowerCase();
    final country = language.localeIntl.locale.countryCode;
    final preferred = <String>[
      if (country != null && country.isNotEmpty) '$iso-${country.toUpperCase()}',
      ..._preferredTtsTags(iso),
    ];

    List<String> installed = const [];
    try {
      final raw = await _flutterTts.getLanguages;
      if (raw is List) {
        installed = raw.map((e) => e.toString()).where((t) => t.isNotEmpty).toList();
      }
    } catch (e) {
      debugPrint('TTS language list unavailable: $e');
    }

    for (final want in preferred) {
      for (final tag in installed) {
        if (tag.toLowerCase().replaceAll('_', '-') == want.toLowerCase()) {
          return tag;
        }
      }
    }
    for (final tag in installed) {
      final norm = tag.toLowerCase().replaceAll('_', '-');
      if (norm == iso || norm.startsWith('$iso-')) return tag;
    }
    return preferred.first;
  }

  List<String> _preferredTtsTags(String iso) {
    switch (iso) {
      case 'fr':
        return const ['fr-FR', 'fr-CA', 'fr'];
      case 'en':
        return const ['en-US', 'en-GB', 'en'];
      case 'es':
        return const ['es-ES', 'es-MX', 'es'];
      case 'pt':
        return const ['pt-PT', 'pt-BR', 'pt'];
      case 'de':
        return const ['de-DE', 'de'];
      case 'it':
        return const ['it-IT', 'it'];
      case 'nl':
        return const ['nl-NL', 'nl'];
      case 'zh':
        return const ['zh-CN', 'zh-TW', 'zh'];
      default:
        return [iso];
    }
  }
}
