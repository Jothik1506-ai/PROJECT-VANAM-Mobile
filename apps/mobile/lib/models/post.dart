class Post {
  const Post({
    required this.authorName,
    required this.timeAgo,
    required this.caption,
    required this.likeCount,
    required this.commentCount,
    required this.mood,
  });

  final String authorName;
  final String timeAgo;
  final String caption;
  final int likeCount;
  final int commentCount;
  final String mood;
}

/// Mock data for UI preview only — not wired to any backend.
/// See ARCHITECTURE.md Section 9: Home Feed is Phase 3, not V1.
const mockPosts = [
  Post(
    authorName: 'Amma',
    timeAgo: '2 hours ago',
    caption:
        'Sunday lunch at home — everyone finally together after so long! 🌿',
    likeCount: 12,
    commentCount: 4,
    mood: 'Family Lunch',
  ),
  Post(
    authorName: 'Nanna',
    timeAgo: 'Yesterday',
    caption: 'Evening walk in the garden. Peaceful.',
    likeCount: 8,
    commentCount: 2,
    mood: 'Garden Walk',
  ),
];
