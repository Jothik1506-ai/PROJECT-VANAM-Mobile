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

  /// Decrypts a conversation's last message for the chat list preview.
  /// Returns null when this device has no key yet or can't read it.
  Future<String?> decryptPreview(DirectConversation conversation) async {
    final cipher = conversation.lastMessageText;
    if (cipher == null || cipher.isEmpty) return null;
    try {
      final key = await keySyncService.peekScopeKey(
        scope: 'direct',
        scopeId: conversation.conversationId,
      );
      if (key == null) return null;
      return _e2ee.decryptMessage(ciphertextBase64: cipher, symmetricKey: key);
    } catch (_) {
      return null;
    }
  }

  /// Messages per page. The server returns the newest page; pass [before]
  /// (the oldest sent_at already shown) to load the page before it.
  static const pageSize = 100;

  /// About the most recent fetchMessages call, measured BEFORE hidden
  /// (undecryptable) messages are filtered out: whether the server page was
  /// full (so an older page may exist) and the oldest sent_at it contained
  /// (the cursor for the next "load earlier" request).
  bool lastPageFull = false;
  DateTime? lastOldestSentAt;

  Future<List<ChatMessage>> fetchMessages({
    required String conversationId,
    DateTime? before,
  }) async {
    final rows = await _client.rpc<List<dynamic>>(
      'list_direct_messages',
      params: {
        'p_conversation_id': conversationId,
        'p_message_limit': pageSize,
        if (before != null) 'p_before': before.toUtc().toIso8601String(),
      },
    );
    final typed = rows.whereType<Map<String, dynamic>>().toList();
    lastPageFull = typed.length >= pageSize;
    lastOldestSentAt = typed.isEmpty
        ? null
        : typed
              .map((r) => DateTime.tryParse(r['sent_at'] as String? ?? ''))
              .whereType<DateTime>()
              .fold<DateTime?>(
                null,
                (min, t) => min == null || t.isBefore(min) ? t : min,
              );
    var key = await _conversationKey(conversationId);
    var messages = await _decodeRows(typed, key);

    // A cached key that no longer decrypts usually means the other member
    // rotated the key (every wrap was replaced). Re-read our wrap once and
    // retry before showing "Unable to decrypt" for the whole thread.
    if (key != null && messages.any((m) => m.text == _undecryptable)) {
      keySyncService.invalidate(scope: 'direct', scopeId: conversationId);
      final fresh = await _conversationKey(conversationId);
      if (fresh != null && !_sameKey(fresh, key)) {
        key = fresh;
        messages = await _decodeRows(typed, key);
      }
    }
    // Old ciphertext whose key was intentionally discarded has no recovery
    // value. Do not keep rendering permanent encryption placeholders while
    // the participants start a fresh conversation.
    return messages..sort((a, b) => a.sentAt.compareTo(b.sentAt));
  }

  Future<List<ChatMessage>> _decodeRows(
    List<Map<String, dynamic>> rows,
    Uint8List? key,
  ) async {
    final messages = <ChatMessage>[];
    for (final row in rows) {
      messages.add(await _messageFromRpcRow(row, key));
    }
    return messages;
  }

  static const _undecryptable = ChatMessage.undecryptableText;

  static bool _sameKey(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Explicit, user-confirmed recovery for a conversation nobody can
  /// unlock: issues a new key and re-seals it for both participants. Older
  /// messages stay unreadable. Never called automatically — doing so on a
  /// plain "key not here yet" wiped the other member's working key.
  Future<void> resetEncryption(String conversationId) async {
    await keySyncService.rotateScopeKey(
      scope: 'direct',
      scopeId: conversationId,
    );
  }

  /// Marks every message from the other participant in this conversation
  /// as read — call whenever the recipient actually has the conversation
  /// open. Idempotent (only touches rows still unread), safe to call
  /// repeatedly (e.g. on every realtime refresh while the screen is open).
  Future<void> markRead(String conversationId) async {
    await _client.rpc(
      'mark_direct_messages_read',
      params: {'p_conversation_id': conversationId},
    );
  }

  Future<ChatMessage> sendMessage({
    required String conversationId,
    required String text,
  }) async {
    final key = await _conversationKey(conversationId);
    if (key == null) throw const EncryptionKeyUnavailableException();
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
    // Listens for UPDATE too, not just INSERT — a message's read_at flips
    // from null to a timestamp via UPDATE, and the sender's device needs
    // that event to turn its sent-tick into a read-tick live, the same way
    // a new message needs the INSERT event to appear live.
    final userId = currentUserId;
    var channel = _client
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
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'direct_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (_) => onChanged(),
        );
    if (userId != null) {
      channel = channel.onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'key_wraps',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'member_id',
          value: userId,
        ),
        callback: (payload) {
          final row = payload.newRecord;
          if (row['scope'] == 'direct' && row['scope_id'] == conversationId) {
            onChanged();
          }
        },
      );
    }
    return channel.subscribe();
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
        ? ChatMessage.waitingForKeyText
        : (await _e2ee.decryptMessage(
                ciphertextBase64: rawText,
                symmetricKey: key,
              ) ??
              _undecryptable);

    return ChatMessage(
      id: json['id'] as String? ?? '',
      senderId: senderId,
      senderName: json['sender_name'] as String? ?? 'Family Member',
      text: text,
      sentAt:
          DateTime.tryParse(json['sent_at'] as String? ?? '') ?? DateTime.now(),
      isMine: senderId.isNotEmpty && senderId == currentUserId,
      readAt: DateTime.tryParse(json['read_at'] as String? ?? ''),
    );
  }
}
