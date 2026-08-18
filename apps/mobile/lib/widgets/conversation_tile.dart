import 'package:flutter/material.dart';

import '../models/conversation.dart';
import '../screens/chat_detail_screen.dart';
import '../theme/tokens.dart';
import 'member_avatar.dart';

/// Preview-only widget — see ARCHITECTURE.md Section 9 (calling is Phase 2,
/// per-contact DMs are not in V1's single-group model).
class ConversationTile extends StatelessWidget {
  const ConversationTile({super.key, required this.conversation});

  final Conversation conversation;

  @override
  Widget build(BuildContext context) {
    final hasUnread = conversation.unreadCount > 0;
    final palette = context.vanam;
    // Only the Family Group has a real chat thread — ARCHITECTURE.md's
    // locked V1 scope is one group, no per-contact DMs.
    final isFamilyGroup = conversation.name == 'Family Group';

    return InkWell(
      onTap: () {
        if (isFamilyGroup) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  ChatDetailScreen(groupName: conversation.name),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Direct messages aren't available yet — only the Family "
                'Group chat works right now.',
              ),
            ),
          );
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: VanamSpacing.md,
          vertical: VanamSpacing.sm,
        ),
        child: Row(
          children: [
            MemberAvatar(name: conversation.name),
            const SizedBox(width: VanamSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    conversation.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: palette.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    conversation.status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: palette.inkMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: VanamSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  conversation.timeLabel,
                  style: TextStyle(fontSize: 11, color: palette.inkMuted),
                ),
                const SizedBox(height: VanamSpacing.xs),
                if (hasUnread) _UnreadBadge(count: conversation.unreadCount),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final palette = context.vanam;
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: palette.brand, shape: BoxShape.circle),
      child: Text(
        '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
