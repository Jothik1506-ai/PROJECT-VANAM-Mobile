import 'package:flutter/material.dart';

import '../screens/login_screen.dart';
import 'preview_shell.dart';

/// PREVIEW-ONLY: wraps LoginScreen so submitting (with any values — there's
/// no real backend yet) navigates into the full tab-bar shell (Home/Reels/
/// Messages/Profile) for click-through review.
///
/// The real V1 app (lib/main.dart) does NOT do this — it has no backend to
/// call yet, so it has nowhere real to navigate after login. Don't copy this
/// navigation into main.dart until the actual auth flow exists.
class PreviewLoginGate extends StatelessWidget {
  const PreviewLoginGate({super.key});

  @override
  Widget build(BuildContext context) {
    return LoginScreen(
      onSubmit: (inviteCode, pin) async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        if (context.mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const PreviewShell()),
          );
        }
      },
    );
  }
}
