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
  SupabaseChatSync? _sync;

  Future<void> load() async {
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
            .toList();
      }
    } catch (_) {
      value = const [];
    }
  }

  Future<void> attachSync(SupabaseChatSync sync) async {
    _sync = sync;
    await refreshFromRemote();
  }

  Future<void> refreshFromRemote() async {
    final sync = _sync;
    if (sync == null) return;

    final remoteMessages = await sync.fetchMessages(groupId: groupId);
    value = remoteMessages;
    await _persist();
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
    final json = value.map((m) => m.toJson()).toList();
    await file.writeAsString(jsonEncode(json));
  }

  Future<File> _chatFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}${Platform.pathSeparator}$fileName');
  }
}
