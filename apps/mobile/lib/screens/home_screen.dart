import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../chat/direct_conversation.dart';
import '../chat/supabase_chat_sync.dart';
import '../chat/supabase_direct_chat_sync.dart';
import '../home/home_feed_repository.dart';
import '../models/family_member.dart';
import '../models/post.dart';
import '../models/web_update.dart';
import '../notifications/in_app_notification_service.dart';
import '../theme/tokens.dart';
import '../widgets/member_avatar.dart';
import '../widgets/post_card.dart';
import '../widgets/story_avatar.dart';
import '../widgets/vanam_logo.dart';
import '../widgets/web_update_card.dart';
import 'notifications_screen.dart';

/// Home feed screen.
/// Web updates are sourced from the current VANAM web hub list. Family posts
/// are still local preview data until the posting backend is connected.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    HomeFeedRepository? repository,
    NotificationRepository? notificationRepository,
    this.isAdmin = false,
  }) : _repository = repository,
       _notificationRepository = notificationRepository;

  final HomeFeedRepository? _repository;
  final NotificationRepository? _notificationRepository;
  final bool isAdmin;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final HomeFeedRepository _repository =
      widget._repository ??
      SupabaseHomeFeedRepository(Supabase.instance.client);
  late final NotificationRepository _notificationRepository =
      widget._notificationRepository ?? inAppNotificationService;
  late Future<List<Post>> _posts = _repository.fetchPosts();
  late Future<int> _unreadNotifications = _notificationRepository.unreadCount();

  Future<void> _refresh() async {
    setState(() {
      _posts = _repository.fetchPosts();
      _unreadNotifications = _notificationRepository.unreadCount();
    });
    await _posts;
  }

  Future<void> _openNotifications() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
    if (!mounted) return;
    setState(() {
      _unreadNotifications = _notificationRepository.unreadCount();
    });
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
            _HomeAppBar(
              unreadNotifications: _unreadNotifications,
              onOpenNotifications: _openNotifications,
            ),
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

class _InAppShareSheet extends StatefulWidget {
  const _InAppShareSheet({required this.post});

  final Post post;

  @override
  State<_InAppShareSheet> createState() => _InAppShareSheetState();
}

class _InAppShareSheetState extends State<_InAppShareSheet> {
  late final Future<List<DirectConversation>> _directConversations =
      SupabaseDirectChatSync(Supabase.instance.client).listConversations();
  var _sharingTarget = '';

  String get _shareText {
    final caption = widget.post.caption.trim();
    final label = caption.isEmpty
        ? 'Photo post by ${widget.post.authorName}'
        : caption;
    return [
      'Shared from Home',
      '${widget.post.authorName}: $label',
      if (widget.post.mediaUrls.isNotEmpty)
        '${widget.post.mediaUrls.length} photo${widget.post.mediaUrls.length == 1 ? '' : 's'} in this post',
    ].join('\n');
  }

  Future<void> _shareToFamilyGroup() async {
    await _runShare('family-group', () {
      return SupabaseChatSync(
        Supabase.instance.client,
      ).sendMessage(text: _shareText);
    });
  }

  Future<void> _shareToDirect(DirectConversation conversation) async {
    await _runShare(conversation.conversationId, () {
      return SupabaseDirectChatSync(Supabase.instance.client).sendMessage(
        conversationId: conversation.conversationId,
        text: _shareText,
      );
    });
  }

  Future<void> _runShare(String target, Future<void> Function() send) async {
    if (_sharingTarget.isNotEmpty) return;
    setState(() => _sharingTarget = target);
    try {
      await send();
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Post shared in Vanam.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not share post: $error')));
    } finally {
      if (mounted) setState(() => _sharingTarget = '');
    }
  }

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
            'Send this post into an encrypted family or direct chat.',
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
              widget.post.caption.isEmpty
                  ? 'Photo post by ${widget.post.authorName}'
                  : widget.post.caption,
              style: TextStyle(color: palette.brandStrong),
            ),
          ),
          const SizedBox(height: VanamSpacing.md),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.groups_outlined),
            title: const Text('Family Group'),
            subtitle: const Text('Share with everyone'),
            trailing: _sharingTarget == 'family-group'
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_outlined),
            onTap: _sharingTarget.isEmpty ? _shareToFamilyGroup : null,
          ),
          FutureBuilder<List<DirectConversation>>(
            future: _directConversations,
            builder: (context, snapshot) {
              final conversations = snapshot.data ?? const [];
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(VanamSpacing.md),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (conversations.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.only(top: VanamSpacing.sm),
                  child: Text(
                    'No direct chats available yet.',
                    style: TextStyle(color: palette.inkMuted),
                  ),
                );
              }
              return Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: conversations.length,
                  itemBuilder: (context, index) {
                    final conversation = conversations[index];
                    final isSharing =
                        _sharingTarget == conversation.conversationId;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: MemberAvatar(name: conversation.otherDisplayName),
                      title: Text(conversation.otherDisplayName),
                      subtitle: const Text('Direct chat'),
                      trailing: isSharing
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_outlined),
                      onTap: _sharingTarget.isEmpty
                          ? () => _shareToDirect(conversation)
                          : null,
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _HomeAppBar extends StatelessWidget {
  const _HomeAppBar({
    required this.unreadNotifications,
    required this.onOpenNotifications,
  });

  final Future<int> unreadNotifications;
  final VoidCallback onOpenNotifications;

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
          FutureBuilder<int>(
            future: unreadNotifications,
            builder: (context, snapshot) {
              final count = snapshot.data ?? 0;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    onPressed: onOpenNotifications,
                    icon: Icon(
                      Icons.notifications_none_rounded,
                      color: palette.ink,
                    ),
                    tooltip: 'Notifications',
                  ),
                  if (count > 0)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        constraints: const BoxConstraints(
                          minWidth: 18,
                          minHeight: 18,
                        ),
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: palette.danger,
                          shape: count > 9
                              ? BoxShape.rectangle
                              : BoxShape.circle,
                          borderRadius: count > 9
                              ? BorderRadius.circular(999)
                              : null,
                        ),
                        child: Text(
                          count > 99 ? '99+' : '$count',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
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
