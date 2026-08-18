import 'package:flutter/material.dart';

import '../home/home_feed_repository.dart';
import '../screens/coming_soon_screen.dart';
import '../screens/home_screen.dart';
import '../screens/messages_screen.dart';
import '../screens/profile_screen.dart';
import '../widgets/feedback_button.dart';
import '../widgets/vanam_bottom_nav.dart';

/// UI-only preview of the full four-tab app shell (Home/Reels/Messages/
/// Profile). NOT the real V1 app — run via lib/dev/preview_main.dart.
/// The real V1 app (lib/main.dart) starts at LoginScreen with no tab bar,
/// per ARCHITECTURE.md.
class PreviewShell extends StatefulWidget {
  const PreviewShell({super.key});

  @override
  State<PreviewShell> createState() => _PreviewShellState();
}

class _PreviewShellState extends State<PreviewShell> {
  int _index = 2; // Home is the default landing tab, now third in order.

  // Order: Reels, Messages, Home, Profile — must match VanamBottomNav._items.
  static const _screens = [
    ComingSoonScreen(label: 'Reels'),
    MessagesScreen(),
    HomeScreen(repository: EmptyHomeFeedRepository()),
    ProfileScreen(),
  ];

  static const _screenLabels = ['Reels', 'Messages', 'Home', 'Profile'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      floatingActionButton: FeedbackButton(screen: _screenLabels[_index]),
      bottomNavigationBar: VanamBottomNav(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}
