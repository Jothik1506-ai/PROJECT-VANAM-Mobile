import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../chat/chat_controller.dart';
import '../chat/chat_message.dart';
import '../chat/supabase_chat_sync.dart';
import '../chat/test_identity.dart';
import '../profile/profile_controller.dart';
import '../theme/tokens.dart';
import 'admin_invites_screen.dart';

/// Real, locally-working chat thread for the Family Group.
///
/// Messages are typed, sent, and persisted on THIS device only — there is
/// no backend yet, so nothing is shared between phones. This is the step
/// before real delivery: see ARCHITECTURE.md Section 6/10 for the planned
/// Cloudflare + E2EE backend that will eventually carry these messages
/// between family members' devices.
class ChatDetailScreen extends StatefulWidget {
  ChatDetailScreen({
    super.key,
    required this.groupName,
    this.isAdmin = false,
    ChatController? controller,
  }) : _controller = controller ?? familyGroupChat;

  final String groupName;
  final bool isAdmin;
  final ChatController _controller;

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  SupabaseChatSync? _sync;
  RealtimeChannel? _messagesChannel;
  String? _syncStatus;

  @override
  void initState() {
    super.initState();
    _attachSupabaseSync();
  }

  @override
  void dispose() {
    final channel = _messagesChannel;
    final sync = _sync;
    if (channel != null && sync != null) {
      sync.unsubscribe(channel);
    }
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _attachSupabaseSync() async {
    try {
      final client = Supabase.instance.client;
      if (client.auth.currentUser == null) return;

      final sync = SupabaseChatSync(client);
      await widget._controller.attachSync(sync);
      final channel = sync.subscribeToMessages(
        groupId: widget._controller.groupId,
        onChanged: widget._controller.refreshFromRemote,
      );
      if (!mounted) return;
      setState(() {
        _sync = sync;
        _messagesChannel = channel;
        _syncStatus = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _syncStatus = 'Offline mode - messages stay on this device',
      );
    }
  }

  Future<void> _send() async {
    final text = _textController.text;
    if (text.trim().isEmpty) return;

    final override = testSenderOverride.value;
    _textController.clear();
    try {
      await widget._controller.sendLocalMessage(
        text: text,
        senderName: override ?? profileController.value.displayName,
        isMine: override == null,
      );
    } catch (_) {
      _textController.text = text;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not send. Check connection and try again.'),
        ),
      );
      return;
    }

    if (!mounted) return;
    // New message lands at the end of the list — follow it.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _openIdentityPicker() async {
    final palette = context.vanam;
    final myName = profileController.value.displayName;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(VanamRadii.card),
        ),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: VanamSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: VanamSpacing.md,
                  ),
                  child: Text(
                    'Testing: chat as…',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: palette.ink,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    VanamSpacing.md,
                    2,
                    VanamSpacing.md,
                    VanamSpacing.sm,
                  ),
                  child: Text(
                    'One phone, simulating a multi-person chat. Not a real '
                    'account switch.',
                    style: TextStyle(fontSize: 12, color: palette.inkMuted),
                  ),
                ),
                ValueListenableBuilder<String?>(
                  valueListenable: testSenderOverride,
                  builder: (context, active, _) {
                    return Column(
                      children: [
                        _IdentityOption(
                          label: 'Me ($myName)',
                          selected: active == null,
                          onTap: () {
                            testSenderOverride.value = null;
                            Navigator.of(sheetContext).pop();
                          },
                        ),
                        for (final name in testIdentityChoices)
                          _IdentityOption(
                            label: name,
                            selected: active == name,
                            onTap: () {
                              testSenderOverride.value = name;
                              Navigator.of(sheetContext).pop();
                            },
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.vanam;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.surfaceCard,
        foregroundColor: palette.ink,
        elevation: 0,
        title: Text(
          widget.groupName,
          style: TextStyle(fontWeight: FontWeight.w700, color: palette.ink),
        ),
        actions: [
          if (widget.isAdmin)
            IconButton(
              tooltip: 'Family Invites',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AdminInvitesScreen()),
              ),
              icon: Icon(Icons.person_add_alt_1, color: palette.brand),
            ),
          IconButton(
            tooltip: 'Testing: chat as…',
            onPressed: _openIdentityPicker,
            icon: Icon(Icons.switch_account_outlined, color: palette.brand),
          ),
          Padding(
            padding: const EdgeInsets.only(right: VanamSpacing.md),
            child: Icon(Icons.lock_outline, size: 18, color: palette.brand),
          ),
        ],
      ),
      backgroundColor: palette.surface,
      body: Column(
        children: [
          ValueListenableBuilder<String?>(
            valueListenable: testSenderOverride,
            builder: (context, active, _) {
              if (active == null) return const SizedBox.shrink();
              return Container(
                width: double.infinity,
                color: palette.noticeSurface,
                padding: const EdgeInsets.symmetric(
                  horizontal: VanamSpacing.md,
                  vertical: VanamSpacing.xs,
                ),
                child: Text(
                  'Testing mode — chatting as $active',
                  style: TextStyle(fontSize: 12, color: palette.brandStrong),
                ),
              );
            },
          ),
          if (_syncStatus != null)
            Container(
              width: double.infinity,
              color: palette.noticeSurface,
              padding: const EdgeInsets.symmetric(
                horizontal: VanamSpacing.md,
                vertical: VanamSpacing.xs,
              ),
              child: Text(
                _syncStatus!,
                style: TextStyle(fontSize: 12, color: palette.brandStrong),
              ),
            ),
          Expanded(
            child: ValueListenableBuilder<List<ChatMessage>>(
              valueListenable: widget._controller,
              builder: (context, messages, _) {
                if (messages.isEmpty) {
                  return Center(
                    child: Text(
                      'No messages yet. Say hello to the family!',
                      style: TextStyle(color: palette.inkMuted),
                    ),
                  );
                }
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(VanamSpacing.md),
                  itemCount: messages.length,
                  itemBuilder: (context, i) => RepaintBoundary(
                    child: _MessageBubble(message: messages[i]),
                  ),
                );
              },
            ),
          ),
          _Composer(controller: _textController, onSend: _send),
        ],
      ),
    );
  }
}

