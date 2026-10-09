import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Live session and one-shot calls into whisper_ggml.
///
/// On Windows, `package:ffi`'s `malloc.free` is `CoTaskMemFree`, but the
/// plugin returns buffers from the C runtime `malloc`. Freeing those with
/// `CoTaskMemFree` aborts the process. Responses are released with
/// `ucrtbase!free` instead. Buffers this file allocates still use Dart's
/// allocator, so those go through `malloc.free`.
typedef _StreamStartNative = Pointer<Utf8> Function(Pointer<Utf8> body);
typedef _StreamFeedNative = Pointer<Utf8> Function(
  Pointer<Float> pcm,
  Int32 nSamples,
);
typedef _StreamFeedDart = Pointer<Utf8> Function(Pointer<Float> pcm, int n);
typedef _StreamStopNative = Pointer<Utf8> Function();
typedef _RequestNative = Pointer<Utf8> Function(Pointer<Utf8> body);
typedef _CFreeNative = Void Function(Pointer<Void>);
typedef _CFreeDart = void Function(Pointer<Void>);

DynamicLibrary openWhisperLibrary() {
  if (Platform.isAndroid) {
    return DynamicLibrary.open('libwhisper.so');
  } else if (Platform.isWindows) {
    return DynamicLibrary.open('whisper_ggml.dll');
  } else if (Platform.isLinux) {
    return DynamicLibrary.open('libwhisper_ggml.so');
  }
  return DynamicLibrary.process();
}

final _CFreeDart? _windowsCrtFree = () {
  if (!Platform.isWindows) return null;
  // Prefer the debug CRT if we are in a debug build, to match the plugin.
  // We check multiple names because the CRT version can vary by toolchain.
  for (final name in [
    'ucrtbased.dll',
    'ucrtbase.dll',
    'msvcr120.dll',
    'msvcr110.dll',
    'msvcrt.dll'
  ]) {
    try {
      final lib = DynamicLibrary.open(name);
      final freePtr = lib.lookup<NativeFunction<_CFreeNative>>('free');
      print('WhisperNative: Found free() in $name');
      return freePtr.asFunction<_CFreeDart>();
    } catch (_) {}
  }
  print('WhisperNative: WARNING - Could not find C runtime free() on Windows. Memory leaks may occur to avoid crashes.');
  return null;
}();

void freeNativeResponse(Pointer<Utf8> response) {
  if (response.address == 0) return;
  final crtFree = _windowsCrtFree;
  if (crtFree != null) {
    crtFree(response.cast());
    return;
  }
  if (!Platform.isWindows) {
    malloc.free(response);
  }
  // On Windows, if we didn't find the CRT free, we LEAK the memory instead
  // of calling CoTaskMemFree which would abort the process.
  // The strings are small JSONs, so the leak is slow.
}

Map<String, dynamic> decodeNativeJson(Pointer<Utf8> response) {
  if (response.address == 0) {
    return {'@type': 'error', 'message': 'Native library returned null'};
  }
  final Map<String, dynamic> result =
      json.decode(response.toDartString()) as Map<String, dynamic>;
  freeNativeResponse(response);
  return result;
}

/// Drop a model parked by `keep_model_loaded`.
Future<void> whisperReleaseModel() {
  return Isolate.run(() {
    final DynamicLibrary lib = openWhisperLibrary();
    final request = lib.lookupFunction<_RequestNative, _RequestNative>(
      'request',
    );
    final Pointer<Utf8> ptr = json.encode({
      '@type': 'releaseModel',
    }).toNativeUtf8();
    try {
      decodeNativeJson(request(ptr));
    } finally {
      malloc.free(ptr);
    }
  });
}

/// One-shot `getTextFromWavFile` against an already decoded 16 kHz mono WAV.
Future<Map<String, dynamic>> whisperTranscribeWav({
  required String wavPath,
  required String modelPath,
  String language = 'auto',
  bool translate = true,
}) {
  final body = json.encode({
    '@type': 'getTextFromWavFile',
    'audio': wavPath,
    'model': modelPath,
    'is_translate': translate,
    'threads': 4,
    'is_verbose': false,
    'language': language,
    'is_special_tokens': false,
    'is_no_timestamps': true,
    'split_on_word': false,
    'diarize': false,
    'no_context': true,
    'suppress_non_speech_tokens': true,
    'keep_model_loaded': true,
  });
  return Isolate.run(() {
    final DynamicLibrary lib = openWhisperLibrary();
    final request = lib.lookupFunction<_RequestNative, _RequestNative>(
      'request',
    );
    final Pointer<Utf8> ptr = body.toNativeUtf8();
    try {
      return decodeNativeJson(request(ptr));
    } finally {
      malloc.free(ptr);
    }
  });
}

/// A running live transcription session.
class MalinaliWhisperLiveSession {
  MalinaliWhisperLiveSession._(this._worker, this._toWorker, this._partials);

  final Isolate _worker;
  final SendPort _toWorker;
  final StreamController<String> _partials;
  final Completer<String> _final = Completer<String>();
  bool _stopped = false;

  Stream<String> get partials => _partials.stream;

  void feed(Uint8List pcm16Bytes) {
    if (_stopped) return;
    _toWorker.send(['feed', pcm16Bytes]);
  }

