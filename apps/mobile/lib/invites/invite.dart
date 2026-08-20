/// A family member, as seen by the admin's member-management screen.
/// Backed by `public.profiles` — see
/// supabase/migrations/20260820020000_username_password_auth.sql.
class Invite {
  const Invite({
    required this.inviteeName,
    required this.status,
    this.id = '',
    this.username,
  });

  /// profiles.id — empty right after creation, when only the RPC's
  /// (username, temp_password) result is available, not the row itself.
  final String id;
  final String inviteeName;
  final String? username;
  final MemberStatus status;

  factory Invite.fromProfileJson(Map<String, dynamic> json) {
    final status = json['status'] as String? ?? 'active';
    final passwordChanged = json['password_changed'] as bool? ?? true;
    final username = json['username'] as String?;

    final MemberStatus resolved;
    if (status == 'revoked') {
      resolved = MemberStatus.revoked;
    } else if (username == null) {
      resolved = MemberStatus.needsCredentials;
    } else if (!passwordChanged) {
      resolved = MemberStatus.pending;
    } else {
      resolved = MemberStatus.active;
    }

    return Invite(
      id: json['id'] as String,
      inviteeName: json['display_name'] as String? ?? '',
      username: username,
      status: resolved,
    );
  }
}

enum MemberStatus {
  /// Just created / re-issued credentials, hasn't logged in and changed
  /// the default password yet.
  pending,

  /// Logged in and set their own password.
  active,

  /// Admin revoked access.
  revoked,

  /// Legacy member from the old invite/PIN flow — has no username yet, an
  /// admin needs to run "Issue login" for them.
  needsCredentials,
}
