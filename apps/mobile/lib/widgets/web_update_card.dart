import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../models/web_update.dart';
import '../theme/tokens.dart';

class WebUpdateCard extends StatelessWidget {
  const WebUpdateCard({super.key, required this.update});

  final WebUpdate update;

  Uri get _uri => Uri.parse('${AppConfig.vanamWebBaseUrl}/${update.path}');

  Future<void> _open(BuildContext context) async {
    final uri = _uri;
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (opened || !context.mounted) return;

    await Clipboard.setData(ClipboardData(text: uri.toString()));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open page. Link copied.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.vanam;
    return Container(
      margin: const EdgeInsets.only(bottom: VanamSpacing.md),
      padding: const EdgeInsets.all(VanamSpacing.md),
      decoration: BoxDecoration(
        color: palette.surfaceCard,
        borderRadius: BorderRadius.circular(VanamRadii.card),
        border: Border.all(color: palette.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.noticeSurface,
              borderRadius: BorderRadius.circular(VanamRadii.field),
              border: Border.all(color: palette.noticeBorder),
            ),
            child: Icon(Icons.public_outlined, color: palette.brand),
          ),
          const SizedBox(width: VanamSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  update.status,
                  style: TextStyle(
                    color: palette.brandStrong,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  update.title,
                  style: TextStyle(
                    color: palette.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: VanamSpacing.xs),
                Text(
                  update.description,
                  style: TextStyle(
                    color: palette.inkMuted,
                    fontSize: 13,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: VanamSpacing.sm),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _open(context),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('Open page'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
