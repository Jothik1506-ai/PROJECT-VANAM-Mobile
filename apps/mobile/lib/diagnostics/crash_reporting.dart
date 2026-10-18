import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import '../navigation/app_page.dart';

class CrashReporting {
  const CrashReporting._();

  static Future<void> setUser(String? userId) async {
    if (Firebase.apps.isEmpty) return;
    try {
      await FirebaseCrashlytics.instance.setUserIdentifier(userId ?? '');
    } catch (_) {}
  }

  static Future<void> setContext({
    required String screen,
    String? chatScope,
  }) async {
    if (Firebase.apps.isEmpty) return;
    try {
      await FirebaseCrashlytics.instance.setCustomKey('screen', screen);
      await FirebaseCrashlytics.instance.setCustomKey(
        'page_id',
        AppPage.byLabel(screen)?.id ?? '',
      );
      await FirebaseCrashlytics.instance.setCustomKey(
        'chat_scope',
        chatScope ?? '',
      );
    } catch (_) {}
  }

  static Future<void> recordError(
    Object error,
    StackTrace stack, {
    required String reason,
  }) async {
    if (Firebase.apps.isEmpty) return;
    try {
      await FirebaseCrashlytics.instance.recordError(
        error,
        stack,
        reason: reason,
      );
    } catch (_) {}
  }
}
