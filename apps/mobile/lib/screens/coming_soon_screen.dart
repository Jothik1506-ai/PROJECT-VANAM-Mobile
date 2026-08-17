import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Polished preview placeholder for deferred tabs.
class ComingSoonScreen extends StatelessWidget {
  const ComingSoonScreen({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.vanam;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.all(VanamSpacing.lg),
            padding: const EdgeInsets.all(VanamSpacing.xl),
            decoration: BoxDecoration(
              color: palette.surfaceCard,
              borderRadius: BorderRadius.circular(VanamRadii.card),
              border: Border.all(color: palette.line),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.forest_outlined, color: palette.brand, size: 42),
                const SizedBox(height: VanamSpacing.md),
                Text(
                  label,
                  style: TextStyle(
                    color: palette.ink,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: VanamSpacing.sm),
                Text(
                  'Planned for a later phase',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: palette.inkMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
