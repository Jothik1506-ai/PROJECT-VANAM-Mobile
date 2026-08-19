import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:vanam_mobile/services/update/update_manifest.dart';
import 'package:vanam_mobile/services/update/update_service.dart';

const _validSha =
    'a3f1b2c4d5e6f708192a3b4c5d6e7f8091a2b3c4d5e6f708192a3b4c5d6e7f80';

/// Pretends the installed build is [versionCode].
void setInstalledVersionCode(int versionCode) {
  PackageInfo.setMockInitialValues(
    appName: 'Vanam',
    packageName: 'in.aivafreelancia.vanam.vanam_mobile',
    version: '1.0.0',
    buildNumber: '$versionCode',
    buildSignature: '',
  );
}

UpdateService serviceReturning(String body, {int statusCode = 200}) {
  return UpdateService(
    manifestUrl: 'https://updates.example.com/manifest.json',
    client: MockClient((_) async => http.Response(body, statusCode)),
  );
}

String manifestJson({
  required int latestVersionCode,
  int minSupportedVersionCode = 0,
}) {
  return jsonEncode({
    'latestVersionCode': latestVersionCode,
    'latestVersionName': '1.2.0',
    'minSupportedVersionCode': minSupportedVersionCode,
    'apkUrl': 'https://updates.example.com/vanam.apk',
    'sha256': _validSha,
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UpdateService.check', () {
    test('reports up to date when installed build matches latest', () async {
      setInstalledVersionCode(5);
      final result = await serviceReturning(
        manifestJson(latestVersionCode: 5),
      ).check();

      expect(result.availability, UpdateAvailability.upToDate);
      expect(result.hasUpdate, isFalse);
    });

    test(
      'reports up to date when installed build is newer than manifest',
      () async {
        // Can happen on a dev device running an unreleased build.
        setInstalledVersionCode(9);
        final result = await serviceReturning(
          manifestJson(latestVersionCode: 5),
        ).check();

        expect(result.availability, UpdateAvailability.upToDate);
      },
    );

    test('reports an optional update when a newer build exists', () async {
      setInstalledVersionCode(4);
      final result = await serviceReturning(
        manifestJson(latestVersionCode: 5, minSupportedVersionCode: 3),
      ).check();

      expect(result.availability, UpdateAvailability.optional);
      expect(result.isRequired, isFalse);
      expect(result.manifest?.latestVersionCode, 5);
    });

    test('reports a required update below minSupportedVersionCode', () async {
      setInstalledVersionCode(2);
      final result = await serviceReturning(
        manifestJson(latestVersionCode: 5, minSupportedVersionCode: 3),
      ).check();

      expect(result.availability, UpdateAvailability.required);
      expect(result.isRequired, isTrue);
    });

    test('treats the minSupported boundary as not required', () async {
      // Installed == minSupported is still supported.
      setInstalledVersionCode(3);
      final result = await serviceReturning(
        manifestJson(latestVersionCode: 5, minSupportedVersionCode: 3),
      ).check();

      expect(result.availability, UpdateAvailability.optional);
    });

    group('fails safe', () {
      // An update check failing must never block someone from opening the
      // app and reading their messages.
      test('on a malformed manifest', () async {
        setInstalledVersionCode(1);
        final result = await serviceReturning('{"nonsense":true}').check();
        expect(result.availability, UpdateAvailability.upToDate);
      });

      test('on invalid JSON', () async {
        setInstalledVersionCode(1);
        final result = await serviceReturning('not json at all').check();
        expect(result.availability, UpdateAvailability.upToDate);
      });

      test('on a server error', () async {
        setInstalledVersionCode(1);
        final result = await serviceReturning('', statusCode: 500).check();
        expect(result.availability, UpdateAvailability.upToDate);
      });

      test('on a network failure', () async {
        setInstalledVersionCode(1);
        final service = UpdateService(
          manifestUrl: 'https://updates.example.com/manifest.json',
          client: MockClient((_) async => throw const SocketExceptionStub()),
        );
        final result = await service.check();
        expect(result.availability, UpdateAvailability.upToDate);
      });
    });
  });
}

class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