class _IdentityOption extends StatelessWidget {
  const _IdentityOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.vanam;
    return ListTile(
      onTap: onTap,
      title: Text(label, style: TextStyle(color: palette.ink)),
      trailing: selected
          ? Icon(Icons.check_circle, color: palette.brand)
          : null,
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final palette = context.vanam;
    final alignment = message.isMine
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;
    final bubbleColor = message.isMine ? palette.brand : palette.surfaceCard;
    final textColor = message.isMine ? Colors.white : palette.ink;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: VanamSpacing.xs),
      child: Column(
        crossAxisAlignment: alignment,
        children: [
          if (!message.isMine)
            Padding(
              padding: const EdgeInsets.only(left: VanamSpacing.sm, bottom: 2),
              child: Text(
                message.senderName,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: palette.inkMuted,
                ),
              ),
            ),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.75,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: VanamSpacing.md,
                vertical: VanamSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(VanamRadii.field),
                  topRight: const Radius.circular(VanamRadii.field),
                  bottomLeft: Radius.circular(
                    message.isMine ? VanamRadii.field : 4,
                  ),
                  bottomRight: Radius.circular(
                    message.isMine ? 4 : VanamRadii.field,
                  ),
                ),
                border: message.isMine ? null : Border.all(color: palette.line),
              ),
              child: Text(message.text, style: TextStyle(color: textColor)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              _timeLabel(message.sentAt),
              style: TextStyle(fontSize: 10, color: palette.inkMuted),
            ),
          ),
        ],
      ),
    );
  }

  static String _timeLabel(DateTime time) {
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.onSend});

  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final palette = context.vanam;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          VanamSpacing.md,
          VanamSpacing.sm,
          VanamSpacing.sm,
          VanamSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: palette.surfaceCard,
          border: Border(top: BorderSide(color: palette.line)),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: 'Message the family…',
                  filled: true,
                  fillColor: palette.surface,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: VanamSpacing.md,
                    vertical: VanamSpacing.sm,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(VanamRadii.button),
                    borderSide: BorderSide(color: palette.line),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(VanamRadii.button),
                    borderSide: BorderSide(color: palette.line),
                  ),
                ),
              ),
            ),
            const SizedBox(width: VanamSpacing.xs),
            IconButton(
              onPressed: onSend,
              icon: Icon(Icons.send_rounded, color: palette.brand),
            ),
          ],
        ),
      ),
    );
  }
}
