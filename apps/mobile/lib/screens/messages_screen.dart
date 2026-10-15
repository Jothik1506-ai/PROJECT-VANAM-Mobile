import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../chat/direct_conversation.dart';
import '../chat/chat_controller.dart';
import '../chat/chat_message.dart';
import '../chat/supabase_direct_chat_sync.dart';
import '../models/conversation.dart';
import '../theme/tokens.dart';
import '../widgets/feedback_button.dart';
import '../widgets/conversation_tile.dart';
import '../widgets/direct_conversation_tile.dart';

/// Messages list: the one real Family Group thread, plus every real
/// direct/personal chat this member is a participant in (see
/// supabase/migrations/20260819070000_direct_chat_messages.sql). Direct
/// conversations are created automatically — one per pair of active
/// members — the first time a member sets their own display name (see
/// set_own_display_name in the join-flow migrations).
class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key, this.isAdmin = false});

  final bool isAdmin;

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  late Future<List<DirectConversation>> _directConversationsFuture;
  final _searchController = TextEditingController();
  bool _searching = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _directConversationsFuture = _loadDirectConversations();
  }

  Future<List<DirectConversation>> _loadDirectConversations() async {
    final client = Supabase.instance.client;
    if (client.auth.currentUser == null) return const [];
    return SupabaseDirectChatSync(client).listConversations();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _query = '';
        _searchController.clear();
      }
    });
  }

  bool _matches(String name) {
    final q = _query.trim().toLowerCase();
    return q.isEmpty || name.toLowerCase().contains(q);
  }

  Future<void> _refresh() async {
    setState(() {
      _directConversationsFuture = _loadDirectConversations();
    });
    await _directConversationsFuture;
  }

  Conversation _familyConversation(Conversation fallback) {
    for (final message in familyGroupChat.value.reversed) {
      if (message.kind == ChatMessageKind.user && !message.isUnavailable) {
        return Conversation(
          name: fallback.name,
          lastMessage: message.text,
          timeLabel: '',
          status: message.text,
        );
      }
    }
    return fallback;
  }

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
                    child: _searching
                        ? TextField(
                            controller: _searchController,
                            autofocus: true,
                            textInputAction: TextInputAction.search,
                            onChanged: (value) =>
                                setState(() => _query = value),
                            decoration: const InputDecoration(
                              hintText: 'Search chats by name',
                              prefixIcon: Icon(Icons.search),
                            ),
                          )
                        : Text(
                            'Messages',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                              color: palette.ink,
                            ),
                          ),
                  ),
                  const SizedBox(width: VanamSpacing.sm),
                  InkResponse(
                    onTap: _toggleSearch,
                    radius: 24,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: palette.surfaceCard,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: palette.shadow, blurRadius: 6),
                        ],
                      ),
                      child: Icon(
                        _searching ? Icons.close : Icons.search,
                        color: palette.ink,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: VanamSpacing.xs),
                  const FeedbackIconButton(screen: 'Messages'),
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
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: FutureBuilder<List<DirectConversation>>(
                  future: _directConversationsFuture,
                  builder: (context, snapshot) {
                    final allDirect = snapshot.data ?? const [];
                    final directConversations = [
                      for (final c in allDirect)
                        if (_matches(c.otherDisplayName)) c,
                    ];
                    final groupTiles = [
                      for (final c in mockConversations)
                        if (_matches(c.name)) c,
                    ];
                    final noResults =
                        _query.trim().isNotEmpty &&
                        groupTiles.isEmpty &&
                        directConversations.isEmpty &&
                        snapshot.connectionState != ConnectionState.waiting;
                    final isLoading =
                        snapshot.connectionState == ConnectionState.waiting;

                    return ListView(
                      children: [
                        for (final conversation in groupTiles)
                          RepaintBoundary(
                            child: AnimatedBuilder(
                              animation: familyGroupChat,
                              builder: (context, _) => ConversationTile(
                                conversation: _familyConversation(conversation),
                                isAdmin: widget.isAdmin,
                                onReturn: _refresh,
                              ),
                            ),
                          ),
                        Divider(
                          height: 1,
                          indent: VanamSpacing.md,
                          endIndent: VanamSpacing.md,
                          color: palette.line,
                        ),
                        if (isLoading)
                          const Padding(
                            padding: EdgeInsets.all(VanamSpacing.lg),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else if (snapshot.hasError)
                          Padding(
                            padding: const EdgeInsets.all(VanamSpacing.lg),
                            child: Text(
                              'Could not load direct chats. Pull down to retry.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: palette.inkMuted),
                            ),
                          )
                        else if (noResults)
                          Padding(
                            padding: const EdgeInsets.all(VanamSpacing.lg),
                            child: Text(
                              'No chats match "${_query.trim()}".',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: palette.inkMuted),
                            ),
                          )
                        else if (_query.trim().isNotEmpty &&
                            directConversations.isEmpty)
                          const SizedBox.shrink()
                        else if (directConversations.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(VanamSpacing.lg),
                            child: Text(
                              'No direct chats yet. They appear here '
                              'automatically once other family members join.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: palette.inkMuted),
                            ),
                          )
                        else
                          for (final conversation in directConversations)
                            RepaintBoundary(
                              child: DirectConversationTile(
                                conversation: conversation,
                                onReturn: _refresh,
                              ),
                            ),
                      ],
                    );
                  },
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
              'Your chats are end-to-end encrypted. Only family members can read them.',
              style: TextStyle(color: palette.brandStrong, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
