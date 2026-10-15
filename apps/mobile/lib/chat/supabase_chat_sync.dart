import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../crypto/e2ee_service.dart';
import '../crypto/key_sync_service.dart';
import 'chat_message.dart';

class SupabaseChatSync {
  SupabaseChatSync(this._client);

  final SupabaseClient _client;
  final _e2ee = E2eeService.instance;

  String? get currentUserId => _client.auth.currentUser?.id;

  /// Family group messages all share one symmetric key — this is where
  /// this device gets or creates it. See KeySyncService for how a member
  /// without a key wrap yet eventually gets one.
  Future<Uint8List?> _groupKey() {
    return keySyncService.getScopeKey(scope: 'group', scopeId: 'family-group');
  }

  /// Messages per page. The server returns the newest page; pass [before]
  /// (the oldest sent_at already shown) to load the page before it.
  static const pageSize = 100;

  Future<List<ChatMessage>> fetchMessages({
    String groupId = 'family-group',
    DateTime? before,
  }) async {
    final rows = await _client.rpc<List<dynamic>>(
      'list_messages',
      params: {
        'p_group_id': groupId,
        'p_message_limit': pageSize,
        if (before != null) 'p_before': before.toUtc().toIso8601String(),
      },
    );
    final typed = rows.whereType<Map<String, dynamic>>().toList();
    var key = await _groupKey();
    var messages = await _decodeRows(typed, key);

    // A cached key that no longer decrypts usually means another member
    // rotated the key (every wrap was replaced). Re-read our wrap once and
    // retry before showing "Unable to decrypt" for the whole thread.
    if (key != null && messages.any((m) => m.text == _undecryptable)) {
      keySyncService.invalidate(scope: 'group', scopeId: groupId);
      final fresh = await _groupKey();
      if (fresh != null && !_sameKey(fresh, key)) {
        key = fresh;
        messages = await _decodeRows(typed, key);
      }
    }
    // Old ciphertext whose key was intentionally discarded has no recovery
    // value. Do not keep rendering permanent encryption placeholders while
    // the family starts a fresh chat history.
    return messages.where((message) => !message.isUnavailable).toList()
      ..sort((a, b) => a.sentAt.compareTo(b.sentAt));
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

  /// Explicit, user-confirmed recovery for a chat nobody can unlock: issues
  /// a new key and re-seals it for every member. Older messages stay
  /// unreadable. Never called automatically — doing so on a plain "key not
  /// here yet" wiped every other member's working key.
  Future<void> resetEncryption({String groupId = 'family-group'}) async {
    await keySyncService.rotateScopeKey(scope: 'group', scopeId: groupId);
  }

  Future<ChatMessage> sendMessage({
    required String text,
    String groupId = 'family-group',
  }) async {
    final key = await _groupKey();
    if (key == null) throw const EncryptionKeyUnavailableException();
    final ciphertext = await _e2ee.encryptMessage(
      plaintext: text,
      symmetricKey: key,
    );

    final rows = await _client.rpc<List<dynamic>>(
      'send_message',
      params: {'p_group_id': groupId, 'p_message_text': ciphertext},
    );
    final row = rows.whereType<Map<String, dynamic>>().first;
    return _messageFromRpcRow(row, key);
  }

  RealtimeChannel subscribeToMessages({
    required String groupId,
    required Future<void> Function() onChanged,
  }) {
    final userId = currentUserId;
    var channel = _client
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
          if (row['scope'] == 'group' && row['scope_id'] == groupId) {
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
    final kind = ChatMessageKind.values.firstWhere(
      (k) => k.name == json['kind'],
      orElse: () => ChatMessageKind.user,
    );
    final rawText = json['message_text'] as String? ?? '';
    final text = await _decodeBody(rawText, kind, key);

    return ChatMessage(
      id: json['id'] as String? ?? '',
      senderId: senderId,
      senderName: json['sender_name'] as String? ?? 'Family Member',
      text: text,
      sentAt:
          DateTime.tryParse(json['sent_at'] as String? ?? '') ?? DateTime.now(),
      isMine: senderId.isNotEmpty && senderId == currentUserId,
      kind: kind,
    );
  }

  /// System events ("`<Name>` joined Vanam") are stored as plain UTF8
  /// bytes, never encrypted — base64-decode straight to text. Real
  /// messages are ciphertext under the group key.
  static Future<String> _decodeBody(
    String base64Body,
    ChatMessageKind kind,
    Uint8List? key,
  ) async {
    if (kind == ChatMessageKind.system) {
      try {
        // Postgres's encode(bytea,'base64') line-wraps every 76 chars —
        // strip before decoding (see E2eeService's note on the same issue).
        final cleaned = base64Body.replaceAll(RegExp(r'\s+'), '');
        return utf8.decode(base64Decode(cleaned));
      } catch (_) {
        return '';
      }
    }
    if (key == null) return ChatMessage.waitingForKeyText;
    final plaintext = await E2eeService.instance.decryptMessage(
      ciphertextBase64: base64Body,
      symmetricKey: key,
    );
    return plaintext ?? _undecryptable;
  }
}
