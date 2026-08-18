import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../home/home_feed_repository.dart';
import '../models/family_member.dart';
import '../models/post.dart';
import '../models/web_update.dart';
import '../theme/tokens.dart';
import '../widgets/member_avatar.dart';
import '../widgets/post_card.dart';
import '../widgets/story_avatar.dart';
import '../widgets/vanam_logo.dart';
import '../widgets/web_update_card.dart';

/// Home feed screen.
/// Web updates are sourced from the current VANAM web hub list. Family posts
/// are still local preview data until the posting backend is connected.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    HomeFeedRepository? repository,
    this.isAdmin = false,
  }) : _repository = repository;

  final HomeFeedRepository? _repository;
  final bool isAdmin;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final HomeFeedRepository _repository =
      widget._repository ??
      SupabaseHomeFeedRepository(Supabase.instance.client);
  late Future<List<Post>> _posts = _repository.fetchPosts();

  Future<void> _refresh() async {
    setState(() {
      _posts = _repository.fetchPosts();
    });
    await _posts;
  }

  Future<void> _showCreatePost() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _CreatePostSheet(repository: _repository),
    );
    if (created == true) {
      await _refresh();
    }
  }

  Future<void> _deletePost(Post post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete post?'),
        content: const Text(
          'This permanently removes the post and its photos from Vanam.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _repository.deletePost(post);
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Post deleted.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not delete post: $error')));
    }
  }

  Future<void> _toggleLike(Post post) async {
    try {
      await _repository.toggleLike(post);
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not update like: $error')));
    }
  }

  Future<void> _showComments(Post post) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _CommentsSheet(post: post, repository: _repository),
    );
    if (changed == true) {
      await _refresh();
    }
  }

  void _showShare(Post post) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (context) => _InAppShareSheet(post: post),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.vanam;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _HomeAppBar(),
            Divider(height: 1, color: palette.line),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(VanamSpacing.md),
                children: [
                  SizedBox(
                    height: 88,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        const AddMemberAvatar(),
                        for (final member in mockFamilyMembers) ...[
                          const SizedBox(width: VanamSpacing.md),
                          StoryAvatar(name: member.name),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: VanamSpacing.lg),
                  const _SectionHeader(
                    title: 'Web Page Updates',
                    subtitle: 'Latest VANAM web pages available for reading.',
                  ),
                  const SizedBox(height: VanamSpacing.md),
                  const RotatingWebUpdateCard(updates: webUpdates),
                  const SizedBox(height: VanamSpacing.md),
                  _SectionHeader(
                    title: 'Family Updates',
                    subtitle: 'Share photos and notes with the family.',
                    action: IconButton.filled(
                      onPressed: _showCreatePost,
                      icon: const Icon(Icons.add),
                      tooltip: 'Create post',
                    ),
                  ),
                  const SizedBox(height: VanamSpacing.md),
                  FutureBuilder<List<Post>>(
                    future: _posts,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(VanamSpacing.lg),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }
                      if (snapshot.hasError) {
                        return _FeedError(onRetry: _refresh);
                      }
                      final posts = snapshot.data ?? mockPosts;
                      if (posts.isEmpty) {
                        return _EmptyFamilyUpdates(onCreate: _showCreatePost);
                      }
                      return Column(
                        children: [
                          for (final post in posts)
                            RepaintBoundary(
                              child: PostCard(
                                post: post,
                                canDelete: widget.isAdmin || post.isMine,
                                onDelete: () => _deletePost(post),
                                onLike: () => _toggleLike(post),
                                onComment: () => _showComments(post),
                                onShare: () => _showShare(post),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentsSheet extends StatefulWidget {
  const _CommentsSheet({required this.post, required this.repository});

  final Post post;
  final HomeFeedRepository repository;

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final _controller = TextEditingController();
  late Future<List<PostComment>> _comments = widget.repository.fetchComments(
    widget.post,
  );
  var _saving = false;
  var _changed = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _saving = true);
    try {
      await widget.repository.addComment(
        post: widget.post,
        body: _controller.text,
      );
      _controller.clear();
      setState(() {
        _changed = true;
        _comments = widget.repository.fetchComments(widget.post);
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not add comment: $error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.vanam;
    return Padding(
      padding: EdgeInsets.only(
        left: VanamSpacing.md,
        right: VanamSpacing.md,
        top: VanamSpacing.md,
        bottom: MediaQuery.viewInsetsOf(context).bottom + VanamSpacing.md,
      ),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Comments',
                    style: TextStyle(
                      color: palette.ink,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(_changed),
                  icon: const Icon(Icons.close),
                  tooltip: 'Close comments',
                ),
              ],
            ),
            const SizedBox(height: VanamSpacing.md),
            Expanded(
              child: FutureBuilder<List<PostComment>>(
                future: _comments,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final comments = snapshot.data!;
                  if (comments.isEmpty) {
                    return Center(
                      child: Text(
                        'No comments yet.',
                        style: TextStyle(color: palette.inkMuted),
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: comments.length,
                    separatorBuilder: (_, _) => Divider(color: palette.line),
                    itemBuilder: (context, index) {
                      final comment = comments[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: MemberAvatar(
                          name: comment.authorName,
                          size: 34,
                        ),
                        title: Text(
                          comment.authorName,
                          style: TextStyle(
                            color: palette.ink,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(comment.body),
                        trailing: Text(
                          comment.timeAgo,
                          style: TextStyle(
                            color: palette.inkMuted,
                            fontSize: 11,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: VanamSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: 'Add a comment',
                    ),
                    minLines: 1,
                    maxLines: 3,
                  ),
                ),
                const SizedBox(width: VanamSpacing.sm),
                IconButton.filled(
                  onPressed: _saving ? null : _send,
                  icon: const Icon(Icons.send),
                  tooltip: 'Send comment',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InAppShareSheet extends StatelessWidget {
  const _InAppShareSheet({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    final palette = context.vanam;
    return Padding(
      padding: const EdgeInsets.all(VanamSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Share in Vanam',
            style: TextStyle(
              color: palette.ink,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: VanamSpacing.sm),
          Text(
            'In-app sharing is ready for the family group flow. Direct share to chats will be connected when post-to-chat is added.',
            style: TextStyle(color: palette.inkMuted),
          ),
          const SizedBox(height: VanamSpacing.md),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(VanamSpacing.md),
            decoration: BoxDecoration(
              color: palette.noticeSurface,
              borderRadius: BorderRadius.circular(VanamRadii.card),
              border: Border.all(color: palette.noticeBorder),
            ),
            child: Text(
              post.caption.isEmpty
                  ? 'Photo post by ${post.authorName}'
                  : post.caption,
              style: TextStyle(color: palette.brandStrong),
            ),
          ),
          const SizedBox(height: VanamSpacing.md),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}

class _HomeAppBar extends StatelessWidget {
  const _HomeAppBar();

  @override
  Widget build(BuildContext context) {
    final palette = context.vanam;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: VanamSpacing.md,
        vertical: VanamSpacing.sm,
      ),
      child: Row(
        children: [
          const VanamLogo(size: 40),
          const SizedBox(width: VanamSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Vanam',
                style: TextStyle(
                  color: palette.ink,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
              Text(
                'Family Hub',
                style: TextStyle(fontSize: 12, color: palette.inkMuted),
              ),
            ],
          ),
          const Spacer(),
          IconButton(
            onPressed: () {},
            icon: Icon(Icons.search, color: palette.ink),
          ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                onPressed: () {},
                icon: Icon(
                  Icons.notifications_none_rounded,
                  color: palette.ink,
                ),
              ),
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: palette.danger,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
    this.action,
  });

  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final palette = context.vanam;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: palette.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(color: palette.inkMuted, fontSize: 13),
              ),
            ],
          ),
        ),
        ?action,
      ],
    );
  }
}

class _EmptyFamilyUpdates extends StatelessWidget {
  const _EmptyFamilyUpdates({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final palette = context.vanam;
    return Container(
      padding: const EdgeInsets.all(VanamSpacing.lg),
      decoration: BoxDecoration(
        color: palette.surfaceCard,
        borderRadius: BorderRadius.circular(VanamRadii.card),
        border: Border.all(color: palette.line),
      ),
      child: Column(
        children: [
          Icon(Icons.post_add_rounded, color: palette.brand, size: 30),
          const SizedBox(height: VanamSpacing.sm),
          Text(
            'No family posts yet.',
            style: TextStyle(
              color: palette.ink,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: VanamSpacing.xs),
          Text(
            'Create the first post with photos or a short note.',
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.inkMuted, height: 1.3),
          ),
          const SizedBox(height: VanamSpacing.md),
          ElevatedButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('Create Post'),
          ),
        ],
      ),
    );
  }
}

class _FeedError extends StatelessWidget {
  const _FeedError({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = context.vanam;
    return Container(
      padding: const EdgeInsets.all(VanamSpacing.lg),
      decoration: BoxDecoration(
        color: palette.surfaceCard,
        borderRadius: BorderRadius.circular(VanamRadii.card),
        border: Border.all(color: palette.line),
      ),
      child: Column(
        children: [
          Icon(Icons.cloud_off_outlined, color: palette.danger),
          const SizedBox(height: VanamSpacing.sm),
          Text(
            'Could not load posts.',
            style: TextStyle(color: palette.ink, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: VanamSpacing.sm),
          TextButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}

class _CreatePostSheet extends StatefulWidget {
  const _CreatePostSheet({required this.repository});

  final HomeFeedRepository repository;

  @override
  State<_CreatePostSheet> createState() => _CreatePostSheetState();
}

class _CreatePostSheetState extends State<_CreatePostSheet> {
  final _caption = TextEditingController();
  final _picker = ImagePicker();
  var _photos = <XFile>[];
  var _saving = false;
  String? _error;

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _pickPhotos() async {
    final picked = await _picker.pickMultiImage(imageQuality: 85);
    if (!mounted || picked.isEmpty) return;
    setState(() {
      _photos = picked
          .take(SupabaseHomeFeedRepository.maxPhotosPerPost)
          .toList();
      _error = picked.length > SupabaseHomeFeedRepository.maxPhotosPerPost
          ? 'Only the first 20 photos were added.'
          : null;
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.createPost(
        caption: _caption.text,
        photos: _photos,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.vanam;
    return Padding(
      padding: EdgeInsets.only(
        left: VanamSpacing.md,
        right: VanamSpacing.md,
        top: VanamSpacing.md,
        bottom: MediaQuery.viewInsetsOf(context).bottom + VanamSpacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Create Post',
            style: TextStyle(
              color: palette.ink,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: VanamSpacing.md),
          TextField(
            controller: _caption,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Caption',
              hintText: 'Write a family update',
            ),
          ),
          const SizedBox(height: VanamSpacing.md),
          OutlinedButton.icon(
            onPressed: _saving ? null : _pickPhotos,
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(
              _photos.isEmpty ? 'Add photos' : '${_photos.length} photos added',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: VanamSpacing.sm),
            Text(_error!, style: TextStyle(color: palette.danger)),
          ],
          const SizedBox(height: VanamSpacing.md),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Share Post'),
          ),
        ],
      ),
    );
  }
}
