import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Profile screen — PREVIEW ONLY.
///
/// Matches the approved visual mockup, but note: ARCHITECTURE.md's locked
/// V1 "Simple Profile" spec (Section 1/8) is just name + avatar + language,
/// no post/family counts, no bio. The Posts/Family stat row here and
/// "WiFi Calling Settings" (which depends on Phase 2 calling, not built)
/// are shown for visual review only — mock data, not wired to anything.
/// The real V1 profile edit form is separate, smaller-scoped work.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const _ProfileHeader(),
            const SizedBox(height: VanamSpacing.lg),
            const _StatsRow(),
            const SizedBox(height: VanamSpacing.sm),
            const _ProfileMenuList(),
            const SizedBox(height: VanamSpacing.xl),
          ],
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        vertical: VanamSpacing.xl,
        horizontal: VanamSpacing.lg,
      ),
      decoration: const BoxDecoration(
        color: VanamColors.brand,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(VanamRadii.card),
          bottomRight: Radius.circular(VanamRadii.card),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 96,
            height: 96,
            padding: const EdgeInsets.all(6),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              border: Border.fromBorderSide(
                BorderSide(color: Colors.white, width: 2),
              ),
            ),
            child: Image.asset(
              'assets/brand/Final.png',
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: VanamSpacing.md),
          const Text(
            'Jothik Krishna', // mock — real V1 profile pulls this from login
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Family Admin · Vanam',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13),
          ),
          const SizedBox(height: VanamSpacing.md),
          OutlinedButton(
            onPressed: () {},
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white, width: 1.2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(VanamRadii.button),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: VanamSpacing.lg,
                vertical: VanamSpacing.sm,
              ),
            ),
            child: const Text('Edit Profile'),
          ),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _StatItem(value: '38', label: 'Posts'),
        _StatItem(value: '12', label: 'Family'),
      ],
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: VanamColors.ink,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: VanamColors.inkMuted),
        ),
      ],
    );
  }
}

class _ProfileMenuList extends StatelessWidget {
  const _ProfileMenuList();

  static const _items = [
    (icon: Icons.person_outline, label: 'Account Details'),
    (icon: Icons.wifi_calling_3_outlined, label: 'WiFi Calling Settings'),
    (icon: Icons.notifications_none_rounded, label: 'Notifications'),
    (icon: Icons.lock_outline, label: 'Privacy & Security'),
    (icon: Icons.help_outline, label: 'Help & Support'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: VanamSpacing.md),
      child: Column(
        children: [
          for (final item in _items) ...[
            _ProfileMenuTile(icon: item.icon, label: item.label),
            const Divider(height: 1, color: VanamColors.line),
          ],
        ],
      ),
    );
  }
}

class _ProfileMenuTile extends StatelessWidget {
  const _ProfileMenuTile({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: VanamSpacing.md),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: VanamColors.brand.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 18, color: VanamColors.brand),
            ),
            const SizedBox(width: VanamSpacing.md),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 15, color: VanamColors.ink),
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: VanamColors.inkMuted,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
