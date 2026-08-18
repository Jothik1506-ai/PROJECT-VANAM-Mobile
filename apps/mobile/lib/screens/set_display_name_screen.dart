import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import '../theme/tokens.dart';
import 'app_shell.dart';

/// Shown once, right after a successful invite redemption: the member picks
/// their own real name instead of being stuck with whatever the admin typed
/// into the invite dialog. Relation labels (Amma/Nanna/Akka...) are
/// viewer-relative — what's "Akka" to one member is someone else's
/// daughter-in-law — so V1 never assigns a name on someone else's behalf.
///
/// Deliberately just a name field. No other profile fields are mandatory.
class SetDisplayNameScreen extends StatefulWidget {
  const SetDisplayNameScreen({super.key, required this.isAdmin});

  final bool isAdmin;

  @override
  State<SetDisplayNameScreen> createState() => _SetDisplayNameScreenState();
}

class _SetDisplayNameScreenState extends State<SetDisplayNameScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  bool _isSubmitting = false;
  String? _errorText;

  @override
  void dispose() {
    _nameController.dispose();
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
      await authService.setOwnDisplayName(_nameController.text.trim());
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => AppShell(isAdmin: widget.isAdmin),
        ),
      );
    } on SetDisplayNameException catch (e) {
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
                    Text(
                      "What's your name?",
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: VanamSpacing.xs),
                    Text(
                      'This is how the rest of the family will see you.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: palette.inkMuted),
                    ),
                    const SizedBox(height: VanamSpacing.xl),
                    TextFormField(
                      controller: _nameController,
                      autofocus: true,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(hintText: 'Your name'),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Enter your name';
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
                          : const Text('Continue'),
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
