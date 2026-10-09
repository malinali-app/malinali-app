import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:malinali/services/whisper_native.dart';
import 'package:record/record.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

import 'package:malinali/services/whisper_specialist_models.dart';

/// On-device Whisper via whisper.cpp.
///
/// Default pack: multilingual tiny/small with `translate: true` (English out).
/// Optional [WhisperSpecialistPack]: language fine-tune (transcribe or English out).
class WhisperSpeechService {
  WhisperSpeechService({
    WhisperController? controller,
    AudioRecorder? audioRecorder,
    AudioRecorder Function()? recorderFactory,
    Dio? dio,
    WhisperModel genericModel = WhisperModel.tiny,
  })  : _controller = controller ?? WhisperController(),
        _audioRecorder = audioRecorder,
        _recorderFactory = recorderFactory,
        _dio = dio ?? Dio(),
        _genericModel = genericModel;

  /// Legacy alias for the compact pack.
  static const WhisperModel model = WhisperModel.tiny;

  /// Hugging Face ggml tiny, fp16, about 75 MB.
  static const String downloadSizeHint = 'environ 75 Mo';

  static const String downloadSizeHintSmall = 'environ 250 Mo';

  final WhisperController _controller;
  final Dio _dio;
  AudioRecorder? _audioRecorder;
  final AudioRecorder Function()? _recorderFactory;
  WhisperModel _genericModel;

  MalinaliWhisperLiveSession? _session;
  StreamSubscription<String>? _partialSub;
  StreamSubscription<Uint8List>? _audioSub;

  WhisperSpecialistPack? _specialist;
  bool _ready = false;
  bool _listening = false;

  void Function(String text)? onResult;
  void Function(String partial)? onPartialResult;
  void Function()? onError;

  bool get isReady => _ready;
  bool get isListening => _listening;

  /// Null means default generic multilingual (English translate).
  WhisperSpecialistPack? get activeSpecialist => _specialist;

  bool get isDefaultTranslatePack => _specialist == null;

  WhisperModel get genericModel => _genericModel;

  /// Analytics / UI label for the active pack.
  String get engineId => _specialist == null
      ? 'whisper-${_genericModel.modelName}'
      : 'whisper-${_specialist!.id}';

  AudioRecorder _recorder() {
    return _audioRecorder ??=
        (_recorderFactory != null ? _recorderFactory() : AudioRecorder());
  }

