import 'package:flutter/material.dart';

import '../chat/direct_conversation.dart';
import '../screens/chat_detail_screen.dart';
import '../theme/tokens.dart';
import 'member_avatar.dart';

/// A real, Supabase-backed direct-chat row — the other member's actual
/// display name (never a relation label), a preview of the last message if
/// any, and a tap target that opens the real per-pair chat thread.
class DirectConversationTile extends StatelessWidget {
  const DirectConversationTile({super.key, required this.conversation});

  final DirectConversation conversation;

  @override
  Widget build(BuildContext context) {
    final palette = context.vanam;
    final preview = conversation.lastMessageText;

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatDetailScreen.direct(
              otherDisplayName: conversation.otherDisplayName,
              conversationId: conversation.conversationId,
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: VanamSpacing.md,
          vertical: VanamSpacing.sm,
        ),
        child: Row(
          children: [
            MemberAvatar(name: conversation.otherDisplayName),
            const SizedBox(width: VanamSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    conversation.otherDisplayName,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: palette.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    preview == null || preview.isEmpty ? 'Say hello!' : preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: palette.inkMuted),
                  ),
                ],
              ),
            ),
            if (conversation.lastMessageAt != null)
              Text(
                _timeLabel(conversation.lastMessageAt!),
                style: TextStyle(fontSize: 11, color: palette.inkMuted),
              ),
          ],
        ),
      ),
    );
  }

  static String _timeLabel(DateTime time) {
    // See chat_detail_screen.dart's _timeLabel — sentAt/lastMessageAt come
    // back from Postgres as UTC and must be converted before reading
    // hour/minute, or the preview shows the sender's UTC time instead of
    // the reader's local time.
    final local = time.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }
}
