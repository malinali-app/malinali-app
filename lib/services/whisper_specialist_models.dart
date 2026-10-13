import 'package:intl/locale.dart';
import 'package:languages_dart/languages_dart.dart';
import 'package:malinali/services/african_helsinki_models.dart';

/// Wolof orthography on the voice bubbles. The source line is the
/// fine-tune transcript; the italic line under it is the English bridge.
const bool kShowWolofText = true;

/// Generic multilingual Whisper size (sherpa-onnx int8 graphs).
enum WhisperModel {
  tiny('tiny', 'environ 103 Mo'),
  small('small', 'environ 375 Mo');

  const WhisperModel(this.modelName, this.sizeHintFr);

  final String modelName;
  final String sizeHintFr;
}

/// Hugging Face sherpa-onnx pack (encoder + decoder + tokens).
class WhisperOnnxRepo {
  const WhisperOnnxRepo({
    required this.repoId,
    this.encoderFile = 'encoder.int8.onnx',
    this.decoderFile = 'decoder.int8.onnx',
    this.tokensFile = 'tokens.txt',
  });

  final String repoId;
  final String encoderFile;
  final String decoderFile;
  final String tokensFile;

  String get baseUrl => 'https://huggingface.co/$repoId/resolve/main';

  List<String> get files => [encoderFile, decoderFile, tokensFile];

  String urlFor(String fileName) => '$baseUrl/$fileName';
}

const WhisperOnnxRepo kGenericTinyOnnx = WhisperOnnxRepo(
  repoId: 'malinali-app/whisper-tiny-onnx',
);

const WhisperOnnxRepo kGenericSmallOnnx = WhisperOnnxRepo(
  repoId: 'malinali-app/whisper-small-onnx',
);

/// Optional Whisper fine-tune for a spoken language (sherpa-onnx).
///
/// Most packs transcribe in the source language. When [emitsEnglish] is true,
/// training targets were English and the pack is used with `task=translate`.
/// [onnxRepo] is null when the pack cannot be redistributed.
class WhisperSpecialistPack {
  const WhisperSpecialistPack({
    required this.id,
    required this.labelFr,
    required this.iso,
    required this.whisperLang,
    required this.downloadSizeHint,
    required this.hasMarianOutbound,
    required this.upstreamRepo,
    this.onnxRepo,
    this.unavailableReason,
    this.emitsEnglish = false,
    this.builtin = false,
  });

  /// Stable id used for storage filenames and analytics.
  final String id;

  /// French UI title.
  final String labelFr;

  /// ISO code for Marian source switching (e.g. `yo`, `sw`).
  final String iso;

  /// Language code passed to Whisper (`auto`, `sw`, `yo`, …).
  final String whisperLang;

  /// Hugging Face sherpa-onnx pack, or null if unavailable.
  final WhisperOnnxRepo? onnxRepo;

  /// Approximate download size shown in the UI.
  final String downloadSizeHint;

  /// True when the Marian catalogue has at least one pair *from* [iso].
  final bool hasMarianOutbound;

  /// Upstream Hugging Face transformers repo (credit).
  final String upstreamRepo;

  /// French reason when [onnxRepo] is null.
  final String? unavailableReason;

  /// True when this pack's training targets are English (speech → English).
  final bool emitsEnglish;

  /// True for English/French entries that use the generic multilingual pack.
  final bool builtin;

  bool get isDownloadable =>
      builtin || (onnxRepo != null && onnxRepo!.repoId.isNotEmpty);

  /// Why this pack cannot be selected.
  String? get statusReason => unavailableReason;

  /// English-output packs use the translate task; others only transcribe.
  bool get translate => emitsEnglish;

  String get dirName => id;
}

/// Curated specialist packs. sherpa-onnx int8 under `malinali-app/*-onnx`.
const List<WhisperSpecialistPack> kWhisperSpecialistPacks = [
  WhisperSpecialistPack(
    id: 'swahili-small',
    labelFr: 'Swahili (small)',
    iso: 'sw',
    whisperLang: 'sw',
    onnxRepo: WhisperOnnxRepo(repoId: 'malinali-app/whisper-swahili-small-onnx'),
    downloadSizeHint: 'environ 180 Mo',
    hasMarianOutbound: false,
    upstreamRepo: 'PaschalK/whisper-swahili-small',
  ),
  WhisperSpecialistPack(
    id: 'yoruba-small',
    labelFr: 'Yoruba + code-switching (small)',
    iso: 'yo',
    whisperLang: 'yo',
    onnxRepo: WhisperOnnxRepo(repoId: 'malinali-app/whisper-small-yoruba-onnx'),
    downloadSizeHint: 'environ 180 Mo',
    hasMarianOutbound: true,
    upstreamRepo: 'LyngualLabs/whisper-small-yoruba',
  ),
  WhisperSpecialistPack(
    id: 'kinyarwanda-small',
    labelFr: 'Kinyarwanda (small)',
    iso: 'rw',
    whisperLang: 'sw',
    onnxRepo: null,
    downloadSizeHint: 'environ 180 Mo',
    hasMarianOutbound: true,
    upstreamRepo: 'mbazaNLP/Whisper-Small-Kinyarwanda',
    unavailableReason:
        'Dépôt Hugging Face avec accès restreint ; licence à clarifier '
        'avant republication ONNX.',
  ),
  WhisperSpecialistPack(
    id: 'wolof-small',
    labelFr: 'Wolof (small)',
    iso: 'wo',
    whisperLang: 'en',
    onnxRepo: WhisperOnnxRepo(repoId: 'malinali-app/whisper-small-wolof-onnx'),
    downloadSizeHint: 'environ 180 Mo',
    hasMarianOutbound: true,
    upstreamRepo: 'M9and2M/whisper-small-wolof',
  ),
  WhisperSpecialistPack(
    id: 'dioula-tiny',
    labelFr: 'Dioula (tiny)',
    iso: 'dyu',
    whisperLang: 'auto',
    onnxRepo: null,
    downloadSizeHint: 'environ 50 Mo',
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
    onnxRepo: null,
    downloadSizeHint: 'environ 180 Mo',
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

WhisperOnnxRepo genericOnnxRepo(WhisperModel model) {
  return model == WhisperModel.small ? kGenericSmallOnnx : kGenericTinyOnnx;
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
