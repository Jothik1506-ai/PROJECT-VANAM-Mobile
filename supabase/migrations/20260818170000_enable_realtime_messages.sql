-- The messages table was never added to Supabase's Realtime publication,
-- so postgres_changes events never fired — the app's Realtime subscription
-- in supabase_chat_sync.dart was listening correctly, but no INSERT event
-- was ever actually broadcast. New messages only appeared after a manual
-- refetch (leaving and reopening the chat screen), never live. Adding the
-- table to the publication is what actually turns on the broadcast.

alter publication supabase_realtime add table public.messages;
