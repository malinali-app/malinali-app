import 'package:flutter/material.dart';
import 'package:malinali/malinali_app.dart';
import 'package:malinali/services/turso_sync_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await TursoSyncService.ensureCredentialsLoaded();

  runApp(const MalinaliApp());
}
