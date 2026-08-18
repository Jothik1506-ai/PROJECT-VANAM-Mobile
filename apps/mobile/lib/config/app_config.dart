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

  /// Supabase project (ARCHITECTURE.md Section 5, supabase/schema.sql).
  ///
  /// The anon key is safe to embed — it grants nothing by itself; Row Level
  /// Security in schema.sql is what actually gates access. The service_role
  /// key (which DOES bypass RLS) must never appear here or anywhere in the
  /// client app.
  static const supabaseUrl = String.fromEnvironment(
    'VANAM_SUPABASE_URL',
    defaultValue: 'https://yweghwsgxstrdodjrvey.supabase.co',
  );

  static const supabaseAnonKey = String.fromEnvironment(
    'VANAM_SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inl3ZWdod3NneHN0cmRvZGpydmV5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODcwMzA5NzYsImV4cCI6MjEwMjYwNjk3Nn0.g9sXJ7ANVkl6MQSjPw9D8qjL717S6deA5xTe-eZnHmo',
  );
}
