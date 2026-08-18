import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'chat/chat_controller.dart';
import 'config/app_config.dart';
import 'profile/profile_controller.dart';
import 'screens/auth_gate.dart';
import 'theme/theme_controller.dart';
import 'theme/tokens.dart';
import 'widgets/update_check_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabaseAnonKey,
  );
  await profileController.load();
  await familyGroupChat.load();
  runApp(const VanamApp());
}

class VanamApp extends StatelessWidget {
  const VanamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: vanamThemeMode,
      builder: (context, themeMode, child) {
        return MaterialApp(
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
