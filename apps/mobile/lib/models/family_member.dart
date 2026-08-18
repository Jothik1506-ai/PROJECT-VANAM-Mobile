class FamilyMember {
  const FamilyMember({required this.name, required this.role});

  final String name;
  final String role;
}

/// Mock data for UI preview only — not wired to any backend.
/// See ARCHITECTURE.md Section 9: Home Feed is Phase 3, not V1.
///
/// Intentionally empty: relation labels (Mom, Dad, Sister...) are
/// viewer-relative, not fixed facts about a person, so they can't be
/// hardcoded here. Real V1 uses each member's own name (set by the member,
/// see SetDisplayNameScreen), never a relation-to-admin label.
const mockFamilyMembers = <FamilyMember>[];
