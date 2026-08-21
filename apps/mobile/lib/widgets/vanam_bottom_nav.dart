import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Bottom tab bar: Home | Reels | Messages | Profile.
///
/// PREVIEW-ONLY SCAFFOLDING. ARCHITECTURE.md explicitly says V1 has no
/// bottom tab bar (one screen, Chat List, doesn't need one). This widget
/// exists so all four planned tabs can be reviewed together; do not wire it
/// into the real V1 app (lib/main.dart) until Phase 3 is scheduled.
class VanamBottomNav extends StatelessWidget {
  const VanamBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.onMenuTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final VoidCallback? onMenuTap;

  static const _items = [
    (icon: Icons.play_circle_outline, label: 'Reels'),
    (icon: Icons.chat_bubble_outline, label: 'Messages'),
    (icon: Icons.home_rounded, label: 'Home'),
    (icon: Icons.person_outline, label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.vanam;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surfaceCard,
        border: Border(top: BorderSide(color: palette.line)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              for (var i = 0; i < _items.length; i++) ...[
                if (i == _items.length - 1 && onMenuTap != null)
                  Expanded(
                    child: InkWell(
                      onTap: onMenuTap,
                      child: const _NavItem(
                        icon: Icons.more_horiz,
                        label: 'More',
                        selected: false,
                      ),
                    ),
                  ),
                Expanded(
                  child: InkWell(
                    onTap: () => onTap(i),
                    child: _NavItem(
                      icon: _items[i].icon,
                      label: _items[i].label,
                      selected: i == currentIndex,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
  });

  final IconData icon;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final palette = context.vanam;
    final color = selected ? palette.brand : palette.inkMuted;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: color),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ],
    );
  }
}
