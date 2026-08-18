import 'package:supabase_flutter/supabase_flutter.dart';

/// Global instance, mirroring the ProfileController/ChatController pattern
/// elsewhere in this app. Safe as a top-level `final` because it's only
/// evaluated on first access, by which point main() has already called
/// Supabase.initialize().
final authService = AuthService(Supabase.instance.client);

/// Wraps the anonymous-sign-in + invite-redemption auth flow.
///
/// See ARCHITECTURE.md Section 5 "Auth model" for why this exists: Supabase
/// Auth assumes email/phone/OAuth, and VANAM's locked model is invite code
/// + PIN with no open signup. The mapping is:
///   1. Sign in anonymously — gets a real auth.uid(), no email/phone attached.
///   2. Call redeem_invite(code, pin) — the only way that session becomes a
///      real family member (see supabase/schema.sql).
/// A session that never redeems an invite can read or write nothing; RLS
/// enforces this at the database, not just in app UI.
class AuthService {
  AuthService(this._client);

  final SupabaseClient _client;

  bool get isSignedIn => _client.auth.currentUser != null;

  /// Ensures there is *some* Supabase session, signing in anonymously if
  /// needed. Does not by itself grant any access — see class doc.
  Future<void> ensureSignedIn() async {
    if (_client.auth.currentSession != null) return;
    await _client.auth.signInAnonymously();
  }

  /// Redeems an invite code + PIN for the current session, linking it to a
  /// real profiles row. Throws [InviteRedemptionException] with a message
  /// safe to show directly on the Login screen — the Postgres function's
  /// error text is already written for a human (see schema.sql).
  Future<void> redeemInvite({
    required String code,
    required String pin,
  }) async {
    await ensureSignedIn();
    try {
      await _client.rpc(
        'redeem_invite',
        params: {'invite_code': code, 'invite_pin': pin},
      );
    } on PostgrestException catch (e) {
      throw InviteRedemptionException(e.message);
    }
  }

  Future<void> signOut() => _client.auth.signOut();
}

class InviteRedemptionException implements Exception {
  const InviteRedemptionException(this.message);
  final String message;
  @override
  String toString() => message;
}
