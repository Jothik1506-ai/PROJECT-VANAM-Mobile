import 'package:supabase_flutter/supabase_flutter.dart';

import 'chat_message.dart';
import 'direct_conversation.dart';

/// Direct/personal chat — one conversation per pair of family members.
/// Mirrors [SupabaseChatSync]'s shape, but talks to the direct_* RPCs and
/// table (see supabase/migrations/20260819070000_direct_chat_messages.sql),
/// which are access-controlled per-conversation-participant rather than
/// "any active member" — a DM must never be readable by the whole family.
class SupabaseDirectChatSync {
  SupabaseDirectChatSync(this._client);

  final SupabaseClient _client;

  String? get currentUserId => _client.auth.currentUser?.id;

  Future<List<DirectConversation>> listConversations() async {
    final rows = await _client.rpc<List<dynamic>>('list_direct_conversations');
    return rows
        .whereType<Map<String, dynamic>>()
        .map(DirectConversation.fromJson)
        .toList();
  }

  Future<List<ChatMessage>> fetchMessages({
    required String conversationId,
  }) async {
    final rows = await _client.rpc<List<dynamic>>(
      'list_direct_messages',
      params: {'p_conversation_id': conversationId, 'p_message_limit': 100},
    );

    return rows
        .whereType<Map<String, dynamic>>()
        .map(_messageFromRpcRow)
        .toList();
  }

  Future<ChatMessage> sendMessage({
    required String conversationId,
    required String text,
  }) async {
    final rows = await _client.rpc<List<dynamic>>(
      'send_direct_message',
      params: {'p_conversation_id': conversationId, 'p_message_text': text},
    );
    final row = rows.whereType<Map<String, dynamic>>().first;
    return _messageFromRpcRow(row);
  }

  RealtimeChannel subscribeToMessages({
    required String conversationId,
    required Future<void> Function() onChanged,
  }) {
    return _client
        .channel('direct_messages:$conversationId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'direct_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
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
