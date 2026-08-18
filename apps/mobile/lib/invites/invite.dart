/// A row from `public.invite_codes`. Admin-only — see
/// supabase/schema.sql's invite_codes_admin_all RLS policy.
class Invite {
  const Invite({
    required this.id,
    required this.code,
    required this.inviteeName,
    required this.expiresAt,
    required this.revoked,
    required this.createdAt,
    this.redeemedAt,
  });

  final String id;
  final String code;
  final String inviteeName;
  final DateTime expiresAt;
  final bool revoked;
  final DateTime createdAt;
  final DateTime? redeemedAt;

  InviteStatus get status {
    if (revoked) return InviteStatus.revoked;
    if (redeemedAt != null) return InviteStatus.used;
    if (expiresAt.isBefore(DateTime.now())) return InviteStatus.expired;
    return InviteStatus.active;
  }

  factory Invite.fromJson(Map<String, dynamic> json) {
    return Invite(
      id: json['id'] as String,
      code: json['code'] as String,
      inviteeName: json['invitee_name'] as String? ?? '',
      expiresAt: DateTime.parse(json['expires_at'] as String),
      revoked: json['revoked'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      redeemedAt: json['redeemed_at'] == null
          ? null
          : DateTime.parse(json['redeemed_at'] as String),
    );
  }
}

enum InviteStatus { active, used, expired, revoked }
