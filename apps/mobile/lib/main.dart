import 'package:flutter/material.dart';

import 'dev/preview_login_gate.dart';
import 'theme/tokens.dart';

void main() {
  runApp(const VanamApp());
}

class VanamApp extends StatelessWidget {
  const VanamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vanam',
      debugShowCheckedModeBanner: false,
      theme: buildVanamTheme(),
      // TEMPORARY: PreviewLoginGate accepts any invite code + PIN (there is
      // no backend yet) and navigates straight into the tab shell, purely
      // so the screens can be clicked through end-to-end during design.
      // TODO(codex): replace with real Splash -> auth-check -> Chat List
      // routing once /auth/login and SessionManager exist
      // (ARCHITECTURE.md Section 4/5/11A/11B). At that point this should
      // go back to plain LoginScreen with no forced navigation.
      home: const PreviewLoginGate(),
    );
  }
}
