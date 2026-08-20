import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../crypto/e2ee_service.dart';
import '../crypto/key_sync_service.dart';
import 'chat_message.dart';
import 'direct_conversation.dart';

final supabaseDirectChatSync = SupabaseDirectChatSync(Supabase.instance.client);

/// Direct/personal chat — one conversation per pair of family members.
/// Mirrors [SupabaseChatSync]'s shape, but talks to the direct_* RPCs and
/// table (see supabase/migrations/20260819070000_direct_chat_messages.sql),
/// which are access-controlled per-conversation-participant rather than
/// "any active member" — a DM must never be readable by the whole family.
/// Each conversation has its own symmetric key (see key_sync_service.dart),
/// separate from the family group's — a DM key leak can't expose the group.
class SupabaseDirectChatSync {
  SupabaseDirectChatSync(this._client);

  final SupabaseClient _client;
  final _e2ee = E2eeService.instance;

  String? get currentUserId => _client.auth.currentUser?.id;

  Future<Uint8List?> _conversationKey(String conversationId) {
    return keySyncService.getScopeKey(scope: 'direct', scopeId: conversationId);
  }

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
    final key = await _conversationKey(conversationId);

    final messages = <ChatMessage>[];
    for (final row in rows.whereType<Map<String, dynamic>>()) {
      messages.add(await _messageFromRpcRow(row, key));
    }
    return messages;
  }

  Future<ChatMessage> sendMessage({
    required String conversationId,
    required String text,
  }) async {
    final key = await _conversationKey(conversationId);
    if (key == null) {
      throw StateError('Encryption key not ready yet — try again in a moment');
    }
    final ciphertext = await _e2ee.encryptMessage(
      plaintext: text,
      symmetricKey: key,
    );

    final rows = await _client.rpc<List<dynamic>>(
      'send_direct_message',
      params: {
        'p_conversation_id': conversationId,
        'p_message_text': ciphertext,
      },
    );
    final row = rows.whereType<Map<String, dynamic>>().first;
    return _messageFromRpcRow(row, key);
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

  Future<ChatMessage> _messageFromRpcRow(
    Map<String, dynamic> json,
    Uint8List? key,
  ) async {
    final senderId = json['sender_id'] as String? ?? '';
    final rawText = json['message_text'] as String? ?? '';
    final text = key == null
        ? '🔒 Waiting for encryption key…'
        : (await _e2ee.decryptMessage(
                ciphertextBase64: rawText,
                symmetricKey: key,
              ) ??
              '🔒 Unable to decrypt this message');

    return ChatMessage(
      id: json['id'] as String? ?? '',
      senderId: senderId,
      senderName: json['sender_name'] as String? ?? 'Family Member',
      text: text,
      sentAt:
          DateTime.tryParse(json['sent_at'] as String? ?? '') ?? DateTime.now(),
      isMine: senderId.isNotEmpty && senderId == currentUserId,
    );
  }
}
