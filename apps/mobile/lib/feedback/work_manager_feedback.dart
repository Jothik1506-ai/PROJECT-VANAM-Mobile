import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class WorkManagerFeedback {
  const WorkManagerFeedback._();

  // Was pointing at the retired Render deployment — Work Manager now runs
  // on a dedicated VPS behind manager.aivafreelancia.in (see the (local,
  // gitignored) AIVA Work Manager repo's docs/VPS-DEPLOYMENT.md).
  static const endpoint = String.fromEnvironment(
    'WORK_MANAGER_FEEDBACK_URL',
    defaultValue: 'https://manager.aivafreelancia.in/api/feedback',
  );

  static Future<void> send({
    required String name,
    required String feedback,
    required String screen,
    String? chatId,
    String? chatType,
    String? chatName,
    String? itemId,
    String? keyState,
  }) async {
    // Same unbounded-network-call pattern already fixed elsewhere
    // (work_manager_activity.dart, key_sync_service.dart) — this had no
    // timeout at all, so a slow/unreachable Work Manager could hang
    // whatever screen calls this indefinitely.
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final userId = Supabase.instance.client.auth.currentUser?.id;
      await Future(() async {
        final request = await client.postUrl(Uri.parse(endpoint));
        request.headers.contentType = ContentType.json;
        request.write(
          jsonEncode({
            'source': 'vanam-mobile-app',
            'category': 'other',
            'message': [
              'Project: Project Vanam',
              'App: Mobile App',
              'Version: ${packageInfo.version} (${packageInfo.buildNumber})',
              'Screen: $screen',
              if (userId != null) 'User ID: $userId',
              if (itemId != null) 'Item ID: $itemId',
              if (chatId != null) 'Chat ID: $chatId',
              if (chatType != null) 'Chat type: $chatType',
              if (chatName != null) 'Chat name: $chatName',
              if (keyState != null) 'Chat key state: $keyState',
              'Name: ${name.trim()}',
              '',
              feedback.trim(),
            ].join('\n'),
            'pageUrl': 'app://vanam-mobile/${_screenSlug(screen)}',
            'platform': '${Platform.operatingSystem} ${Platform.version}',
          }),
        );

        final response = await request.close();
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw const HttpException('Work Manager rejected feedback.');
        }
      }).timeout(const Duration(seconds: 8));
    } finally {
      client.close(force: true);
    }
  }

  static String _screenSlug(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }
}
