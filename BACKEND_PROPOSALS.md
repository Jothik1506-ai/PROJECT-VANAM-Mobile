# Backend proposals (not applied)

## Recover stale encryption wraps without rotating a working chat key

Old ciphertext cannot be recovered if every participant has lost the private
key capable of opening the existing scope key. The backend must not pretend it
can recover that material, and the client must not automatically delete or
rotate other members' wraps.

For recoverable cases, add a `recipient_public_key` fingerprint to each
`key_wraps` row. Replace `list_missing_key_wraps` with an authorized RPC that
returns participants whose wrap is absent **or** whose stored fingerprint no
longer matches `profiles.public_key`. Change `upload_key_wrap` to update a wrap
only when the caller is an active participant and the submitted fingerprint
matches the target member's current public key. Revoke function execution from
`PUBLIC`/`anon` and grant only to `authenticated`.

The `list_missing_key_wraps` RPC must authorize the caller before returning
member IDs or public keys: for a group scope, require `auth.uid()` to be an
active member of that group; for a direct scope, require the caller to be a
participant in that conversation. Reject unknown scopes and unauthorized
callers inside the function even when RLS is enabled.

This lets any still-keyed participant automatically reseal for a reinstalled
member without deleting the stale row first. If no participant can decrypt the
scope key, the UI must continue to require the explicit confirmed reset because
preserving old ciphertext and inventing a new key are mutually exclusive.

## Provision new family members promptly

A database trigger cannot produce an E2EE key wrap because Postgres never has
the plaintext scope key. Instead, emit a Realtime-visible `key_reseal_requests`
row when a profile becomes active or changes `public_key`. Keyed clients should
subscribe to authorized requests for scopes they participate in, reseal the
existing key locally, upload the wrap through the hardened RPC above, and mark
the request complete. Apply RLS so request rows are visible only to active
participants of that scope and writable only by the requesting member or an
active participant completing it.

This removes the need for a keyed member to reopen the specific chat while
keeping all plaintext keys on participant devices. A server-side Edge Function
cannot safely perform the reseal without becoming a key escrow service.

## Direct-chat unread counts

Extend `list_direct_conversations()` with an `unread_count bigint` result
computed from `direct_messages` where the conversation matches, `sender_id` is
not `auth.uid()`, and `read_at is null`. Keep the existing participant check in
the function, revoke execution from `PUBLIC`/`anon`, and grant it only to
`authenticated`. The Flutter model already treats the field as optional and
defaults to zero, so deploying the RPC change will enable badges without a
coordinated app release.

## Chat attachments deploy

Chat photos and documents are sent as an encrypted message whose decrypted
body is `vanam:att:1:{...}` (a JSON pointer to the encrypted file in storage).
Older clients (1.0.1+29 and earlier) don't know this format and show that raw
`vanam:att:1:{...}` text instead of the photo or document.

Deploy in this exact order:

1. Apply `supabase/migrations/20261015090000_chat_attachments.sql` (storage
   bucket and policies the new app uploads to).
2. Release the new app build that sends and renders attachments.
3. Apply `supabase/migrations/20261015120000_chat_history_paging.sql`. It is
   now additive: it adds `list_messages_page` / `list_direct_messages_page`
   and only adds columns to `list_direct_conversations`, leaving
   `list_messages` / `list_direct_messages` untouched, so it is safe to apply
   at any time. Note: the new app calls the `*_page` functions to load chat
   history, so apply it no later than the moment the release goes live;
   applying it before step 2 is also fine and avoids any gap.
