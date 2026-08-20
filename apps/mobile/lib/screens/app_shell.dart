import 'package:flutter/material.dart';

import '../auth/family_profile.dart';
import '../crypto/key_sync_service.dart';
import '../notifications/push_notification_service.dart';
import '../widgets/feedback_button.dart';
import '../widgets/vanam_bottom_nav.dart';
import '../work_manager/work_manager_activity.dart';
import 'admin_invites_screen.dart';
import 'home_screen.dart';
import 'messages_screen.dart';
import 'profile_screen.dart';
import 'reels_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.isAdmin, required this.profile});

  final bool isAdmin;
  final FamilyProfile profile;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 2;
  late final _pageController = PageController(initialPage: _index);

  static const _screenLabels = ['Reels', 'Messages', 'Home', 'Profile'];

  @override
  void initState() {
    super.initState();
    // Fire-and-forget: uploads this device's E2EE public key if it hasn't
    // already. Runs every time the app shell mounts (cheap no-op once
    // set) rather than in AuthGate, so it fires on every path that
    // reaches here — straight in, or via SetPasswordScreen/
    // SetDisplayNameScreen first.
    keySyncService.ensurePublicKeyUploaded();
    workManagerActivity.reportActive(profile: widget.profile, force: true);
    pushNotificationService.ensureTokenRegistered();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // Tapping a tab animates the PageView to it; onPageChanged (below) is what
  // actually updates _index, for both taps and swipes alike — so the two
  // input methods can never disagree about which tab is "current".
  void _goToTab(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      const ReelsScreen(),
      MessagesScreen(isAdmin: widget.isAdmin),
      HomeScreen(isAdmin: widget.isAdmin),
      const ProfileScreen(),
    ];

    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: (i) {
          setState(() => _index = i);
          workManagerActivity.reportActive(profile: widget.profile);
        },
        children: screens,
      ),
      floatingActionButton: _GlobalActions(
        isAdmin: widget.isAdmin,
        screen: _screenLabels[_index],
      ),
      bottomNavigationBar: VanamBottomNav(
        currentIndex: _index,
        onTap: _goToTab,
      ),
    );
  }
}

class _GlobalActions extends StatelessWidget {
  const _GlobalActions({required this.isAdmin, required this.screen});

  final bool isAdmin;
  final String screen;

  @override
  Widget build(BuildContext context) {
    if (!isAdmin) return FeedbackButton(screen: screen);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        FloatingActionButton.extended(
          heroTag: 'global-invite',
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AdminInvitesScreen()),
            );
          },
          icon: const Icon(Icons.person_add_alt_1_outlined),
          label: const Text('Invite'),
        ),
        const SizedBox(height: 12),
        FeedbackButton(screen: screen),
      ],
    );
  }
}
