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

/// Mock data for UI preview only — not wired to any backend.
///
/// Real V1 messaging (ARCHITECTURE.md Section 1/9) is a single family
/// group, no per-contact DMs, no calling. This list of individual
/// conversations + a group is shown for visual review only.
const mockConversations = [
  Conversation(
    name: 'Family Group',
    lastMessage: 'Amma: Dinner at 8. Everyone confirm.',
    timeLabel: '9:41 AM',
    status: 'Encrypted family group',
    unreadCount: 5,
  ),
  Conversation(
    name: 'Amma',
    lastMessage: 'Kept prasadam for you.',
    timeLabel: '8:15 AM',
    status: 'Preview contact',
    unreadCount: 2,
  ),
  Conversation(
    name: 'Nanna',
    lastMessage: 'Temple visit photos are ready.',
    timeLabel: 'Yesterday',
    status: 'Preview contact',
  ),
  Conversation(
    name: 'Akka',
    lastMessage: 'I updated the shopping list.',
    timeLabel: 'Yesterday',
    status: 'Preview contact',
  ),
  Conversation(
    name: 'Thammudu',
    lastMessage: 'On my way home',
    timeLabel: 'Mon',
    status: 'Preview contact',
    unreadCount: 1,
  ),
];
