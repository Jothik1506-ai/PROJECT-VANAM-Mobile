import 'package:flutter/material.dart';

import '../notifications/in_app_notification.dart';
import '../notifications/in_app_notification_service.dart';
import '../theme/tokens.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late Future<List<InAppNotification>> _notifications = inAppNotificationService
      .fetchNotifications();

  Future<void> _refresh() async {
    setState(() {
      _notifications = inAppNotificationService.fetchNotifications();
    });
    await _notifications;
  }

  Future<void> _markAllRead() async {
    await inAppNotificationService.markAllRead();
    await _refresh();
  }

  @override
  void initState() {
    super.initState();
    inAppNotificationService.markAllRead().then((_) {
      if (mounted) _refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.vanam;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(onPressed: _markAllRead, child: const Text('Mark read')),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<InAppNotification>>(
          future: _notifications,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final notifications = snapshot.data!;
            if (notifications.isEmpty) {
              return ListView(
                children: [
                  SizedBox(height: MediaQuery.sizeOf(context).height * 0.22),
                  Icon(
                    Icons.notifications_none_rounded,
                    color: palette.brand,
                    size: 44,
                  ),
                  const SizedBox(height: VanamSpacing.md),
                  Center(
                    child: Text(
                      'No notifications yet.',
                      style: TextStyle(color: palette.inkMuted),
                    ),
                  ),
                ],
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.all(VanamSpacing.md),
              itemCount: notifications.length,
              separatorBuilder: (_, _) => Divider(color: palette.line),
              itemBuilder: (context, index) {
                final item = notifications[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: item.isUnread
                        ? palette.brand
                        : palette.noticeSurface,
                    child: Icon(
                      Icons.family_restroom_outlined,
                      color: item.isUnread ? Colors.white : palette.brand,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    item.title,
                    style: TextStyle(
                      color: palette.ink,
                      fontWeight: item.isUnread
                          ? FontWeight.w800
                          : FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(item.body),
                  trailing: Text(
                    item.timeAgo,
                    style: TextStyle(color: palette.inkMuted, fontSize: 11),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
