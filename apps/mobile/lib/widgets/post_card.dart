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
    final palette = context.vanam;
    return Container(
      margin: const EdgeInsets.only(bottom: VanamSpacing.md),
      decoration: BoxDecoration(
        color: palette.surfaceCard,
        borderRadius: BorderRadius.circular(VanamRadii.card),
        border: Border.all(color: palette.line),
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
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: palette.ink,
                        ),
                      ),
                      Text(
                        post.timeAgo,
                        style: TextStyle(fontSize: 12, color: palette.inkMuted),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.more_horiz, color: palette.inkMuted),
              ],
            ),
          ),
          AspectRatio(
            aspectRatio: 4 / 3,
            child: _PostMediaCarousel(urls: post.mediaUrls),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              VanamSpacing.md,
              VanamSpacing.sm,
              VanamSpacing.md,
              VanamSpacing.xs,
            ),
            child: Text(post.caption, style: TextStyle(color: palette.ink)),
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
                Icon(Icons.favorite_border, size: 20, color: palette.ink),
                const SizedBox(width: 4),
                Text(
                  '${post.likeCount}',
                  style: TextStyle(fontSize: 13, color: palette.ink),
                ),
                const SizedBox(width: VanamSpacing.md),
                Icon(Icons.mode_comment_outlined, size: 20, color: palette.ink),
                const SizedBox(width: 4),
                Text(
                  '${post.commentCount}',
                  style: TextStyle(fontSize: 13, color: palette.ink),
                ),
                const SizedBox(width: VanamSpacing.md),
                Icon(Icons.send_outlined, size: 20, color: palette.ink),
                const Spacer(),
                Icon(Icons.bookmark_border, size: 20, color: palette.ink),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PostMediaCarousel extends StatefulWidget {
  const _PostMediaCarousel({required this.urls});

  final List<String> urls;

  @override
  State<_PostMediaCarousel> createState() => _PostMediaCarouselState();
}

class _PostMediaCarouselState extends State<_PostMediaCarousel> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final palette = context.vanam;
    if (widget.urls.isEmpty) {
      return const _MemoryPreview(label: 'Family note');
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          itemCount: widget.urls.length,
          onPageChanged: (index) => setState(() => _index = index),
          itemBuilder: (context, index) {
            return Image.network(
              widget.urls[index],
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return const _MemoryPreview(label: 'Photo unavailable');
              },
            );
          },
        ),
        if (widget.urls.length > 1)
          Positioned(
            top: VanamSpacing.sm,
            right: VanamSpacing.sm,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: VanamSpacing.sm,
                vertical: VanamSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${_index + 1}/${widget.urls.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        if (widget.urls.length > 1)
          Positioned(
            left: 0,
            right: 0,
            bottom: VanamSpacing.sm,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < widget.urls.length; i++)
                  Container(
                    width: i == _index ? 12 : 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: i == _index ? palette.brand : Colors.white70,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MemoryPreview extends StatelessWidget {
  const _MemoryPreview({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.vanam;
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: palette.memoryGradient,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.photo_camera_outlined, color: palette.brand, size: 34),
          const SizedBox(height: VanamSpacing.xs),
          Text(
            label,
            style: TextStyle(
              color: palette.brandStrong,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
