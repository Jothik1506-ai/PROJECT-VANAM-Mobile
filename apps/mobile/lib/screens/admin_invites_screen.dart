import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../invites/invite.dart';
import '../invites/invite_qr_codec.dart';
import '../invites/invite_service.dart';
import '../theme/tokens.dart';
import 'chat_detail_screen.dart';

/// Real admin screen — creates real username/password member accounts via
/// admin_create_member, lists actual profiles rows. Reachable only for a
/// session whose profiles.role = 'admin' (ARCHITECTURE.md Section 7). Not
/// preview data.
class AdminInvitesScreen extends StatefulWidget {
  const AdminInvitesScreen({super.key});

  @override
  State<AdminInvitesScreen> createState() => _AdminInvitesScreenState();
}

class _AdminInvitesScreenState extends State<AdminInvitesScreen> {
  late Future<List<Invite>> _invitesFuture;

  @override
  void initState() {
    super.initState();
    _invitesFuture = inviteService.listInvites();
  }

  void _refresh() {
    // Block body, not =>: an arrow-expression assignment evaluates to the
    // assigned value, so `() => _invitesFuture = future` implicitly
    // returns that Future — which setState explicitly forbids its
    // callback from doing (throws "setState() callback argument returned
    // a Future"). The invite creation itself was never the problem; this
    // crashed only the refresh that followed it.
    setState(() {
      _invitesFuture = inviteService.listInvites();
    });
  }

