import 'package:flutter/material.dart';
import 'package:malinali/malinali_app.dart';
import 'package:malinali/services/app_info.dart';
import 'package:malinali/services/malinali_audio_open_intent.dart';
import 'package:malinali/utils/aptabase_bootstrap.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initAptabaseSkippingTestLab();
  await AppInfo.init();
  await MalinaliAudioOpenIntent.instance.bootstrap();
  runApp(const MalinaliApp());
}
