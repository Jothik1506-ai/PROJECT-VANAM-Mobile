/// A row from `public.profiles` — the real, Supabase-backed family member
/// record. Distinct from `profile/user_profile.dart`'s `UserProfile`, which
/// is this device's local display-name/language preference only.
class FamilyProfile {
  const FamilyProfile({
    required this.id,
    required this.displayName,
    required this.role,
    required this.status,
    required this.nameConfirmed,
  });

  final String id;
  final String displayName;
  final String role;
  final String status;

  /// False until the member has set their own display name (see
  /// AuthService.setOwnDisplayName). Rows created before that feature
  /// existed default to true — see supabase/migrations/20260818160000.
  final bool nameConfirmed;

  bool get isAdmin => role == 'admin' && status == 'active';

  factory FamilyProfile.fromJson(Map<String, dynamic> json) {
    return FamilyProfile(
      id: json['id'] as String,
      displayName: json['display_name'] as String? ?? '',
      role: json['role'] as String? ?? 'member',
      status: json['status'] as String? ?? 'active',
      nameConfirmed: json['name_confirmed'] as bool? ?? true,
    );
  }
}
