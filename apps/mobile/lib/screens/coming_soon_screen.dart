import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Polished preview placeholder for deferred tabs.
class ComingSoonScreen extends StatelessWidget {
  const ComingSoonScreen({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.all(VanamSpacing.lg),
            padding: const EdgeInsets.all(VanamSpacing.xl),
            decoration: BoxDecoration(
              color: VanamColors.surfaceCard,
              borderRadius: BorderRadius.circular(VanamRadii.card),
              border: Border.all(color: VanamColors.line),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.forest_outlined,
                  color: VanamColors.brand,
                  size: 42,
                ),
                const SizedBox(height: VanamSpacing.md),
                Text(
                  label,
                  style: const TextStyle(
                    color: VanamColors.ink,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: VanamSpacing.sm),
                const Text(
                  'Planned for a later phase',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: VanamColors.inkMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
