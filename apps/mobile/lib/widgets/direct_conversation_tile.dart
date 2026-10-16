import 'package:flutter/material.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../chat/chat_attachment.dart';
import '../chat/direct_conversation.dart';
import '../chat/supabase_direct_chat_sync.dart';
import '../screens/chat_detail_screen.dart';
import '../theme/tokens.dart';
import 'member_avatar.dart';

/// A real, Supabase-backed direct-chat row — the other member's actual
/// display name (never a relation label), a preview of the last message if
/// any, and a tap target that opens the real per-pair chat thread.
class DirectConversationTile extends StatefulWidget {
  const DirectConversationTile({
    super.key,
    required this.conversation,
    this.onReturn,
  });

  final DirectConversation conversation;
  final Future<void> Function()? onReturn;

  @override
  State<DirectConversationTile> createState() => _DirectConversationTileState();
}

class _DirectConversationTileState extends State<DirectConversationTile> {
  DirectConversation get conversation => widget.conversation;
  String? _preview;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  @override
  void didUpdateWidget(DirectConversationTile old) {
    super.didUpdateWidget(old);
    if (old.conversation.lastMessageBody != conversation.lastMessageBody) {
      _preview = null;
      _loadPreview();
    }
  }

  Future<void> _loadPreview() async {
    if (conversation.lastMessageBody == null) return;
    final sync = SupabaseDirectChatSync(Supabase.instance.client);
    final plain = await sync.decryptPreview(conversation);
    if (!mounted || plain == null) return;
    final attachment = ChatAttachment.tryParse(plain);
    final text = attachment?.previewLabel ?? plain.replaceAll('\n', ' ');
    final mine =
        conversation.lastMessageSenderId != null &&
        conversation.lastMessageSenderId ==
            Supabase.instance.client.auth.currentUser?.id;
    setState(() => _preview = mine ? 'You: $text' : text);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.vanam;
    final preview = conversation.lastMessageAt == null
        ? 'Say hello!'
        : (_preview ?? 'Encrypted message');

    return InkWell(
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatDetailScreen.direct(
              otherDisplayName: conversation.otherDisplayName,
              conversationId: conversation.conversationId,
            ),
          ),
        );
        await widget.onReturn?.call();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: VanamSpacing.md,
          vertical: VanamSpacing.sm,
        ),
        child: Row(
          children: [
            MemberAvatar(name: conversation.otherDisplayName),
            const SizedBox(width: VanamSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    conversation.otherDisplayName,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: palette.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: palette.inkMuted),
                  ),
                ],
              ),
            ),
            if (conversation.lastMessageAt != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _timeLabel(conversation.lastMessageAt!),
                    style: TextStyle(fontSize: 11, color: palette.inkMuted),
                  ),
                  if (conversation.unreadCount > 0) ...[
                    const SizedBox(height: 4),
                    CircleAvatar(
                      radius: 10,
                      backgroundColor: palette.brand,
                      child: Text(
                        '${conversation.unreadCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }

  static String _timeLabel(DateTime time) {
    // See chat_detail_screen.dart's _timeLabel — sentAt/lastMessageAt come
    // back from Postgres as UTC and must be converted before reading
    // hour/minute, or the preview shows the sender's UTC time instead of
    // the reader's local time.
    final local = time.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }
}
