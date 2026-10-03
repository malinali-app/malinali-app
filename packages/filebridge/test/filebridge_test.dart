import 'package:filebridge/filebridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sanitizeExportFileName', () {
    test('strips path-hostile characters', () {
      expect(
        sanitizeExportFileName('contrat/2024:final#.txt'),
        'contrat_2024_final_.txt',
      );
    });

    test('falls back when empty', () {
      expect(sanitizeExportFileName(''), 'export.txt');
      expect(sanitizeExportFileName(':::'), 'export.txt');
    });
  });

  group('stripMacOsVolumePrefix', () {
    test('strips /Volumes/<disk>', () {
      expect(
        stripMacOsVolumePrefix('/Volumes/Macintosh HD/Users/a/out.txt'),
        '/Users/a/out.txt',
      );
    });

    test('leaves other paths unchanged', () {
      expect(stripMacOsVolumePrefix(r'C:\Users\a\out.txt'), r'C:\Users\a\out.txt');
      expect(stripMacOsVolumePrefix('/home/a/out.txt'), '/home/a/out.txt');
    });
  });
}
