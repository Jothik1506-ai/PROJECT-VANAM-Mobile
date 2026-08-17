import 'package:flutter/material.dart';

import '../models/post.dart';
import '../theme/tokens.dart';
import 'member_avatar.dart';

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
                MemberAvatar(name: post.authorName, size: 36),
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
          AspectRatio(
            aspectRatio: 4 / 3,
            child: _MemoryPreview(label: post.mood),
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

class _MemoryPreview extends StatelessWidget {
  const _MemoryPreview({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFDDEAD7), Color(0xFFFFF1D2)],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.photo_camera_outlined,
            color: VanamColors.brand,
            size: 34,
          ),
          const SizedBox(height: VanamSpacing.xs),
          Text(
            label,
            style: const TextStyle(
              color: VanamColors.brandDark,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
