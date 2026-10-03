import 'package:flutter/material.dart';
import 'package:malinali/malinali_app.dart';
import 'package:malinali/services/malinali_audio_open_intent.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MalinaliAudioOpenIntent.instance.bootstrap();
  runApp(const MalinaliApp());
}
