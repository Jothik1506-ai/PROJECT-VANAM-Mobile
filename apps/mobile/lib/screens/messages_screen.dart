import 'package:flutter/material.dart';

import '../models/conversation.dart';
import '../theme/tokens.dart';
import '../widgets/conversation_tile.dart';

/// Messages list screen — PREVIEW ONLY.
///
/// ARCHITECTURE.md's locked V1 messaging model (Section 1/9) is a single
/// family group with no per-contact DMs and no calling (Phase 2). This
/// screen shows a polished preview list; none of it is wired to a backend.
class MessagesScreen extends StatelessWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                VanamSpacing.md,
                VanamSpacing.sm,
                VanamSpacing.md,
                0,
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Messages',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: VanamColors.ink,
                      ),
                    ),
                  ),
                  Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      color: VanamColors.surfaceCard,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x14000000),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.search,
                      color: VanamColors.ink,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(
                VanamSpacing.md,
                VanamSpacing.md,
                VanamSpacing.md,
                VanamSpacing.sm,
              ),
              child: _EncryptedNotice(),
            ),
            Expanded(
              child: ListView.separated(
                itemCount: mockConversations.length,
                separatorBuilder: (context, index) => const Divider(
                  height: 1,
                  indent: VanamSpacing.md,
                  endIndent: VanamSpacing.md,
                  color: VanamColors.line,
                ),
                itemBuilder: (context, i) =>
                    ConversationTile(conversation: mockConversations[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EncryptedNotice extends StatelessWidget {
  const _EncryptedNotice();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(VanamSpacing.md),
      decoration: BoxDecoration(
        color: VanamColors.brand.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(VanamRadii.card),
        border: Border.all(color: VanamColors.brand.withValues(alpha: 0.14)),
      ),
      child: const Row(
        children: [
          Icon(Icons.lock_outline, color: VanamColors.brand, size: 18),
          SizedBox(width: VanamSpacing.sm),
          Expanded(
            child: Text(
              'Messages preview. V1 will use one encrypted family group.',
              style: TextStyle(color: VanamColors.brandDark, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
