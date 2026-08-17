/// Build-time configuration.
class AppConfig {
  AppConfig._();

  /// URL of the OTA update manifest (docs/OTA-RELEASES.md).
  ///
  /// Overridable per build so a test channel can point elsewhere:
  ///   flutter build apk --release \
  ///     --dart-define=VANAM_UPDATE_MANIFEST_URL=https://.../beta.json
  ///
  /// NOT YET LIVE: the hostname below is the planned endpoint. Until it is
  /// actually serving a manifest, update checks fail closed — UpdateService
  /// treats any error as "up to date" — so this is safe to ship ahead of the
  /// infrastructure.
  static const updateManifestUrl = String.fromEnvironment(
    'VANAM_UPDATE_MANIFEST_URL',
    defaultValue: 'https://updates.vanam.aivafreelancia.in/manifest.json',
  );

  /// Whether to check for updates at all. Disabled in the preview shell so
  /// UI review sessions never hit the network.
  static const updateChecksEnabled = bool.fromEnvironment(
    'VANAM_UPDATE_CHECKS_ENABLED',
    defaultValue: true,
  );
}
