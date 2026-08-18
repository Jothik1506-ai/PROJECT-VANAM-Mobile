import 'package:flutter/material.dart';

import '../widgets/feedback_button.dart';
import '../widgets/vanam_bottom_nav.dart';
import 'coming_soon_screen.dart';
import 'home_screen.dart';
import 'messages_screen.dart';
import 'profile_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.isAdmin});

  final bool isAdmin;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 2;
  late final _pageController = PageController(initialPage: _index);

  static const _screenLabels = ['Reels', 'Messages', 'Home', 'Profile'];

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
      const ComingSoonScreen(label: 'Reels'),
      MessagesScreen(isAdmin: widget.isAdmin),
      const HomeScreen(),
      const ProfileScreen(),
    ];

    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: (i) => setState(() => _index = i),
        children: screens,
      ),
      floatingActionButton: FeedbackButton(screen: _screenLabels[_index]),
      bottomNavigationBar: VanamBottomNav(
        currentIndex: _index,
        onTap: _goToTab,
      ),
    );
  }
}
