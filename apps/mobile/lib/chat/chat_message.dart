class ChatMessage {
  const ChatMessage({
    required this.id,
    this.senderId,
    required this.senderName,
    required this.text,
    required this.sentAt,
    this.isMine = false,
    this.kind = ChatMessageKind.user,
  });

  final String id;
  final String? senderId;
  final String senderName;
  final String text;
  final DateTime sentAt;

  /// Whether this device's user sent it. Synced messages derive this from
  /// Supabase auth.uid(); local test messages can still override it.
  final bool isMine;

  /// 'user' (a real chat message) or 'system' (e.g. "`<Name>` joined Vanam").
  /// System events render as a centered notice, never as a bubble — see
  /// ChatDetailScreen. Not attributable to "me" or "them" either way.
  final ChatMessageKind kind;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'senderId': senderId,
      'senderName': senderName,
      'text': text,
      'sentAt': sentAt.toIso8601String(),
      'isMine': isMine,
      'kind': kind.name,
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
      kind: ChatMessageKind.values.firstWhere(
        (k) => k.name == json['kind'],
        orElse: () => ChatMessageKind.user,
      ),
    );
  }
}

enum ChatMessageKind { user, system }
