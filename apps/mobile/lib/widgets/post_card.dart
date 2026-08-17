import 'package:flutter/material.dart';

import '../models/post.dart';
import '../theme/tokens.dart';

/// Preview-only widget — Home Feed is Phase 3 (ARCHITECTURE.md Section 9).
class PostCard extends StatelessWidget {
  const PostCard({super.key, required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: VanamSpacing.md),
      decoration: BoxDecoration(
        color: VanamColors.surfaceCard,
        borderRadius: BorderRadius.circular(VanamRadii.card),
        border: Border.all(color: VanamColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              VanamSpacing.md,
              VanamSpacing.md,
              VanamSpacing.sm,
              VanamSpacing.sm,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 36,
                  height: 36,
                  child: Image.asset(
                    'assets/brand/Final.png',
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(width: VanamSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        post.authorName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: VanamColors.ink,
                        ),
                      ),
                      Text(
                        post.timeAgo,
                        style: const TextStyle(
                          fontSize: 12,
                          color: VanamColors.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.more_horiz, color: VanamColors.inkMuted),
              ],
            ),
          ),
          if (post.hasImage)
            AspectRatio(
              aspectRatio: 4 / 3,
              child: Container(color: const Color(0xFFCFE0CE)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              VanamSpacing.md,
              VanamSpacing.sm,
              VanamSpacing.md,
              VanamSpacing.xs,
            ),
            child: Text(post.caption, style: const TextStyle(color: VanamColors.ink)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              VanamSpacing.sm,
              0,
              VanamSpacing.md,
              VanamSpacing.sm,
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.favorite_border,
                  size: 20,
                  color: VanamColors.ink,
                ),
                const SizedBox(width: 4),
                Text('${post.likeCount}', style: const TextStyle(fontSize: 13)),
                const SizedBox(width: VanamSpacing.md),
                const Icon(
                  Icons.mode_comment_outlined,
                  size: 20,
                  color: VanamColors.ink,
                ),
                const SizedBox(width: 4),
                Text('${post.commentCount}', style: const TextStyle(fontSize: 13)),
                const SizedBox(width: VanamSpacing.md),
                const Icon(Icons.send_outlined, size: 20, color: VanamColors.ink),
                const Spacer(),
                const Icon(
                  Icons.bookmark_border,
                  size: 20,
                  color: VanamColors.ink,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
