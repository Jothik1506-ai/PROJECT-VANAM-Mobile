import 'package:supabase_flutter/supabase_flutter.dart';

import 'invite.dart';

final inviteService = InviteService(Supabase.instance.client);

/// Admin-only member management, backed by the admin_create_member /
/// admin_issue_credentials / admin_reset_member_password RPCs (see
/// supabase/migrations/20260820020000_username_password_auth.sql). Every
/// method here will simply fail (RPC exception) if the caller isn't an
/// admin — enforced at the database, not just by not showing this screen
/// to non-admins.
class InviteService {
  InviteService(this._client);

  final SupabaseClient _client;

  /// Creates a brand-new member: a real username/password account plus
  /// their profiles row. Returns the one-time credentials + recovery code
  /// to show/QR-encode — after this call the plaintext password and
  /// recovery code are never available again (the recovery code's hash is
  /// stored; the password isn't stored at all, only its bcrypt hash).
  Future<(Invite, String username, String password, String recoveryCode)>
  createInvite({required String inviteeName}) async {
    final row = await _client.rpc(
      'admin_create_member',
      params: {'p_display_name': inviteeName},
    );
    final r = (row as List).first as Map<String, dynamic>;
    final username = r['username'] as String;
    final password = r['temp_password'] as String;
    final recoveryCode = r['recovery_code'] as String;
    return (
      Invite(
        id: '',
        inviteeName: inviteeName,
        username: username,
        status: MemberStatus.pending,
      ),
      username,
      password,
      recoveryCode,
    );
  }

  Future<List<Invite>> listInvites() async {
    final rows = await _client
        .from('profiles')
        .select()
        .order('created_at', ascending: false);
    return (rows as List)
        .map((r) => Invite.fromProfileJson(r as Map<String, dynamic>))
        .toList();
  }

  /// For a member who was created under the old invite/PIN flow, or has
  /// otherwise never had a username — attaches password login to their
  /// existing account (same id, so message history stays attached).
  Future<(String username, String password, String recoveryCode)>
  issueCredentials(String memberId) async {
    final row = await _client.rpc(
      'admin_issue_credentials',
      params: {'p_member_id': memberId},
    );
    final r = (row as List).first as Map<String, dynamic>;
    return (
      r['username'] as String,
      r['temp_password'] as String,
      r['recovery_code'] as String,
    );
  }

  /// Resets a member back to the default password (for someone who forgot
  /// theirs and doesn't have the original QR anymore) and mints a fresh
  /// recovery code.
  Future<(String password, String recoveryCode)> resetPassword(
    String memberId,
  ) async {
    final row = await _client.rpc(
      'admin_reset_member_password',
      params: {'p_member_id': memberId},
    );
    final r = (row as List).first as Map<String, dynamic>;
    return (r['temp_password'] as String, r['recovery_code'] as String);
  }

  Future<void> revokeInvite(String memberId) async {
    await _client
        .from('profiles')
        .update({'status': 'revoked'})
        .eq('id', memberId);
  }
}
