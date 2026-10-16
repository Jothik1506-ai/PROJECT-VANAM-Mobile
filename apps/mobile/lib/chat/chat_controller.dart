import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'chat_message.dart';
import 'chat_page.dart';
import 'supabase_chat_sync.dart';

final familyGroupChat = ChatController(
  fileName: 'vanam_chat_family_group.json',
);

/// Local-first chat store for one conversation.
///
/// It always keeps a JSON cache so the thread opens quickly/offline. When a
/// [SupabaseChatSync] is attached, sends and refreshes go through Supabase.
class ChatController extends ValueNotifier<List<ChatMessage>> {
  ChatController({required this.fileName, this.groupId = 'family-group'})
    : super(const []);

  final String fileName;
  final String groupId;

  bool _loaded = false;
  String _accountId = 'signed-out';
  SupabaseChatSync? _sync;

  Future<void> load({String? userId}) async {
    final accountId = userId ?? 'signed-out';
    if (_accountId != accountId) {
      _loaded = false;
      _sync = null;
      value = const [];
      _accountId = accountId;
    }
    if (_loaded) return;
    _loaded = true;

    try {
      final file = await _chatFile();
      if (!await file.exists()) return;

      final decoded = jsonDecode(await file.readAsString());
      if (decoded is List) {
        value = decoded
            .whereType<Map<String, dynamic>>()
            .map(ChatMessage.fromJson)
            .where((message) => !message.isUnavailable)
            .toList();
      }
    } catch (_) {
      value = const [];
    }
  }

  void clearSession() {
    _loaded = false;
    _accountId = 'signed-out';
    _sync = null;
    _cursor = null;
    hasOlder = false;
    value = const [];
  }

  Future<void> attachSync(SupabaseChatSync sync) async {
    _sync = sync;
    await refreshFromRemote();
  }

  Future<void> refreshFromRemote() async {
    final sync = _sync;
    if (sync == null) return;

    final page = await sync.fetchMessages(groupId: groupId);
    final remoteMessages = page.messages
        .where((m) => !m.isUnavailable)
        .toList();
    // An empty newest page with rows on the server (all filtered) must not
    // wipe what is shown; only a truly empty server history clears it.
    if (remoteMessages.isEmpty && page.cursor != null) {
      hasOlder = page.hasOlder;
      _cursor ??= page.cursor;
      return;
    }
    // The server returns the newest page only. Keep older pages the user
    // already scrolled back to instead of dropping them on each refresh.
    final newestKnown = remoteMessages.isEmpty
        ? null
        : remoteMessages.first.sentAt;
    final older = newestKnown == null
        ? const <ChatMessage>[]
        : value.where((m) => m.sentAt.isBefore(newestKnown)).toList();
    value = [...older, ...remoteMessages];
    // Keep the deeper cursor if older pages were already loaded.
    if (older.isEmpty) {
      hasOlder = page.hasOlder;
      _cursor = page.cursor;
    }
    await _persist();
  }

  /// Whether another page of history may exist before what's loaded.
  bool hasOlder = false;

  /// Oldest raw server row loaded so far (may be a filtered-out message).
  ChatPageCursor? _cursor;

  /// Loads the page before the oldest message shown. Returns how many were
  /// added (0 means the start of the chat was reached).
  Future<int> loadOlder() async {
    final sync = _sync;
    final cursor = _cursor;
    if (sync == null || cursor == null || !hasOlder) return 0;
    final page = await sync.fetchMessages(groupId: groupId, before: cursor);
    hasOlder = page.hasOlder;
    if (page.cursor != null) _cursor = page.cursor;
    final older = page.messages;
    if (older.isEmpty) return 0;
    final known = value.map((m) => m.id).toSet();
    final fresh = older
        .where((m) => !m.isUnavailable && known.add(m.id))
        .toList();
    value = [...fresh, ...value];
    return fresh.length;
  }

  Future<void> sendLocalMessage({
    required String text,
    required String senderName,
    bool isMine = true,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final sync = _sync;
    if (sync != null && isMine) {
      final message = await sync.sendMessage(text: trimmed, groupId: groupId);
      value = _upsertMessage(value, message);
      await _persist();
      return;
    }

    final message = ChatMessage(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      senderName: senderName.trim().isEmpty ? 'You' : senderName.trim(),
      text: trimmed,
      sentAt: DateTime.now(),
      isMine: isMine,
    );

    value = [...value, message];
    await _persist();
  }

  List<ChatMessage> _upsertMessage(
    List<ChatMessage> messages,
    ChatMessage message,
  ) {
    final index = messages.indexWhere((m) => m.id == message.id);
    final next = [...messages];
    if (index == -1) {
      next.add(message);
    } else {
      next[index] = message;
    }
    return next..sort((a, b) => a.sentAt.compareTo(b.sentAt));
  }

  Future<void> _persist() async {
    final file = await _chatFile();
    final json = value
        .where((message) => !message.isUnavailable)
        .map((message) => message.toJson())
        .toList();
    await file.writeAsString(jsonEncode(json));
  }

  Future<File> _chatFile() async {
    final directory = await getApplicationSupportDirectory();
    final dot = fileName.lastIndexOf('.');
    final scopedName = dot == -1
        ? '${fileName}_$_accountId'
        : '${fileName.substring(0, dot)}_$_accountId${fileName.substring(dot)}';
    return File('${directory.path}${Platform.pathSeparator}$scopedName');
  }
}
