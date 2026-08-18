import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:vanam_mobile/home/home_feed_repository.dart';
import 'package:vanam_mobile/models/post.dart';
import 'package:vanam_mobile/screens/home_screen.dart';
import 'package:vanam_mobile/theme/tokens.dart';

Widget _wrap(Widget child) =>
    MaterialApp(theme: buildVanamTheme(), home: child);

void main() {
  testWidgets('Home shows VANAM web page updates', (tester) async {
    await tester.pumpWidget(
      _wrap(const HomeScreen(repository: _FakeHomeFeedRepository())),
    );
    await tester.pump();

    expect(find.text('Web Page Updates'), findsOneWidget);
    expect(find.text('Varalakshmi Vratham'), findsOneWidget);
    expect(find.byIcon(Icons.open_in_new), findsOneWidget);
    expect(find.text('No family posts yet.'), findsOneWidget);
  });
}

class _FakeHomeFeedRepository implements HomeFeedRepository {
  const _FakeHomeFeedRepository();

  @override
  Future<List<Post>> fetchPosts() async => const [];

  @override
  Future<void> createPost({
    required String caption,
    required List<XFile> photos,
  }) async {}

  @override
  Future<void> deletePost(Post post) async {}
}
