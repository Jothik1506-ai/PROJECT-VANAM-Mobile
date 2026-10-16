-- Chat attachments (photos and documents) for the family group and direct chats.
--
-- Files are END-TO-END ENCRYPTED on the phone with the chat's symmetric key
-- before upload, so this bucket only ever holds ciphertext. The message that
-- points at a file (name, type, size, storage path) is itself an encrypted
-- chat message — nothing about an attachment is readable by the server.
--
-- Object path layout (enforced by the policies below):
--   group/<uploader uuid>/<random>           family group files
--   direct/<conversation uuid>/<random>      direct chat files
--
-- Apply this BEFORE shipping an app build that can send attachments.

insert into storage.buckets (id, name, public, file_size_limit)
values ('chat-attachments', 'chat-attachments', false, 20971520) -- 20 MB
on conflict (id) do update
  set public = false,
      file_size_limit = excluded.file_size_limit;

-- Read: active members for group files; conversation participants for direct.
drop policy if exists chat_attachments_select on storage.objects;
create policy chat_attachments_select on storage.objects
  for select to authenticated
  using (
    bucket_id = 'chat-attachments'
    and (
      ((storage.foldername(name))[1] = 'group' and public.is_active_member())
      or (
        (storage.foldername(name))[1] = 'direct'
        and (storage.foldername(name))[2] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        and public.is_conversation_participant(((storage.foldername(name))[2])::uuid)
      )
    )
  );

-- Upload: same membership rules; group files must live under the uploader's
-- own folder.
drop policy if exists chat_attachments_insert on storage.objects;
create policy chat_attachments_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'chat-attachments'
    and (
      (
        (storage.foldername(name))[1] = 'group'
        and (storage.foldername(name))[2] = auth.uid()::text
        and public.is_active_member()
      )
      or (
        (storage.foldername(name))[1] = 'direct'
        and (storage.foldername(name))[2] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        and public.is_conversation_participant(((storage.foldername(name))[2])::uuid)
      )
    )
  );

-- Delete: only the uploader (used to clean up a file whose message failed).
drop policy if exists chat_attachments_delete on storage.objects;
create policy chat_attachments_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'chat-attachments' and owner = auth.uid());
