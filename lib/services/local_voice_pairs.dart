import 'package:malinali/services/supported_languages.dart';
import 'package:malinali/services/voice_preferences.dart';
import 'package:malinali/services/voice_speech_resolver.dart';
import 'package:malinali/services/whisper_specialist_models.dart';

/// A source/target pair whose speech and translation models are on disk.
class LocalVoicePair {
  const LocalVoicePair({
    required this.sourceIso,
    required this.targetIso,
    required this.sourceLabel,
    required this.targetLabel,
  });

  final String sourceIso;
  final String targetIso;
  final String sourceLabel;
  final String targetLabel;
}

/// Pairs the voice chat can run without downloading.
///
/// [prefs] supplies the whisper size and Vosk flag. Each candidate is resolved
/// the same way a live turn would be, then kept only when [modelsReady] is true.
Future<List<LocalVoicePair>> readyVoicePairs({
  required VoicePreferences prefs,
  required Future<bool> Function(VoiceSpeechPlan plan) modelsReady,
  VoiceSpeechResolver resolver = const VoiceSpeechResolver(),
}) async {
  final seenSources = <String>[];
  for (final pack in voiceSpokenLanguagePacks()) {
    final iso = pack.iso.toLowerCase();
    if (!seenSources.contains(iso)) seenSources.add(iso);
  }

  final out = <LocalVoicePair>[];
  final seen = <String>{};
  for (final sourceIso in seenSources) {
    for (final target in getAvailableTargetLanguages(sourceIso: sourceIso)) {
      final targetIso = target.iso.toLowerCase();
      if (targetIso == sourceIso) continue;
      final key = '$sourceIso>$targetIso';
      if (!seen.add(key)) continue;
      final plan = resolver.resolve(
        prefs.copyWith(sourceIso: sourceIso, targetIso: targetIso),
      );
      if (!await modelsReady(plan)) continue;
      out.add(
        LocalVoicePair(
          sourceIso: sourceIso,
          targetIso: targetIso,
          sourceLabel: _label(sourceIso),
          targetLabel: target.name.isEmpty ? target.nameEn : target.name,
        ),
      );
    }
  }
  return out;
}

/// All source/target pairs supported by the voice resolver, regardless of local presence.
Future<List<LocalVoicePair>> supportedVoicePairs({
  required VoicePreferences prefs,
  VoiceSpeechResolver resolver = const VoiceSpeechResolver(),
}) async {
  final seenSources = <String>[];
  // 1. Generic sources
  for (final pack in voiceSpokenLanguagePacks()) {
    final iso = pack.iso.toLowerCase();
    if (!seenSources.contains(iso)) seenSources.add(iso);
  }
  // 2. Specialist packs that are downloadable (e.g. Wolof, Swahili, Yoruba)
  for (final pack in kWhisperSpecialistPacks) {
    if (!pack.isDownloadable) continue;
    final iso = pack.iso.toLowerCase();
    if (!seenSources.contains(iso)) seenSources.add(iso);
  }

  final out = <LocalVoicePair>[];
  final seen = <String>{};
  for (final sourceIso in seenSources) {
    final targets = getAvailableTargetLanguages(sourceIso: sourceIso);
    for (final target in targets) {
      final targetIso = target.iso.toLowerCase();
      if (targetIso == sourceIso) continue;
      final key = '$sourceIso>$targetIso';
      if (!seen.add(key)) continue;

      out.add(
        LocalVoicePair(
          sourceIso: sourceIso,
          targetIso: targetIso,
          sourceLabel: _label(sourceIso),
          targetLabel: target.name.isEmpty ? target.nameEn : target.name,
        ),
      );
    }
  }
  return out;
}

String _label(String iso) {
  final lang = voiceLanguageByIso(iso);
  if (lang == null) return iso;
  return lang.name.isEmpty ? lang.nameEn : lang.name;
}
