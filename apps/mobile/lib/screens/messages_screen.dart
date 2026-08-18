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
  const MessagesScreen({super.key, this.isAdmin = false});

  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final palette = context.vanam;
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
                  Expanded(
                    child: Text(
                      'Messages',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: palette.ink,
                      ),
                    ),
                  ),
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: palette.surfaceCard,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: palette.shadow, blurRadius: 6),
                      ],
                    ),
                    child: Icon(Icons.search, color: palette.ink, size: 20),
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
                separatorBuilder: (context, index) => Divider(
                  height: 1,
                  indent: VanamSpacing.md,
                  endIndent: VanamSpacing.md,
                  color: palette.line,
                ),
                itemBuilder: (context, i) => RepaintBoundary(
                  child: ConversationTile(
                    conversation: mockConversations[i],
                    isAdmin: isAdmin,
                  ),
                ),
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
    final palette = context.vanam;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(VanamSpacing.md),
      decoration: BoxDecoration(
        color: palette.noticeSurface,
        borderRadius: BorderRadius.circular(VanamRadii.card),
        border: Border.all(color: palette.noticeBorder),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline, color: palette.brand, size: 18),
          const SizedBox(width: VanamSpacing.sm),
          Expanded(
            child: Text(
              'Messages preview. V1 will use one encrypted family group.',
              style: TextStyle(color: palette.brandStrong, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
