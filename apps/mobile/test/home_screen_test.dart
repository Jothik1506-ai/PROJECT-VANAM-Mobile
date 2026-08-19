import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:vanam_mobile/home/home_feed_repository.dart';
import 'package:vanam_mobile/models/post.dart';
import 'package:vanam_mobile/notifications/in_app_notification.dart';
import 'package:vanam_mobile/notifications/in_app_notification_service.dart';
import 'package:vanam_mobile/screens/home_screen.dart';
import 'package:vanam_mobile/theme/tokens.dart';

Widget _wrap(Widget child) =>
    MaterialApp(theme: buildVanamTheme(), home: child);

void main() {
  testWidgets('Home shows VANAM web page updates', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const HomeScreen(
          repository: _FakeHomeFeedRepository(),
          notificationRepository: _FakeNotificationRepository(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Web Page Updates'), findsOneWidget);
    expect(find.text('Varalakshmi Vratham'), findsOneWidget);
    expect(find.byIcon(Icons.open_in_new), findsOneWidget);
    expect(find.text('No family posts yet.'), findsOneWidget);
  });
}

class _FakeNotificationRepository implements NotificationRepository {
  const _FakeNotificationRepository();

  @override
  Future<List<InAppNotification>> fetchNotifications() async => const [];

  @override
  Future<int> unreadCount() async => 0;

  @override
  Future<void> markAllRead() async {}
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

  @override
  Future<void> toggleLike(Post post) async {}

  @override
  Future<List<PostComment>> fetchComments(Post post) async => const [];

  @override
  Future<void> addComment({required Post post, required String body}) async {}
}
