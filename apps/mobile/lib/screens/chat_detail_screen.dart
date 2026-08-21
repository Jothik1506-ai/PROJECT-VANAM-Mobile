import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../chat/chat_controller.dart';
import '../chat/chat_message.dart';
import '../chat/supabase_chat_sync.dart';
import '../chat/supabase_direct_chat_sync.dart';
import '../notifications/active_chat_tracker.dart';
import '../profile/profile_controller.dart';
import '../theme/tokens.dart';
import 'admin_invites_screen.dart';

enum ChatDetailMode { familyGroup, direct }

/// Real chat thread — either the one Family Group, or a direct/personal
/// chat with one other member. One screen, not two, per mode/params
/// preference: the two modes differ only in which Supabase sync target
/// they attach (family group's shared `messages` table + ChatController's
/// local cache, vs. a direct conversation's per-pair `direct_messages`
/// table with no local cache) — the rest of the UI is identical.
class ChatDetailScreen extends StatefulWidget {
  // Cannot be const because the default family-group controller is runtime state.
  // ignore: prefer_const_constructors_in_immutables
  ChatDetailScreen({
    super.key,
    required this.groupName,
    this.isAdmin = false,
    ChatController? controller,
  }) : mode = ChatDetailMode.familyGroup,
       _controller = controller ?? familyGroupChat,
       conversationId = null;

  const ChatDetailScreen.direct({
    super.key,
    required String otherDisplayName,
    required this.conversationId,
  }) : groupName = otherDisplayName,
       isAdmin = false,
       mode = ChatDetailMode.direct,
       _controller = null;

  final String groupName;
  final bool isAdmin;
  final ChatDetailMode mode;
  final String? conversationId;

  /// Only set (and only used) in familyGroup mode.
  final ChatController? _controller;

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();

  /// Family-group mode reads/writes through widget._controller directly
  /// (it's already the source of truth, with its own local cache). Direct
  /// mode has no persistent controller of its own, so this notifier is
  /// state-owned and fed by fetch + Realtime instead.
  late final ValueNotifier<List<ChatMessage>> _messages =
      widget.mode == ChatDetailMode.familyGroup
      ? widget._controller!
      : ValueNotifier<List<ChatMessage>>(const []);

  SupabaseChatSync? _familySync;
  SupabaseDirectChatSync? _directSync;
  RealtimeChannel? _messagesChannel;
  String? _syncStatus;

  /// The scope key this screen registers with activeChatTracker so a
  /// foreground push for this exact chat gets suppressed (see
  /// push_notification_service.dart) — same key shape the Edge Function's
  /// notification data uses.
  late final String _activeScope = widget.mode == ChatDetailMode.familyGroup
      ? ActiveChatTracker.familyGroupScope
      : ActiveChatTracker.directScope(widget.conversationId!);

  @override
  void initState() {
    super.initState();
    activeChatTracker.setActive(_activeScope);
    _attachSupabaseSync();
  }

