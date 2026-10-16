import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:malinali/services/wav_pcm_info.dart';
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
  }) : _audioRecorder = audioRecorder,
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
    'joiner.int8.onnx',
  ];

  final Dio _dio;
  AudioRecorder? _audioRecorder;
  final AudioRecorder Function()? _recorderFactory;
  WhisperModel _genericModel;

  SherpaLiveSession? _session;
  StreamSubscription<String>? _partialSub;
  StreamSubscription<Uint8List>? _audioSub;
  IOSink? _wavSink;
  final List<Uint8List> _pendingPcm = [];
  String _latestPartial = '';
  int _epoch = 0;

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
  String get engineId =>
      _specialist == null
          ? 'whisper-${_genericModel.modelName}'
          : 'sherpa-${_specialist!.id}';

  AudioRecorder _recorder() {
    return _audioRecorder ??=
        (_recorderFactory != null ? _recorderFactory() : AudioRecorder());
  }

  Future<Directory> _rootStorage() async {
    final docs = await getApplicationDocumentsDirectory();
    final String baseDir =
        Platform.isWindows
            ? p.join(docs.path, 'Malinali_do_not_delete', 'sherpa_onnx')
            : p.join(docs.path, 'sherpa_onnx');
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

  bool _dirComplete(String dirPath, {WhisperOnnxRepo? repo}) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return false;
    final files = repo?.files ?? kOnnxFiles.sublist(0, 3);
    for (final name in files) {
      final f = File(p.join(dirPath, name));
      if (!f.existsSync() || f.lengthSync() <= 0) return false;
    }
    return true;
  }

  WhisperOnnxPaths _pathsIn(String dirPath, {WhisperOnnxRepo? repo}) {
    return WhisperOnnxPaths(
      encoder: p.join(dirPath, repo?.encoderFile ?? 'encoder.int8.onnx'),
      decoder: p.join(dirPath, repo?.decoderFile ?? 'decoder.int8.onnx'),
      tokens: p.join(dirPath, repo?.tokensFile ?? 'tokens.txt'),
      joiner:
          repo?.joinerFile != null ? p.join(dirPath, repo!.joinerFile!) : null,
      modelType: repo?.modelType ?? 'whisper',
      sherpaModelType: repo?.sherpaModelType ?? '',
    );
  }

  /// True when the active pack's onnx files are already on disk.
  Future<bool> isModelPresent() async {
    try {
      final dir = await _activeModelDir();
      final present = _dirComplete(dir, repo: _specialist?.onnxRepo);
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
      return _dirComplete(await specialistDirPath(pack), repo: pack.onnxRepo);
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
    if (_dirComplete(dirPath, repo: repo)) return;

    // A previous pack in this folder (same id, different filenames) must not
    // keep its tokens.txt. Both English Zipformers use that name.
    final expected = repo.files.toSet();
    final hasStale = dir.listSync().whereType<File>().any((f) {
      final name = p.basename(f.path);
      return !name.endsWith('.partial') && !expected.contains(name);
    });
    if (hasStale) {
      for (final f in dir.listSync().whereType<File>()) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    }

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
          onReceiveProgress:
              onProgress == null
                  ? null
                  : (recv, total) {
                    final int fileProgress =
                        (total > 0) ? (recv * 1000 ~/ total) : 0;
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

  /// Open a Whisper or Sherpa session for PCM that is not the microphone.
  Future<SherpaLiveSession> openPcmSession({
    String? language,
    bool? translate,
  }) async {
    if (!_ready) {
      await ensureModel();
    }
    final dir = await _activeModelDir();
    final specialist = _specialist;
    if (!_dirComplete(dir, repo: specialist?.onnxRepo)) {
      throw Exception('Model files not found in $dir');
    }
    return startSherpaLiveSession(
      model: _pathsIn(dir, repo: specialist?.onnxRepo),
      lang: _languageFor(specialist, override: language),
      translate: _translateFor(specialist, override: translate),
    );
  }

  Future<void> startListening({
    String? wavPath,
    String? language,
    bool? translate,
  }) async {
    if (_listening || _session != null || _wavSink != null) {
      await stopListening();
    }
    final epoch = ++_epoch;

    if (wavPath != null) {
      _wavSink = await openPlaceholderWav(wavPath);
    }
    if (epoch != _epoch) {
      await _closeWav();
      return;
    }

    final hasPermission = await _recorder().hasPermission();
    if (!hasPermission) {
      await _closeWav();
      throw Exception('Microphone permission not granted');
    }

    final stream = await _recorder().startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );
    if (epoch != _epoch) {
      await _recorder().stop();
      await _closeWav();
      return;
    }

    _listening = true;
    _pendingPcm.clear();
    _latestPartial = '';
    _audioSub = stream.listen(
      (chunk) {
        if (!_listening || epoch != _epoch) return;
        final copy = Uint8List.fromList(chunk);
        _wavSink?.add(copy);
        final session = _session;
        if (session == null) {
          _pendingPcm.add(copy);
        } else {
          session.feed(copy);
        }
      },
      onError: (_) {
        _listening = false;
        onError?.call();
      },
    );

    try {
      if (!_ready) {
        await ensureModel();
      }
      final dir = await _activeModelDir();
      final specialist = _specialist;
      if (!_dirComplete(dir, repo: specialist?.onnxRepo)) {
        throw Exception('Model files not found in $dir');
      }
      final session = await startSherpaLiveSession(
        model: _pathsIn(dir, repo: specialist?.onnxRepo),
        lang: _languageFor(specialist, override: language),
        translate: _translateFor(specialist, override: translate),
      );
      if (epoch != _epoch) {
        session.setSink(null);
        await session.dispose();
        return;
      }
      session.setSink(null);
      _session = session;
      final backlog = List<Uint8List>.of(_pendingPcm);
      _pendingPcm.clear();
      for (final chunk in backlog) {
        session.feed(chunk);
      }
      _partialSub = session.partials.listen((text) {
        final partial = text.trim();
        if (partial.isEmpty) return;
        _latestPartial = partial;
        onPartialResult?.call(partial);
      }, onError: (_) => onError?.call());
    } catch (e) {
      _listening = false;
      await _audioSub?.cancel();
      _audioSub = null;
      try {
        await _audioRecorder?.stop();
      } catch (_) {}
      await _closeWav();
      rethrow;
    }
  }

  Future<String> stopListening() async {
    if (!_listening && _session == null && _wavSink == null) return '';
    _epoch++;
    _listening = false;

    try {
      await _audioSub?.cancel();
      _audioSub = null;
      try {
        await _audioRecorder?.stop();
      } catch (_) {}
      await _closeWav();

      final session = _session;
      _session = null;
      final text = preferSpokenTranscript(
        (await session?.stop()) ?? '',
        _latestPartial,
      );
      await _partialSub?.cancel();
      _partialSub = null;
      if (text.isNotEmpty) onResult?.call(text);
      return text;
    } catch (_) {
      await _partialSub?.cancel();
      _partialSub = null;
      _session = null;
      await _closeWav();
      onError?.call();
      rethrow;
    }
  }

  Future<void> _closeWav() async {
    final sink = _wavSink;
    _wavSink = null;
    _pendingPcm.clear();
    if (sink == null) return;
    try {
      await sink.flush();
      await sink.close();
    } catch (_) {}
  }

  Future<void> fixWavHeader(String path) => repairWavHeader(path);

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
    final response = await sherpaTranscribeWav(
      wavPath: audioPath,
      model: _pathsIn(dir, repo: specialist?.onnxRepo),
      language: lang,
      translate: toEnglish,
    );
    onProgress?.call(100);
    final text = response['text'];
    if (text is! String) {
      throw Exception(response['message'] ?? 'Sherpa transcription failed');
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

void writeWavHeader(IOSink sink, int dataLength) {
  const int sampleRate = 16000;
  const int channels = 1;
  const int bitsPerSample = 16;
  final int byteRate = sampleRate * channels * bitsPerSample ~/ 8;
  final int blockAlign = channels * bitsPerSample ~/ 8;

  final header = ByteData(44);
  header.setUint8(0, 0x52); // R
  header.setUint8(1, 0x49); // I
  header.setUint8(2, 0x46); // F
  header.setUint8(3, 0x46); // F
  header.setUint32(4, 36 + dataLength, Endian.little);
  header.setUint8(8, 0x57); // W
  header.setUint8(9, 0x41); // A
  header.setUint8(10, 0x56); // V
  header.setUint8(11, 0x45); // E
  header.setUint8(12, 0x66); // f
  header.setUint8(13, 0x6d); // m
  header.setUint8(14, 0x74); // t
  header.setUint8(15, 0x20); // (space)
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little); // PCM
  header.setUint16(22, channels, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, byteRate, Endian.little);
  header.setUint16(32, blockAlign, Endian.little);
  header.setUint16(34, bitsPerSample, Endian.little);
  header.setUint8(36, 0x64); // d
  header.setUint8(37, 0x61); // a
  header.setUint8(38, 0x74); // t
  header.setUint8(39, 0x61); // a
  header.setUint32(40, dataLength, Endian.little);

  sink.add(header.buffer.asUint8List());
}

/// Creates [path] and flushes a 44-byte WAV header so the file exists
/// before the recognizer finishes loading.
Future<IOSink> openPlaceholderWav(String path) async {
  final file = File(path);
  if (file.existsSync()) file.deleteSync();
  final parent = file.parent;
  if (!parent.existsSync()) parent.createSync(recursive: true);
  final sink = file.openWrite();
  writeWavHeader(sink, 0);
  await sink.flush();
  return sink;
}

/// Rewrites a live-recording WAV so players see the PCM that follows the
/// placeholder header. A valid file is left unchanged.
Future<void> repairWavHeader(String path) async {
  final file = File(path);
  if (!file.existsSync()) {
    throw StateError('Fichier audio introuvable');
  }
  final bytes = await file.readAsBytes();
  if (bytes.length <= 44) {
    throw StateError('Audio vide');
  }
  if (patchPlaceholderWavHeader(bytes)) {
    await file.writeAsBytes(bytes, flush: true);
    return;
  }
  final info = WavPcmInfo.parse(bytes);
  if (info.dataByteCount <= 0) {
    throw StateError('Audio vide');
  }
}
