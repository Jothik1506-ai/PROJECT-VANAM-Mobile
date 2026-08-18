import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../auth/auth_service.dart';
import '../theme/tokens.dart';
import '../widgets/feedback_button.dart';
import '../widgets/vanam_logo.dart';

/// Login screen — invite code + PIN only.
/// No password, no Google login, no OTP login, no self-signup: this app has
/// no open-registration path (see ARCHITECTURE.md, Section 3 / 3a).
///
/// [onSubmit] is injected so PreviewLoginGate can substitute a mock flow for
/// UI review without touching the real backend. When left unset (the real
/// V1 app, lib/main.dart), submitting calls the actual
/// `authService.redeemInvite` — see ARCHITECTURE.md Section 5.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.onSubmit});

  final Future<void> Function(String inviteCode, String pin)? onSubmit;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _inviteCodeController = TextEditingController();
  final _pinController = TextEditingController();
  bool _obscurePin = true;
  bool _isSubmitting = false;
  String? _errorText;

  @override
  void dispose() {
    _inviteCodeController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });

    final code = _inviteCodeController.text.trim().toUpperCase();
    final pin = _pinController.text.trim();

    try {
      if (widget.onSubmit != null) {
        await widget.onSubmit!(code, pin);
      } else {
        await authService.redeemInvite(code: code, pin: pin);
        // No further navigation here: main.dart doesn't yet route anywhere
        // after login (ARCHITECTURE.md Section 4/11A — Chat List screen
        // doesn't exist for the real app yet, only in the preview shell).
        // A successful redeemInvite with no error is the correct signal
        // that this step of the flow now genuinely works end-to-end.
      }
    } on InviteRedemptionException catch (e) {
      // The Postgres function's error text is already written for a human
      // — see supabase/schema.sql redeem_invite() — so show it directly
      // rather than a generic message that would hide *why* it failed
      // (wrong PIN vs expired vs already used vs locked).
      setState(() => _errorText = e.message);
    } catch (e) {
      setState(
        () => _errorText = 'Something went wrong. Check your connection and try again.',
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
                      controller: _inviteCodeController,
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[A-Za-z0-9-]'),
                        ),
                      ],
                      decoration: const InputDecoration(
                        hintText: 'Invite code',
                        prefixIcon: Icon(Icons.confirmation_number_outlined),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Enter the invite code your admin shared';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: VanamSpacing.md),
                    TextFormField(
                      controller: _pinController,
                      obscureText: _obscurePin,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      decoration: InputDecoration(
                        hintText: 'PIN',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePin
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: palette.inkMuted,
                          ),
                          onPressed: () =>
                              setState(() => _obscurePin = !_obscurePin),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().length < 4) {
                          return 'Enter the PIN your admin gave you';
                        }
                        return null;
                      },
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
                    const SizedBox(height: VanamSpacing.lg),
                    Text.rich(
                      TextSpan(
                        style: Theme.of(context).textTheme.bodyMedium,
                        children: [
                          const TextSpan(text: 'Need an invite? '),
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
