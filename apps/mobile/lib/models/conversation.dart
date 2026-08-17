class Conversation {
  const Conversation({
    required this.name,
    required this.lastMessage,
    required this.timeLabel,
    this.unreadCount = 0,
  });

  final String name;
  final String lastMessage;
  final String timeLabel;
  final int unreadCount;
}

/// Mock data for UI preview only — not wired to any backend.
///
/// Real V1 messaging (ARCHITECTURE.md Section 1/9) is a single family
/// group, no per-contact DMs, no calling. This list of individual
/// conversations + a group is shown for visual review only.
const mockConversations = [
  Conversation(
    name: 'Amma',
    lastMessage: "Call me when you're free 💚",
    timeLabel: '9:41 AM',
    unreadCount: 2,
  ),
  Conversation(
    name: 'Nanna',
    lastMessage: 'Sent the WiFi bill receipt',
    timeLabel: 'Yesterday',
  ),
  Conversation(
    name: 'Akka',
    lastMessage: 'Loved your reel! 😍',
    timeLabel: 'Yesterday',
  ),
  Conversation(
    name: 'Thammudu',
    lastMessage: 'On my way home',
    timeLabel: 'Mon',
    unreadCount: 1,
  ),
  Conversation(
    name: 'Family Group',
    lastMessage: 'Nayana: See you all Sunday!',
    timeLabel: 'Sun',
    unreadCount: 5,
  ),
];
