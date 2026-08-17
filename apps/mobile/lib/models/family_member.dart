class FamilyMember {
  const FamilyMember({required this.name, required this.role});

  final String name;
  final String role;
}

/// Mock data for UI preview only — not wired to any backend.
/// See ARCHITECTURE.md Section 9: Home Feed is Phase 3, not V1.
const mockFamilyMembers = [
  FamilyMember(name: 'Amma', role: 'Mom'),
  FamilyMember(name: 'Nanna', role: 'Dad'),
  FamilyMember(name: 'Akka', role: 'Sister'),
  FamilyMember(name: 'Thammudu', role: 'Brother'),
  FamilyMember(name: 'Nanamma', role: 'Grandmother'),
];
