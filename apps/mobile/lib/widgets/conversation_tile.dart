import 'package:flutter/material.dart';

import '../models/conversation.dart';
import '../theme/tokens.dart';

/// Preview-only widget — see ARCHITECTURE.md Section 9 (calling is Phase 2,
/// per-contact DMs are not in V1's single-group model).
class ConversationTile extends StatelessWidget {
  const ConversationTile({super.key, required this.conversation});

  final Conversation conversation;

  @override
  Widget build(BuildContext context) {
    final hasUnread = conversation.unreadCount > 0;
    return InkWell(
      onTap: () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: VanamSpacing.md,
          vertical: VanamSpacing.sm,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: Image.asset('assets/brand/Final.png', fit: BoxFit.contain),
            ),
            const SizedBox(width: VanamSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    conversation.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: VanamColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    conversation.lastMessage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: VanamColors.inkMuted,
                    ),
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
                  style: const TextStyle(
                    fontSize: 11,
                    color: VanamColors.inkMuted,
                  ),
                ),
                const SizedBox(height: VanamSpacing.xs),
                Row(
                  children: [
                    if (hasUnread) ...[
                      _UnreadBadge(count: conversation.unreadCount),
                      const SizedBox(width: VanamSpacing.xs),
                    ],
                    _CallButton(),
                  ],
                ),
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
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: VanamColors.brand,
        shape: BoxShape.circle,
      ),
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

class _CallButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: VanamColors.brand.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.call, size: 13, color: VanamColors.brand),
    );
  }
}
