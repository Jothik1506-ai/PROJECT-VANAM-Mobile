import 'package:flutter/material.dart';

import '../services/update/update_manifest.dart';
import '../services/update/update_service.dart';
import '../theme/tokens.dart';

/// Update dialog shown when a newer build is published.
///
/// VANAM is distributed outside the Play Store, so this is the only path a
/// family member has to receive a fix. A required update (installed build is
/// below minSupportedVersionCode) cannot be dismissed — no back button, no
/// barrier tap, no "Later".
///
/// See docs/OTA-RELEASES.md.
class UpdatePrompt extends StatefulWidget {
  const UpdatePrompt({
    super.key,
    required this.result,
    required this.service,
  });

  final UpdateCheckResult result;
  final UpdateService service;

  /// Shows the prompt. Returns when the user dismisses it (optional updates
  /// only) or once the installer has been handed the APK.
  static Future<void> show(
    BuildContext context, {
    required UpdateCheckResult result,
    required UpdateService service,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: !result.isRequired,
      builder: (_) => UpdatePrompt(result: result, service: service),
    );
  }

  @override
  State<UpdatePrompt> createState() => _UpdatePromptState();
}

class _UpdatePromptState extends State<UpdatePrompt> {
  double? _progress;
  bool _busy = false;
  String? _error;

  UpdateManifest get _manifest => widget.result.manifest!;

  Future<void> _startUpdate() async {
    setState(() {
      _busy = true;
      _error = null;
      _progress = 0;
    });

    try {
      final file = await widget.service.download(
        _manifest,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      await widget.service.install(file);
      if (mounted) Navigator.of(context).pop();
    } on UpdateIntegrityException {
      // Worth distinguishing: this means the bytes we got were not the bytes
      // we published, which is a different problem from a flaky network.
      if (mounted) {
        setState(() {
          _error =
              'The download was incomplete or altered. Please try again on a '
              'trusted network.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Update failed. Please check your connection.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.vanam;
    final required = widget.result.isRequired;

    return PopScope(
      // A required update must not be escapable via the system back gesture.
      canPop: !required,
      child: AlertDialog(
        backgroundColor: palette.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VanamRadii.card),
        ),
        title: Row(
          children: [
            Icon(
              required ? Icons.gpp_maybe_outlined : Icons.system_update_alt,
              color: palette.brand,
            ),
            const SizedBox(width: VanamSpacing.sm),
            Expanded(
              child: Text(
                required ? 'Update required' : 'Update available',
                style: TextStyle(
                  color: palette.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Version ${_manifest.latestVersionName}',
              style: TextStyle(
                color: palette.inkMuted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (_manifest.releaseNotes != null) ...[
              const SizedBox(height: VanamSpacing.sm),
              Text(
                _manifest.releaseNotes!,
                style: TextStyle(color: palette.ink, fontSize: 14),
              ),
            ],
            if (_manifest.releaseNotesTe != null) ...[
              const SizedBox(height: VanamSpacing.xs),
              Text(
                _manifest.releaseNotesTe!,
                style: TextStyle(color: palette.inkMuted, fontSize: 14),
              ),
            ],
            if (required) ...[
              const SizedBox(height: VanamSpacing.md),
              Text(
                'This update is needed to keep using Vanam safely.',
                style: TextStyle(color: palette.brandStrong, fontSize: 13),
              ),
            ],
            if (_busy) ...[
              const SizedBox(height: VanamSpacing.md),
              LinearProgressIndicator(
                value: _progress == 0 ? null : _progress,
                backgroundColor: palette.line,
                color: palette.brand,
              ),
              const SizedBox(height: VanamSpacing.xs),
              Text(
                _progress == null || _progress == 0
                    ? 'Starting download…'
                    : 'Downloading ${(_progress! * 100).toStringAsFixed(0)}%',
                style: TextStyle(color: palette.inkMuted, fontSize: 12),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: VanamSpacing.sm),
              Text(
                _error!,
                style: TextStyle(color: palette.danger, fontSize: 13),
              ),
            ],
          ],
        ),
        actions: [
          if (!required)
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: Text(
                'Later',
                style: TextStyle(color: palette.inkMuted),
              ),
            ),
          FilledButton(
            onPressed: _busy ? null : _startUpdate,
            child: Text(_error == null ? 'Update now' : 'Retry'),
          ),
        ],
      ),
    );
  }
}
