/// Parsed form of the remote update manifest.
///
/// See docs/OTA-RELEASES.md section 4 for the published JSON schema.
/// VANAM ships outside the Play Store, so this manifest is how a build
/// learns that a newer build exists.
class UpdateManifest {
  const UpdateManifest({
    required this.latestVersionCode,
    required this.latestVersionName,
    required this.minSupportedVersionCode,
    required this.apkUrl,
    required this.sha256,
    this.sizeBytes,
    this.releaseNotes,
    this.releaseNotesTe,
    this.publishedAt,
  });

  final int latestVersionCode;
  final String latestVersionName;

  /// Installed builds below this code must update before continuing.
  /// This is the lever for pushing a security fix; use it sparingly.
  final int minSupportedVersionCode;

  final String apkUrl;

  /// Lowercase hex SHA-256 of the APK. Verified before install.
  final String sha256;

  final int? sizeBytes;
  final String? releaseNotes;
  final String? releaseNotesTe;
  final DateTime? publishedAt;

  /// Parses a manifest, throwing [FormatException] on anything malformed.
  ///
  /// Deliberately strict: every field that the update decision depends on
  /// (version code, URL, checksum) is required and validated. A manifest we
  /// cannot fully trust must not be able to trigger an install, so there are
  /// no silent defaults for those.
  factory UpdateManifest.fromJson(Map<String, dynamic> json) {
    final latestVersionCode = json['latestVersionCode'];
    if (latestVersionCode is! int || latestVersionCode < 1) {
      throw const FormatException('latestVersionCode must be a positive int');
    }

    final apkUrl = json['apkUrl'];
    if (apkUrl is! String || apkUrl.isEmpty) {
      throw const FormatException('apkUrl missing');
    }
    final uri = Uri.tryParse(apkUrl);
    // HTTPS only — an APK fetched over plaintext could be swapped in transit.
    if (uri == null || uri.scheme != 'https') {
      throw const FormatException('apkUrl must be an https URL');
    }

    final sha256 = json['sha256'];
    if (sha256 is! String || !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(sha256)) {
      throw const FormatException('sha256 must be 64 hex characters');
    }

    // Defaults to the latest code's own value only if absent, meaning "no
    // forced update" is expressed by omitting the field or setting it low.
    final minSupported = json['minSupportedVersionCode'];
    final minSupportedVersionCode = minSupported is int ? minSupported : 0;

    final publishedAtRaw = json['publishedAt'];
    return UpdateManifest(
      latestVersionCode: latestVersionCode,
      latestVersionName: json['latestVersionName'] as String? ?? '',
      minSupportedVersionCode: minSupportedVersionCode,
      apkUrl: apkUrl,
      sha256: sha256.toLowerCase(),
      sizeBytes: json['sizeBytes'] is int ? json['sizeBytes'] as int : null,
      releaseNotes: json['releaseNotes'] as String?,
      releaseNotesTe: json['releaseNotesTe'] as String?,
      publishedAt: publishedAtRaw is String
          ? DateTime.tryParse(publishedAtRaw)
          : null,
    );
  }
}

/// Outcome of an update check.
enum UpdateAvailability {
  /// Installed build is current.
  upToDate,

  /// A newer build exists; the user may dismiss the prompt.
  optional,

  /// Installed build is below minSupportedVersionCode and must update.
  required,
}

class UpdateCheckResult {
  const UpdateCheckResult({
    required this.availability,
    required this.installedVersionCode,
    this.manifest,
  });

  final UpdateAvailability availability;
  final int installedVersionCode;
  final UpdateManifest? manifest;

  bool get hasUpdate => availability != UpdateAvailability.upToDate;
  bool get isRequired => availability == UpdateAvailability.required;
}
