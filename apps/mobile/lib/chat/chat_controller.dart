import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'chat_message.dart';

final familyGroupChat = ChatController(fileName: 'vanam_chat_family_group.json');

/// Local-only chat store for one conversation, mirroring ProfileController's
/// shape (ValueNotifier + JSON file via path_provider) so the two local
/// persistence stores in this app behave the same way.
///
/// Not synced anywhere. This is the "local working chat" step before real
/// backend delivery — see ARCHITECTURE.md Section 6/10 for the planned
/// Cloudflare Workers + D1 + Durable Object replacement.
class ChatController extends ValueNotifier<List<ChatMessage>> {
  ChatController({required this.fileName}) : super(const []);

  final String fileName;

  bool _loaded = false;

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
      // A corrupt local chat file must not crash the app or block the user
      // from continuing to chat — start empty rather than throw.
      value = const [];
    }
  }

  /// Appends a message sent from this device and persists it.
  ///
  /// [isMine] defaults to true (your own outgoing message, right-aligned).
  /// It can be set false by the dev-only identity switcher (see
  /// lib/chat/test_identity.dart) to simulate an incoming-style message from
  /// another family member while testing on a single phone.
  Future<void> sendLocalMessage({
    required String text,
    required String senderName,
    bool isMine = true,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

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
