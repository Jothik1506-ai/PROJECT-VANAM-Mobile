import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'invite.dart';

final inviteService = InviteService(Supabase.instance.client);

/// Admin-only invite management, backed by the create_invite/invite_codes
/// RLS in supabase/schema.sql. Every method here will simply fail (RPC
/// exception or empty result) if the caller isn't an admin — enforced at
/// the database, not just by not showing this screen to non-admins.
class InviteService {
  InviteService(this._client);

  final SupabaseClient _client;

  /// Creates an invite with a freshly system-generated PIN (ARCHITECTURE.md
  /// Section 7: "System generates invite code + one-time PIN" — not an
  /// admin-chosen one, which would tend toward predictable PINs).
  ///
  /// Returns the plaintext PIN alongside the created [Invite] — this is the
  /// only place it's ever available. The database only ever stores its
  /// bcrypt hash from this point on.
  Future<(Invite, String pin)> createInvite({
    required String inviteeName,
    int ttlDays = 7,
  }) async {
    final pin = _generatePin();
    final row = await _client.rpc(
      'create_invite',
      params: {
        'invitee_name': inviteeName,
        'invite_pin': pin,
        'ttl_days': ttlDays,
      },
    );
    return (Invite.fromJson(row as Map<String, dynamic>), pin);
  }

  Future<List<Invite>> listInvites() async {
    final rows = await _client
        .from('invite_codes')
        .select()
        .order('created_at', ascending: false);
    return (rows as List)
        .map((r) => Invite.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Revokes an invite that hasn't been used yet. Uses the
  /// profiles_admin/invite_codes_admin_all RLS path — a direct table
  /// update, not an RPC, since no extra validation logic is needed beyond
  /// "is this caller an admin," which RLS already enforces.
  Future<void> revokeInvite(String id) async {
    await _client.from('invite_codes').update({'revoked': true}).eq('id', id);
  }

  static String _generatePin() {
    final rng = Random.secure();
    return (100000 + rng.nextInt(900000)).toString();
  }
}
