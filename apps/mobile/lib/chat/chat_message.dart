class ChatMessage {
  const ChatMessage({
    required this.id,
    this.senderId,
    required this.senderName,
    required this.text,
    required this.sentAt,
    this.isMine = false,
    this.kind = ChatMessageKind.user,
    this.readAt,
  });

  final String id;
  final String? senderId;
  final String senderName;
  final String text;
  final DateTime sentAt;

  /// When the recipient read this message — direct messages only (see
  /// supabase/migrations/20260820070000_direct_message_read_receipts.sql).
  /// Null means "not read yet" (family group messages never set this;
  /// there's no per-message N-way read receipt in this app).
  final DateTime? readAt;

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
      'readAt': readAt?.toIso8601String(),
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
      readAt: DateTime.tryParse(json['readAt'] as String? ?? ''),
    );
  }
}

enum ChatMessageKind { user, system }
