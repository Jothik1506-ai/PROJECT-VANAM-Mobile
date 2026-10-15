# Photo & Document Uploads

Status: **written, not yet verified on a device** (no Flutter toolchain was
available when this was built). Run `flutter pub get`, `flutter analyze` and
`flutter test`, then test on a phone before releasing.

Two features are covered here:

1. Grouped photo posts on Home (Instagram-style)
2. Photo and document attachments in chats (WhatsApp-style)

---

## 1. Grouped photo posts (Home)

A Home post already supported up to 20 photos shown as a swipeable carousel.
The Create Post sheet is what changed.

- Chosen photos appear as a thumbnail strip, numbered 1, 2, 3...
- Each photo has its own ✕ button to remove it.
- A "+" tile adds more photos. Picks are **added** to the current selection
  instead of replacing it. Duplicates are ignored.
- "Remove all" clears the selection.
- A post is still either photos **or** one video, not both.
- Limit: 20 photos per post (`SupabaseHomeFeedRepository.maxPhotosPerPost`).

Code: `apps/mobile/lib/screens/home_screen.dart` (`_CreatePostSheetState`).

---

## 2. Chat attachments

Available in both the family group and direct chats.

### What members can do
- Tap the paperclip next to the message box and choose:
  - **Photos**: up to 10 at once from the gallery
  - **Camera**: take a photo
  - **Document**: PDF, Word, Excel, text, zip and other files, up to **15 MB**
- Photos show as a preview inside the chat bubble. Tap to open full screen
  with pinch-to-zoom.
- Documents show the file name and size. Tap to open in any app on the phone
  that can read that file type.
- A sending attachment appears immediately with a clock icon. If it fails,
  tap it to retry (the file is not re-uploaded if it already went up) or
  hold to delete.

### Security: attachments are end-to-end encrypted
- The file is encrypted **on the phone** with the chat's symmetric key
  (AES-256-GCM, the same key that protects that chat's messages) before it
  is uploaded. The server only ever stores ciphertext.
- The chat message that points at the file (name, type, size, storage path)
  is itself an encrypted chat message. Nothing about an attachment is
  readable by the server.
- Encryption and decryption run in a background isolate so large files do not
  freeze the app.
- Rule for contributors: never upload a plaintext file to this bucket.

### How it works
1. The sender picks a file and it is encrypted with the chat key.
2. The ciphertext is uploaded to the private `chat-attachments` bucket at
   - `group/<uploader id>/<random>` for the family group
   - `direct/<conversation id>/<random>` for a direct chat
3. A normal encrypted chat message is sent whose body is
   `vanam:att:1:` followed by a small JSON description (kind, name, type,
   size, path).
4. Receivers decrypt the message, see the marker, download the ciphertext,
   decrypt it with the chat key and show it. Decrypted photos are kept in a
   small in-memory cache (40 photos) for the session.

### Storage rules (`20261015090000_chat_attachments.sql`)
- Bucket `chat-attachments` is **private**, 20 MB object limit.
- Read: active members for `group/...`; conversation participants for
  `direct/<conversation>/...`.
- Upload: the same membership rules. Group files must be in the uploader's
  own folder.
- Delete: only the uploader (used to clean up a file whose message failed).

### Files
| File | Purpose |
|---|---|
| `supabase/migrations/20261015090000_chat_attachments.sql` | Bucket and access rules |
| `apps/mobile/lib/chat/chat_attachment.dart` | Attachment model, message format, 15 MB limit |
| `apps/mobile/lib/chat/attachment_service.dart` | Encrypt + upload, download + decrypt, cache |
| `apps/mobile/lib/chat/attachment_picker.dart` | Gallery, camera and document pickers |
| `apps/mobile/lib/crypto/e2ee_service.dart` | `encryptBytes` / `decryptBytes` for files |
| `apps/mobile/lib/widgets/chat_attachment_view.dart` | Photo preview, document row, full-screen viewer |
| `apps/mobile/lib/screens/chat_detail_screen.dart` | Paperclip menu, sending, retry |
| `apps/mobile/test/chat_attachment_test.dart` | Format and encryption round-trip tests |

### New dependency
`file_picker: ^8.1.2` (for choosing documents). It has not been built
against this project's Android setup yet. Run `flutter pub get` first.

---

## Release checklist

1. **Apply the migration** `20261015090000_chat_attachments.sql` on Supabase
   *before* shipping a build that can send attachments. Without it, sending
   an attachment fails.
2. `flutter pub get`, `flutter analyze`, `flutter test`.
3. Test on a real phone:
   - [ ] Send several photos in the family group and in a direct chat
   - [ ] Send a camera photo
   - [ ] Send a PDF and a Word or Excel file, then open each from the receiver
   - [ ] A file over 15 MB is rejected with a clear message
   - [ ] Turn off data mid-send: the message shows "Not sent", tap retries
   - [ ] Build a Home post with 5+ photos: remove one, add more, post
4. Bump the build number in `apps/mobile/pubspec.yaml` (currently
   `1.0.1+29`).
5. Update the OTA manifest if distributing the APK outside Play
   (`docs/OTA-RELEASES.md`).

## Known limitations
- Phones on an older build show an attachment message as raw text like
  `vanam:att:1:{...}` until they update.
- No captions on photos, and no video in chats.
- A Home post cannot mix photos and a video.
- After an encryption reset, attachments sent before the reset cannot be
  opened (same as older messages).
- Message previews and push notification text do not describe attachments
  yet. `ChatAttachment.previewLabel` exists for this.
