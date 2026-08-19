import 'package:flutter_test/flutter_test.dart';
import 'package:vanam_mobile/services/update/update_manifest.dart';

const _validSha =
    'a3f1b2c4d5e6f708192a3b4c5d6e7f8091a2b3c4d5e6f708192a3b4c5d6e7f80';

Map<String, dynamic> validJson({
  int latestVersionCode = 5,
  int? minSupportedVersionCode,
  String? apkUrl,
  String? sha256,
}) {
  return {
    'latestVersionCode': latestVersionCode,
    'latestVersionName': '1.2.0',
    'minSupportedVersionCode': ?minSupportedVersionCode,
    'apkUrl': apkUrl ?? 'https://updates.example.com/vanam-1.2.0-5.apk',
    'sha256': sha256 ?? _validSha,
    'sizeBytes': 1024,
    'releaseNotes': 'Bug fixes.',
  };
}

void main() {
  group('UpdateManifest.fromJson', () {
    test('parses a well-formed manifest', () {
      final m = UpdateManifest.fromJson(validJson(minSupportedVersionCode: 3));
      expect(m.latestVersionCode, 5);
      expect(m.latestVersionName, '1.2.0');
      expect(m.minSupportedVersionCode, 3);
      expect(m.sha256, _validSha);
      expect(m.sizeBytes, 1024);
    });

    test('normalises checksum case so comparison is stable', () {
      final m = UpdateManifest.fromJson(
        validJson(sha256: _validSha.toUpperCase()),
      );
      expect(m.sha256, _validSha);
    });

    test('defaults minSupportedVersionCode to 0 (no forced update)', () {
      final m = UpdateManifest.fromJson(validJson());
      expect(m.minSupportedVersionCode, 0);
    });

    test('rejects a plaintext http APK url', () {
      // An APK fetched over http could be swapped in transit.
      expect(
        () => UpdateManifest.fromJson(
          validJson(apkUrl: 'http://updates.example.com/app.apk'),
        ),
        throwsFormatException,
      );
    });

    test('rejects a malformed checksum', () {
      expect(
        () => UpdateManifest.fromJson(validJson(sha256: 'deadbeef')),
        throwsFormatException,
      );
    });

    test('rejects a non-positive version code', () {
      expect(
        () => UpdateManifest.fromJson(validJson(latestVersionCode: 0)),
        throwsFormatException,
      );
    });

    test('rejects a missing apk url', () {
      final json = validJson()..remove('apkUrl');
      expect(() => UpdateManifest.fromJson(json), throwsFormatException);
    });

    test('rejects a missing checksum', () {
      final json = validJson()..remove('sha256');
      expect(() => UpdateManifest.fromJson(json), throwsFormatException);
    });
  });
}
