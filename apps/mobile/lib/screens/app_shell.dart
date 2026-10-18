import 'dart:async';

import 'package:flutter/material.dart';

import '../auth/family_profile.dart';
import '../auth/auth_service.dart';
import '../chat/chat_controller.dart';
import '../crypto/key_sync_service.dart';
import '../diagnostics/crash_reporting.dart';
import '../notifications/push_notification_service.dart';
import '../profile/profile_controller.dart';
import '../navigation/app_page.dart';
import '../widgets/feedback_button.dart';
import '../widgets/vanam_bottom_nav.dart';
import '../work_manager/work_manager_activity.dart';
import 'admin_invites_screen.dart';
import 'auth_gate.dart';
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

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _index = 2;
  late final _pageController = PageController(initialPage: _index);
  Timer? _accessCheckTimer;
  Timer? _keyResyncTimer;
  bool _checkingAccess = false;

  // Tab metadata (label + unique page id) lives in AppPage.
  static final _screenLabels = [for (final t in AppPage.tabs) t.label];

  // Previously all four tabs were built (and started fetching data +
  // loading images) the instant AppShell mounted, regardless of which one
  // was actually visible — Home and Reels even independently fetched the
  // same posts. Building lazily on first visit, and keeping each screen's
  // widget instance (not rebuilding it) once built, means only the
  // initially-visible tab (Home, index 2) does any work at startup.
  final List<Widget?> _builtScreens = List<Widget?>.filled(4, null);

  Widget _screenFor(int index) {
    return _builtScreens[index] ??= _KeepAlivePage(
      key: PageStorageKey<String>(AppPage.tabs[index].id),
      child: switch (index) {
        0 => const ReelsScreen(),
        1 => MessagesScreen(isAdmin: widget.isAdmin),
        2 => HomeScreen(isAdmin: widget.isAdmin),
        _ => const ProfileScreen(),
      },
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(CrashReporting.setUser(widget.profile.id));
    unawaited(CrashReporting.setContext(screen: _screenLabels[_index]));
    unawaited(familyGroupChat.load(userId: widget.profile.id));
    unawaited(profileController.load(userId: widget.profile.id));
    // Fire-and-forget: uploads this device's E2EE public key if it hasn't
    // already. Runs every time the app shell mounts (cheap no-op once
    // set) rather than in AuthGate, so it fires on every path that
    // reaches here — straight in, or via SetPasswordScreen/
    // SetDisplayNameScreen first.
    unawaited(keySyncService.refreshAccessibleScopes());
    unawaited(
      workManagerActivity.reportActive(profile: widget.profile, force: true),
    );
    unawaited(pushNotificationService.ensureTokenRegistered());
    _accessCheckTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _enforceAccountAccess(),
    );
    // Resealing a chat's key for a member who's missing it only happens on
    // an already-keyed participant's device — and previously only ran once,
    // at app launch. If that participant's public key showed up *after* the
    // other side last opened the app, the sender stayed stuck on
    // "Encryption is syncing" until someone thought to relaunch. Retrying
    // every 45s while the app is open closes that gap without needing
    // anyone to notice and manually restart anything.
    _keyResyncTimer = Timer.periodic(
      const Duration(seconds: 45),
      (_) => unawaited(keySyncService.refreshAccessibleScopes()),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _accessCheckTimer?.cancel();
    _keyResyncTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _enforceAccountAccess();
      unawaited(keySyncService.refreshAccessibleScopes());
    }
  }

  Future<void> _enforceAccountAccess() async {
    if (_checkingAccess || !mounted) return;
    _checkingAccess = true;
    try {
      final profile = await authService.fetchMyProfile();
      if (profile != null && profile.status == 'active') {
        if (profile.role == widget.profile.role) return;
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthGate()),
          (_) => false,
        );
        return;
      }

      await authService.signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthGate()),
        (_) => false,
      );
    } catch (_) {
      // A temporary network failure must never log a valid member out.
    } finally {
      _checkingAccess = false;
    }
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
    return Scaffold(
      body: PageView.builder(
        controller: _pageController,
        itemCount: 4,
        onPageChanged: (i) {
          setState(() => _index = i);
          unawaited(CrashReporting.setContext(screen: _screenLabels[i]));
          workManagerActivity.reportActive(profile: widget.profile);
        },
        itemBuilder: (context, index) => _screenFor(index),
      ),
      bottomNavigationBar: VanamBottomNav(
        currentIndex: _index,
        onTap: _goToTab,
        onMenuTap: _showGlobalActionsMenu,
      ),
    );
  }

  Future<void> _showGlobalActionsMenu() async {
    final action = await showModalBottomSheet<_GlobalAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.isAdmin)
              ListTile(
                leading: const Icon(Icons.person_add_alt_1_outlined),
                title: const Text('Invite'),
                subtitle: const Text('Create or manage family access'),
                onTap: () => Navigator.of(context).pop(_GlobalAction.invite),
              ),
            // Messages, Home and Profile have a Feedback button in their
            // header; Reels has no header, so it stays reachable here.
            if (_index == 0)
              ListTile(
                leading: const Icon(Icons.feedback_outlined),
                title: const Text('Feedback'),
                subtitle: Text('Send feedback from ${_screenLabels[_index]}'),
                onTap: () => Navigator.of(context).pop(_GlobalAction.feedback),
              ),
          ],
        ),
      ),
    );

    if (!mounted || action == null) return;

    switch (action) {
      case _GlobalAction.invite:
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const AdminInvitesScreen()));
      case _GlobalAction.feedback:
        await showFeedbackDialog(context, screen: _screenLabels[_index]);
    }
  }
}

enum _GlobalAction { invite, feedback }

/// Keeps a lazily-built tab's state alive once it's been visited, instead
/// of PageView disposing it as soon as it scrolls out of the viewport
/// (which would otherwise re-run each screen's fetch every time the user
/// swipes back to it).
class _KeepAlivePage extends StatefulWidget {
  const _KeepAlivePage({super.key, required this.child});

  final Widget child;

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
