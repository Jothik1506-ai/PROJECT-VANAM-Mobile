import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/family_profile.dart';

final workManagerActivity = WorkManagerActivity();

class WorkManagerActivity {
  WorkManagerActivity();

  static const endpoint = String.fromEnvironment(
    'WORK_MANAGER_ACTIVITY_URL',
    defaultValue:
        'https://aiva-work-manager-by4q.onrender.com/api/vanam/mobile/activity',
  );

  static const sharedSecret = String.fromEnvironment(
    'WORK_MANAGER_ACTIVITY_SECRET',
  );

  DateTime? _lastActiveSentAt;
  FamilyProfile? _lastProfile;

  bool get _configured =>
      endpoint.trim().isNotEmpty && sharedSecret.trim().isNotEmpty;

  Future<void> reportLogin(FamilyProfile profile) {
    _lastProfile = profile;
    return _send(profile: profile, lastLoginAt: DateTime.now().toUtc());
  }

  Future<void> reportActive({
    FamilyProfile? profile,
    bool force = false,
  }) async {
    final effectiveProfile = profile ?? _lastProfile;
    if (effectiveProfile == null) return;

    final now = DateTime.now().toUtc();
    if (!force &&
        _lastActiveSentAt != null &&
        now.difference(_lastActiveSentAt!) < const Duration(minutes: 5)) {
      return;
    }

    _lastActiveSentAt = now;
    await _send(profile: effectiveProfile, lastActiveAt: now);
  }

  Future<void> reportPushTokenRegistered() {
    return _send(
      profile: _lastProfile,
      pushTokenRegistered: true,
      pushTokenUpdatedAt: DateTime.now().toUtc(),
    );
  }

  Future<void> reportFeedbackSent() {
    return _send(
      profile: _lastProfile,
      lastFeedbackAt: DateTime.now().toUtc(),
    );
  }

  Future<void> _send({
    FamilyProfile? profile,
    bool? pushTokenRegistered,
    DateTime? pushTokenUpdatedAt,
    DateTime? lastLoginAt,
    DateTime? lastActiveAt,
    DateTime? lastFeedbackAt,
  }) async {
    if (!_configured || profile == null) return;

    final info = await PackageInfo.fromPlatform();
    final sessionId = _currentSessionId();
    final payload = <String, Object?>{
      'familyMemberId': profile.id,
      'displayName': profile.displayName,
      'username': profile.username,
      'roleStatus': '${profile.role}/${profile.status}',
      'appVersion': '${info.version}+${info.buildNumber}',
      'platform': Platform.isAndroid ? 'android' : Platform.operatingSystem,
      'deviceLabel': Platform.operatingSystemVersion,
    };
    if (sessionId != null) payload['sessionId'] = sessionId;
    if (pushTokenRegistered != null) {
      payload['pushTokenRegistered'] = pushTokenRegistered;
    }
    if (pushTokenUpdatedAt != null) {
      payload['pushTokenUpdatedAt'] = pushTokenUpdatedAt.toIso8601String();
    }
    if (lastLoginAt != null) {
      payload['lastLoginAt'] = lastLoginAt.toIso8601String();
    }
    if (lastActiveAt != null) {
      payload['lastActiveAt'] = lastActiveAt.toIso8601String();
    }
    if (lastFeedbackAt != null) {
      payload['lastFeedbackAt'] = lastFeedbackAt.toIso8601String();
    }

    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse(endpoint));
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $sharedSecret');
      request.write(jsonEncode(payload));

      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.drain<void>();
      }
    } catch (_) {
      // Work Manager activity is admin observability, not app-critical UX.
      // Never block login, chat, push registration, or feedback on it.
    } finally {
      client.close(force: true);
    }
  }

  String? _currentSessionId() {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null) return null;
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      if (payload is! Map<String, dynamic>) return null;
      final value = payload['session_id'];
      return value is String && value.isNotEmpty ? value : null;
    } catch (_) {
      return null;
    }
  }
}
