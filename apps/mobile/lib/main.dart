import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'chat/chat_controller.dart';
import 'config/app_config.dart';
import 'notifications/push_navigation.dart';
import 'notifications/push_notification_service.dart';
import 'profile/profile_controller.dart';
import 'screens/auth_gate.dart';
import 'theme/theme_controller.dart';
import 'theme/tokens.dart';
import 'widgets/update_check_gate.dart';

Future<void> main() async {
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      // Was 40 images / 32MB — too small for a photo-heavy family feed
      // (Home + Reels), causing images scrolled past to be evicted and
      // re-decoded from disk/network on scroll-back. 100MB (an earlier
      // version of this fix) was too aggressive for older/low-memory
      // Android phones once stacked alongside Flutter, Firebase, Supabase,
      // and page state — 64MB is a safer middle ground that still holds
      // meaningfully more than the original 32MB.
      PaintingBinding.instance.imageCache.maximumSize = 120;
      PaintingBinding.instance.imageCache.maximumSizeBytes = 64 << 20;

      // pushNotificationService.initialize() runs Firebase.initializeApp()
      // internally — Crashlytics can only be touched afterward, and only if
      // that actually succeeded (it swallows its own init failures rather
      // than rethrowing, so Firebase.apps can still be empty here).
      //
      // initialize() already catches everything internally now, but this
      // call is wrapped again here as defense-in-depth: nothing about push
      // notifications — today or in any future change to that file — may
      // ever be allowed to stop runApp() from being reached below. Before
      // this fix, an uncaught throw anywhere past the Firebase.initializeApp
      // step (notification-channel setup, the permission prompt,
      // getInitialMessage()) propagated all the way out here and skipped
      // runApp() entirely, leaving a permanent blank screen.
      //
      // A try/catch alone only protects against a *throw* — it does
      // nothing if a step hangs instead (e.g. a broken/incompatible Google
      // Play Services install stalling the permission prompt or
      // getInitialMessage() rather than erroring out), which would still
      // delay runApp() indefinitely. The explicit timeout below bounds
      // that too.
      try {
        await pushNotificationService.initialize().timeout(
          const Duration(seconds: 8),
        );
      } catch (_) {}
      final crashlyticsReady = await _initCrashlyticsIfPossible();

      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        if (crashlyticsReady) {
          FirebaseCrashlytics.instance.recordFlutterFatalError(details);
        }
      };
      if (crashlyticsReady) {
        PlatformDispatcher.instance.onError = (error, stack) {
          FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
          return true;
        };
      }

      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        publishableKey: AppConfig.supabaseAnonKey,
      );
      await profileController.load();
      await familyGroupChat.load();
      runApp(const VanamApp());
    },
    (error, stack) {
      // Previously discarded entirely — every uncaught error anywhere in
      // the app (including any real crash) left zero evidence trail. Now
      // reported to Crashlytics when available; release builds still
      // never restart-loop on this, and screen-level code still surfaces
      // user-facing errors independently of this handler.
      unawaited(_recordZoneError(error, stack));
    },
  );
}

/// Returns whether Crashlytics is actually usable — false if Firebase
/// itself never finished initializing (see pushNotificationService, whose
/// own Firebase.initializeApp() failure is swallowed rather than thrown).
Future<bool> _initCrashlyticsIfPossible() async {
  if (Firebase.apps.isEmpty) return false;
  try {
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
    return true;
  } catch (_) {
    return false;
  }
}

Future<void> _recordZoneError(Object error, StackTrace stack) async {
  if (Firebase.apps.isEmpty) return;
  try {
    await FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
  } catch (_) {
    // Crashlytics itself must never be the thing that crashes the app.
  }
}

class VanamApp extends StatelessWidget {
  const VanamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: vanamThemeMode,
      builder: (context, themeMode, child) {
        return MaterialApp(
          navigatorKey: vanamNavigatorKey,
          title: 'Vanam',
          debugShowCheckedModeBanner: false,
          theme: buildVanamTheme(),
          darkTheme: buildVanamTheme(brightness: Brightness.dark),
          themeMode: themeMode,
          // Real V1 entry point. AuthGate checks for a persisted session +
          // profile and routes straight past Login if one already exists.
          // Use lib/dev/preview_main.dart for the click-through preview shell.
          home: const UpdateCheckGate(child: AuthGate()),
        );
      },
    );
  }
}
