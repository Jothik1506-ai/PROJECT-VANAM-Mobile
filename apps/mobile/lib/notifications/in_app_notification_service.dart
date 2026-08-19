import 'package:supabase_flutter/supabase_flutter.dart';

import 'in_app_notification.dart';

final inAppNotificationService = InAppNotificationService(
  Supabase.instance.client,
);

abstract class NotificationRepository {
  Future<List<InAppNotification>> fetchNotifications();

  Future<int> unreadCount();

  Future<void> markAllRead();
}

class EmptyNotificationRepository implements NotificationRepository {
  const EmptyNotificationRepository();

  @override
  Future<List<InAppNotification>> fetchNotifications() async => const [];

  @override
  Future<int> unreadCount() async => 0;

  @override
  Future<void> markAllRead() async {}
}

class InAppNotificationService implements NotificationRepository {
  InAppNotificationService(this._client);

  final SupabaseClient _client;

  @override
  Future<List<InAppNotification>> fetchNotifications() async {
    final rows = await _client
        .from('app_notifications')
        .select()
        .order('created_at', ascending: false)
        .limit(50);

    return rows
        .whereType<Map<String, dynamic>>()
        .map(InAppNotification.fromJson)
        .toList(growable: false);
  }

  @override
  Future<int> unreadCount() async {
    final rows = await _client
        .from('app_notifications')
        .select('id')
        .filter('read_at', 'is', null);
    return rows.length;
  }

  @override
  Future<void> markAllRead() async {
    await _client
        .from('app_notifications')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .filter('read_at', 'is', null);
  }
}
