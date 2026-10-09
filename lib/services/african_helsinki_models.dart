import 'package:intl/locale.dart';
import 'package:languages_dart/languages_dart.dart';

/// Extra ISO codes not always present (or aliased) in [Languages.defaultLanguages].
Language? africanLanguageByIso(String iso) {
  switch (iso.toLowerCase()) {
    case 'rn':
    case 'run':
      return Languages.rundi;
    case 'swc':
      return Language(
        LocaleIntl(Locale.fromSubtags(languageCode: 'swc')),
        'Congo Swahili',
        'Congo Swahili',
      );
    case 'kab':
      return Language(
        LocaleIntl(Locale.fromSubtags(languageCode: 'kab')),
        'Kabyle',
        'Taqbaylit',
      );
    case 'tiv':
      return Language(
        LocaleIntl(Locale.fromSubtags(languageCode: 'tiv')),
        'Tiv',
        'Tiv',
      );
    case 'ff':
    case 'fuv':
    case 'fuc':
      return Language(
        Languages.fulah.localeIntl,
        'Pulaar',
        'Pulaar',
      );
    default:
      return null;
  }
}

/// Curated bilateral African / LR Helsinki Opus-MT pairs (no multilingual).
/// af↔en / xh↔en omitted (already via Xenova).
///
/// BLEU paper: https://dl.acm.org/doi/10.3115/1073083.1073135
const kBleuPaperUrl = 'https://dl.acm.org/doi/10.3115/1073083.1073135';

/// Formats OPUS BLEU for UI: `BLEU 34.1` → `BLEU 34.1 / 100`. Bare `OPUS` unchanged.
String formatOpusBleuHint(String hint) {
  if (RegExp(r'^BLEU\s+[\d.]+$').hasMatch(hint)) {
    return '$hint / 100';
  }
  return hint;
}

/// One Helsinki Opus-MT bilateral. [qualityHint] is OPUS card BLEU when known
/// (`BLEU 34.1` or `OPUS`). When [candleOrg] is set (default `malinali-app`),
/// the app downloads that org's Candle pack instead of raw Helsinki-NLP.
class AfricanOpusPair {
  const AfricanOpusPair({
    required this.sourceIso,
    required this.targetIso,
    required this.repoName,
    required this.qualityHint,
    this.candleOrg = 'malinali-app',
  });

  final String sourceIso;
  final String targetIso;
  final String repoName;
  final String qualityHint;
  /// HF org hosting the Candle pack (`config` + safetensors + enc/dec).
  final String candleOrg;

  String get modelId => '$candleOrg/$repoName';
}

