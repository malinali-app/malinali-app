import 'dart:io';
import 'dart:convert';
import 'package:marian_flutter/marian_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

void main() async {
  print('Starting TDD for fr-es (DART RUN)...');
  
  // 1. Locate DLL
  final libPath = 'build/windows/x64/runner/Release/marian_flutter.dll';
  if (!File(libPath).existsSync()) {
     print('DLL not found. Build Release first!');
     return;
  }
  
  try {
    await MarianService.initRust(externalLibrary: ExternalLibrary.open(libPath));
  } catch (_) {}

  // 2. Prepare Model Dir manually
  final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '';
  final modelDir = p.join(home, 'Documents', 'Malinali_do_not_delete', 'marian_models', 'doubleggg_traductor_fr_es');
  final dir = Directory(modelDir);
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }

  final modelId = 'doubleggg/traductor_fr_es';
  final files = ['config.json', 'model.safetensors'];
  
  final client = HttpClient();
  for (final file in files) {
    final targetFile = File(p.join(modelDir, file));
    if (!targetFile.existsSync() || targetFile.lengthSync() == 0) {
      print('Downloading $file...');
      final request = await client.getUrl(Uri.parse('https://huggingface.co/$modelId/resolve/main/$file'));
      final response = await request.close();
      if (response.statusCode != 200) {
         print('Failed to download $file: ${response.statusCode}');
         return;
      }
      await response.pipe(targetFile.openWrite());
    }
  }

  final tokenizerFile = File(p.join(modelDir, 'tokenizer.json'));
  if (!tokenizerFile.existsSync() || tokenizerFile.lengthSync() == 0) {
    print('Downloading tokenizer from Xenova/opus-mt-fr-es...');
    final request = await client.getUrl(Uri.parse('https://huggingface.co/Xenova/opus-mt-fr-es/resolve/main/tokenizer.json'));
    final response = await request.close();
    if (response.statusCode != 200) {
         print('Failed to download tokenizer: ${response.statusCode}');
         return;
    }
    final bytes = await response.reduce((a, b) => [...a, ...b]);
    String content = utf8.decode(bytes);
    
    // Clean up tokenizer
    final data = jsonDecode(content);
    void cleanData(dynamic obj) {
      if (obj is Map) {
        final keysToRemove = [];
        for (final key in obj.keys) {
          if (obj[key] == null) {
            keysToRemove.add(key);
          } else if (key == 'normalizer' && obj[key] is Map && obj[key]['type'] == 'Precompiled' && obj[key]['precompiled_charsmap'] == null) {
            keysToRemove.add(key);
          } else {
            cleanData(obj[key]);
          }
        }
        for (final key in keysToRemove) {
          obj.remove(key);
        }
      } else if (obj is List) {
        for (final item in obj) {
          cleanData(item);
        }
      }
    }
    cleanData(data);
    await tokenizerFile.writeAsString(jsonEncode(data));
  }
  client.close();
  
  print('Loading model from ${dir.path}...');
  final marian = await MarianService.loadFromDirectory(dir.path);
  
  final input = 'bonjour';
  print('Translating "$input"...');
  final result = await marian.translate(input);
  print('RESULT: "$result"');
  
  if (result.toLowerCase().contains('hola')) {
    print('SUCCESS!');
  } else {
    print('FAILED! Expected hola. Got: $result');
  }
  exit(0);
}
