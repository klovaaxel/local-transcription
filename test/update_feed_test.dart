import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_local/update/update_feed.dart';

void main() {
  group('UpdateManifest.tryParse', () {
    test('parses the published shape', () {
      const body = '''
        {
          "schema": 1,
          "version": "1.1.0",
          "build": 2,
          "notes": "Bättre live-text.",
          "artifacts": {
            "windows": {
              "file": "Forelasning-1.1.0-windows-x64-setup.exe",
              "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
            },
            "android": {
              "file": "Forelasning-1.1.0-android-universal.apk",
              "sha256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
            }
          }
        }
      ''';
      final manifest = UpdateManifest.tryParse(body)!;
      expect(manifest.version, '1.1.0');
      expect(manifest.build, 2);
      expect(manifest.notes, 'Bättre live-text.');
      expect(manifest.artifacts.length, 2);
      expect(
        manifest.artifacts['windows']!.url.host,
        'github.com',
      );
      expect(
        manifest.artifacts['windows']!.url.path,
        '/klovaaxel/local-transcription/releases/latest/download/'
        'Forelasning-1.1.0-windows-x64-setup.exe',
      );
    });

    test('junk is null, not a crash', () {
      expect(UpdateManifest.tryParse('not json'), isNull);
      expect(UpdateManifest.tryParse('[]'), isNull);
    });

    test('missing artifacts gives an empty map, not a crash', () {
      final manifest = UpdateManifest.tryParse('{"version":"1.1.0"}')!;
      expect(manifest.artifacts, isEmpty);
      expect(manifest.build, 0);
    });

    test('artifact validity needs a file and a full sha256', () {
      const bad = '''
        {"artifacts": {"windows": {"file": "x.exe", "sha256": "short"}}}
      ''';
      final manifest = UpdateManifest.tryParse(bad)!;
      expect(manifest.artifacts['windows']!.isValid, isFalse);
    });
  });

  group('versionIsNewer', () {
    test('patch bump wins', () {
      expect(versionIsNewer('1.0.0', 1, '1.0.1', 2), isTrue);
    });

    test('older candidate loses', () {
      expect(versionIsNewer('1.2.0', 5, '1.1.9', 99), isFalse);
    });

    test('same version compares build numbers - the Android rule', () {
      expect(versionIsNewer('1.0.0', 1, '1.0.0', 2), isTrue);
      expect(versionIsNewer('1.0.0', 2, '1.0.0', 2), isFalse);
      expect(versionIsNewer('1.0.0', 2, '1.0.0', 1), isFalse);
    });

    test('partial version strings do not crash', () {
      expect(versionIsNewer('1.0', 0, '1.0.1', 0), isTrue);
      expect(versionIsNewer('1.0.0', 0, '1', 0), isFalse);
    });
  });
}
