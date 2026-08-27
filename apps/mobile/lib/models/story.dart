/// One photo status update — WhatsApp-style, disappears 24 hours after
/// posting. Grouped client-side by [authorId] into one "ring" per person
/// in the Home story row (see StoryRing/StoryGroup below).
class Story {
  const Story({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.mediaUrl,
    required this.createdAt,
    required this.expiresAt,
    required this.viewedByMe,
  });

  final String id;
  final String authorId;
  final String authorName;
  final String mediaUrl;
  final DateTime createdAt;
  final DateTime expiresAt;
  final bool viewedByMe;

  factory Story.fromJson(Map<String, dynamic> json) {
    return Story(
      id: json['story_id'] as String? ?? '',
      authorId: json['author_id'] as String? ?? '',
      authorName: json['author_name'] as String? ?? 'Family Member',
      mediaUrl: json['media_url'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      expiresAt:
          DateTime.tryParse(json['expires_at'] as String? ?? '') ??
          DateTime.now(),
      viewedByMe: json['viewed_by_me'] as bool? ?? false,
    );
  }
}

/// All of one person's currently-active stories, oldest first (so the
/// viewer plays them in the order they were posted — same as WhatsApp).
class StoryGroup {
  const StoryGroup({
    required this.authorId,
    required this.authorName,
    required this.stories,
  });

  final String authorId;
  final String authorName;
  final List<Story> stories;

  bool get hasUnseen => stories.any((s) => !s.viewedByMe);

  /// Groups a flat list (as returned by list_active_stories, already
  /// ordered author_id, created_at asc) into one entry per author,
  /// preserving that order.
  static List<StoryGroup> group(List<Story> stories) {
    final groups = <String, List<Story>>{};
    final order = <String>[];
    for (final story in stories) {
      if (!groups.containsKey(story.authorId)) order.add(story.authorId);
      groups.putIfAbsent(story.authorId, () => []).add(story);
    }
    return order
        .map(
          (authorId) => StoryGroup(
            authorId: authorId,
            authorName: groups[authorId]!.first.authorName,
            stories: groups[authorId]!,
          ),
        )
        .toList(growable: false);
  }
}
