import 'package:supabase_flutter/supabase_flutter.dart';

import 'family_profile.dart';

/// Global instance, mirroring the ProfileController/ChatController pattern
/// elsewhere in this app. Safe as a top-level `final` because it's only
/// evaluated on first access, by which point main() has already called
/// Supabase.initialize().
final authService = AuthService(Supabase.instance.client);

/// Username/password auth (see ARCHITECTURE.md Section 5 and
/// supabase/migrations/20260820020000_username_password_auth.sql).
///
/// Supabase Auth wants an email, so a member's `vanam_<name>` username is
/// mapped to a synthetic `<username>@vanam.local` address the member never
/// sees or types — they only ever deal with the username. An admin creates
/// the account (`admin_create_member`/`admin_issue_credentials`) and hands
/// over the username + a default password; the member changes it on first
/// login. Unlike the old anonymous-session model, this credential works
/// from any device, indefinitely — it isn't lost if the app's local data
/// is cleared.
class AuthService {
  AuthService(this._client);

  final SupabaseClient _client;

  bool get isSignedIn => _client.auth.currentUser != null;

  static String _emailFor(String username) => '$username@vanam.local';

  /// Logs in with a member's username + password. Throws [LoginException]
  /// with a message safe to show directly on the Login screen.
  Future<void> signInWithUsernamePassword({
    required String username,
    required String password,
  }) async {
    try {
      await _client.auth.signInWithPassword(
        email: _emailFor(username.trim().toLowerCase()),
        password: password,
      );
    } on AuthException catch (e) {
      throw LoginException(
        e.message.toLowerCase().contains('invalid')
            ? 'Wrong username or password.'
            : e.message,
      );
    }
  }

  /// Sets a new password for the currently signed-in member, then clears
  /// the "must change password" flag that forced this screen.
  Future<void> changeOwnPassword(String newPassword) async {
    try {
      await _client.auth.updateUser(UserAttributes(password: newPassword));
      await _client.rpc('mark_own_password_changed');
    } on AuthException catch (e) {
      throw LoginException(e.message);
    }
  }

  /// The caller's own profiles row, or null if this session has no
  /// linked profile (shouldn't normally happen once signed in with a
  /// real username/password — every account created via admin_create_member
  /// gets one atomically).
  Future<FamilyProfile?> fetchMyProfile() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return null;
    final row = await _client
        .from('profiles')
        .select()
        .eq('id', uid)
        .maybeSingle();
    if (row == null) return null;
    return FamilyProfile.fromJson(row);
  }

  /// Lets the current member set their own display name, overriding
  /// whatever the admin typed into the invite dialog. See
  /// SetDisplayNameScreen and supabase/migrations/20260818160000 — relation
  /// labels (Amma/Nanna/Akka...) are viewer-relative, so V1 doesn't assign a
  /// name on someone else's behalf.
  Future<void> setOwnDisplayName(String name) async {
    try {
      await _client.rpc(
        'set_own_display_name',
        params: {'p_display_name': name},
      );
    } on PostgrestException catch (e) {
      throw SetDisplayNameException(e.message);
    }
  }

  Future<void> signOut() => _client.auth.signOut();

  /// Self-service password reset via a one-time recovery code (shown once
  /// alongside the username/password when an admin creates/issues/resets
  /// credentials — see admin_invites_screen.dart). No session required;
  /// callable straight from the Login screen.
  Future<void> resetPasswordWithRecoveryCode({
    required String username,
    required String recoveryCode,
    required String newPassword,
  }) async {
    try {
      await _client.rpc(
        'reset_password_with_recovery_code',
        params: {
          'p_username': username.trim().toLowerCase(),
          'p_recovery_code': recoveryCode.trim(),
          'p_new_password': newPassword,
        },
      );
    } on PostgrestException catch (e) {
      throw LoginException(e.message);
    }
  }
}

class LoginException implements Exception {
  const LoginException(this.message);
  final String message;
  @override
  String toString() => message;
}

class SetDisplayNameException implements Exception {
  const SetDisplayNameException(this.message);
  final String message;
  @override
  String toString() => message;
}
