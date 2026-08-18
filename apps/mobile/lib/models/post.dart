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
///
/// Intentionally empty: no fabricated author names. See
/// mockFamilyMembers for why relation-based placeholder names were removed.
const mockPosts = <Post>[];