const List<AfricanOpusPair> kAfricanHelsinkiOpusPairs = [
  // Hausa
  AfricanOpusPair(sourceIso: 'en', targetIso: 'ha', repoName: 'opus-mt-en-ha', qualityHint: 'BLEU 34.1'),
  AfricanOpusPair(sourceIso: 'ha', targetIso: 'en', repoName: 'opus-mt-ha-en', qualityHint: 'BLEU 35.0'),
  AfricanOpusPair(sourceIso: 'fr', targetIso: 'ha', repoName: 'opus-mt-fr-ha', qualityHint: 'BLEU 24.4'),
  AfricanOpusPair(sourceIso: 'ha', targetIso: 'fr', repoName: 'opus-mt-ha-fr', qualityHint: 'BLEU 24.3'),
  AfricanOpusPair(sourceIso: 'de', targetIso: 'ha', repoName: 'opus-mt-de-ha', qualityHint: 'OPUS'),
  AfricanOpusPair(sourceIso: 'ha', targetIso: 'es', repoName: 'opus-mt-ha-es', qualityHint: 'BLEU 21.8'),
  AfricanOpusPair(sourceIso: 'es', targetIso: 'ha', repoName: 'opus-mt-es-ha', qualityHint: 'OPUS'),
  AfricanOpusPair(sourceIso: 'fi', targetIso: 'ha', repoName: 'opus-mt-fi-ha', qualityHint: 'OPUS'),
  AfricanOpusPair(sourceIso: 'ha', targetIso: 'fi', repoName: 'opus-mt-ha-fi', qualityHint: 'BLEU 21.9'),
  AfricanOpusPair(sourceIso: 'sv', targetIso: 'ha', repoName: 'opus-mt-sv-ha', qualityHint: 'OPUS'),
  AfricanOpusPair(sourceIso: 'ha', targetIso: 'sv', repoName: 'opus-mt-ha-sv', qualityHint: 'OPUS'),

  // Yoruba
  AfricanOpusPair(sourceIso: 'yo', targetIso: 'en', repoName: 'opus-mt-yo-en', qualityHint: 'BLEU 33.8'),
  AfricanOpusPair(sourceIso: 'fr', targetIso: 'yo', repoName: 'opus-mt-fr-yo', qualityHint: 'BLEU 25.9'),
  AfricanOpusPair(sourceIso: 'yo', targetIso: 'fr', repoName: 'opus-mt-yo-fr', qualityHint: 'BLEU 24.1'),
  AfricanOpusPair(sourceIso: 'es', targetIso: 'yo', repoName: 'opus-mt-es-yo', qualityHint: 'OPUS'),
  AfricanOpusPair(sourceIso: 'yo', targetIso: 'es', repoName: 'opus-mt-yo-es', qualityHint: 'OPUS'),
  AfricanOpusPair(sourceIso: 'fi', targetIso: 'yo', repoName: 'opus-mt-fi-yo', qualityHint: 'OPUS'),
  AfricanOpusPair(sourceIso: 'yo', targetIso: 'fi', repoName: 'opus-mt-yo-fi', qualityHint: 'OPUS'),
  AfricanOpusPair(sourceIso: 'sv', targetIso: 'yo', repoName: 'opus-mt-sv-yo', qualityHint: 'OPUS'),
  AfricanOpusPair(sourceIso: 'yo', targetIso: 'sv', repoName: 'opus-mt-yo-sv', qualityHint: 'OPUS'),

  // Igbo
  AfricanOpusPair(sourceIso: 'en', targetIso: 'ig', repoName: 'opus-mt-en-ig', qualityHint: 'BLEU 39.5'),
  AfricanOpusPair(sourceIso: 'ig', targetIso: 'en', repoName: 'opus-mt-ig-en', qualityHint: 'BLEU 36.7'),
  AfricanOpusPair(sourceIso: 'fr', targetIso: 'ig', repoName: 'opus-mt-fr-ig', qualityHint: 'BLEU 29.0'),
  AfricanOpusPair(sourceIso: 'ig', targetIso: 'fr', repoName: 'opus-mt-ig-fr', qualityHint: 'BLEU 25.6'),
  AfricanOpusPair(sourceIso: 'de', targetIso: 'ig', repoName: 'opus-mt-de-ig', qualityHint: 'OPUS'),
  AfricanOpusPair(sourceIso: 'ig', targetIso: 'de', repoName: 'opus-mt-ig-de', qualityHint: 'OPUS'),
  AfricanOpusPair(sourceIso: 'es', targetIso: 'ig', repoName: 'opus-mt-es-ig', qualityHint: 'OPUS'),
  AfricanOpusPair(sourceIso: 'ig', targetIso: 'es', repoName: 'opus-mt-ig-es', qualityHint: 'OPUS'),
  AfricanOpusPair(sourceIso: 'fi', targetIso: 'ig', repoName: 'opus-mt-fi-ig', qualityHint: 'OPUS'),
  AfricanOpusPair(sourceIso: 'ig', targetIso: 'fi', repoName: 'opus-mt-ig-fi', qualityHint: 'OPUS'),
  AfricanOpusPair(sourceIso: 'sv', targetIso: 'ig', repoName: 'opus-mt-sv-ig', qualityHint: 'OPUS'),
  AfricanOpusPair(sourceIso: 'ig', targetIso: 'sv', repoName: 'opus-mt-ig-sv', qualityHint: 'OPUS'),

  // Swahili / Congo Swahili
  AfricanOpusPair(sourceIso: 'en', targetIso: 'sw', repoName: 'opus-mt-en-sw', qualityHint: 'BLEU 24.2'),
  AfricanOpusPair(sourceIso: 'swc', targetIso: 'en', repoName: 'opus-mt-swc-en', qualityHint: 'BLEU 41.1'),
  AfricanOpusPair(sourceIso: 'fr', targetIso: 'swc', repoName: 'opus-mt-fr-swc', qualityHint: 'BLEU 28.2'),
  AfricanOpusPair(sourceIso: 'swc', targetIso: 'fr', repoName: 'opus-mt-swc-fr', qualityHint: 'BLEU 28.6'),
  AfricanOpusPair(sourceIso: 'fi', targetIso: 'sw', repoName: 'opus-mt-fi-sw', qualityHint: 'OPUS'),
  AfricanOpusPair(sourceIso: 'swc', targetIso: 'es', repoName: 'opus-mt-swc-es', qualityHint: 'OPUS'),
  AfricanOpusPair(sourceIso: 'swc', targetIso: 'fi', repoName: 'opus-mt-swc-fi', qualityHint: 'OPUS'),
  AfricanOpusPair(sourceIso: 'swc', targetIso: 'sv', repoName: 'opus-mt-swc-sv', qualityHint: 'OPUS'),

  // Kinyarwanda
  AfricanOpusPair(sourceIso: 'en', targetIso: 'rw', repoName: 'opus-mt-en-rw', qualityHint: 'BLEU 33.3'),
  AfricanOpusPair(sourceIso: 'rw', targetIso: 'en', repoName: 'opus-mt-rw-en', qualityHint: 'BLEU 37.3'),
  AfricanOpusPair(sourceIso: 'fr', targetIso: 'rw', repoName: 'opus-mt-fr-rw', qualityHint: 'BLEU 25.5'),
  AfricanOpusPair(sourceIso: 'rw', targetIso: 'fr', repoName: 'opus-mt-rw-fr', qualityHint: 'BLEU 26.7'),
  AfricanOpusPair(sourceIso: 'es', targetIso: 'rw', repoName: 'opus-mt-es-rw', qualityHint: 'OPUS'),
  AfricanOpusPair(sourceIso: 'rw', targetIso: 'es', repoName: 'opus-mt-rw-es', qualityHint: 'OPUS'),
  AfricanOpusPair(sourceIso: 'fi', targetIso: 'rw', repoName: 'opus-mt-fi-rw', qualityHint: 'OPUS'),
  AfricanOpusPair(sourceIso: 'sv', targetIso: 'rw', repoName: 'opus-mt-sv-rw', qualityHint: 'OPUS'),
  AfricanOpusPair(sourceIso: 'rw', targetIso: 'sv', repoName: 'opus-mt-rw-sv', qualityHint: 'OPUS'),

  // Rundi (Helsinki rn → Languages.rundi / run)
  AfricanOpusPair(sourceIso: 'en', targetIso: 'rn', repoName: 'opus-mt-en-rn', qualityHint: 'BLEU 10.4'),
  AfricanOpusPair(sourceIso: 'rn', targetIso: 'en', repoName: 'opus-mt-rn-en', qualityHint: 'BLEU 26.7'),
  AfricanOpusPair(sourceIso: 'rn', targetIso: 'fr', repoName: 'opus-mt-rn-fr', qualityHint: 'BLEU 18.2'),
  AfricanOpusPair(sourceIso: 'es', targetIso: 'rn', repoName: 'opus-mt-es-rn', qualityHint: 'OPUS'),
  AfricanOpusPair(sourceIso: 'rn', targetIso: 'es', repoName: 'opus-mt-rn-es', qualityHint: 'OPUS'),
  AfricanOpusPair(sourceIso: 'rn', targetIso: 'de', repoName: 'opus-mt-rn-de', qualityHint: 'OPUS'),
  AfricanOpusPair(sourceIso: 'rn', targetIso: 'ru', repoName: 'opus-mt-rn-ru', qualityHint: 'OPUS'),

  // Ganda
  AfricanOpusPair(sourceIso: 'en', targetIso: 'lg', repoName: 'opus-mt-en-lg', qualityHint: 'BLEU 30.4'),
  AfricanOpusPair(sourceIso: 'lg', targetIso: 'en', repoName: 'opus-mt-lg-en', qualityHint: 'BLEU 32.6'),
  AfricanOpusPair(sourceIso: 'fr', targetIso: 'lg', repoName: 'opus-mt-fr-lg', qualityHint: 'BLEU 21.7'),
  AfricanOpusPair(sourceIso: 'lg', targetIso: 'fr', repoName: 'opus-mt-lg-fr', qualityHint: 'BLEU 23.7'),
  AfricanOpusPair(sourceIso: 'fi', targetIso: 'lg', repoName: 'opus-mt-fi-lg', qualityHint: 'OPUS'),
  AfricanOpusPair(sourceIso: 'lg', targetIso: 'es', repoName: 'opus-mt-lg-es', qualityHint: 'OPUS'),
  AfricanOpusPair(sourceIso: 'lg', targetIso: 'fi', repoName: 'opus-mt-lg-fi', qualityHint: 'OPUS'),
  AfricanOpusPair(sourceIso: 'sv', targetIso: 'lg', repoName: 'opus-mt-sv-lg', qualityHint: 'OPUS'),
  AfricanOpusPair(sourceIso: 'lg', targetIso: 'sv', repoName: 'opus-mt-lg-sv', qualityHint: 'OPUS'),

  // Shona
  AfricanOpusPair(sourceIso: 'en', targetIso: 'sn', repoName: 'opus-mt-en-sn', qualityHint: 'BLEU 38.0'),
  AfricanOpusPair(sourceIso: 'sn', targetIso: 'en', repoName: 'opus-mt-sn-en', qualityHint: 'BLEU 51.8'),
  AfricanOpusPair(sourceIso: 'fr', targetIso: 'sn', repoName: 'opus-mt-fr-sn', qualityHint: 'BLEU 23.4'),
  AfricanOpusPair(sourceIso: 'sn', targetIso: 'fr', repoName: 'opus-mt-sn-fr', qualityHint: 'BLEU 30.8'),
  AfricanOpusPair(sourceIso: 'es', targetIso: 'sn', repoName: 'opus-mt-es-sn', qualityHint: 'OPUS'),
  AfricanOpusPair(sourceIso: 'sn', targetIso: 'es', repoName: 'opus-mt-sn-es', qualityHint: 'OPUS'),
  AfricanOpusPair(sourceIso: 'fi', targetIso: 'sn', repoName: 'opus-mt-fi-sn', qualityHint: 'OPUS'),
  AfricanOpusPair(sourceIso: 'sv', targetIso: 'sn', repoName: 'opus-mt-sv-sn', qualityHint: 'OPUS'),
  AfricanOpusPair(sourceIso: 'sn', targetIso: 'sv', repoName: 'opus-mt-sn-sv', qualityHint: 'OPUS'),

  // Lingala
  AfricanOpusPair(sourceIso: 'en', targetIso: 'ln', repoName: 'opus-mt-en-ln', qualityHint: 'BLEU 36.7'),
  AfricanOpusPair(sourceIso: 'ln', targetIso: 'en', repoName: 'opus-mt-ln-en', qualityHint: 'BLEU 35.9'),
  AfricanOpusPair(sourceIso: 'fr', targetIso: 'ln', repoName: 'opus-mt-fr-ln', qualityHint: 'BLEU 30.5'),
  AfricanOpusPair(sourceIso: 'ln', targetIso: 'fr', repoName: 'opus-mt-ln-fr', qualityHint: 'BLEU 28.4'),
  AfricanOpusPair(sourceIso: 'de', targetIso: 'ln', repoName: 'opus-mt-de-ln', qualityHint: 'OPUS'),
  AfricanOpusPair(sourceIso: 'ln', targetIso: 'de', repoName: 'opus-mt-ln-de', qualityHint: 'OPUS'),
  AfricanOpusPair(sourceIso: 'es', targetIso: 'ln', repoName: 'opus-mt-es-ln', qualityHint: 'OPUS'),
  AfricanOpusPair(sourceIso: 'ln', targetIso: 'es', repoName: 'opus-mt-ln-es', qualityHint: 'OPUS'),
  AfricanOpusPair(sourceIso: 'fi', targetIso: 'ln', repoName: 'opus-mt-fi-ln', qualityHint: 'OPUS'),
  AfricanOpusPair(sourceIso: 'sv', targetIso: 'ln', repoName: 'opus-mt-sv-ln', qualityHint: 'OPUS'),

  // Nyanja / Chewa
  AfricanOpusPair(sourceIso: 'en', targetIso: 'ny', repoName: 'opus-mt-en-ny', qualityHint: 'BLEU 31.4'),
  AfricanOpusPair(sourceIso: 'ny', targetIso: 'en', repoName: 'opus-mt-ny-en', qualityHint: 'BLEU 39.7'),
  AfricanOpusPair(sourceIso: 'fr', targetIso: 'ny', repoName: 'opus-mt-fr-ny', qualityHint: 'BLEU 23.2'),
  AfricanOpusPair(sourceIso: 'de', targetIso: 'ny', repoName: 'opus-mt-de-ny', qualityHint: 'OPUS'),
  AfricanOpusPair(sourceIso: 'ny', targetIso: 'de', repoName: 'opus-mt-ny-de', qualityHint: 'OPUS'),
  AfricanOpusPair(sourceIso: 'es', targetIso: 'ny', repoName: 'opus-mt-es-ny', qualityHint: 'OPUS'),
  AfricanOpusPair(sourceIso: 'ny', targetIso: 'es', repoName: 'opus-mt-ny-es', qualityHint: 'OPUS'),
  AfricanOpusPair(sourceIso: 'fi', targetIso: 'ny', repoName: 'opus-mt-fi-ny', qualityHint: 'OPUS'),
  AfricanOpusPair(sourceIso: 'sv', targetIso: 'ny', repoName: 'opus-mt-sv-ny', qualityHint: 'OPUS'),

  // Twi
  AfricanOpusPair(sourceIso: 'en', targetIso: 'tw', repoName: 'opus-mt-en-tw', qualityHint: 'BLEU 38.2'),
  AfricanOpusPair(sourceIso: 'fr', targetIso: 'tw', repoName: 'opus-mt-fr-tw', qualityHint: 'BLEU 27.9'),
  AfricanOpusPair(sourceIso: 'es', targetIso: 'tw', repoName: 'opus-mt-es-tw', qualityHint: 'OPUS'),
  AfricanOpusPair(sourceIso: 'fi', targetIso: 'tw', repoName: 'opus-mt-fi-tw', qualityHint: 'OPUS'),
  AfricanOpusPair(sourceIso: 'sv', targetIso: 'tw', repoName: 'opus-mt-sv-tw', qualityHint: 'OPUS'),
  AfricanOpusPair(sourceIso: 'tw', targetIso: 'es', repoName: 'opus-mt-tw-es', qualityHint: 'OPUS'),
  AfricanOpusPair(sourceIso: 'tw', targetIso: 'fi', repoName: 'opus-mt-tw-fi', qualityHint: 'OPUS'),
  AfricanOpusPair(sourceIso: 'tw', targetIso: 'fr', repoName: 'opus-mt-tw-fr', qualityHint: 'OPUS'),
  AfricanOpusPair(sourceIso: 'tw', targetIso: 'sv', repoName: 'opus-mt-tw-sv', qualityHint: 'OPUS'),

  // Ewe
  AfricanOpusPair(sourceIso: 'ee', targetIso: 'en', repoName: 'opus-mt-ee-en', qualityHint: 'BLEU 39.3'),
  AfricanOpusPair(sourceIso: 'en', targetIso: 'ee', repoName: 'opus-mt-en-ee', qualityHint: 'BLEU 38.2'),
  AfricanOpusPair(sourceIso: 'ee', targetIso: 'fr', repoName: 'opus-mt-ee-fr', qualityHint: 'BLEU 27.1'),
  AfricanOpusPair(sourceIso: 'fr', targetIso: 'ee', repoName: 'opus-mt-fr-ee', qualityHint: 'BLEU 26.3'),
  AfricanOpusPair(sourceIso: 'de', targetIso: 'ee', repoName: 'opus-mt-de-ee', qualityHint: 'OPUS'),
  AfricanOpusPair(sourceIso: 'ee', targetIso: 'de', repoName: 'opus-mt-ee-de', qualityHint: 'OPUS'),
  AfricanOpusPair(sourceIso: 'es', targetIso: 'ee', repoName: 'opus-mt-es-ee', qualityHint: 'OPUS'),
  AfricanOpusPair(sourceIso: 'ee', targetIso: 'es', repoName: 'opus-mt-ee-es', qualityHint: 'OPUS'),
  AfricanOpusPair(sourceIso: 'fi', targetIso: 'ee', repoName: 'opus-mt-fi-ee', qualityHint: 'OPUS'),
  AfricanOpusPair(sourceIso: 'ee', targetIso: 'fi', repoName: 'opus-mt-ee-fi', qualityHint: 'OPUS'),
  AfricanOpusPair(sourceIso: 'sv', targetIso: 'ee', repoName: 'opus-mt-sv-ee', qualityHint: 'OPUS'),
  AfricanOpusPair(sourceIso: 'ee', targetIso: 'sv', repoName: 'opus-mt-ee-sv', qualityHint: 'OPUS'),

  // Kabyle / Tigrinya / Tiv
  AfricanOpusPair(sourceIso: 'kab', targetIso: 'en', repoName: 'opus-mt-kab-en', qualityHint: 'BLEU 27.5'),
  AfricanOpusPair(sourceIso: 'en', targetIso: 'ti', repoName: 'opus-mt-en-ti', qualityHint: 'BLEU 25.3'),
  AfricanOpusPair(sourceIso: 'ti', targetIso: 'en', repoName: 'opus-mt-ti-en', qualityHint: 'BLEU 30.4'),
  AfricanOpusPair(sourceIso: 'tiv', targetIso: 'en', repoName: 'opus-mt-tiv-en', qualityHint: 'BLEU 31.5'),
  AfricanOpusPair(sourceIso: 'tiv', targetIso: 'fr', repoName: 'opus-mt-tiv-fr', qualityHint: 'BLEU 22.3'),
  AfricanOpusPair(sourceIso: 'tiv', targetIso: 'sv', repoName: 'opus-mt-tiv-sv', qualityHint: 'OPUS'),
];
