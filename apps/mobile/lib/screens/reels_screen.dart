import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../home/home_feed_repository.dart';
import '../models/reel_item.dart';
import '../theme/tokens.dart';
import '../widgets/member_avatar.dart';

/// Reels: every photo posted to the Home family feed, full-screen,
/// swipe-vertically — the same posts and the same [HomeFeedRepository] as
/// Home, just a different way of moving through them. Liking here updates
/// the same post, so like counts stay consistent with Home.
class ReelsScreen extends StatefulWidget {
  const ReelsScreen({super.key, HomeFeedRepository? repository})
    : _repository = repository;

  final HomeFeedRepository? _repository;

  @override
  State<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends State<ReelsScreen> {
  late final HomeFeedRepository _repository =
      widget._repository ??
      SupabaseHomeFeedRepository(Supabase.instance.client);
  late Future<List<ReelItem>> _reels = _load();

  Future<List<ReelItem>> _load() async {
    final posts = await _repository.fetchPosts();
    return flattenPostsToReelItems(posts);
  }

  Future<void> _refresh() async {
    setState(() => _reels = _load());
    await _reels;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: FutureBuilder<List<ReelItem>>(
        future: _reels,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white),
            );
          }
          if (snapshot.hasError) {
            return _ReelsMessage(
              icon: Icons.cloud_off_outlined,
              title: 'Could not load reels.',
              subtitle: 'Pull down to try again.',
              onRefresh: _refresh,
            );
          }
          final reels = snapshot.data ?? const [];
          if (reels.isEmpty) {
            return _ReelsMessage(
              icon: Icons.photo_camera_outlined,
              title: 'No photos yet.',
              subtitle:
                  'Photos posted to Family Updates on Home appear here, '
                  'full-screen.',
              onRefresh: _refresh,
            );
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            color: Colors.white,
            backgroundColor: Colors.black,
            child: PageView.builder(
              scrollDirection: Axis.vertical,
              itemCount: reels.length,
              itemBuilder: (context, index) => _ReelPage(
                reel: reels[index],
                repository: _repository,
                onChanged: _refresh,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ReelPage extends StatefulWidget {
  const _ReelPage({
    required this.reel,
    required this.repository,
    required this.onChanged,
  });

  final ReelItem reel;
  final HomeFeedRepository repository;
  final Future<void> Function() onChanged;

  @override
  State<_ReelPage> createState() => _ReelPageState();
}

class _ReelPageState extends State<_ReelPage> {
  var _liking = false;

  Future<void> _toggleLike() async {
    if (_liking) return;
    setState(() => _liking = true);
    try {
      await widget.repository.toggleLike(widget.reel.post);
      await widget.onChanged();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not update like.')));
    } finally {
      if (mounted) setState(() => _liking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.reel.post;

    return Stack(
      fit: StackFit.expand,
      children: [
        CachedNetworkImage(
          imageUrl: widget.reel.mediaUrl,
          fit: BoxFit.cover,
          memCacheWidth: 1200,
          fadeInDuration: const Duration(milliseconds: 120),
          errorWidget: (context, url, error) => const ColoredBox(
            color: Color(0xFF1A1A1A),
            child: Center(
              child: Icon(
                Icons.broken_image_outlined,
                color: Colors.white54,
                size: 48,
              ),
            ),
          ),
          placeholder: (context, url) => const ColoredBox(
            color: Colors.black,
            child: Center(
              child: CircularProgressIndicator(color: Colors.white54),
            ),
          ),
        ),
        // Bottom gradient so white overlay text stays readable over any photo.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black87],
              stops: [0.6, 1.0],
            ),
          ),
        ),
        if (widget.reel.mediaCount > 1)
          Positioned(
            top: VanamSpacing.md,
            right: VanamSpacing.md,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: VanamSpacing.sm,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${widget.reel.mediaIndex + 1}/${widget.reel.mediaCount}',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
        Positioned(
          left: VanamSpacing.md,
          right: 72,
          bottom: VanamSpacing.xl,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  MemberAvatar(name: post.authorName, size: 32),
                  const SizedBox(width: VanamSpacing.sm),
                  Expanded(
                    child: Text(
                      post.authorName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (post.caption.isNotEmpty) ...[
                const SizedBox(height: VanamSpacing.xs),
                Text(
                  post.caption,
                  style: const TextStyle(color: Colors.white),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
        Positioned(
          right: VanamSpacing.md,
          bottom: VanamSpacing.xl,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: _liking ? null : _toggleLike,
                icon: Icon(
                  post.likedByMe
                      ? Icons.favorite_rounded
                      : Icons.favorite_border,
                  color: post.likedByMe ? Colors.redAccent : Colors.white,
                  size: 30,
                ),
              ),
              Text(
                '${post.likeCount}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReelsMessage extends StatelessWidget {
  const _ReelsMessage({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onRefresh,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: Colors.white,
      backgroundColor: Colors.black,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.8,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(VanamSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: Colors.white54, size: 42),
                    const SizedBox(height: VanamSpacing.md),
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: VanamSpacing.xs),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
