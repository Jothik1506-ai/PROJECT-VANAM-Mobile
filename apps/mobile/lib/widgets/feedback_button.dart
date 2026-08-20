import 'package:flutter/material.dart';

import '../feedback/work_manager_feedback.dart';
import '../profile/profile_controller.dart';
import '../theme/tokens.dart';
import '../work_manager/work_manager_activity.dart';

class FeedbackButton extends StatelessWidget {
  const FeedbackButton({super.key, required this.screen});

  final String screen;

  @override
  Widget build(BuildContext context) {
    final palette = context.vanam;
    return FloatingActionButton.extended(
      onPressed: () => showFeedbackDialog(context, screen: screen),
      backgroundColor: palette.brand,
      foregroundColor: Colors.white,
      icon: const Icon(Icons.feedback_outlined),
      label: const Text('Feedback'),
    );
  }
}

Future<void> showFeedbackDialog(
  BuildContext context, {
  required String screen,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _FeedbackDialog(screen: screen),
  );
}

class _FeedbackDialog extends StatefulWidget {
  const _FeedbackDialog({required this.screen});

  final String screen;

  @override
  State<_FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<_FeedbackDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  final _feedbackController = TextEditingController();
  bool _isSending = false;
  String? _status;

  /// Normally true: the member already gave their real name once, during
  /// invite onboarding (see SetDisplayNameScreen) — feedback should never
  /// ask again, just show who it's from. Only falls back to an editable
  /// field if that local name is somehow missing (e.g. a very old install
  /// from before that name was saved locally too).
  bool get _hasKnownName => profileController.value.hasName;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: profileController.value.feedbackName,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _feedbackController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    setState(() {
      _isSending = true;
      _status = 'Sending feedback...';
    });

    try {
      await WorkManagerFeedback.send(
        name: _nameController.text,
        feedback: _feedbackController.text,
        screen: widget.screen,
      );
      await workManagerActivity.reportFeedbackSent();
      if (!mounted) return;
      _feedbackController.clear();
      setState(() => _status = 'Feedback sent to Work Manager.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = 'Could not send feedback. Please try again.');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.vanam;
    return AlertDialog(
      backgroundColor: palette.surfaceCard,
      title: Text(
        'Project Vanam feedback',
        style: TextStyle(color: palette.ink),
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sending from ${widget.screen}',
                style: TextStyle(color: palette.inkMuted, fontSize: 13),
              ),
              const SizedBox(height: VanamSpacing.md),
              if (_hasKnownName)
                Text(
                  'Sending as ${_nameController.text}',
                  style: TextStyle(color: palette.ink, fontSize: 13),
                )
              else
                TextFormField(
                  controller: _nameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(hintText: 'Your name'),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Add your name';
                    }
                    return null;
                  },
                ),
              const SizedBox(height: VanamSpacing.md),
              TextFormField(
                controller: _feedbackController,
                minLines: 4,
                maxLines: 6,
                decoration: const InputDecoration(
                  hintText: 'Type bug, fix, idea, or improvement',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Add feedback';
                  }
                  return null;
                },
              ),
              if (_status != null) ...[
                const SizedBox(height: VanamSpacing.sm),
                Text(
                  _status!,
                  style: TextStyle(
                    color: _status!.startsWith('Could')
                        ? palette.danger
                        : palette.brandStrong,
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSending ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: _isSending ? null : _submit,
          child: Text(_isSending ? 'Sending...' : 'Send'),
        ),
      ],
    );
  }
}
