import 'package:intl/locale.dart';
import 'package:languages_dart/languages_dart.dart';
import 'package:malinali/services/african_helsinki_models.dart';

/// Wolof orthography on the voice bubbles. The source line is the
/// fine-tune transcript; the italic line under it is the English bridge.
const bool kShowWolofText = true;

/// Optional Whisper.cpp fine-tune for a spoken language.
///
/// Most packs transcribe in the source language. When [emitsEnglish] is true,
/// training targets were English and the pack is used with `translate: true`.
/// [ggmlUrl] is null when the pack cannot be redistributed (gate / non-commercial).
class WhisperSpecialistPack {
  const WhisperSpecialistPack({
    required this.id,
    required this.labelFr,
    required this.iso,
    required this.whisperLang,
    required this.downloadSizeHint,
    required this.hasMarianOutbound,
    required this.upstreamRepo,
    this.ggmlUrl,
    this.unavailableReason,
    this.emitsEnglish = false,
  });

  /// Stable id used for storage filenames and analytics.
  final String id;

  /// French UI title.
  final String labelFr;

  /// ISO code for Marian source switching (e.g. `yo`, `sw`).
  final String iso;

  /// Language code passed to whisper.cpp (`auto`, `sw`, `yo`, …).
  final String whisperLang;

  /// Hugging Face resolve URL for the published ggml `.bin`, or null if unavailable.
  final String? ggmlUrl;

  /// Approximate download size shown in the UI.
  final String downloadSizeHint;

  /// True when the Marian catalogue has at least one pair *from* [iso].
  final bool hasMarianOutbound;

  /// Upstream Hugging Face transformers repo (credit).
  final String upstreamRepo;

  /// French reason when [ggmlUrl] is null.
  final String? unavailableReason;

  /// True when this pack's training targets are English (speech → English).
  final bool emitsEnglish;

  bool get isDownloadable => ggmlUrl != null && ggmlUrl!.isNotEmpty;

  /// Why this pack cannot be selected.
  String? get statusReason => unavailableReason;

  /// English-output packs use the translate task; others only transcribe.
  bool get translate => emitsEnglish;

  String get fileName => '$id.bin';
}

/// Curated specialist packs. First-wave ggml under `malinali-app/*-ggml`.
const List<WhisperSpecialistPack> kWhisperSpecialistPacks = [
  WhisperSpecialistPack(
    id: 'swahili-small',
    labelFr: 'Swahili (small)',
    iso: 'sw',
    whisperLang: 'sw',
    ggmlUrl:
        'https://huggingface.co/malinali-app/whisper-swahili-small-ggml/resolve/main/ggml-model-q8_0.bin',
    downloadSizeHint: 'environ 250 Mo',
    hasMarianOutbound: false,
    upstreamRepo: 'PaschalK/whisper-swahili-small',
  ),
  WhisperSpecialistPack(
    id: 'yoruba-small',
    labelFr: 'Yoruba + code-switching (small)',
    iso: 'yo',
    whisperLang: 'yo',
    ggmlUrl:
        'https://huggingface.co/malinali-app/whisper-small-yoruba-ggml/resolve/main/ggml-model-q8_0.bin',
    downloadSizeHint: 'environ 250 Mo',
    hasMarianOutbound: true,
    upstreamRepo: 'LyngualLabs/whisper-small-yoruba',
  ),
  WhisperSpecialistPack(
    id: 'kinyarwanda-small',
    labelFr: 'Kinyarwanda (small)',
    iso: 'rw',
    // `<|rw|>` is not a Whisper language token; prompt lang confirmed at convert time.
    whisperLang: 'sw',
    ggmlUrl: null,
    downloadSizeHint: 'environ 250 Mo',
    hasMarianOutbound: true,
    upstreamRepo: 'mbazaNLP/Whisper-Small-Kinyarwanda',
    unavailableReason:
        'Dépôt Hugging Face avec accès restreint ; licence à clarifier '
        'avant republication ggml.',
  ),
  WhisperSpecialistPack(
    id: 'wolof-small',
    labelFr: 'Wolof (small)',
    iso: 'wo',
    // No `<|wo|>` token. On the clip dofbi rendered as "Maa bëgg aar gi",
    // prompting English recovered salaamalekum, nanga def, and the name.
    // French prompting did not. New id so the cached dofbi ggml is not reused.
    whisperLang: 'en',
    ggmlUrl:
        'https://huggingface.co/malinali-app/whisper-small-wolof-ggml/resolve/main/ggml-model-q8_0.bin',
    downloadSizeHint: 'environ 250 Mo',
    hasMarianOutbound: true,
    upstreamRepo: 'M9and2M/whisper-small-wolof',
  ),
  WhisperSpecialistPack(
    id: 'dioula-tiny',
    labelFr: 'Dioula (tiny)',
    iso: 'dyu',
    whisperLang: 'auto',
    ggmlUrl: null,
    downloadSizeHint: 'environ 75 Mo',
    hasMarianOutbound: false,
    upstreamRepo: 'Dama12/whisper-tiny-dioula',
    unavailableReason:
        'Licence CC-BY-NC-4.0 et dépôt gated : pas de republication '
        'dans malinali-app.',
  ),
  WhisperSpecialistPack(
    id: 'moore-small',
    labelFr: 'Mòoré (small)',
    iso: 'mos',
    whisperLang: 'auto',
    ggmlUrl: null,
    downloadSizeHint: 'environ 250 Mo',
    hasMarianOutbound: false,
    upstreamRepo: 'Dama12/whisper-small-moore',
    unavailableReason:
        'Licence CC-BY-NC-4.0 et dépôt gated : pas de republication '
        'dans malinali-app.',
  ),
];

WhisperSpecialistPack? whisperSpecialistById(String id) {
  for (final pack in kWhisperSpecialistPacks) {
    if (pack.id == id) return pack;
  }
  return null;
}

/// Resolves a [Language] for Marian source switching after specialist ASR.
Language? languageForWhisperIso(String iso) {
  final code = iso.toLowerCase();
  final african = africanLanguageByIso(code);
  if (african != null) return african;
  try {
    return Languages.defaultLanguages.firstWhere(
      (l) => l.localeIntl.locale.languageCode.toLowerCase() == code,
    );
  } catch (_) {}
  switch (code) {
    case 'dyu':
      return Language(
        LocaleIntl(Locale.fromSubtags(languageCode: 'dyu')),
        'Dioula',
        'Dioula',
      );
    case 'mos':
      return Language(
        LocaleIntl(Locale.fromSubtags(languageCode: 'mos')),
        'Mòoré',
        'Moore',
      );
    default:
      return null;
  }
}
