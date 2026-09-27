enum PostMediaType {
  photo,
  video;

  static PostMediaType fromString(String? value) {
    if (value == 'video') return PostMediaType.video;
    return PostMediaType.photo;
  }
}

class PostMediaItem {
  const PostMediaItem({
    required this.url,
    this.type = PostMediaType.photo,
    this.durationSeconds,
    this.thumbnailUrl,
  });

  final String url;
  final PostMediaType type;
  final int? durationSeconds;
  final String? thumbnailUrl;

  bool get isVideo => type == PostMediaType.video;
  bool get isPhoto => type == PostMediaType.photo;

  factory PostMediaItem.fromJson(Map<String, dynamic> json) {
    return PostMediaItem(
      url: json['url'] as String? ?? '',
      type: PostMediaType.fromString(json['media_type'] as String?),
      durationSeconds: json['duration_seconds'] as int?,
      thumbnailUrl: json['thumbnail_url'] as String?,
    );
  }
}

class Post {
  const Post({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.createdAt,
    required this.caption,
    required this.likeCount,
    required this.commentCount,
    required this.mediaUrls,
    required this.isMine,
    required this.likedByMe,
    this.mediaItems = const [],
  });

  final String id;
  final String authorId;
  final String authorName;
  final DateTime createdAt;
  final String caption;
  final int likeCount;
  final int commentCount;
  final List<String> mediaUrls;
  final bool isMine;
  final bool likedByMe;
  final List<PostMediaItem> mediaItems;

  bool get hasVideo => mediaItems.any((m) => m.isVideo);
  PostMediaItem? get videoItem {
    for (final m in mediaItems) {
      if (m.isVideo) return m;
    }
    return null;
  }

  String get timeAgo {
    final difference = DateTime.now().difference(createdAt);
    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inHours < 1) return '${difference.inMinutes}m ago';
    if (difference.inDays < 1) return '${difference.inHours}h ago';
    if (difference.inDays < 7) return '${difference.inDays}d ago';
    return '${createdAt.day}/${createdAt.month}/${createdAt.year}';
  }

  factory Post.fromJson(Map<String, dynamic> json) {
    final media = json['media_urls'];
    final rawItems = json['media_items'];
    final items = <PostMediaItem>[];
    if (rawItems is List) {
      for (final item in rawItems) {
        if (item is Map<String, dynamic>) {
          items.add(PostMediaItem.fromJson(item));
        }
      }
    }
    final urls = media is List
        ? media.whereType<String>().toList(growable: false)
        : (items.isNotEmpty
            ? items.map((m) => m.url).toList(growable: false)
            : const <String>[]);

    return Post(
      id: json['id'] as String? ?? '',
      authorId: json['author_id'] as String? ?? '',
      authorName: json['author_name'] as String? ?? 'Family Member',
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      caption: json['caption'] as String? ?? '',
      likeCount: json['like_count'] as int? ?? 0,
      commentCount: json['comment_count'] as int? ?? 0,
      mediaUrls: urls,
      mediaItems: items,
      isMine: json['is_mine'] as bool? ?? false,
      likedByMe: json['liked_by_me'] as bool? ?? false,
    );
  }
}

class PostComment {
  const PostComment({
    required this.id,
    required this.authorName,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final String authorName;
  final String body;
  final DateTime createdAt;

  String get timeAgo {
    final difference = DateTime.now().difference(createdAt);
    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inHours < 1) return '${difference.inMinutes}m ago';
    if (difference.inDays < 1) return '${difference.inHours}h ago';
    if (difference.inDays < 7) return '${difference.inDays}d ago';
    return '${createdAt.day}/${createdAt.month}/${createdAt.year}';
  }

  factory PostComment.fromJson(Map<String, dynamic> json) {
    return PostComment(
      id: json['id'] as String? ?? '',
      authorName: json['author_name'] as String? ?? 'Family Member',
      body: json['body'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

const mockPosts = <Post>[];
