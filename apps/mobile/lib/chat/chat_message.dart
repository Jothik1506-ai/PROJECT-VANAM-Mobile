/// A single message in the local Family Group chat.
///
/// Local-only for now: stored on this device, not synced anywhere. See
/// ARCHITECTURE.md Section 6 for the real E2EE backend this will be
/// replaced/backed by later (Cloudflare Workers + D1 + Durable Objects).
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderName,
    required this.text,
    required this.sentAt,
    this.isMine = false,
  });

  final String id;
  final String senderName;
  final String text;
  final DateTime sentAt;

  /// Whether this device's user sent it — drives bubble alignment/color.
  /// Purely a local-UI concept; there is no real sender identity yet.
  final bool isMine;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'senderName': senderName,
      'text': text,
      'sentAt': sentAt.toIso8601String(),
      'isMine': isMine,
    };
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String? ?? '',
      senderName: json['senderName'] as String? ?? 'Family Member',
      text: json['text'] as String? ?? '',
      sentAt: DateTime.tryParse(json['sentAt'] as String? ?? '') ??
          DateTime.now(),
      isMine: json['isMine'] as bool? ?? false,
    );
  }
}
