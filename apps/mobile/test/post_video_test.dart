import 'package:flutter_test/flutter_test.dart';
import 'package:vanam_mobile/models/post.dart';
import 'package:vanam_mobile/models/reel_item.dart';
import 'package:vanam_mobile/models/web_update.dart';

void main() {
  group('Video media model and feed integration', () {
    test('Post.fromJson parses photo and video media_items correctly', () {
      final json = {
        'id': 'post-123',
        'author_id': 'user-456',
        'author_name': 'Jothik',
        'created_at': '2026-09-12T10:00:00Z',
        'caption': 'Festival celebration video',
        'like_count': 5,
        'comment_count': 2,
        'is_mine': true,
        'liked_by_me': false,
        'media_items': [
          {
            'url': 'https://example.com/video1.mp4',
            'media_type': 'video',
            'duration_seconds': 42,
          },
        ],
      };

      final post = Post.fromJson(json);

      expect(post.id, 'post-123');
      expect(post.authorName, 'Jothik');
      expect(post.hasVideo, isTrue);
      expect(post.videoItem, isNotNull);
      expect(post.videoItem!.url, 'https://example.com/video1.mp4');
      expect(post.videoItem!.isVideo, isTrue);
      expect(post.videoItem!.durationSeconds, 42);
      expect(post.mediaUrls, ['https://example.com/video1.mp4']);
    });

    test('flattenPostsToReelItems excludes video posts from Reels feed', () {
      final videoPost = Post(
        id: 'vid-1',
        authorId: 'user-1',
        authorName: 'Jothik',
        createdAt: DateTime.now(),
        caption: 'Video clip',
        likeCount: 0,
        commentCount: 0,
        mediaUrls: ['https://example.com/video.mp4'],
        isMine: true,
        likedByMe: false,
        mediaItems: const [
          PostMediaItem(
            url: 'https://example.com/video.mp4',
            type: PostMediaType.video,
            durationSeconds: 30,
          ),
        ],
      );

      final photoPost = Post(
        id: 'photo-1',
        authorId: 'user-2',
        authorName: 'Amma',
        createdAt: DateTime.now(),
        caption: 'Photo memories',
        likeCount: 2,
        commentCount: 1,
        mediaUrls: ['https://example.com/photo1.jpg', 'https://example.com/photo2.jpg'],
        isMine: false,
        likedByMe: true,
        mediaItems: const [
          PostMediaItem(
            url: 'https://example.com/photo1.jpg',
            type: PostMediaType.photo,
          ),
          PostMediaItem(
            url: 'https://example.com/photo2.jpg',
            type: PostMediaType.photo,
          ),
        ],
      );

      final reelItems = flattenPostsToReelItems([videoPost, photoPost]);

      // Video post should NOT produce any reel items
      expect(reelItems.length, 2);
      expect(reelItems.every((item) => item.post.id == 'photo-1'), isTrue);
      expect(reelItems[0].mediaUrl, 'https://example.com/photo1.jpg');
      expect(reelItems[1].mediaUrl, 'https://example.com/photo2.jpg');
    });

    test('webUpdates includes Vinayaka Vratham as third update entry', () {
      expect(webUpdates.length, 3);
      final vinayaka = webUpdates.firstWhere(
        (u) => u.title == 'Vinayaka Vratham',
      );
      expect(vinayaka.path, 'Vinayaka%20vratham/');
      expect(vinayaka.status, 'Ready for launch');
      expect(vinayaka.iconLabel, 'Vratham');
      expect(vinayaka.description, contains('Telugu puja materials'));
    });
  });
}