  Future<void> _createInvite() async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => const _NewInviteDialog(),
    );
    if (name == null || name.trim().isEmpty) return;
    if (!mounted) return;

    try {
      final (invite, username, password, recoveryCode) = await inviteService
          .createInvite(inviteeName: name.trim());
      _refresh();
      if (mounted) {
        await _InviteCreatedSheet.show(
          context,
          invite: invite,
          username: username,
          password: password,
          recoveryCode: recoveryCode,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not create member. Check your connection and try again.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _issueCredentials(Invite invite) async {
    try {
      final (username, password, recoveryCode) = await inviteService
          .issueCredentials(invite.id);
      _refresh();
      if (mounted) {
        await _InviteCreatedSheet.show(
          context,
          invite: invite,
          username: username,
          password: password,
          recoveryCode: recoveryCode,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not issue login. Try again.'),
          ),
        );
      }
    }
  }

  Future<void> _resetPassword(Invite invite) async {
    try {
      final (password, recoveryCode) = await inviteService.resetPassword(
        invite.id,
      );
      _refresh();
      if (mounted) {
        await _InviteCreatedSheet.show(
          context,
          invite: invite,
          username: invite.username ?? '',
          password: password,
          recoveryCode: recoveryCode,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not reset password. Try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.vanam;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Family Members'),
        actions: [
          IconButton(
            tooltip: 'Family Group chat',
            icon: const Icon(Icons.chat_bubble_outline),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    ChatDetailScreen(groupName: 'Family Group', isAdmin: true),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createInvite,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('New Member'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<List<Invite>>(
          future: _invitesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(VanamSpacing.xl),
                    child: Text(
                      'Could not load members. Pull down to retry.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: palette.inkMuted),
                    ),
                  ),
                ],
              );
            }
            final invites = snapshot.data ?? const [];
            if (invites.isEmpty) {
              return ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(VanamSpacing.xl),
                    child: Text(
                      'No members yet. Tap "New Member" to add a family '
                      'member.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: palette.inkMuted),
                    ),
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                VanamSpacing.md,
                VanamSpacing.md,
                VanamSpacing.md,
                VanamSpacing.xxl,
              ),
              itemCount: invites.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(height: VanamSpacing.sm),
              itemBuilder: (context, i) => _InviteTile(
                invite: invites[i],
                onRevoked: _refresh,
                onIssueCredentials: () => _issueCredentials(invites[i]),
                onResetPassword: () => _resetPassword(invites[i]),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _NewInviteDialog extends StatefulWidget {
  const _NewInviteDialog();

  @override
  State<_NewInviteDialog> createState() => _NewInviteDialogState();
}

class _NewInviteDialogState extends State<_NewInviteDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add a family member'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(hintText: "Their name"),
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Create Login'),
        ),
      ],
    );
  }
}

class _InviteCreatedSheet extends StatelessWidget {
  const _InviteCreatedSheet({
    required this.invite,
    required this.username,
    required this.password,
    required this.recoveryCode,
  });

  final Invite invite;
  final String username;
  final String password;
  final String recoveryCode;

  static Future<void> show(
    BuildContext context, {
    required Invite invite,
    required String username,
    required String password,
    required String recoveryCode,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => _InviteCreatedSheet(
        invite: invite,
        username: username,
        password: password,
        recoveryCode: recoveryCode,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.vanam;
    final shareText =
        'Join our family on Vanam!\nUsername: $username\nPassword: $password\n'
        'Recovery code (keep this safe, only shown once): $recoveryCode\n'
        "(You'll be asked to set your own password on first login. If you "
        'forget it later, use "Forgot password?" on the Login screen with '
        'the recovery code above.)';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(VanamSpacing.lg),
        // QR + username + password + copy button no longer reliably fits
        // every phone height in one screen — scrollable so it clips
        // instead of overflowing, rather than assuming every device is
        // tall enough.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Login ready for ${invite.inviteeName}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: palette.ink,
                ),
              ),
              const SizedBox(height: VanamSpacing.xs),
              Text(
                'This password is shown only once. Copy or share it now — '
                "it can't be recovered later, only reset.",
                style: TextStyle(fontSize: 12, color: palette.danger),
              ),
              const SizedBox(height: VanamSpacing.md),
              Container(
                padding: const EdgeInsets.all(VanamSpacing.md),
                decoration: BoxDecoration(
                  color: palette.noticeSurface,
                  borderRadius: BorderRadius.circular(VanamRadii.card),
                  border: Border.all(color: palette.noticeBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Username',
                      style: TextStyle(fontSize: 12, color: palette.inkMuted),
                    ),
                    SelectableText(
                      username,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: palette.brandStrong,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: VanamSpacing.sm),
                    Text(
                      'Password',
                      style: TextStyle(fontSize: 12, color: palette.inkMuted),
                    ),
                    SelectableText(
                      password,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: palette.brandStrong,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: VanamSpacing.sm),
                    Text(
                      'Recovery code',
                      style: TextStyle(fontSize: 12, color: palette.inkMuted),
                    ),
                    SelectableText(
                      recoveryCode,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: palette.brandStrong,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'For "Forgot password?" if they lose their password '
                      'later. Not the same as the password above.',
                      style: TextStyle(fontSize: 11, color: palette.inkMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: VanamSpacing.md),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(VanamSpacing.md),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(VanamRadii.card),
                  ),
                  child: QrImageView(
                    data: InviteQrCodec.encode(
                      username: username,
                      password: password,
                    ),
                    size: 180,
                    padding: EdgeInsets.zero,
                  ),
                ),
              ),
              const SizedBox(height: VanamSpacing.xs),
              Text(
                'Or let them scan this from the Login screen — signs them '
                'in and walks them straight into setting their own '
                'password.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: palette.inkMuted),
              ),
              const SizedBox(height: VanamSpacing.md),
              FilledButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: shareText));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Copied — paste it to WhatsApp'),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.copy_all),
                label: const Text('Copy login details'),
              ),
              const SizedBox(height: VanamSpacing.sm),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InviteTile extends StatelessWidget {
  const _InviteTile({
    required this.invite,
    required this.onRevoked,
    required this.onIssueCredentials,
    required this.onResetPassword,
  });

  final Invite invite;
  final VoidCallback onRevoked;
  final VoidCallback onIssueCredentials;
  final VoidCallback onResetPassword;

  @override
  Widget build(BuildContext context) {
    final palette = context.vanam;
    final (label, color) = switch (invite.status) {
      MemberStatus.active => ('Active', palette.brand),
      MemberStatus.pending => ('Awaiting first login', palette.inkMuted),
      MemberStatus.revoked => ('Revoked', palette.danger),
      MemberStatus.needsCredentials => ('Needs login', palette.danger),
    };

    return Container(
      padding: const EdgeInsets.all(VanamSpacing.md),
      decoration: BoxDecoration(
        color: palette.surfaceCard,
        borderRadius: BorderRadius.circular(VanamRadii.card),
        border: Border.all(color: palette.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  invite.inviteeName,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: palette.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  invite.username ?? 'no login yet',
                  style: TextStyle(
                    fontSize: 12,
                    color: palette.inkMuted,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
          if (invite.status == MemberStatus.needsCredentials) ...[
            const SizedBox(width: VanamSpacing.xs),
            IconButton(
              tooltip: 'Issue login',
              icon: Icon(Icons.key, size: 18, color: palette.brand),
              onPressed: onIssueCredentials,
            ),
          ],
          if (invite.status == MemberStatus.active ||
              invite.status == MemberStatus.pending) ...[
            const SizedBox(width: VanamSpacing.xs),
            IconButton(
              tooltip: 'Reset password',
              icon: Icon(
                Icons.lock_reset,
                size: 18,
                color: palette.inkMuted,
              ),
              onPressed: onResetPassword,
            ),
            const SizedBox(width: VanamSpacing.xs),
            IconButton(
              tooltip: 'Revoke',
              icon: Icon(Icons.close, size: 18, color: palette.danger),
              onPressed: () async {
                await inviteService.revokeInvite(invite.id);
                onRevoked();
              },
            ),
          ],
        ],
      ),
    );
  }
}
