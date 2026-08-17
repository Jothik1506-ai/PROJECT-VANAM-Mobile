import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Profile screen — PREVIEW ONLY.
///
/// Preview profile with the VANAM logo kept as the hero mark.
/// Real V1 keeps profile settings simple: name, avatar, language, privacy.
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
            const _PrivacySummary(),
            const SizedBox(height: VanamSpacing.md),
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
            'Your Profile',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Family member · Vanam',
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

class _PrivacySummary extends StatelessWidget {
  const _PrivacySummary();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: VanamSpacing.md),
      child: Container(
        padding: const EdgeInsets.all(VanamSpacing.md),
        decoration: BoxDecoration(
          color: VanamColors.brand.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(VanamRadii.card),
          border: Border.all(color: VanamColors.brand.withValues(alpha: 0.14)),
        ),
        child: const Row(
          children: [
            Icon(Icons.lock_outline, color: VanamColors.brand),
            SizedBox(width: VanamSpacing.sm),
            Expanded(
              child: Text(
                'Messages are planned as end-to-end encrypted in V1.',
                style: TextStyle(color: VanamColors.brandDark, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileMenuList extends StatelessWidget {
  const _ProfileMenuList();

  static const _items = [
    (icon: Icons.person_outline, label: 'Account Details'),
    (icon: Icons.translate_outlined, label: 'Language'),
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
