import 'package:supabase_flutter/supabase_flutter.dart';

import 'chat_message.dart';

class SupabaseChatSync {
  SupabaseChatSync(this._client);

  final SupabaseClient _client;

  String? get currentUserId => _client.auth.currentUser?.id;

  Future<List<ChatMessage>> fetchMessages({
    String groupId = 'family-group',
  }) async {
    final rows = await _client.rpc<List<dynamic>>(
      'list_messages',
      params: {'message_group_id': groupId, 'message_limit': 100},
    );

    return rows
        .whereType<Map<String, dynamic>>()
        .map(_messageFromRpcRow)
        .toList();
  }

  Future<ChatMessage> sendMessage({
    required String text,
    String groupId = 'family-group',
  }) async {
    final rows = await _client.rpc<List<dynamic>>(
      'send_message',
      params: {'message_group_id': groupId, 'message_text': text},
    );
    final row = rows.whereType<Map<String, dynamic>>().first;
    return _messageFromRpcRow(row);
  }

  RealtimeChannel subscribeToMessages({
    required String groupId,
    required Future<void> Function() onChanged,
  }) {
    return _client
        .channel('messages:$groupId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'group_id',
            value: groupId,
          ),
          callback: (_) => onChanged(),
        )
        .subscribe();
  }

  Future<void> unsubscribe(RealtimeChannel channel) {
    return _client.removeChannel(channel);
  }

  ChatMessage _messageFromRpcRow(Map<String, dynamic> json) {
    final senderId = json['sender_id'] as String? ?? '';
    return ChatMessage(
      id: json['id'] as String? ?? '',
      senderId: senderId,
      senderName: json['sender_name'] as String? ?? 'Family Member',
      text: json['message_text'] as String? ?? '',
      sentAt:
          DateTime.tryParse(json['sent_at'] as String? ?? '') ?? DateTime.now(),
      isMine: senderId.isNotEmpty && senderId == currentUserId,
    );
  }
}
