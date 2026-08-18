class ChatMessage {
  const ChatMessage({
    required this.id,
    this.senderId,
    required this.senderName,
    required this.text,
    required this.sentAt,
    this.isMine = false,
  });

  final String id;
  final String? senderId;
  final String senderName;
  final String text;
  final DateTime sentAt;

  /// Whether this device's user sent it. Synced messages derive this from
  /// Supabase auth.uid(); local test messages can still override it.
  final bool isMine;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'senderId': senderId,
      'senderName': senderName,
      'text': text,
      'sentAt': sentAt.toIso8601String(),
      'isMine': isMine,
    };
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String? ?? '',
      senderId: json['senderId'] as String?,
      senderName: json['senderName'] as String? ?? 'Family Member',
      text: json['text'] as String? ?? '',
      sentAt:
          DateTime.tryParse(json['sentAt'] as String? ?? '') ?? DateTime.now(),
      isMine: json['isMine'] as bool? ?? false,
    );
  }
}
