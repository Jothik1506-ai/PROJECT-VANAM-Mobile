import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_service.dart';
import '../chat/supabase_direct_chat_sync.dart';
import '../screens/chat_detail_screen.dart';
import 'active_chat_tracker.dart';

final vanamNavigatorKey = GlobalKey<NavigatorState>();

class PushNavigation {
  PushNavigation._();

  static Future<void> openFromPayload(Map<String, dynamic> data) async {
    if (Supabase.instance.client.auth.currentUser == null) return;
    // A tap that cold-starts the app can arrive before the navigator exists
    // (still on splash / sign-in); wait briefly instead of dropping it.
    var navigator = vanamNavigatorKey.currentState;
    for (var i = 0; navigator == null && i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      navigator = vanamNavigatorKey.currentState;
    }
    if (navigator == null) return;

    final chatType = data['chat_type']?.toString();
    if (chatType == 'family') {
      // Already looking at this chat: don't stack a duplicate screen.
      if (activeChatTracker.isActive(ActiveChatTracker.familyGroupScope)) {
        return;
      }
      var isAdmin = false;
      try {
        final profile = await authService.fetchMyProfile().timeout(
          const Duration(seconds: 8),
        );
        isAdmin = profile?.isAdmin ?? false;
      } catch (_) {}
      navigator.push(
        MaterialPageRoute(
          builder: (_) =>
              ChatDetailScreen(groupName: 'Family Group', isAdmin: isAdmin),
        ),
      );
      return;
    }

    if (chatType == 'direct') {
      final conversationId = data['conversation_id']?.toString();
      if (conversationId == null || conversationId.isEmpty) return;
      if (activeChatTracker.isActive(
        ActiveChatTracker.directScope(conversationId),
      )) {
        return;
      }

      var otherName = data['sender_name']?.toString() ?? 'Family Member';
      try {
        final conversations = await supabaseDirectChatSync
            .listConversations()
            .timeout(const Duration(seconds: 8));
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
