import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import 'admin_invites_screen.dart';
import 'chat_detail_screen.dart';
import 'login_screen.dart';

/// Real startup routing for the actual app (lib/main.dart).
///
/// supabase_flutter persists sessions on-device, including anonymous ones
/// that already redeemed an invite — without this check, someone who
/// already joined would see the Login screen again every time they open
/// the app. Checks the session + profiles row and routes straight to
/// Admin Invites (admins) or the Family Group chat (everyone else);
/// otherwise falls back to Login.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late Future<Widget> _destination;

  @override
  void initState() {
    super.initState();
    _destination = _resolve();
  }

  Future<Widget> _resolve() async {
    if (!authService.isSignedIn) return const LoginScreen();

    try {
      final profile = await authService.fetchMyProfile();
      if (profile == null) {
        // Signed in (even anonymously) but never successfully redeemed an
        // invite — RLS would show them nothing anyway. Send them to Login
        // to actually redeem one.
        return const LoginScreen();
      }
      return profile.isAdmin
          ? const AdminInvitesScreen()
          : ChatDetailScreen(groupName: 'Family Group');
    } catch (_) {
      // Offline or a transient error resolving the profile must not strand
      // the user on a blank screen — Login can always be retried.
      return const LoginScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _destination,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return snapshot.data!;
      },
    );
  }
}
