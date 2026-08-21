import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../work_manager/work_manager_activity.dart';
import 'active_chat_tracker.dart';
import 'push_navigation.dart';

final pushNotificationService = PushNotificationService();

const _messagesChannel = AndroidNotificationChannel(
  'vanam_messages',
  'Vanam Messages',
  description: 'Private Vanam family message alerts',
  importance: Importance.high,
);

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

class PushNotificationService {
  PushNotificationService();

  // Deliberately not created until after Firebase.initializeApp() succeeds —
  // FirebaseMessaging.instance calls Firebase.app() internally and throws
  // ([core/no-app]) if grabbed any earlier. A previous version passed
  // FirebaseMessaging.instance into this constructor eagerly, which ran at
  // this class's top-level singleton's first access (main()'s first touch
  // of `pushNotificationService`, i.e. before initialize() had a chance to
  // call Firebase.initializeApp()) and crashed the app on every launch.
  FirebaseMessaging? _messaging;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  bool _firebaseReady = false;

  SupabaseClient get _client => Supabase.instance.client;

  Future<void> initialize() async {
    try {
      await Firebase.initializeApp();
      _messaging = FirebaseMessaging.instance;
      _firebaseReady = true;
    } catch (_) {
      _firebaseReady = false;
      return;
    }

    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_messagesChannel);
    await _localNotifications.initialize(
      // A status-bar notification icon must be a flat white silhouette —
      // the full-color launcher icon (ic_launcher) renders as a blank
      // circle once Android tints it. ic_stat_vanam is generated from the
      // brand logo for exactly this (see AndroidManifest.xml's comment).
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_stat_vanam'),
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        final data = jsonDecode(payload);
        if (data is Map<String, dynamic>) {
          PushNavigation.openFromPayload(data);
        }
      },
    );

    final messaging = _messaging!;
    await messaging.setAutoInitEnabled(true);
    await messaging.requestPermission(alert: true, badge: true, sound: true);

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      PushNavigation.openFromPayload(message.data);
    });
    FirebaseMessaging.onMessage.listen(_showForegroundNotification);

    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        PushNavigation.openFromPayload(initialMessage.data);
      });
    }
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    // Suppress the banner if this exact chat is already open — the message
    // is already appearing live via Realtime, so a system notification on
    // top of it is just noise (and, sent per-recipient-per-device, was
    // showing up even for the person actively reading the chat). Matches
    // the scope keys ChatDetailScreen registers in active_chat_tracker.dart.
    final chatType = message.data['chat_type']?.toString();
    final scope = chatType == 'family'
        ? ActiveChatTracker.familyGroupScope
        : chatType == 'direct'
        ? ActiveChatTracker.directScope(
            message.data['conversation_id']?.toString() ?? '',
          )
        : null;
    if (scope != null && activeChatTracker.isActive(scope)) return;

    await _localNotifications.show(
      id: message.hashCode,
      title: notification.title,
      body: notification.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _messagesChannel.id,
          _messagesChannel.name,
          channelDescription: _messagesChannel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  Future<void> ensureTokenRegistered() async {
    try {
      if (!_firebaseReady) return;
      final memberId = _client.auth.currentUser?.id;
      if (memberId == null) return;

      final token = await _messaging!.getToken();
      if (token == null || token.isEmpty) return;
      await _upsertToken(token);

      _messaging!.onTokenRefresh.listen((newToken) {
        if (newToken.isEmpty) return;
        unawaited(_upsertToken(newToken));
      });
    } catch (_) {
      // Push registration must never crash or restart the family app.
    }
  }

  Future<void> _upsertToken(String token) async {
    try {
      final memberId = _client.auth.currentUser?.id;
      if (memberId == null) return;

      final info = await PackageInfo.fromPlatform();
      await _client.rpc(
        'register_push_token',
        params: {
          'p_fcm_token': token,
          'p_platform': Platform.isAndroid ? 'android' : 'other',
          'p_app_version': '${info.version}+${info.buildNumber}',
        },
      );
      await workManagerActivity.reportPushTokenRegistered();
    } catch (_) {
      // Retry on the next app start/token refresh.
    }
  }
}
