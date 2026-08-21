import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/post.dart';
import '../theme/tokens.dart';
import 'member_avatar.dart';

/// Preview-only widget — Home Feed is Phase 3 (ARCHITECTURE.md Section 9).
class PostCard extends StatelessWidget {
  const PostCard({
    super.key,
    required this.post,
    this.canDelete = false,
    this.onDelete,
    this.onLike,
    this.onComment,
    this.onShare,
  });

  final Post post;
  final bool canDelete;
  final VoidCallback? onDelete;
  final VoidCallback? onLike;
  final VoidCallback? onComment;
  final VoidCallback? onShare;

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
                PopupMenuButton<_PostAction>(
                  enabled: canDelete,
                  icon: Icon(Icons.more_horiz, color: palette.inkMuted),
                  onSelected: (action) {
                    if (action == _PostAction.delete) onDelete?.call();
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: _PostAction.delete,
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_outline,
                            color: palette.danger,
                            size: 20,
                          ),
                          const SizedBox(width: VanamSpacing.sm),
                          Text(
                            'Delete permanently',
                            style: TextStyle(color: palette.danger),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
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
                IconButton(
                  onPressed: onLike,
                  icon: Icon(
                    post.likedByMe
                        ? Icons.favorite_rounded
                        : Icons.favorite_border,
                    size: 20,
                    color: post.likedByMe ? palette.danger : palette.ink,
                  ),
                  tooltip: post.likedByMe ? 'Unlike' : 'Like',
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 4),
                Text(
                  '${post.likeCount}',
                  style: TextStyle(fontSize: 13, color: palette.ink),
                ),
                const SizedBox(width: VanamSpacing.md),
                IconButton(
                  onPressed: onComment,
                  icon: Icon(
                    Icons.mode_comment_outlined,
                    size: 20,
                    color: palette.ink,
                  ),
                  tooltip: 'Comments',
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 4),
                Text(
                  '${post.commentCount}',
                  style: TextStyle(fontSize: 13, color: palette.ink),
                ),
                const SizedBox(width: VanamSpacing.md),
                IconButton(
                  onPressed: onShare,
                  icon: Icon(Icons.send_outlined, size: 20, color: palette.ink),
                  tooltip: 'Share in Vanam',
                  visualDensity: VisualDensity.compact,
                ),
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

enum _PostAction { delete }

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
            return CachedNetworkImage(
              imageUrl: widget.urls[index],
              fit: BoxFit.cover,
              memCacheWidth: 900,
              fadeInDuration: const Duration(milliseconds: 120),
              placeholder: (context, url) =>
                  const _MemoryPreview(label: 'Loading photo...'),
              errorWidget: (context, url, error) =>
                  const _MemoryPreview(label: 'Photo unavailable'),
              imageBuilder: (context, provider) => GestureDetector(
                onTap: () => _openViewer(context, index),
                child: Image(image: provider, fit: BoxFit.cover),
              ),
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

  void _openViewer(BuildContext context, int initialIndex) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FullScreenMediaViewer(
          urls: widget.urls,
          initialIndex: initialIndex,
        ),
      ),
    );
  }
}

class _FullScreenMediaViewer extends StatefulWidget {
  const _FullScreenMediaViewer({
    required this.urls,
    required this.initialIndex,
  });

  final List<String> urls;
  final int initialIndex;

  @override
  State<_FullScreenMediaViewer> createState() => _FullScreenMediaViewerState();
}

class _FullScreenMediaViewerState extends State<_FullScreenMediaViewer> {
  late final PageController _controller = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_index + 1}/${widget.urls.length}'),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.urls.length,
        onPageChanged: (index) => setState(() => _index = index),
        itemBuilder: (context, index) {
          return InteractiveViewer(
            minScale: 1,
            maxScale: 4,
            child: Center(
              child: CachedNetworkImage(
                imageUrl: widget.urls[index],
                fit: BoxFit.contain,
                memCacheWidth: 1440,
                placeholder: (context, url) => const Center(
                  child: CircularProgressIndicator(color: Colors.white54),
                ),
                errorWidget: (context, url, error) => const Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white54,
                    size: 48,
                  ),
                ),
              ),
            ),
          );
        },
      ),
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