  @override
  void dispose() {
    activeChatTracker.clearIfActive(_activeScope);
    final channel = _messagesChannel;
    if (channel != null) {
      if (_familySync != null) {
        _familySync!.unsubscribe(channel);
      } else if (_directSync != null) {
        _directSync!.unsubscribe(channel);
      }
    }
    if (widget.mode == ChatDetailMode.direct) {
      _messages.dispose();
    }
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _attachSupabaseSync() async {
    try {
      final client = Supabase.instance.client;
      if (client.auth.currentUser == null) return;

      if (widget.mode == ChatDetailMode.familyGroup) {
        final sync = SupabaseChatSync(client);
        await widget._controller!.attachSync(sync);
        final channel = sync.subscribeToMessages(
          groupId: widget._controller!.groupId,
          onChanged: widget._controller!.refreshFromRemote,
        );
        if (!mounted) return;
        setState(() {
          _familySync = sync;
          _messagesChannel = channel;
          _syncStatus = null;
        });
        return;
      }

      final conversationId = widget.conversationId!;
      final sync = SupabaseDirectChatSync(client);
      _messages.value = await sync.fetchMessages(
        conversationId: conversationId,
      );
      // Mark anything already sitting unread as read now that this screen
      // is open, then again after every realtime refresh — cheap/idempotent
      // (see SupabaseDirectChatSync.markRead), and is what turns the
      // sender's tick blue on their device.
      unawaited(sync.markRead(conversationId));
      final channel = sync.subscribeToMessages(
        conversationId: conversationId,
        onChanged: () async {
          _messages.value = await sync.fetchMessages(
            conversationId: conversationId,
          );
          unawaited(sync.markRead(conversationId));
        },
      );
      if (!mounted) return;
      setState(() {
        _directSync = sync;
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

    _textController.clear();
    try {
      if (widget.mode == ChatDetailMode.familyGroup) {
        await widget._controller!.sendLocalMessage(
          text: text,
          senderName: profileController.value.displayName,
        );
      } else {
        final sync = _directSync;
        if (sync == null) {
          throw StateError('Direct chat sync not ready');
        }
        final message = await sync.sendMessage(
          conversationId: widget.conversationId!,
          text: text,
        );
        _messages.value = [..._messages.value, message]
          ..sort((a, b) => a.sentAt.compareTo(b.sentAt));
      }
    } catch (error) {
      _textController.text = text;
      if (!mounted) return;
      final encryptionSyncing = error.toString().contains(
        'Encryption key not ready',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            encryptionSyncing
                ? 'Encryption is syncing. Ask the other family member to open this chat, then try again.'
                : 'Could not send. Check connection and try again.',
          ),
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
          Padding(
            padding: const EdgeInsets.only(right: VanamSpacing.md),
            child: Icon(Icons.lock_outline, size: 18, color: palette.brand),
          ),
        ],
      ),
      backgroundColor: palette.surface,
      body: Column(
        children: [
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
              valueListenable: _messages,
              builder: (context, messages, _) {
                if (messages.isEmpty) {
                  return Center(
                    child: Text(
                      widget.mode == ChatDetailMode.familyGroup
                          ? 'No messages yet. Say hello to the family!'
                          : 'No messages yet. Say hello to ${widget.groupName}!',
                      style: TextStyle(color: palette.inkMuted),
                    ),
                  );
                }
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(VanamSpacing.md),
                  itemCount: messages.length,
                  itemBuilder: (context, i) {
                    final message = messages[i];
                    return RepaintBoundary(
                      child: message.kind == ChatMessageKind.system
                          ? _SystemEventNotice(message: message)
                          : _MessageBubble(
                              message: message,
                              showReadReceipt:
                                  widget.mode == ChatDetailMode.direct,
                            ),
                    );
                  },
                );
              },
            ),
          ),
          _Composer(
            controller: _textController,
            onSend: _send,
            hintText: widget.mode == ChatDetailMode.familyGroup
                ? 'Message the family…'
                : 'Message ${widget.groupName}…',
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.showReadReceipt});

  final ChatMessage message;

  /// Only true in direct-message mode — the family group has no per-message
  /// N-way read receipt, so a tick there would misleadingly imply tracking
  /// that doesn't exist.
  final bool showReadReceipt;

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
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _timeLabel(message.sentAt),
                  style: TextStyle(fontSize: 10, color: palette.inkMuted),
                ),
                if (showReadReceipt && message.isMine) ...[
                  const SizedBox(width: 3),
                  Icon(
                    message.readAt != null ? Icons.done_all : Icons.done,
                    size: 13,
                    color: message.readAt != null
                        ? palette.brand
                        : palette.inkMuted,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _timeLabel(DateTime time) {
    // sentAt is parsed from Postgres's timestamptz (UTC) — must convert to
    // local before reading hour/minute, or every message shows the sender's
    // UTC send time instead of the reader's own clock time (e.g. IST readers
    // saw messages sent at 12:14 PM local labeled 6:45 AM).
    final local = time.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }
}

/// A system event ("`<Name>` joined Vanam") — centered notice text, never a
/// chat bubble, and never attributed to "me" or "them" either way.
class _SystemEventNotice extends StatelessWidget {
  const _SystemEventNotice({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final palette = context.vanam;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: VanamSpacing.sm),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: VanamSpacing.md,
            vertical: VanamSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: palette.noticeSurface,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            message.text,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: palette.brandStrong),
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.onSend,
    required this.hintText,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final String hintText;

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
                  hintText: hintText,
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
