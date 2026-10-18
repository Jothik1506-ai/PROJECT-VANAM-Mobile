import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'chat_message.dart';
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

    final remoteMessages = await sync.fetchMessages(groupId: groupId);
    // The server returns the newest page only. Keep older pages the user
    // already scrolled back to instead of dropping them on each refresh.
    final newestKnown = remoteMessages.isEmpty
        ? null
        : remoteMessages.first.sentAt;
    final older = newestKnown == null
        ? const <ChatMessage>[]
        : value.where((m) => m.sentAt.isBefore(newestKnown)).toList();
    value = [...older, ...remoteMessages];
    _adoptPageCursor(sync);
    await _persist();
  }

  /// Whether another page of history may exist before what's loaded.
  bool hasOlder = false;

  // Oldest sent_at fetched from the server so far (hidden messages
  // included), the cursor for the next "load earlier" request. Only ever
  // moves back in time, so a refresh of the newest page doesn't reset it.
  DateTime? _cursor;

  void _adoptPageCursor(SupabaseChatSync sync) {
    final oldest = sync.lastOldestSentAt;
    if (_cursor == null || (oldest != null && oldest.isBefore(_cursor!))) {
      _cursor = oldest;
      hasOlder = sync.lastPageFull;
    }
  }

  /// Loads the page before the oldest message fetched. Returns how many
  /// were added (0 can also mean the page held only unreadable messages).
  Future<int> loadOlder() async {
    final sync = _sync;
    final cursor = _cursor;
    if (sync == null || cursor == null || !hasOlder) return 0;
    final older = await sync.fetchMessages(groupId: groupId, before: cursor);
    _cursor = sync.lastOldestSentAt ?? cursor;
    hasOlder = sync.lastPageFull;
    if (older.isEmpty) return 0;
    final known = value.map((m) => m.id).toSet();
    final fresh = older.where((m) => known.add(m.id)).toList();
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
