/// One row from list_direct_conversations() — a DM thread this device's
/// user participates in, with the other member's real name (never a
/// relation label — see family_member.dart) and a preview of the last
/// message, if any.
class DirectConversation {
  const DirectConversation({
    required this.conversationId,
    required this.otherUserId,
    required this.otherDisplayName,
    this.lastMessageText,
    this.lastMessageAt,
    this.lastMessageBody,
    this.lastMessageSenderId,
    this.unreadCount = 0,
  });

  final String conversationId;
  final String otherUserId;
  final String otherDisplayName;
  final String? lastMessageText;
  final DateTime? lastMessageAt;

  /// The last message's ciphertext (base64), decrypted on the device for
  /// the chat list preview. [lastMessageText] stays the server's plain
  /// "New message" placeholder so older app versions keep working.
  final String? lastMessageBody;

  /// Who sent the last message — lets the list prefix "You: ".
  final String? lastMessageSenderId;
  final int unreadCount;

  factory DirectConversation.fromJson(Map<String, dynamic> json) {
    return DirectConversation(
      conversationId: json['conversation_id'] as String? ?? '',
      otherUserId: json['other_user_id'] as String? ?? '',
      otherDisplayName:
          json['other_display_name'] as String? ?? 'Family Member',
      lastMessageText: json['last_message_text'] as String?,
      lastMessageAt: DateTime.tryParse(
        json['last_message_at'] as String? ?? '',
      ),
      lastMessageBody: json['last_message_body'] as String?,
      lastMessageSenderId: json['last_message_sender_id'] as String?,
      unreadCount: json['unread_count'] as int? ?? 0,
    );
  }
}
