import 'post.dart';

/// One full-screen "reel" page: a single photo from a Home family post,
/// plus which position it is within that post's photo set (so a post with
/// 3 photos becomes 3 reel pages, each still pointing back at the same
/// [post] for likes/author/caption).
class ReelItem {
  const ReelItem({
    required this.post,
    required this.mediaUrl,
    required this.mediaIndex,
    required this.mediaCount,
  });

  final Post post;
  final String mediaUrl;
  final int mediaIndex;
  final int mediaCount;
}

/// Text-only posts have nothing to show full-screen, so they're skipped —
/// Reels is a photo feed, not a duplicate of the Home text feed.
List<ReelItem> flattenPostsToReelItems(List<Post> posts) {
  final items = <ReelItem>[];
  for (final post in posts) {
    final photoUrls = post.mediaItems.isNotEmpty
        ? post.mediaItems.where((m) => !m.isVideo).map((m) => m.url).toList()
        : post.mediaUrls;
    for (var i = 0; i < photoUrls.length; i++) {
      items.add(
        ReelItem(
          post: post,
          mediaUrl: photoUrls[i],
          mediaIndex: i,
          mediaCount: photoUrls.length,
        ),
      );
    }
  }
  return items;
}
