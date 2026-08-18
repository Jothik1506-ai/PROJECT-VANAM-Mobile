/// A row from `public.profiles` — the real, Supabase-backed family member
/// record. Distinct from `profile/user_profile.dart`'s `UserProfile`, which
/// is this device's local display-name/language preference only.
class FamilyProfile {
  const FamilyProfile({
    required this.id,
    required this.displayName,
    required this.role,
    required this.status,
  });

  final String id;
  final String displayName;
  final String role;
  final String status;

  bool get isAdmin => role == 'admin' && status == 'active';

  factory FamilyProfile.fromJson(Map<String, dynamic> json) {
    return FamilyProfile(
      id: json['id'] as String,
      displayName: json['display_name'] as String? ?? '',
      role: json['role'] as String? ?? 'member',
      status: json['status'] as String? ?? 'active',
    );
  }
}
