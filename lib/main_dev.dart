import 'package:flutter/material.dart';
import 'package:malinali/malinali_app.dart';
import 'package:malinali/services/malinali_audio_open_intent.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  sherpa_onnx.initBindings();
  await MalinaliAudioOpenIntent.instance.bootstrap();
  runApp(const MalinaliApp());
}
