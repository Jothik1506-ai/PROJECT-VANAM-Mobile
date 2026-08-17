import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Generic placeholder for tabs not built yet (Reels, Messages, Profile in
/// the preview shell). PREVIEW-ONLY — real Messages/Profile screens are V1
/// work tracked separately in ARCHITECTURE.md; this is just nav scaffolding.
class ComingSoonScreen extends StatelessWidget {
  const ComingSoonScreen({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text(
          '$label — coming soon',
          style: const TextStyle(color: VanamColors.inkMuted, fontSize: 15),
        ),
      ),
    );
  }
}
