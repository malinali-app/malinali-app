// ignore_for_file: implementation_imports
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:malinali/malinali_app.dart';
import 'package:malinali/services/turso_sync_service.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isAndroid) {
    await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
  }

  await TursoSyncService.ensureCredentialsLoaded();

  runApp(const MalinaliApp());
}
