# Chat Improvements — Oct 2026

Status: **written, not yet verified on a device** (no Flutter toolchain was
available when this was built). Run `flutter pub get`, `flutter analyze` and
`flutter test`, then test on a phone before releasing.

This round closes gaps left by the attachments work (`docs/ATTACHMENTS.md`)
and fixes one serious bug found while reading the message RPCs.

---

## 1. Bug fix: chats stopped showing new messages after 100

**What was wrong.** `list_messages` and `list_direct_messages` sorted
messages oldest-first and then took the first 100. Once a chat had more than
100 messages, the app only ever received the *oldest* 100, so anything newer
never appeared on screen. The family group is the first chat that will hit
this.

**Fix.** Both RPCs now return the **newest** page (sorted newest-first on the
server, re-sorted oldest-first on the phone) and accept `p_before` to fetch
the page before a given time.

Migration: `supabase/migrations/20261015120000_chat_history_paging.sql`.

## 2. New: load earlier messages

- Scrolling to the top of a chat (or tapping **Load earlier messages**)
  fetches the previous 100 messages and inserts them above, keeping your
  scroll position.
- Works in the family group and in direct chats.
- When the start of the chat is reached, the button disappears.
- A realtime refresh (a new message arriving) no longer throws away the older
  pages you scrolled back to.

## 3. New: real previews in the Messages list

The direct-chat list used to show "Encrypted message" for every chat. It now
shows:

- the decrypted last message, e.g. `sure, 6pm`
- `📷 Photo` or `📎 filename.pdf` for attachments
- a `You: ` prefix when you sent it
- the **unread count** badge is now a real count of the other person's
  unread messages (the field existed in the app but the server never
  filled it)

Decryption happens on the phone with the chat key, the same way the chat
screen does it. The server still only ever has ciphertext. If the key is not
on this phone yet, the row falls back to "Encrypted message".

---

## Files

| File | Change |
|---|---|
| `supabase/migrations/20261015120000_chat_history_paging.sql` | Newest-first paging with `p_before`; `list_direct_conversations` returns encrypted last body, its sender, and `unread_count` |
| `apps/mobile/lib/chat/supabase_chat_sync.dart` | `fetchMessages(before:)`, `pageSize` |
| `apps/mobile/lib/chat/supabase_direct_chat_sync.dart` | `fetchMessages(before:)`, `pageSize`, `decryptPreview()` |
| `apps/mobile/lib/chat/chat_controller.dart` | `loadOlder()`, `hasOlder`; refresh keeps older pages |
| `apps/mobile/lib/chat/direct_conversation.dart` | `lastMessageSenderId` |
| `apps/mobile/lib/screens/chat_detail_screen.dart` | Scroll-to-top loading, "Load earlier messages" row, page merging |
| `apps/mobile/lib/widgets/direct_conversation_tile.dart` | Decrypted preview, attachment labels, "You:" prefix |

---

## Release checklist

1. **Apply the migration** `20261015120000_chat_history_paging.sql` on
   Supabase before shipping this build. The RPC signatures change
   (`p_before` added, `list_direct_conversations` gains two columns).
   Older app builds keep working: they don't pass `p_before` and ignore the
   extra columns.
2. If not applied yet, also apply `20261015090000_chat_attachments.sql`.
3. `flutter pub get`, `flutter analyze`, `flutter test`.
4. Device check:
   - [ ] A chat with 100+ messages shows the newest ones on open
   - [ ] Scroll to the top: earlier messages load and the view does not jump
   - [ ] Reach the start of a chat: the button disappears
   - [ ] Messages list shows the real last message, "You:" when yours,
         `📷 Photo` for a photo, and the correct unread badge
   - [ ] Receive a message while scrolled back: it appears at the bottom and
         the older pages stay
5. Bump the build number (`apps/mobile/pubspec.yaml`, currently `1.0.1+29`).

## Still open

- Push notification text still says "Open Vanam to read it." — the server
  cannot read messages, so a richer preview would need the phone to render
  the notification itself.
- Video in chats, photo captions, and mixing photos + video in one Home post.
- Message search (contents are encrypted; only names are searchable).
