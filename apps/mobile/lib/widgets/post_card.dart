import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../media/vanam_cached_image.dart';
import '../models/post.dart';
import '../theme/tokens.dart';
import 'member_avatar.dart';
import 'post_video_player.dart';

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
          if (post.hasVideo && post.videoItem != null)
            AspectRatio(
              aspectRatio: 4 / 3,
              child: PostVideoPlayer(
                videoUrl: post.videoItem!.url,
                durationSeconds: post.videoItem!.durationSeconds,
                thumbnailUrl: post.videoItem!.thumbnailUrl,
              ),
            )
          else
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
                _DownloadShareButton(post: post),
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

/// Downloads a post's media (all photos, or its one video) to a temp file
/// and opens the OS share sheet — the only way for a photo/video actually
/// hosted in Vanam's private storage bucket to leave the app (WhatsApp,
/// Gallery, etc.) rather than staying inside "Share in Vanam".
class _DownloadShareButton extends StatefulWidget {
  const _DownloadShareButton({required this.post});

  final Post post;

  @override
  State<_DownloadShareButton> createState() => _DownloadShareButtonState();
}

class _DownloadShareButtonState extends State<_DownloadShareButton> {
  var _busy = false;

  Future<void> _downloadAndShare() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final isVideo = widget.post.hasVideo && widget.post.videoItem != null;
      final urls = isVideo
          ? [widget.post.videoItem!.url]
          : widget.post.mediaUrls;
      if (urls.isEmpty) {
        throw const _DownloadFailure('This post has no media to download.');
      }

      final tempDir = await getTemporaryDirectory();
      final files = <XFile>[];
      for (var i = 0; i < urls.length; i++) {
        final response = await http
            .get(Uri.parse(urls[i]))
            .timeout(const Duration(seconds: 30));
        if (response.statusCode != 200) {
          throw const _DownloadFailure('Could not download media.');
        }
        final extension = isVideo ? 'mp4' : 'jpg';
        final file = File(
          '${tempDir.path}/vanam_${widget.post.id}_$i.$extension',
        );
        await file.writeAsBytes(response.bodyBytes);
        files.add(XFile(file.path));
      }

      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: files,
          text: widget.post.caption.isNotEmpty ? widget.post.caption : null,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not download this post.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.vanam;
    return IconButton(
      onPressed: _busy ? null : _downloadAndShare,
      icon: _busy
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: palette.ink,
              ),
            )
          : Icon(Icons.download_outlined, size: 20, color: palette.ink),
      tooltip: 'Download & share outside Vanam',
      visualDensity: VisualDensity.compact,
    );
  }
}

class _DownloadFailure implements Exception {
  const _DownloadFailure(this.message);
  final String message;
  @override
  String toString() => message;
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
            // Was a fixed 720 regardless of the device's actual screen
            // width/pixel density — sized to whatever it happened to be
            // tuned on, over-fetching on smaller/lower-DPI phones.
            return VanamCachedImage(
              imageUrl: widget.urls[index],
              fit: BoxFit.cover,
              width: screenAwareImageWidth(
                context,
                MediaQuery.sizeOf(context).width,
              ),
              quality: 62,
              placeholder: (context) =>
                  const _MemoryPreview(label: 'Loading photo...'),
              errorWidget: (context) =>
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
              child: VanamCachedImage(
                imageUrl: widget.urls[index],
                fit: BoxFit.contain,
                width: 1200,
                quality: 72,
                resize: 'contain',
                placeholder: (context) => const Center(
                  child: CircularProgressIndicator(color: Colors.white54),
                ),
                errorWidget: (context) => const Center(
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
