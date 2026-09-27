/// Build-time XOR obfuscation for the Hugging Face read token in [secret.txt].
///
/// Usage:
///   dart run tool/embed_hf_token.dart
///
/// Writes [lib/generated/hf_token.g.dart]. Re-run when the token rotates.
library;

import 'dart:io';
import 'dart:math';

void main() {
  final root = Directory.current;
  final secretFile = File('${root.path}/secret.txt');
  if (!secretFile.existsSync()) {
    stderr.writeln('Missing secret.txt at ${secretFile.path}');
    exit(1);
  }
  final token = secretFile.readAsStringSync().trim();
  if (!token.startsWith('hf_') || token.length < 20) {
    stderr.writeln('secret.txt does not look like an HF token');
    exit(1);
  }

  final rng = Random.secure();
  final key = List<int>.generate(token.length, (_) => rng.nextInt(256));
  final encoded = List<int>.generate(
    token.length,
    (i) => token.codeUnitAt(i) ^ key[i],
  );

  final outDir = Directory('${root.path}/lib/generated');
  outDir.createSync(recursive: true);
  final out = File('${outDir.path}/hf_token.g.dart');
  out.writeAsStringSync('''
// GENERATED — do not edit. Run: dart run tool/embed_hf_token.dart
// obfuscates secret.txt (read-only HF token). Not cryptographic security.

String hfReadToken() {
  const key = <int>[${key.join(', ')}];
  const enc = <int>[${encoded.join(', ')}];
  final out = StringBuffer();
  for (var i = 0; i < enc.length; i++) {
    out.writeCharCode(enc[i] ^ key[i]);
  }
  return out.toString();
}
''');
  stdout.writeln('Wrote ${out.path}');
}
