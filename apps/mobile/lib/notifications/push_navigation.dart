import 'package:flutter/material.dart';

import '../chat/supabase_direct_chat_sync.dart';
import '../screens/chat_detail_screen.dart';

final vanamNavigatorKey = GlobalKey<NavigatorState>();

class PushNavigation {
  PushNavigation._();

  static Future<void> openFromPayload(Map<String, dynamic> data) async {
    final navigator = vanamNavigatorKey.currentState;
    if (navigator == null) return;

    final chatType = data['chat_type']?.toString();
    if (chatType == 'family') {
      navigator.push(
        MaterialPageRoute(
          builder: (_) => ChatDetailScreen(groupName: 'Family Group'),
        ),
      );
      return;
    }

    if (chatType == 'direct') {
      final conversationId = data['conversation_id']?.toString();
      if (conversationId == null || conversationId.isEmpty) return;

      var otherName = data['sender_name']?.toString() ?? 'Family Member';
      try {
        final conversations = await supabaseDirectChatSync.listConversations();
        final match = conversations.where(
          (c) => c.conversationId == conversationId,
        );
        if (match.isNotEmpty) {
          otherName = match.first.otherDisplayName;
        }
      } catch (_) {
        // The notification can still open the chat by conversation id.
      }

      navigator.push(
        MaterialPageRoute(
          builder: (_) => ChatDetailScreen.direct(
            otherDisplayName: otherName,
            conversationId: conversationId,
          ),
        ),
      );
    }
  }
}
