class FamilyMember {
  const FamilyMember({required this.name, this.avatarAsset});

  final String name;
  final String? avatarAsset;
}

/// Mock data for UI preview only — not wired to any backend.
/// See ARCHITECTURE.md Section 9: Home Feed is Phase 3, not V1.
const mockFamilyMembers = [
  FamilyMember(name: 'Amma'),
  FamilyMember(name: 'Nanna'),
  FamilyMember(name: 'Akka'),
  FamilyMember(name: 'Thammudu'),
  FamilyMember(name: 'Nanamma'),
];
