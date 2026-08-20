import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import '../theme/tokens.dart';

/// Self-service password reset — username + the one-time recovery code
/// shown once when an admin created/issued/reset the account (see
/// admin_invites_screen.dart's _InviteCreatedSheet). No admin needed for
/// this path; succeeding consumes the code (see
/// supabase/migrations/20260820030000_e2ee_and_password_recovery.sql).
/// A member who's lost their recovery code too still has the admin-reset
/// fallback — this doesn't replace that, it just avoids needing it.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _recoveryCodeController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscure = true;
  bool _isSubmitting = false;
  String? _errorText;
  bool _succeeded = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _recoveryCodeController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });

    try {
      await authService.resetPasswordWithRecoveryCode(
        username: _usernameController.text,
        recoveryCode: _recoveryCodeController.text,
        newPassword: _passwordController.text,
      );
      if (!mounted) return;
      setState(() => _succeeded = true);
    } on LoginException catch (e) {
      setState(() => _errorText = e.message);
    } catch (e) {
      setState(
        () => _errorText =
            'Something went wrong. Check your connection and try again.',
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.vanam;
    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: VanamSpacing.lg,
              vertical: VanamSpacing.xxl,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: _succeeded
                  ? _SuccessView(onDone: () => Navigator.of(context).pop())
                  : Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Enter your recovery code',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: VanamSpacing.xs),
                          Text(
                            'Your admin gave you this once, alongside your '
                            "username and password. If you don't have it, "
                            'ask your admin to reset your password instead.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: palette.inkMuted),
                          ),
                          const SizedBox(height: VanamSpacing.xl),
                          TextFormField(
                            controller: _usernameController,
                            autocorrect: false,
                            decoration: const InputDecoration(
                              hintText: 'Username',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Enter your username';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: VanamSpacing.md),
                          TextFormField(
                            controller: _recoveryCodeController,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              hintText: 'Recovery code',
                              prefixIcon: Icon(Icons.key_outlined),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Enter your recovery code';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: VanamSpacing.md),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscure,
                            decoration: InputDecoration(
                              hintText: 'New password',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  color: palette.inkMuted,
                                ),
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.length < 6) {
                                return 'At least 6 characters';
                              }
                              return null;
                            },
                            onFieldSubmitted: (_) => _handleSubmit(),
                          ),
                          if (_errorText != null) ...[
                            const SizedBox(height: VanamSpacing.sm),
                            Text(
                              _errorText!,
                              style: TextStyle(
                                color: palette.danger,
                                fontSize: 13,
                              ),
                            ),
                          ],
                          const SizedBox(height: VanamSpacing.lg),
                          ElevatedButton(
                            onPressed: _isSubmitting ? null : _handleSubmit,
                            child: _isSubmitting
                                ? const SizedBox(
                                    height: 22,
                                    width: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      valueColor: AlwaysStoppedAnimation(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : const Text('Reset password'),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SuccessView extends StatelessWidget {
  const _SuccessView({required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final palette = context.vanam;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.check_circle_outline, size: 64, color: palette.brand),
        const SizedBox(height: VanamSpacing.md),
        Text(
          'Password reset',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: VanamSpacing.xs),
        Text(
          'Log in with your username and new password.',
          textAlign: TextAlign.center,
          style: TextStyle(color: palette.inkMuted),
        ),
        const SizedBox(height: VanamSpacing.lg),
        ElevatedButton(onPressed: onDone, child: const Text('Back to Log In')),
      ],
    );
  }
}
