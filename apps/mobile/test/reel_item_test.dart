import 'package:flutter_test/flutter_test.dart';
import 'package:vanam_mobile/models/post.dart';
import 'package:vanam_mobile/models/reel_item.dart';

Post _post({
  required String id,
  List<String> mediaUrls = const [],
  String caption = '',
}) {
  return Post(
    id: id,
    authorId: 'author-$id',
    authorName: 'Author $id',
    createdAt: DateTime(2026, 8, 19),
    caption: caption,
    likeCount: 0,
    commentCount: 0,
    mediaUrls: mediaUrls,
    isMine: false,
    likedByMe: false,
  );
}

void main() {
  group('flattenPostsToReelItems', () {
    test('one photo becomes one reel item', () {
      final items = flattenPostsToReelItems([
        _post(id: '1', mediaUrls: const ['https://x/1.jpg']),
      ]);

      expect(items, hasLength(1));
      expect(items.single.mediaUrl, 'https://x/1.jpg');
      expect(items.single.mediaIndex, 0);
      expect(items.single.mediaCount, 1);
    });

    test('a post with multiple photos becomes one reel item per photo, in order', () {
      final items = flattenPostsToReelItems([
        _post(id: '1', mediaUrls: const ['https://x/a.jpg', 'https://x/b.jpg']),
      ]);

      expect(items, hasLength(2));
      expect(items[0].mediaUrl, 'https://x/a.jpg');
      expect(items[0].mediaIndex, 0);
      expect(items[1].mediaUrl, 'https://x/b.jpg');
      expect(items[1].mediaIndex, 1);
      expect(items.every((i) => i.mediaCount == 2), isTrue);
    });

    test('a text-only post (no photos) contributes zero reel items', () {
      final items = flattenPostsToReelItems([
        _post(id: '1', caption: 'no photo here'),
        _post(id: '2', mediaUrls: const ['https://x/only.jpg']),
      ]);

      expect(items, hasLength(1));
      expect(items.single.post.id, '2');
    });

    test('an empty post list produces an empty reel list', () {
      expect(flattenPostsToReelItems(const []), isEmpty);
    });
  });
}
