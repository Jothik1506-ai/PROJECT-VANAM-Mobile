import 'chat_message.dart';

/// Position in the server's history: the oldest RAW row of a page,
/// including rows the app filtered out (undecryptable, unavailable).
class ChatPageCursor {
  const ChatPageCursor(this.sentAt, this.id);

  final DateTime sentAt;
  final String id;

  Map<String, dynamic> toParams() => {
    'p_before': sentAt.toUtc().toIso8601String(),
    'p_before_id': id,
  };
}

/// One page from a *_page RPC: the visible messages plus paging state
/// computed from the raw rows, so filtered rows never stop paging.
class ChatPage {
  const ChatPage({
    required this.messages,
    required this.hasOlder,
    required this.cursor,
  });

  final List<ChatMessage> messages;

  /// True when the server returned a full page of raw rows.
  final bool hasOlder;

  /// Oldest raw row of this page; null when the page had no rows.
  final ChatPageCursor? cursor;

  static const empty = ChatPage(messages: [], hasOlder: false, cursor: null);

  /// Paging state from raw RPC rows (each with `id` and `sent_at`).
  static ({bool hasOlder, ChatPageCursor? cursor}) pagingFromRows(
    List<Map<String, dynamic>> rows,
    int pageSize,
  ) {
    ChatPageCursor? oldest;
    for (final row in rows) {
      final id = row['id']?.toString();
      final sent = DateTime.tryParse(row['sent_at']?.toString() ?? '');
      if (id == null || sent == null) continue;
      if (oldest == null ||
          sent.isBefore(oldest.sentAt) ||
          (sent.isAtSameMomentAs(oldest.sentAt) &&
              id.compareTo(oldest.id) < 0)) {
        oldest = ChatPageCursor(sent, id);
      }
    }
    return (hasOlder: rows.length >= pageSize, cursor: oldest);
  }

  /// Keeps already-loaded older pages when the newest page is refetched.
  /// An empty readable page keeps [current] unless [serverEmpty] says the
  /// server truly has no messages.
  static List<ChatMessage> mergeNewest(
    List<ChatMessage> current,
    List<ChatMessage> newest, {
    required bool serverEmpty,
  }) {
    final readable = newest.where((m) => !m.isUnavailable).toList();
    if (readable.isEmpty) return serverEmpty ? readable : current;
    final cutoff = readable.first.sentAt;
    final older = current.where(
      (m) => m.sentAt.isBefore(cutoff) && !m.isUnavailable,
    );
    return [...older, ...readable];
  }
}
