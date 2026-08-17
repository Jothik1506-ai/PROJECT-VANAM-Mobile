import 'package:flutter/material.dart';

import 'profile/profile_controller.dart';
import 'screens/login_screen.dart';
import 'theme/theme_controller.dart';
import 'theme/tokens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await profileController.load();
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
          // Real V1 entry point: invite code + PIN login only.
          // Use lib/dev/preview_main.dart for the click-through preview shell.
          home: const LoginScreen(),
        );
      },
    );
  }
}
