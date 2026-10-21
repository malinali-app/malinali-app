import 'package:malinali/services/african_helsinki_models.dart';
import 'package:malinali/services/voice_preferences.dart';

/// Supported source languages for the initial setup.
class AppSourceLanguage {
  const AppSourceLanguage({
    required this.iso,
    required this.name,
    required this.nameEn,
  });

  final String iso;
  final String name;
  final String nameEn;
}

/// Spoken sources for voice onboarding. Wolof is a **target** only (EN/FR→WO);
/// WO→EN/FR vocal quality is not offered. Fon is Fon audio → French only.
const List<AppSourceLanguage> kSupportedSourceLanguages = [
  AppSourceLanguage(iso: 'en', name: 'English', nameEn: 'English'),
  AppSourceLanguage(iso: 'fr', name: 'Français', nameEn: 'French'),
  AppSourceLanguage(iso: 'fon', name: 'Fon', nameEn: 'Fon'),
];

/// Target language option shown in the language picker.
class TargetLanguageOption {
  const TargetLanguageOption({
    required this.iso,
    required this.name,
    required this.nameEn,
    this.qualityHint,
  });

  final String iso;
  final String name;
  final String nameEn;
  final String? qualityHint;
}

/// Parses the numeric BLEU score from a hint like "BLEU 34.1 / 100" or "BLEU 34.1".
double? extractBleuScore(String? qualityHint) {
  if (qualityHint == null) return null;
  final match = RegExp(r'BLEU\s+([\d.]+)').firstMatch(qualityHint);
  if (match == null) return null;
  return double.tryParse(match.group(1)!);
}

/// Computes the valid target languages for a given source ISO.
///
/// Rules:
/// - Low-resource languages (e.g. Wolof) can ONLY target French or English.
/// - French / English sources can target Wolof, reciprocal (FR↔EN), and
///   African languages with a MarianMT BLEU score >= [minBleuScore] (default 30.0).
List<TargetLanguageOption> getAvailableTargetLanguages({
  required String sourceIso,
  double minBleuScore = 30.0,
  bool includeEnFrReciprocal = true,
}) {
  final src = sourceIso.toLowerCase();

  // Fon speech-translation pack emits French only (no Marian hop).
  if (src == 'fon') {
    return _sortedByName(const [
      TargetLanguageOption(
        iso: 'fr',
        name: 'Français',
        nameEn: 'French',
        qualityHint: 'ST (sem_sim gate)',
      ),
    ]);
  }

  // Rule 1: Low-resource language (Wolof or others) -> strictly French & English
  if (src != 'fr' && src != 'en') {
    return _sortedByName(const [
      TargetLanguageOption(
        iso: 'fr',
        name: 'Français',
        nameEn: 'French',
      ),
      TargetLanguageOption(
        iso: 'en',
        name: 'English',
        nameEn: 'English',
        qualityHint: 'BLEU 68.5 / 100',
      ),
    ]);
  }

  final List<TargetLanguageOption> targets = [];

  // Rule 2: Reciprocal European bridge (FR <-> EN)
  if (includeEnFrReciprocal) {
    if (src == 'fr') {
      targets.add(const TargetLanguageOption(
        iso: 'en',
        name: 'English',
        nameEn: 'English',
      ));
    } else if (src == 'en') {
      targets.add(const TargetLanguageOption(
        iso: 'fr',
        name: 'Français',
        nameEn: 'French',
      ));
    }
  }

  // Rule 3: Wolof is always available for French and English sources
  if (src == 'fr') {
    targets.add(const TargetLanguageOption(
      iso: 'wo',
      name: 'Wolof',
      nameEn: 'Wolof',
      // Direct FR→WO is BLEU 9.3; voice/auto uses FR→EN then LocaleNLP en→wo.
      qualityHint: 'BLEU 76.1 / 100',
    ));
  } else if (src == 'en') {
    targets.add(const TargetLanguageOption(
      iso: 'wo',
      name: 'Wolof',
      nameEn: 'Wolof',
      qualityHint: 'BLEU 76.1 / 100',
    ));
  }

  // Rule 4: African languages with MarianMT BLEU >= minBleuScore
  for (final pair in kAfricanHelsinkiOpusPairs) {
    if (pair.sourceIso != src) continue;
    final bleu = extractBleuScore(pair.qualityHint);
    if (bleu == null || bleu < minBleuScore) continue;

    final lang = voiceLanguageByIso(pair.targetIso);
    final nativeName = lang == null
        ? pair.targetIso
        : (lang.name.isNotEmpty ? lang.name : lang.nameEn);
    final englishName = lang?.nameEn ?? pair.targetIso;

    if (targets.any((t) => t.iso == pair.targetIso)) continue;

    targets.add(TargetLanguageOption(
      iso: pair.targetIso,
      name: nativeName,
      nameEn: englishName,
      qualityHint: formatOpusBleuHint(pair.qualityHint),
    ));
  }

  return _sortedByName(targets);
}

/// Default pick after a source change: Wolof, then French, then English.
String? preferredTargetIso(List<TargetLanguageOption> targets) {
  const preferred = ['wo', 'fr', 'en'];
  for (final iso in preferred) {
    for (final target in targets) {
      if (target.iso == iso) return target.iso;
    }
  }
  return targets.isNotEmpty ? targets.first.iso : null;
}

List<TargetLanguageOption> _sortedByName(List<TargetLanguageOption> targets) {
  final out = List<TargetLanguageOption>.from(targets);
  out.sort(
    (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
  );
  return out;
}