  Future<String> stop() {
    if (!_stopped) {
      _stopped = true;
      _toWorker.send(const ['stop']);
    }
    return _final.future;
  }
}

Future<MalinaliWhisperLiveSession> startMalinaliWhisperLiveSession({
  required String modelPath,
  String lang = 'auto',
  bool translate = true,
  bool suppressNonSpeechTokens = true,
  bool keepModelLoaded = true,
  int threads = 4,
}) async {
  final ReceivePort fromWorker = ReceivePort();
  final Isolate worker = await Isolate.spawn(_liveWorker, fromWorker.sendPort);

  final StreamController<String> partials = StreamController<String>();
  final Completer<SendPort> ready = Completer<SendPort>();
  final Completer<void> started = Completer<void>();
  late final MalinaliWhisperLiveSession session;
  String lastText = '';

  fromWorker.listen((dynamic message) {
    final List<dynamic> msg = message as List<dynamic>;
    switch (msg[0] as String) {
      case 'ready':
        ready.complete(msg[1] as SendPort);
      case 'started':
        started.complete();
      case 'partial':
        lastText = msg[1] as String;
        if (!partials.isClosed) partials.add(lastText);
      case 'final':
        if (!partials.isClosed) partials.close();
        session._final.complete(msg[1] as String);
        fromWorker.close();
        session._worker.kill();
      case 'error':
        final error = Exception(msg[1] as String);
        if (!started.isCompleted) {
          started.completeError(error);
        } else if (!session._final.isCompleted) {
          if (!partials.isClosed) {
            partials
              ..addError(error)
              ..close();
          }
          session._final.complete(lastText);
          fromWorker.close();
          session._worker.kill();
        }
    }
  });

  final SendPort toWorker = await ready.future;
  session = MalinaliWhisperLiveSession._(worker, toWorker, partials);
  toWorker.send([
    'start',
    json.encode({
      'model': modelPath,
      'language': lang,
      'is_translate': translate,
      'threads': threads,
      'suppress_non_speech_tokens': suppressNonSpeechTokens,
      'keep_model_loaded': keepModelLoaded,
    }),
  ]);

  try {
    await started.future;
  } catch (_) {
    worker.kill(priority: Isolate.immediate);
    fromWorker.close();
    await partials.close();
    rethrow;
  }
  return session;
}

void _liveWorker(SendPort toMain) {
  final DynamicLibrary lib = openWhisperLibrary();
  final start = lib.lookupFunction<_StreamStartNative, _StreamStartNative>(
    'stream_start',
  );
  final feed = lib.lookupFunction<_StreamFeedNative, _StreamFeedDart>(
    'stream_feed',
  );
  final stopFn = lib.lookupFunction<_StreamStopNative, _StreamStopNative>(
    'stream_stop',
  );

  final ReceivePort inbox = ReceivePort();
  toMain.send(['ready', inbox.sendPort]);

  String lastPartial = '';
  int pendingByte = -1;

  inbox.listen((dynamic message) {
    final List<dynamic> msg = message as List<dynamic>;
    switch (msg[0] as String) {
      case 'start':
        final Pointer<Utf8> body = (msg[1] as String).toNativeUtf8();
        try {
          final Map<String, dynamic> result = decodeNativeJson(start(body));
          if (result['@type'] == 'error') {
            toMain.send(['error', result['message']]);
          } else {
            toMain.send(const ['started']);
          }
        } finally {
          malloc.free(body);
        }
      case 'feed':
        Uint8List bytes = msg[1] as Uint8List;
        if (pendingByte >= 0 ||
            bytes.offsetInBytes.isOdd ||
            bytes.length.isOdd) {
          final Uint8List merged = Uint8List(
            bytes.length + (pendingByte >= 0 ? 1 : 0),
          );
          var offset = 0;
          if (pendingByte >= 0) merged[offset++] = pendingByte;
          merged.setRange(offset, offset + bytes.length, bytes);
          if (merged.length.isOdd) {
            pendingByte = merged.last;
            bytes = Uint8List.sublistView(merged, 0, merged.length - 1);
          } else {
            pendingByte = -1;
            bytes = merged;
          }
        }
        if (bytes.isEmpty) return;
        final Int16List samples = bytes.buffer.asInt16List(
          bytes.offsetInBytes,
          bytes.length ~/ 2,
        );
        final Pointer<Float> pcm = malloc.allocate<Float>(
          samples.length * sizeOf<Float>(),
        );
        final Float32List dest = pcm.asTypedList(samples.length);
        for (var i = 0; i < samples.length; i++) {
          dest[i] = samples[i] / 32768.0;
        }
        try {
          final Map<String, dynamic> result = decodeNativeJson(
            feed(pcm, samples.length),
          );
          if (result['@type'] == 'error') {
            toMain.send(['error', result['message']]);
          } else {
            final String text = result['text'] as String? ?? '';
            if (text != lastPartial) {
              lastPartial = text;
              toMain.send(['partial', text]);
            }
          }
        } finally {
          malloc.free(pcm);
        }
      case 'stop':
        final Map<String, dynamic> result = decodeNativeJson(stopFn());
        toMain.send([
          'final',
          result['@type'] == 'error'
              ? lastPartial
              : result['text'] as String,
        ]);
        inbox.close();
    }
  });
}
