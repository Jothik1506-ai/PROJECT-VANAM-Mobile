import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../auth/auth_service.dart';
import '../profile/profile_controller.dart';
import '../profile/user_profile.dart';
import '../theme/theme_controller.dart';
import '../theme/tokens.dart';
import '../widgets/vanam_logo.dart';
import 'change_password_screen.dart';
import 'auth_gate.dart';

/// Profile screen.
///
/// Keeps the VANAM logo as the hero mark while saving real local profile
/// settings that other features can read.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.zero,
          children: const [
            _ProfileHeader(),
            SizedBox(height: VanamSpacing.lg),
            _ThemeModeSetting(),
            SizedBox(height: VanamSpacing.md),
            _PrivacySummary(),
            SizedBox(height: VanamSpacing.md),
            _ProfileMenuList(),
            SizedBox(height: VanamSpacing.md),
            _SignOutButton(),
            SizedBox(height: VanamSpacing.xl),
            _AppVersionLabel(),
            SizedBox(height: VanamSpacing.xl),
          ],
        ),
      ),
    );
  }
}

class _AppVersionLabel extends StatelessWidget {
  const _AppVersionLabel();

  @override
  Widget build(BuildContext context) {
    final palette = context.vanam;
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final info = snapshot.data;
        final versionText = info == null
            ? 'Version loading...'
            : 'Version ${info.version} (${info.buildNumber})';
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: VanamSpacing.md),
          child: Center(
            child: Text(
              versionText,
              style: TextStyle(color: palette.inkMuted, fontSize: 12),
            ),
          ),
        );
      },
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader();

  @override
  Widget build(BuildContext context) {
    final palette = context.vanam;
    return ValueListenableBuilder<UserProfile>(
      valueListenable: profileController,
      builder: (context, profile, child) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            vertical: VanamSpacing.xl,
            horizontal: VanamSpacing.lg,
          ),
          decoration: BoxDecoration(
            color: palette.brand,
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
                child: const VanamLogo(size: 84),
              ),
              const SizedBox(height: VanamSpacing.md),
              Text(
                profile.displayName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${profile.language} - Vanam',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: VanamSpacing.md),
              OutlinedButton(
                onPressed: () => _showEditProfileDialog(context, profile),
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
      },
    );
  }
}

Future<void> _showEditProfileDialog(BuildContext context, UserProfile profile) {
  return showDialog<void>(
    context: context,
    builder: (context) => _EditProfileDialog(profile: profile),
  );
}

class _EditProfileDialog extends StatefulWidget {
  const _EditProfileDialog({required this.profile});

  final UserProfile profile;

  @override
  State<_EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends State<_EditProfileDialog> {
  late final TextEditingController _nameController;
  late String _language;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile.name);
    _language = widget.profile.language;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _saving = true);
    await profileController.save(UserProfile(name: name, language: _language));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.vanam;
    return AlertDialog(
      backgroundColor: palette.surfaceCard,
      title: Text('Edit Profile', style: TextStyle(color: palette.ink)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(hintText: 'Your name'),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: VanamSpacing.md),
          DropdownButtonFormField<String>(
            initialValue: _language,
            decoration: const InputDecoration(hintText: 'Language'),
            items: const [
              DropdownMenuItem(value: 'English', child: Text('English')),
              DropdownMenuItem(value: 'Telugu', child: Text('Telugu')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _language = value);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving...' : 'Save'),
        ),
      ],
    );
  }
}

class _ThemeModeSetting extends StatelessWidget {
  const _ThemeModeSetting();

  @override
  Widget build(BuildContext context) {
    final palette = context.vanam;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: VanamSpacing.md),
      child: Container(
        padding: const EdgeInsets.all(VanamSpacing.md),
        decoration: BoxDecoration(
          color: palette.surfaceCard,
          borderRadius: BorderRadius.circular(VanamRadii.card),
          border: Border.all(color: palette.line),
        ),
        child: ValueListenableBuilder<ThemeMode>(
          valueListenable: vanamThemeMode,
          builder: (context, selectedMode, child) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.dark_mode_outlined, color: palette.brand),
                    const SizedBox(width: VanamSpacing.sm),
                    Text(
                      'Dark Mode',
                      style: TextStyle(
                        color: palette.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      themeModeLabel(selectedMode),
                      style: TextStyle(color: palette.inkMuted, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: VanamSpacing.md),
                SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      icon: Icon(Icons.phone_android_outlined),
                      label: Text('System'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      icon: Icon(Icons.light_mode_outlined),
                      label: Text('Light'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      icon: Icon(Icons.dark_mode_outlined),
                      label: Text('Dark'),
                    ),
                  ],
                  selected: {selectedMode},
                  onSelectionChanged: (selection) {
                    vanamThemeMode.value = selection.first;
                  },
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    side: WidgetStatePropertyAll(
                      BorderSide(color: palette.line),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PrivacySummary extends StatelessWidget {
  const _PrivacySummary();

  @override
  Widget build(BuildContext context) {
    final palette = context.vanam;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: VanamSpacing.md),
      child: Container(
        padding: const EdgeInsets.all(VanamSpacing.md),
        decoration: BoxDecoration(
          color: palette.noticeSurface,
          borderRadius: BorderRadius.circular(VanamRadii.card),
          border: Border.all(color: palette.noticeBorder),
        ),
        child: Row(
          children: [
            Icon(Icons.lock_outline, color: palette.brand),
            const SizedBox(width: VanamSpacing.sm),
            Expanded(
              child: Text(
                'Messages are end-to-end encrypted — Vanam never sees '
                'their content.',
                style: TextStyle(color: palette.brandStrong, fontSize: 13),
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

  @override
  Widget build(BuildContext context) {
    final palette = context.vanam;
    final List<({IconData icon, String label, VoidCallback? onTap})> items = [
      (icon: Icons.person_outline, label: 'Account Details', onTap: null),
      (icon: Icons.translate_outlined, label: 'Language', onTap: null),
      (
        icon: Icons.notifications_none_rounded,
        label: 'Notifications',
        onTap: null,
      ),
      (
        icon: Icons.lock_outline,
        label: 'Change Password',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ChangePasswordScreen()),
        ),
      ),
      (icon: Icons.help_outline, label: 'Help & Support', onTap: null),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: VanamSpacing.md),
      child: Column(
        children: [
          for (final item in items) ...[
            _ProfileMenuTile(
              icon: item.icon,
              label: item.label,
              onTap: item.onTap,
            ),
            Divider(height: 1, color: palette.line),
          ],
        ],
      ),
    );
  }
}

class _SignOutButton extends StatelessWidget {
  const _SignOutButton();

  Future<void> _signOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text("You'll need your username and password to log back in."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await authService.signOut();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthGate()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.vanam;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: VanamSpacing.md),
      child: OutlinedButton.icon(
        onPressed: () => _signOut(context),
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.danger,
          side: BorderSide(color: palette.danger),
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(VanamRadii.button),
          ),
        ),
        icon: const Icon(Icons.logout),
        label: const Text('Sign Out'),
      ),
    );
  }
}

class _ProfileMenuTile extends StatelessWidget {
  const _ProfileMenuTile({
    required this.icon,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.vanam;
    return InkWell(
      onTap: onTap ?? () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: VanamSpacing.md),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: palette.noticeSurface,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 18, color: palette.brand),
            ),
            const SizedBox(width: VanamSpacing.md),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 15, color: palette.ink),
              ),
            ),
            Icon(Icons.chevron_right, color: palette.inkMuted, size: 20),
          ],
        ),
      ),
    );
  }
}
