class Post {
  const Post({
    required this.id,
    required this.authorName,
    required this.createdAt,
    required this.caption,
    required this.likeCount,
    required this.commentCount,
    required this.mediaUrls,
  });

  final String id;
  final String authorName;
  final DateTime createdAt;
  final String caption;
  final int likeCount;
  final int commentCount;
  final List<String> mediaUrls;

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
    return Post(
      id: json['id'] as String? ?? '',
      authorName: json['author_name'] as String? ?? 'Family Member',
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      caption: json['caption'] as String? ?? '',
      likeCount: json['like_count'] as int? ?? 0,
      commentCount: json['comment_count'] as int? ?? 0,
      mediaUrls: media is List
          ? media.whereType<String>().toList(growable: false)
          : const [],
    );
  }
}

const mockPosts = <Post>[];
