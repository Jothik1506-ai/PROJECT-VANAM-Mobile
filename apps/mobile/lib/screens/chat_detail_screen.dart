import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../chat/attachment_picker.dart';
import '../chat/attachment_service.dart';
import '../chat/chat_attachment.dart';
import '../chat/chat_controller.dart';
import '../chat/chat_message.dart';
import '../chat/supabase_chat_sync.dart';
import '../chat/supabase_direct_chat_sync.dart';
import '../crypto/key_sync_service.dart';
import '../diagnostics/crash_reporting.dart';
import '../notifications/active_chat_tracker.dart';
import '../profile/profile_controller.dart';
import '../theme/tokens.dart';
import '../widgets/chat_attachment_view.dart';
import '../widgets/feedback_button.dart';
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

  /// Files being sent, by pending-message id. Kept so a failed send can be
  /// retried without picking the file again (or uploading it twice).
  final _uploads = <String, PickedAttachment>{};

  String get _scope =>
      widget.mode == ChatDetailMode.familyGroup ? 'group' : 'direct';
  String get _scopeId => widget.mode == ChatDetailMode.familyGroup
      ? widget._controller!.groupId
      : widget.conversationId!;

  final _scrollController = ScrollController();

  /// Family-group mode reads/writes through widget._controller directly
  /// (it's already the source of truth, with its own local cache). Direct
  /// mode has no persistent controller of its own, so this notifier is
  /// state-owned and fed by fetch + Realtime instead.
  late final ValueNotifier<List<ChatMessage>> _messages =
      widget.mode == ChatDetailMode.familyGroup
      ? widget._controller!
      : ValueNotifier<List<ChatMessage>>(const []);

  /// Messages typed but not yet confirmed by the server. Kept apart from
  /// [_messages] so a realtime refresh can't wipe them mid-send.
  final ValueNotifier<List<ChatMessage>> _pending =
      ValueNotifier<List<ChatMessage>>(const []);

  SupabaseChatSync? _familySync;
  SupabaseDirectChatSync? _directSync;
  RealtimeChannel? _messagesChannel;
  String? _syncStatus;
  bool _keyMissingOnDevice = false;

  // Direct mode's _messages is disposed in dispose() (unlike family-group
  // mode, which reuses the long-lived shared controller) — a realtime
  // onChanged callback that's already mid-fetch when the screen closes
  // must not write into it afterward. mounted alone isn't quite enough
  // here since dispose() explicitly disposes this notifier itself.
  bool _disposed = false;
  // Realtime can fire onChanged again before a previous fetchMessages call
  // finishes (e.g. several messages arriving in quick succession) — without
  // this, two overlapping fetches could resolve out of order and let a
  // stale response overwrite a newer one. Only the response matching the
  // latest request actually gets applied.
  int _refreshRequestId = 0;
  bool _initialScrollDone = false;
  bool _initialScrollScheduled = false;

  // "Load earlier messages": the server hands out the newest page, so
  // scrolling to the top fetches the page before the oldest one shown.
  bool _loadingOlder = false;
  // Direct mode tracks this itself; family-group mode asks the controller.
  bool _directHasOlder = false;

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
    _scrollController.addListener(_maybeLoadOlder);
    unawaited(
      CrashReporting.setContext(screen: 'Chat', chatScope: _activeScope),
    );
    _messages.addListener(_handleMessagesChanged);
    _pending.addListener(_handleMessagesChanged);
    _attachSupabaseSync();
  }

  @override
  void dispose() {
    _disposed = true;
    activeChatTracker.clearIfActive(_activeScope);
    unawaited(CrashReporting.setContext(screen: 'Messages'));
    _messages.removeListener(_handleMessagesChanged);
    _pending.removeListener(_handleMessagesChanged);
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
    _pending.dispose();
    _textController.dispose();
    _scrollController.removeListener(_maybeLoadOlder);
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
        // subscribeToMessages already created and subscribed the channel
        // above — if the screen was closed while we were awaiting
        // attachSync, this check used to run too late and the channel's
        // reference (and thus any way to unsubscribe it in dispose()) was
        // silently discarded, leaking a live Realtime socket subscription
        // for the rest of the app's life. Unsubscribe it here instead.
        if (!mounted) {
          unawaited(sync.unsubscribe(channel));
          return;
        }
        setState(() {
          _familySync = sync;
          _messagesChannel = channel;
          _syncStatus = null;
          _keyMissingOnDevice = false;
        });
        return;
      }

      final conversationId = widget.conversationId!;
      final sync = SupabaseDirectChatSync(client);
      final initialRequestId = ++_refreshRequestId;
      final initialMessages = await sync.fetchMessages(
        conversationId: conversationId,
      );
      // _messages is disposed in dispose() for direct mode — a screen
      // closed while this initial fetch was in flight must not write into
      // it afterward.
      if (_disposed) return;
      if (initialRequestId == _refreshRequestId) {
        _messages.value = initialMessages;
        _directHasOlder =
            initialMessages.length >= SupabaseDirectChatSync.pageSize;
      }
      // Mark anything already sitting unread as read now that this screen
      // is open, then again after every realtime refresh — cheap/idempotent
      // (see SupabaseDirectChatSync.markRead), and is what turns the
      // sender's tick blue on their device.
      unawaited(sync.markRead(conversationId));
      final channel = sync.subscribeToMessages(
        conversationId: conversationId,
        onChanged: () async {
          // Two realtime events arriving close together could otherwise
          // start overlapping fetches that resolve out of order, letting a
          // stale response clobber a newer one — only the response
          // matching the most recently *started* request gets applied.
          final requestId = ++_refreshRequestId;
          final messages = await sync.fetchMessages(
            conversationId: conversationId,
          );
          if (_disposed || requestId != _refreshRequestId) return;
          _messages.value = _mergeNewestPage(_messages.value, messages);
          unawaited(sync.markRead(conversationId));
        },
      );
      // Same leak risk as the family-group branch above: the channel is
      // already live by this point, so a closed screen must explicitly
      // unsubscribe it rather than just dropping the reference.
      if (!mounted) {
        unawaited(sync.unsubscribe(channel));
        return;
      }
      setState(() {
        _directSync = sync;
        _messagesChannel = channel;
        _syncStatus = null;
        _keyMissingOnDevice = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _keyMissingOnDevice = error is EncryptionKeyMissingOnDeviceException;
        _syncStatus = _keyMissingOnDevice
            ? 'Encryption key is missing on this device.'
            : error is TimeoutException
            ? 'Message sync is taking too long. Check your connection.'
            : 'Could not sync messages. Your saved messages are still available.';
      });
    }
  }

  Future<void> _showAttachMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Photos'),
              subtitle: const Text('Choose up to 10 from your gallery'),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: const Text('Document'),
              subtitle: const Text('PDF, Word, Excel and more · up to 15 MB'),
              onTap: () => Navigator.pop(context, 'document'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    try {
      final result = switch (choice) {
        'gallery' => await AttachmentPicker.gallery(),
        'camera' => await AttachmentPicker.camera(),
        _ => await AttachmentPicker.documents(),
      };
      if (!mounted) return;
      if (result.tooLarge > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.tooLarge == 1
                  ? 'One file was skipped: files can be up to 15 MB.'
                  : '${result.tooLarge} files were skipped: files can be up to 15 MB.',
            ),
          ),
        );
      }
      for (final item in result.items) {
        unawaited(_sendAttachment(item));
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open your files.')),
      );
    }
  }

  /// Shows the attachment in the thread right away (clock icon), then
  /// encrypts, uploads and sends it in the background.
  Future<void> _sendAttachment(PickedAttachment item) async {
    final pendingMessage = ChatMessage(
      id: 'pending-${DateTime.now().microsecondsSinceEpoch}-${_uploads.length}',
      senderName: profileController.value.displayName,
      text: item.placeholderText,
      sentAt: DateTime.now(),
      isMine: true,
      pending: true,
    );
    _uploads[pendingMessage.id] = item;
    _pending.value = [..._pending.value, pendingMessage];
    await _deliver(pendingMessage);
  }

  Future<void> _send() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    // Show the message right away; encryption + the network round trip
    // finish in the background and the confirmed message replaces it.
    final pendingMessage = ChatMessage(
      id: 'pending-${DateTime.now().microsecondsSinceEpoch}',
      senderName: profileController.value.displayName,
      text: text,
      sentAt: DateTime.now(),
      isMine: true,
      pending: true,
    );
    _pending.value = [..._pending.value, pendingMessage];
    _textController.clear();
    await _deliver(pendingMessage);
  }

  /// Tap on a failed message: try sending it again in place.
  Future<void> _retry(ChatMessage failed) async {
    _replacePending(failed.id, failed.copyWith(pending: true, failed: false));
    await _deliver(failed);
  }

  void _discard(ChatMessage failed) {
    final upload = _uploads.remove(failed.id);
    final uploaded = upload?.uploaded;
    if (uploaded != null) unawaited(chatAttachmentService.discard(uploaded));
    _removePending(failed.id);
  }

  Future<void> _deliver(ChatMessage pendingMessage) async {
    var text = pendingMessage.text;
    final upload = _uploads[pendingMessage.id];
    try {
      if (upload != null) {
        // Upload once; a retry after a failed message send reuses the file.
        upload.uploaded ??= await chatAttachmentService.upload(
          scope: _scope,
          scopeId: _scopeId,
          bytes: upload.bytes,
          name: upload.name,
          mime: upload.mime,
          kind: upload.kind,
        );
        text = upload.uploaded!.encode();
      }
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
        if (!_disposed) {
          final next = _messages.value.where((m) => m.id != message.id).toList()
            ..add(message)
            ..sort((a, b) => a.sentAt.compareTo(b.sentAt));
          _messages.value = next;
        }
      }
      _uploads.remove(pendingMessage.id);
      _removePending(pendingMessage.id);
    } catch (error, stack) {
      if (error is AttachmentTooLargeException) {
        _uploads.remove(pendingMessage.id);
        _removePending(pendingMessage.id);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(error.toString())));
        }
        return;
      }
      unawaited(
        CrashReporting.recordError(error, stack, reason: 'chat_send_failed'),
      );
      // Keep the message in the thread, marked "Not sent", so the user can
      // tap to retry instead of retyping it.
      _replacePending(
        pendingMessage.id,
        pendingMessage.copyWith(pending: false, failed: true),
      );
      if (!mounted) return;
      final encryptionSyncing = error is EncryptionKeyUnavailableException;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: encryptionSyncing
              ? const Duration(seconds: 10)
              : const Duration(seconds: 4),
          content: Text(
            encryptionSyncing
                ? "This chat's encryption key hasn't reached this phone yet. "
                      'It usually fixes itself once another member opens '
                      "Vanam. If it stays stuck, reset encryption."
                : 'Could not send. Check connection and tap the message to retry.',
          ),
          action: encryptionSyncing
              ? SnackBarAction(
                  label: 'Reset',
                  onPressed: _confirmResetEncryption,
                )
              : null,
        ),
      );
    }
  }

  void _replacePending(String id, ChatMessage replacement) {
    if (_disposed) return;
    _pending.value = [
      for (final m in _pending.value) m.id == id ? replacement : m,
    ];
  }

  void _removePending(String id) {
    if (_disposed) return;
    _pending.value = _pending.value.where((m) => m.id != id).toList();
  }

  /// Keeps already-loaded older pages when the newest page is refetched.
  static List<ChatMessage> _mergeNewestPage(
    List<ChatMessage> current,
    List<ChatMessage> newest,
  ) {
    if (newest.isEmpty) return newest;
    final cutoff = newest.first.sentAt;
    final older = current.where((m) => m.sentAt.isBefore(cutoff));
    return [...older, ...newest];
  }

  bool get _hasOlder => widget.mode == ChatDetailMode.familyGroup
      ? widget._controller!.hasOlder
      : _directHasOlder;

  void _maybeLoadOlder() {
    if (!_scrollController.hasClients || !_initialScrollDone) return;
    if (_scrollController.position.pixels > 120) return;
    unawaited(_loadOlder());
  }

  Future<void> _loadOlder() async {
    if (_loadingOlder || !_hasOlder) return;
    setState(() => _loadingOlder = true);
    // Remember how far from the bottom we are so prepending doesn't jump.
    final before = _scrollController.hasClients
        ? _scrollController.position.maxScrollExtent -
              _scrollController.position.pixels
        : 0.0;
    try {
      if (widget.mode == ChatDetailMode.familyGroup) {
        await widget._controller!.loadOlder();
      } else {
        final sync = _directSync;
        final current = _messages.value;
        if (sync == null || current.isEmpty) return;
        final older = await sync.fetchMessages(
          conversationId: widget.conversationId!,
          before: current.first.sentAt,
        );
        if (_disposed) return;
        _directHasOlder = older.length >= SupabaseDirectChatSync.pageSize;
        final known = current.map((m) => m.id).toSet();
        final fresh = older.where((m) => known.add(m.id)).toList();
        if (fresh.isNotEmpty) _messages.value = [...fresh, ...current];
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        _scrollController.jumpTo(
          _scrollController.position.maxScrollExtent - before,
        );
      });
    } catch (_) {
      // Leave the thread as is; scrolling up again retries.
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  void _handleMessagesChanged() {
    final shouldFollow = !_scrollController.hasClients || _isNearBottom;
    if (!shouldFollow) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
  }

  bool get _isNearBottom {
    if (!_scrollController.hasClients) return true;
    return _scrollController.position.maxScrollExtent -
            _scrollController.position.pixels <=
        80;
  }

  void _scrollToEnd({bool jump = false}) {
    if (!mounted || !_scrollController.hasClients) return;
    final end = _scrollController.position.maxScrollExtent;
    if (jump) {
      _scrollController.jumpTo(end);
      return;
    }
    _scrollController.animateTo(
      end,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  void _scheduleInitialScroll() {
    if (_initialScrollDone || _initialScrollScheduled) return;
    _initialScrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialScrollScheduled = false;
      if (!mounted || _initialScrollDone) return;
      if (!_scrollController.hasClients) {
        _scheduleInitialScroll();
        return;
      }
      _scrollToEnd(jump: true);
      _initialScrollDone = true;
    });
  }

  Future<void> _confirmResetEncryption() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset encryption?'),
        content: const Text(
          'This creates a new encryption key for this chat and shares it '
          'with its members. Messages sent before the reset stay unreadable. '
          'Only do this if the chat has been stuck for a while.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      if (widget.mode == ChatDetailMode.familyGroup) {
        final sync = _familySync ?? SupabaseChatSync(Supabase.instance.client);
        await sync.resetEncryption(groupId: widget._controller!.groupId);
        await widget._controller!.refreshFromRemote();
      } else {
        final sync =
            _directSync ?? SupabaseDirectChatSync(Supabase.instance.client);
        await sync.resetEncryption(widget.conversationId!);
        await _attachSupabaseSync();
        return;
      }
      if (mounted) {
        setState(() {
          _keyMissingOnDevice = false;
          _syncStatus = null;
        });
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not reset encryption. Try again shortly.'),
        ),
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
          FeedbackIconButton(
            screen: 'Chat',
            color: palette.brand,
            chatId: widget.mode == ChatDetailMode.familyGroup
                ? widget._controller!.groupId
                : widget.conversationId!,
            chatType: widget.mode == ChatDetailMode.familyGroup
                ? 'family group'
                : 'direct',
            chatName: widget.groupName,
            itemId: widget.mode == ChatDetailMode.familyGroup
                ? widget._controller!.groupId
                : widget.conversationId!,
            keyState:
                keySyncService.hasCachedScopeKey(
                  scope: widget.mode == ChatDetailMode.familyGroup
                      ? 'group'
                      : 'direct',
                  scopeId: widget.mode == ChatDetailMode.familyGroup
                      ? widget._controller!.groupId
                      : widget.conversationId!,
                )
                ? 'available'
                : 'waiting',
          ),
          if (widget.isAdmin)
            IconButton(
              tooltip: 'Family Invites',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AdminInvitesScreen()),
              ),
              icon: Icon(Icons.person_add_alt_1, color: palette.brand),
            ),
          IconButton(
            tooltip: 'Reset encryption',
            onPressed: _confirmResetEncryption,
            icon: Icon(Icons.lock_outline, size: 18, color: palette.brand),
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
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _syncStatus!,
                      style: TextStyle(
                        fontSize: 12,
                        color: palette.brandStrong,
                      ),
                    ),
                  ),
                  if (_keyMissingOnDevice)
                    TextButton(
                      onPressed: _confirmResetEncryption,
                      child: const Text('Reset'),
                    )
                  else if (widget.mode == ChatDetailMode.direct)
                    TextButton(
                      onPressed: _attachSupabaseSync,
                      child: const Text('Retry'),
                    ),
                ],
              ),
            ),
          Expanded(
            child: ListenableBuilder(
              listenable: Listenable.merge([_messages, _pending]),
              builder: (context, _) {
                final messages = [..._messages.value, ..._pending.value];
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
                if (!_initialScrollDone) {
                  _scheduleInitialScroll();
                }
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(VanamSpacing.md),
                  itemCount: messages.length + 1,
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      if (_loadingOlder) {
                        return const Padding(
                          padding: EdgeInsets.all(VanamSpacing.sm),
                          child: Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        );
                      }
                      if (_hasOlder) {
                        return Center(
                          child: TextButton(
                            onPressed: _loadOlder,
                            child: const Text('Load earlier messages'),
                          ),
                        );
                      }
                      return const SizedBox(height: VanamSpacing.sm);
                    }
                    final message = messages[i - 1];
                    return RepaintBoundary(
                      child: message.kind == ChatMessageKind.system
                          ? _SystemEventNotice(message: message)
                          : _MessageBubble(
                              message: message,
                              attachmentScope: _scope,
                              attachmentScopeId: _scopeId,
                              onRetry: message.failed
                                  ? () => _retry(message)
                                  : null,
                              onDiscard: message.failed
                                  ? () => _discard(message)
                                  : null,
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
            onAttach: _showAttachMenu,
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
  const _MessageBubble({
    required this.message,
    required this.showReadReceipt,
    required this.attachmentScope,
    required this.attachmentScopeId,
    this.onRetry,
    this.onDiscard,
  });

  /// Which chat's key decrypts this message's photo or document.
  final String attachmentScope;
  final String attachmentScopeId;

  /// Only set for a message that failed to send: tap retries, long-press
  /// discards.
  final VoidCallback? onRetry;
  final VoidCallback? onDiscard;

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
          GestureDetector(
            onTap: onRetry,
            onLongPress: onDiscard,
            child: ConstrainedBox(
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
                  border: message.isMine
                      ? null
                      : Border.all(color: palette.line),
                ),
                child: message.attachment != null
                    ? ChatAttachmentView(
                        attachment: message.attachment!,
                        scope: attachmentScope,
                        scopeId: attachmentScopeId,
                        textColor: textColor,
                      )
                    : Text(
                        message.text,
                        style: TextStyle(
                          color: message.isUnavailable && !message.isMine
                              ? palette.inkMuted
                              : textColor,
                          fontStyle: message.isUnavailable
                              ? FontStyle.italic
                              : FontStyle.normal,
                        ),
                      ),
              ),
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
                if (message.failed) ...[
                  Icon(Icons.error_outline, size: 13, color: palette.danger),
                  const SizedBox(width: 3),
                  Text(
                    'Not sent · tap to retry, hold to delete',
                    style: TextStyle(fontSize: 10, color: palette.danger),
                  ),
                ] else if (message.pending) ...[
                  const SizedBox(width: 3),
                  Icon(Icons.schedule, size: 13, color: palette.inkMuted),
                ] else if (showReadReceipt && message.isMine) ...[
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
    required this.onAttach,
    required this.hintText,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onAttach;
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
            IconButton(
              onPressed: onAttach,
              icon: Icon(Icons.attach_file, color: palette.inkMuted),
              tooltip: 'Attach photos or documents',
            ),
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
