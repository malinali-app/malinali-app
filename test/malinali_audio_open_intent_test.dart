import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malinali/services/malinali_audio_open_intent.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(MalinaliAudioOpenIntent.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late MalinaliAudioOpenIntent intent;

  setUp(() {
    intent = MalinaliAudioOpenIntent.instance;
    intent.resetForTest();
  });

  tearDown(() {
    intent.resetForTest();
    messenger.setMockMethodCallHandler(channel, null);
  });

  group('looksLikeAudio', () {
    test('accepts WhatsApp / common audio extensions', () {
      expect(MalinaliAudioOpenIntent.looksLikeAudio(r'C:\cache\PTT-WA0003.opus'), isTrue);
      expect(MalinaliAudioOpenIntent.looksLikeAudio('/tmp/note.OGG'), isTrue);
      expect(MalinaliAudioOpenIntent.looksLikeAudio('voice.m4a'), isTrue);
      expect(MalinaliAudioOpenIntent.looksLikeAudio('clip.mp3'), isTrue);
      expect(MalinaliAudioOpenIntent.looksLikeAudio('rec.wav'), isTrue);
    });

    test('rejects non-audio paths', () {
      expect(MalinaliAudioOpenIntent.looksLikeAudio('catalogue.db'), isFalse);
      expect(MalinaliAudioOpenIntent.looksLikeAudio('photo.jpg'), isFalse);
      expect(MalinaliAudioOpenIntent.looksLikeAudio('readme.txt'), isFalse);
      expect(MalinaliAudioOpenIntent.looksLikeAudio(''), isFalse);
    });
  });

  group('pending path', () {
    test('setPendingPath stores trimmed path and takePendingPath clears it', () {
      intent.setPendingPath('  /cache/shared_voice.opus  ');
      expect(intent.hasPending, isTrue);
      expect(intent.pendingPath, '/cache/shared_voice.opus');

      expect(intent.takePendingPath(), '/cache/shared_voice.opus');
      expect(intent.hasPending, isFalse);
      expect(intent.takePendingPath(), isNull);
    });

    test('empty / whitespace clears pending', () {
      intent.setPendingPath('/a.opus');
      intent.setPendingPath('   ');
      expect(intent.hasPending, isFalse);
      expect(intent.pendingPath, isNull);
    });

    test('pathStream emits when pending is set', () async {
      final events = <String>[];
      final sub = intent.pathStream.listen(events.add);

      intent.setPendingPath('/shared/note.ogg');
      await Future<void>.delayed(Duration.zero);

      expect(events, ['/shared/note.ogg']);
      await sub.cancel();
    });
  });

  group('bootstrap with mocked native channel', () {
    test('loads pending path from getPendingAudioPath (cold start / WhatsApp SEND)',
        () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getPendingAudioPath') {
          return '/data/user/0/app.malinali.l10n/cache/shared_PTT.opus';
        }
        return null;
      });

      await intent.bootstrap();

      expect(
        intent.takePendingPath(),
        '/data/user/0/app.malinali.l10n/cache/shared_PTT.opus',
      );
    });

    test('ignores null pending from native', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getPendingAudioPath') return null;
        return null;
      });

      await intent.bootstrap();
      expect(intent.hasPending, isFalse);
    });

    test('onAudioPath from native (warm start / onNewIntent) sets pending',
        () async {
      await intent.bootstrap();

      await messenger.handlePlatformMessage(
        MalinaliAudioOpenIntent.channelName,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('onAudioPath', '/cache/from_whatsapp.opus'),
        ),
        (_) {},
      );

      expect(intent.takePendingPath(), '/cache/from_whatsapp.opus');
    });

    test('argv audio file that exists is accepted (desktop open)', () async {
      final dir = await Directory.systemTemp.createTemp('malinali_share_');
      final file = File('${dir.path}${Platform.pathSeparator}voice.opus');
      await file.writeAsBytes([0x4F, 0x67, 0x67, 0x53]); // "OggS" stub

      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });

      messenger.setMockMethodCallHandler(channel, (call) async => null);

      await intent.bootstrap(args: [
        '--something',
        '"${file.path}"',
      ]);

      expect(intent.takePendingPath(), file.path);
    });

    test('argv non-audio file is ignored even if it exists', () async {
      final dir = await Directory.systemTemp.createTemp('malinali_share_');
      final file = File('${dir.path}${Platform.pathSeparator}note.txt');
      await file.writeAsString('hello');

      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });

      messenger.setMockMethodCallHandler(channel, (call) async => null);

      await intent.bootstrap(args: [file.path]);
      expect(intent.hasPending, isFalse);
    });
  });
}
