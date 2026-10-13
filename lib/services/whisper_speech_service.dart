import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:malinali/services/whisper_native.dart';
import 'package:record/record.dart';

import 'package:malinali/services/whisper_specialist_models.dart';

/// On-device Whisper via sherpa-onnx.
///
/// Default pack: multilingual tiny/small with `translate: true` (English out).
/// Optional [WhisperSpecialistPack]: language fine-tune (transcribe or English out).
class WhisperSpeechService {
  WhisperSpeechService({
    AudioRecorder? audioRecorder,
    AudioRecorder Function()? recorderFactory,
    Dio? dio,
    WhisperModel genericModel = WhisperModel.tiny,
  })  : _audioRecorder = audioRecorder,
        _recorderFactory = recorderFactory,
        _dio = dio ?? Dio(),
        _genericModel = genericModel;

  /// Legacy alias for the compact pack.
  static const WhisperModel model = WhisperModel.tiny;

  static const String downloadSizeHint = 'environ 103 Mo';

  static const String downloadSizeHintSmall = 'environ 375 Mo';

  static const List<String> kOnnxFiles = [
    'encoder.int8.onnx',
    'decoder.int8.onnx',
    'tokens.txt',
  ];

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

  Future<Directory> _rootStorage() async {
    final docs = await getApplicationDocumentsDirectory();
    final String baseDir = Platform.isWindows
        ? p.join(docs.path, 'Malinali_do_not_delete', 'whisper_onnx')
        : p.join(docs.path, 'whisper_onnx');
    final dir = Directory(baseDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  Future<Directory> specialistStorageDirectory() async {
    final root = await _rootStorage();
    return Directory(p.join(root.path, 'specialists'));
  }

  Future<String> specialistDirPath(WhisperSpecialistPack pack) async {
    final dir = await specialistStorageDirectory();
    return p.join(dir.path, pack.dirName);
  }

  /// Kept for tests that previously checked a single ggml file.
  Future<String> specialistFilePath(WhisperSpecialistPack pack) async {
    return p.join(await specialistDirPath(pack), 'encoder.int8.onnx');
  }

  Future<String> genericDirPath(WhisperModel model) async {
    final root = await _rootStorage();
    return p.join(root.path, 'generic', model.modelName);
  }

  bool _dirComplete(String dirPath) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return false;
    for (final name in kOnnxFiles) {
      final f = File(p.join(dirPath, name));
      if (!f.existsSync() || f.lengthSync() <= 0) return false;
    }
    return true;
  }

  WhisperOnnxPaths _pathsIn(String dirPath) {
    return WhisperOnnxPaths(
      encoder: p.join(dirPath, 'encoder.int8.onnx'),
      decoder: p.join(dirPath, 'decoder.int8.onnx'),
      tokens: p.join(dirPath, 'tokens.txt'),
    );
  }

  /// True when the active pack's onnx files are already on disk.
  Future<bool> isModelPresent() async {
    try {
      final dir = await _activeModelDir();
      final present = _dirComplete(dir);
      _ready = present;
      return present;
    } catch (_) {
      _ready = false;
      return false;
    }
  }

  Future<bool> isTinyDownloaded() async {
    return isGenericDownloaded(WhisperModel.tiny);
  }

  Future<bool> isGenericDownloaded(WhisperModel model) async {
    try {
      return _dirComplete(await genericDirPath(model));
    } catch (_) {
      return false;
    }
  }

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
    if (!pack.isDownloadable || pack.onnxRepo == null) return false;
    try {
      return _dirComplete(await specialistDirPath(pack));
    } catch (_) {
      return false;
    }
  }

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

  Future<String> ensureTinyModel({
    void Function(int received, int total)? onProgress,
  }) async {
    return ensureGenericModel(WhisperModel.tiny, onProgress);
  }

  Future<String> ensureGenericModel([
    WhisperModel? model,
    void Function(int received, int total)? onProgress,
  ]) async {
    final target = model ?? _genericModel;
    final dir = await genericDirPath(target);
    await _downloadRepo(genericOnnxRepo(target), dir, onProgress: onProgress);
    if (_specialist == null && target == _genericModel) {
      _ready = true;
    }
    return dir;
  }

  Future<String> ensureModel() async {
    final specialist = _specialist;
    if (specialist == null) {
      return ensureGenericModel();
    }
    return downloadSpecialist(specialist);
  }

  Future<String> downloadSpecialist(
    WhisperSpecialistPack pack, {
    void Function(int received, int total)? onProgress,
  }) async {
    if (!pack.isDownloadable || pack.onnxRepo == null) {
      throw StateError(
        pack.statusReason ?? 'Ce modèle Whisper n\'est pas disponible.',
      );
    }
    final dir = await specialistDirPath(pack);
    await _downloadRepo(pack.onnxRepo!, dir, onProgress: onProgress);
    if (_specialist?.id == pack.id) {
      _ready = true;
    }
    return dir;
  }

  Future<void> _downloadRepo(
    WhisperOnnxRepo repo,
    String dirPath, {
    void Function(int received, int total)? onProgress,
  }) async {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    if (_dirComplete(dirPath)) return;

    var done = 0;
    final files = repo.files;
    for (final name in files) {
      final dest = File(p.join(dirPath, name));
      if (dest.existsSync() && dest.lengthSync() > 0) {
        done++;
        onProgress?.call(done * 1000, files.length * 1000);
        continue;
      }
      final tmp = File('${dest.path}.partial');
      try {
        await _dio.download(
          repo.urlFor(name),
          tmp.path,
          onReceiveProgress: onProgress == null
              ? null
              : (recv, total) {
                  final int fileProgress = (total > 0) ? (recv * 1000 ~/ total) : 0;
                  onProgress(done * 1000 + fileProgress, files.length * 1000);
                },
        );
        if (dest.existsSync()) {
          try {
            dest.deleteSync();
          } catch (_) {}
        }
        await tmp.rename(dest.path);
        done++;
        onProgress?.call(done * 1000, files.length * 1000);
      } catch (_) {
        if (tmp.existsSync()) {
          try {
            tmp.deleteSync();
          } catch (_) {}
        }
        rethrow;
      }
    }
  }

  Future<String> _activeModelDir() async {
    final specialist = _specialist;
    if (specialist == null) {
      return genericDirPath(_genericModel);
    }
    return specialistDirPath(specialist);
  }

  Future<void> releaseParkedModel() => _releaseParkedModel();

  Future<void> _releaseParkedModel() async {
    try {
      await whisperReleaseModel();
    } catch (_) {}
  }

  Future<void> startListening() async {
    if (_listening) return;
    if (!_ready) {
      await ensureModel();
    }

    final hasPermission = await _recorder().hasPermission();
    if (!hasPermission) {
      throw Exception('Microphone permission not granted');
    }

    final dir = await _activeModelDir();
    if (!_dirComplete(dir)) {
      throw Exception('Model files not found in $dir');
    }

    final specialist = _specialist;
    final session = await startMalinaliWhisperLiveSession(
      model: _pathsIn(dir),
      lang: _languageFor(specialist),
      translate: _translateFor(specialist),
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

  Future<String> transcribeWav(
    String audioPath, {
    void Function(int percent)? onProgress,
    String? language,
    bool? translate,
  }) async {
    final dir = await ensureModel();
    final specialist = _specialist;
    final lang = _languageFor(specialist, override: language);
    final toEnglish = _translateFor(specialist, override: translate);
    onProgress?.call(0);
    final response = await whisperTranscribeWav(
      wavPath: audioPath,
      model: _pathsIn(dir),
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
