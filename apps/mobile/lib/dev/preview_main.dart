import 'package:flutter/material.dart';

import '../theme/theme_controller.dart';
import '../theme/tokens.dart';
import 'preview_login_gate.dart';

/// Entry point for reviewing the full app shell UI (Home/Reels/Messages/
/// Profile) with mock data. Run with:
///   flutter run -t lib/dev/preview_main.dart
///
/// This is NOT the production entry point — that's lib/main.dart, which
/// starts at LoginScreen per the locked V1 scope (chat-only, no tab bar).
void main() {
  runApp(const VanamPreviewApp());
}

class VanamPreviewApp extends StatelessWidget {
  const VanamPreviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: vanamThemeMode,
      builder: (context, themeMode, child) {
        return MaterialApp(
          title: 'Vanam (Preview)',
          debugShowCheckedModeBanner: false,
          theme: buildVanamTheme(),
          darkTheme: buildVanamTheme(brightness: Brightness.dark),
          themeMode: themeMode,
          home: const PreviewLoginGate(),
        );
      },
    );
  }
}