  Future<Directory> specialistStorageDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    final String baseDir = Platform.isWindows
        ? p.join(docs.path, 'Malinali_do_not_delete', 'whisper_specialists')
        : p.join(docs.path, 'whisper_specialists');
    final dir = Directory(baseDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  Future<String> specialistFilePath(WhisperSpecialistPack pack) async {
    final dir = await specialistStorageDirectory();
    return p.join(dir.path, pack.fileName);
  }

  /// True when the active pack's ggml file is already on disk.
  Future<bool> isModelPresent() async {
    try {
      final path = await _activeModelPath();
      final present = File(path).existsSync();
      _ready = present;
      return present;
    } catch (_) {
      _ready = false;
      return false;
    }
  }

  /// True when the active generic multilingual model is on disk.
  Future<bool> isTinyDownloaded() async {
    return isGenericDownloaded(_genericModel);
  }

  Future<bool> isGenericDownloaded(WhisperModel model) async {
    try {
      final path = await _controller.getPath(model);
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  /// Switch the generic multilingual size (tiny / small). Clears specialist use.
  Future<void> setGenericModel(WhisperModel model) async {
    if (_genericModel == model && _specialist == null && _ready) return;
    if (_listening || _session != null) {
      await stopListening();
    }
    await _releaseParkedModel();
    _genericModel = model;
    if (_specialist == null) {
      _ready = await isModelPresent();
    }
  }

  Future<bool> isSpecialistDownloaded(WhisperSpecialistPack pack) async {
    if (!pack.isDownloadable) return false;
    try {
      final path = await specialistFilePath(pack);
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  /// Switch pack. Releases a parked native model when the path changes.
  Future<void> setActivePack(WhisperSpecialistPack? pack) async {
    if (pack != null && !pack.isDownloadable) {
      throw StateError(
        pack.statusReason ?? 'Ce modèle Whisper n\'est pas disponible.',
      );
    }
    final previous = _specialist;
    if (previous?.id == pack?.id && _ready) {
      return;
    }
    if (_listening || _session != null) {
      await stopListening();
    }
    await _releaseParkedModel();
    _specialist = pack;
    _ready = await isModelPresent();
  }

  /// Download multilingual tiny if it is not already stored.
  Future<String> ensureTinyModel() async {
    return ensureGenericModel(WhisperModel.tiny);
  }

  /// Download a generic multilingual ggml if it is not already stored.
  Future<String> ensureGenericModel([WhisperModel? model]) async {
    final target = model ?? _genericModel;
    final path = await _controller.downloadModel(target);
    if (_specialist == null && target == _genericModel) {
      _ready = true;
    }
    return path;
  }

  /// Download the active pack (generic or specialist) if it is not already stored.
  Future<String> ensureModel() async {
    final specialist = _specialist;
    if (specialist == null) {
      return ensureGenericModel();
    }
    return downloadSpecialist(specialist);
  }

  /// Download a specialist ggml with Dio into app storage.
  Future<String> downloadSpecialist(
    WhisperSpecialistPack pack, {
    void Function(int received, int total)? onProgress,
  }) async {
    if (!pack.isDownloadable) {
      throw StateError(
        pack.statusReason ?? 'Ce modèle Whisper n\'est pas disponible.',
      );
    }
    final path = await specialistFilePath(pack);
    final file = File(path);
    if (file.existsSync() && await file.length() > 0) {
      if (_specialist?.id == pack.id) {
        _ready = true;
      }
      return path;
    }

    final tmp = File('$path.partial');
    try {
      await _dio.download(
        pack.ggmlUrl!,
        tmp.path,
        onReceiveProgress: onProgress,
      );
      if (file.existsSync()) {
        try {
          file.deleteSync();
        } catch (_) {}
      }
      await tmp.rename(path);
      if (_specialist?.id == pack.id) {
        _ready = true;
      }
      return path;
    } catch (e) {
      if (tmp.existsSync()) {
        try {
          tmp.deleteSync();
        } catch (_) {}
      }
      rethrow;
    }
  }

  Future<String> _activeModelPath() async {
    final specialist = _specialist;
    if (specialist == null) {
      return _controller.getPath(_genericModel);
    }
    return specialistFilePath(specialist);
  }

  Future<void> _releaseParkedModel() async {
    try {
      await whisperReleaseModel();
    } catch (_) {}
  }

  /// Start the microphone.
  ///
  /// Default pack: partials and final line are English.
  /// Specialist pack: transcript in the fine-tuned language.
  Future<void> startListening() async {
    if (_listening) return;
    if (!_ready) {
      await ensureModel();
    }

    final hasPermission = await _recorder().hasPermission();
    if (!hasPermission) {
      throw Exception('Microphone permission not granted');
    }

    final modelPath = (await _activeModelPath()).replaceAll('/', p.separator).replaceAll('\\', p.separator);
    final specialist = _specialist;
    
    if (!File(modelPath).existsSync()) {
      throw Exception('Model file not found: $modelPath');
    }

    final session = await startMalinaliWhisperLiveSession(
      modelPath: modelPath,
      lang: _languageFor(specialist),
      translate: _translateFor(specialist),
      suppressNonSpeechTokens: true,
      keepModelLoaded: true,
    );
    _session = session;
    _partialSub = session.partials.listen(
      (text) {
        final partial = text.trim();
        if (partial.isNotEmpty) onPartialResult?.call(partial);
      },
      onError: (_) => onError?.call(),
    );

    final stream = await _recorder().startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );

    _listening = true;
    _audioSub = stream.listen(
      (chunk) {
        if (!_listening) return;
        session.feed(chunk);
      },
      onError: (_) {
        _listening = false;
        onError?.call();
      },
    );
  }

  /// Stop the microphone and return the transcript.
  Future<String> stopListening() async {
    if (!_listening && _session == null) return '';
    _listening = false;

    try {
      await _audioSub?.cancel();
      _audioSub = null;
      try {
        await _audioRecorder?.stop();
      } catch (_) {}

      final text = (await _session?.stop())?.trim() ?? '';
      await _partialSub?.cancel();
      _partialSub = null;
      _session = null;
      if (text.isNotEmpty) onResult?.call(text);
      return text;
    } catch (_) {
      _session = null;
      onError?.call();
      return '';
    }
  }

  /// Transcribe a 16 kHz mono WAV (or any file whisper.cpp can open).
  ///
  /// [language] and [translate] override the active pack. Callers that know
  /// the spoken language must pass them: a null pack used to send `auto`
  /// plus translate-to-English, and Whisper then labeled Wolof as English.
  Future<String> transcribeWav(
    String audioPath, {
    void Function(int percent)? onProgress,
    String? language,
    bool? translate,
  }) async {
    final modelPath = await ensureModel();
    final specialist = _specialist;
    final lang = _languageFor(specialist, override: language);
    final toEnglish = _translateFor(specialist, override: translate);
    onProgress?.call(0);
    final response = await whisperTranscribeWav(
      wavPath: audioPath,
      modelPath: modelPath,
      language: lang,
      translate: toEnglish,
    );
    onProgress?.call(100);
    final text = response['text'];
    if (text is! String) {
      throw Exception(response['message'] ?? 'Whisper transcription failed');
    }
    return text.trim();
  }

  /// whisper.cpp language token. An explicit [override] wins, including when
  /// the active pack is still null.
  String _languageFor(WhisperSpecialistPack? specialist, {String? override}) {
    final requested = (override ?? specialist?.whisperLang ?? 'auto').trim();
    if (requested.isEmpty) return 'auto';
    return requested.toLowerCase();
  }

  bool _translateFor(WhisperSpecialistPack? specialist, {bool? override}) {
    return override ?? specialist?.translate ?? true;
  }

  Future<void> dispose() async {
    if (_listening || _session != null) {
      await stopListening();
    }
    await _releaseParkedModel();
    try {
      await _audioRecorder?.dispose();
    } catch (_) {}
    _audioRecorder = null;
  }
}
