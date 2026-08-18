class Conversation {
  const Conversation({
    required this.name,
    required this.lastMessage,
    required this.timeLabel,
    required this.status,
    this.unreadCount = 0,
  });

  final String name;
  final String lastMessage;
  final String timeLabel;
  final String status;
  final int unreadCount;
}

/// Real V1 messaging (ARCHITECTURE.md Section 1/9) is a single family
/// group, no per-contact DMs, no calling. Only the one real thread is
/// listed here — per-relation mock contacts (Amma/Nanna/Akka/Thammudu)
/// were removed because relation labels are viewer-relative (what's
/// "Akka" to one member is someone else's daughter-in-law), not a fact
/// the app can hardcode. The Family Group tile below routes to the real
/// Supabase-backed chat; nothing else in this list is wired to a backend.
const mockConversations = [
  Conversation(
    name: 'Family Group',
    lastMessage: 'Tap to open the family chat',
    timeLabel: '',
    status: 'Encrypted family group',
  ),
];
