import 'package:flutter/material.dart';

import '../models/conversation.dart';
import '../theme/tokens.dart';
import '../widgets/conversation_tile.dart';

/// Messages list screen — PREVIEW ONLY.
///
/// ARCHITECTURE.md's locked V1 messaging model (Section 1/9) is a single
/// family group with no per-contact DMs and no calling (Phase 2). This
/// screen shows the fuller Chats/Calls + individual conversations mockup
/// for visual review; none of it is wired to a backend.
class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  bool _showingChats = true;

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
            Padding(
              padding: const EdgeInsets.all(VanamSpacing.md),
              child: _ChatsCallsToggle(
                showingChats: _showingChats,
                onChanged: (value) => setState(() => _showingChats = value),
              ),
            ),
            Expanded(
              child: _showingChats
                  ? ListView.separated(
                      itemCount: mockConversations.length,
                      separatorBuilder: (context, index) => const Divider(
                        height: 1,
                        indent: VanamSpacing.md,
                        endIndent: VanamSpacing.md,
                        color: VanamColors.line,
                      ),
                      itemBuilder: (context, i) =>
                          ConversationTile(conversation: mockConversations[i]),
                    )
                  : const Center(
                      child: Text(
                        'Call log coming soon',
                        style: TextStyle(color: VanamColors.inkMuted),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatsCallsToggle extends StatelessWidget {
  const _ChatsCallsToggle({required this.showingChats, required this.onChanged});

  final bool showingChats;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: VanamColors.brand.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(VanamRadii.button),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(
            child: _ToggleSegment(
              label: 'Chats',
              selected: showingChats,
              onTap: () => onChanged(true),
            ),
          ),
          Expanded(
            child: _ToggleSegment(
              label: 'Calls',
              selected: !showingChats,
              onTap: () => onChanged(false),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleSegment extends StatelessWidget {
  const _ToggleSegment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: VanamSpacing.sm),
        decoration: BoxDecoration(
          color: selected ? VanamColors.surfaceCard : Colors.transparent,
          borderRadius: BorderRadius.circular(VanamRadii.button - 4),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: selected ? VanamColors.brand : VanamColors.inkMuted,
          ),
        ),
      ),
    );
  }
}
