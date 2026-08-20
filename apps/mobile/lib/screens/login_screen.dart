import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import '../theme/tokens.dart';
import '../widgets/feedback_button.dart';
import '../widgets/vanam_logo.dart';
import 'app_shell.dart';
import 'forgot_password_screen.dart';
import 'qr_scan_screen.dart';
import 'set_display_name_screen.dart';
import 'set_password_screen.dart';

/// Login screen — username + password, admin-issued (see
/// ARCHITECTURE.md Section 5). Still no open self-signup: only an admin can
/// create a member account, either from the Admin screen (which shows a
/// username + default password and a QR code encoding both) or by scanning
/// that QR here.
///
/// [onSubmit] is injected so PreviewLoginGate can substitute a mock flow for
/// UI review without touching the real backend. When left unset (the real
/// V1 app, lib/main.dart), submitting calls the actual
/// `authService.signInWithUsernamePassword`.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.onSubmit});

  final Future<void> Function(String username, String password)? onSubmit;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isSubmitting = false;
  String? _errorText;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _scanQr() async {
    final result = await Navigator.of(context).push<(String, String)>(
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
    if (result == null || !mounted) return;

    final (username, password) = result;
    setState(() {
      _usernameController.text = username;
      _passwordController.text = password;
    });
    // A scanned code is already exact — no reason to make the person tap
    // Log In too after they just pointed a camera at it.
    await _handleSubmit();
  }

  Future<void> _handleSubmit() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });

    final username = _usernameController.text.trim().toLowerCase();
    final password = _passwordController.text;

    try {
      if (widget.onSubmit != null) {
        await widget.onSubmit!(username, password);
      } else {
        await authService.signInWithUsernamePassword(
          username: username,
          password: password,
        );
        final profile = await authService.fetchMyProfile();
        if (!mounted) return;
        // pushReplacement, not push: Login shouldn't be reachable via back
        // once sign-in succeeds — there's nothing to "go back" to.
        final isAdmin = profile?.isAdmin ?? false;
        final nameConfirmed = profile?.nameConfirmed ?? true;
        final passwordChanged = profile?.passwordChanged ?? true;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => !passwordChanged
                ? SetPasswordScreen(
                    isAdmin: isAdmin,
                    nameConfirmed: nameConfirmed,
                  )
                : !nameConfirmed
                ? SetDisplayNameScreen(isAdmin: isAdmin)
                : AppShell(isAdmin: isAdmin),
          ),
        );
      }
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
      floatingActionButton: const FeedbackButton(screen: 'Login'),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: VanamSpacing.lg,
              vertical: VanamSpacing.xxl,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: VanamLogo(size: 96)),
                    const SizedBox(height: VanamSpacing.lg),
                    Text(
                      'Welcome to Vanam',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: VanamSpacing.xs),
                    Text(
                      'Your family, always connected',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: VanamSpacing.xl),
                    TextFormField(
                      controller: _usernameController,
                      textCapitalization: TextCapitalization.none,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        hintText: 'Username',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Enter the username your admin gave you';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: VanamSpacing.md),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        hintText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: palette.inkMuted,
                          ),
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Enter your password';
                        }
                        return null;
                      },
                      onFieldSubmitted: (_) => _handleSubmit(),
                    ),
                    if (_errorText != null) ...[
                      const SizedBox(height: VanamSpacing.sm),
                      Text(
                        _errorText!,
                        style: TextStyle(color: palette.danger, fontSize: 13),
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
                          : const Text('Log In'),
                    ),
                    const SizedBox(height: VanamSpacing.sm),
                    OutlinedButton.icon(
                      onPressed: _isSubmitting ? null : _scanQr,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Scan QR instead'),
                    ),
                    const SizedBox(height: VanamSpacing.sm),
                    TextButton(
                      onPressed: _isSubmitting
                          ? null
                          : () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const ForgotPasswordScreen(),
                              ),
                            ),
                      child: const Text('Forgot password?'),
                    ),
                    const SizedBox(height: VanamSpacing.lg),
                    Text.rich(
                      TextSpan(
                        style: Theme.of(context).textTheme.bodyMedium,
                        children: [
                          const TextSpan(text: 'Need an account? '),
                          TextSpan(
                            text: 'Contact your family admin.',
                            style: TextStyle(
                              color: palette.brand,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
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
