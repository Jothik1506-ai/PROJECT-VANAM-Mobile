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

  static const _screenLabels = ['Reels', 'Messages', 'Home', 'Profile'];

  @override
  Widget build(BuildContext context) {
    final screens = [
      const ComingSoonScreen(label: 'Reels'),
      MessagesScreen(isAdmin: widget.isAdmin),
      const HomeScreen(),
      const ProfileScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: screens),
      floatingActionButton: FeedbackButton(screen: _screenLabels[_index]),
      bottomNavigationBar: VanamBottomNav(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}
