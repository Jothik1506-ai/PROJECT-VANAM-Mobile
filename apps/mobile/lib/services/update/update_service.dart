import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'update_manifest.dart';

/// Self-update client for builds distributed outside the Play Store.
///
/// Flow: fetch manifest → compare versionCode → download APK → verify
/// SHA-256 → hand to the system package installer. The user still confirms
/// the install at the OS level; there is no silent update path for a normal
/// Android app, and that is correct.
///
/// See docs/OTA-RELEASES.md.
class UpdateService {
  UpdateService({required this.manifestUrl, http.Client? client})
    : _client = client ?? http.Client();

  /// HTTPS URL of manifest.json.
  final String manifestUrl;
  final http.Client _client;

  static const _checkTimeout = Duration(seconds: 10);

  /// Checks whether a newer build is published.
  ///
  /// Never throws: an update check failing (offline, bad manifest, server
  /// down) must not block someone from opening the app and reading their
  /// messages. Failures resolve to [UpdateAvailability.upToDate].
  Future<UpdateCheckResult> check() async {
    final installedVersionCode = await _installedVersionCode();

    try {
      final response = await _client
          .get(Uri.parse(manifestUrl))
          .timeout(_checkTimeout);

      if (response.statusCode != 200) {
        return UpdateCheckResult(
          availability: UpdateAvailability.upToDate,
          installedVersionCode: installedVersionCode,
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return UpdateCheckResult(
          availability: UpdateAvailability.upToDate,
          installedVersionCode: installedVersionCode,
        );
      }

      final manifest = UpdateManifest.fromJson(decoded);

      if (manifest.latestVersionCode <= installedVersionCode) {
        return UpdateCheckResult(
          availability: UpdateAvailability.upToDate,
          installedVersionCode: installedVersionCode,
          manifest: manifest,
        );
      }

      return UpdateCheckResult(
        availability: installedVersionCode < manifest.minSupportedVersionCode
            ? UpdateAvailability.required
            : UpdateAvailability.optional,
        installedVersionCode: installedVersionCode,
        manifest: manifest,
      );
    } catch (_) {
      // Offline, timeout, malformed manifest, TLS failure — all non-fatal.
      return UpdateCheckResult(
        availability: UpdateAvailability.upToDate,
        installedVersionCode: installedVersionCode,
      );
    }
  }

  Future<int> _installedVersionCode() async {
    final info = await PackageInfo.fromPlatform();
    return int.tryParse(info.buildNumber) ?? 0;
  }

  /// Downloads the APK, verifying its checksum before returning.
  ///
  /// [onProgress] receives 0.0–1.0 when the server reports a content length.
  /// Throws [UpdateIntegrityException] if the download does not match the
  /// manifest's SHA-256 — the file is deleted rather than left on disk.
  Future<File> download(
    UpdateManifest manifest, {
    void Function(double progress)? onProgress,
  }) async {
    final request = http.Request('GET', Uri.parse(manifest.apkUrl));
    final response = await _client.send(request);

    if (response.statusCode != 200) {
      throw UpdateDownloadException(
        'Download failed with status ${response.statusCode}',
      );
    }

    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/vanam-${manifest.latestVersionCode}.apk',
    );
    // A partial file from an interrupted earlier attempt would otherwise be
    // appended to and fail the checksum.
    if (await file.exists()) {
      await file.delete();
    }

    final sink = file.openWrite();
    final total = response.contentLength;
    var received = 0;

    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total != null && total > 0) {
          onProgress?.call(received / total);
        }
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    // Verify before the file is ever handed to the package installer.
    // Outside the Play Store this checksum plus the signing key are the
    // integrity guarantees we have.
    final digest = await sha256.bind(file.openRead()).first;
    if (digest.toString() != manifest.sha256) {
      await file.delete();
      throw const UpdateIntegrityException(
        'Downloaded file did not match the expected checksum.',
      );
    }

    return file;
  }

  /// Hands the verified APK to the Android package installer.
  ///
  /// The OS shows its own confirmation dialog. If the user has not granted
  /// "install unknown apps" for VANAM, Android prompts for that first.
  Future<void> install(File apk) async {
    final result = await OpenFilex.open(
      apk.path,
      type: 'application/vnd.android.package-archive',
    );
    if (result.type != ResultType.done) {
      throw UpdateInstallException(result.message);
    }
  }

  void dispose() => _client.close();
}

class UpdateDownloadException implements Exception {
  const UpdateDownloadException(this.message);
  final String message;
  @override
  String toString() => message;
}

class UpdateIntegrityException implements Exception {
  const UpdateIntegrityException(this.message);
  final String message;
  @override
  String toString() => message;
}

class UpdateInstallException implements Exception {
  const UpdateInstallException(this.message);
  final String message;
  @override
  String toString() => message;
}
